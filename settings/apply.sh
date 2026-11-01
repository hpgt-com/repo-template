#!/usr/bin/env bash
# Setter innstillingene som ikke kan ligge i et repo. Kjøres lokalt av en org-eier med `gh auth login`.
#
#   ./apply.sh org   <org>                       org-innstillinger (Actions-policy, base permission, ...)
#   ./apply.sh repo  <org>/<repo> [--checks a,b] repo-innstillinger, sikkerhet og rulesettet «Main protection»
#   ./apply.sh audit <org>/<repo>                viser hva som står på, uten å endre noe
#
# Trygt å kjøre flere ganger: rulesettet oppdateres hvis det finnes fra før.
set -euo pipefail
cd "$(dirname "$0")"

die() { echo "feil: $*" >&2; exit 1; }
ok()  { echo "  ✓ $*"; }

cmd_org() {
  local org=$1
  echo "== Org $org"
  # Medlemmer får bare lesetilgang som standard; skrivetilgang gis per repo eller team.
  # Medlemmer kan ikke lage repo (eiere kan alltid). «Bare private» krever Enterprise Cloud, så på Free er det
  # alt eller ingenting.
  gh api -X PATCH "orgs/$org" --silent \
    -f default_repository_permission=read \
    -F members_can_create_repositories=false \
    -F members_can_fork_private_repositories=false
  ok "base permission = read, medlemmer kan ikke lage repo"

  # Actions: alle actions tillatt, men de MÅ være pinnet til full commit-SHA.
  gh api -X PUT "orgs/$org/actions/permissions" --silent \
    -f enabled_repositories=all -f allowed_actions=all -F sha_pinning_required=true
  ok "Actions: krever SHA-pinning"

  # GITHUB_TOKEN er read-only som standard, og workflows kan ikke godkjenne PR-er.
  gh api -X PUT "orgs/$org/actions/permissions/workflow" --silent \
    -f default_workflow_permissions=read -F can_approve_pull_request_reviews=false
  ok "Actions: GITHUB_TOKEN read-only, kan ikke godkjenne PR-er"

  # Sikkerhetsoppsettet «GitHub recommended» (dependency graph, Dependabot, secret scanning, push protection,
  # private vulnerability reporting) på alle offentlige repo, og som standard for nye offentlige repo.
  # Private repo får de gratis delene via `apply.sh repo`; resten krever betalte lisenser.
  local cfg; cfg=$(gh api "orgs/$org/code-security/configurations" \
    --jq '.[] | select(.target_type=="global" and .name=="GitHub recommended") | .id' | head -1)
  [[ -n $cfg ]] || die "fant ikke «GitHub recommended» i orgs/$org/code-security/configurations"
  gh api -X POST "orgs/$org/code-security/configurations/$cfg/attach" --silent -f scope=public
  gh api -X PUT "orgs/$org/code-security/configurations/$cfg/defaults" --silent -f default_for_new_repos=public
  ok "«GitHub recommended» på alle offentlige repo og som standard for nye"

  # Tofaktor kan ikke slås på via API-et, bare leses. Skriptet sjekker og viser hvem som mangler det.
  if [[ $(gh api "orgs/$org" --jq .two_factor_requirement_enabled) == true ]]; then
    ok "tofaktor er påkrevd"
  else
    echo "  ! tofaktor er IKKE påkrevd. Slå på i nettleseren:"
    echo "    https://github.com/organizations/$org/settings/security → Require two-factor authentication"
    echo "    Medlemmer uten tofaktor blir fjernet når du slår det på. Disse mangler det nå:"
    gh api "orgs/$org/members?filter=2fa_disabled" --paginate --jq '.[].login' | sed 's/^/      /'
  fi
}

cmd_repo() {
  local full=$1; shift
  local checks="dependency-review,workflow-security"
  while [[ $# -gt 0 ]]; do
    case $1 in
      --checks) checks="$checks,$2"; shift 2 ;;
      *) die "ukjent valg $1" ;;
    esac
  done
  [[ $full == */* ]] || die "bruk <org>/<repo>"
  echo "== Repo $full"

  local vis; vis=$(gh api "repos/$full" --jq .visibility)

  # Alle merge-metoder tillatt (som flying-sites). Slett branch etter merge.
  gh api -X PATCH "repos/$full" --silent \
    -F delete_branch_on_merge=true -F allow_update_branch=true \
    -F has_wiki=false -F has_projects=false
  ok "slett branch etter merge, wiki/projects av"

  gh api -X PUT "repos/$full/vulnerability-alerts" --silent;      ok "Dependabot alerts"
  gh api -X PUT "repos/$full/automated-security-fixes" --silent;  ok "Dependabot security updates"
  gh api -X PUT "repos/$full/private-vulnerability-reporting" --silent; ok "Private vulnerability reporting"

  # Secret scanning er gratis for offentlige repo; private repo krever GitHub Secret Protection.
  if [[ $vis == public ]]; then
    gh api -X PATCH "repos/$full" --silent --input - <<JSON
{"security_and_analysis":{"secret_scanning":{"status":"enabled"},"secret_scanning_push_protection":{"status":"enabled"}}}
JSON
    ok "Secret scanning + push protection"
  else
    echo "  ! privat repo: secret scanning krever GitHub Secret Protection, hoppet over"
  fi

  gh api -X PUT "repos/$full/actions/permissions/workflow" --silent \
    -f default_workflow_permissions=read -F can_approve_pull_request_reviews=false
  ok "Actions: GITHUB_TOKEN read-only"

  # Rulesettet, med de påkrevde sjekkene.
  local body; body=$(python3 - "$checks" <<'PY'
import json, sys
r = json.load(open("ruleset-main.json"))
names = list(dict.fromkeys(c for c in sys.argv[1].split(",") if c))
for rule in r["rules"]:
    if rule["type"] == "required_status_checks":
        rule["parameters"]["required_status_checks"] = [{"context": n, "integration_id": 15368} for n in names]
print(json.dumps(r))
PY
)
  local id; id=$(gh api "repos/$full/rulesets" --jq '.[] | select(.name | ascii_downcase == "main protection") | .id' | head -1)
  if [[ -n $id ]]; then
    gh api -X PUT "repos/$full/rulesets/$id" --silent --input - <<<"$body"; ok "ruleset oppdatert ($checks)"
  else
    gh api -X POST "repos/$full/rulesets" --silent --input - <<<"$body";    ok "ruleset opprettet ($checks)"
  fi
}

cmd_audit() {
  local full=$1
  echo "== $full"
  gh api "repos/$full" --jq '"  synlighet: \(.visibility)\n  merge: squash=\(.allow_squash_merge) merge=\(.allow_merge_commit) rebase=\(.allow_rebase_merge) slett-branch=\(.delete_branch_on_merge)\n  secret scanning: \(.security_and_analysis.secret_scanning.status) / push protection: \(.security_and_analysis.secret_scanning_push_protection.status)\n  dependabot security updates: \(.security_and_analysis.dependabot_security_updates.status)"'
  gh api "repos/$full/private-vulnerability-reporting" --jq '"  private vulnerability reporting: \(.enabled)"'
  gh api "repos/$full/vulnerability-alerts" --silent 2>/dev/null && echo "  dependabot alerts: på" || echo "  dependabot alerts: AV"
  gh api "repos/$full/rulesets" --jq '"  rulesets: \([.[].name] | join(", "))"'
  for f in SECURITY.md .github/CODEOWNERS .github/dependabot.yml .github/workflows/security.yml .github/workflows/code-scanning.yml; do
    gh api "repos/$full/contents/$f" --silent 2>/dev/null && echo "  ✓ $f" || echo "  ✗ $f mangler"
  done
}

case ${1:-} in
  org)   [[ $# -eq 2 ]] || die "bruk: $0 org <org>"; cmd_org "$2" ;;
  repo)  [[ $# -ge 2 ]] || die "bruk: $0 repo <org>/<repo> [--checks a,b]"; shift; cmd_repo "$@" ;;
  audit) [[ $# -eq 2 ]] || die "bruk: $0 audit <org>/<repo>"; cmd_audit "$2" ;;
  *) sed -n '2,9p' "$0"; exit 1 ;;
esac

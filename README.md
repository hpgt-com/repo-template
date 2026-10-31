# <repo-navn>

<!-- Én setning: hva repoet er, og for hvem. -->

## Kom i gang

<!-- Hvordan installere, bygge og teste lokalt. -->

## Etter at repoet er laget fra malen

- [ ] Fyll inn denne README-en og `description` på repoet.
- [ ] `.github/workflows/code-scanning.yml`: legg til språkene repoet bruker.
- [ ] `.github/dependabot.yml`: slå på økosystemene repoet bruker.
- [ ] Privat repo: slett `.github/workflows/scorecard.yml`.
- [ ] Kjør `settings/apply.sh repo <navn>` fra `hpgt-com/repo-template` (rulesett og sikkerhetsinnstillinger;
      innstillinger følger ikke med når et repo lages fra en mal).
- [ ] Legg til en `build`/`test`-jobb og legg den til som påkrevd sjekk (`--checks`).

## Sikkerhet

Se [SECURITY.md](SECURITY.md).

# Bidra

- Alle endringer går via en pull request mot `main`. Direkte push til `main` er blokkert.
- Hold PR-en liten og om én ting. Beskriv hva som er endret og hvorfor.
- Sjekkene må være grønne før merge (bygg/test, `dependency-review`, `workflow-security`, CodeQL).
- Aldri legg hemmeligheter (API-nøkler, passord, private nøkler) i koden. Secret scanning med push protection stopper
  de fleste, men ikke alle. Har du lekket en nøkkel: roter den med en gang, og si fra.
- Nye avhengigheter: velg vedlikeholdte pakker, og vurder om du trenger dem i det hele tatt.
- Sikkerhetsfeil rapporteres via «Report a vulnerability», se SECURITY.md.

# Start-Prompt (nur Lesen) - MacBook und QNAP

Zweck: Eine KI-Sitzung (oder du selbst) liest das Repo mit **Lesezugriff** und fuehrt nur **lesende** Pruefungen aus. Es wird nichts installiert, geschrieben, gepusht oder konfiguriert.

## Vorbereitung

- Repo nur lesend nutzen: `git clone --depth 1 https://github.com/KonradLanz/bootstrap-foundation.git` (oder bestehenden Klon mit `git fetch` aktualisieren; kein `push`).
- Branch: `plan/stalwart-parallel-to-kolab16`.
- Keine Tokens/Passwoerter in den Prompt einfuegen.

## Prompt (kopieren)

```text
Du arbeitest NUR LESEND. Regeln:
- Keine Installation, keine Konfigurationsaenderung, kein git push/commit, kein sudo mit Schreibzugriff.
- Keine Passwoerter, Tokens oder Schluessel ausgeben; bei Treffern nur Dateiname und Zeile nennen.
- Wenn ein Befehl etwas aendern wuerde: nicht ausfuehren, sondern vorschlagen.

Kontext:
Repo KonradLanz/bootstrap-foundation, Branch plan/stalwart-parallel-to-kolab16.
Lies services/stalwart/PLAN.md, README.md, services/README.md, services/forgejo/, qnap/vaultwarden/ und CREDENTIAL-BACKENDS.md.
Ziel: Stalwart parallel zu Kolab 16 auf einer Subdomain, spaeter Umstellung auf die Hauptdomain.

Aufgaben:
1. Phase 0: Vergleiche den lokalen Stand (git log, git status, git diff origin/main --stat) mit GitHub main. Fasse die Abweichungen kurz zusammen (Dateien, Art der Aenderung). Nichts zurueckfuehren.
2. Phase 1 (nur auf dem QNAP-Host ausfuehren, falls dort gestartet): Gib aus
   - uname -a, cat /etc/config/uLinux.conf (nur Modell/Firmware, keine Secrets)
   - freie/belegte Ports: netstat -tlnp oder ss -tlnp (Ports 25, 80, 443, 465, 587, 993, 8080, 8443)
   - Container Station: docker version, docker ps (ohne Env-Variablen)
   - Volumes: df -h
   - RAM: free -m
3. Nenne Konflikte zwischen den belegten Ports und den Stalwart-Ports (25, 465, 587, 993, Web-Admin/HTTPS).
4. Schlage vor: Docker in Container Station oder Ubuntu-VM, mit Begruendung.
5. Liste Luecken im PLAN.md und welche Fragen offen bleiben.

Ausgabeformat: Markdown mit Abschnitten 'Repo-Abgleich', 'QNAP-Inventar', 'Portkonflikte', 'Empfehlung', 'Offene Fragen'.
Ende: Frage nach Freigabe fuer den naechsten Schritt (Entwurf services/stalwart/bootstrap.sh). Nicht ohne Freigabe fortfahren.
```

## Hinweise

- MacBook: Phase 0 und Planlesen. QNAP: Phase 1.
- Ausgaben vor dem Teilen auf Secrets pruefen.
- Ergebnisse als Notiz im Repo ablegen (ohne Secrets), erst nach deiner Freigabe.

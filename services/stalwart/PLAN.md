# Stalwart parallel zu Kolab 16 - Plan

Status: ENTWURF (nur Plan, kein Code). Branch: `plan/stalwart-parallel-to-kolab16`.

## Ziel

Stalwart (IMAP, SMTP, CalDAV, CardDAV, WebDAV) parallel zu Kolab 16 betreiben, bis es fuer Familie und Familienbetrieb stabil ist. Danach Mails und Kontakte migrieren und Stalwart auf die Hauptdomain umstellen. Kolab 16 wird dabei nicht veraendert.

## Rahmen und Annahmen

- Hardware: QNAP TVS-673 (x86, AMD RX-421BD, 24 GB RAM), QTS 5.2.9.3499.
- Clients: Thunderbird, iOS, Android (DAVx5), gelegentlich Outlook (wegen Kalendereinladungen).
- Benutzer: wenige, aber sehr viele Mails und Kontakte; geteilte Kalender noetig.
- Hauptdomain heute: `own.dedyn.io` (Kolab 16). Testdomain: `mail2.own.dedyn.io` (Name ist ein Vorschlag).
- Nachbarn im Repo: Forgejo, Vaultwarden (HAProxy-Muster unter `qnap/vaultwarden/`).
- Lokale Forgejo-Version weicht von GitHub ab: GitHub ist fuer diesen Plan die Referenz (read-only). Abgleich siehe Phase 0.

## Prinzipien

1. Kolab 16 bleibt unveraendert und produktiv.
2. Version von Stalwart wird fixiert (kein `latest`).
3. Jeder Schritt idempotent, mit Backup vorher.
4. Secrets nie ins Repo; Ablage ueber `CREDENTIAL-BACKENDS.md`.
5. Erst Subdomain, dann Hauptdomain; Rueckweg bleibt bis zum Ende offen.

## Phase 0 - Repo-Abgleich (MacBook)

- GitHub-Stand lesen (read-only), lokalen Forgejo-Stand vergleichen.
- Entscheidung: GitHub-`main` als Basis oder Forgejo-Aenderungen zuerst zurueckfuehren.
- Ergebnis: kurze Diff-Zusammenfassung, noch kein Push.

## Phase 1 - Inventar (QNAP + Kolab-Server, read-only)

- QNAP: Container Station Version, freie Ports, belegte Ports (25, 465, 587, 993, 443, 8080), Volumes (SSD/HDD), RAM.
- Netzwerk: zweite IP/VLAN fuer Stalwart moeglich? Port-Weiterleitung am Router/pfSense (`pfsense/` im Repo).
- Kolab: Anzahl Benutzer, Postfachgroessen, Anzahl Kontakte/Kalender, geteilte Ordner, Sieve-Regeln, Gruppen.
- Ausgabe: Inventar als Markdown, ohne Passwoerter.

## Phase 2 - Subdomain-Bootstrap (`services/stalwart/`)

- Variante A: Docker in Container Station (Compose, fixierte Image-Version, Volume mit passender UID).
- Variante B: Ubuntu-VM in Virtualization Station mit Binary + systemd.
- Entscheidung nach Phase 1 (Portkonflikte entscheiden).
- Bootstrap nach Muster von `services/forgejo/` (Umgebungsvariablen wie `STALWART_DOMAIN`, `STALWART_VERSION`), Reverse Proxy wie bei Vaultwarden (HAProxy) oder Caddy.
- DNS fuer die Subdomain: A/AAAA, MX nur fuer die Subdomain, SPF, DKIM, DMARC, PTR (Reverse-DNS beim Provider pruefen).
- TLS: Zertifikat fuer die Subdomain; Uebernahme des bestehenden Certificate-Deploy-Musters pruefen.

## Phase 3 - Pilot

- Testbenutzer + Testdomain, ein Familienmitglied als Pilot.
- Tests: IMAP/SMTP-Submission, CalDAV/CardDAV mit Thunderbird, iOS, DAVx5.
- Geteilte Kalender (WebDAV-ACL) und Outlook-Einladungen (iMIP) mit echten Einladungen pruefen.
- Update-Test: Version anheben auf einer Kopie, Freigaben danach erneut pruefen.
- Abbruchkriterien festlegen (z. B. Freigaben unzuverlaessig, Zustellprobleme).

## Phase 4 - Datenmigration (Kopie, kein Umschalten)

- Mails: `imapsync` von Kolab nach Stalwart, Kolab-Spezialordner (Kalender, Kontakte, Aufgaben, Notizen) ausschliessen; mehrfach wiederholen (delta).
- Kontakte/Kalender: Export aus Kolab (vCard/iCal), Import in Stalwart, Gruppen und Verteilerlisten gesondert pruefen.
- Vergleich: Anzahl Mails pro Ordner, Anzahl Kontakte, Stichproben.
- Backups vor und nach jedem Lauf; Restore-Test.

## Phase 5 - Parallelbetrieb

- Familie nutzt Subdomain-Konten aktiv, Kolab bleibt Hauptsystem.
- Beobachtungszeit (Vorschlag: mindestens 4 Wochen) mit Checkliste: Zustellung, Spam, Kalender, Mobilgeraete, Performance, Backups.

## Phase 6 - Umstellung auf die Hauptdomain (Cutover)

Vorbereitung:
- TTL der DNS-Eintraege Tage vorher senken.
- Stalwart als Mailserver fuer `own.dedyn.io` konfigurieren, aber MX noch nicht umstellen.
- Autodiscover/Autoconfig/SRV-Eintraege vorbereiten.
- Letzter Voll-Backup von Kolab.

Cutover-Tag:
1. Kolab Annahme stoppen oder MX umstellen (Reihenfolge festlegen, Mailverlust vermeiden: Kolab behaelt Queue).
2. Delta-`imapsync` und finaler Kontakt-/Kalenderabgleich.
3. DNS: MX, A/AAAA, SPF, DKIM (neuer Selektor), DMARC, Autodiscover.
4. Port-Weiterleitungen am Router/pfSense auf Stalwart.
5. Clients umstellen (Server-Namen, ggf. Konten neu anlegen).
6. Zustellung testen: intern, extern, Outlook-Einladung, Mobilgeraete.

Nach dem Cutover:
- Kolab mindestens einige Wochen read-only als Fallback behalten.
- Rollback: MX/A zurueck auf Kolab, Delta zurueckspielen (Verfahren vorab testen).
- Erst danach Kolab ausser Betrieb nehmen (Backup archivieren).

## Offene Fragen

- Docker (Container Station) oder VM? Entscheidung nach Portinventar.
- Webmail noetig? (Stalwart liefert keines; z. B. Roundcube/SnappyMail als eigener Service.)
- Familie und Familienbetrieb: eine Domain oder zwei?
- Welche Enterprise-Funktionen werden gebraucht (Mehrfachdomains, Gruppen)? Lizenz pruefen: Community AGPL-3.0, Enterprise proprietaer.
- Wie werden Stalwart-Updates ohne Bruch der Freigaben getestet?

## Risiken

- Junge Kalender/Kontakt-Funktionen; Freigaben koennen sich zwischen Versionen aendern.
- Firmengefuehrtes Projekt, Lizenzmodell kann sich aendern.
- Zustellbarkeit (Reverse-DNS, Reputation der IP) haengt am Anschluss, nicht am NAS.
- NAS-Firmwareupdates koennen Container Station beeinflussen.

## Naechste Schritte

1. Start-Prompt (`START-PROMPT.md`) auf MacBook und QNAP ausfuehren (nur lesen).
2. Ergebnis von Phase 0 und 1 in dieses Repo als Notiz committen (ohne Secrets).
3. Entscheidung Docker oder VM, dann `services/stalwart/bootstrap.sh` entwerfen.

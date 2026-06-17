# bootstrap-foundation — TODO

---

## Gitea / Forgejo auf QNAP

**Status:** Bootstrap-Scripts vorhanden (`qnap/gitea/`, `qnap/forgejo/`), noch nicht live deployed

- [ ] Forgejo auf QNAP deployen: `sh qnap/forgejo/bootstrap-forgejo.sh --postgres --haproxy forgejo.own.dedyn.io`
- [ ] Post-Setup: `sh qnap/forgejo/setup-forgejo.sh --disable-register`
- [ ] Gitea: entscheiden ob Forgejo-only oder beide (Forgejo bevorzugt)
- [ ] Shared PostgreSQL-Container deployen: `bootstrap-postgres.sh` (Voraussetzung fuer `--postgres`)
- [ ] Services README aktualisieren sobald live

---

## Vaultwarden auf QNAP

**Status:** Bootstrap-Scripts neu erstellt (`qnap/vaultwarden/`), noch nicht deployed  
**Zweck:** Self-hosted Bitwarden-Server fuer hoKI-Secrets-Integration (email-analyser, local-ai-stack)

- [ ] Vaultwarden deployen: `sh qnap/vaultwarden/bootstrap-vaultwarden.sh --haproxy vault.own.dedyn.io`
- [ ] Erster Account anlegen, dann signups sperren: `sh qnap/vaultwarden/setup-vaultwarden.sh --disable-signups --setup-backup`
- [ ] Bitwarden Browser-Extension + Mobile App auf `https://vault.own.dedyn.io` konfigurieren
- [ ] `email-analyser`: IMAP/SMTP-Credentials in Vaultwarden ablegen, `.env` durch `bw get`-Aufrufe ersetzen
- [ ] `local-ai-stack`: API-Keys (falls externe Dienste) analog migrieren
- [ ] README.md der betroffenen Projekte mit bw-CLI-Snippet aktualisieren
- [ ] In `services/README.md` Vaultwarden-Eintrag ergaenzen (analog Forgejo)

---

## MCP Tool: macOS System Settings

**Status:** Idee, noch nicht gebaut  
**Kontext:** Das MCP-Tool für den Repo-Verzeichniszugriff (`LOCAL_MCP`) ist aktiv.
Ein separates MCP-Tool das macOS `defaults` direkt lesen/schreiben kann existiert noch nicht.

### Was es tun soll

- `defaults read <domain>` als MCP-Action exponieren (read-only)
- `defaults write <domain> <key> <value>` mit Approval-Gate
- Diff-Ansicht: aktuellen Zustand vs. letztem Snapshot aus `system-settings-tracker/`
- Integration in AI-Assistenten: "Zeig mir alle controlcenter-Keys" direkt aus dem Chat
- Optional: LaunchAgent-Status (is tracker running?)

### Referenz-Implementierung

- Vorbild: `macos/system-settings-tracker/track.sh` (liest bereits alle relevanten Domains)
- Analog zu: ETSI-MCP-Tool (anderes Projekt, gleiche MCP-Server-Architektur)
- Sicherheitsmodell: raw plist lokal bleiben (`~/.local/system-settings-keeper/`),
  MCP exponiert nur Diffs und Key-Listen — keine vollständigen Exports

### Nächste Schritte

1. MCP-Server-Boilerplate aus ETSI-Projekt als Vorlage nehmen
2. Actions definieren: `read_domain`, `list_keys`, `write_key`, `get_diff`
3. Approval-Pflicht für alle write-Actions (`_requires_user_approval: true`)
4. In bootstrap.sh als optionalen MCP-Service registrieren

---

## Notch Flanken — Offene Punkte

- [ ] Testen ob `NSStatusItemSpacing=6` nach nächstem macOS-Update erhalten bleibt
- [ ] BentoBox-Einstellung "Immer anzeigen" für kritische Icons setzen
      (macht `apply.sh` dauerhaft obsolet)
- [ ] `system-settings-tracker` LaunchAgent installieren:
      `bash ~/git/bootstrap-foundation/macos/system-settings-tracker/install-launchd.sh`
- [ ] Ersten Snapshot manuell triggern (Baseline):
      `bash ~/git/bootstrap-foundation/macos/system-settings-tracker/track.sh`

---

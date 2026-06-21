# bootstrap-foundation — TODO

> Priorisierte offene Punkte. Abgearbeitetes kommt in git history.

---

## 🔴 SOFORT (Forgejo live kriegen)

- [ ] `bw config server https://vault.own.dedyn.io` + `bw login` auf Mac
- [ ] Forgejo-Admin-Passwort via `bw generate` erstellen + in Vaultwarden speichern
- [ ] `git config --global --add safe.directory ...` auf NAS (dubious ownership fix)
- [ ] `git pull` auf NAS dann `bootstrap-forgejo.sh --admin-pass` mit bw-Passwort
- [ ] HAProxy auf pfSense konfigurieren: Frontend 443 → Backend NAS:3000
- [ ] DNS: `forgejo.own.dedyn.io` → `192.168.111.40`

---

## 🟠 Credential-Backend Architektur

### Pattern (beschlossen)

```
Vaultwarden  = aktuelle Passwörter (primär, immer aktuell)
KeePass      = Backup der aktuellen + History aller geänderter PWs
GPG          = später entscheiden (evtl. für at-rest encryption von .kdbx)
```

### Vaultwarden-Struktur (Ordner/Collections)
```
bootstrap-foundation/
  forgejo/
    forgejo-admin         (user: forgejo-admin, URL: https://forgejo.own.dedyn.io)
    structured-pdf        (Projekt-User)
  gitea/
    gitea-admin
  vaultwarden/
    admin-token
  nas/
    admin-ssh             (NAS SSH)
    samba-koni            (SMB)
```

### KeePass-Struktur (.kdbx) = Backup + History
```
bootstrap-foundation/       ← Root-Gruppe
  forge/
    forgejo-admin_pass
    forgejo-admin_token_*
    structured-pdf_pass
  vaultwarden/
    admin_token
  nas/
    admin_pass
```

### TODO: Mehrere alte KeePass-Files zusammenfassen
- [ ] Bestehende `.kdbx`-Dateien inventarisieren (`find ~ -name '*.kdbx'`)
- [ ] Merge-Script oder manuell in KeePassXC konsolidieren
- [ ] Ziel: Ein Master `.kdbx` unter `~/KeePassLatest.kdbx`
- [ ] Unterordner spiegeln Vaultwarden-Struktur
- [ ] Alte Files nach Merge löschen / archivieren

---

## 🟡 lib/secret-backends.sh Erweiterungen

- [ ] **Bitwarden-Backend** (`CREDENTIAL_BACKEND=bitwarden`) implementieren:
  - `sb_bw_read KEY` → `bw get password "$KEY"`
  - `sb_bw_write KEY VALUE USERNAME` → `bw create item` via JSON template
  - `_sb_bw_unlock` → `BW_SESSION=$(bw unlock --raw)` wenn kein Session
  - Auto-Detection: `keepassxc → bitwarden → gpg → plain`

- [ ] **`services/forgejo/03-create-forgejo-users.sh`** updaten:
  - Passwort zuerst aus Vaultwarden lesen (bw get)
  - Fallback: KeePass, dann Prompt

- [ ] **`services/forge/create-user.sh`** updaten:
  - Gleicher Vaultwarden-first Fallback-Chain

---

## 🟢 services/forge/ Ergänzungen

- [ ] `set-deploy-key.sh` — SSH Deploy-Key für Repo via API
- [ ] `README.md` updaten (create-repo.sh + create-token.sh dokumentieren)

---

## 🟢 services/vaultwarden/

- [ ] `uninstall.sh` erstellen
- [ ] `setup-bw-backend.sh` → setzt `CREDENTIAL_BACKEND=bitwarden` in `~/.env`
- [ ] Session-Management (`BW_SESSION` Export) in `setup-bw-backend.sh`
- [ ] email-analyser `.env` → Passwörter aus `bw get` statt Plaintext

---

## 🟢 NAS / QNAP

- [ ] `git config --global --add safe.directory` permanent auf NAS (`~/.gitconfig`)
- [ ] PATH dauerhaft in `~/.profile` auf NAS (Container Station + Entware)
- [ ] IP-Migration `192.168.1.x` → `192.168.111.x` abschließen
  - Details: `~/git/TODO-ip-migration.md`
  - Vaultwarden `docker-compose.qnap.yml` Port-Binding prüfen

---

## 🔵 Später / GPG-Entscheidung

- [ ] GPG-Rolle klären: at-rest encryption von KeePass `.kdbx`? Oder ablehnen?
- [ ] `CREDENTIAL_BACKEND=gpg` bleibt als Fallback in `lib/secret-backends.sh`

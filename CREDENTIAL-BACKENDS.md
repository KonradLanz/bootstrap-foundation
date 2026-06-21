# Credential Backends

`lib/secret-backends.sh` stellt eine einheitliche Schnittstelle fuer drei
Passwort-Backends bereit. Skripte sourced die Library und rufen `sb_read` /
`sb_write` auf – welches Backend tatsaechlich genutzt wird, entscheidet
`sb_detect_backend` automatisch oder wird per `CREDENTIAL_BACKEND` erzwungen.

## Backend-Uebersicht

| Backend | Voraussetzung | Speicherort | Empfehlung |
|---|---|---|---|
| `keepassxc` | `keepassxc-cli` + `.kdbx`-Datei | `.kdbx`-Datenbank | **Bevorzugt** – GUI + CLI, cross-platform |
| `gpg` | `gpg` in PATH | `~/.cache/kl-input-cache/<repo>/<key>.gpg` | Guter Fallback, kein GUI noetig |
| `plain` | nichts | `~/.cache/kl-input-cache/<repo>/<key>.txt` | Nur fuer nicht-sensible Werte |
| `bitwarden` | `bw` CLI + Vaultwarden/BW-Server | Vaultwarden (lokal) | Geplant – siehe Roadmap |

### Auto-Detection (Standard)

```
keepassxc  →  gpg  →  plain
(bitwarden: manuell via CREDENTIAL_BACKEND=bitwarden, noch nicht implementiert)
```

Umgebungsvariable `CREDENTIAL_BACKEND` erzwingt ein bestimmtes Backend:

```bash
CREDENTIAL_BACKEND=gpg bash services/forge/create-user.sh
```

---

## KeePassXC Backend

### Umgebungsvariablen

| Variable | Default | Beschreibung |
|---|---|---|
| `KEEPASSXC_CLI` | `keepassxc-cli` | Pfad/Name des CLI-Binaries |
| `KL_KEEPASS_DB` | `~/KeePassLatest.kdbx` | Pfad zur `.kdbx`-Datei |
| `KL_KEEPASS_GROUP` | `bootstrap-foundation` | Root-Gruppe in der DB |
| `KL_KEEPASS_PASS` | _(leer)_ | Master-PW als Env-Var (optional, fuer CI) |

### Datenbank anlegen

```bash
bash services/forge/init-keepass-db.sh

# Mit eigener DB-Datei (z.B. bestehende QNAP-DB):
KL_KEEPASS_DB=/share/homes/DOMAIN=AD/koni/Database2.kdbx \
  bash services/forge/init-keepass-db.sh
```

### Gruppen-Struktur in der DB

```
bookstrap-foundation/
  forge/
    admin_pass           <- Forge Admin-Passwort
    <username>_pass      <- Applikations-User-Passwort
    <username>_token     <- API-Token (write:repository)
  vaultwarden/
    admin_token
  nas/
    admin_pass
    ssh_key              <- (geplant)
```

### Installation auf verschiedenen Plattformen

#### QNAP NAS (x86_64) – AppImage

```bash
mkdir -p ~/bin
wget -q -O ~/bin/KeePassXC.AppImage \
  "https://github.com/keepassxreboot/keepassxc/releases/latest/download/KeePassXC-2.7.9-x86_64.AppImage"
chmod +x ~/bin/KeePassXC.AppImage

cat > ~/bin/keepassxc-cli << 'EOF'
#!/bin/sh
exec ~/bin/KeePassXC.AppImage cli "$@"
EOF
chmod +x ~/bin/keepassxc-cli
export PATH="$HOME/bin:$PATH"  # in ~/.profile eintragen
```

> **QNAP ARM** (TS-x31, x28 etc.): Kein AppImage verfuegbar.
> Fallback: `CREDENTIAL_BACKEND=gpg`

#### macOS

```bash
brew install keepassxc
# keepassxc-cli ist automatisch im PATH
```

#### Ubuntu/Debian

```bash
sudo apt install keepassxc
```

#### Windows (PowerShell)

```powershell
winget install KeePassXCTeam.KeePassXC
# keepassxc-cli.exe liegt in C:\Program Files\KeePassXC\
```

### Symlink auf bestehende DB

Falls du eine bestehende KeePass-Datei nutzen willst:

```bash
ln -sf /share/homes/DOMAIN=AD/koni/Database2.kdbx ~/KeePassLatest.kdbx
export KL_KEEPASS_DB="$HOME/KeePassLatest.kdbx"
```

**Concurrent Access:** KeePass nutzt nur einen Advisory Lock (`.lock`-Datei).
CLI-Writes waehrend kein GUI-Client offen ist: sicher.
Gleichzeitiges Schreiben aus GUI + CLI: letzter Schreibvorgang gewinnt.

---

## GPG Backend

Werte werden symmetrisch mit AES-256 verschluesselt. Kein Key-Management
noetig – das Passphrase wird beim ersten Zugriff abgefragt und vom
`gpg-agent` fuer die Session gecacht.

### Installation

```bash
# QNAP Entware
opkg install gnupg2

# macOS
brew install gnupg

# Ubuntu/Debian
sudo apt install gnupg2
```

---

## TODO: Bitwarden/Vaultwarden Backend (`bw` CLI)

> **Status:** [ ] Noch nicht implementiert

`bw` (Bitwarden CLI) soll als viertes Backend in `lib/secret-backends.sh`
engetragen werden. Relevante Infos:

- `bw` ist Node.js-basiert – **nicht auf QNAP/BusyBox lauffaehig**
- Mac und Windows: `bw` via Homebrew (`brew install bitwarden-cli`) oder
  Winget (`winget install Bitwarden.CLI`) verfuegbar
- Vaultwarden-Server laeuft bereits auf dem NAS (`https://vault.own.dedyn.io`)
- API-kompatibel mit Bitwarden-Server; `bw config server` zeigt auf
  eigene Instanz

### Geplante API-Erweiterung in `lib/secret-backends.sh`

```sh
# Backend-Erkennung (ergaenzen)
sb_detect_backend() {
    # ... keepassxc ... gpg ... dann:
    if command -v bw >/dev/null 2>&1 && bw status 2>/dev/null | grep -q '"status":"unlocked"'; then
        printf 'bitwarden'
        return
    fi
    printf 'plain'
}

# Lesen
sb_bw_read() {
    local key="$1"  # z.B. "forgejo/admin_pass"
    bw get password "$key" 2>/dev/null
}

# Schreiben (einmaliges Anlegen)
sb_bw_write() {
    local key="$1" value="$2" username="${3:-}"
    bw get template item | python3 -c "
import sys, json
t = json.load(sys.stdin)
t['name'] = '$key'
t['type'] = 1
t['login'] = {'username': '$username', 'password': '$value'}
print(json.dumps(t))
" | bw encode | bw create item
}
```

### Session-Handling

```bash
# Einmalig pro Terminal-Session:
export BW_SESSION=$(bw unlock --raw)
# oder beim ersten Login:
export BW_SESSION=$(bw login --raw)
```

---

## TODO: Secret Detection – Verteidigungsschichten

> **Status:** [ ] Noch nicht implementiert – zur Pruefung, Prioritaet offen

Secret Detection und Secret Storage sind **zwei orthogonale Schichten**.
Die folgende Uebersicht dient als Referenz fuer eine spaetere Entscheidung
ob und welche Tools eingesetzt werden:

| Schicht | Tool | Wo | Zweck |
|---|---|---|---|
| Storage | KeePass + GPG | lokal | Secrets nie als Plaintext auf Disk |
| Praevention lokal | pre-commit Hook / `git-secrets` | lokal | Blockiert Commit bevor er entsteht |
| Praevention server | GitHub Secret Scanning | GitHub | Scannt jeden Push auf bekannte Formate |
| Tiefenscan | `trufflehog` | CI/CD + lokal | Scannt History, Entropie, verifiziert live |
| Archiv-Schutz | `.gitattributes export-ignore` | Repo | Verhindert Secrets in ZIP-Exporten |

### Schicht 1: Einfacher pre-commit Hook (kein Tool-Install noetig)

```bash
cat > .git/hooks/pre-commit << 'EOF'
#!/bin/sh
if git diff --cached --name-only | grep -qE '^\.env$|^\.env\.local$'; then
  echo "ERROR: Attempt to commit .env blocked."
  exit 1
fi
if git diff --cached | grep -qiE '(password|secret|token|api_key)\s*=\s*[^$<{]'; then
  echo "WARN: Possible credential in staged diff."
  # exit 1  # auskommentieren fuer hard-block
fi
EOF
chmod +x .git/hooks/pre-commit
```

### Schicht 2: `git-secrets` (Pattern-Registry, TODO pruefen)

> Zu pruefen: Passt `git-secrets` zum KeePass-Workflow oder ist der
> pre-commit Hook (Schicht 1) ausreichend?

```bash
brew install git-secrets
git secrets --install
git secrets --register-aws
git secrets --add 'KL_KEEPASS_PASS\s*=\s*[^$<{]'
```

### Schicht 3: GitHub Secret Scanning

GitHub scannt automatisch jeden Push auf bekannte Credential-Formate.
Mit **Push Protection** wird der Push serverseitig blockiert:

> Settings → Security → Secret scanning → **Push protection: Enable**

### Schicht 4: `trufflehog` (TODO pruefen ob benoetigt)

> Zu pruefen: Ist trufflehog zusaetzlich zu GitHub Secret Scanning
> notwendig, oder reicht Schicht 3 fuer dieses Projekt?

```bash
# Einmalig lokal - scannt komplette git-History:
trufflehog git file://. --only-verified
```

### Schicht 5: `.gitattributes export-ignore`

```bash
echo '.env export-ignore' >> .gitattributes
echo '.env.local export-ignore' >> .gitattributes
echo '*.pem export-ignore' >> .gitattributes
echo '*.key export-ignore' >> .gitattributes
```

### History-Check (falls .env je committed war)

```bash
# Pruefen ob .env jemals in der History war:
git log --all --full-history -- .env

# Falls Treffer - History bereinigen:
pip install git-filter-repo
git filter-repo --path .env --invert-paths
git push --force --all
```

> `git filter-repo` kann **einzelne Dateien** aus der History entfernen,
> nicht nur ganze Repos. Aendert alle Commit-SHAs – alle Clones muessen
> danach neu geklont werden.

---

## Lizenzen

| Tool | Lizenz | Auswirkung |
|---|---|---|
| KeePassXC / keepassxc-cli | GPL-2.0+ | Subprocess-Aufruf loest keine GPL-Pflicht aus |
| GnuPG | GPL-3.0+ | Gleiche Subprocess-Ausnahme (GPL-FAQ) |
| git-secrets | Apache-2.0 | Keine Einschraenkung fuer Shell-Skripte |
| trufflehog | AGPL-3.0 | Nur CLI-Aufruf, keine Library-Einbindung – keine Infektion |
| git-filter-repo | MIT | Keine Einschraenkung |
| bootstrap-foundation | MIT | Unveraendert – keine Infektion durch externe Binaries |

Subprocess-Aufrufe via `exec`, `$()` oder Pipes gelten laut GPL-FAQ nicht
als Linking oder Combining. Shell-Skripte die nur aufrufen bleiben MIT.

Referenzen:
- https://www.gnu.org/licenses/gpl-faq.html#MereAggregation
- https://keepassxc.org/docs/
- https://github.com/awslabs/git-secrets
- https://github.com/trufflesecurity/trufflehog
- https://github.com/newren/git-filter-repo
- https://docs.github.com/en/code-security/secret-scanning/push-protection-for-repositories-and-organizations

---

## Versions-Historie

| Datum | Änderung | Branch |
|---|---|---|
| 2026-05-31 | Initiale Version: keepassxc, gpg, plain Backends | `main` |
| 2026-06-21 | Union-Merge aus `feature/enter-once-cache`: bw-Backend (TODO), Secret Detection Layers (TODO), git-filter-repo Hinweis, Lizenzen erweitert | `main` |

---

## Zu Pruefen / Unsicher (Ablage)

> Dieser Abschnitt sammelt Punkte die noch nicht entschieden oder
> verifiziert sind. Vor naechstem Release pruefen und einarbeiten oder
> verwerfen.

- [ ] **git-secrets vs. pre-commit Hook:** Ist `git-secrets` fuer dieses
  Projekt relevant, oder reicht der einfache Hook? Entscheidung ausstehend.
- [ ] **trufflehog in CI/CD:** Gitea Actions / GitHub Actions Einbindung
  sinnvoll? Oder ist GitHub Secret Scanning ausreichend?
- [ ] **`.enterHo/` in .gitignore:** Nach Merge des DurchEntern-Patterns
  sicherstellen dass `.ai/` und `.enterHo/` nicht auf GitHub landen.
  Pre-push Hook implementieren.
- [ ] **KeePass concurrent access bei NAS + Mac:** Advisory Lock klar,
  aber Verhalten bei SMB-Mount + direktem Zugriff noch nicht getestet.
- [ ] **Bitwarden-Backend QNAP:** bw CLI laeuft nicht auf BusyBox.
  Alternativer Weg: NAS-Skripte holen PW via SSH vom Mac? Oder immer
  `--admin-pass` CLI-Argument?
- [ ] **`git filter-repo` per-file rebase:** Klaeren ob `git filter-repo
  --path <file> --invert-paths` fuer einzelne Dateien in History sicher
  ist ohne den ganzen Repo-Graphen neu zu schreiben (technisch: ja, aber
  SHA-Kollateralschaden bleibt).

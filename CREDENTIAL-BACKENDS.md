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

### Auto-Detection (Standard)

```
keepassxc  -->  gpg  -->  plain
```

Umgebungsvariable `CREDENTIAL_BACKEND` erzwingt ein bestimmtes Backend:

```bash
CREDENTIAL_BACKEND=gpg bash services/forge/create-user.sh
```

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

## TODO: Secret Detection – Vollstaendige Verteidigungsschichten

> **Status:** [ ] Noch nicht implementiert

Secret Detection und Secret Storage sind **zwei orthogonale Schichten** –
sie loesen verschiedene Probleme und ergaenzen sich:

| Schicht | Tool | Wo | Zweck |
|---|---|---|---|
| **Storage** | KeePass + GPG | lokal | Secrets nie als Plaintext auf Disk |
| **Praevention lokal** | pre-commit Hook / `git-secrets` | lokal | Blockiert Commit bevor er entsteht |
| **Praevention server** | GitHub Secret Scanning | GitHub | Scannt jeden Push auf bekannte Formate |
| **Tiefenscan** | `trufflehog` | CI/CD + lokal | Scannt History, Entropie, verifiziert live |
| **Archiv-Schutz** | `.gitattributes export-ignore` | Repo | Verhindert Secrets in ZIP-Exporten |

### Schicht 1: pre-commit Hook (minimal, kein Tool-Install noetig)

Ein einfacher Shell-Hook als erste Absicherung – blockiert `.env`-Commits
und warnt bei verdaechtigen Patterns:

```bash
cat > .git/hooks/pre-commit << 'EOF'
#!/bin/sh
# Block commits that touch .env
if git diff --cached --name-only | grep -qE '^.env$|^.env.local$'; then
  echo "ERROR: Attempt to commit .env blocked by pre-commit hook."
  exit 1
fi
# Warn on suspicious patterns in staged content
if git diff --cached | grep -qiE '(password|secret|token|api_key)\s*=\s*[^$<{]'; then
  echo "WARN: Possible credential in staged diff -- review carefully."
  # exit 1  # auskommentieren fuer hard-block
fi
EOF
chmod +x .git/hooks/pre-commit
```

> Dieser Hook lebt in `.git/hooks/` und wird nicht ins Repo eingecheckt.
> Fuer Team-weite Hooks: `git-secrets --install` (Schicht 2) oder
> `core.hooksPath` auf ein versioniertes Verzeichnis setzen.

### Schicht 2: `git-secrets` als pre-commit Hook (lokal, Pattern-Registry)

```bash
brew install git-secrets       # macOS
git secrets --install          # installiert Hook in .git/hooks/pre-commit
git secrets --register-aws     # kennt AWS-Key-Pattern out-of-the-box

# Projektspezifische Pattern (Gitea-Tokens, KeePass-Pass, etc.)
git secrets --add 'KL_KEEPASS_PASS\s*=\s*[^$<{]'
git secrets --add '[0-9a-f]{40}'  # Gitea API-Token-Format
```

Ersetzt den manuellen pre-commit Hook aus Schicht 1 durch eine pflegbare
Pattern-Registry. Passt zum KeePass-Backend: `.env` landet nie auf Disk,
aber versehentliches Hineinkopieren in Quellcode wird trotzdem gestoppt.

### Schicht 3: GitHub Secret Scanning + Push Protection (serverseitig)

GitHub scannt automatisch jeden Push auf bekannte Credential-Formate
(AWS, GCP, Stripe, GitHub-Tokens, etc.). Bei Fund:
- E-Mail-Benachrichtigung an Repository-Owner
- Mit **Push Protection**: Push wird serverseitig blockiert, bevor er
  in der History landet

**Aktivieren unter:**
> Settings → Security → Secret scanning → **Push protection: Enable**

Diese Schicht greift unabhaengig von lokalen Hooks – schuetzt auch Forks
und Pull Requests von Contributoren.

### Schicht 4: `trufflehog` in CI/CD (tiefster Scan)

```bash
# Einmalig lokal – scannt komplette git-History
trufflehog git file://. --only-verified

# In Gitea Actions / GitHub Actions:
- name: Secret Scan
  uses: trufflesecurity/trufflehog@main
  with:
    path: ./
    base: ${{ github.event.repository.default_branch }}
    head: HEAD
```

`trufflehog` scannt tiefer als `git-secrets` (inkl. History, Entropie-Analyse,
verifiziert ob Credentials noch aktiv sind) und laeuft serverseitig als
zweite Sicherheitslinie nach GitHub Secret Scanning.

### Schicht 5: `.gitattributes export-ignore`

Verhindert, dass `.env` oder andere sensitive Dateien in `git archive`-
Exporten (ZIP-Downloads ueber GitHub/Gitea UI) landen:

```bash
echo '.env export-ignore' >> .gitattributes
echo '.env.local export-ignore' >> .gitattributes
echo '*.pem export-ignore' >> .gitattributes
echo '*.key export-ignore' >> .gitattributes
```

Diese Zeilen wirken nur wenn die Dateien versehentlich doch im Repo landen
– als letzte Schutzschicht fuer den Distributionsweg.

### Zusammenspiel aller Schichten

```
Entwickler tippt Secret einmal  →  sb_write speichert in KeePass/GPG
                                          │
                                          ▼
                               .env wird NICHT auf Disk geschrieben
                               Secrets leben nur im RAM (export FOO=...)
                                          │
                                          ▼
                               pre-commit / git-secrets (Schicht 1+2)
                               blockiert falls doch etwas durchgerutscht ist
                                          │
                                          ▼
                               GitHub Push Protection (Schicht 3)
                               blockiert serverseitig, unabh. von lokalem Setup
                                          │
                                          ▼
                               trufflehog CI-Scan (Schicht 4)
                               scannt History + verifiziert aktive Credentials
                                          │
                                          ▼
                               .gitattributes export-ignore (Schicht 5)
                               Secrets nicht in ZIP-Exporten/Releases
```

### WICHTIG: War `.env` je committed? History-Check

Vor dem Aktivieren aller Schichten zuerst pruefen ob die History sauber ist:

```bash
# Pruefen ob .env jemals in der History war
git log --all --full-history -- .env
git log --all --full-history -- .env.local

# Alle Dateien die je sensitive Namen hatten
git log --all --full-history -- '*.pem' '*.key'
```

**Falls ein Treffer:** Credentials sofort rotieren (Token/Passwort unguelig
machen), dann History bereinigen:

```bash
# git filter-repo (Nachfolger von git filter-branch)
pip install git-filter-repo
git filter-repo --path .env --invert-paths

# Danach: alle Remotes neu setzen und force-push
git remote add origin <url>
git push --force --all
git push --force --tags
```

> Das Bereinigen der History aendert alle Commit-SHAs. Alle Clones muessen
> danach neu geklont werden. Bei public Repos: GitHub Support kontaktieren
> um gecachte Views zu loeschen.

## Lizenzen

| Tool | Lizenz | Auswirkung auf deine Skripte |
|---|---|---|
| KeePassXC / keepassxc-cli | GPL-2.0+ | Subprocess-Aufruf loest keine GPL-Pflicht aus |
| GnuPG | GPL-3.0+ | Gleiche Subprocess-Ausnahme (GPL-FAQ) |
| git-secrets | Apache-2.0 | Keine Einschraenkung fuer Shell-Skripte |
| trufflehog | AGPL-3.0 | Nur CLI-Aufruf, keine Library-Einbindung – keine Infektion |
| git-filter-repo | MIT | Keine Einschraenkung |
| bootstrap-foundation | MIT | Unveraendert – keine Infektion durch externe Binaries |

Subprocess-Aufrufe via `exec`, `$()` oder Pipes gelten laut GPL-FAQ nicht
als Linking oder Combining. Shell-Skripte die `keepassxc-cli` oder `gpg`
nur aufrufen bleiben unter ihrer eigenen Lizenz (hier: MIT).

Referenzen:
- https://www.gnu.org/licenses/gpl-faq.html#MereAggregation
- https://keepassxc.org/docs/
- https://github.com/awslabs/git-secrets
- https://github.com/trufflesecurity/trufflehog
- https://github.com/newren/git-filter-repo
- https://docs.github.com/en/code-security/secret-scanning/push-protection-for-repositories-and-organizations

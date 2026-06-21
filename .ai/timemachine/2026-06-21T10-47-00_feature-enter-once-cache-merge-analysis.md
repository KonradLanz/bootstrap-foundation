# Timemachine: feature/enter-once-cache — Merge-Analyse & Entscheidungen

**Zeitpunkt:** 2026-06-21T10:47 CEST  
**Session-Kontext:** Forgejo-Bootstrap auf QNAP + Credential-System-Design  
**Branch:** `feature/enter-once-cache` → `main` (Merge steht aus)

---

## Was ist passiert (Chronologie dieser Session)

1. Forgejo-Bootstrap auf NAS schlägt fehl wegen `git: command not found` und `docker not found`
2. Ursache: NAS läuft als `admin` (BusyBox sh), Container Station PATH fehlt
3. Lösung: `export PATH="/share/CACHEDEV1_DATA/.qpkg/container-station/bin:..."`
4. Zweites Problem: `dubious ownership` weil Repo unter `koni`-Home liegt, SSH-Login als `admin`
5. Dann: Frage nach seamlosem Passwort-Handling → Feature-Branch entdeckt
6. PR #1 erstellt, Merge scheitert an Konflikten → lokaler Merge nötig

---

## Abstrakte Diff-Analyse: main vs. feature/enter-once-cache

### ✅ NUR auf feature-Branch: merge-ready, wollen wir

| Datei | Was | Entscheidung |
|---|---|---|
| `lib/input-cache.sh` | **Neu** — vollständiges DurchEntern/WeiterEntern System, POSIX sh, BusyBox-kompatibel | **→ main nehmen** |
| `ENTER-ONCE-CACHE.md` | **Neu** — vollständige Doku inkl. Cache-Policy Roadmap | **→ main nehmen** |
| `CREDENTIAL-BACKENDS.md` | **Erweitert** — +169 Zeilen: Secret Detection Layers, git-secrets, trufflehog, export-ignore | **→ main nehmen (beide Seiten mergen)** |
| `services/forge/create-user.sh` | **Umgebaut** — `ask()` jetzt via `kl_read_cached`, backend-aware | **→ Feature-Version nehmen** |
| `services/forge/init-keepass-db.sh` | **Refactored** — sauberer, weniger Redundanz | **→ Feature-Version nehmen** |
| `lib/secret-backends.sh` | **Modifiziert** — Details siehe unten | **→ manuell mergen** |

### ⚠️ Auf feature-Branch GELÖSCHT (seit Branch-Abspaltung auf main weiterentwickelt)

Der Branch wurde VOR diesen main-Entwicklungen abgespalten — die `D`-Einträge
sind **kein echter Delete**, sondern zeigen was main NACH dem Branch-Zeitpunkt
hinzugefügt hat:

| "Gelöscht" laut Diff | Realität |
|---|---|
| `.ai/context.md` | Auf main nach Branch-Erstellung angelegt — **behalten** |
| `TODO.md` | Heute in dieser Session angelegt — **behalten** |
| `.gitignore` | Auf main weiterentwickelt — **main-Version behalten** |
| `lib/README.md` | Auf main nach Branch angelegt — **behalten** |
| `lib/detect-hardware.ps1/.sh` | Auf main nach Branch — **behalten** |
| `macos/system-settings-tracker/diffs/*` | Tracker-Patches seit Branch — **behalten** |
| `macos/menubar-defaults/*` | Auf main nach Branch — **behalten** |
| `macos/new-project.sh` | Auf main nach Branch — **behalten** |

**Merge-Strategie:** `git merge --no-ff` + bei Konflikten jeweils
`main`-Seite als Basis, Feature-Änderungen einarbeiten.

### Konflikte erwartet in

1. `CREDENTIAL-BACKENDS.md` — beide Seiten erweitert
2. `lib/secret-backends.sh` — beide Seiten modifiziert  
3. `services/forge/create-user.sh` — komplett umgebaut auf Feature-Branch

---

## Neue Architektur-Entscheidungen (diese Session)

### .ai Folder Pattern — Erweiterung nach Merge

**Beschlossen:**
- `.ai/` Folder → nie auf GitHub, wird auf lokalem Forgejo-Server versioniert
- `.enterHo/` Folder (cache für DurchEntern) → gleiches Pattern
- Beide werden via `.gitignore` aus GitHub-Sync herausgefiltert
- Auf lokalem Forgejo: eigene Repos oder Branches für diese Layer
- Langfristig: Forgejo als primäre Versionierungsquelle für private Kontexte

**Pattern-Name:** `.ai` + `.enterHo` = "privacy-aware local-only layers"

**`.gitignore` Ergänzungen (TODO nach Merge):**
```
# Local-only layers (tracked on local Forgejo, never on GitHub)
.ai/
.enterHo/
~/.cache/kl-input-cache/  # außerhalb Repo, aber zur Klarheit
```

**Sync-Filter auf GitHub-Seite (TODO):**
- `git filter-repo --path .ai --invert-paths` vor jedem GitHub-Push
- Oder: GitHub Remote hat nur gefilterte Branches
- Entscheidung: pre-push Hook der `.ai/` und `.enterHo/` aus Push herausfiltert

### Credential-Architektur (beschlossen)

```
Vaultwarden  = aktuelle PWs (primär, always up-to-date)
KeePass .kdbx = Backup der aktuellen + vollständige History
GPG          = später entscheiden (at-rest encryption .kdbx?)
bw CLI       = fehlt noch als Backend (Roadmap in ENTER-ONCE-CACHE.md)
```

### bw (Bitwarden CLI) auf QNAP
- Nicht verfügbar (Node.js-basiert, BusyBox inkompatibel)
- Mac ist die Stelle für bw-Operationen
- NAS bekommt Passwörter via `--admin-pass` CLI-Argument oder kl_read_cached

---

## Offene TODOs nach Merge

- [ ] Merge lokal durchführen: `git merge origin/feature/enter-once-cache`
- [ ] Konflikte auflösen (siehe oben)
- [ ] `.gitignore`: `.ai/` und `.enterHo/` eintragen
- [ ] `qnap/forgejo/bootstrap-forgejo.sh` auf `kl_read_cached` umstellen
- [ ] `bootstrap-on-nas.sh` Passwort-Prompt entfernen (kommt aus Cache)
- [ ] Vaultwarden-Backend (`bw`) in `lib/secret-backends.sh` implementieren
- [ ] Pre-push Hook: filtert `.ai/` und `.enterHo/` vor GitHub-Push
- [ ] NAS: `git config --global --add safe.directory` fix permanent
- [ ] NAS: PATH in `~/.profile` dauerhaft setzen
- [ ] Forgejo Bootstrap auf NAS abschließen

---

## NAS-Probleme dieser Session (für spätere Referenz)

```
Problem 1: git nicht im PATH
Fix:       export PATH="/share/CACHEDEV1_DATA/.qpkg/container-station/bin:/opt/bin:$PATH"
Permanent: cat >> ~/.profile << 'EOF'
           export PATH="/share/CACHEDEV1_DATA/.qpkg/container-station/bin:/opt/bin:$PATH"
           EOF

Problem 2: docker not found (gleicher PATH-Fix, Container Station)

Problem 3: git dubious ownership
Ursache:   SSH als 'admin', Repo liegt unter koni-Home
Fix:       git config --global --add safe.directory \
             /share/CE_CACHEDEV4_DATA/homes/DOMAIN=AD/koni/git/bootstrap-foundation
Oder:      ssh als koni statt admin einloggen

Problem 4: Kein bw CLI auf NAS (Node.js fehlt in BusyBox)
Lösung:    bw läuft auf Mac, NAS bekommt PW via --admin-pass oder kl_read_cached
```

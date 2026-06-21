# Timemachine: .ai + .enterHo Pattern — Architektur-Entscheidung

**Zeitpunkt:** 2026-06-21T10:47 CEST  
**Status:** Entschieden, noch nicht implementiert

---

## Das Pattern

Zwei Ordner leben in jedem Repo, aber nie auf GitHub:

```
<repo>/
  .ai/                  # KI-Kontext, Entscheidungen, Timemachine
  ├── context.md         # Aktueller Kontext (Projektstand, Architektur)
  ├── timemachine/       # Zeitgestempelte Snapshots dieser Session
  │   └── YYYY-MM-DDTHH-MM-SS_<thema>.md
  └── ...                # Weitere KI-Hilfsdateien

  .enterHo/             # DurchEntern Cache (kl-input-cache lokal)
  └── <key-hash>/       # Gecachte Werte pro Repo (analog XDG_CACHE_HOME)
      ├── forge/
      │   └── admin_pass.gpg
      └── auth/
          └── github_token.gpg
```

## Sync-Modell

```
GitHub (public/private remote)
  └── Kein .ai/, kein .enterHo/
  └── Pre-push Hook filtert beide raus

Lokaler Forgejo (NAS)
  └── .ai/ wird versioniert (voller Kontext + History)
  └── .enterHo/ wird versioniert (PW-Cache, nur lokal)
  └── Kein Sync nach aussen

Mac / Workstation
  └── Beide Folder live in Working Copy
  └── .enterHo/ alternativ: $XDG_CACHE_HOME/kl-input-cache/<repo-hash>/
     (ausserhalb des Repos, kein .gitignore nötig)
```

## .gitignore Einträge (TODO implementieren)

```gitignore
# Local-only KI-Kontext (tracked only on local Forgejo)
.ai/

# DurchEntern / Enter-Once Cache
.enterHo/

# Alternativpfad (falls im Repo statt XDG_CACHE_HOME)
.kl-input-cache/
```

## Pre-push Hook (TODO implementieren)

```sh
#!/bin/sh
# .git/hooks/pre-push
# Filtert .ai/ und .enterHo/ aus Pushes zu GitHub heraus.
# Lokale Forgejo-Remotes sind ausgenommen.

remote="$1"
url="$2"

# Nur bei GitHub filtern
case "$url" in
  *github.com*)
    if git diff --cached --name-only | grep -qE '^\.ai/|^\.enterHo/'; then
      echo "[pre-push] .ai/ oder .enterHo/ würde auf GitHub landen — geblockt."
      exit 1
    fi
    ;;
esac
```

Alternativ: zwei getrennte git-Remotes:
```sh
git remote add forgejo ssh://koni@nas.ad.own.dedyn.io/~/git/bootstrap-foundation
git remote add github  git@github.com:KonradLanz/bootstrap-foundation.git

# Push mit allem an Forgejo:
git push forgejo main

# Push gefiltert an GitHub:
git push github main  # Hook filtert .ai/ und .enterHo/ raus
```

## Namensgebung

- `.ai` — neutral, klar, etabliert im dotAI-Projekt
- `.enterHo` — Wortspiel: "Enter Ho!" (Pirat) + "EnterHo" (Enter-Once)
  Cache-Verzeichnis als Verb: "ich enterHo diese Session"
  Alternativname falls zu verspielt: `.kl-cache` oder `.input-cache`

## Langfristige Vision

Forgejo (lokal auf NAS) als primärer Versionierungsserver für:
- `.ai/` Kontexte aller Repos
- `.enterHo/` Caches
- Passwort-History (via KeePass .kdbx, ebenfalls lokal)
- GPG-verschlüsselte Artefakte

GitHub bleibt: Code, Issues, PRs, CI/CD — aber KEIN privater Kontext.

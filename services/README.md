# services/

Service-spezifische Bootstrap-Foundations fuer Self-Hosted-Dienste.

Jeder Service-Bootstrap ist **unabhaengig von der OS-Plattform** und setzt
auf einem installierten Ubuntu/Debian-System auf.

## Verfuegbare Services

| Service | Typ | Lizenz | One-Liner |
|---------|-----|--------|-----------|
| **[Forgejo](forgejo/)** | Git Forge (Gitea-Fork, Free Software) | MIT / GPL-agnostisch, 100% Free | `curl -fsSL https://raw.githubusercontent.com/KonradLanz/bootstrap-foundation/main/services/forgejo/bootstrap.sh \| sh` |
| **[Gitea](gitea/)** | Git Forge (Original) | MIT (Open Core EE) | `curl -fsSL https://raw.githubusercontent.com/KonradLanz/bootstrap-foundation/main/services/gitea/bootstrap.sh \| sh` |

## Forgejo vs. Gitea — Entscheidungshilfe

| Kriterium | Forgejo | Gitea |
|-----------|---------|-------|
| Lizenz | 100% Free Software | Open Core (EE proprietaer) |
| Governance | Non-Profit (Codeberg e.V.) | Kommerziell |
| ForgeFed Federation | In Entwicklung | Nicht geplant |
| Kompatibilitaet | Gitea-API-kompatibel | — |
| Releases | Codeberg.org | dl.gitea.com |
| Empfehlung | Neue Instanzen | Bestehende Gitea-Instanzen |

## Optionale Variablen

Beide Bootstrap-Skripte unterstuetzen dieselben Umgebungsvariablen:

```sh
# Forgejo-Beispiel mit Domain und Version:
FORGEJO_VERSION=9.0.3 \
FORGEJO_DOMAIN=git.example.com \
curl -fsSL https://raw.githubusercontent.com/KonradLanz/bootstrap-foundation/main/services/forgejo/bootstrap.sh | sh

# Gitea-Beispiel:
GITEA_VERSION=1.23.7 \
GITEA_DOMAIN=git.example.com \
curl -fsSL https://raw.githubusercontent.com/KonradLanz/bootstrap-foundation/main/services/gitea/bootstrap.sh | sh
```

## Was jeder Service-Bootstrap macht

1. Basis-Pakete installieren (`git`, `curl`, `wget`, `sqlite3`)
2. Dedizierten Systembenutzer anlegen
3. Aktuelle Binary von der offiziellen Quelle herunterladen
4. Verzeichnisstruktur + `app.ini` anlegen (idempotent)
5. systemd Service registrieren und starten
6. Caddy Reverse Proxy konfigurieren (nur wenn `DOMAIN != localhost`)

## Voraussetzungen

- Ubuntu 22.04 / 24.04 oder Debian 12+
- `sudo`-Rechte oder Root-Zugang
- Offene Ports: `80` und `443` (fuer Caddy/HTTPS), `22` (SSH fuer Git)
- Gueltige Domain mit DNS-A-Eintrag (fuer automatisches Let's-Encrypt via Caddy)

# services/forge

Plattformunabhängige Hilfsskripte für **Forgejo und Gitea** – funktionieren
gegen jede laufende Instanz (QNAP Container Station, Ubuntu systemd, Docker).

## Skripte

| Skript | Zweck |
|---|---|
| `create-user.sh` | Forgejo/Gitea-User + API-Token anlegen (idempotent) |

## Verwendung

```bash
# Aus bootstrap-foundation heraus:
bash services/forge/create-user.sh

# Explizit Gitea statt Forgejo:
FORGE_TYPE=gitea bash services/forge/create-user.sh
```

Werte werden interaktiv abgefragt. Bereits gecachte Werte
(`~/.config/structured-pdf-pipeline/env`) werden als Default angezeigt –
einfach Enter drücken um sie zu übernehmen.

## Abgrenzung

| Ordner | Zweck |
|---|---|
| `services/forgejo/` | Ubuntu/Debian-Installation (Binary, systemd, Caddy) |
| `services/gitea/` | Ubuntu/Debian-Installation (Binary, systemd, Caddy) |
| `services/forge/` | **Plattformunabhängig**: User/Token-Verwaltung via REST-API |

## Cache

Gecachte Werte liegen in `~/.config/structured-pdf-pipeline/env` (lokal,
nicht im Repo). Token werden dort **nicht** automatisch gespeichert –
bitte in KeePass ablegen.

# bootstrap-foundation — Repo Context

> **Purpose:** Master AI context file. Read this first before any other `.ai.md`.
> Then read the service-specific `*-context.ai.md` for the area you work in.

**Last updated:** 2026-06-21

---

## Zweck des Repos

Infrastruktur-Bootstrap-Scripts und Service-Definitions für das GrEEV Home-Lab.
Enthält alles was nötig ist um QNAP NAS, pfSense und Services (Vaultwarden, Gitea,
Forgejo) von Null aufzusetzen.

---

## ⚠️ NAS SSH-Zugang

```
Host:  nas.ad.own.dedyn.io  (192.168.111.42 — seit 2026-06-20, vorher 192.168.1.201)
User:  admin
Login: ssh admin@nas.ad.own.dedyn.io
```

- QNAP hat **kein Standard-`docker`-Binary** im PATH
- Docker/Container Station liegt unter:
  `/share/CACHEDEV1_DATA/.qpkg/container-station/bin/docker-compose`
- `.profile` auf dem NAS anpassen:
  ```sh
  export PATH="/share/CACHEDEV1_DATA/.qpkg/container-station/bin:$PATH"
  ```
- `docker compose` (v2 Plugin) ggf. nicht verfügbar — `docker-compose` (v1) bevorzugen

---

## IP-Adressen / Netzwerk

| Host | Hostname | IP (neu) | IP (alt) |
|---|---|---|---|
| QNAP NAS | nas.ad.own.dedyn.io | 192.168.111.42 | 192.168.1.201 |
| pfSense/HAProxy | — | 192.168.111.40 | 192.168.1.2 |
| AD-DNS | ad.own.dedyn.io | 192.168.111.40 | — |

> ⚠️ Migration von `192.168.1.x` → `192.168.111.x` läuft noch (Stand 2026-06-20).
> Offene TODOs: `~/git/TODO-ip-migration.md`

**Wichtig:** Hardcoded IPs in `/etc/hosts` auf dem Mac überschreiben DNS.
Bei Verbindungsproblemen zuerst `/etc/hosts` prüfen.

---

## Repo-Struktur

```
bootstrap-foundation/
├── .ai/
│   └── context.md                     ← dieses File (Repo-weiter Kontext)
├── lib/
│   └── secret-backends.sh             ← KeePass/GPG/plain Credential-Library
├── services/
│   ├── forge/                         ← API-Skripte (Forgejo+Gitea, plattformunabhängig)
│   │   └── forge-context.ai.md
│   ├── forgejo/                       ← CLI-Install-Skripte für Forgejo (Ubuntu/Debian)
│   │   ├── forgejo-context.ai.md
│   │   └── forgejo-missing-compared-to-gitea.md  ← gap analysis (resolved)
│   ├── gitea/                         ← CLI-Install-Skripte für Gitea (Ubuntu/Debian)
│   └── vaultwarden/
│       └── vaultwarden-context.ai.md
├── qnap/                              ← QNAP-spezifische Bootstrap-Scripts
│   ├── forgejo/bootstrap-forgejo.sh
│   └── gitea/bootstrap-gitea.sh
├── pfsense/
│   └── sync-certs-to-nas.sh           ← ACME TLS-Zertifikat pfSense → QNAP
└── CREDENTIAL-BACKENDS.md            ← Doku zu lib/secret-backends.sh
```

---

## Service-Übersicht

| Service | URL | Status |
|---|---|---|
| Forgejo | https://forgejo.own.dedyn.io | ❌ nicht deployed (Scripts: ✅ komplett) |
| Vaultwarden | https://vault.own.dedyn.io | ❌ nicht deployed |
| Gitea | (geplant auf QNAP) | ❌ nicht deployed |

---

## pfSense / HAProxy

- TLS terminiert bei **allen** Services am pfSense HAProxy (Port 443)
- Intern laufen Services auf HTTP (Port 3000, 8080, etc.)
- `pfsense/sync-certs-to-nas.sh` pusht ACME-Zertifikat per SSH auf QNAP
- SSH-Key Setup (einmalig auf pfSense):
  ```sh
  ssh-keygen -t ed25519 -C "pfSense-acme-push" -f /root/.ssh/id_acme_push
  ssh-copy-id -i /root/.ssh/id_acme_push.pub admin@nas.ad.own.dedyn.io
  ```

---

## Docker Compose Konventionen

- Port-Bindings **nie** mit hardcodierter IP — stattdessen `${NAS_IP}` aus `.env`
- `.env` liegt neben dem jeweiligen `docker-compose.qnap.yml`
- Docker Daemon Default-IP in `/etc/docker/daemon.json`:
  ```json
  { "ip": "192.168.111.42" }
  ```

---

## Credential-Backend (lib/secret-backends.sh)

```
sb_read  BACKEND KEY   → stdout
sb_write BACKEND KEY VALUE [username]
```

BACKEND-Werte: `keepassxc` | `gpg` | `plain`
Auto-Detection: `sb_detect_backend()` → `keepassxc > gpg > plain`

KeePass DB: `~/KeePassLatest.kdbx` (Default, überschreibbar via `KL_KEEPASS_DB`)
Gruppen-Struktur:
- `bootstrap-foundation/forge/<key>` — API-User + Token
- `bootstrap-foundation/forgejo/<key>` — Forgejo-User Passwörter

Details: `CREDENTIAL-BACKENDS.md`

---

## Was ein AI-Helper zuerst lesen sollte

1. **Diese Datei** (`.ai/context.md`) — IPs, Struktur, Konventionen
2. **Service-spezifisch:**
   - Forgejo-Arbeit → `services/forgejo/forgejo-context.ai.md`
   - API-Skripte → `services/forge/forge-context.ai.md`
   - Vaultwarden → `services/vaultwarden/vaultwarden-context.ai.md`
3. `TODO.md` — offene Punkte mit Priorität
4. `~/git/TODO-ip-migration.md` — laufende IP-Migration

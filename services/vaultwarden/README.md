# Vaultwarden Service

Self-hosted Bitwarden-compatible password manager.

## Deployment-Strategie

| Szenario | Backend | Zugriff |
|---|---|---|
| Produktiv (bei KonradLanz) | QNAP NAS via Docker | WireGuard VPN → `https://vault.own.dedyn.io` |
| Lokal (kein Server konfiguriert) | Docker auf localhost | `http://localhost:8080` |
| CI / andere Nutzer ohne NAS | Docker Compose auto-start | `http://localhost:8080` |

Das Bootstrap-Skript erkennt automatisch ob ein externer Server erreichbar ist.
Falls nicht: lokaler Docker-Container wird gestartet.

## Dateien

| Datei | Beschreibung |
|---|---|
| `bootstrap-vaultwarden.sh` | Haupt-Bootstrap: QNAP oder lokaler Fallback |
| `docker-compose.qnap.yml` | QNAP Container Station Compose |
| `docker-compose.local.yml` | Lokaler Entwicklungs-/Fallback-Container |
| `setup-recovery-qr.sh` | QR-Code für Master-Passwort-Reset drucken |
| `setup-bw-backend.sh` | `bw` CLI konfigurieren + in secret-backends.sh einhängen |

## Schnellstart

```bash
# QNAP (im VPN) oder lokaler Fallback
bash services/vaultwarden/bootstrap-vaultwarden.sh

# QR-Code für Recovery drucken
bash services/vaultwarden/setup-recovery-qr.sh
```

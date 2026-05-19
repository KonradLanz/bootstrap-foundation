# bootstrap-foundation

Cross-platform bootstrap layer fuer Windows, macOS, Alpine (WSL2), Ubuntu (WSL2) und QNAP Entware.

## Architektur

```
ExecutionPolicy-Foundation          <- Windows PS-Kern
        downstream
bootstrap-foundation                <- Cross-platform Layer (dieses Repo)
        downstream
windows-disk-transition-toolkit     <- Projektspezifisch
git-history-tools                   <- History-Cleanup Tools
```

## Platform One-Liner

| Platform | Command |
|---|---|
| **Windows PS** | `iex ((New-Object Net.WebClient).DownloadString('https://raw.githubusercontent.com/KonradLanz/bootstrap-foundation/main/windows/bootstrap.ps1'))` |
| **macOS** | `curl -fsSL https://raw.githubusercontent.com/KonradLanz/bootstrap-foundation/main/macos/bootstrap.sh \| sh` |
| **Alpine / WSL2** | `wget -qO- https://raw.githubusercontent.com/KonradLanz/bootstrap-foundation/main/alpine/bootstrap.sh \| sh` |
| **Ubuntu / WSL2** | `curl -fsSL https://raw.githubusercontent.com/KonradLanz/bootstrap-foundation/main/ubuntu/bootstrap.sh \| sh` |
| **QNAP Entware** | `wget -qO- https://raw.githubusercontent.com/KonradLanz/bootstrap-foundation/main/qnap/bootstrap.sh \| sh` |

## Was jedes Bootstrap macht

1. Paketmanager pruefen / installieren (winget / brew / apk / apt / opkg)
2. git installieren
3. Basis-Repos klonen (`ExecutionPolicy-Foundation`, `bootstrap-foundation`)
4. Plattformspezifische Nachschritte ausgeben

## Upstream

- **[ExecutionPolicy-Foundation](https://github.com/KonradLanz/ExecutionPolicy-Foundation)** — Windows PS ExecutionPolicy, Credential-Helpers

## Verwandte Repos

- **[windows-disk-transition-toolkit](https://github.com/KonradLanz/windows-disk-transition-toolkit)** — Disk-Analyse, NAS, Bootstrap-Windows
- **[git-history-tools](https://github.com/KonradLanz/git-history-tools)** — History-Bereinigung, NOTICE, Fork-Notifications

## Lizenz

MIT — siehe [LICENSE](LICENSE)

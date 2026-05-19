# Abhaengigkeiten & Lizenzhinweise

## Upstream

| Repo | Beziehung | Lizenz |
|---|---|---|
| [ExecutionPolicy-Foundation](https://github.com/KonradLanz/ExecutionPolicy-Foundation) | Upstream (Windows-Pfad) | MIT |

## Downstream (Projekte die bootstrap-foundation nutzen)

| Repo | Platform |
|---|---|
| [windows-disk-transition-toolkit](https://github.com/KonradLanz/windows-disk-transition-toolkit) | Windows |
| [git-history-tools](https://github.com/KonradLanz/git-history-tools) | Cross-platform |

## Laufzeit-Abhaengigkeiten pro Platform

| Platform | Tool | Pflicht | Bezug |
|---|---|---|---|
| Windows | winget | Ja | Windows 10/11 Inbox |
| Windows | git | Ja | winget install --id Git.Git |
| macOS | Xcode CLT | Ja | xcode-select --install |
| macOS | Homebrew | Empfohlen | brew.sh |
| Alpine | apk | Ja | Alpine Inbox |
| Ubuntu | apt | Ja | Ubuntu Inbox |
| QNAP | Entware/opkg | Ja | QNAP App Center |

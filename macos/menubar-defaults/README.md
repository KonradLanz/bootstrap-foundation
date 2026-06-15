# menubar-defaults/

macOS Menüleisten-Defaults — idempotenter Fix für BentoBox/Notch-Flanken-Konflikt.

## Problem

BentoBox überschreibt `NSStatusItem Visible Item-2` und `Item-3` nach SystemUIServer-Restart
(setzt sie auf `0`). Die Notch-Flanken erscheinen dadurch leer.

## Betroffenes System

| Feld | Wert |
|---|---|
| macOS | 26.5.1 (Build 25F80) |
| Hardware | MacBook Pro M2 Max, 96 GB |
| Display | 3024 × 1964 Retina |
| Menu-Bar-Manager | BentoBox |
| Entdeckt | 2026-06-15 |

## Dateien

| Datei | Funktion |
|---|---|
| `apply.sh` | Idempotenter Fix — prüft aktuellen Zustand, schreibt nur wenn nötig |
| `restore.sh` | Rollback — stellt macOS-Defaults wieder her |

## Verwendung

```zsh
# Fix anwenden (idempotent, sicher mehrfach ausführbar)
bash ~/git/bootstrap-foundation/macos/menubar-defaults/apply.sh

# Rollback
bash ~/git/bootstrap-foundation/macos/menubar-defaults/restore.sh
```

## Integration in bootstrap.sh

Optional in `macos/bootstrap.sh` einbinden:

```zsh
bash "$(dirname "$0")/menubar-defaults/apply.sh"
```

## Dauerhafter Fix

Wenn `apply.sh` nach SystemUIServer-Restart wieder zurückfällt:
→ In **BentoBox-Einstellungen** für gewünschte Icons "Immer in Menüleiste anzeigen" aktivieren.
BentoBox hält dann die Sichtbarkeit selbst, kein manueller Eingriff nötig.

## Verwandtes

- Einmaliger Anlass-Script: `~/scripts/20260615_fix_notch_menubar.sh`

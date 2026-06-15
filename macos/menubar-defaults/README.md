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
| `20260615_fix_notch_menubar_oneshot.sh` | Aggressiver Einmal-Fix inkl. Session-/Control-Center-Reset für hartnäckige Notch-Flanken-Probleme |
| `restore.sh` | Rollback — stellt macOS-Defaults wieder her |

## Verwendung

```zsh
# Standard-Fix anwenden (idempotent, sicher mehrfach ausführbar)
bash ~/git/bootstrap-foundation/macos/menubar-defaults/apply.sh

# Aggressiver Einmal-Fix für Notch-Flanken / leere Bereiche links und rechts der Notch
bash ~/git/bootstrap-foundation/macos/menubar-defaults/20260615_fix_notch_menubar_oneshot.sh

# Rollback
bash ~/git/bootstrap-foundation/macos/menubar-defaults/restore.sh
```

## Integration in bootstrap.sh

Bereits in `macos/bootstrap.sh` eingebunden:

```zsh
bash "${DIR}/macos/menubar-defaults/apply.sh"
```

Der aggressive One-Shot-Fix bleibt bewusst **manuell**, weil er `ControlCenter` / `SystemUIServer` hart neu startet und je nach Zustand einen Logout erforderlich machen kann.

## Notch-Flanken

Wenn **rechts und links der Notch** trotz gesetzter `NSStatusItem Visible ... = 1` leer bleiben, reicht `apply.sh` unter Umständen nicht aus. In diesem Fall zuerst den aggressiven One-Shot-Fix verwenden; der setzt zusätzlich Spacing, Preferred Positions und relevante Control-Center-Zustände zurück.

Danach gilt weiter: Wenn BentoBox die Sichtbarkeit nach Restarts erneut überschreibt, müssen die betroffenen Icons in BentoBox dauerhaft auf "Immer in Menüleiste anzeigen" gestellt werden.

## Dauerhafter Fix

Wenn `apply.sh` nach SystemUIServer-Restart wieder zurückfällt:
→ In **BentoBox-Einstellungen** für gewünschte Icons "Immer in Menüleiste anzeigen" aktivieren.
BentoBox hält dann die Sichtbarkeit selbst, kein manueller Eingriff nötig.

## Verwandtes

- Einmaliger Anlass-Script: `~/scripts/20260615_fix_notch_menubar.sh`

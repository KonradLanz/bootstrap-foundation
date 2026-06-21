# system-settings-tracker/

Local-only macOS system settings tracker for bootstrap-foundation.

Tracks changes to privacy-sensitive `defaults` domains over time.
**Raw plist data stays local — never committed to git.**
Only diffs (patches) and a manifest are tracked in the repo.

---

## Architecture: Local Keeper

```
bootstrap-foundation/macos/system-settings-tracker/   ← committed to git
├── track.sh              — snapshot + diff engine
├── diff-show.sh          — human-readable diff viewer
├── install-launchd.sh    — register 30-min auto-run
├── manifest.txt          — change log (timestamps + domain + line count)
├── diffs/                — patch files (no raw values) committed to git
└── README.md

~/.local/system-settings-keeper/                      ← LOCAL ONLY (in .gitignore)
├── controlcenter/
│   ├── current.plist       — latest export
│   └── previous.plist      — baseline for next diff
├── dock/
├── finder/
├── ... (one dir per domain)
├── track.log
└── launchd.out / launchd.err
```

**Why this split?**
Plist exports can contain serial numbers, hardware UUIDs, paired device IDs,
and other machine-unique or sensitive data. Committing them to git creates a
permanent record of your hardware fingerprint. Only the diffs — which show
*what changed*, not full state — are committed, and they are reviewed before
being committed.

---

## Tracked Domains

| Domain | Label | Notes |
|---|---|---|
| `com.apple.controlcenter` | controlcenter | Notch flanks, status items, spacing |
| `com.apple.dock` | dock | Dock position, autohide, hot corners |
| `com.apple.finder` | finder | Extensions, hidden files, path bar |
| `com.apple.universalaccess` | universalaccess | Accessibility prefs |
| `com.apple.screensaver` | screensaver | Lock screen, screensaver timing |
| `com.apple.desktopservices` | desktopservices | .DS_Store suppression |
| `NSGlobalDomain` | NSGlobalDomain | Global prefs (key repeat, language…) |
| `com.apple.HIToolbox` | HIToolbox | Input method, keyboard layouts |
| `com.apple.driver.AppleBluetoothMultitouch.trackpad` | trackpad | Trackpad gestures |
| `com.apple.AppleMultitouchTrackpad` | multitouch | Trackpad sensitivity |
| `com.apple.PowerManagement` | powermanagement | Sleep, battery thresholds |
| `com.apple.systempreferences` | systempreferences | System Settings prefs |
| `com.apple.spaces` | spaces | Mission Control / Spaces config |

---

## Quick Start

Important: these scripts are **zsh-native**. Run them with `zsh`, not `bash`, because they use zsh path expansion like `${(%):-%N}` and `${var:A}`.

```zsh
# 1. Run tracker once manually
zsh ~/git/bootstrap-foundation/macos/system-settings-tracker/track.sh

# 2. View what changed (colored diff output)
zsh ~/git/bootstrap-foundation/macos/system-settings-tracker/diff-show.sh

# 3. Filter by domain
zsh ~/git/bootstrap-foundation/macos/system-settings-tracker/diff-show.sh controlcenter

# 4. Install 30-min auto-tracking via launchd
zsh ~/git/bootstrap-foundation/macos/system-settings-tracker/install-launchd.sh
```

---

## Notch Flank Context (Why This Module Exists)

This module was created 2026-06-15 after diagnosing a

**BentoBox → SystemUIServer restart → notch flank cleared** issue on:

- macOS 26.5.1 (Build 25F80), M2 Max, 3024×1964
- Symptom: items left/right of notch disappeared after restart
- Root cause: BentoBox overwrote `NSStatusItem Visible Item-*` keys

See `macos/menubar-defaults/` for the fix (`apply.sh` / `restore.sh`).

### macOS Notch Flank Space — Version History

| macOS Version | Notch Hardware | Flank Behavior |
|---|---|---|
| macOS 11 Big Sur (2020) | — No notch | Full menu bar, no flanks |
| macOS 12 Monterey (2021) | MacBook Pro 14”/16” M1 Pro/Max | **First notch.** Left flank: app menus. Right flank: status items (clipped if overflow) |
| macOS 13 Ventura (2022) | M2 Pro/Max models | Same behavior; Stage Manager added but unrelated |
| macOS 14 Sonoma (2023) | M3 models | Menu bar widgets added; flanks unchanged in behavior |
| macOS 15 Sequoia (2024) | M4 models | Window tiling added; flank clipping behavior unchanged |
| macOS 26 (2025/2026) | M4 Pro / M2 Max (your HW) | Flank space confirmed active; `NSStatusItemSpacing` key effective |

**Key insight:** The notch flanks have been available since Monterey on notch hardware.
The *reason* you only noticed them recently is almost certainly that a macOS or BentoBox
update changed the default spacing or visibility of `NSStatusItem` slots,
making previously-hidden items appear in the flank region.
Apple caps right-flank overflow — items are hidden when space is constrained,
prioritizing Clock, then Control Center, then user-added items.

---

## .gitignore note

Ensure `~/.local/` is NOT in the repo. This tracker writes only to
`~/.local/system-settings-keeper/` for raw data. The `diffs/` directory
in the repo contains only patch files (safe to inspect and commit).

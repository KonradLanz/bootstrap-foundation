#!/bin/sh
# macos/foundations/tools.sh  — idempotent
# Deklarative Liste aller macOS Foundation-Tools.
# Wird von bootstrap.sh aufgerufen; kann auch einzeln ausgeführt werden.
#
# Ausfuehren:
#   bash ~/git/bootstrap-foundation/macos/foundations/tools.sh

set -e

_ok()   { printf '  [OK]  %s\n' "$1"; }
_skip() { printf '  [--]  %s\n' "$1"; }
_run()  { printf '  [>>]  %s\n' "$1"; }

# Homebrew PATH (Apple Silicon)
[ -f /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"

if ! command -v brew >/dev/null 2>&1; then
  echo 'ERROR: Homebrew nicht gefunden. Bitte zuerst bootstrap.sh ausfuehren.' >&2
  exit 1
fi

echo ''
echo '================================================'
echo '  macOS Foundations: Tools  (idempotent)'
echo '================================================'
echo ''

# ---------------------------------------------------------------------------
# CLI-Tools (brew install)
# ---------------------------------------------------------------------------
CLI_TOOLS="
  git          # Versionskontrolle
  gh           # GitHub CLI — PR, Auth, Releases, Secrets
  curl         # HTTP-Client
  wget         # Alternativer HTTP-Client
  jq           # JSON-Verarbeitung
  yq           # YAML-Verarbeitung
  tree         # Verzeichnisbaum
  htop         # Prozessmonitor
  ripgrep      # Schnelles grep (rg)
  fd           # Schnelles find
  bat          # cat mit Syntax-Highlighting
  eza          # Modernes ls
  fzf          # Fuzzy-Finder
  zoxide       # Smarter cd-Ersatz
  tldr         # Kurzreferenz für Kommandos
  make         # Build-Tool
  gnupg        # GPG für Signaturen
  age          # Modernes Verschlüsselungstool
  sops         # Secrets-Verschlüsselung für Git
"

echo '--- CLI-Tools ---'
for entry in $CLI_TOOLS; do
  # Kommentare (#...) überspringen
  case "$entry" in
    \#*) continue ;;
  esac
  tool="$entry"
  if brew list "$tool" >/dev/null 2>&1; then
    _skip "$tool"
  else
    _run "installiere $tool..."
    brew install "$tool"
    _ok "$tool installiert"
  fi
done

echo ''
# ---------------------------------------------------------------------------
# Casks (brew install --cask)
# ---------------------------------------------------------------------------
CASK_TOOLS="
  keepassxc    # Passwortmanager
  visual-studio-code  # Editor
"

echo '--- Cask-Apps ---'
for entry in $CASK_TOOLS; do
  case "$entry" in
    \#*) continue ;;
  esac
  tool="$entry"
  if brew list --cask "$tool" >/dev/null 2>&1; then
    _skip "$tool"
  else
    _run "installiere $tool..."
    brew install --cask "$tool"
    _ok "$tool installiert"
  fi
done

echo ''
echo '================================================'
echo '  Foundations Tools abgeschlossen!'
echo '================================================'
echo ''

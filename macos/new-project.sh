#!/bin/sh
# =============================================================================
# macos/new-project.sh — dünner macOS-Wrapper um ../new-project.sh
# Einzige Aufgabe: Homebrew PATH sicherstellen, dann POSIX-Core aufrufen.
# Copyright 2026 GrEEV.com KG  |  AGPL-3.0-or-later
#
# USAGE
#   sh ~/git/bootstrap-foundation/macos/new-project.sh <projekt-name> [--private|--public]
# =============================================================================
set -eu

# Homebrew PATH (Apple Silicon: /opt/homebrew, Intel: /usr/local)
for _brew_prefix in /opt/homebrew /usr/local; do
  if [ -f "${_brew_prefix}/bin/brew" ]; then
    eval "$(${_brew_prefix}/bin/brew shellenv)"
    break
  fi
done

# gh installieren falls noch nicht da (macOS-spezifisch via brew)
if ! command -v gh >/dev/null 2>&1; then
  printf '  [>>]  gh nicht gefunden — installiere via Homebrew...\n'
  brew install gh
fi

# POSIX-Core aufrufen (alle Argumente 1:1 weitergeben)
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
exec sh "${SCRIPT_DIR}/new-project.sh" "$@"

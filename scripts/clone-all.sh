#!/bin/sh
# clone-all.sh — safe gh repo clone loop (POSIX sh, BusyBox-compatible)
#
# Usage:
#   sh clone-all.sh [--dry-run]
#
# Requires:
#   - gh CLI authenticated
#   - GIT_DIR must resolve to a storage volume (not a small flash partition)
#   - CLONE-EXCLUDE file (optional) in same directory as this script
#
# See: qnap-storage-advisor/docs/root-flash-overflow.md

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GIT_DIR="${GIT_DIR:-/root/git}"
EXCLUDE_FILE="$SCRIPT_DIR/CLONE-EXCLUDE"
MIN_FREE_KB=${MIN_FREE_KB:-51200}   # 50 MB minimum free before each clone
DRY_RUN=0
[ "$1" = "--dry-run" ] && DRY_RUN=1

# ── Pre-flight: refuse to clone onto flash ───────────────────────────────────

if [ -L "$GIT_DIR" ]; then
  REAL_GIT_DIR=$(readlink -f "$GIT_DIR")
else
  REAL_GIT_DIR="$GIT_DIR"
fi

echo "INFO: git volume = $REAL_GIT_DIR"
df -k "$REAL_GIT_DIR" | awk 'NR==2{printf "INFO: %dMB used / %dMB total / %dMB free\n", $3/1024, $2/1024, $4/1024}'

# Warn if resolves to a small volume (< 2GB) — likely flash
TOTAL_KB=$(df -k "$REAL_GIT_DIR" | awk 'NR==2{print $2}')
if [ "$TOTAL_KB" -lt 2097152 ]; then
  echo "WARN: git volume is smaller than 2GB — may be flash storage!"
  echo "      Set GIT_DIR to a storage volume or create a symlink."
  echo "      Continuing in 5s — Ctrl-C to abort."
  sleep 5
fi

# ── Space check ──────────────────────────────────────────────────────────────

check_space() {
  available=$(df -k "$REAL_GIT_DIR" | awk 'NR==2{print $4}')
  if [ "$available" -lt "$MIN_FREE_KB" ]; then
    echo "ERROR: less than $(( MIN_FREE_KB / 1024 ))MB free on $REAL_GIT_DIR" >&2
    echo "       Aborting — remaining repos not cloned." >&2
    exit 1
  fi
}

# ── Exclude list ─────────────────────────────────────────────────────────────

is_excluded() {
  [ -f "$EXCLUDE_FILE" ] && grep -qx "$1" "$EXCLUDE_FILE" 2>/dev/null
}

# ── Clone loop ───────────────────────────────────────────────────────────────

OK=0; CLONED=0; EXCLUDED=0; FAILED=0

gh repo list KonradLanz --limit 100 --json nameWithOwner \
  -q '.[].nameWithOwner' | while read repo; do

  name="${repo##*/}"

  if is_excluded "$name"; then
    echo "EXCLUDED: $name"
    continue
  fi

  if [ -d "$GIT_DIR/$name/.git" ]; then
    echo "OK:       $name"
    continue
  fi

  check_space

  if [ "$DRY_RUN" -eq 1 ]; then
    echo "DRY-RUN:  would clone $repo -> $GIT_DIR/$name"
    continue
  fi

  echo "CLONE:    $name ..."
  if gh repo clone "$repo" "$GIT_DIR/$name"; then
    echo "DONE:     $name"
  else
    echo "FAILED:   $name" >&2
  fi
done

df -k "$REAL_GIT_DIR" | awk 'NR==2{printf "\nFree after: %dMB\n", $4/1024}'

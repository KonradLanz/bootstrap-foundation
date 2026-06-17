#!/bin/sh
# clone-all.sh — safe gh repo clone loop for QNAP (BusyBox-compatible)
#
# Usage:
#   ./clone-all.sh [--dry-run]
#
# Requires:
#   - gh CLI authenticated (gh auth status)
#   - /root/git must be a symlink to the storage volume
#   - CLONE-EXCLUDE file (optional) next to this script
#
# See: qnap-storage-advisor/docs/root-flash-overflow.md

set -e

GIT_DIR="/root/git"
EXCLUDE_FILE="$(dirname "$0")/CLONE-EXCLUDE"
MIN_FREE_KB=51200   # 50 MB minimum free before each clone
DRY_RUN=0
[ "$1" = "--dry-run" ] && DRY_RUN=1

# ── Pre-flight checks ────────────────────────────────────────────────────────

if [ ! -L "$GIT_DIR" ]; then
  echo "ERROR: $GIT_DIR is not a symlink — refusing to clone to flash storage."
  echo "       Run: ln -s /share/homes/DOMAIN=AD/koni/git /root/git"
  exit 1
fi

REAL_GIT_DIR=$(readlink -f "$GIT_DIR")
echo "INFO: git volume = $REAL_GIT_DIR"
df -k "$REAL_GIT_DIR" | awk 'NR==2{printf "INFO: volume usage = %dMB used / %dMB total / %dMB free\n", $3/1024, $2/1024, $4/1024}'

# ── Space check function ─────────────────────────────────────────────────────

check_space() {
  available=$(df -k "$REAL_GIT_DIR" | awk 'NR==2{print $4}')
  if [ "$available" -lt "$MIN_FREE_KB" ]; then
    echo "ERROR: less than $(( MIN_FREE_KB / 1024 ))MB free on $REAL_GIT_DIR" >&2
    echo "       Aborting — remaining repos not cloned." >&2
    exit 1
  fi
}

# ── Load exclude list ────────────────────────────────────────────────────────

is_excluded() {
  name="$1"
  [ -f "$EXCLUDE_FILE" ] || return 1
  grep -qx "$name" "$EXCLUDE_FILE" 2>/dev/null
}

# ── Clone loop ───────────────────────────────────────────────────────────────

OK=0; SKIPPED=0; CLONED=0; FAILED=0; EXCLUDED=0

gh repo list KonradLanz --limit 100 --json nameWithOwner \
  -q '.[].nameWithOwner' | while read repo; do

  name="${repo##*/}"

  if is_excluded "$name"; then
    echo "EXCLUDED: $name"
    EXCLUDED=$(( EXCLUDED + 1 ))
    continue
  fi

  if [ -d "$GIT_DIR/$name/.git" ]; then
    echo "OK:       $name"
    OK=$(( OK + 1 ))
    continue
  fi

  check_space

  if [ "$DRY_RUN" -eq 1 ]; then
    echo "DRY-RUN:  would clone $repo -> $GIT_DIR/$name"
    CLONED=$(( CLONED + 1 ))
    continue
  fi

  echo "CLONE:    $name ..."
  if gh repo clone "$repo" "$GIT_DIR/$name"; then
    echo "DONE:     $name"
    CLONED=$(( CLONED + 1 ))
  else
    echo "FAILED:   $name" >&2
    FAILED=$(( FAILED + 1 ))
  fi
done

echo ""
echo "── Summary ──────────────────────────────────────────────"
echo "  Already present : $OK"
echo "  Cloned          : $CLONED"
echo "  Excluded        : $EXCLUDED"
echo "  Failed          : $FAILED"
df -k "$REAL_GIT_DIR" | awk 'NR==2{printf "  Free after      : %dMB\n", $4/1024}'

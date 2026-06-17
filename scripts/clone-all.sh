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

# ── Resolve real path ─────────────────────────────────────────────────────────

if [ -L "$GIT_DIR" ]; then
  REAL_GIT_DIR=$(readlink -f "$GIT_DIR")
else
  REAL_GIT_DIR="$GIT_DIR"
fi

echo "INFO: git volume = $REAL_GIT_DIR"

# ── df helper: BusyBox df returns 0 on NFS mounts ────────────────────────────
# Use /proc/mounts to find the actual block device mountpoint, then df that.

df_free_kb() {
  target="$1"
  # Walk up the path to find the longest matching mountpoint
  mp=$(awk -v p="$target" '
    BEGIN { best="" }
    {
      mnt=$2
      if (index(p, mnt) == 1 && length(mnt) > length(best)) best=mnt
    }
    END { print best }
  ' /proc/mounts 2>/dev/null)

  [ -z "$mp" ] && mp="$target"

  val=$(df -k "$mp" 2>/dev/null | awk 'NR==2{print $4}')
  # If empty or zero, try the target directly
  [ -z "$val" ] || [ "$val" = "0" ] && val=$(df -k "$target" 2>/dev/null | awk 'NR==2{print $4}')
  printf '%s' "${val:-0}"
}

df_total_kb() {
  target="$1"
  mp=$(awk -v p="$target" '
    BEGIN { best="" }
    { mnt=$2; if (index(p,mnt)==1 && length(mnt)>length(best)) best=mnt }
    END { print best }
  ' /proc/mounts 2>/dev/null)
  [ -z "$mp" ] && mp="$target"
  val=$(df -k "$mp" 2>/dev/null | awk 'NR==2{print $2}')
  [ -z "$val" ] || [ "$val" = "0" ] && val=$(df -k "$target" 2>/dev/null | awk 'NR==2{print $2}')
  printf '%s' "${val:-0}"
}

FREE_KB=$(df_free_kb "$REAL_GIT_DIR")
TOTAL_KB=$(df_total_kb "$REAL_GIT_DIR")

if [ "$TOTAL_KB" -gt 0 ] 2>/dev/null; then
  USED_KB=$(( TOTAL_KB - FREE_KB ))
  echo "INFO: ${USED_KB}MB used / ${TOTAL_KB}MB total / ${FREE_KB}MB free" \
    | awk '{printf "INFO: %dMB used / %dMB total / %dMB free\n", $2/1024, $5/1024, $8/1024}' 2>/dev/null \
    || echo "INFO: total=${TOTAL_KB}KB free=${FREE_KB}KB"
else
  echo "INFO: df returned 0 for $REAL_GIT_DIR (NFS mount — space guard skipped)"
fi

# ── Flash guard ───────────────────────────────────────────────────────────────

if [ "$TOTAL_KB" -gt 0 ] 2>/dev/null && [ "$TOTAL_KB" -lt 2097152 ] 2>/dev/null; then
  echo "WARN: git volume is smaller than 2GB — may be flash storage!"
  echo "      Set GIT_DIR to a storage volume or create a symlink."
  echo "      Continuing in 5s — Ctrl-C to abort."
  sleep 5
fi

# ── Space check ───────────────────────────────────────────────────────────────

check_space() {
  available=$(df_free_kb "$REAL_GIT_DIR")
  # Skip guard if df returns 0 (NFS limitation)
  [ "$available" = "0" ] && return 0
  if [ "$available" -lt "$MIN_FREE_KB" ] 2>/dev/null; then
    echo "ERROR: less than $(( MIN_FREE_KB / 1024 ))MB free on $REAL_GIT_DIR" >&2
    echo "       Aborting — remaining repos not cloned." >&2
    exit 1
  fi
}

# ── Exclude list ──────────────────────────────────────────────────────────────

is_excluded() {
  [ -f "$EXCLUDE_FILE" ] && grep -qx "$1" "$EXCLUDE_FILE" 2>/dev/null
}

# ── Clone loop ────────────────────────────────────────────────────────────────

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

echo ""
FREE_AFTER=$(df_free_kb "$REAL_GIT_DIR")
[ "$FREE_AFTER" = "0" ] \
  && echo "Free after: unknown (NFS df limitation)" \
  || echo "Free after: $(( FREE_AFTER / 1024 ))MB"

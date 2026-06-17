#!/bin/sh
# crontab-dedup.sh — remove duplicate lines from a crontab file
#
# POSIX sh, BusyBox-compatible (awk, wc, cp, mv available).
# QNAP QTS appends a full crontab copy on some updates — this fixes it.
# Safe to run multiple times (idempotent).
#
# Usage:
#   sh crontab-dedup.sh [<crontab-file>] [--dry-run]
#
# Default crontab file: /etc/config/crontab (QNAP) or /etc/crontab (Linux)
# Override: sh crontab-dedup.sh /etc/crontab

DRY_RUN=0
CRONTAB=""

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    *) CRONTAB="$arg" ;;
  esac
done

# Auto-detect crontab path
if [ -z "$CRONTAB" ]; then
  if [ -f /etc/config/crontab ]; then
    CRONTAB=/etc/config/crontab        # QNAP QTS
  elif [ -f /etc/crontab ]; then
    CRONTAB=/etc/crontab               # Linux
  else
    echo "ERROR: no crontab file found. Pass path explicitly."
    exit 1
  fi
fi

[ -f "$CRONTAB" ] || { echo "ERROR: $CRONTAB not found"; exit 1; }

ORIG_LINES=$(wc -l < "$CRONTAB")
UNIQ_LINES=$(awk '!seen[$0]++' "$CRONTAB" | wc -l)

if [ "$ORIG_LINES" -eq "$UNIQ_LINES" ]; then
  echo "OK: $CRONTAB has no duplicate lines ($ORIG_LINES lines)"
  exit 0
fi

DUPS=$(( ORIG_LINES - UNIQ_LINES ))
echo "WARN: $CRONTAB — $ORIG_LINES lines, $DUPS duplicates found"

if [ "$DRY_RUN" -eq 1 ]; then
  echo "DRY-RUN: would reduce to $UNIQ_LINES lines"
  echo "         backup would be: ${CRONTAB}.bak.$(date +%Y%m%d-%H%M%S)"
  exit 0
fi

BACKUP="${CRONTAB}.bak.$(date +%Y%m%d-%H%M%S)"
cp "$CRONTAB" "$BACKUP"
echo "INFO: backup -> $BACKUP"

awk '!seen[$0]++' "$CRONTAB" > "${CRONTAB}.tmp"
mv "${CRONTAB}.tmp" "$CRONTAB"

echo "OK: $ORIG_LINES -> $UNIQ_LINES lines"

# Reload cron (works on QNAP and most Linux)
if command -v crontab >/dev/null 2>&1; then
  crontab "$CRONTAB" 2>/dev/null && echo "OK: cron reloaded" \
    || echo "WARN: could not reload — run manually: crontab $CRONTAB"
fi

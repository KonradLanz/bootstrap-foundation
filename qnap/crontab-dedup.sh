#!/bin/sh
# crontab-dedup.sh — remove duplicate lines from /etc/config/crontab
#
# QNAP sometimes appends a full copy of the crontab on QTS updates.
# This script deduplicates in-place, backs up the original, and
# reloads the cron daemon.
#
# Safe to run multiple times (idempotent).
#
# Usage:
#   sh crontab-dedup.sh [--dry-run]

set -e

CRONTAB="/etc/config/crontab"
BACKUP="/etc/config/crontab.bak.$(date +%Y%m%d-%H%M%S)"
DRY_RUN=0
[ "$1" = "--dry-run" ] && DRY_RUN=1

if [ ! -f "$CRONTAB" ]; then
  echo "ERROR: $CRONTAB not found"
  exit 1
fi

ORIG_LINES=$(wc -l < "$CRONTAB")
UNIQ_LINES=$(sort -u "$CRONTAB" | wc -l)

if [ "$ORIG_LINES" -eq "$UNIQ_LINES" ]; then
  echo "OK: $CRONTAB has no duplicate lines ($ORIG_LINES lines)"
  exit 0
fi

DUPS=$(( ORIG_LINES - UNIQ_LINES ))
echo "WARN: $CRONTAB has $ORIG_LINES lines, $DUPS are duplicates"

if [ "$DRY_RUN" -eq 1 ]; then
  echo "DRY-RUN: would deduplicate $DUPS lines (backup -> $BACKUP)"
  exit 0
fi

# Backup
cp "$CRONTAB" "$BACKUP"
echo "INFO: backup saved to $BACKUP"

# Deduplicate preserving order (awk is available on BusyBox)
awk '!seen[$0]++' "$CRONTAB" > "${CRONTAB}.tmp"
mv "${CRONTAB}.tmp" "$CRONTAB"

NEW_LINES=$(wc -l < "$CRONTAB")
echo "OK: deduplicated $CRONTAB: $ORIG_LINES -> $NEW_LINES lines"

# Reload cron
if crontab "$CRONTAB" 2>/dev/null; then
  echo "OK: cron reloaded"
else
  echo "WARN: could not reload cron automatically — run: crontab $CRONTAB"
fi

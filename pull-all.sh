#!/usr/bin/env bash
# pull-all.sh — Tag-aware cross-repo sync
# Lives in bootstrap-foundation (most upstream repo).
# Copyright 2026 GrEEV.com KG  |  AGPL-3.0-or-later
#
# USAGE
#   bash ~/git/bootstrap-foundation/pull-all.sh              # pull all repos
#   bash ~/git/bootstrap-foundation/pull-all.sh --tag v1.2   # checkout tag everywhere
#   bash ~/git/bootstrap-foundation/pull-all.sh --branch feat/mcp  # branch or main fallback
#
set -euo pipefail

GIT_ROOT="${GIT_ROOT:-$HOME/git}"
MODE=pull
TARGET=''
FAILED=0; UPDATED=0; ALREADY=0; SKIPPED=0

while [[ $# -gt 0 ]]; do
  case $1 in
    --tag)    MODE=tag;    TARGET=$2; shift 2 ;;
    --branch) MODE=branch; TARGET=$2; shift 2 ;;
    -h|--help) grep '^#' "$0" | head -12 | sed 's/^# \?//'; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [ -t 1 ]; then
  _green()  { printf '\033[0;32m%s\033[0m\n' "$*"; }
  _yellow() { printf '\033[0;33m%s\033[0m\n' "$*"; }
  _red()    { printf '\033[0;31m%s\033[0m\n' "$*"; }
  _cyan()   { printf '\033[0;36m%s\033[0m\n' "$*"; }
  _bold()   { printf '\033[1m%s\033[0m\n'   "$*"; }
else
  _green() { echo "$*"; }; _yellow() { echo "$*"; }; _red() { echo "$*"; }
  _cyan()  { echo "$*"; }; _bold()   { echo "$*"; }
fi

echo ''
case $MODE in
  pull)   _bold "=== pull-all: $GIT_ROOT ==" ;;
  tag)    _bold "=== pull-all → tag $TARGET ==" ;;
  branch) _bold "=== pull-all → branch $TARGET (main fallback) ==" ;;
esac
echo ''

for dir in "$GIT_ROOT"/*/; do
  [ -d "$dir/.git" ] || continue
  name=$(basename "$dir")
  printf '  %-30s ' "$name"

  case $MODE in

    pull)
      # Check if current branch has an upstream; skip gracefully if not
      branch=$(git -C "$dir" symbolic-ref --short HEAD 2>/dev/null || echo '')
      has_upstream=$(git -C "$dir" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || echo '')

      if [ -z "$has_upstream" ]; then
        _yellow "no upstream (branch: ${branch:-detached}) — skipped"
        SKIPPED=$((SKIPPED+1))
        continue
      fi

      out=$(git -C "$dir" pull --ff-only 2>&1) && rc=0 || rc=$?
      if   [ $rc -ne 0 ]; then
        _red "FAIL"; echo "    ${out}" | head -3
        FAILED=$((FAILED+1))
      elif echo "$out" | grep -q 'Already up to date'; then
        _green "up to date"
        ALREADY=$((ALREADY+1))
      else
        _yellow "updated"
        UPDATED=$((UPDATED+1))
      fi
    ;;

    tag)
      git -C "$dir" fetch --tags --quiet 2>/dev/null || true
      if git -C "$dir" tag | grep -qx "$TARGET"; then
        git -C "$dir" checkout --quiet "$TARGET" 2>&1 && \
          _cyan "@ $TARGET" && UPDATED=$((UPDATED+1)) || \
          { _red "FAIL"; FAILED=$((FAILED+1)); }
      else
        _yellow "tag not found — skipped"
        SKIPPED=$((SKIPPED+1))
      fi
    ;;

    branch)
      git -C "$dir" fetch --quiet 2>/dev/null || true
      if git -C "$dir" ls-remote --heads origin "$TARGET" 2>/dev/null | grep -q "$TARGET"; then
        out=$(git -C "$dir" checkout "$TARGET" 2>&1 && git -C "$dir" pull --ff-only 2>&1) && rc=0 || rc=$?
        [ $rc -eq 0 ] && _cyan "on $TARGET" && UPDATED=$((UPDATED+1)) || \
          { _red "FAIL"; FAILED=$((FAILED+1)); }
      else
        # Fall back to main / master
        default=$(git -C "$dir" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null \
          | sed 's|refs/remotes/origin/||' || echo 'main')
        out=$(git -C "$dir" checkout "$default" 2>&1 \
              && git -C "$dir" pull --ff-only 2>&1) && rc=0 || rc=$?
        [ $rc -eq 0 ] && _green "${default} (no ${TARGET})" && ALREADY=$((ALREADY+1)) || \
          { _red "FAIL"; FAILED=$((FAILED+1)); }
      fi
    ;;
  esac
done

echo ''
case $MODE in
  pull)   _bold "=== $UPDATED updated, $ALREADY current, $SKIPPED skipped (no upstream), $FAILED failed ==" ;;
  tag)    _bold "=== $UPDATED @ $TARGET, $SKIPPED no tag, $FAILED failed ==" ;;
  branch) _bold "=== $UPDATED on $TARGET, $ALREADY on default, $FAILED failed ==" ;;
esac
echo ''

[ $FAILED -eq 0 ] || exit 1

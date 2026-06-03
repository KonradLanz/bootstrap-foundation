#!/usr/bin/env bash
# pull-all.sh — Tag-aware cross-repo sync
# Lives in bootstrap-foundation (most upstream repo).
# Copyright 2026 GrEEV.com KG  |  AGPL-3.0-or-later
#
# USAGE
#   bash ~/git/bootstrap-foundation/pull-all.sh            # pull all repos to latest
#   bash ~/git/bootstrap-foundation/pull-all.sh --tag v1.2  # checkout tag v1.2 everywhere it exists
#   bash ~/git/bootstrap-foundation/pull-all.sh --branch feat/mcp  # feature branch with main fallback
#
# STRATEGY
#   No tag/branch flag  →  git pull --ff-only on current branch (stay where you are, just update)
#   --tag <name>        →  checkout that tag in every repo that has it, skip others
#   --branch <name>     →  checkout named branch if it exists in repo, otherwise stay on main
#
# GOOD PRACTICE NOTE
#   This implements the "monorepo-lite" coordination pattern:
#   independent repos stay decoupled but can be cohered at a point-in-time
#   via a shared tag (e.g. v1.2 across all repos = a tested fleet snapshot).
#   See: https://github.com/KonradLanz/bootstrap-foundation#versioning
#
set -euo pipefail

GIT_ROOT="${GIT_ROOT:-$HOME/git}"
MODE=pull          # pull | tag | branch
TARGET=''
FAILED=0; UPDATED=0; ALREADY=0; SKIPPED=0

# ---------------------------------------------------------------------------
# Args
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case $1 in
    --tag)    MODE=tag;    TARGET=$2; shift 2 ;;
    --branch) MODE=branch; TARGET=$2; shift 2 ;;
    -h|--help)
      sed -n '2,/^set /p' "$0" | grep '^#' | sed 's/^# \?//'
      exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# ---------------------------------------------------------------------------
# Colour helpers (no-op if not a tty)
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# Header
# ---------------------------------------------------------------------------
echo ''
case $MODE in
  pull)   _bold "=== pull-all: $GIT_ROOT (ff-only on current branch) ==" ;;
  tag)    _bold "=== pull-all: $GIT_ROOT → tag $TARGET ==" ;;
  branch) _bold "=== pull-all: $GIT_ROOT → branch $TARGET (main fallback) ==" ;;
esac
echo ''

# ---------------------------------------------------------------------------
# Per-repo logic
# ---------------------------------------------------------------------------
for dir in "$GIT_ROOT"/*/; do
  [ -d "$dir/.git" ] || continue
  name=$(basename "$dir")
  printf '  %-30s ' "$name"

  case $MODE in

    # -- plain pull: just update current branch --
    pull)
      out=$(git -C "$dir" pull --ff-only 2>&1) && rc=0 || rc=$?
      if   [ $rc -ne 0 ]; then
        _red   "FAIL"; echo "    ${out}" | head -3
        FAILED=$((FAILED+1))
      elif echo "$out" | grep -q 'Already up to date'; then
        _green "up to date"
        ALREADY=$((ALREADY+1))
      else
        _yellow "updated"
        UPDATED=$((UPDATED+1))
      fi
    ;;

    # -- tag checkout: exact point-in-time cohesion across repos --
    tag)
      # Fetch tags silently first
      git -C "$dir" fetch --tags --quiet 2>/dev/null || true
      if git -C "$dir" tag | grep -qx "$TARGET"; then
        git -C "$dir" checkout --quiet "$TARGET" 2>&1 && \
          _cyan "@ $TARGET" && UPDATED=$((UPDATED+1)) || \
          { _red "FAIL (checkout)"; FAILED=$((FAILED+1)); }
      else
        _yellow "tag not found — skipped"
        SKIPPED=$((SKIPPED+1))
      fi
    ;;

    # -- branch: checkout if exists, else stay on main --
    branch)
      git -C "$dir" fetch --quiet 2>/dev/null || true
      # Check remote branch exists
      if git -C "$dir" ls-remote --heads origin "$TARGET" 2>/dev/null | grep -q "$TARGET"; then
        out=$(git -C "$dir" checkout "$TARGET" 2>&1 && git -C "$dir" pull --ff-only 2>&1) && rc=0 || rc=$?
        [ $rc -eq 0 ] && _cyan "on $TARGET" && UPDATED=$((UPDATED+1)) || \
          { _red "FAIL"; FAILED=$((FAILED+1)); }
      else
        # Fall back: ensure we're on main and up to date
        out=$(git -C "$dir" checkout main 2>&1 && git -C "$dir" pull --ff-only 2>&1) && rc=0 || rc=$?
        [ $rc -eq 0 ] && _green "main (no $TARGET)" && ALREADY=$((ALREADY+1)) || \
          { _red "FAIL (main fallback)"; FAILED=$((FAILED+1)); }
      fi
    ;;
  esac
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ''
case $MODE in
  pull)   _bold "=== $UPDATED updated, $ALREADY current, $FAILED failed ==" ;;
  tag)    _bold "=== $UPDATED checked out @ $TARGET, $SKIPPED skipped (no tag), $FAILED failed ==" ;;
  branch) _bold "=== $UPDATED on $TARGET, $ALREADY on main fallback, $FAILED failed ==" ;;
esac
echo ''

[ $FAILED -eq 0 ] || exit 1

#!/usr/bin/env zsh
# system-settings-tracker/diff-show.sh — zsh native; invoke with zsh, not bash

setopt ERR_EXIT PIPE_FAIL
SCRIPT_PATH="${(%):-%N}"
SCRIPT_DIR="${SCRIPT_PATH:A:h}"
DIFF_STORE="${SCRIPT_DIR}/diffs"

FILTER_DOMAIN="${1:-}"
FILTER_SINCE="${2:-}"

if [[ ! -d "$DIFF_STORE" ]]; then
  echo "No diffs yet. Run track.sh first."
  exit 0
fi

setopt NULL_GLOB
files=("${DIFF_STORE}"/*.patch)

if [[ ${#files} -eq 0 ]]; then
  echo "No diffs recorded yet."
  exit 0
fi

for f in "${files[@]}"; do
  name="$(basename "$f")"
  [[ -n "$FILTER_DOMAIN" && "$name" != *"${FILTER_DOMAIN}"* ]] && continue
  [[ -n "$FILTER_SINCE"  && "$name" != *"${FILTER_SINCE}"*  ]] && continue
  echo
  echo "════════════════════════════════════════════════════════════════"
  echo "  $name"
  echo "════════════════════════════════════════════════════════════════"
  grep -E '^[+-]' "$f" | grep -v '^---\|^+++' |     sed -e 's/^+/\x1b[32m+\x1b[0m/' -e 's/^-/\x1b[31m-\x1b[0m/' || cat "$f"
done
echo

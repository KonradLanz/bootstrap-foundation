#!/usr/bin/env zsh
# macos/system-settings-tracker/track.sh — zsh native; invoke with zsh, not bash
# Snapshots defaults domains locally; commits only diffs to git, never raw plists.

setopt ERR_EXIT PIPE_FAIL

SCRIPT_PATH="${(%):-%N}"
SCRIPT_DIR="${SCRIPT_PATH:A:h}"
LOCAL_KEEPER_DIR="${LOCAL_KEEPER_DIR:-${HOME}/.local/system-settings-keeper}"
GIT_REPO="${SCRIPT_DIR:h:h}"
DIFF_STORE="${SCRIPT_DIR}/diffs"
MANIFEST="${SCRIPT_DIR}/manifest.txt"
LOG_FILE="${LOCAL_KEEPER_DIR}/track.log"
SNAP_DATE="$(date +%Y-%m-%dT%H-%M-%S)"

domains=(
  "com.apple.controlcenter|controlcenter|"
  "com.apple.dock|dock|"
  "com.apple.finder|finder|"
  "com.apple.universalaccess|universalaccess|"
  "com.apple.screensaver|screensaver|"
  "com.apple.desktopservices|desktopservices|"
  "com.apple.NetworkBrowser|networkbrowser|"
  "com.apple.spaces|spaces|"
  "NSGlobalDomain|NSGlobalDomain|-g"
  "com.apple.HIToolbox|HIToolbox|"
  "com.apple.driver.AppleBluetoothMultitouch.trackpad|trackpad|"
  "com.apple.AppleMultitouchTrackpad|multitouch|"
  "com.apple.PowerManagement|powermanagement|"
  "com.apple.systempreferences|systempreferences|"
)

mkdir -p "${LOCAL_KEEPER_DIR}" "${DIFF_STORE}"
touch "${LOG_FILE}" "${MANIFEST}"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "${LOG_FILE}" }

snapshot_domain() {
  local domain="$1"
  local label="$2"
  local extra_args="$3"
  local dir="${LOCAL_KEEPER_DIR}/${label}"
  local current="${dir}/current.plist"
  local prev="${dir}/previous.plist"
  local diff_out="${DIFF_STORE}/${label}-${SNAP_DATE}.patch"
  local rest patch line_count

  mkdir -p "${dir}"

  if [[ -n "$extra_args" ]]; then
    defaults ${=extra_args} export "$domain" - > "$current" 2>/dev/null || {
      log "WARN: ${domain} export failed (domain may not exist yet)"
      return 0
    }
  else
    defaults export "$domain" - > "$current" 2>/dev/null || {
      log "WARN: ${domain} export failed (domain may not exist yet)"
      return 0
    }
  fi

  if [[ ! -f "$prev" ]]; then
    cp "$current" "$prev"
    log "INIT: ${label} — baseline created"
    echo "${SNAP_DATE} INIT ${label}" >> "$MANIFEST"
    return 0
  fi

  patch=$(diff -u "$prev" "$current" || true)
  if [[ -z "$patch" ]]; then
    log "UNCHANGED: ${label}"
    return 0
  fi

  printf '%s\n' "$patch" > "$diff_out"
  cp "$current" "$prev"
  line_count=$(wc -l < "$diff_out" | tr -d ' ')
  log "CHANGED: ${label} → diff saved: ${diff_out}"
  echo "${SNAP_DATE} CHANGED ${label} ${line_count} lines" >> "$MANIFEST"

  if [[ -d "$GIT_REPO/.git" ]]; then
    git -C "$GIT_REPO" add "$diff_out" "$MANIFEST" >/dev/null 2>&1 || true
    git -C "$GIT_REPO" commit -m "track(system-settings): ${label} changed [${SNAP_DATE}]" --no-verify >/dev/null 2>&1 || true
  fi
}

log "=== system-settings-tracker/track.sh ==="
typeset domain label extra rest
for entry in "${domains[@]}"; do
  domain="${entry%%|*}"
  rest="${entry#*|}"
  label="${rest%%|*}"
  extra="${rest##*|}"
  snapshot_domain "$domain" "$label" "$extra"
done
log "=== done ==="

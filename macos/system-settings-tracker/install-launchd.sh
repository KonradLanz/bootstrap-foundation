#!/usr/bin/env zsh
# system-settings-tracker/install-launchd.sh — zsh native; invoke with zsh, not bash

setopt ERR_EXIT PIPE_FAIL
SCRIPT_PATH="${(%):-%N}"
SCRIPT_DIR="${SCRIPT_PATH:A:h}"
TRACK_SCRIPT="${SCRIPT_DIR}/track.sh"
LABEL="dev.bootstrap.system-settings-tracker"
PLIST="${HOME}/Library/LaunchAgents/${LABEL}.plist"

mkdir -p "${HOME}/Library/LaunchAgents" "${HOME}/.local/system-settings-keeper"
chmod +x "$TRACK_SCRIPT"

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/zsh</string>
    <string>${TRACK_SCRIPT}</string>
  </array>
  <key>StartInterval</key><integer>1800</integer>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>${HOME}/.local/system-settings-keeper/launchd.out</string>
  <key>StandardErrorPath</key><string>${HOME}/.local/system-settings-keeper/launchd.err</string>
</dict>
</plist>
EOF

launchctl unload "$PLIST" 2>/dev/null || true
launchctl load -w "$PLIST"

echo "[OK] LaunchAgent installed: ${LABEL}"
echo "     Runs every 30 min. Logs: ~/.local/system-settings-keeper/launchd.*"

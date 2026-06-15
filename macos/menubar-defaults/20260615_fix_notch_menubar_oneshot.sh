#!/usr/bin/env zsh
# fix-notch-menubar.sh
# Fixes menu bar notch-flank icon visibility on macOS 26.x
# Restores NSStatusItem slots and restarts SystemUIServer

set -euo pipefail

DOMAIN="com.apple.controlcenter"
SPACING_KEY="NSStatusItemSpacing"
SPACING_VALUE=6

echo "==> Reading current NSStatusItem visibility state..."
defaults read "$DOMAIN" 2>/dev/null | grep -E "NSStatusItem|VisibleCC" || true

echo ""
echo "==> Enabling all NSStatusItem slots (Item-0 through Item-3)..."
for i in 0 1 2 3; do
  defaults write "$DOMAIN" "NSStatusItem Visible Item-$i" -bool true
  echo "    Item-$i → true"
done

echo ""
echo "==> Ensuring BentoBox and CC items are visible..."
defaults write "$DOMAIN" "NSStatusItem Visible BentoBox" -bool true
defaults write "$DOMAIN" "NSStatusItem VisibleCC BentoBox-0" -bool true
defaults write "$DOMAIN" "NSStatusItem VisibleCC Battery" -bool true
defaults write "$DOMAIN" "NSStatusItem VisibleCC Clock" -bool true
defaults write "$DOMAIN" "NSStatusItem VisibleCC WiFi" -bool true

echo ""
echo "==> Reducing NSStatusItemSpacing to $SPACING_VALUE (default ~12) for denser notch-flank packing..."
defaults write -g "$SPACING_KEY" -int "$SPACING_VALUE"

echo ""
echo "==> Restarting SystemUIServer..."
killall SystemUIServer 2>/dev/null && echo "    SystemUIServer restarted." || echo "    SystemUIServer not running, skipping."

echo ""
echo "==> Verifying post-restart state (wait 2s for SystemUIServer to settle)..."
sleep 2
echo "--- NSStatusItem values after restart ---"
defaults read "$DOMAIN" 2>/dev/null | grep -E "NSStatusItem|VisibleCC" || true

echo ""
echo "==> Done. If BentoBox reverts Item-2/Item-3 again, enable 'Always show in menu bar'"
echo "    for those icons directly inside BentoBox preferences."

#!/bin/sh
# qnap/bootstrap.sh
# QNAP NAS Bootstrap via Entware (BusyBox sh)
#
# PREREQUISITES: Entware must be installed via QNAP App Center.
#
# COLD START (first time, no local repo yet):
#   wget -qO- https://raw.githubusercontent.com/KonradLanz/bootstrap-foundation/main/bootstrap.sh | sh
#
# REPEATABLE (from local repo, after first run):
#   cd /share/CACHEDEV2_DATA/repos/bootstrap-foundation && git pull && sh bootstrap.sh

GITHUB_USER="${GITHUB_USER:-KonradLanz}"
REPO_BASE="/share/CACHEDEV2_DATA/repos"

# Load lib/detect-os.sh if available (local repo run), skip on cold start
SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo '.')"
if [ -f "$SCRIPT_DIR/../lib/detect-os.sh" ]; then
    . "$SCRIPT_DIR/../lib/detect-os.sh"
    detect_os
fi

echo ''
echo '================================================'
echo '  bootstrap-foundation: QNAP Entware'
echo '================================================'
echo ''

# 1) Verify Entware is installed
echo '[1/5] Checking Entware...'
if [ ! -f /opt/bin/opkg ]; then
    echo '      [ERROR] Entware not found!'
    echo '      Please install Entware via QNAP App Center first.'
    echo '      https://github.com/Entware/Entware/wiki/Install-on-QNAP-NAS'
    exit 1
fi
echo '      Entware OK (/opt/bin/opkg)'

export PATH="/opt/bin:/opt/sbin:$PATH"

# 2) opkg update + base packages
echo '[2/5] opkg update + base packages...'
opkg update
for PKG in git wget; do
    if ! command -v "$PKG" >/dev/null 2>&1; then
        echo "      Installing $PKG..."
        opkg install "$PKG"
    else
        echo "      $PKG already installed, OK"
    fi
done

# 3) Install Entware vim and set up /opt/bin/vi symlink
#
# Background: QNAP ships two broken vim variants:
#   /bin/vim  -> QNAP App Center vim QPKG (vim 7.2, 2008)
#               - Missing syntax files (/usr/local/share/vim/ is empty)
#               - Broken TTY handling in some SSH sessions
#               - Can become a 0-byte file after QPKG corruption/update
#   /bin/vi   -> same QPKG, same problems
#
# Strategy: Install Entware vim to /opt/bin/vim (runs in parallel, never
# touches /bin/). Set /opt/bin/vi -> /opt/bin/vim so that with /opt/bin
# first in PATH, both `vim` and `vi` resolve to Entware vim.
#
# Why we never overwrite /bin/vim or /bin/vi:
#   QTS updates and QPKG reinstalls reset /bin/ symlinks. Overwriting them
#   would break after every update. After a QTS update, /bin/vim falls back
#   to the QNAP system vim (old but functional) — no total outage.
#   Once Entware starts and PATH is loaded, /opt/bin/vim takes precedence.
#
# The autorun.sh hook below re-creates /opt/bin/vi after every reboot,
# ensuring the symlink survives NAS restarts.
echo '[3/5] Setting up Entware vim...'
if [ -x /opt/bin/vim ]; then
    echo '      Entware vim already installed (/opt/bin/vim), OK'
else
    echo '      Installing Entware vim to /opt/bin/vim (parallel to /bin/vim)...'
    opkg install vim
fi
# /opt/bin/vi symlink: safe to set here, never touches /bin/
if [ -x /opt/bin/vim ]; then
    ln -sf /opt/bin/vim /opt/bin/vi
    echo '      /opt/bin/vi -> /opt/bin/vim linked'
else
    echo '      [WARN] /opt/bin/vim not found after install, skipping vi symlink'
fi

# 4) Clone or update repos
echo '[4/5] Cloning/updating repos...'
mkdir -p "$REPO_BASE"
for REPO in bootstrap-foundation qnap-config-keeper qnap-dotfiles; do
    DIR="$REPO_BASE/$REPO"
    if [ ! -d "$DIR" ]; then
        echo "      Cloning $REPO..."
        git clone "https://github.com/$GITHUB_USER/$REPO.git" "$DIR"
    else
        echo "      Updating $REPO..."
        git -C "$DIR" pull
    fi
done
echo '      Repos OK'

# 5) Set up qnap-config-keeper (cron + autorun.sh)
echo '[5/5] Setting up qnap-config-keeper...'
CONFIG_KEEPER="$REPO_BASE/qnap-config-keeper/qnap-config-keeper.sh"
if [ -f "$CONFIG_KEEPER" ]; then
    ln -sf "$CONFIG_KEEPER" /opt/bin/qnap-config-keeper.sh
    chmod +x "$CONFIG_KEEPER"
    KEEPER_REPO="/share/CACHEDEV2_DATA/config-keeper"
    if [ ! -d "$KEEPER_REPO/.git" ]; then
        echo '      Initializing config-keeper repo...'
        sh "$CONFIG_KEEPER" init
    else
        echo '      config-keeper repo already exists, OK'
    fi
    sh "$CONFIG_KEEPER" install
    echo '      qnap-config-keeper OK'
else
    echo '      [WARN] qnap-config-keeper.sh not found, skipping'
fi

# Ensure /opt/bin/vi symlink survives reboots via autorun.sh.
# QTS does not reset /opt/bin/ on updates, but Entware re-mounts /opt
# on every boot, so the symlink needs to be re-created.
# We add this hook only once.
AUTORUN="/etc/config/autorun.sh"
if ! grep -q 'opt/bin/vi.*opt/bin/vim' "$AUTORUN" 2>/dev/null; then
    [ -f "$AUTORUN" ] || { echo '#!/bin/sh' > "$AUTORUN"; chmod +x "$AUTORUN"; }
    echo '[ -x /opt/bin/vim ] && ln -sf /opt/bin/vim /opt/bin/vi  # Entware vim: re-create /opt/bin/vi after reboot' >> "$AUTORUN"
    echo '      autorun.sh: /opt/bin/vi hook added'
else
    echo '      autorun.sh: /opt/bin/vi hook already present, OK'
fi

echo ''
echo '================================================'
echo '  QNAP Bootstrap complete!'
echo '================================================'
echo ''
echo "Repos : $REPO_BASE"
echo "config-keeper : /share/CACHEDEV2_DATA/config-keeper"
echo ''
echo 'To make PATH permanent (if not already set):'
echo '  echo export PATH="/opt/bin:/opt/sbin:\$PATH" >> /etc/profile'
echo ''

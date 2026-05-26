#!/bin/sh
# qnap/bootstrap.sh
# QNAP NAS Bootstrap via Entware (BusyBox sh)
#
# VORAUSSETZUNG: Entware muss installiert sein (QNAP App Center)
#
# COLD START (einmalig, ohne lokales Repo):
#   wget -qO- https://raw.githubusercontent.com/KonradLanz/bootstrap-foundation/main/bootstrap.sh | sh
#
# WIEDERHOLBAR (aus lokalem Repo):
#   cd /share/homes/admin/github/bootstrap-foundation && git pull && sh bootstrap.sh

GITHUB_USER="${GITHUB_USER:-KonradLanz}"
REPO_BASE="/share/homes/admin/github"

# lib/detect-os.sh laden falls vorhanden (lokales Repo), sonst inline
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

# 1) Entware pruefen
echo '[1/5] Pruefe Entware...'
if [ ! -f /opt/bin/opkg ]; then
    echo '      [FEHLER] Entware nicht gefunden!'
    echo '      Bitte Entware im QNAP App Center installieren.'
    echo '      https://github.com/Entware/Entware/wiki/Install-on-QNAP-NAS'
    exit 1
fi
echo '      Entware OK (/opt/bin/opkg)'

export PATH="/opt/bin:/opt/sbin:$PATH"

# 2) opkg update + git + wget
echo '[2/5] opkg update + Basispakete...'
opkg update
for PKG in git wget; do
    if ! command -v "$PKG" >/dev/null 2>&1; then
        echo "      Installiere $PKG..."
        opkg install "$PKG"
    else
        echo "      $PKG OK"
    fi
done

# 3) vim via Entware (System-/bin/vim hat keine volle Syntax-Unterstuetzung)
echo '[3/5] vim einrichten...'
# QNAP hat /bin/vim (System-vim, eingeschraenkt), wir wollen /opt/bin/vim (Entware-vim, vollstaendig)
if [ -f /opt/bin/vim ]; then
    echo '      Entware-vim bereits installiert (/opt/bin/vim), OK'
else
    echo '      Installiere Entware-vim (ersetzt /bin/vim nicht, liegt parallel in /opt/bin)...'
    opkg install vim
fi
# vi-Symlink: nur in /opt/bin anlegen, nie /bin/vi ueberschreiben
if [ -f /opt/bin/vim ] && [ ! -e /opt/bin/vi ]; then
    ln -sf /opt/bin/vim /opt/bin/vi
    echo '      /opt/bin/vi -> /opt/bin/vim verlinkt'
else
    echo '      vi-Symlink bereits vorhanden oder vim fehlt, OK'
fi

# 4) Repos klonen oder aktualisieren
echo '[4/5] Repos klonen/aktualisieren...'
mkdir -p "$REPO_BASE"
for REPO in bootstrap-foundation qnap-config-keeper qnap-dotfiles; do
    DIR="$REPO_BASE/$REPO"
    if [ ! -d "$DIR" ]; then
        echo "      Klone $REPO..."
        git clone "https://github.com/$GITHUB_USER/$REPO.git" "$DIR"
    else
        echo "      Aktualisiere $REPO..."
        git -C "$DIR" pull
    fi
done
echo '      Repos OK'

# 5) qnap-config-keeper einrichten
echo '[5/5] qnap-config-keeper einrichten...'
CONFIG_KEEPER="$REPO_BASE/qnap-config-keeper/qnap-config-keeper.sh"
if [ -f "$CONFIG_KEEPER" ]; then
    ln -sf "$CONFIG_KEEPER" /opt/bin/qnap-config-keeper.sh
    chmod +x "$CONFIG_KEEPER"
    KEEPER_REPO="/share/CACHEDEV2_DATA/config-keeper"
    if [ ! -d "$KEEPER_REPO/.git" ]; then
        echo '      Initialisiere config-keeper Repo...'
        sh "$CONFIG_KEEPER" init
    else
        echo '      config-keeper Repo bereits vorhanden, OK'
    fi
    sh "$CONFIG_KEEPER" install
    echo '      qnap-config-keeper OK'
else
    echo '      [WARN] qnap-config-keeper.sh nicht gefunden, uebersprungen'
fi

echo ''
echo '================================================'
echo '  QNAP Bootstrap abgeschlossen!'
echo '================================================'
echo ''
echo "Repos: $REPO_BASE"
echo "config-keeper: /share/CACHEDEV2_DATA/config-keeper"
echo ''
echo 'PATH dauerhaft (falls noch nicht gesetzt):'
echo '  echo export PATH="/opt/bin:/opt/sbin:\$PATH" >> /etc/profile'
echo ''

#!/bin/sh
# qnap/bootstrap.sh
# QNAP NAS Bootstrap via Entware (BusyBox sh)
#
# VORAUSSETZUNG: Entware muss installiert sein (QNAP App Center)
#
# STARTEN (SSH auf QNAP):
#   wget -qO- https://raw.githubusercontent.com/KonradLanz/bootstrap-foundation/main/qnap/bootstrap.sh | sh

GITHUB_USER="${GITHUB_USER:-KonradLanz}"
REPO_BASE="/share/homes/admin/github"

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

# PATH fuer Entware sicherstellen
export PATH="/opt/bin:/opt/sbin:$PATH"

# 2) opkg update + Pakete
echo '[2/5] opkg update + Pakete installieren...'
opkg update
for PKG in git wget vim; do
    if ! command -v "$PKG" >/dev/null 2>&1; then
        echo "      Installiere $PKG..."
        opkg install "$PKG"
    else
        echo "      $PKG bereits vorhanden, OK"
    fi
done
echo '      Pakete OK'

# 3) vim als vi-Ersatz verlinken (Entware vim hat vollen Syntax-Support)
echo '[3/5] vim als Standard-Editor einrichten...'
if [ -f /opt/bin/vim ] && [ ! -L /opt/bin/vi ]; then
    ln -sf /opt/bin/vim /opt/bin/vi
    echo '      /opt/bin/vi -> vim verlinkt'
else
    echo '      vi-Symlink bereits vorhanden oder vim nicht gefunden, OK'
fi

# 4) Repos klonen
echo '[4/5] Repos klonen...'
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

# 5) qnap-config-keeper installieren (Cron + autorun.sh)
echo '[5/5] qnap-config-keeper einrichten...'
CONFIG_KEEPER="$REPO_BASE/qnap-config-keeper/qnap-config-keeper.sh"
if [ -f "$CONFIG_KEEPER" ]; then
    # Script in /opt/bin verlinken
    ln -sf "$CONFIG_KEEPER" /opt/bin/qnap-config-keeper.sh
    chmod +x "$CONFIG_KEEPER"
    # Init nur wenn Repo noch nicht existiert
    KEEPER_REPO="/share/CACHEDEV2_DATA/config-keeper"
    if [ ! -d "$KEEPER_REPO/.git" ]; then
        echo '      Initialisiere config-keeper Repo...'
        sh "$CONFIG_KEEPER" init
    else
        echo '      config-keeper Repo bereits vorhanden, OK'
    fi
    # Cron + autorun.sh einrichten
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
echo 'Hinweis: PATH fuer Entware dauerhaft setzen:'
echo '  echo export PATH="/opt/bin:/opt/sbin:\$PATH" >> /etc/profile'
echo ''
echo 'vim-Tipp: .vimrc fuer QNAP (busybox-safe):'
echo '  if !has("syntax") | finish | endif'
echo '  syntax on'
echo ''

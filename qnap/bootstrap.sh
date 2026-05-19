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
echo '[1/4] Pruefe Entware...'
if [ ! -f /opt/bin/opkg ]; then
    echo '      [FEHLER] Entware nicht gefunden!'
    echo '      Bitte Entware im QNAP App Center installieren.'
    echo '      https://github.com/Entware/Entware/wiki/Install-on-QNAP-NAS'
    exit 1
fi
echo '      Entware OK (/opt/bin/opkg)'

# PATH fuer Entware sicherstellen
export PATH="/opt/bin:/opt/sbin:$PATH"

# 2) opkg update + git
echo '[2/4] opkg update + git installieren...'
opkg update
if ! command -v git >/dev/null 2>&1; then
    opkg install git
fi
echo '      git OK'

# 3) wget / curl
echo '[3/4] Pruefe wget/curl...'
if ! command -v wget >/dev/null 2>&1; then
    opkg install wget
fi
echo '      OK'

# 4) Repos klonen
echo '[4/4] Repos klonen...'
mkdir -p "$REPO_BASE"
for REPO in bootstrap-foundation; do
    DIR="$REPO_BASE/$REPO"
    if [ ! -d "$DIR" ]; then
        echo "      Klone $REPO..."
        git clone "https://github.com/$GITHUB_USER/$REPO.git" "$DIR"
    else
        echo "      Aktualisiere $REPO..."
        git -C "$DIR" pull
    fi
done
echo '      OK'

echo ''
echo '================================================'
echo '  QNAP Bootstrap abgeschlossen!'
echo '================================================'
echo ''
echo "Repos: $REPO_BASE"
echo ''
echo 'Hinweis: PATH fuer Entware dauerhaft setzen:'
echo '  echo export PATH="/opt/bin:/opt/sbin:\$PATH" >> /etc/profile'
echo ''

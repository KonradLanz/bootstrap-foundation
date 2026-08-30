#!/bin/sh
# bootstrap-foundation/android/full-setup.sh
# IDEMPOTENT All-in-One Setup fuer Android/Termux.
# Kann beliebig oft erneut gestartet werden - macht dort weiter, wo aufgehoert wurde.
# Nutzt HTTPS + gh-Credential-Helper statt SSH-Keys (keine "Permission denied (publickey)" Fehler mehr).
#
# One-liner:
#   curl -fsSL https://raw.githubusercontent.com/KonradLanz/bootstrap-foundation/main/android/full-setup.sh | sh

set -e

GITHUB_USER="${KL_GITHUB_USER:-KonradLanz}"
PROJECTS="$HOME/projects"

_banner() {
  printf '\n\033[1;36m########################################\033[0m\n'
  printf '\033[1;36m#  %s\033[0m\n' "$1"
  printf '\033[1;36m########################################\033[0m\n\n'
}
_ok()   { printf '\n\033[1;32m>>> %s\033[0m\n\n' "$*"; }
_wait() { printf '\033[1;33m%s\033[0m\n' "$*"; }
_warn() { printf '\n\033[1;31m>>> %s\033[0m\n\n' "$*"; }

_banner 'SCHRITT 1 VON 6: SPEICHERZUGRIFF'
if [ ! -d "$HOME/storage" ]; then
  _wait 'Fordere Speicherzugriff an ...'
  termux-setup-storage || _warn 'Konnte nicht automatisch angefordert werden - kein Problem, weiter gehts'
  _ok 'ERLEDIGT'
else
  _ok 'BEREITS ERLEDIGT - WEITER GEHTS'
fi

_banner 'SCHRITT 2 VON 6: GRUNDPROGRAMME'
_wait 'Aktualisiere und installiere Grundprogramme ... bitte warten (kann 1-2 Minuten dauern)'
pkg update -y >/dev/null 2>&1
pkg install -y git openssh curl wget python nodejs vim termux-api gh >/dev/null 2>&1
_ok 'GRUNDPROGRAMME BEREIT'

_banner 'SCHRITT 3 VON 6: GIT-EINSTELLUNGEN'
if [ -z "$(git config --global user.name 2>/dev/null)" ]; then
  printf 'WIE SOLL DEIN NAME BEI AENDERUNGEN ANGEZEIGT WERDEN?\n> '
  read -r GIT_NAME
  git config --global user.name "${GIT_NAME:-Nutzer}"
fi
if [ -z "$(git config --global user.email 2>/dev/null)" ]; then
  printf 'DEINE E-MAIL-ADRESSE (fuer Git, wird nicht versendet):\n> '
  read -r GIT_EMAIL
  git config --global user.email "${GIT_EMAIL:-nutzer@example.com}"
fi
git config --global init.defaultBranch main
git config --global pull.rebase false
_ok "GIT EINGERICHTET: $(git config --global user.name) <$(git config --global user.email)>"

_banner 'SCHRITT 4 VON 6: BEI GITHUB ANMELDEN'
if gh auth status >/dev/null 2>&1; then
  _ok 'DU BIST BEREITS ANGEMELDET - KEIN LOGIN NOETIG'
else
  printf '\033[1;33mGLEICH OEFFNET SICH DER BROWSER.\033[0m\n'
  printf '\033[1;33mDORT ERSCHEINT EIN KURZER CODE.\033[0m\n'
  printf '\033[1;33mDIESEN CODE EINGEBEN UND BESTAETIGEN.\033[0m\n\n'
  gh auth login --hostname github.com --git-protocol https --web
  _ok 'ANMELDUNG ERFOLGREICH'
fi

gh auth setup-git >/dev/null 2>&1 || true
_ok 'GIT NUTZT JETZT DEINEN GITHUB-LOGIN AUTOMATISCH (HTTPS, KEIN SSH-KEY NOETIG)'

_banner 'SCHRITT 5 VON 6: PROJEKTE HERUNTERLADEN'
mkdir -p "$PROJECTS"

_clone_or_pull() {
  _name="$1"
  _url="https://github.com/${GITHUB_USER}/${_name}.git"
  _dir="$PROJECTS/$_name"
  if [ -d "$_dir/.git" ]; then
    _wait "Aktualisiere $_name ..."
    ( cd "$_dir" && git pull --ff-only ) || _warn "$_name: Aktualisierung uebersprungen (lokale Aenderungen vorhanden?)"
    _ok "$_name IST AKTUELL"
  else
    _wait "Lade $_name herunter ..."
    git clone "$_url" "$_dir"
    _ok "$_name HERUNTERGELADEN"
  fi
}

_clone_or_pull 'bootstrap-foundation'
_clone_or_pull 'hello-world-apk'

_banner 'SCHRITT 6 VON 6: HILFS-BEFEHLE EINRICHTEN'
if ! grep -q 'alias gcp=' "$HOME/.bashrc" 2>/dev/null; then
  cat >> "$HOME/.bashrc" << 'BASHRC'

# --- bootstrap-foundation android helpers ---
alias gs='git status'
alias gl='git log --oneline -10'
alias gp='git push'
alias gpl='git pull'
alias ga='git add -A'
_kl_commit_push() { git add -A && git commit -m "${*:-update}" && git push; }
alias gcp='_kl_commit_push'
BASHRC
  _ok 'BEFEHLE EINGERICHTET (gs, gl, gp, gpl, ga, gcp)'
else
  _ok 'BEFEHLE BEREITS VORHANDEN'
fi

printf '\n\033[1;32m########################################\033[0m\n'
printf '\033[1;32m#      ALLES FERTIG EINGERICHTET!      #\033[0m\n'
printf '\033[1;32m########################################\033[0m\n\n'

printf 'DEINE PROJEKTE LIEGEN HIER:\n'
printf '  %s/bootstrap-foundation\n' "$PROJECTS"
printf '  %s/hello-world-apk\n\n' "$PROJECTS"

printf 'NAECHSTER SCHRITT:\n'
printf '  1. Acode oeffnen\n'
printf '  2. Ordner oeffnen: %s/hello-world-apk\n' "$PROJECTS"
printf '  3. Datei www/index.html bearbeiten\n'
printf '  4. In Termux: cd %s/hello-world-apk\n' "$PROJECTS"
printf '  5. Dann: gcp "meine erste Aenderung"\n\n'

printf '\033[1;32mTIPP: Dieses Skript kannst du JEDERZEIT erneut ausfuehren.\033[0m\n'
printf '\033[1;32mEs ueberspringt automatisch alles, was schon erledigt ist.\033[0m\n\n'

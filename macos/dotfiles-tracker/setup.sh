#!/bin/sh
# macos/dotfiles-tracker/setup.sh
# Erstellt das lokale dotfiles Git-Repo, kopiert die konfigurierten Dateien
# hinein und setzt Symlinks zurueck an die Originalposition.
#
# Ausfuehren (einmalig):
#   bash ~/git/bootstrap-foundation/macos/dotfiles-tracker/setup.sh
#
# Umgebungsvariablen (optional):
#   DOTFILES_DIR   Zielverzeichnis fuer das dotfiles-Repo  (default: ~/git/dotfiles)

set -e

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/git/dotfiles}"

echo ''
echo '================================================'
echo '  dotfiles-tracker: Setup'
echo '================================================'
echo ''

# Konfigurierte Dateien: "Quelle|Zieldatei-im-Repo"
# Quelle kann ~ enthalten, wird mit $HOME expandiert
FILES="
$HOME/.zshrc|zshrc
$HOME/.zprofile|zprofile
$HOME/.gitconfig|gitconfig
$HOME/.ssh/config|ssh/config
/etc/hosts|etc/hosts
"

# 1) Verzeichnis + Git-Repo anlegen
echo '[1/4] Verzeichnis anlegen...'
mkdir -p "${DOTFILES_DIR}"
if [ ! -d "${DOTFILES_DIR}/.git" ]; then
  git -C "${DOTFILES_DIR}" init
  echo "      Init: ${DOTFILES_DIR}"
else
  echo '      Git-Repo existiert bereits.'
fi

# .gitignore anlegen (SSH private keys etc. nie tracken)
cat > "${DOTFILES_DIR}/.gitignore" << 'EOF'
# Niemals private SSH-Keys tracken!
ssh/id_*
ssh/*.pem
ssh/*.key
EOF

# 2) Dateien kopieren + Unterverzeichnisse anlegen
echo '[2/4] Dateien ins Repo kopieren...'
echo "$FILES" | while IFS='|' read -r src dst; do
  [ -z "$src" ] && continue

  dst_path="${DOTFILES_DIR}/${dst}"
  dst_dir=$(dirname "${dst_path}")

  if [ ! -f "${src}" ]; then
    echo "      SKIP (nicht vorhanden): ${src}"
    continue
  fi

  mkdir -p "${dst_dir}"
  cp "${src}" "${dst_path}"
  echo "      OK: ${src} -> ${dst}"
done

# 3) Symlinks setzen (Original ersetzen durch Symlink ins Repo)
echo '[3/4] Symlinks setzen...'
echo "$FILES" | while IFS='|' read -r src dst; do
  [ -z "$src" ] && continue

  dst_path="${DOTFILES_DIR}/${dst}"
  [ ! -f "${dst_path}" ] && continue

  # Backup des Originals (falls kein Symlink)
  if [ -f "${src}" ] && [ ! -L "${src}" ]; then
    cp "${src}" "${src}.bak"
    echo "      Backup: ${src}.bak"
  fi

  # Symlink nur fuer Home-Dateien (nicht /etc/ - braucht sudo)
  case "${src}" in
    /etc/*)
      echo "      INFO: ${src} - kein Symlink (braucht sudo), nur getrackt"
      ;;
    *)
      ln -sf "${dst_path}" "${src}"
      echo "      Symlink: ${src} -> ${dst_path}"
      ;;
  esac
done

# 4) Ersten Commit
echo '[4/4] Initialen Commit anlegen...'
git -C "${DOTFILES_DIR}" add -A
git -C "${DOTFILES_DIR}" commit -m "initial snapshot [$(date '+%Y-%m-%d %H:%M')]" 2>/dev/null \
  || echo '      (keine Aenderungen zum committen)'

echo ''
echo '================================================'
echo '  dotfiles-tracker Setup abgeschlossen!'
echo '================================================'
echo ''
echo "Dotfiles-Repo: ${DOTFILES_DIR}"
echo ''
echo 'Verlauf ansehen:'
echo "  git -C ${DOTFILES_DIR} log --oneline"
echo ''
echo 'Aenderungen manuell committen:'
echo "  bash ~/git/bootstrap-foundation/macos/dotfiles-tracker/dotfiles-sync.sh"
echo ''

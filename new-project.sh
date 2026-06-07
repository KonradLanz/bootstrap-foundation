#!/bin/sh
# =============================================================================
# new-project.sh — POSIX core: Neues oder vorhandenes Projekt einrichten
# Läuft auf: macOS zsh/bash, Alpine ash, BusyBox (QNAP), Ubuntu sh
# Upstream: bootstrap-foundation
# Copyright 2026 GrEEV.com KG  |  AGPL-3.0-or-later
#
# USAGE
#   sh ~/git/bootstrap-foundation/new-project.sh <projekt-name>
#   sh ~/git/bootstrap-foundation/new-project.sh <projekt-name> --private
#   sh ~/git/bootstrap-foundation/new-project.sh <projekt-name> --public
#
# ENV-Variablen (alle optional)
#   GITHUB_USER   GitHub-Username        (default: KonradLanz)
#   GIT_ROOT      lokales Repo-Verz.     (default: ~/git)
#   VISIBILITY    private|public         (default: private)
#   DOTFILES_RC   shell rc-Datei         (default: ~/.zshrc oder ~/.bashrc)
# =============================================================================
set -eu

GITHUB_USER="${GITHUB_USER:-KonradLanz}"
GIT_ROOT="${GIT_ROOT:-$HOME/git}"
VISIBILITY="${VISIBILITY:-private}"

# ---------------------------------------------------------------------------
# Helfer (POSIX-sicher: keine bash-Arrays, kein [[ ]])
# ---------------------------------------------------------------------------
if [ -t 1 ]; then
  _ok()   { printf '  \033[0;32m[OK]\033[0m  %s\n' "$*"; }
  _skip() { printf '  \033[0;36m[--]\033[0m  %s\n' "$*"; }
  _run()  { printf '  \033[1;33m[>>]\033[0m  %s\n' "$*"; }
  _err()  { printf '  \033[0;31m[!!]\033[0m  %s\n' "$*" >&2; }
  _head() { printf '\n\033[1m=== %s ===\033[0m\n' "$*"; }
else
  _ok()   { echo "  [OK]  $*"; }
  _skip() { echo "  [--]  $*"; }
  _run()  { echo "  [>>]  $*"; }
  _err()  { echo "  [!!]  $*" >&2; }
  _head() { echo ""; echo "=== $* ==="; }
fi

# ---------------------------------------------------------------------------
# Argumente
# ---------------------------------------------------------------------------
if [ $# -lt 1 ]; then
  echo "Usage: sh $0 <projekt-name> [--private|--public]"
  exit 1
fi

PROJEKT="$1"; shift

while [ $# -gt 0 ]; do
  case "$1" in
    --private) VISIBILITY=private; shift ;;
    --public)  VISIBILITY=public;  shift ;;
    *) _err "Unbekannte Option: $1"; exit 1 ;;
  esac
done

LOCAL_DIR="${GIT_ROOT}/${PROJEKT}"

_head "new-project: ${PROJEKT} (${VISIBILITY})"

# ---------------------------------------------------------------------------
# 1. GIT_ROOT anlegen
# ---------------------------------------------------------------------------
_head "1/6  GIT_ROOT"
if [ -d "${GIT_ROOT}" ]; then
  _skip "${GIT_ROOT} existiert"
else
  mkdir -p "${GIT_ROOT}"
  _ok "${GIT_ROOT} angelegt"
fi

# ---------------------------------------------------------------------------
# 2. Auth: gh bevorzugt, SSH-Fallback
# ---------------------------------------------------------------------------
_head "2/6  GitHub-Auth"

GH_AVAILABLE=0
if command -v gh >/dev/null 2>&1; then
  if gh auth status >/dev/null 2>&1; then
    _skip "gh bereits authentifiziert"
    GH_AVAILABLE=1
  else
    _run "gh nicht eingeloggt — starte Authentifizierung..."
    gh auth login --hostname github.com --git-protocol https --web
    gh auth setup-git
    GH_AVAILABLE=1
    _ok "gh authentifiziert + credential helper gesetzt"
  fi
else
  _skip "gh CLI nicht gefunden — prüfe SSH"
  if ssh -T git@github.com 2>&1 | grep -q 'successfully authenticated'; then
    _skip "SSH zu GitHub funktioniert"
  else
    _err "Weder gh noch SSH-Auth verfügbar!"
    _err "Lösung: sh ${GIT_ROOT}/bootstrap-foundation/macos/02-gh-auth.sh"
    exit 1
  fi
fi

# ---------------------------------------------------------------------------
# 3. Repo klonen oder anlegen
# ---------------------------------------------------------------------------
_head "3/6  Repository"

if [ -d "${LOCAL_DIR}/.git" ]; then
  _skip "${LOCAL_DIR} bereits ein git-Repo — aktualisiere"
  BRANCH=$(git -C "${LOCAL_DIR}" symbolic-ref --short HEAD 2>/dev/null || echo 'main')
  git -C "${LOCAL_DIR}" pull --ff-only >/dev/null 2>&1 \
    && _ok "Repo aktuell (${BRANCH})" \
    || _skip "Kein upstream — lokaler Stand behalten"

elif [ -d "${LOCAL_DIR}" ]; then
  _skip "${LOCAL_DIR} existiert ohne .git — initialisiere"
  git -C "${LOCAL_DIR}" init
  git -C "${LOCAL_DIR}" branch -M main 2>/dev/null || true
  _ok "git init in ${LOCAL_DIR}"

else
  REMOTE_EXISTS=0
  if [ "${GH_AVAILABLE}" = "1" ]; then
    if gh repo view "${GITHUB_USER}/${PROJEKT}" >/dev/null 2>&1; then
      REMOTE_EXISTS=1
    fi
  fi

  if [ "${REMOTE_EXISTS}" = "1" ]; then
    _run "Klone ${GITHUB_USER}/${PROJEKT} nach ${LOCAL_DIR}..."
    if [ "${GH_AVAILABLE}" = "1" ]; then
      gh repo clone "${GITHUB_USER}/${PROJEKT}" "${LOCAL_DIR}"
    else
      git clone "git@github.com:${GITHUB_USER}/${PROJEKT}.git" "${LOCAL_DIR}"
    fi
    _ok "Geklont nach ${LOCAL_DIR}"
  else
    _run "Repo nicht remote gefunden — lege neu an..."
    mkdir -p "${LOCAL_DIR}"
    cd "${LOCAL_DIR}"
    git init
    git branch -M main 2>/dev/null || true
    if [ "${GH_AVAILABLE}" = "1" ]; then
      gh repo create "${GITHUB_USER}/${PROJEKT}" \
        "--${VISIBILITY}" \
        --source=. \
        --remote=origin \
        --push >/dev/null 2>&1 \
        && _ok "Remote-Repo angelegt (${VISIBILITY}) + initial push" \
        || _skip "Remote-Anlage übersprungen"
    else
      _skip "gh nicht verfügbar — Remote manuell:"
      echo "  git remote add origin git@github.com:${GITHUB_USER}/${PROJEKT}.git"
    fi
  fi
fi

# ---------------------------------------------------------------------------
# 4. dotfiles einbinden (idempotent, RC-Datei auto-detect)
# ---------------------------------------------------------------------------
_head "4/6  dotfiles"

DOTFILES_DIR="${GIT_ROOT}/dotfiles-macos"

# RC-Datei: explizit per Env, sonst .zshrc wenn vorhanden, sonst .bashrc
if [ -n "${DOTFILES_RC:-}" ]; then
  RC_FILE="${DOTFILES_RC}"
elif [ -f "${HOME}/.zshrc" ]; then
  RC_FILE="${HOME}/.zshrc"
else
  RC_FILE="${HOME}/.bashrc"
fi

if [ -d "${DOTFILES_DIR}" ]; then
  if grep -qF 'dotfiles-macos/git/aliases.zsh' "${RC_FILE}" 2>/dev/null; then
    _skip "aliases.zsh bereits in ${RC_FILE}"
  else
    printf 'source "%s/git/aliases.zsh"\n' "${DOTFILES_DIR}" >> "${RC_FILE}"
    _ok "aliases.zsh in ${RC_FILE} eingetragen"
  fi
  if git config --global --list 2>/dev/null | grep -q 'dotfiles-macos/git/gitconfig'; then
    _skip "gitconfig include bereits gesetzt"
  else
    git config --global include.path "${DOTFILES_DIR}/git/gitconfig"
    _ok "gitconfig include gesetzt"
  fi
else
  _skip "dotfiles-macos nicht unter ${DOTFILES_DIR}"
  _skip "  → sh ${GIT_ROOT}/bootstrap-foundation/pull-all.sh"
fi

# ---------------------------------------------------------------------------
# 5. requirements.txt + install.sh
# ---------------------------------------------------------------------------
_head "5/6  Projekt-Setup"

cd "${LOCAL_DIR}"

if [ -f requirements.txt ]; then
  PIP=""
  command -v pip3 >/dev/null 2>&1 && PIP="pip3"
  command -v pip  >/dev/null 2>&1 && PIP="${PIP:-pip}"
  if [ -n "${PIP}" ]; then
    _run "${PIP} install -r requirements.txt"
    "${PIP}" install --quiet -r requirements.txt \
      && _ok "Python-Dependencies installiert" \
      || _skip "Einige Dependencies fehlgeschlagen"
  else
    _skip "pip nicht gefunden — requirements.txt übersprungen"
  fi
else
  _skip "keine requirements.txt"
fi

if [ -f install.sh ]; then
  _run "sh install.sh"
  sh install.sh && _ok "install.sh erfolgreich" || _skip "install.sh mit Fehlern"
else
  _skip "kein install.sh"
fi

# ---------------------------------------------------------------------------
# 6. Fertig-Report
# ---------------------------------------------------------------------------
_head "6/6  Fertig!"
printf '\n  Projekt:  %s\n' "${PROJEKT}"
printf '  Lokal:    %s\n' "${LOCAL_DIR}"
if [ "${GH_AVAILABLE}" = "1" ]; then
  printf '  Remote:   https://github.com/%s/%s\n' "${GITHUB_USER}" "${PROJEKT}"
fi
printf '\n  Nächste Schritte:\n'
printf '    cd %s\n' "${LOCAL_DIR}"
printf '    gup "erster commit"   # Alias aus dotfiles-macos\n'
printf '\n'

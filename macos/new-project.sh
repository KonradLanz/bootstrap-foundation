#!/usr/bin/env bash
# =============================================================================
# macos/new-project.sh — Neues oder vorhandenes Projekt einrichten
# Upstream: bootstrap-foundation
# Copyright 2026 GrEEV.com KG  |  AGPL-3.0-or-later
#
# USAGE
#   bash ~/git/bootstrap-foundation/macos/new-project.sh <projekt-name>
#   bash ~/git/bootstrap-foundation/macos/new-project.sh <projekt-name> --private
#   bash ~/git/bootstrap-foundation/macos/new-project.sh <projekt-name> --public
#
# Was es tut (idempotent, alles was schon da ist wird übersprungen):
#   1. gh / git Verfügbarkeit prüfen + Auth sicherstellen
#   2. GIT_ROOT anlegen falls nicht vorhanden
#   3. Repo lokal klonen ODER remote anlegen + klonen
#      → gh bevorzugt (kennt private + public), git-SSH als Fallback
#   4. dotfiles-macos aliases.zsh + gitconfig einbinden falls vorhanden
#   5. requirements.txt + install.sh ausführen falls vorhanden
#   6. Fertig-Report mit nächsten Schritten
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Konfiguration (Env-Variablen überschreiben Defaults)
# ---------------------------------------------------------------------------
GITHUB_USER="${GITHUB_USER:-KonradLanz}"
GIT_ROOT="${GIT_ROOT:-$HOME/git}"
VISIBILITY="${VISIBILITY:-private}"  # Default: privat

# ---------------------------------------------------------------------------
# Farben + Helfer
# ---------------------------------------------------------------------------
if [ -t 1 ]; then
  _ok()   { printf '  \033[0;32m[OK]\033[0m  %s\n' "$*"; }
  _skip() { printf '  \033[0;36m[--]\033[0m  %s\n' "$*"; }
  _run()  { printf '  \033[1;33m[>>]\033[0m  %s\n' "$*"; }
  _err()  { printf '  \033[0;31m[!!]\033[0m  %s\n' "$*" >&2; }
  _head() { printf '\n\033[1m%s\033[0m\n' "$*"; }
else
  _ok()   { echo "  [OK]  $*"; }
  _skip() { echo "  [--]  $*"; }
  _run()  { echo "  [>>]  $*"; }
  _err()  { echo "  [!!]  $*" >&2; }
  _head() { echo ""; echo "$*"; }
fi

# ---------------------------------------------------------------------------
# Argumente
# ---------------------------------------------------------------------------
if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <projekt-name> [--private|--public]"
  exit 1
fi

PROJEKT="$1"
shift

while [[ $# -gt 0 ]]; do
  case $1 in
    --private) VISIBILITY=private; shift ;;
    --public)  VISIBILITY=public;  shift ;;
    *) _err "Unbekannte Option: $1"; exit 1 ;;
  esac
done

LOCAL_DIR="${GIT_ROOT}/${PROJEKT}"

_head "=== new-project: ${PROJEKT} (${VISIBILITY}) ==="

# ---------------------------------------------------------------------------
# 1. Homebrew PATH sicherstellen (Apple Silicon)
# ---------------------------------------------------------------------------
[[ -f /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"

# ---------------------------------------------------------------------------
# 2. GIT_ROOT anlegen
# ---------------------------------------------------------------------------
_head "[1/6] GIT_ROOT"
if [[ -d "${GIT_ROOT}" ]]; then
  _skip "${GIT_ROOT} existiert"
else
  mkdir -p "${GIT_ROOT}"
  _ok "${GIT_ROOT} angelegt"
fi

# ---------------------------------------------------------------------------
# 3. gh-Auth sicherstellen (gh hat Priorität)
# ---------------------------------------------------------------------------
_head "[2/6] GitHub-Auth"

GH_AVAILABLE=0
if command -v gh &>/dev/null; then
  if gh auth status &>/dev/null 2>&1; then
    _skip "gh bereits authentifiziert"
    GH_AVAILABLE=1
  else
    _run "gh nicht eingeloggt — starte Authentifizierung..."
    # gh auth setup-git setzt credential.helper, danach klappt auch plain git
    gh auth login --hostname github.com --git-protocol https --web
    gh auth setup-git
    GH_AVAILABLE=1
    _ok "gh authentifiziert + credential helper gesetzt"
  fi
else
  _skip "gh CLI nicht gefunden — versuche SSH-Fallback"
  # SSH-Fallback: prüfen ob Key für github.com konfiguriert
  if ssh -T git@github.com 2>&1 | grep -q 'successfully authenticated'; then
    _skip "SSH zu GitHub funktioniert"
  else
    _err "Weder gh noch SSH-Auth verfügbar!"
    _err "Lösung: bash ${GIT_ROOT}/bootstrap-foundation/macos/02-gh-auth.sh"
    exit 1
  fi
fi

# ---------------------------------------------------------------------------
# 4. Repo klonen oder anlegen
# ---------------------------------------------------------------------------
_head "[3/6] Repository"

if [[ -d "${LOCAL_DIR}/.git" ]]; then
  _skip "${LOCAL_DIR} bereits ein git-Repo — aktualisiere"
  BRANCH=$(git -C "${LOCAL_DIR}" symbolic-ref --short HEAD 2>/dev/null || echo 'main')
  git -C "${LOCAL_DIR}" pull --ff-only 2>/dev/null && _ok "Repo aktuell (${BRANCH})" || _skip "Kein upstream — lokaler Stand behalten"

elif [[ -d "${LOCAL_DIR}" ]]; then
  _skip "${LOCAL_DIR} existiert, aber kein .git — initialisiere"
  git -C "${LOCAL_DIR}" init
  git -C "${LOCAL_DIR}" branch -M main
  _ok "git init in ${LOCAL_DIR}"

else
  # Remote-Check: existiert das Repo schon auf GitHub?
  REMOTE_EXISTS=0
  if [[ $GH_AVAILABLE -eq 1 ]]; then
    if gh repo view "${GITHUB_USER}/${PROJEKT}" &>/dev/null 2>&1; then
      REMOTE_EXISTS=1
    fi
  fi

  if [[ $REMOTE_EXISTS -eq 1 ]]; then
    # Repo existiert remote → klonen
    _run "Klone ${GITHUB_USER}/${PROJEKT} nach ${LOCAL_DIR}..."
    if [[ $GH_AVAILABLE -eq 1 ]]; then
      # gh repo clone nutzt automatisch SSH oder HTTPS je nach gh-Konfiguration
      # und kennt private Repos ohne extra Token-Gymkhana
      gh repo clone "${GITHUB_USER}/${PROJEKT}" "${LOCAL_DIR}"
    else
      git clone "git@github.com:${GITHUB_USER}/${PROJEKT}.git" "${LOCAL_DIR}"
    fi
    _ok "Geklont nach ${LOCAL_DIR}"
  else
    # Repo existiert noch nicht → lokal init + optional remote anlegen
    _run "Repo ${PROJEKT} existiert nicht remote — lege an..."
    mkdir -p "${LOCAL_DIR}"
    cd "${LOCAL_DIR}"
    git init
    git branch -M main

    if [[ $GH_AVAILABLE -eq 1 ]]; then
      gh repo create "${GITHUB_USER}/${PROJEKT}" \
        --${VISIBILITY} \
        --source=. \
        --remote=origin \
        --push 2>/dev/null && _ok "Remote-Repo angelegt (${VISIBILITY}) + initial push" \
        || _skip "Remote-Anlage übersprungen (vielleicht schon vorhanden)"
    else
      _skip "gh nicht verfügbar — Remote manuell anlegen:"
      echo "        git remote add origin git@github.com:${GITHUB_USER}/${PROJEKT}.git"
    fi
  fi
fi

# ---------------------------------------------------------------------------
# 5. dotfiles-macos einbinden (idempotent)
# ---------------------------------------------------------------------------
_head "[4/6] dotfiles-macos"

DOTFILES_DIR="${GIT_ROOT}/dotfiles-macos"
ZSHRC="${HOME}/.zshrc"

if [[ -d "${DOTFILES_DIR}" ]]; then
  # aliases.zsh
  ALIASES_LINE="source \"${DOTFILES_DIR}/git/aliases.zsh\""
  if grep -qF 'dotfiles-macos/git/aliases.zsh' "${ZSHRC}" 2>/dev/null; then
    _skip "aliases.zsh bereits in .zshrc"
  else
    echo "${ALIASES_LINE}" >> "${ZSHRC}"
    _ok "aliases.zsh in .zshrc eingetragen"
  fi

  # gitconfig via include
  if git config --global --list 2>/dev/null | grep -q 'dotfiles-macos/git/gitconfig'; then
    _skip "gitconfig include bereits gesetzt"
  else
    git config --global include.path "${DOTFILES_DIR}/git/gitconfig"
    _ok "gitconfig include gesetzt"
  fi
else
  _skip "dotfiles-macos nicht unter ${DOTFILES_DIR} — übersprungen"
  _skip "  → bash ${GIT_ROOT}/bootstrap-foundation/pull-all.sh  um alle Repos zu holen"
fi

# ---------------------------------------------------------------------------
# 6. requirements.txt + install.sh ausführen (falls vorhanden)
# ---------------------------------------------------------------------------
_head "[5/6] Projekt-Setup"

cd "${LOCAL_DIR}"

if [[ -f requirements.txt ]]; then
  PIP=$(command -v pip3 || command -v pip || true)
  if [[ -n "${PIP}" ]]; then
    _run "pip install -r requirements.txt"
    "${PIP}" install --quiet -r requirements.txt && _ok "Python-Dependencies installiert" || _skip "Einige Dependencies fehlgeschlagen"
  else
    _skip "pip nicht gefunden — requirements.txt übersprungen"
  fi
else
  _skip "keine requirements.txt gefunden"
fi

if [[ -f install.sh ]]; then
  _run "bash install.sh"
  bash install.sh && _ok "install.sh erfolgreich" || _skip "install.sh mit Fehlern beendet"
else
  _skip "kein install.sh gefunden"
fi

# ---------------------------------------------------------------------------
# 7. Fertig-Report
# ---------------------------------------------------------------------------
_head "[6/6] Fertig!"
echo ''
echo "  Projekt:  ${PROJEKT}"
echo "  Lokal:    ${LOCAL_DIR}"
if [[ $GH_AVAILABLE -eq 1 ]]; then
  echo "  Remote:   https://github.com/${GITHUB_USER}/${PROJEKT}"
fi
echo ''
echo '  Nächste Schritte:'
echo "    cd ${LOCAL_DIR}"
echo '    python3 asr/hotkey_listener.py   # (falls ASR-Projekt)'
echo '    gup \"erster commit\"              # (Alias aus dotfiles-macos)'
echo ''

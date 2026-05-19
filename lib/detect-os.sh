#!/bin/sh
# lib/detect-os.sh
# OS- und Package-Manager-Erkennung fuer alle Plattformen
# Source this file: . ./lib/detect-os.sh

detect_os() {
    OS='unknown'
    PKG_MGR='unknown'

    # QNAP: /etc/qnap_ver oder /etc/config/uLinux.conf
    if [ -f /etc/qnap_ver ] || [ -f /etc/config/uLinux.conf ]; then
        OS='qnap'
        PKG_MGR='opkg'
        return
    fi

    # Alpine
    if [ -f /etc/alpine-release ]; then
        OS='alpine'
        PKG_MGR='apk'
        return
    fi

    # Ubuntu / Debian
    if [ -f /etc/debian_version ]; then
        OS='ubuntu'
        PKG_MGR='apt'
        return
    fi

    # macOS
    if [ "$(uname)" = 'Darwin' ]; then
        OS='macos'
        PKG_MGR='brew'
        return
    fi

    # Generic Linux fallback
    if [ "$(uname)" = 'Linux' ]; then
        OS='linux'
        if command -v apt-get >/dev/null 2>&1;  then PKG_MGR='apt'
        elif command -v apk    >/dev/null 2>&1; then PKG_MGR='apk'
        elif command -v dnf    >/dev/null 2>&1; then PKG_MGR='dnf'
        elif command -v yum    >/dev/null 2>&1; then PKG_MGR='yum'
        elif command -v opkg   >/dev/null 2>&1; then PKG_MGR='opkg'
        fi
        return
    fi
}

install_git() {
    if command -v git >/dev/null 2>&1; then
        echo '[git] bereits installiert'
        return 0
    fi
    echo '[git] wird installiert...'
    case "$PKG_MGR" in
        apk)  apk add --no-cache git ;;
        apt)  apt-get update -qq && apt-get install -y git ;;
        brew) brew install git ;;
        opkg) opkg update && opkg install git ;;
        *)    echo '[FEHLER] Unbekannter Paketmanager: $PKG_MGR'; return 1 ;;
    esac
}

install_package() {
    PKG="$1"
    case "$PKG_MGR" in
        apk)  apk add --no-cache "$PKG" ;;
        apt)  apt-get install -y "$PKG" ;;
        brew) brew install "$PKG" ;;
        opkg) opkg install "$PKG" ;;
        *)    echo "[FEHLER] Unbekannter Paketmanager: $PKG_MGR"; return 1 ;;
    esac
}

#!/usr/bin/env bash
# Copyright (c) 2026 Waldemar Scudeller Junior.  Licensed under MIT License
# dashmotd uninstaller — removes units, entry script, bashrc hook, and /opt/dashmotd.

set -euo pipefail

PREFIX="/opt/dashmotd"
UNIT_DIR="/etc/systemd/system"
MOTD_DIR="/etc/update-motd.d"
INSTALL_USER="${SUDO_USER:-${USER:-}}"

log()  { printf '[+] %s\n' "$*"; }
warn() { printf '[!] %s\n' "$*" >&2; }
die()  { printf '[x] %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --user) shift; INSTALL_USER="${1:-}" ;;
        -h|--help)
            echo "Usage: uninstall.sh [--user NAME]"
            exit 0
            ;;
        *) die "unknown option: $1" ;;
    esac
    shift
done

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    if command -v sudo >/dev/null 2>&1; then
        exec sudo --preserve-env=SUDO_USER bash "$0" ${INSTALL_USER:+--user "$INSTALL_USER"}
    else
        die "root privileges required"
    fi
fi

if [[ -d /run/systemd/system ]]; then
    if systemctl list-unit-files dashmotd.timer &>/dev/null; then
        log "stopping dashmotd.timer"
        systemctl disable --now dashmotd.timer 2>/dev/null || true
    fi
    rm -f "$UNIT_DIR/dashmotd.service" "$UNIT_DIR/dashmotd.timer"
    systemctl daemon-reload 2>/dev/null || true
fi

if [[ -e "$MOTD_DIR/50-dashmotd" ]]; then
    log "removing $MOTD_DIR/50-dashmotd"
    rm -f "$MOTD_DIR/50-dashmotd"
fi

# Re-enable stock uname script if we disabled it
if [[ -f "$MOTD_DIR/10-uname" && ! -x "$MOTD_DIR/10-uname" ]]; then
    log "re-enabling $MOTD_DIR/10-uname"
    chmod +x "$MOTD_DIR/10-uname"
fi

if [[ -e /etc/profile.d/zzz-dashmotd.sh ]]; then
    log "removing /etc/profile.d/zzz-dashmotd.sh"
    rm -f /etc/profile.d/zzz-dashmotd.sh
fi

if [[ -f /etc/motd.dashmotd.bak ]]; then
    log "restoring /etc/motd from backup"
    mv /etc/motd.dashmotd.bak /etc/motd
fi

if [[ -n "$INSTALL_USER" && "$INSTALL_USER" != "root" ]]; then
    home="$(getent passwd "$INSTALL_USER" | cut -d: -f6 || true)"
    if [[ -n "$home" && -f "$home/.bashrc.d/21-dashmotd.sh" ]]; then
        log "removing bashrc hook"
        rm -f "$home/.bashrc.d/21-dashmotd.sh"
    fi
fi

if [[ -d "$PREFIX" ]]; then
    log "removing $PREFIX"
    rm -rf "$PREFIX"
fi

log "dashmotd uninstalled"

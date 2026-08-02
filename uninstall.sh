#!/usr/bin/env bash
# dashmotd uninstaller — removes units, entry script, bashrc hooks, and /opt/dashmotd.
#
# Copyright (c) 2026 Waldemar Scudeller Junior.  Licensed under MIT License

set -euo pipefail

PREFIX="/opt/dashmotd"
UNIT_DIR="/etc/systemd/system"
MOTD_DIR="/etc/update-motd.d"

log()  { printf '[+] %s\n' "$*"; }
warn() { printf '[!] %s\n' "$*" >&2; }
die()  { printf '[x] %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            cat <<'EOF'
Usage: uninstall.sh

Removes dashmotd systemd units, MOTD/profile hooks, the system-wide bashrc
hook, any legacy per-user bashrc hooks from older releases, and /opt/dashmotd.

Options:
  -h, --help          Show this help
EOF
            exit 0
            ;;
        *) die "unknown option: $1" ;;
    esac
    shift
done

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    if command -v sudo >/dev/null 2>&1; then
        exec sudo --preserve-env=SUDO_USER bash "$0"
    else
        die "root privileges required"
    fi
fi

# Source helpers before removing $PREFIX (still present at this point).
if [[ -f "$PREFIX/lib/users.sh" ]]; then
    # shellcheck source=/dev/null
    source "$PREFIX/lib/users.sh"
elif [[ -f "$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)/lib/users.sh" ]]; then
    # Fallback: running from a git clone that still has lib/
    # shellcheck source=/dev/null
    source "$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)/lib/users.sh"
else
    warn "lib/users.sh not found — bashrc hook cleanup may be incomplete"
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

if declare -F dashmotd_remove_system_hook >/dev/null 2>&1; then
    dashmotd_remove_system_hook
fi
if declare -F dashmotd_remove_legacy_user_hooks >/dev/null 2>&1; then
    dashmotd_remove_legacy_user_hooks
fi

if [[ -d "$PREFIX" ]]; then
    log "removing $PREFIX"
    rm -rf "$PREFIX"
fi

log "dashmotd uninstalled"

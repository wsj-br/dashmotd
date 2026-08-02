#!/usr/bin/env bash
# Copyright (c) 2026 Waldemar Scudeller Junior.  Licensed under MIT License
# dashmotd uninstaller — removes units, entry script, bashrc hooks, and /opt/dashmotd.

set -euo pipefail

PREFIX="/opt/dashmotd"
UNIT_DIR="/etc/systemd/system"
MOTD_DIR="/etc/update-motd.d"
# Empty = remove bashrc hooks for every human user; --user NAME restricts.
INSTALL_USER=""
USER_SPECIFIED=0

log()  { printf '[+] %s\n' "$*"; }
warn() { printf '[!] %s\n' "$*" >&2; }
die()  { printf '[x] %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --user)
            shift
            INSTALL_USER="${1:-}"
            [[ -n "$INSTALL_USER" ]] || die "--user requires a name"
            USER_SPECIFIED=1
            ;;
        -h|--help)
            cat <<'EOF'
Usage: uninstall.sh [--user NAME]

Options:
  --user NAME         Restrict bashrc hook removal to this user
                      (default: every human user on the system)
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
        extra_args=()
        (( USER_SPECIFIED )) && extra_args+=(--user "$INSTALL_USER")
        exec sudo --preserve-env=SUDO_USER bash "$0" "${extra_args[@]}"
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

if declare -F dashmotd_remove_user_hook >/dev/null 2>&1; then
    if (( USER_SPECIFIED )); then
        home="$(getent passwd "$INSTALL_USER" | cut -d: -f6 || true)"
        dashmotd_remove_user_hook "$INSTALL_USER" "$home"
    else
        while IFS=: read -r _uname _uhome; do
            [[ -n "$_uname" ]] || continue
            dashmotd_remove_user_hook "$_uname" "$_uhome"
        done < <(dashmotd_list_target_users)
    fi
fi

if [[ -d "$PREFIX" ]]; then
    log "removing $PREFIX"
    rm -rf "$PREFIX"
fi

log "dashmotd uninstalled"

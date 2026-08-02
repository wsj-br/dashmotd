#!/usr/bin/env bash
# Copyright (c) 2026 Waldemar Scudeller Junior.  Licensed under MIT License
# dashmotd updater — refresh an existing /opt/dashmotd install.
# Usage:
#   sudo /opt/dashmotd/update.sh
#   sudo ./update.sh                  # from a git clone
#   DASHMOTD_REF=main sudo ./update.sh
#
# Preserves /opt/dashmotd/config and cache/. Replaces scripts, units, and hooks.
#
# Environment:
#   DASHMOTD_REPO     GitHub repo URL (default: https://github.com/wsj-br/dashmotd)
#   DASHMOTD_REF      git ref / branch / tag for tarball (default: main)
#   DASHMOTD_TARBALL  local .tar.gz path or URL (overrides DASHMOTD_REPO)
#   DASHMOTD_PREFIX   install prefix (default: /opt/dashmotd)

set -euo pipefail

PREFIX="${DASHMOTD_PREFIX:-/opt/dashmotd}"
UNIT_DIR="/etc/systemd/system"
MOTD_DIR="/etc/update-motd.d"
# Empty = refresh bashrc hooks for every human user; --user NAME restricts.
INSTALL_USER=""
USER_SPECIFIED=0

DASHMOTD_REPO="${DASHMOTD_REPO:-https://github.com/wsj-br/dashmotd}"
DASHMOTD_REF="${DASHMOTD_REF:-main}"

log()  { printf '[+] %s\n' "$*"; }
warn() { printf '[!] %s\n' "$*" >&2; }
die()  { printf '[x] %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<'EOF'
Usage: update.sh [options]

Refresh an existing dashmotd installation. Keeps config and cache; replaces
binaries, section scripts, systemd units, and MOTD hooks from upstream (or a
local clone / tarball).

Options:
  --user NAME         Restrict bashrc hook refresh to this user
                      (default: every human user on the system)
  -h, --help          Show this help

Environment:
  DASHMOTD_REPO       GitHub repo to fetch (default: https://github.com/wsj-br/dashmotd)
  DASHMOTD_REF        Branch/tag/ref for the tarball (default: main)
  DASHMOTD_TARBALL    Local path or URL of a .tar.gz (overrides repo)
  DASHMOTD_PREFIX     Install prefix (default: /opt/dashmotd)
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --user)
            shift
            INSTALL_USER="${1:-}"
            [[ -n "$INSTALL_USER" ]] || die "--user requires a name"
            USER_SPECIFIED=1
            ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown option: $1" ;;
    esac
    shift
done

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    self="${BASH_SOURCE[0]:-}"
    if [[ -z "$self" || "$self" == "/dev/stdin" || "$self" == /dev/fd/* ]]; then
        die "root privileges required — re-run as: sudo $0"
    fi
    command -v sudo >/dev/null 2>&1 || die "root privileges required"
    extra_args=()
    (( USER_SPECIFIED )) && extra_args+=(--user "$INSTALL_USER")
    exec sudo --preserve-env=DASHMOTD_REPO,DASHMOTD_REF,DASHMOTD_TARBALL,DASHMOTD_PREFIX,SUDO_USER \
        bash "$self" "${extra_args[@]}"
fi

[[ -d "$PREFIX" && -x "$PREFIX/bin/dashmotd-render" ]] \
    || die "no dashmotd install found at $PREFIX — run install.sh first"

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
BOOTSTRAP_TMP=""

# Resolve update source: local git clone, else download tarball.
# Never treat the live PREFIX tree as the source (that would be a no-op).
resolve_source() {
    if [[ "$HERE" != "$PREFIX" \
        && -f "$HERE/config" \
        && -d "$HERE/sections" \
        && -x "$HERE/bin/dashmotd-render" ]]; then
        log "using local source tree $HERE" >&2
        printf '%s\n' "$HERE"
        return 0
    fi

    local tmp tarball_url extract_dir repo
    tmp="$(mktemp -d)"
    BOOTSTRAP_TMP="$tmp"

    if [[ -n "${DASHMOTD_TARBALL:-}" ]]; then
        if [[ -f "$DASHMOTD_TARBALL" ]]; then
            log "using local tarball $DASHMOTD_TARBALL" >&2
            tar -xzf "$DASHMOTD_TARBALL" -C "$tmp"
        else
            log "downloading tarball $DASHMOTD_TARBALL" >&2
            if command -v curl >/dev/null 2>&1; then
                curl -fsSL "$DASHMOTD_TARBALL" | tar -xz -C "$tmp"
            else
                wget -qO - "$DASHMOTD_TARBALL" | tar -xz -C "$tmp"
            fi
        fi
    else
        repo="${DASHMOTD_REPO%/}"
        tarball_url="${repo}/archive/refs/heads/${DASHMOTD_REF}.tar.gz"
        log "downloading ${tarball_url}" >&2
        if command -v curl >/dev/null 2>&1; then
            if ! curl -fsSL "$tarball_url" | tar -xz -C "$tmp"; then
                tarball_url="${repo}/archive/refs/tags/${DASHMOTD_REF}.tar.gz"
                log "retrying ${tarball_url}" >&2
                curl -fsSL "$tarball_url" | tar -xz -C "$tmp"
            fi
        else
            wget -qO - "$tarball_url" | tar -xz -C "$tmp"
        fi
    fi

    extract_dir="$(find "$tmp" -mindepth 1 -maxdepth 1 -type d | head -n1)"
    [[ -n "$extract_dir" && -f "$extract_dir/config" ]] \
        || die "downloaded archive does not look like dashmotd"
    printf '%s\n' "$extract_dir"
}

cleanup() {
    if [[ -n "${BOOTSTRAP_TMP:-}" && -d "${BOOTSTRAP_TMP:-}" ]]; then
        rm -rf "$BOOTSTRAP_TMP"
    fi
}
trap cleanup EXIT

SRC="$(resolve_source)"
log "source tree: $SRC"
log "updating $PREFIX"

# shellcheck source=/dev/null
source "$SRC/lib/users.sh"

mkdir -p "$PREFIX"/{bin,lib,sections,cache,cache/sections,update-motd.d,systemd}

# Preserve site config; only install a default if missing.
if [[ -f "$PREFIX/config" ]]; then
    log "keeping existing $PREFIX/config"
else
    log "installing default config (none present)"
    install -m 0644 "$SRC/config" "$PREFIX/config"
fi

install -m 0644 "$SRC/LICENSE" "$PREFIX/LICENSE" 2>/dev/null || true
install -m 0644 "$SRC/README.md" "$PREFIX/README.md" 2>/dev/null || true
install -m 0755 "$SRC"/bin/* "$PREFIX/bin/"
install -m 0644 "$SRC"/lib/*.sh "$PREFIX/lib/"
chmod 0755 "$PREFIX/lib/cpu.sh"
# Replace section scripts; drop retired names from older releases.
install -m 0755 "$SRC"/sections/* "$PREFIX/sections/"
rm -f "$PREFIX/sections/last_execution.sh"
install -m 0755 "$SRC/update-motd.d/50-dashmotd" "$PREFIX/update-motd.d/50-dashmotd"
install -m 0644 "$SRC/systemd/dashmotd.service" "$PREFIX/systemd/dashmotd.service"
install -m 0644 "$SRC/systemd/dashmotd.timer" "$PREFIX/systemd/dashmotd.timer"
install -m 0755 "$SRC/install.sh" "$PREFIX/install.sh"
install -m 0755 "$SRC/uninstall.sh" "$PREFIX/uninstall.sh" 2>/dev/null || true
install -m 0755 "$SRC/update.sh" "$PREFIX/update.sh"

if [[ -d "$MOTD_DIR" ]]; then
    log "updating $MOTD_DIR/50-dashmotd"
    install -m 0755 "$PREFIX/update-motd.d/50-dashmotd" "$MOTD_DIR/50-dashmotd"
fi

if [[ -d /etc/profile.d && -e /etc/profile.d/zzz-dashmotd.sh ]]; then
    log "refreshing /etc/profile.d/zzz-dashmotd.sh"
    cat > /etc/profile.d/zzz-dashmotd.sh <<'PROFILE'
# dashmotd — render dashboard (live + collected cache) on login shells
if [ -x /opt/dashmotd/bin/dashmotd-render ]; then
    /opt/dashmotd/bin/dashmotd-render
fi
PROFILE
    chmod 0644 /etc/profile.d/zzz-dashmotd.sh
fi

if [[ -d /run/systemd/system ]]; then
    log "updating systemd units"
    install -m 0644 "$PREFIX/systemd/dashmotd.service" "$UNIT_DIR/dashmotd.service"
    install -m 0644 "$PREFIX/systemd/dashmotd.timer" "$UNIT_DIR/dashmotd.timer"
    systemctl daemon-reload
    systemctl enable --now dashmotd.timer
fi

# Refresh bashrc hooks for non-login interactive shells
if (( USER_SPECIFIED )); then
    home="$(getent passwd "$INSTALL_USER" | cut -d: -f6 || true)"
    dashmotd_install_user_hook "$INSTALL_USER" "$home"
else
    while IFS=: read -r _uname _uhome; do
        [[ -n "$_uname" ]] || continue
        dashmotd_install_user_hook "$_uname" "$_uhome"
    done < <(dashmotd_list_target_users)
fi

log "generating hostname banner"
"$PREFIX/bin/dashmotd-banner" >/dev/null 2>&1 || true
log "collecting cached section data"
"$PREFIX/bin/dashmotd-collect"
log "rendering dashboard"
"$PREFIX/bin/dashmotd-render" >/dev/null 2>&1 || true

log "update complete"
log "preview: $PREFIX/bin/dashmotd-render"

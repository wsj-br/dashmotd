#!/usr/bin/env bash
# dashmotd updater — refresh an existing /opt/dashmotd install.
# Usage:
#   sudo /opt/dashmotd/update.sh
#   sudo /opt/dashmotd/update.sh --force-new-config
#   sudo /opt/dashmotd/update.sh -f
#   sudo ./update.sh                  # from a git clone
#   DASHMOTD_REF=main sudo ./update.sh
#
# Preserves cache/. Site config is kept by default; when it differs from the
# packaged file, prompts (apt-style) or honors DASHMOTD_CONFIG_ACTION /
# --force-new-config. Replaces scripts, units, and hooks.
#
# Environment:
#   DASHMOTD_REPO     GitHub repo URL (default: https://github.com/wsj-br/dashmotd)
#   DASHMOTD_REF      git ref / branch / tag / SHA (default: main)
#   DASHMOTD_TARBALL  local .tar.gz path or URL (overrides DASHMOTD_REPO)
#   DASHMOTD_PREFIX   install prefix (default: /opt/dashmotd)
#   DASHMOTD_CONFIG_ACTION  keep|replace — force site-config conflict choice
#
# Remote updates fetch via the GitHub tarball API (api.github.com/.../tarball/...)
# so they are not subject to raw.githubusercontent.com CDN lag.
#
# Copyright (c) 2026 Waldemar Scudeller Junior.  Licensed under MIT License

set -euo pipefail

PREFIX="${DASHMOTD_PREFIX:-/opt/dashmotd}"
UNIT_DIR="/etc/systemd/system"
MOTD_DIR="/etc/update-motd.d"

DASHMOTD_REPO="${DASHMOTD_REPO:-https://github.com/wsj-br/dashmotd}"
DASHMOTD_REF="${DASHMOTD_REF:-main}"
FORCE_NEW_CONFIG=0

log()  { printf '[+] %s\n' "$*"; }
warn() { printf '[!] %s\n' "$*" >&2; }
die()  { printf '[x] %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<'EOF'
Usage: update.sh [options]

Refresh an existing dashmotd installation. Keeps cache; replaces binaries,
section scripts, systemd units, and MOTD hooks from upstream (or a local clone
/ tarball). When site config differs from packaged defaults, prompts apt-style
(default: keep existing).

Options:
  -f, --force-new-config
                      Replace site config with the packaged version (saves
                      previous as config.old; skips the conflict prompt)
  -h, --help          Show this help

Environment:
  DASHMOTD_REPO           GitHub repo to fetch (default: https://github.com/wsj-br/dashmotd)
  DASHMOTD_REF            Branch/tag/ref for the tarball (default: main)
  DASHMOTD_TARBALL        Local path or URL of a .tar.gz (overrides repo)
  DASHMOTD_PREFIX         Install prefix (default: /opt/dashmotd)
  DASHMOTD_CONFIG_ACTION  keep|replace — force config conflict choice (skip prompt)
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -f|--force-new-config) FORCE_NEW_CONFIG=1 ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown option: $1" ;;
    esac
    shift
done

if (( FORCE_NEW_CONFIG )); then
    DASHMOTD_CONFIG_ACTION=replace
fi

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    self="${BASH_SOURCE[0]:-}"
    if [[ -z "$self" || "$self" == "/dev/stdin" || "$self" == /dev/fd/* ]]; then
        die "root privileges required — re-run as: sudo $0"
    fi
    command -v sudo >/dev/null 2>&1 || die "root privileges required"
    extra_args=()
    (( FORCE_NEW_CONFIG )) && extra_args+=(--force-new-config)
    exec sudo --preserve-env=DASHMOTD_REPO,DASHMOTD_REF,DASHMOTD_TARBALL,DASHMOTD_PREFIX,DASHMOTD_CONFIG_ACTION,SUDO_USER \
        bash "$self" "${extra_args[@]}"
fi

[[ -d "$PREFIX" && -x "$PREFIX/bin/dashmotd-render" ]] \
    || die "no dashmotd install found at $PREFIX — run install.sh first"

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

# Create bootstrap temp in the parent so cleanup survives command substitution.
BOOTSTRAP_TMP="$(mktemp -d)"
cleanup() {
    if [[ -n "${BOOTSTRAP_TMP:-}" && -d "${BOOTSTRAP_TMP:-}" ]]; then
        rm -rf "$BOOTSTRAP_TMP"
    fi
}
trap cleanup EXIT

# Extract owner/repo from a github.com URL (https or ssh).
github_slug() {
    local repo="${1%/}"
    repo="${repo%.git}"
    if [[ "$repo" =~ github\.com[:/]([^/]+)/([^/]+)$ ]]; then
        printf '%s/%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
        return 0
    fi
    return 1
}

# Download repo tree via GitHub's tarball API (codeload; no raw-CDN lag).
# Accepts branch, tag, or commit SHA in DASHMOTD_REF.
download_github_tarball() {
    local dest="$1" slug tarball_url
    slug="$(github_slug "$DASHMOTD_REPO")" \
        || die "DASHMOTD_REPO must be a github.com URL (got: $DASHMOTD_REPO)"
    tarball_url="https://api.github.com/repos/${slug}/tarball/${DASHMOTD_REF}"
    log "downloading ${tarball_url}" >&2
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL \
            -H "Accept: application/vnd.github+json" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            "$tarball_url" | tar -xz -C "$dest"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO - \
            --header="Accept: application/vnd.github+json" \
            --header="X-GitHub-Api-Version: 2022-11-28" \
            "$tarball_url" | tar -xz -C "$dest"
    else
        die "need curl or wget to download updates"
    fi
}

# Resolve update source: local git clone, else download tarball.
# $1 = parent-owned temp dir used when downloading.
# Never treat the live PREFIX tree as the source (that would be a no-op).
resolve_source() {
    local tmp="$1" extract_dir
    if [[ "$HERE" != "$PREFIX" \
        && -f "$HERE/config" \
        && -d "$HERE/sections" \
        && -x "$HERE/bin/dashmotd-render" ]]; then
        log "using local source tree $HERE" >&2
        printf '%s\n' "$HERE"
        return 0
    fi

    [[ -n "$tmp" && -d "$tmp" ]] || die "bootstrap temp directory missing"

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
        download_github_tarball "$tmp"
    fi

    extract_dir="$(find "$tmp" -mindepth 1 -maxdepth 1 -type d | head -n1)"
    [[ -n "$extract_dir" && -f "$extract_dir/config" ]] \
        || die "downloaded archive does not look like dashmotd"
    printf '%s\n' "$extract_dir"
}

SRC="$(resolve_source "$BOOTSTRAP_TMP")"
log "source tree: $SRC"
log "updating $PREFIX"

# shellcheck source=/dev/null
source "$SRC/lib/users.sh"
# shellcheck source=/dev/null
source "$SRC/lib/site_config.sh"

mkdir -p "$PREFIX"/{bin,lib,sections,cache,cache/sections,update-motd.d,systemd,share/figlet}

dashmotd_install_site_config "$SRC/config" "$PREFIX"

install -m 0644 "$SRC/LICENSE" "$PREFIX/LICENSE" 2>/dev/null || true
install -m 0644 "$SRC/README.md" "$PREFIX/README.md" 2>/dev/null || true
if [[ -d "$SRC/docs" ]]; then
    mkdir -p "$PREFIX/docs"
    install -m 0644 "$SRC"/docs/*.md "$PREFIX/docs/" 2>/dev/null || true
fi
install -m 0755 "$SRC"/bin/* "$PREFIX/bin/"
install -m 0644 "$SRC"/lib/*.sh "$PREFIX/lib/"
chmod 0755 "$PREFIX/lib/cpu.sh"
if [[ -d "$SRC/share/figlet" ]]; then
    install -m 0644 "$SRC"/share/figlet/* "$PREFIX/share/figlet/"
fi
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
# dashmotd — render dashboard (live + collected cache) on interactive login shells
# DASHMOTD_AUTO=1: show at most once per tty/session (skip sudo -i / nested shells)
case $- in
    *i*) ;;
    *) return 0 ;;
esac
if [ -n "${DASHMOTD_SHOWN:-}" ]; then
    return 0
fi
if [ -x /opt/dashmotd/bin/dashmotd-render ]; then
    DASHMOTD_AUTO=1 /opt/dashmotd/bin/dashmotd-render
    DASHMOTD_SHOWN=1
    export DASHMOTD_SHOWN
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

# Migrate: strip legacy per-user hooks, then refresh the system-wide hook
log "removing legacy per-user bashrc hooks (if any)"
dashmotd_remove_legacy_user_hooks
dashmotd_install_system_hook >/dev/null || true

log "generating hostname banner"
"$PREFIX/bin/dashmotd-banner" >/dev/null 2>&1 || true
log "collecting cached section data"
"$PREFIX/bin/dashmotd-collect"
log "rendering dashboard"
"$PREFIX/bin/dashmotd-render" >/dev/null 2>&1 || true

log "update complete"
log "preview: $PREFIX/bin/dashmotd-render"

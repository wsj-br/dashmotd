#!/usr/bin/env bash
# dashmotd installer — clean install only.
# Usage:
#   sudo ./install.sh [--no-static-motd]
#   curl -fsSL https://raw.githubusercontent.com/<owner>/dashmotd/main/install.sh | sudo bash
#
# Environment:
#   DASHMOTD_REPO     GitHub repo URL (default: https://github.com/wsj-br/dashmotd)
#   DASHMOTD_REF      git ref / branch / tag for tarball (default: main)
#   DASHMOTD_TARBALL  local .tar.gz path or URL (overrides DASHMOTD_REPO)
#   DASHMOTD_CONFIG_ACTION  keep|replace — force site-config conflict choice (default: prompt / keep)
#
# Copyright (c) 2026 Waldemar Scudeller Junior.  Licensed under MIT License

set -euo pipefail

PREFIX="/opt/dashmotd"
UNIT_DIR="/etc/systemd/system"
MOTD_DIR="/etc/update-motd.d"
# Default: backup /etc/motd, blank it (pam would otherwise print it after
# the dynamic MOTD), and show the backup before the dashboard via 50-dashmotd.
SHOW_STATIC=1

# Default repo for curl|bash bootstrap (must match the published GitHub repo).
DASHMOTD_REPO="${DASHMOTD_REPO:-https://github.com/wsj-br/dashmotd}"
DASHMOTD_REF="${DASHMOTD_REF:-main}"

log()  { printf '[+] %s\n' "$*"; }
warn() { printf '[!] %s\n' "$*" >&2; }
die()  { printf '[x] %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<'EOF'
Usage: install.sh [options]

Options:
  --no-static-motd    Do not show the old /etc/motd text before the dashboard
                      (still blanks /etc/motd so pam does not print it after)
  -h, --help          Show this help

Environment:
  DASHMOTD_REPO           GitHub repo to fetch when bootstrapping (curl | bash)
  DASHMOTD_REF            Branch/tag/ref for the tarball (default: main)
  DASHMOTD_TARBALL        Local path or URL of a release tarball (overrides repo)
  DASHMOTD_CONFIG_ACTION  keep|replace — force config conflict choice (skip prompt)
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-static-motd) SHOW_STATIC=0 ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown option: $1" ;;
    esac
    shift
done

# Re-exec as root if needed.
# Piped installs (curl | bash) cannot be re-read after parsing, so require sudo:
#   curl -fsSL .../install.sh | sudo bash
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    self="${BASH_SOURCE[0]:-}"
    if [[ -z "$self" || "$self" == "/dev/stdin" || "$self" == /dev/fd/* ]]; then
        die "root privileges required — re-run as: curl -fsSL <url> | sudo bash"
    fi
    if ! command -v sudo >/dev/null 2>&1; then
        die "root privileges required"
    fi
    extra_args=()
    (( ! SHOW_STATIC )) && extra_args+=(--no-static-motd)
    exec sudo --preserve-env=DASHMOTD_REPO,DASHMOTD_REF,DASHMOTD_TARBALL,DASHMOTD_CONFIG_ACTION,SUDO_USER \
        bash "$self" "${extra_args[@]}"
fi

# Resolve source tree: local checkout, or bootstrap from tarball.
# $1 = parent-owned temp dir used when downloading (never created in a subshell).
# Prints ONLY the absolute path on stdout; all messages go to stderr.
resolve_source() {
    local tmp="$1" here self tarball_url extract_dir
    # When piped through curl, BASH_SOURCE may be empty or /dev/fd/*
    self="${BASH_SOURCE[0]:-}"
    if [[ -n "$self" && -f "$self" && "$self" != "/dev/stdin" && "$self" != /dev/fd/* ]]; then
        here="$(cd "$(dirname "$(readlink -f "$self")")" && pwd)"
        if [[ -f "$here/config" && -d "$here/sections" && -x "$here/bin/dashmotd-render" ]]; then
            printf '%s\n' "$here"
            return 0
        fi
    fi

    # Bootstrap: download tarball into the caller-provided temp directory
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
        # GitHub archive URL: https://github.com/owner/repo/archive/refs/heads/main.tar.gz
        local repo="${DASHMOTD_REPO%/}"
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
    [[ -n "$extract_dir" && -f "$extract_dir/config" ]] || die "downloaded archive does not look like dashmotd"
    printf '%s\n' "$extract_dir"
}

# Create bootstrap temp in the parent so cleanup survives command substitution.
BOOTSTRAP_TMP="$(mktemp -d)"
# shellcheck disable=SC2064
trap 'rm -rf "$BOOTSTRAP_TMP"' EXIT
SRC="$(resolve_source "$BOOTSTRAP_TMP")"
log "source tree: $SRC"

# shellcheck source=/dev/null
source "$SRC/lib/distro.sh"
# shellcheck source=/dev/null
source "$SRC/lib/users.sh"
dashmotd_detect_os
log "detected OS family=${DASHMOTD_OS_FAMILY} pkg=${DASHMOTD_PKG_MANAGER}"

# --- dependency checks -------------------------------------------------------
need_cmd() {
    local c="$1"
    command -v "$c" >/dev/null 2>&1 || return 1
}

missing=()
for c in bash column paste free awk sed grep mktemp; do
    need_cmd "$c" || missing+=("$c")
done
# Recommended (sections degrade gracefully without them)
optional_missing=()
for c in smartctl openssl figlet; do
    need_cmd "$c" || optional_missing+=("$c")
done
# Need at least one HTTP client
if ! need_cmd curl && ! need_cmd wget; then
    optional_missing+=("curl|wget")
fi
need_cmd docker || optional_missing+=("docker")
# Arch: checkupdates improves pacman upgrade counts
if [[ "$DASHMOTD_PKG_MANAGER" == "pacman" ]] && ! need_cmd checkupdates; then
    optional_missing+=("checkupdates(pacman-contrib)")
fi

if (( ${#missing[@]} > 0 )); then
    case "$DASHMOTD_PKG_MANAGER" in
        apt)    hint="apt-get install -y bsdextrautils util-linux procps" ;;
        dnf)    hint="dnf install -y util-linux procps-ng" ;;
        yum)    hint="yum install -y util-linux procps-ng" ;;
        pacman) hint="pacman -S --needed util-linux procps-ng" ;;
        zypper) hint="zypper install -y util-linux procps" ;;
        *)      hint="install: util-linux procps column paste" ;;
    esac
    die "missing required commands: ${missing[*]}  (try: ${hint})"
fi
if (( ${#optional_missing[@]} > 0 )); then
    warn "optional tools missing (sections will degrade): ${optional_missing[*]}"
    case "$DASHMOTD_PKG_MANAGER" in
        apt)
            warn "hint: apt-get install -y smartmontools openssl wget curl figlet toilet-fonts"
            ;;
        dnf|yum)
            warn "hint: ${DASHMOTD_PKG_MANAGER} install -y smartmontools openssl wget curl figlet"
            ;;
        pacman)
            warn "hint: pacman -S --needed smartmontools openssl wget curl figlet pacman-contrib"
            ;;
        zypper)
            warn "hint: zypper install -y smartmontools openssl wget curl figlet"
            ;;
    esac
fi

# --- install files -----------------------------------------------------------
log "installing to $PREFIX"
mkdir -p "$PREFIX"/{bin,lib,sections,cache,update-motd.d,systemd}
# shellcheck source=/dev/null
source "$SRC/lib/site_config.sh"
dashmotd_install_site_config "$SRC/config" "$PREFIX"
install -m 0644 "$SRC/LICENSE" "$PREFIX/LICENSE" 2>/dev/null || true
install -m 0644 "$SRC/README.md" "$PREFIX/README.md" 2>/dev/null || true
install -m 0755 "$SRC"/bin/* "$PREFIX/bin/"
install -m 0644 "$SRC"/lib/*.sh "$PREFIX/lib/"
# cpu.sh must be executable
chmod 0755 "$PREFIX/lib/cpu.sh"
install -m 0755 "$SRC"/sections/* "$PREFIX/sections/"
install -m 0755 "$SRC/update-motd.d/50-dashmotd" "$PREFIX/update-motd.d/50-dashmotd"
install -m 0644 "$SRC/systemd/dashmotd.service" "$PREFIX/systemd/dashmotd.service"
install -m 0644 "$SRC/systemd/dashmotd.timer" "$PREFIX/systemd/dashmotd.timer"
install -m 0755 "$SRC/install.sh" "$PREFIX/install.sh"
install -m 0755 "$SRC/uninstall.sh" "$PREFIX/uninstall.sh" 2>/dev/null || true
install -m 0755 "$SRC/update.sh" "$PREFIX/update.sh" 2>/dev/null || true

# --- display path (distro-aware) ---------------------------------------------
# Debian/Ubuntu/Raspberry Pi: /etc/update-motd.d + pam_motd
# RHEL/Oracle/Arch/others without update-motd.d: /etc/profile.d
# Non-login interactive shells: system-wide /etc/bash.bashrc or /etc/bashrc
USED_UPDATE_MOTD=0
USED_PROFILE_D=0

if [[ -d "$MOTD_DIR" ]]; then
    log "installing $MOTD_DIR/50-dashmotd (update-motd)"
    install -m 0755 "$PREFIX/update-motd.d/50-dashmotd" "$MOTD_DIR/50-dashmotd"
    USED_UPDATE_MOTD=1
    if [[ -x "$MOTD_DIR/10-uname" ]]; then
        log "disabling $MOTD_DIR/10-uname (kernel shown in dashboard)"
        chmod -x "$MOTD_DIR/10-uname"
    fi
else
    warn "$MOTD_DIR not present — skipping update-motd integration"
fi

# profile.d for login shells on distros without update-motd.d
if (( ! USED_UPDATE_MOTD )) && [[ -d /etc/profile.d ]]; then
    log "installing /etc/profile.d/zzz-dashmotd.sh (login shells)"
    cat > /etc/profile.d/zzz-dashmotd.sh <<'PROFILE'
# dashmotd — render dashboard (live + collected cache) on interactive login shells
case $- in
    *i*) ;;
    *) return 0 ;;
esac
if [ -x /opt/dashmotd/bin/dashmotd-render ]; then
    /opt/dashmotd/bin/dashmotd-render
fi
PROFILE
    chmod 0644 /etc/profile.d/zzz-dashmotd.sh
    USED_PROFILE_D=1
fi

# PAM sanity check (informative)
for pam in /etc/pam.d/sshd /etc/pam.d/login; do
    if [[ -f "$pam" ]] && ! grep -q 'pam_motd' "$pam"; then
        warn "$pam has no pam_motd entry — relying on profile.d / system bashrc hook"
    fi
done

# Systemd units
if [[ -d /run/systemd/system ]]; then
    log "installing systemd units"
    install -m 0644 "$PREFIX/systemd/dashmotd.service" "$UNIT_DIR/dashmotd.service"
    install -m 0644 "$PREFIX/systemd/dashmotd.timer" "$UNIT_DIR/dashmotd.timer"
    systemctl daemon-reload
    systemctl enable --now dashmotd.timer
else
    warn "systemd not detected; install a cron job that runs $PREFIX/bin/dashmotd-collect"
fi

# Banner + initial collect + render
log "generating hostname banner"
"$PREFIX/bin/dashmotd-banner" >/dev/null
log "collecting cached section data"
"$PREFIX/bin/dashmotd-collect"
log "rendering initial dashboard"
"$PREFIX/bin/dashmotd-render" >/dev/null

# Remove per-user hooks left by older releases, then install system-wide hook
# for non-login interactive shells (/etc/bash.bashrc or /etc/bashrc).
log "removing legacy per-user bashrc hooks (if any)"
dashmotd_remove_legacy_user_hooks
dashmotd_install_system_hook >/dev/null || true

# Move static /etc/motd before the dashboard (pam prints it after dynamic MOTD).
# Backup + blank so the text is not duplicated after dashmotd.
if [[ -s /etc/motd ]]; then
    if [[ ! -e /etc/motd.dashmotd.bak ]]; then
        log "backing up /etc/motd -> /etc/motd.dashmotd.bak"
        cp -a /etc/motd /etc/motd.dashmotd.bak
    fi
    log "blanking /etc/motd (shown before dashboard via 50-dashmotd when enabled)"
    : > /etc/motd
elif [[ ! -e /etc/motd.dashmotd.bak ]]; then
    # Ensure the file exists so pam_motd has a harmless empty static MOTD
    : > /etc/motd 2>/dev/null || true
fi

if (( SHOW_STATIC )) && [[ -s /etc/motd.dashmotd.bak ]]; then
    log "enabling static MOTD preamble before dashboard"
    touch "$PREFIX/show-static-motd"
else
    rm -f "$PREFIX/show-static-motd"
fi

if (( USED_UPDATE_MOTD )) && command -v run-parts >/dev/null 2>&1; then
    log "done. Preview with: run-parts /etc/update-motd.d/"
else
    log "done. Preview with: /opt/dashmotd/bin/dashmotd-render"
fi
log "Timer status: systemctl list-timers dashmotd.timer"

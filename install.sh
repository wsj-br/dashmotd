#!/usr/bin/env bash
# Copyright (c) 2026 Waldemar Scudeller Junior.  Licensed under MIT License
# dashmotd installer — clean install only.
# Usage:
#   sudo ./install.sh [--user NAME] [--no-static-motd]
#   curl -fsSL https://raw.githubusercontent.com/<owner>/dashmotd/main/install.sh | sudo bash
#
# Environment:
#   DASHMOTD_REPO     GitHub repo URL (default: https://github.com/wsj/dashmotd)
#   DASHMOTD_REF      git ref / branch / tag for tarball (default: main)
#   DASHMOTD_TARBALL  local .tar.gz path or URL (overrides DASHMOTD_REPO)

set -euo pipefail

PREFIX="/opt/dashmotd"
UNIT_DIR="/etc/systemd/system"
MOTD_DIR="/etc/update-motd.d"
INSTALL_USER="${SUDO_USER:-${USER:-}}"
CLEAR_STATIC=0

DASHMOTD_REPO="${DASHMOTD_REPO:-https://github.com/wsj/dashmotd}"
DASHMOTD_REF="${DASHMOTD_REF:-main}"

log()  { printf '[+] %s\n' "$*"; }
warn() { printf '[!] %s\n' "$*" >&2; }
die()  { printf '[x] %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<'EOF'
Usage: install.sh [options]

Options:
  --user NAME         Install bashrc hook for this user (default: $SUDO_USER)
  --no-static-motd    Blank /etc/motd (backed up first)
  -h, --help          Show this help

Environment:
  DASHMOTD_REPO       GitHub repo to fetch when bootstrapping (curl | bash)
  DASHMOTD_REF        Branch/tag/ref for the tarball (default: main)
  DASHMOTD_TARBALL    Local path or URL of a release tarball (overrides repo)
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --user) shift; INSTALL_USER="${1:-}"; [[ -n "$INSTALL_USER" ]] || die "--user requires a name" ;;
        --no-static-motd) CLEAR_STATIC=1 ;;
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
    [[ -n "$INSTALL_USER" ]] && extra_args+=(--user "$INSTALL_USER")
    (( CLEAR_STATIC )) && extra_args+=(--no-static-motd)
    exec sudo --preserve-env=DASHMOTD_REPO,DASHMOTD_REF,DASHMOTD_TARBALL,SUDO_USER \
        bash "$self" "${extra_args[@]}"
fi

# When invoked via sudo without an explicit --user, keep the calling user
if [[ -z "${INSTALL_USER}" || "${INSTALL_USER}" == "root" ]]; then
    if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
        INSTALL_USER="$SUDO_USER"
    fi
fi

# Resolve source tree: local checkout, or bootstrap from tarball.
# Prints ONLY the absolute path on stdout; all messages go to stderr.
resolve_source() {
    local here self
    # When piped through curl, BASH_SOURCE may be empty or /dev/fd/*
    self="${BASH_SOURCE[0]:-}"
    if [[ -n "$self" && -f "$self" && "$self" != "/dev/stdin" && "$self" != /dev/fd/* ]]; then
        here="$(cd "$(dirname "$(readlink -f "$self")")" && pwd)"
        if [[ -f "$here/config" && -d "$here/sections" && -x "$here/bin/dashmotd-render" ]]; then
            printf '%s\n' "$here"
            return 0
        fi
    fi

    # Bootstrap: download tarball into a temp directory
    local tmp tarball_url extract_dir
    tmp="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '$tmp'" EXIT

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
    # Disable cleanup trap — caller will use extract_dir; keep tmp until install finishes
    trap - EXIT
    # Export for later cleanup
    BOOTSTRAP_TMP="$tmp"
    printf '%s\n' "$extract_dir"
}

SRC="$(resolve_source)"
log "source tree: $SRC"

# shellcheck source=/dev/null
source "$SRC/lib/distro.sh"
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
install -m 0644 "$SRC/config" "$PREFIX/config"
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

# --- display path (distro-aware) ---------------------------------------------
# Debian/Ubuntu/Raspberry Pi: /etc/update-motd.d + pam_motd
# RHEL/Oracle/Arch/others without update-motd.d: /etc/profile.d + bashrc hook
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
# dashmotd — render dashboard (live + collected cache) on login shells
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
        warn "$pam has no pam_motd entry — relying on profile.d / bashrc hook"
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

# Bashrc hook for non-login interactive shells
if [[ -n "$INSTALL_USER" && "$INSTALL_USER" != "root" ]]; then
    home="$(getent passwd "$INSTALL_USER" | cut -d: -f6 || true)"
    if [[ -n "$home" && -d "$home" ]]; then
        hook_dir="$home/.bashrc.d"
        mkdir -p "$hook_dir"
        hook="$hook_dir/21-dashmotd.sh"
        log "installing bashrc hook $hook"
        cat > "$hook" <<'HOOK'
# dashmotd — render dashboard in non-login interactive shells only
# (login shells already get it via pam_motd / update-motd.d)
if [[ $- == *i* ]] && ! shopt -q login_shell; then
    if [[ -x /opt/dashmotd/bin/dashmotd-render ]]; then
        /opt/dashmotd/bin/dashmotd-render
    fi
fi
HOOK
        chown "$INSTALL_USER:" "$hook" 2>/dev/null || true
        # Ensure .bashrc sources ~/.bashrc.d if not already
        bashrc="$home/.bashrc"
        if [[ -f "$bashrc" ]] && ! grep -q 'bashrc.d' "$bashrc"; then
            log "appending ~/.bashrc.d loader to $bashrc"
            cat >> "$bashrc" <<'RC'

# dashmotd: load interactive snippets
if [ -d ~/.bashrc.d ]; then
    for _rc_file in ~/.bashrc.d/*.sh; do
        [ -r "$_rc_file" ] && . "$_rc_file"
    done
    unset _rc_file
fi
RC
            chown "$INSTALL_USER:" "$bashrc" 2>/dev/null || true
        fi
    else
        warn "could not resolve home for user $INSTALL_USER; skipping bashrc hook"
    fi
fi

# Optional static motd blanking
if (( CLEAR_STATIC )); then
    if [[ -s /etc/motd ]]; then
        log "backing up /etc/motd -> /etc/motd.dashmotd.bak"
        cp -a /etc/motd /etc/motd.dashmotd.bak
        : > /etc/motd
    fi
fi

# Cleanup bootstrap temp if used
if [[ -n "${BOOTSTRAP_TMP:-}" && -d "${BOOTSTRAP_TMP:-}" ]]; then
    rm -rf "$BOOTSTRAP_TMP"
fi

if (( USED_UPDATE_MOTD )) && command -v run-parts >/dev/null 2>&1; then
    log "done. Preview with: run-parts /etc/update-motd.d/"
else
    log "done. Preview with: /opt/dashmotd/bin/dashmotd-render"
fi
log "Timer status: systemctl list-timers dashmotd.timer"

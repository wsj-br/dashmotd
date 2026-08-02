#!/usr/bin/env bash
# Section: packages — upgradable count across apt / dnf / yum / pacman / zypper
#
# Copyright (c) 2026 Waldemar Scudeller Junior.  Licensed under MIT License

set -euo pipefail
# shellcheck source=/dev/null
source "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"
# shellcheck source=/dev/null
source "$DASHMOTD_ROOT/lib/distro.sh"
ensure_cache_dir
dashmotd_detect_os

cache_hours="${PKG_CACHE_HOURS:-${APT_CACHE_HOURS:-1}}"
cache_file="$DASHMOTD_CACHE/packages"
bucket="$(date +%Y%m%d%H)"
if (( cache_hours > 1 )); then
    hour="$(date +%H)"
    hour=$(( 10#$hour / cache_hours * cache_hours ))
    bucket="$(date +%Y%m%d)$(printf '%02d' "$hour")"
fi

t_pkgs=0
s_pkgs=0
pkg_mgr="${DASHMOTD_PKG_MANAGER}"

last_update="$(dashmotd_cache_get "$cache_file" last_update 2>/dev/null || true)"
cached_mgr="$(dashmotd_cache_get "$cache_file" cached_mgr 2>/dev/null || true)"
t_pkgs="$(dashmotd_cache_get "$cache_file" t_pkgs 2>/dev/null || true)"
s_pkgs="$(dashmotd_cache_get "$cache_file" s_pkgs 2>/dev/null || true)"
[[ "$t_pkgs" =~ ^[0-9]+$ ]] || t_pkgs=0
[[ "$s_pkgs" =~ ^[0-9]+$ ]] || s_pkgs=0

count_apt() {
    apt-get -qq update >/dev/null 2>&1 || true
    local upgradable
    upgradable="$(apt -qq list --upgradable 2>/dev/null || true)"
    if [[ -z "${upgradable// }" ]]; then
        t_pkgs=0
        s_pkgs=0
    else
        t_pkgs="$(printf '%s\n' "$upgradable" | grep -cve '^ *$')"
        s_pkgs="$(printf '%s\n' "$upgradable" | grep -c -- '-security' || true)"
    fi
}

count_dnf() {
    # dnf check-update: exit 100 => updates available; stdout lists them
    local out
    out="$(dnf -q check-update --refresh 2>/dev/null || true)"
    # Lines look like: name.arch  version  repo
    t_pkgs="$(printf '%s\n' "$out" | awk 'NF>=3 && $1 !~ /^Last/ && $1 !~ /^Obsoleting/ {c++} END{print c+0}')"
    s_pkgs="$(dnf -q updateinfo list --security updates 2>/dev/null \
        | awk 'NF && $1 !~ /^Last/ && $1 !~ /^Updating/ {c++} END{print c+0}' || echo 0)"
}

count_yum() {
    local out
    out="$(yum -q check-update 2>/dev/null || true)"
    t_pkgs="$(printf '%s\n' "$out" | awk 'NF>=3 && $1 !~ /^Loaded/ && $1 !~ /^Security/ {c++} END{print c+0}')"
    s_pkgs=0
    if yum --help 2>&1 | grep -q -- '--security'; then
        s_pkgs="$(yum -q --security check-update 2>/dev/null \
            | awk 'NF>=3 {c++} END{print c+0}' || echo 0)"
    fi
}

count_pacman() {
    # Prefer checkupdates (pacman-contrib): syncs a temp DB, no root needed
    if command -v checkupdates >/dev/null 2>&1; then
        local out
        out="$(checkupdates 2>/dev/null || true)"
        if [[ -z "${out// }" ]]; then
            t_pkgs=0
        else
            t_pkgs="$(printf '%s\n' "$out" | grep -cve '^ *$')"
        fi
    else
        # Fallback: packages with newer versions in sync DB (may be stale)
        local out
        out="$(pacman -Qu 2>/dev/null || true)"
        if [[ -z "${out// }" ]]; then
            t_pkgs=0
        else
            t_pkgs="$(printf '%s\n' "$out" | grep -cve '^ *$')"
        fi
    fi
    s_pkgs=0  # Arch has no security channel split
}

count_zypper() {
    local out
    zypper --non-interactive refresh >/dev/null 2>&1 || true
    out="$(zypper --non-interactive list-updates 2>/dev/null || true)"
    # Skip header lines
    t_pkgs="$(printf '%s\n' "$out" | awk -F'|' '/^v/ {c++} END{print c+0}')"
    s_pkgs="$(zypper --non-interactive list-patches --category security 2>/dev/null \
        | awk -F'|' '/^v/ {c++} END{print c+0}' || echo 0)"
}

if [[ "${last_update:-}" != "$bucket" || "${cached_mgr:-}" != "$pkg_mgr" ]]; then
    case "$pkg_mgr" in
        apt)    count_apt ;;
        dnf)    count_dnf ;;
        yum)    count_yum ;;
        pacman) count_pacman ;;
        zypper) count_zypper ;;
        *)
            t_pkgs=0
            s_pkgs=0
            ;;
    esac
    {
        echo "last_update=${bucket}"
        echo "cached_mgr=${pkg_mgr}"
        echo "t_pkgs=${t_pkgs}"
        echo "s_pkgs=${s_pkgs}"
    } > "$cache_file"
fi

if [[ "$pkg_mgr" == "unknown" ]]; then
    echo
    echo "${bold}packages:${reset}"
    echo '  package manager not detected'
    exit 0
fi

[[ "$t_pkgs" =~ ^[0-9]+$ ]] || t_pkgs=0
[[ "$s_pkgs" =~ ^[0-9]+$ ]] || s_pkgs=0

if (( t_pkgs > 0 )); then
    t_disp="${bred}${t_pkgs}${reset}"
    s_disp="${bred}${s_pkgs}${reset}"
    if (( s_pkgs > 0 )); then
        msg="${t_disp} available (${s_disp} security)"
    else
        msg="${t_disp} available"
    fi
else
    msg="${bgreen}0${reset} available"
fi

echo
echo "${bold}packages:${reset}"
echo -e "  ${msg}"
if reboot_required; then
    echo -e "  ${bred}!${reset} reboot required"
fi

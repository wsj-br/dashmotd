# dashmotd distro / package-manager detection
# Sourced by sections and the installer.
#
# Copyright (c) 2026 Waldemar Scudeller Junior.  Licensed under MIT License

# DASHMOTD_OS_FAMILY: debian | rhel | arch | suse | unknown
# DASHMOTD_PKG_MANAGER: apt | dnf | yum | pacman | zypper | unknown

dashmotd_detect_os() {
    local id_like="" id=""

    if [[ -r /etc/os-release ]]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        id="${ID:-}"
        id_like="${ID_LIKE:-}"
    fi

    # Normalize to a family
    case "$id" in
        debian|ubuntu|raspbian|linuxmint|pop|zorin|elementary|neon|kali|parrot)
            DASHMOTD_OS_FAMILY=debian
            ;;
        rhel|centos|rocky|alma|ol|oracle|fedora|amzn|almalinux|rocky)
            DASHMOTD_OS_FAMILY=rhel
            ;;
        arch|archarm|manjaro|endeavouros|garuda|artix)
            DASHMOTD_OS_FAMILY=arch
            ;;
        opensuse*|sles|suse)
            DASHMOTD_OS_FAMILY=suse
            ;;
        *)
            case " $id_like " in
                *" debian "*|*" ubuntu "*) DASHMOTD_OS_FAMILY=debian ;;
                *" rhel "*|*" fedora "*|*" centos "*) DASHMOTD_OS_FAMILY=rhel ;;
                *" arch "*) DASHMOTD_OS_FAMILY=arch ;;
                *" suse "*) DASHMOTD_OS_FAMILY=suse ;;
                *) DASHMOTD_OS_FAMILY=unknown ;;
            esac
            ;;
    esac

    # Package manager: honor explicit config override, else probe
    if [[ -n "${PKG_MANAGER:-}" && "${PKG_MANAGER}" != "auto" ]]; then
        DASHMOTD_PKG_MANAGER="$PKG_MANAGER"
        return 0
    fi

    if command -v apt-get >/dev/null 2>&1 && command -v apt >/dev/null 2>&1; then
        DASHMOTD_PKG_MANAGER=apt
    elif command -v dnf >/dev/null 2>&1; then
        DASHMOTD_PKG_MANAGER=dnf
    elif command -v yum >/dev/null 2>&1; then
        DASHMOTD_PKG_MANAGER=yum
    elif command -v pacman >/dev/null 2>&1; then
        DASHMOTD_PKG_MANAGER=pacman
    elif command -v zypper >/dev/null 2>&1; then
        DASHMOTD_PKG_MANAGER=zypper
    else
        # Fall back by family
        case "${DASHMOTD_OS_FAMILY}" in
            debian) DASHMOTD_PKG_MANAGER=apt ;;
            rhel)   DASHMOTD_PKG_MANAGER=dnf ;;
            arch)   DASHMOTD_PKG_MANAGER=pacman ;;
            suse)   DASHMOTD_PKG_MANAGER=zypper ;;
            *)      DASHMOTD_PKG_MANAGER=unknown ;;
        esac
    fi
}

# http_get URL [4|6] — print body to stdout using curl or wget.
# Optional second arg forces the IP family (-4 / -6) so dual-stack hosts
# do not reach an "IPv4" endpoint over IPv6 (and vice versa).
http_get() {
    local url="$1"
    local family="${2:-}"
    local -a curl_opts=() wget_opts=()
    case "$family" in
        4) curl_opts=(-4); wget_opts=(-4) ;;
        6) curl_opts=(-6); wget_opts=(-6) ;;
        "") ;;
        *) ;;
    esac
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --max-time 5 "${curl_opts[@]}" "$url" 2>/dev/null || true
    elif command -v wget >/dev/null 2>&1; then
        wget -qO - --timeout=5 "${wget_opts[@]}" "$url" 2>/dev/null || true
    fi
}

# dashmotd_pkg_install_hint PKGS... — print a distro-appropriate install command
dashmotd_pkg_install_hint() {
    dashmotd_detect_os
    case "${DASHMOTD_PKG_MANAGER}" in
        apt)    printf 'apt-get install -y %s\n' "$*" ;;
        dnf)    printf 'dnf install -y %s\n' "$*" ;;
        yum)    printf 'yum install -y %s\n' "$*" ;;
        pacman) printf 'pacman -S --needed %s\n' "$*" ;;
        zypper) printf 'zypper install -y %s\n' "$*" ;;
        *)      printf 'install: %s\n' "$*" ;;
    esac
}

# reboot_required — exit 0 if a reboot is pending (safe under set -e)
reboot_required() {
    # Ensure family is known when called standalone
    [[ -n "${DASHMOTD_OS_FAMILY:-}" ]] || dashmotd_detect_os

    # Debian/Ubuntu / Raspberry Pi
    [[ -f /run/reboot-required ]] && return 0

    # RHEL/Oracle: needs-restarting from yum-utils / dnf-utils (exit 1 = reboot needed)
    if [[ "${DASHMOTD_OS_FAMILY}" == "rhel" ]] && command -v needs-restarting >/dev/null 2>&1; then
        local rc=0
        needs-restarting -r >/dev/null 2>&1 || rc=$?
        (( rc == 1 )) && return 0
    fi

    # Arch only: running kernel dir missing under /usr/lib/modules (best-effort).
    # Do NOT compare "newest" module dir — multi-flavor kernels (e.g. rpi-2712 vs rpi-v8)
    # produce false positives with sort -V.
    if [[ "${DASHMOTD_OS_FAMILY}" == "arch" ]]; then
        local running
        running="$(uname -r)"
        if [[ ! -d "/usr/lib/modules/${running}" ]]; then
            return 0
        fi
    fi
    return 1
}

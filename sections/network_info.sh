#!/usr/bin/env bash
# Section: network (public IP cached daily, private IPs on the default interface)
#
# Copyright (c) 2026 Waldemar Scudeller Junior.  Licensed under MIT License

set -euo pipefail
# shellcheck source=/dev/null
source "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"
# shellcheck source=/dev/null
source "$DASHMOTD_ROOT/lib/distro.sh"
ensure_cache_dir

cache_file="$DASHMOTD_CACHE/network"
today="$(date +%Y%m%d)"

# Accept bare IPv4 or IPv6 literals only (never evaluate cache as shell).
is_valid_ip() {
    local ip="$1"
    [[ "$ip" =~ ^([0-9]{1,3}(\.[0-9]{1,3}){3}|[0-9a-fA-F:]{2,45})$ ]]
}

is_ipv6() {
    [[ "$1" == *:* ]]
}

# All global IPv4 addresses on the interface used for the default route.
# The route source is listed first; the interface's other addresses follow.
collect_private_ips() {
    local dev="" src="" ip line out=""
    local -a ips=() ordered=()
    line="$(ip route get 1.2.3.4 2>/dev/null | awk '
        {
            for (i = 1; i <= NF; i++) {
                if ($i == "dev") dev = $(i + 1)
                if ($i == "src") src = $(i + 1)
            }
        }
        END { print dev; print src }
    ' || true)"
    dev="${line%%$'\n'*}"
    src="${line#*$'\n'}"
    if [[ -n "$dev" && "$dev" != "lo" ]]; then
        while IFS= read -r ip; do
            [[ -n "$ip" ]] || continue
            is_valid_ip "$ip" || continue
            ips+=("$ip")
        done < <(ip -4 -o addr show dev "$dev" scope global 2>/dev/null \
            | awk '{ split($4, a, "/"); print a[1] }' || true)
    fi
    if [[ ${#ips[@]} -eq 0 ]]; then
        ip="$(hostname -I 2>/dev/null | awk '{ print $1 }' || true)"
        ip="$(printf '%s' "$ip" | tr -d '[:space:]')"
        if is_valid_ip "$ip"; then
            ips+=("$ip")
        fi
    fi
    if [[ -n "$src" ]]; then
        for ip in "${ips[@]}"; do
            if [[ "$ip" == "$src" ]]; then
                ordered+=("$ip")
                break
            fi
        done
    fi
    for ip in "${ips[@]}"; do
        [[ -n "$src" && "$ip" == "$src" ]] && continue
        ordered+=("$ip")
    done
    if [[ ${#ordered[@]} -eq 0 ]]; then
        printf '%s' "unknown"
        return
    fi
    for ip in "${ordered[@]}"; do
        if [[ -z "$out" ]]; then
            out="$ip"
        else
            out+=" / ${ip}"
        fi
    done
    printf '%s' "$out"
}

# Single IP, or "ipv6 / ipv4" display form written to the cache.
is_valid_public_ip() {
    local s="$1" left right
    if [[ "$s" == *" / "* ]]; then
        left="${s%% / *}"
        right="${s#* / }"
        is_valid_ip "$left" && is_valid_ip "$right"
    else
        is_valid_ip "$s"
    fi
}

last_update="$(dashmotd_cache_get "$cache_file" last_update 2>/dev/null || true)"
public_ip="$(dashmotd_cache_get "$cache_file" public_ip 2>/dev/null || true)"
private_ip="$(collect_private_ips)"

if [[ "$last_update" != "$today" ]]; then
    # Collect runs as root (systemd); Happy Eyeballs preference differs by uid
    # (root often gets IPv6 from api64, a regular user often gets IPv4). Always
    # force both families against the same URL so dual-stack hosts show
    # "v6 / v4" regardless.
    local_v6="$(http_get "${PUBLIC_IP_URL}" 6 | tr -d '[:space:]')"
    local_v4="$(http_get "${PUBLIC_IP_URL}" 4 | tr -d '[:space:]')"
    v6_ok=0
    v4_ok=0
    if is_valid_ip "$local_v6" && is_ipv6 "$local_v6"; then
        v6_ok=1
    fi
    if is_valid_ip "$local_v4" && ! is_ipv6 "$local_v4"; then
        v4_ok=1
    fi
    if (( v6_ok && v4_ok )); then
        public_ip="${local_v6} / ${local_v4}"
    elif (( v6_ok )); then
        public_ip="$local_v6"
    elif (( v4_ok )); then
        public_ip="$local_v4"
    else
        public_ip="unknown"
    fi
    {
        echo "last_update=${today}"
        echo "public_ip=${public_ip}"
        echo "private_ip=${private_ip}"
    } > "$cache_file"
else
    # Re-validate the cached public address (defense in depth against a poisoned file).
    # Private addresses are local and refreshed on every collect.
    if ! is_valid_public_ip "$public_ip"; then
        public_ip="unknown"
    fi
fi

echo
echo "${bold}network:${reset}"
{
    echo -e "public ip|${public_ip:-unknown}"
    echo -e "private ip|${private_ip:-unknown}"
} | dashmotd_column '|' | indent

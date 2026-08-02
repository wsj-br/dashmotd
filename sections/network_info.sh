#!/usr/bin/env bash
# Copyright (c) 2026 Waldemar Scudeller Junior.  Licensed under MIT License
# Section: network (public IP cached daily, private IP)

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
private_ip="$(dashmotd_cache_get "$cache_file" private_ip 2>/dev/null || true)"

if [[ "$last_update" != "$today" ]]; then
    private_ip="$(ip route get 1.2.3.4 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}')"
    # Fallback if "ip route get" format differs
    if [[ -z "$private_ip" ]]; then
        private_ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
    fi
    private_ip="$(printf '%s' "$private_ip" | tr -d '[:space:]')"
    if ! is_valid_ip "$private_ip"; then
        private_ip="unknown"
    fi

    # Prefer api64 (IPv6 when available); append IPv4 from the v4 endpoint.
    public_ip="$(http_get "${PUBLIC_IP_URL}" | tr -d '[:space:]')"
    if ! is_valid_ip "$public_ip"; then
        public_ip="unknown"
    elif is_ipv6 "$public_ip"; then
        local_v4="$(http_get "${PUBLIC_IP_V4_URL:-https://api.ipify.org/}" | tr -d '[:space:]')"
        if is_valid_ip "$local_v4" && ! is_ipv6 "$local_v4"; then
            public_ip="${public_ip} / ${local_v4}"
        fi
    fi
    {
        echo "last_update=${today}"
        echo "public_ip=${public_ip}"
        echo "private_ip=${private_ip}"
    } > "$cache_file"
else
    # Re-validate cached values (defense in depth against a poisoned file).
    if ! is_valid_public_ip "$public_ip"; then
        public_ip="unknown"
    fi
    if ! is_valid_ip "$private_ip"; then
        private_ip="unknown"
    fi
fi

echo
echo 'network:'
{
    echo -e "public ip|${public_ip:-unknown}"
    echo -e "private ip|${private_ip:-unknown}"
} | column -ts'|' | indent

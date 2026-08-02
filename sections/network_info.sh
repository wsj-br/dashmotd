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

public_ip=""
private_ip=""

if [[ -r "$cache_file" ]]; then
    # shellcheck source=/dev/null
    source "$cache_file"
fi

if [[ "${last_update:-}" != "$today" ]]; then
    private_ip="$(ip route get 1.2.3.4 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}')"
    # Fallback if "ip route get" format differs
    if [[ -z "$private_ip" ]]; then
        private_ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
    fi
    public_ip="$(http_get "${PUBLIC_IP_URL}")"
    {
        echo "last_update=${today}"
        echo "public_ip=${public_ip}"
        echo "private_ip=${private_ip}"
    } > "$cache_file"
else
    # Values already sourced from cache
    :
fi

echo
echo 'network:'
{
    echo -e "public ip|${public_ip:-unknown}"
    echo -e "private ip|${private_ip:-unknown}"
} | column -ts'|' | indent

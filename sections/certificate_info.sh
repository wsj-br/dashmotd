#!/usr/bin/env bash
# Section: certificates (TLS expiry via openssl)
#
# Copyright (c) 2026 Waldemar Scudeller Junior.  Licensed under MIT License

set -euo pipefail
# shellcheck source=/dev/null
source "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"
ensure_cache_dir

if ! command -v openssl >/dev/null 2>&1; then
    echo
    echo "${bold}certificates:${reset}"
    echo '  openssl not available'
    exit 0
fi

cache_file="$DASHMOTD_CACHE/certs"
out_file="$DASHMOTD_CACHE/certs.out"
today="$(date +%Y%m%d)"
out=""

last_update="$(dashmotd_cache_get "$cache_file" last_update 2>/dev/null || true)"
if [[ "$last_update" == "$today" && -r "$out_file" ]]; then
    out="$(cat "$out_file")"
fi

if [[ "$last_update" != "$today" ]]; then
    out=""
    now="$(date +%s)"
    export LANG=C.UTF-8
    for target in $CERT_TARGETS; do
        host="${target%%:*}"
        port="${target##*:}"
        if [[ "$host" == "$port" ]]; then
            port=443
        fi
        end_raw="$(
            echo | openssl s_client -servername "$host" -connect "${host}:${port}" 2>/dev/null \
                | openssl x509 -noout -enddate 2>/dev/null \
                | cut -d= -f2
        )"
        if [[ -z "$end_raw" ]]; then
            state="${bred}x${reset}"
            end_fmt="unreachable"
        else
            end_stamp="$(date -d "$end_raw" +%s 2>/dev/null || echo 0)"
            end_fmt="$(date -d "$end_raw" +"%d/%m/%Y" 2>/dev/null || echo '?')"
            state="$(color_ge "$end_stamp" "$now" o x)"
        fi
        out+=$'\n'"${state} ${host}|${end_fmt}"
    done
    printf 'last_update=%s\n' "$today" > "$cache_file"
    printf '%s' "$out" > "$out_file"
fi

echo
echo "${bold}certificates:${reset}"
if [[ -z "${out:-}" ]]; then
    echo '  none configured'
else
    printf '%s\n' "$out" | dashmotd_column '|' | indent
fi

#!/usr/bin/env bash
# Copyright (c) 2026 Waldemar Scudeller Junior.  Licensed under MIT License
# Section: disks health (SMART attributes)

set -euo pipefail
# shellcheck source=/dev/null
source "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"

if ! command -v smartctl >/dev/null 2>&1; then
    echo
    echo 'disks health:'
    echo '  smartctl not available'
    exit 0
fi

out=" |Pwr|Temp|Cycl|Spare"$'\n'

while read -r disk; do
    [[ -z "$disk" ]] && continue
    base="${disk##*/}"
    if [[ "$base" =~ ^(${DISK_FILTER}) ]]; then
        continue
    fi

    smart_tmp="$(mktemp)"
    # Prefer sudo-less read; fall back silently if permission denied
    if ! smartctl -A -H "$disk" >"$smart_tmp" 2>/dev/null; then
        # Try with -d auto for NVMe naming quirks
        smartctl -A -H -d auto "$disk" >"$smart_tmp" 2>/dev/null || true
    fi

    age_h="$(awk -F: '/Power On Hours/ {print $2; exit} /Power_On_Hours/ {print $4; exit}' "$smart_tmp" | tr -cd '0-9')"
    if [[ -n "$age_h" ]]; then
        age_y=$(( age_h / 24 / 365 ))
        age="$(color_below "$age_y" "$POWERON_WARN" 'y')"
    else
        age='.'
    fi

    temp="$(awk -F: '/^Temperature:/ {gsub(/[^0-9]/,"",$2); print $2; exit}
        /Temperature_Celsius|Airflow_Temperature_Cel/ {print $2; exit}' "$smart_tmp")"
    if [[ -n "$temp" ]]; then
        temp="$(color_below "$temp" "$TEMP_WARN" '°C')"
    else
        temp='.'
    fi

    cycle="$(awk -F: '/Power Cycles/ {print $2; exit} /Load_Cycle_Count/ {print $3; exit}' "$smart_tmp" | tr -cd '0-9')"
    if [[ -n "$cycle" ]]; then
        cycle_k=$(( cycle / 1000 ))
        cycle="$(color_below "$cycle_k" "$LOADCYCLE_WARN" 'k')"
    else
        cycle='.'
    fi

    spare="$(awk -F: '/Available Spare:/ {gsub(/ /,"",$2); print $2; exit}
        /Reallocated_Sector_Ct/ {print $4; exit}' "$smart_tmp")"
    spare="${spare:-.}"

    if grep -qiE 'test result: PASSED|Health Status:\s*OK' "$smart_tmp"; then
        state="${bgreen}o${reset}"
    else
        state="${bred}x${reset}"
    fi

    out+="${state} ${base}|${age}|${temp}|${cycle}|${spare}"$'\n'
    rm -f "$smart_tmp"
done < <(lsblk -dpno KNAME 2>/dev/null)

echo
echo 'disks health:'
printf '%s' "$out" | column -ts'|' | indent

#!/usr/bin/env bash
# Section: disks health (SMART attributes)
#
# Copyright (c) 2026 Waldemar Scudeller Junior.  Licensed under MIT License

set -euo pipefail
# shellcheck source=/dev/null
source "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"

if ! command -v smartctl >/dev/null 2>&1; then
    echo
    echo "${bold}disks health:${reset}"
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

    # NVMe: "Key: value" lines. ATA/SATA: attribute table with RAW_VALUE in $NF.
    age_h="$(awk '
        /Power On Hours:/ { if (match($0, /[0-9]+/)) { print substr($0, RSTART, RLENGTH); exit } }
        $2 == "Power_On_Hours" { print $NF; exit }
    ' "$smart_tmp" | tr -cd '0-9')"
    temp="$(awk '
        /^Temperature:/ { if (match($0, /[0-9]+/)) { print substr($0, RSTART, RLENGTH); exit } }
        $2 == "Temperature_Celsius" || $2 == "Airflow_Temperature_Cel" { print $NF; exit }
    ' "$smart_tmp" | tr -cd '0-9')"
    cycle="$(awk '
        /Power Cycles:/ { if (match($0, /[0-9]+/)) { print substr($0, RSTART, RLENGTH); exit } }
        $2 == "Power_Cycle_Count" || $2 == "Load_Cycle_Count" { print $NF; exit }
    ' "$smart_tmp" | tr -cd '0-9')"
    # Prefer available-spare style attrs over reallocated-sector count.
    spare="$(awk '
        /Available Spare:/ {
            n = $0; sub(/^[^:]*:/, "", n); gsub(/[ \t]/, "", n); pref = n
        }
        $2 == "Available_Reservd_Space" { pref = $NF "%" }
        $2 == "Reallocated_Sector_Ct" { if (pref == "") fallback = $NF }
        END {
            if (pref != "") print pref
            else if (fallback != "") print fallback
        }
    ' "$smart_tmp")"

    healthy=0
    if grep -qiE 'test result: PASSED|Health Status:\s*OK' "$smart_tmp"; then
        healthy=1
    fi

    # Omit disks with no usable SMART data (e.g. unknown USB bridges).
    if (( ! healthy )) && [[ -z "$age_h" && -z "$temp" && -z "$cycle" && -z "$spare" ]]; then
        rm -f "$smart_tmp"
        continue
    fi

    if [[ -n "$age_h" ]]; then
        age_y=$(( age_h / 24 / 365 ))
        age="$(color_below "$age_y" "$POWERON_WARN" 'y')"
    else
        age='.'
    fi

    if [[ -n "$temp" ]]; then
        temp="$(color_below "$temp" "$TEMP_WARN" '°C')"
    else
        temp='.'
    fi

    if [[ -n "$cycle" ]]; then
        cycle_k=$(( cycle / 1000 ))
        cycle="$(color_below "$cycle_k" "$LOADCYCLE_WARN" 'k')"
    else
        cycle='.'
    fi

    spare="${spare:-.}"

    if (( healthy )); then
        state="${bgreen}o${reset}"
    else
        state="${bred}x${reset}"
    fi

    out+="${state} ${base}|${age}|${temp}|${cycle}|${spare}"$'\n'
    rm -f "$smart_tmp"
done < <(lsblk -dpno KNAME 2>/dev/null)

echo
echo "${bold}disks health:${reset}"
printf '%s' "$out" | dashmotd_column '|' | indent

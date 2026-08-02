#!/usr/bin/env bash
# Section: partitions usage (df-based)
#
# Copyright (c) 2026 Waldemar Scudeller Junior.  Licensed under MIT License

set -euo pipefail
# shellcheck source=/dev/null
source "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"

out=""
# Tab-delimited fields so mount points containing spaces survive.
while IFS=$'\t' read -r _fstype size _used avail pcent target; do
    [[ -z "${target:-}" ]] && continue
    pct="${pcent%%%}"
    pct_disp="$(color_below "$pct" "$DISK_WARN" '%')"
    target_disp="${bblue}${target}${reset}"
    out+="${pct_disp}|${target_disp}|${avail} free of ${size}"$'\n'
done < <(df -hT 2>/dev/null | awk -v filter="$PARTITION_FILTER" -v OFS='\t' '
    NR==1 { next }
    $2 ~ ("^(" filter ")$") { next }
    $1 ~ ("^(" filter ")$") { next }
    {
        target = $7
        for (i = 8; i <= NF; i++) target = target " " $i
        print $2, $3, $4, $5, $6, target
    }
' | sort -t $'\t' -k6)

echo
echo "${bold}partitions usage:${reset}"
if [[ -z "$out" ]]; then
    echo '  none'
else
    printf '%s' "$out" | dashmotd_column '|' | indent
fi

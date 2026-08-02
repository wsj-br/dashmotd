#!/usr/bin/env bash
# Copyright (c) 2026 Waldemar Scudeller Junior.  Licensed under MIT License
# Section: partitions usage (df-based)

set -euo pipefail
# shellcheck source=/dev/null
source "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"

out=""
while read -r _fstype size _used avail pcent target; do
    [[ -z "${target:-}" ]] && continue
    pct="${pcent%%%}"
    pct_disp="$(color_below "$pct" "$DISK_WARN" '%')"
    target_disp="${bblue}${target}${reset}"
    out+="${pct_disp}|${target_disp}|${avail} free of ${size}"$'\n'
done < <(df -hT 2>/dev/null | awk -v filter="$PARTITION_FILTER" '
    NR==1 { next }
    $2 ~ ("^(" filter ")$") { next }
    $1 ~ ("^(" filter ")$") { next }
    { print $2, $3, $4, $5, $6, $7 }
' | sort -k6)

echo
echo 'partitions usage:'
if [[ -z "$out" ]]; then
    echo '  none'
else
    printf '%s' "$out" | column -ts'|' | indent
fi

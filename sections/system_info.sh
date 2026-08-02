#!/usr/bin/env bash
# Copyright (c) 2026 Waldemar Scudeller Junior.  Licensed under MIT License
# Section: system info (kernel, tasks, cpu, load, memory, temperature)

set -euo pipefail
# shellcheck source=/dev/null
source "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"

kern="$(uname -r | cut -d. -f1-2)"
tasks="$(ps --no-headers --ppid 2 -p 2 --deselect 2>/dev/null | wc -l)"
load="$(awk '{print $3}' /proc/loadavg)"
cpus="$(grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo 1)"
mem="$(free -b | awk 'NR==2 {printf "%.0f", 100*$3/$2}')"
cpu="$("$DASHMOTD_ROOT/lib/cpu.sh")"

cpu_disp="$(color_below "$cpu" "$CPU_WARN" '%')"
if (( ${load%%.*} < cpus )); then
    load_disp="${bgreen}${load}${reset}"
else
    load_disp="${bred}${load}${reset}"
fi
mem_disp="$(color_below "$mem" "$MEM_WARN" '%')"

lines=()
lines+=("${kern}|kernel|${tasks}|tasks")
lines+=("${cpu_disp}|cpu|${load_disp}|load")

temp_line=""
if [[ -r /sys/class/thermal/thermal_zone0/temp ]]; then
    temp=$(( $(cat /sys/class/thermal/thermal_zone0/temp) / 1000 ))
    temp_disp="$(color_below "$temp" "$TEMP_WARN" '°C')"
    temp_line="${mem_disp}|memory|${temp_disp}|temp"
else
    temp_line="${mem_disp}|memory|"
fi
lines+=("$temp_line")

echo
echo 'system info:'
{
    for line in "${lines[@]}"; do
        echo -e "$line"
    done
} | column -ts'|' | indent

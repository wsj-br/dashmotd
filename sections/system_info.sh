#!/usr/bin/env bash
# Section: system info (kernel, tasks, cpu, load, memory, temperature, uptime)
#
# Copyright (c) 2026 Waldemar Scudeller Junior.  Licensed under MIT License

set -euo pipefail
# shellcheck source=/dev/null
source "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"

# dashmotd_color_load VALUE CPUS — green when load < CPU count, else red.
dashmotd_color_load() {
    local value="$1" ncpu="$2"
    if (( ${value%%.*} < ncpu )); then
        printf '%s%s%s' "$bgreen" "$value" "$reset"
    else
        printf '%s%s%s' "$bred" "$value" "$reset"
    fi
}

# dashmotd_uptime_value — compact duration from /proc/uptime (no clock).
# "12d 3:41" when up a day or more, otherwise "H:MM".
dashmotd_uptime_value() {
    local secs days remain hours mins
    [[ -r /proc/uptime ]] || return 1
    secs="$(awk '{print int($1)}' /proc/uptime)"
    days=$((secs / 86400))
    remain=$((secs % 86400))
    hours=$((remain / 3600))
    mins=$(((remain % 3600) / 60))
    if (( days > 0 )); then
        printf '%dd %d:%02d' "$days" "$hours" "$mins"
    else
        printf '%d:%02d' "$hours" "$mins"
    fi
}

kern="$(uname -r | cut -d. -f1-2)"
tasks="$(ps --no-headers --ppid 2 -p 2 --deselect 2>/dev/null | wc -l)"
load1="$(awk '{print $1}' /proc/loadavg)"
load5="$(awk '{print $2}' /proc/loadavg)"
load15="$(awk '{print $3}' /proc/loadavg)"
cpus="$(grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo 1)"
mem="$(free -b | awk 'NR==2 {printf "%.0f", 100*$3/$2}')"
cpu="$("$DASHMOTD_ROOT/lib/cpu.sh")"
nusers="$(who 2>/dev/null | wc -l | tr -d ' ')"
[[ "$nusers" =~ ^[0-9]+$ ]] || nusers=0
up_disp="$(dashmotd_uptime_value || true)"

cpu_disp="$(color_below "$cpu" "$CPU_WARN" '%')"
load1_disp="$(dashmotd_color_load "$load1" "$cpus")"
load5_disp="$(dashmotd_color_load "$load5" "$cpus")"
load15_disp="$(dashmotd_color_load "$load15" "$cpus")"
mem_disp="$(color_below "$mem" "$MEM_WARN" '%')"

lines=()
lines+=("${kern}|kernel|${tasks}|tasks")
lines+=("${cpu_disp}|cpu|${load15_disp}|load")

temp_line=""
if [[ -r /sys/class/thermal/thermal_zone0/temp ]]; then
    temp=$(( $(cat /sys/class/thermal/thermal_zone0/temp) / 1000 ))
    temp_disp="$(color_below "$temp" "$TEMP_WARN" '°C')"
    temp_line="${mem_disp}|memory|${temp_disp}|temp"
else
    temp_line="${mem_disp}|memory|"
fi
lines+=("$temp_line")

if [[ -n "$up_disp" ]]; then
    lines+=("${up_disp}|uptime|${nusers}|users")
fi
lines+=("${load1_disp}|1m|${load5_disp}|5m")

echo
echo "${bold}system info:${reset}"
{
    for line in "${lines[@]}"; do
        echo -e "$line"
    done
} | dashmotd_column '|' | indent

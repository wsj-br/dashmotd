#!/usr/bin/env bash
# Sample CPU usage from /proc/stat over a short interval.
# Prints a single integer percentage to stdout.
#
# Copyright (c) 2026 Waldemar Scudeller Junior.  Licensed under MIT License

renice -n 20 -p "$$" &>/dev/null || true

samples=2
delay=0.5
prev_idle=0
prev_total=0
usage=0

for _ in $(seq "$samples"); do
    # Fields: user nice system idle iowait irq softirq steal guest guest_nice
    read -r _ user nice system idle iowait irq softirq steal _rest < /proc/stat
    idle_sum=$(( idle + iowait ))
    total=$(( user + nice + system + idle + iowait + irq + softirq + steal ))
    idle_delta=$(( idle_sum - prev_idle ))
    total_delta=$(( total - prev_total ))
    if (( total_delta > 0 )); then
        usage=$(( 100 * (total_delta - idle_delta) / total_delta ))
    fi
    prev_idle=$idle_sum
    prev_total=$total
    sleep "$delay"
done

printf '%s\n' "$usage"

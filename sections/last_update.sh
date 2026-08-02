#!/usr/bin/env bash
# Section: last update (when dashmotd-collect last refreshed cached data)
#
# Copyright (c) 2026 Waldemar Scudeller Junior.  Licensed under MIT License

set -euo pipefail
# shellcheck source=/dev/null
source "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"

stamp_file="$DASHMOTD_CACHE/last_update"

# Prefer the stamp written by dashmotd-collect; fall back to "now" when
# this section is invoked on its own (e.g. test.sh per-section smoke).
if [[ -r "$stamp_file" ]]; then
    stamp="$(cat "$stamp_file")"
else
    stamp="$(LC_ALL=C.UTF-8 date +'%A %d %B, %H:%M:%S')"
fi

echo
echo "${bold}last update:${reset}"
printf '  %s\n' "$stamp"

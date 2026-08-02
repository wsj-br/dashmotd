#!/usr/bin/env bash
# Copyright (c) 2026 Waldemar Scudeller Junior.  Licensed under MIT License
# Section: containers (docker ps)

set -euo pipefail
# shellcheck source=/dev/null
source "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"

if ! command -v docker >/dev/null 2>&1; then
    echo
    echo 'containers:'
    echo '  docker not available'
    exit 0
fi

mapfile -t containers < <(
    docker ps -a --format '{{.Names}} {{.State}}' 2>/dev/null \
        | awk -v filter="$DOCKER_FILTER" '
            BEGIN { n = split(filter, pats, "|") }
            {
                skip = 0
                for (i = 1; i <= n; i++) if (pats[i] != "" && $1 ~ pats[i]) skip = 1
                if (!skip) print
            }
        '
)

out=""
i=0
for entry in "${containers[@]:-}"; do
    [[ -z "$entry" ]] && continue
    name="${entry%% *}"
    state="${entry#* }"
    mark="$(color_ok "$state" running o x)"
    out+="${mark}|${name}|"
    i=$(( i + 1 ))
    if (( i % DOCKER_COLUMNS == 0 )); then
        out+=$'\n'
    fi
done

echo
echo 'containers:'
if [[ -z "$out" ]]; then
    echo '  none'
else
    # Ensure trailing newline for column
    printf '%s\n' "$out" | column -ts'|' | indent
fi

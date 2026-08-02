# Copyright (c) 2026 Waldemar Scudeller Junior.  Licensed under MIT License
# dashmotd common helpers — sourced by section scripts.

# pam_motd runs update-motd.d via `env -i` (empty LANG). Force a UTF-8 locale
# so symbols like °C survive SSH login MOTD generation.
export LANG="${LANG:-C.UTF-8}"
export LC_ALL="${LC_ALL:-C.UTF-8}"

# Resolve project root relative to the calling section (sections/..)
# or absolute when ROOT is already set by the renderer.
if [[ -z "${DASHMOTD_ROOT:-}" ]]; then
    DASHMOTD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

DASHMOTD_CACHE="${DASHMOTD_CACHE:-$DASHMOTD_ROOT/cache}"

# Load config if not already loaded (do not key off GRID_COLUMNS or COLUMNS —
# the shell sets COLUMNS to the terminal width)
if [[ -z "${DASHMOTD_CONFIG_LOADED:-}" ]]; then
    # shellcheck source=/dev/null
    source "$DASHMOTD_ROOT/config"
fi

# shellcheck source=/dev/null
source "$DASHMOTD_ROOT/lib/colors.sh"

# ensure_cache_dir — create the cache directory if missing
ensure_cache_dir() {
    mkdir -p "$DASHMOTD_CACHE"
}

# dashmotd_cache_get FILE KEY — print the value for KEY, no shell evaluation.
# Cache files are key=value lines; never source them as shell.
dashmotd_cache_get() {
    local file="$1" key="$2" line
    [[ -r "$file" ]] || return 1
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" == "$key="* ]] || continue
        printf '%s' "${line#*=}"
        return 0
    done < "$file"
    return 1
}

# indent — prefix every line with two spaces
indent() {
    sed 's/^/  /'
}

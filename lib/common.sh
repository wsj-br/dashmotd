# Copyright (c) 2026 Waldemar Scudeller Junior.  Licensed under MIT License
# dashmotd common helpers — sourced by section scripts.

# Resolve project root relative to the calling section (sections/..)
# or absolute when ROOT is already set by the renderer.
if [[ -z "${DASHMOTD_ROOT:-}" ]]; then
    DASHMOTD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

DASHMOTD_CACHE="${DASHMOTD_CACHE:-$DASHMOTD_ROOT/cache}"

# Load config if not already loaded (do not key off COLUMNS — the shell sets it)
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

# indent — prefix every line with two spaces
indent() {
    sed 's/^/  /'
}

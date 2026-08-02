# Copyright (c) 2026 Waldemar Scudeller Junior.  Licensed under MIT License
# dashmotd layout helpers — sourced by dashmotd-collect and dashmotd-render.
# Requires: DASHMOTD_ROOT, LAYOUT, LIVE_SECTIONS, and the sections map from config.

# dashmotd_trim STRING — strip leading/trailing whitespace
dashmotd_trim() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

# dashmotd_layout_rows — print non-empty, non-comment LAYOUT rows
dashmotd_layout_rows() {
    printf '%s\n' "$LAYOUT" | awk 'NF && $1 !~ /^#/'
}

# dashmotd_resolve_section NAME — print executable section script path, or fail
# Uses the sections map in config (e.g. sysinfo="system_info.sh").
dashmotd_resolve_section() {
    local name script_name script
    name="$(dashmotd_trim "$1")"
    [[ -z "$name" ]] && return 1

    # Indirect expansion: config key -> script filename
    script_name="${!name:-}"
    if [[ -z "$script_name" ]]; then
        # Fallback: treat the cell itself as a filename
        script_name="$name"
    fi

    script="$DASHMOTD_ROOT/sections/$script_name"
    if [[ -x "$script" ]]; then
        printf '%s\n' "$script"
        return 0
    fi
    return 1
}

# dashmotd_is_live NAME — true when NAME is listed in LIVE_SECTIONS
dashmotd_is_live() {
    local name key
    name="$(dashmotd_trim "$1")"
    [[ -z "$name" ]] && return 1
    for key in ${LIVE_SECTIONS:-}; do
        [[ "$key" == "$name" ]] && return 0
    done
    return 1
}

# Copyright (c) 2026 Waldemar Scudeller Junior.  Licensed under MIT License
# dashmotd color helpers — sourced by section scripts
# Provides ANSI bold green/red threshold coloring.

reset=$'\e[0m'
bred=$'\e[1;31m'
bgreen=$'\e[1;32m'
bblue=$'\e[1;34m'

# color_below VALUE THRESHOLD [SUFFIX]
# Prints VALUE(+SUFFIX) in green when VALUE < THRESHOLD, else red.
color_below() {
    local value="$1" threshold="$2" suffix="${3:-}"
    if (( ${value%%.*} < ${threshold%%.*} )); then
        printf '%s%s%s%s' "$bgreen" "$value" "$suffix" "$reset"
    else
        printf '%s%s%s%s' "$bred" "$value" "$suffix" "$reset"
    fi
}

# color_ok VALUE EXPECTED OK_TEXT FAIL_TEXT
# Prints OK_TEXT in green when VALUE equals EXPECTED, else FAIL_TEXT in red.
color_ok() {
    local value="$1" expected="$2" ok_text="$3" fail_text="$4"
    if [[ "$value" == "$expected" ]]; then
        printf '%s%s%s' "$bgreen" "$ok_text" "$reset"
    else
        printf '%s%s%s' "$bred" "$fail_text" "$reset"
    fi
}

# color_ge VALUE THRESHOLD OK_TEXT FAIL_TEXT
# Prints OK_TEXT in green when VALUE >= THRESHOLD, else FAIL_TEXT in red.
color_ge() {
    local value="$1" threshold="$2" ok_text="$3" fail_text="$4"
    if (( ${value%%.*} >= ${threshold%%.*} )); then
        printf '%s%s%s' "$bgreen" "$ok_text" "$reset"
    else
        printf '%s%s%s' "$bred" "$fail_text" "$reset"
    fi
}

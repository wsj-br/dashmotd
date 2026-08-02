# dashmotd column helpers — ANSI-aware table formatting.
# util-linux column only ignores CSI width from v2.40+; OL8/RHEL8 ship 2.32.
#
# Copyright (c) 2026 Waldemar Scudeller Junior.  Licensed under MIT License

# dashmotd_column [FIELD_SEP [OUTPUT_SEP]]
# Read delimiter-separated rows from stdin; print a table padded by visible
# width (ANSI CSI sequences do not count). Default field sep "|", output "  ".
dashmotd_column() {
    local sep="${1:-|}"
    local out_sep="${2:-  }"
    awk -v sep="$sep" -v osep="$out_sep" '
    function vlen(s,    t) {
        t = s
        gsub(/\033\[[0-9;:]*[[:alpha:]]/, "", t)
        return length(t)
    }
    {
        if ($0 == "")
            next
        n = split($0, f, sep)
        nr++
        nf[nr] = n
        for (i = 1; i <= n; i++) {
            cell[nr, i] = f[i]
            w = vlen(f[i])
            if (w > width[i])
                width[i] = w
            if (i > maxf)
                maxf = i
        }
    }
    END {
        for (r = 1; r <= nr; r++) {
            for (i = 1; i <= maxf; i++) {
                s = cell[r, i]
                if (i > 1)
                    printf "%s", osep
                printf "%s", s
                if (i < maxf) {
                    pad = width[i] - vlen(s)
                    if (pad > 0)
                        printf "%*s", pad, ""
                }
            }
            printf "\n"
        }
    }
    '
}

# dashmotd_merge_columns FILE...
# Paste files side-by-side with ANSI-aware column widths and a 4-space gutter.
dashmotd_merge_columns() {
    if (($# == 0)); then
        return 0
    fi
    if (($# == 1)); then
        cat "$1"
        return 0
    fi
    local us=$'\x1f'
    local -a paste_args=()
    local f
    for f in "$@"; do
        paste_args+=("$f")
    done
    paste -d "$us" "${paste_args[@]}" | dashmotd_column "$us" "    "
}

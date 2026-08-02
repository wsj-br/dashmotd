# dashmotd once-per-session display guard (POSIX sh).
#
# Show the dashboard once per controlling tty + kernel session. Nested
# interactive shells (chezmoi cd, bash, sudo -s) and su-login (sudo su -)
# reuse the same tty/session and are skipped. New tmux panes get a new pts
# and still show the dashboard.
#
# Sourced by update-motd.d/50-dashmotd and bin/dashmotd-render.
# Override stamp dir with DASHMOTD_ONCE_DIR. Bypass with DASHMOTD_FORCE=1
# or DASHMOTD_FORCE_TTY=1 (tests / manual previews).
#
# Copyright (c) 2026 Waldemar Scudeller Junior.  Licensed under MIT License

# dashmotd_once_tty — print controlling tty path, or empty
# DASHMOTD_ONCE_TTY overrides (tests).
dashmotd_once_tty() {
    if [ -n "${DASHMOTD_ONCE_TTY:-}" ]; then
        printf '%s\n' "$DASHMOTD_ONCE_TTY"
        return 0
    fi
    if [ -c /dev/tty ]; then
        tty < /dev/tty 2>/dev/null && return 0
    fi
    tty 2>/dev/null || true
}

# dashmotd_once_sid — print kernel session id, or empty
# DASHMOTD_ONCE_SID overrides (tests).
dashmotd_once_sid() {
    if [ -n "${DASHMOTD_ONCE_SID:-}" ]; then
        printf '%s\n' "$DASHMOTD_ONCE_SID"
        return 0
    fi
    if [ -r /proc/self/sessionid ]; then
        cat /proc/self/sessionid 2>/dev/null
        return 0
    fi
    ps -o sid= -p $$ 2>/dev/null | tr -d ' '
}

# dashmotd_once_from_su — 0 if an ancestor process is su (e.g. sudo su -)
dashmotd_once_from_su() {
    pid=${PPID:-}
    n=0
    while [ "$n" -lt 12 ] && [ -n "$pid" ] && [ "$pid" -gt 1 ] 2>/dev/null; do
        if [ -r "/proc/$pid/comm" ]; then
            comm=$(cat "/proc/$pid/comm" 2>/dev/null || true)
            case "$comm" in
                su|su.*) return 0 ;;
                sshd|sshd:*|login) return 1 ;;
            esac
        fi
        next=$(awk '/^PPid:/{print $2; exit}' "/proc/$pid/status" 2>/dev/null) || break
        [ "$next" = "$pid" ] && break
        pid=$next
        n=$((n + 1))
    done
    return 1
}

# dashmotd_once_should_display — 0 if this invocation should print the
# dashboard (and claim the tty/session); 1 if it should stay silent.
dashmotd_once_should_display() {
    # Explicit bypass for tests and forced previews.
    if [ -n "${DASHMOTD_FORCE:-}" ] || [ -n "${DASHMOTD_FORCE_TTY:-}" ]; then
        return 0
    fi

    # Inherited from a parent interactive shell that already displayed (or
    # marked) the dashboard — covers chezmoi cd and plain nested bash.
    if [ -n "${DASHMOTD_SHOWN:-}" ]; then
        return 1
    fi

    # Privilege elevation from an existing session: never re-show.
    if [ -n "${SUDO_USER:-}" ] || [ -n "${SUDO_UID:-}" ]; then
        return 1
    fi
    if dashmotd_once_from_su; then
        return 1
    fi

    tty_path=$(dashmotd_once_tty)
    sid=$(dashmotd_once_sid)
    # Without a tty/session key, fail open (show) — same as pre-guard behavior.
    if [ -z "$tty_path" ] || [ -z "$sid" ]; then
        return 0
    fi

    once_dir="${DASHMOTD_ONCE_DIR:-/tmp/dashmotd-once}"
    mkdir -p "$once_dir" 2>/dev/null || true
    chmod 1777 "$once_dir" 2>/dev/null || true

    key=$(printf '%s' "$tty_path" | tr -c 'A-Za-z0-9._-' '_')
    stamp="$once_dir/$key"
    if [ -r "$stamp" ]; then
        prev=$(cat "$stamp" 2>/dev/null || true)
        if [ "$prev" = "$sid" ]; then
            return 1
        fi
    fi

    # Claim (best-effort). Failure to write still allows display.
    printf '%s\n' "$sid" >"$stamp" 2>/dev/null || true
    return 0
}

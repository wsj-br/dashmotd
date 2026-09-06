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

# dashmotd_once_tty_ok — 0 if PATH is a concrete tty device (not /dev/tty).
# Bare /dev/tty is a synonym for "controlling terminal" and collapses every
# session onto one stamp key; reject it so callers fail open instead.
dashmotd_once_tty_ok() {
    case "$1" in
        /dev/pts/*|/dev/tty[0-9]*|/dev/ttyS*|/dev/ttyUSB*|/dev/ttyAMA*|/dev/ttyACM*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# dashmotd_once_tty — print controlling tty path, or empty
# DASHMOTD_ONCE_TTY overrides (tests).
dashmotd_once_tty() {
    if [ -n "${DASHMOTD_ONCE_TTY:-}" ]; then
        if dashmotd_once_tty_ok "$DASHMOTD_ONCE_TTY"; then
            printf '%s\n' "$DASHMOTD_ONCE_TTY"
        fi
        return 0
    fi
    if [ -c /dev/tty ]; then
        tty_path=$(tty < /dev/tty 2>/dev/null || true)
        if dashmotd_once_tty_ok "$tty_path"; then
            printf '%s\n' "$tty_path"
            return 0
        fi
    fi
    tty_path=$(tty 2>/dev/null || true)
    if dashmotd_once_tty_ok "$tty_path"; then
        printf '%s\n' "$tty_path"
    fi
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
    # Without a concrete tty/session key, fail open (show) — same as
    # pre-guard behavior. Also covers pam_motd before a pts is attached.
    if [ -z "$tty_path" ] || [ -z "$sid" ]; then
        return 0
    fi

    once_dir="${DASHMOTD_ONCE_DIR:-/tmp/dashmotd-once}"
    mkdir -p "$once_dir" 2>/dev/null || true
    chmod 1777 "$once_dir" 2>/dev/null || true

    key=$(printf '%s' "$tty_path" | tr -c 'A-Za-z0-9._-' '_')
    uid=$(id -u 2>/dev/null || printf '0')
    # Per-uid stamp so a root-owned file under sticky /tmp cannot block a
    # later user claim (and so the shell never prints Permission denied).
    stamp="$once_dir/${uid}_${key}"
    # Legacy shared stamp + other uids' stamps for the same tty: if any
    # readable one already holds this session id, stay silent (pam as root
    # then bashrc as the login user).
    for candidate in "$stamp" "$once_dir/$key" "$once_dir/"*"_${key}"; do
        # Unmatched globs stay literal; skip non-files.
        [ -f "$candidate" ] || continue
        [ -r "$candidate" ] || continue
        prev=$(cat "$candidate" 2>/dev/null || true)
        if [ "$prev" = "$sid" ]; then
            return 1
        fi
    done

    # Claim our uid-scoped stamp (best-effort). Redirect failures are
    # shell-level; wrap so Permission denied never reaches the login tty.
    # Failure to write still allows display.
    { printf '%s\n' "$sid" >"$stamp"; } 2>/dev/null || true
    return 0
}

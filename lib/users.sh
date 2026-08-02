# dashmotd bashrc-hook helpers — sourced by install.sh, update.sh, uninstall.sh.
#
# Non-login interactive shells get the dashboard via a system-wide hook in
# /etc/bash.bashrc (Debian/Arch/SUSE) or /etc/bashrc (RHEL). Per-user
# ~/.bashrc / ~/.bashrc.d hooks from older releases are removed on install/update.
#
# Copyright (c) 2026 Waldemar Scudeller Junior.  Licensed under MIT License

# Marker comments delimiting the hook block (system-wide and legacy per-user).
DASHMOTD_HOOK_BEGIN='# >>> dashmotd hook >>>'
DASHMOTD_HOOK_END='# <<< dashmotd hook <<<'

# Body of the non-login interactive shell hook (no markers).
_dashmotd_hook_body() {
    cat <<'HOOK'
# dashmotd — render dashboard in non-login interactive shells only
# (login shells already get it via pam_motd / update-motd.d / profile.d)
if [[ $- == *i* ]] && ! shopt -q login_shell; then
    if [[ -x /opt/dashmotd/bin/dashmotd-render ]]; then
        /opt/dashmotd/bin/dashmotd-render
    fi
fi
HOOK
}

# dashmotd_strip_hook_block FILE — remove marker-delimited block from FILE if present
dashmotd_strip_hook_block() {
    local file="$1"
    [[ -f "$file" ]] || return 0
    if grep -Fq "$DASHMOTD_HOOK_BEGIN" "$file"; then
        # Markers use #/>/spaces; | is a safe sed address delimiter here.
        sed -i "\|$DASHMOTD_HOOK_BEGIN|,\\|$DASHMOTD_HOOK_END|d" "$file"
    fi
}

# dashmotd_append_hook_block FILE — append marker-delimited hook to FILE
dashmotd_append_hook_block() {
    local file="$1"
    {
        printf '\n%s\n' "$DASHMOTD_HOOK_BEGIN"
        _dashmotd_hook_body
        printf '%s\n' "$DASHMOTD_HOOK_END"
    } >> "$file"
}

# dashmotd_system_rcfile — print system-wide bash rc path, or return 1
dashmotd_system_rcfile() {
    if [[ -f /etc/bash.bashrc ]]; then
        printf '%s\n' /etc/bash.bashrc
        return 0
    fi
    if [[ -f /etc/bashrc ]]; then
        printf '%s\n' /etc/bashrc
        return 0
    fi
    return 1
}

# dashmotd_install_system_hook [FILE] — idempotent marker block in system rc
# Optional FILE overrides detection (for tests).
dashmotd_install_system_hook() {
    local rcfile="${1:-}"
    if [[ -z "$rcfile" ]]; then
        rcfile="$(dashmotd_system_rcfile)" || {
            warn "no system-wide bashrc found — non-login shells will not show the dashboard"
            return 1
        }
    fi
    [[ -f "$rcfile" ]] || {
        warn "system bashrc missing: $rcfile"
        return 1
    }
    dashmotd_strip_hook_block "$rcfile"
    dashmotd_append_hook_block "$rcfile"
    log "installing system bashrc hook in $rcfile"
    printf '%s\n' "$rcfile"
}

# dashmotd_remove_system_hook — strip marker block from both candidate files
dashmotd_remove_system_hook() {
    local f
    for f in /etc/bash.bashrc /etc/bashrc; do
        if [[ -f "$f" ]] && grep -Fq "$DASHMOTD_HOOK_BEGIN" "$f"; then
            log "removing system bashrc hook from $f"
            dashmotd_strip_hook_block "$f"
        fi
    done
}

# dashmotd_list_target_users — print name:home for human login accounts.
# Filters by UID_MIN from /etc/login.defs (default 1000), skips root,
# nologin/false shells, and missing home directories. Dedupes by home.
# Used only for legacy per-user hook cleanup.
dashmotd_list_target_users() {
    local uid_min=1000 name uid home shell seen_homes=""
    if [[ -r /etc/login.defs ]]; then
        uid_min="$(awk '/^[[:space:]]*UID_MIN[[:space:]]+/ { print $2; exit }' /etc/login.defs 2>/dev/null || echo 1000)"
        [[ "$uid_min" =~ ^[0-9]+$ ]] || uid_min=1000
    fi

    while IFS=: read -r name _ uid _ _ home shell; do
        [[ -n "$name" && "$name" != "root" ]] || continue
        [[ "$uid" =~ ^[0-9]+$ ]] || continue
        (( uid >= uid_min )) || continue
        case "$shell" in
            */nologin|*/false|"") continue ;;
        esac
        [[ -n "$home" && -d "$home" ]] || continue
        # Deduplicate by home directory
        case " $seen_homes " in
            *" $home "*) continue ;;
        esac
        seen_homes+=" $home"
        printf '%s:%s\n' "$name" "$home"
    done < <(getent passwd)
}

# dashmotd_remove_bashrc_block HOME [OWNER] — strip marker block from ~/.bashrc
# OWNER is unused (kept for call-site compatibility); ownership is not changed.
dashmotd_remove_bashrc_block() {
    local home="$1"
    dashmotd_strip_hook_block "$home/.bashrc"
}

# dashmotd_remove_user_hook USER HOME — remove legacy file and/or inlined block
dashmotd_remove_user_hook() {
    local user="$1" home="$2"
    local hook="$home/.bashrc.d/21-dashmotd.sh"

    if [[ -n "$home" && -f "$hook" ]]; then
        log "removing legacy bashrc hook $hook"
        rm -f "$hook"
    fi
    if [[ -n "$home" && -f "$home/.bashrc" ]] \
        && grep -Fq "$DASHMOTD_HOOK_BEGIN" "$home/.bashrc"
    then
        log "removing legacy bashrc hook block from $home/.bashrc"
        dashmotd_remove_bashrc_block "$home" "$user"
    fi
}

# dashmotd_remove_legacy_user_hooks — strip per-user hooks from older releases
dashmotd_remove_legacy_user_hooks() {
    local _uname _uhome
    while IFS=: read -r _uname _uhome; do
        [[ -n "$_uname" ]] || continue
        dashmotd_remove_user_hook "$_uname" "$_uhome"
    done < <(dashmotd_list_target_users)
}

# Copyright (c) 2026 Waldemar Scudeller Junior.  Licensed under MIT License
# dashmotd user / bashrc-hook helpers — sourced by install.sh, update.sh, uninstall.sh.

# Marker comments delimiting the inlined bashrc block for unwired users.
DASHMOTD_HOOK_BEGIN='# >>> dashmotd hook >>>'
DASHMOTD_HOOK_END='# <<< dashmotd hook <<<'

# Body of the non-login interactive shell hook (no markers).
_dashmotd_hook_body() {
    cat <<'HOOK'
# dashmotd — render dashboard in non-login interactive shells only
# (login shells already get it via pam_motd / update-motd.d)
if [[ $- == *i* ]] && ! shopt -q login_shell; then
    if [[ -x /opt/dashmotd/bin/dashmotd-render ]]; then
        /opt/dashmotd/bin/dashmotd-render
    fi
fi
HOOK
}

# dashmotd_list_target_users — print name:home for human login accounts.
# Filters by UID_MIN from /etc/login.defs (default 1000), skips root,
# nologin/false shells, and missing home directories. Dedupes by home.
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

# dashmotd_bashrc_wired HOME — true if ~/.bashrc already sources bashrc.d
dashmotd_bashrc_wired() {
    local home="$1" bashrc="$1/.bashrc"
    [[ -f "$bashrc" ]] && grep -q 'bashrc\.d' "$bashrc"
}

# dashmotd_write_hook_file HOME OWNER — write ~/.bashrc.d/21-dashmotd.sh
dashmotd_write_hook_file() {
    local home="$1" owner="$2"
    local hook_dir="$home/.bashrc.d"
    local hook="$hook_dir/21-dashmotd.sh"

    mkdir -p "$hook_dir"
    _dashmotd_hook_body > "$hook"
    chown "$owner:" "$hook" 2>/dev/null || true
    chown "$owner:" "$hook_dir" 2>/dev/null || true
    printf '%s\n' "$hook"
}

# dashmotd_remove_bashrc_block HOME — strip marker-delimited block from ~/.bashrc
dashmotd_remove_bashrc_block() {
    local home="$1" bashrc="$1/.bashrc" owner="$2"
    [[ -f "$bashrc" ]] || return 0
    if grep -Fq "$DASHMOTD_HOOK_BEGIN" "$bashrc"; then
        # Markers use #/>/spaces; | is a safe sed address delimiter here.
        sed -i "\|$DASHMOTD_HOOK_BEGIN|,\\|$DASHMOTD_HOOK_END|d" "$bashrc"
        if [[ -n "${owner:-}" ]]; then
            chown "$owner:" "$bashrc" 2>/dev/null || true
        fi
    fi
}

# dashmotd_upsert_bashrc_block HOME OWNER — idempotent inlined hook in ~/.bashrc
dashmotd_upsert_bashrc_block() {
    local home="$1" owner="$2"
    local bashrc="$home/.bashrc"

    if [[ ! -f "$bashrc" ]]; then
        # Create a minimal bashrc so the hook has somewhere to live
        touch "$bashrc"
        chown "$owner:" "$bashrc" 2>/dev/null || true
    fi

    dashmotd_remove_bashrc_block "$home" "$owner"

    {
        printf '\n%s\n' "$DASHMOTD_HOOK_BEGIN"
        _dashmotd_hook_body
        printf '%s\n' "$DASHMOTD_HOOK_END"
    } >> "$bashrc"
    chown "$owner:" "$bashrc" 2>/dev/null || true
    printf '%s\n' "$bashrc"
}

# dashmotd_install_user_hook USER HOME — wire hook via bashrc.d or inlined block
dashmotd_install_user_hook() {
    local user="$1" home="$2" path

    if [[ -z "$home" || ! -d "$home" ]]; then
        warn "could not resolve home for user $user; skipping bashrc hook"
        return 0
    fi

    if dashmotd_bashrc_wired "$home"; then
        path="$(dashmotd_write_hook_file "$home" "$user")"
        log "installing bashrc hook $path"
    else
        path="$(dashmotd_upsert_bashrc_block "$home" "$user")"
        log "installing bashrc hook block in $path"
    fi
}

# dashmotd_remove_user_hook USER HOME — remove file and/or inlined block
dashmotd_remove_user_hook() {
    local user="$1" home="$2"
    local hook="$home/.bashrc.d/21-dashmotd.sh"

    if [[ -n "$home" && -f "$hook" ]]; then
        log "removing bashrc hook $hook"
        rm -f "$hook"
    fi
    if [[ -n "$home" && -f "$home/.bashrc" ]] \
        && grep -Fq "$DASHMOTD_HOOK_BEGIN" "$home/.bashrc"
    then
        log "removing bashrc hook block from $home/.bashrc"
        dashmotd_remove_bashrc_block "$home" "$user"
    fi
}

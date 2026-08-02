# dashmotd site-config installer — sourced by install.sh and update.sh.
#
# Apt/dpkg-style conflict handling when the packaged config differs from the
# site file at $PREFIX/config.
#
# Environment:
#   DASHMOTD_CONFIG_ACTION=keep|replace  force choice without prompting
#
# Copyright (c) 2026 Waldemar Scudeller Junior.  Licensed under MIT License

# Prompt on /dev/tty; prints "keep" or "replace" on stdout.
dashmotd_prompt_config_action() {
    local dest="$1" src="$2"
    local reply normalized

    while true; do
        {
            printf "Configuration file '%s' has been modified.\n" "$dest"
            printf 'What do you want to do about it?\n'
            printf '  Y = keep your currently-installed version (default)\n'
            printf '  N = install the package maintainer'\''s version\n'
            printf '  D = show the differences between the versions\n'
            printf '*** dashmotd config (Y/N/D) [default=Y] ? '
        } >/dev/tty

        if ! read -r reply </dev/tty; then
            printf 'keep\n'
            return 0
        fi

        normalized="$(printf '%s' "$reply" | tr '[:upper:]' '[:lower:]')"
        normalized="${normalized#"${normalized%%[![:space:]]*}"}"
        normalized="${normalized%"${normalized##*[![:space:]]}"}"

        case "$normalized" in
            ''|y|yes)
                printf 'keep\n'
                return 0
                ;;
            n|no)
                printf 'replace\n'
                return 0
                ;;
            d|diff)
                if command -v diff >/dev/null 2>&1; then
                    diff -u "$dest" "$src" >/dev/tty || true
                else
                    printf 'diff unavailable; install diffutils or choose Y/N\n' >/dev/tty
                fi
                ;;
            *)
                printf 'Please answer Y, N, or D.\n' >/dev/tty
                ;;
        esac
    done
}

# dashmotd_install_site_config SRC_CONFIG PREFIX
# Install packaged config with conflict prompt when the site file differs.
dashmotd_install_site_config() {
    local src="$1" prefix="$2"
    local dest="$prefix/config"
    local dest_new="$prefix/config.new"
    local dest_old="$prefix/config.old"
    local action=""

    if [[ ! -f "$src" ]]; then
        warn "packaged config missing: $src"
        return 1
    fi

    if [[ ! -f "$dest" ]]; then
        install -m 0644 "$src" "$dest"
        log "installed $dest"
        return 0
    fi

    if cmp -s "$dest" "$src"; then
        log "$dest unchanged"
        rm -f "$dest_new"
        return 0
    fi

    action="${DASHMOTD_CONFIG_ACTION:-}"
    case "$action" in
        keep|replace) ;;
        '')
            if [[ -r /dev/tty ]]; then
                action="$(dashmotd_prompt_config_action "$dest" "$src")"
            else
                action="keep"
                warn "no TTY; keeping existing $dest"
            fi
            ;;
        *)
            warn "invalid DASHMOTD_CONFIG_ACTION='$action' (use keep|replace); keeping existing"
            action="keep"
            ;;
    esac

    case "$action" in
        replace)
            install -m 0644 "$dest" "$dest_old"
            install -m 0644 "$src" "$dest"
            rm -f "$dest_new"
            log "replaced $dest (previous saved as $dest_old)"
            ;;
        keep|*)
            install -m 0644 "$src" "$dest_new"
            warn "existing $dest kept; packaged defaults written to $dest_new"
            ;;
    esac
}

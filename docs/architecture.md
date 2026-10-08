# Architecture

← [README](../README.md)

```
Collect (hourly):
  dashmotd.timer ──► dashmotd.service ──► bin/dashmotd-collect
                                              │
                                              ├─ cache/last_update
                                              └─ cache/sections/*

Render (every login / interactive shell):
  profile.d / system bashrc ──► bin/dashmotd-render
                                        │
                                        ├─ live: sysinfo, partitions, docker
                                        ├─ cache/sections/*  (collected cells)
                                        ├─ cache/banner
                                        └─ stdout (+ cache/motd fallback)
```

- **Collect path** (hourly + 2 min after boot): systemd oneshot runs
  `dashmotd-collect` as root. It gathers only non-live LAYOUT cells (network,
  disks, packages, lastupdate) into `cache/sections/` and stamps
  `cache/last_update`. Live keys are skipped. Slow lookups (public IP,
  packages) may also keep their own files under `cache/`.
- **Render path** (every display): the system-wide bashrc hook
  (`/etc/bash.bashrc` or `/etc/bashrc`) calls `dashmotd-render`. Login shells
  set `DASHMOTD_LOGIN=1` so the backed-up static `/etc/motd` text is printed
  immediately before the dashboard when `/opt/dashmotd/show-static-motd` is
  present. Distros without `/etc/update-motd.d` also drop
  `/etc/profile.d/zzz-dashmotd.sh` (interactive login shells only). The
  installer blanks `/etc/motd` so pam does not print that text after the
  dashboard. For **non-login interactive** shells (tmux/byobu panes, `bash`
  subshells) the same bashrc hook renders once with `DASHMOTD_AUTO=1`. That
  covers every user — present and future — without editing personal
  `~/.bashrc` files. Install/update also remove any leftover
  `/etc/update-motd.d/50-dashmotd` from older releases (the first
  `update.sh` run is enough: the old updater recopies that file, then calls
  `dashmotd_install_system_hook` from the new `lib/users.sh`, which deletes
  both `/etc` and `/opt` copies). Legacy per-user hooks
  (`~/.bashrc.d/21-dashmotd.sh` or inlined marker blocks) are stripped too.
  Render always samples `LIVE_SECTIONS` and reads everything else from the
  collect cache.

## System-wide bashrc hook

```bash
# >>> dashmotd hook >>>
# dashmotd — show dashboard once per interactive session
if [[ $- == *i* ]]; then
    if [[ -z "${DASHMOTD_SHOWN:-}" ]] && [[ -x /opt/dashmotd/bin/dashmotd-render ]]; then
        if shopt -q login_shell; then
            DASHMOTD_LOGIN=1 DASHMOTD_AUTO=1 /opt/dashmotd/bin/dashmotd-render
        else
            DASHMOTD_AUTO=1 /opt/dashmotd/bin/dashmotd-render
        fi
        export DASHMOTD_SHOWN=1
    fi
fi
# <<< dashmotd hook <<<
```

Auto display paths also use `lib/once.sh`: at most one render per controlling
tty + kernel session, and skips `sudo`/`su` elevation. That prevents a second
dashboard on `sudo su -` or `chezmoi cd` while still showing it in new tmux
panes (new pts). Bypass with `DASHMOTD_FORCE=1` or a direct
`/opt/dashmotd/bin/dashmotd-render` (no `DASHMOTD_AUTO`).

> **Notes:** On Debian-family systems `/etc/bash.bashrc` is a dpkg conffile;
> a bash package upgrade may ask whether to keep your local version — keep
> the dashmotd block. On RHEL-family hosts bash does not read `/etc/bashrc`
> itself; the stock `/etc/skel/.bashrc` sources it, so users who removed
> that line from their own `~/.bashrc` will still see the dashboard at login
> (via profile.d) but not in non-login shells.


# Test in development 

```bash
./test.sh          # full simulated run
./test.sh --quick  # syntax + config + render smoke only
```

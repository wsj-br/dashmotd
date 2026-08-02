# Architecture

← [README](../README.md)

```
Collect (hourly):
  dashmotd.timer ──► dashmotd.service ──► bin/dashmotd-collect
                                              │
                                              ├─ cache/last_update
                                              └─ cache/sections/*

Render (every login / interactive shell):
  pam_motd / profile.d / system bashrc ──► bin/dashmotd-render
                                        │
                                        ├─ live: sysinfo, partitions, docker
                                        ├─ cache/sections/*  (collected cells)
                                        ├─ cache/banner
                                        └─ stdout (+ cache/motd fallback)
```

- **Collect path** (hourly + 2 min after boot): systemd oneshot runs
  `dashmotd-collect` as root. It gathers only non-live LAYOUT cells (network,
  disks, packages, certs, lastupdate) into `cache/sections/` and stamps
  `cache/last_update`. Live keys are skipped. Slow lookups (public IP,
  packages, TLS expiry) may also keep their own files under `cache/`.
- **Render path** (every display): `pam_motd` runs
  `/etc/update-motd.d/50-dashmotd`, which optionally prints the backed-up
  static `/etc/motd` text first, then calls `dashmotd-render` when a
  controlling terminal is present (skips the live render for non-interactive
  ssh such as scp/sftp/git — MOTD output would be discarded anyway). The
  installer blanks `/etc/motd` so pam does not repeat that text after the
  dashboard. Elsewhere the installer drops `/etc/profile.d/zzz-dashmotd.sh`
  (interactive login shells only). For **non-login interactive** shells
  (tmux/byobu panes, `bash` subshells) the installer appends a single
  marker-delimited hook to the system-wide bash rc file:
  `/etc/bash.bashrc` (Debian/Ubuntu/Arch/SUSE) or `/etc/bashrc` (RHEL/Oracle
  Linux/Fedora). That covers every user — present and future — without
  editing personal `~/.bashrc` files. Install/update also remove any legacy
  per-user hooks (`~/.bashrc.d/21-dashmotd.sh` or inlined marker blocks)
  left by older releases. Render always samples `LIVE_SECTIONS` and reads
  everything else from the collect cache.

## System-wide bashrc hook

```bash
# >>> dashmotd hook >>>
# dashmotd — show dashboard once per interactive session
# Login shells: pam_motd / profile.d already displayed; just mark SHOWN so
# nested shells (chezmoi cd, bash) inherit the flag and skip.
# Non-login shells: render at most once per tty/session (DASHMOTD_AUTO=1).
if [[ $- == *i* ]]; then
    if shopt -q login_shell; then
        export DASHMOTD_SHOWN=1
    elif [[ -z "${DASHMOTD_SHOWN:-}" ]] && [[ -x /opt/dashmotd/bin/dashmotd-render ]]; then
        DASHMOTD_AUTO=1 /opt/dashmotd/bin/dashmotd-render
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
> (via pam_motd / profile.d) but not in non-login shells.


# Test in development 

```bash
./test.sh          # full simulated run
./test.sh --quick  # syntax + config + render smoke only
```


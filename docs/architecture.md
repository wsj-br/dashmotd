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
# dashmotd — render dashboard in non-login interactive shells only
# (login shells already get it via pam_motd / update-motd.d / profile.d)
if [[ $- == *i* ]] && ! shopt -q login_shell; then
    if [[ -x /opt/dashmotd/bin/dashmotd-render ]]; then
        /opt/dashmotd/bin/dashmotd-render
    fi
fi
# <<< dashmotd hook <<<
```

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


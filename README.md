# dashmotd

A two-column system dashboard delivered through the standard Linux
`update-motd` framework (`/etc/update-motd.d` + `pam_motd`).

dashmotd separates **collect** (slow / privilege-sensitive data, hourly) from
**render** (login always composes the grid from live samples + collected
cache), so SSH logins stay fast while system info, partitions, and containers
reflect current status.

## Prerequisites

- A supported Linux distribution (see [Supported distributions](#supported-distributions))
- Root privileges to install (the installer configures systemd and MOTD hooks)
- `systemd` recommended (hourly collect timer); without it, run `dashmotd-collect` from cron
- On Debian-family systems: `pam_motd` + `/etc/update-motd.d` (usual default). Elsewhere the installer falls back to `/etc/profile.d`

**Required commands:** `bash`, `column`, `paste`, `free`, `awk`, `sed`, `grep`, `mktemp`

**Recommended** (sections degrade gracefully if missing): `smartmontools` (`smartctl`), `openssl`, `curl` or `wget`, `figlet` (+ `toilet-fonts` on Debian for the mono9 font), `docker`; on Arch also `pacman-contrib` (`checkupdates`)

```bash
# Debian / Ubuntu / Raspberry Pi / Zorin
sudo apt-get install -y smartmontools openssl wget curl figlet toilet-fonts

# RHEL / Oracle Linux / Rocky / Alma / Fedora
sudo dnf install -y smartmontools openssl wget curl figlet

# Arch / Manjaro
sudo pacman -S --needed smartmontools openssl wget curl figlet pacman-contrib
```

## Quick install

```bash
curl -fsSL https://raw.githubusercontent.com/wsj-br/dashmotd/main/install.sh | sudo bash
```

The installer is self-bootstrapping: when piped through `curl` it downloads
the project tarball, installs into `/opt/dashmotd`, wires up systemd +
`update-motd.d`, collects the first cache, and renders a preview. Pipe into
`sudo bash` (root is required; a non-root pipe cannot re-exec itself).

> **Development tip:** GitHub’s raw CDN can lag ~5 minutes after a push. If a
> just-published `install.sh` still looks stale, use a clone/`DASHMOTD_TARBALL`,
> or temporarily:
> `curl -fsSL https://cdn.jsdelivr.net/gh/wsj-br/dashmotd@main/install.sh | sudo bash`

Or install from a local tarball / clone:

```bash
# from a git clone (installs bashrc hooks for every human user by default)
sudo ./install.sh

# from a release archive
DASHMOTD_TARBALL=./dashmotd.tar.gz sudo -E bash install.sh
```

## Update

Refresh an existing install (keeps `/opt/dashmotd/config` and `cache/`):

```bash
sudo /opt/dashmotd/update.sh
```

From a git clone instead of downloading GitHub:

```bash
sudo ./update.sh
```

Optional overrides: `DASHMOTD_REF=main`, `DASHMOTD_REPO=...`, `DASHMOTD_TARBALL=...`
(same meaning as for `install.sh`). The updater replaces scripts, systemd units,
and MOTD hooks, then runs collect + render. Site `config` is preserved — if you
still have an old `PUBLIC_IP_URL`, set it to `https://api64.ipify.org/` (and
optionally `PUBLIC_IP_V4_URL=https://api.ipify.org/`) so dual-stack hosts show
`ipv6 / ipv4`. `COLUMNS` was renamed to `GRID_COLUMNS`; an old `COLUMNS=2` line
is ignored and the grid falls back to 2 columns.

### Options

| Flag / env | Meaning |
|---|---|
| `--user NAME` | Restrict the non-login bashrc hook to this user (default: every human user on the system) |
| `--no-static-motd` | Do not show the old `/etc/motd` text before the dashboard (still blanks it so pam does not print it after) |
| `DASHMOTD_REPO` | GitHub repo URL used when bootstrapping |
| `DASHMOTD_REF` | Branch or tag (default `main`) |
| `DASHMOTD_TARBALL` | Local path or URL of a `.tar.gz` (skips GitHub) |

## Self-test

From a clone (no install required):

```bash
./test.sh          # full simulated run
./test.sh --quick  # syntax + config + render smoke only
```

Uses an isolated temp cache; does not modify `/opt/dashmotd`.

> **Note:** Disk health (`smartctl`) needs root to read SMART attributes.
> Disks with no usable SMART data (e.g. unknown USB bridges) are omitted from
> the list. A non-root `./test.sh` still passes, but the disks section may be
> empty until collect has run as root. Use `sudo ./test.sh` for a full preview,
> or rely on the installed systemd unit which runs `dashmotd-collect` as root.

## Preview

```bash
run-parts /etc/update-motd.d/
# or
/opt/dashmotd/bin/dashmotd-render
```

Force a refresh of **collected** (cached) data:

```bash
sudo systemctl start dashmotd.service
# or
sudo /opt/dashmotd/bin/dashmotd-collect
```

Then preview again with `/opt/dashmotd/bin/dashmotd-render` (live sections are
always sampled at render time).

## Supported distributions

| Family | Examples | Package manager | Login display |
|---|---|---|---|
| Debian | Debian, Ubuntu, Zorin, Raspberry Pi OS, Mint, Pop!_OS | `apt` | `/etc/update-motd.d` + pam_motd |
| RHEL | Oracle Linux, RHEL, Rocky, Alma, Fedora, Amazon Linux | `dnf` / `yum` | `/etc/profile.d` (if no update-motd.d) |
| Arch | Arch, Manjaro, EndeavourOS | `pacman` (+ `checkupdates`) | `/etc/profile.d` |
| SUSE | openSUSE, SLES | `zypper` | `/etc/profile.d` |

Package manager is auto-detected (`PKG_MANAGER=auto`); override in `config` if needed.

## How it works

```
Collect (hourly):
  dashmotd.timer ──► dashmotd.service ──► bin/dashmotd-collect
                                              │
                                              ├─ cache/last_update
                                              └─ cache/sections/{network,disks,packages,certs,lastupdate}

Render (every login / interactive shell):
  pam_motd / profile.d / bashrc ──► bin/dashmotd-render
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
  static `/etc/motd` text first, then calls `dashmotd-render`. The installer
  blanks `/etc/motd` so pam does not repeat that text after the dashboard.
  Elsewhere the installer drops `/etc/profile.d/zzz-dashmotd.sh`. For
  non-login interactive shells (tmux/byobu) the installer also adds a
  guarded hook for every human user on the system (or only `--user NAME`):
  if `~/.bashrc` already sources `~/.bashrc.d/*.sh`, it writes
  `~/.bashrc.d/21-dashmotd.sh`; otherwise it appends a marker-delimited
  block directly to `~/.bashrc` so the hook runs without inventing a
  `.bashrc.d` layout. Render always samples `LIVE_SECTIONS` and reads
  everything else from the collect cache.

```bash
# >>> dashmotd hook >>>
# dashmotd — render dashboard in non-login interactive shells only
# (login shells already get it via pam_motd / update-motd.d)
if [[ $- == *i* ]] && ! shopt -q login_shell; then
    if [[ -x /opt/dashmotd/bin/dashmotd-render ]]; then
        /opt/dashmotd/bin/dashmotd-render
    fi
fi
# <<< dashmotd hook <<<
```

## Configuration

Edit `/opt/dashmotd/config` (or `config` in a clone before installing):

```bash
GRID_COLUMNS=2
LAYOUT="
sysinfo    | network
partitions | disks
packages   | certs
docker     | lastupdate
"

# Map layout cell names to scripts under sections/
sysinfo="system_info.sh"
network="network_info.sh"
partitions="partition_info.sh"
disks="disk_info.sh"
packages="packages_info.sh"
certs="certificate_info.sh"
docker="docker_info.sh"
lastupdate="last_update.sh"

# Sampled live at every render (not stored by dashmotd-collect)
LIVE_SECTIONS="sysinfo partitions docker"

PKG_MANAGER=auto          # auto | apt | dnf | yum | pacman | zypper
PKG_CACHE_HOURS=1
MEM_WARN=50
CPU_WARN=20
TEMP_WARN=60
DISK_WARN=80
CERT_TARGETS="example.com:443"
DOCKER_FILTER="watchtower-runnow"
```

To add a section: drop a script in `sections/`, map it in the sections block, and put its key in `LAYOUT`. Put the key in `LIVE_SECTIONS` if it should be sampled at every login; otherwise the collector will cache it. To swap an implementation, change only the mapped filename.

After editing collected sections, re-collect:

```bash
sudo systemctl start dashmotd.service
```

Regenerate the hostname banner (e.g. after a rename):

```bash
sudo /opt/dashmotd/bin/dashmotd-banner
```

### Static `/etc/motd` (legal / admin text)

On install, the previous `/etc/motd` is moved aside so pam does not print it
*after* the dashboard. The backup is shown *before* dashmotd instead.

| Path | Role |
|---|---|
| `/etc/motd.dashmotd.bak` | Backup of the original static MOTD |
| `/etc/motd` | Left empty (pam static MOTD) |
| `/opt/dashmotd/show-static-motd` | Marker: when present, `50-dashmotd` prints the backup first |

**Edit** the text shown before the dashboard:

```bash
sudo nano /etc/motd.dashmotd.bak
# next SSH login picks it up (no re-collect needed)
```

**Restore** it as the normal static `/etc/motd` again (and stop prepending it):

```bash
sudo mv /etc/motd.dashmotd.bak /etc/motd
sudo rm -f /opt/dashmotd/show-static-motd
```

**Delete** / stop showing the old text (keep dashmotd only):

```bash
sudo rm -f /etc/motd.dashmotd.bak /opt/dashmotd/show-static-motd
```

Install with `--no-static-motd` to skip showing the backup from the start ( `/etc/motd` is still blanked).

## Sections

| Layout key | Script | When | Contents |
|---|---|---|---|
| `sysinfo` | `system_info.sh` | live | Kernel, tasks, CPU %, load, memory %, temperature |
| `network` | `network_info.sh` | collect | Public IP (IPv6 + IPv4 when dual-stack; daily cache) and private IP |
| `partitions` | `partition_info.sh` | live | Usage % plus free/total from `df -h` (e.g. `66%  /  304G free of 917G`) |
| `disks` | `disk_info.sh` | collect | SMART power-on / temp / cycles / spare (`smartctl`) |
| `packages` | `packages_info.sh` | collect | Upgradable count via apt/dnf/yum/pacman/zypper + reboot flag |
| `certs` | `certificate_info.sh` | collect | TLS certificate expiry via `openssl` |
| `docker` | `docker_info.sh` | live | Container names and running/stopped marks |
| `lastupdate` | `last_update.sh` | collect | When `dashmotd-collect` last refreshed cached data |

## Uninstall

```bash
sudo /opt/dashmotd/uninstall.sh
# or from a clone:
sudo ./uninstall.sh
```

This removes the systemd units, the `update-motd.d` entry, per-user bashrc
hooks (both `~/.bashrc.d/21-dashmotd.sh` and any inlined marker block in
`~/.bashrc`), and `/opt/dashmotd`. It re-enables `/etc/update-motd.d/10-uname`
if it was disabled, and restores `/etc/motd` if a backup was made.

## License

Copyright (c) 2026 Waldemar Scudeller Junior. 

Licensed under the MIT License — see [LICENSE](LICENSE).

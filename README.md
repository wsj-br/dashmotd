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

*(If running an update or install immediately after a GitHub commit, see [Troubleshooting](#troubleshooting) regarding GitHub CDN cache latency).*

Or install from a local tarball / clone:

```bash
# from a git clone
sudo ./install.sh

# from a release archive
DASHMOTD_TARBALL=./dashmotd.tar.gz sudo -E bash install.sh
```

## Update

Refresh an existing install (keeps `cache/`; site config handled as below):

```bash
sudo /opt/dashmotd/update.sh

# replace site config with packaged defaults (previous saved as config.old)
sudo /opt/dashmotd/update.sh --force-new-config
sudo /opt/dashmotd/update.sh -f
```

From a git clone instead of downloading GitHub:

```bash
sudo ./update.sh
```

Optional overrides: `DASHMOTD_REF=main`, `DASHMOTD_REPO=...`, `DASHMOTD_TARBALL=...`
(same meaning as for `install.sh`). The updater replaces scripts, systemd units,
and MOTD hooks, then runs collect + render.

If `/opt/dashmotd/config` differs from the packaged defaults, install and update
prompt apt-style: keep your version (default), install the maintainer's version,
or show a diff and ask again. Keeping writes packaged defaults to
`/opt/dashmotd/config.new`; replacing saves your file as
`/opt/dashmotd/config.old`. With no TTY (or for automation), the existing file
is kept and `config.new` is written. Force a choice with
`update.sh --force-new-config`, `DASHMOTD_CONFIG_ACTION=keep`, or
`DASHMOTD_CONFIG_ACTION=replace`.

If you still have an old `PUBLIC_IP_URL`, set it to `https://api64.ipify.org/` so
dual-stack hosts can resolve both families (`ipv6 / ipv4`). A leftover
`PUBLIC_IP_V4_URL` line in site config is ignored. `COLUMNS` was renamed to
`GRID_COLUMNS`; an old `COLUMNS=2` line is ignored and the grid falls back to
2 columns.

### Options

| Flag / env | Meaning |
|---|---|
| `--no-static-motd` | Do not show the old `/etc/motd` text before the dashboard (still blanks it so pam does not print it after) |
| `-f`, `--force-new-config` | `update.sh` only: replace site config with packaged defaults (saves previous as `config.old`) |
| `DASHMOTD_REPO` | GitHub repo URL used when bootstrapping |
| `DASHMOTD_REF` | Branch or tag (default `main`) |
| `DASHMOTD_TARBALL` | Local path or URL of a `.tar.gz` (skips GitHub) |
| `DASHMOTD_CONFIG_ACTION` | `keep` or `replace` — skip the config conflict prompt |

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

<details>
<summary><strong>System-wide bashrc hook details</strong></summary>

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

</details>

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

<details>
<summary><strong>Managing static /etc/motd (legal / admin text)</strong></summary>

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

Install with `--no-static-motd` to skip showing the backup from the start (`/etc/motd` is still blanked).

</details>

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

## Troubleshooting

<details>
<summary><strong>Why is <code>update.sh</code> or <code>install.sh</code> not picking up the latest GitHub commit?</strong></summary>

GitHub’s `raw.githubusercontent.com` CDN can lag ~5 minutes after a push. If a just-published update is not reflecting on other servers, bypass raw CDN caching using one of these methods:

1. **Update from a git clone:**
   ```bash
   git pull
   sudo ./update.sh
   ```

2. **Fetch via GitHub Contents API:**
   ```bash
   curl -fsSL -H "Accept: application/vnd.github.raw" https://api.github.com/repos/wsj-br/dashmotd/contents/update.sh?ref=main | sudo bash
   ```

3. **Force update using branch ref:**
   ```bash
   DASHMOTD_REF=main sudo -E /opt/dashmotd/update.sh
   ```
</details>

<details>
<summary><strong>Why is the hostname banner using plain text instead of ASCII art?</strong></summary>

`dashmotd-banner` uses `figlet` with the `mono9` font (provided by `toilet-fonts` on Debian/Ubuntu). If `figlet` or font packages were missing when the update or installation ran, it wrote a plain hostname fallback to `cache/banner`.

To generate the ASCII art banner, install the missing packages and run the banner generator:

```bash
# Debian / Ubuntu
sudo apt-get install -y figlet toilet-fonts

# RHEL / Fedora / Oracle Linux
sudo dnf install -y figlet

# Arch Linux
sudo pacman -S figlet

# Regenerate the cached banner:
sudo /opt/dashmotd/bin/dashmotd-banner
```
</details>

<details>
<summary><strong>Why are column vertical separators (<code>│</code>) showing gaps or broken characters?</strong></summary>

`dashmotd` uses the Unicode box-drawing character `│` (`U+2502`) as a column separator. Terminals like Ghostty or Kitty render box-drawing characters as continuous full-cell sprites without line-height gaps.

If vertical bars show gaps or unexpected characters:
- Ensure your terminal emulator encoding is set to **UTF-8**.
- Use a font that properly supports Unicode box-drawing glyphs, or enable box-drawing character sprite rendering in your terminal configuration.
- Re-run `sudo /opt/dashmotd/update.sh` to ensure `dashmotd-render` is updated to the latest script version using `U+2502`.
</details>

<details>
<summary><strong>Why are disk SMART health or package updates missing or empty?</strong></summary>

Sections fall into two execution categories:
- **Live sections:** sampled instantly at every login (`sysinfo`, `partitions`, `docker`).
- **Collected sections:** updated hourly by the `dashmotd.service` systemd timer (`disks`, `packages`, `certs`, `network`).

If a collected section is empty:
1. **Privileges:** `smartctl` requires root privileges to query disk health. The hourly systemd service runs as root to generate these caches safely.
2. **Missing utilities:** ensure required tools are installed (e.g., `smartmontools`, `openssl`, `curl`).
3. **Manual cache refresh:** trigger a manual collect run to inspect errors:
   ```bash
   sudo systemctl start dashmotd.service
   # or
   sudo /opt/dashmotd/bin/dashmotd-collect
   ```
</details>

<details>
<summary><strong>Why is the dashboard rendered twice or not displaying in tmux / subshells?</strong></summary>

- **Double rendering:** if upgrading from older versions, check for leftover manual hooks in `~/.bashrc` or `~/.bashrc.d/21-dashmotd.sh`. `update.sh` automatically removes legacy per-user hooks in favor of the system-wide hook.
- **Subshell rendering:** `dashmotd` hooks into system-wide interactive non-login shells (`/etc/bash.bashrc` on Debian/Ubuntu/Arch/SUSE, `/etc/bashrc` on RHEL/Fedora). Ensure your user `~/.bashrc` sources the system bashrc file if using customized shell configs.
</details>

## Uninstall

```bash
sudo /opt/dashmotd/uninstall.sh
# or from a clone:
sudo ./uninstall.sh
```

This removes the systemd units, the `update-motd.d` entry, the
`/etc/profile.d` snippet (if present), the system-wide bashrc hook from
`/etc/bash.bashrc` or `/etc/bashrc`, any legacy per-user hooks
(`~/.bashrc.d/21-dashmotd.sh` or inlined marker blocks in `~/.bashrc`), and
`/opt/dashmotd`. It re-enables `/etc/update-motd.d/10-uname` if it was
disabled, and restores `/etc/motd` if a backup was made.

## License

Copyright (c) 2026 Waldemar Scudeller Junior. 

Licensed under the MIT License — see [LICENSE](LICENSE).

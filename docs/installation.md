# Installation

← [README](../README.md)

## Prerequisites

- A supported Linux distribution (see [Supported distributions](../README.md#supported-distributions))
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

*(If running an update or install immediately after a GitHub commit, see
[Troubleshooting](troubleshooting.md) regarding GitHub CDN cache latency).*

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

# dashmotd

A two-column system dashboard delivered through the standard Linux
`update-motd` framework (`/etc/update-motd.d` + `pam_motd`).

dashmotd separates **collect** (slow / privilege-sensitive data, hourly) from
**render** (login always composes the grid from live samples + collected
cache), so SSH logins stay fast while system info, partitions, and containers
reflect current status.

## Features

- Fast SSH logins — slow lookups run hourly; render stays light
- Two-column auto-sized grid of system status cells
- Live sections (sysinfo, partitions, docker) sampled at every login; others cached by collect
- Works across Debian, RHEL, Arch, and SUSE families
- Optional tools (`smartctl`, `openssl`, `figlet`, `docker`, …) degrade gracefully when missing

## Prerequisites

- A supported Linux distribution (see [Supported distributions](../README.md#supported-distributions))
- Root privileges to install (the installer configures systemd and MOTD hooks)
- `systemd` recommended (hourly collect timer); without it, run `dashmotd-collect` from cron
- On Debian-family systems: `pam_motd` + `/etc/update-motd.d` (usual default). Elsewhere the installer falls back to `/etc/profile.d`

**Required commands:** `bash`, `paste`, `free`, `awk`, `sed`, `grep`, `mktemp`

**Recommended** (sections degrade gracefully if missing): `smartmontools` (`smartctl`), `openssl`, `curl` or `wget`, `figlet` (dashmotd bundles the `mono9` font), `docker`; on Arch also `pacman-contrib` (`checkupdates`)

```bash
# Debian / Ubuntu / Raspberry Pi / Zorin
sudo apt-get install -y smartmontools openssl wget curl figlet

# RHEL / Oracle Linux / Rocky / Alma / Fedora
sudo dnf install -y smartmontools openssl wget curl figlet

# Arch / Manjaro
sudo pacman -S --needed smartmontools openssl wget curl figlet pacman-contrib
```


## Quick install

```bash
curl -fsSL https://raw.githubusercontent.com/wsj-br/dashmotd/main/install.sh | sudo bash
```

Or install from a local tarball / clone:

```bash
# from a git clone
sudo ./install.sh

# from a release archive
DASHMOTD_TARBALL=./dashmotd.tar.gz sudo -E bash install.sh
```

See [Installation](docs/installation.md) for prerequisites, update options, and
config conflict handling.

## Usage

Update an existing install:

```bash
sudo /opt/dashmotd/update.sh
```

Preview the dashboard:

```bash
run-parts /etc/update-motd.d/
# or
/opt/dashmotd/bin/dashmotd-render
```

Force a refresh of collected (cached) data, then preview again:

```bash
sudo systemctl start dashmotd.service
# or
sudo /opt/dashmotd/bin/dashmotd-collect
```

## Dashboard sections

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

## Supported distributions

| Family | Examples | Package manager | Login display |
|---|---|---|---|
| Debian | Debian, Ubuntu, Zorin, Raspberry Pi OS, Mint, Pop!_OS | `apt` | `/etc/update-motd.d` + pam_motd |
| RHEL | Oracle Linux, RHEL, Rocky, Alma, Fedora, Amazon Linux | `dnf` / `yum` | `/etc/profile.d` (if no update-motd.d) |
| Arch | Arch, Manjaro, EndeavourOS | `pacman` (+ `checkupdates`) | `/etc/profile.d` |
| SUSE | openSUSE, SLES | `zypper` | `/etc/profile.d` |

Package manager is auto-detected (`PKG_MANAGER=auto`); override in `config` if needed.

## Documentation

- [Installation](docs/installation.md) — prerequisites, install/update options, uninstall
- [Configuration](docs/configuration.md) — `config` reference, custom sections, static MOTD
- [Architecture](docs/architecture.md) — collect/render paths and shell hooks
- [Troubleshooting](docs/troubleshooting.md) — common issues and fixes

## Uninstall

```bash
sudo /opt/dashmotd/uninstall.sh
```

See [Installation](docs/installation.md#uninstall) for what is removed and restored.

## License

Copyright (c) 2026 Waldemar Scudeller Junior.

Licensed under the MIT License — see [LICENSE](LICENSE).

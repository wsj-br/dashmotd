# Configuration

← [README](../README.md)

Edit `/opt/dashmotd/config` (or `config` in a clone before installing):

```bash
GRID_COLUMNS=2
LAYOUT="
sysinfo    | network
partitions | disks
packages   | lastupdate
docker     |
"

# Map layout cell names to scripts under sections/
sysinfo="system_info.sh"
network="network_info.sh"
partitions="partition_info.sh"
disks="disk_info.sh"
packages="packages_info.sh"
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
DOCKER_FILTER="watchtower-runnow"
```

To add a section: drop a script in `sections/`, map it in the sections block, and put its key in `LAYOUT`. Put the key in `LIVE_SECTIONS` if it should be sampled at every login; otherwise the collector will cache it. To swap an implementation, change only the mapped filename.

If you kept a site config from before certificates were removed, delete the `certs` cell (and any `CERT_TARGETS` line) from `/opt/dashmotd/config` so the grid does not leave an empty slot.

After editing collected sections, re-collect:

```bash
sudo systemctl start dashmotd.service
```

Regenerate the hostname banner (e.g. after a rename):

```bash
sudo /opt/dashmotd/bin/dashmotd-banner
```

## Managing static /etc/motd (legal / admin text)

On install, the previous `/etc/motd` is moved aside so pam does not print it
*after* the dashboard. On login shells the backup is shown *before* the
dashboard when the marker file is present.

| Path | Role |
|---|---|
| `/etc/motd.dashmotd.bak` | Backup of the original static MOTD |
| `/etc/motd` | Left empty (pam static MOTD) |
| `/opt/dashmotd/show-static-motd` | Marker: when present, a login-shell render prints the backup first |

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

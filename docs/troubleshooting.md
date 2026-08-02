# Troubleshooting

← [README](../README.md)

- [Why is `update.sh` or `install.sh` not picking up the latest GitHub commit?](#why-is-updatesh-or-installsh-not-picking-up-the-latest-github-commit)
- [Why is the hostname banner using plain text instead of ASCII art?](#why-is-the-hostname-banner-using-plain-text-instead-of-ascii-art)
- [Why are the two columns misaligned (colors push the right column around)?](#why-are-the-two-columns-misaligned-colors-push-the-right-column-around)
- [Why are column vertical separators (`│`) showing gaps or broken characters?](#why-are-column-vertical-separators--showing-gaps-or-broken-characters)
- [Why are disk SMART health or package updates missing or empty?](#why-are-disk-smart-health-or-package-updates-missing-or-empty)
- [Why is the dashboard rendered twice or not displaying in tmux / subshells?](#why-is-the-dashboard-rendered-twice-or-not-displaying-in-tmux--subshells)
- [Disk health (`smartctl`) needs root](#disk-health-smartctl-needs-root)

## Why is `update.sh` or `install.sh` not picking up the latest GitHub commit?

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

## Why is the hostname banner using plain text instead of ASCII art?

`dashmotd-banner` uses `figlet` with the bundled `share/figlet/mono9.tlf` font (RHEL/Oracle `figlet` packages do not ship `mono9`). If `figlet` was missing when the update or installation ran, it wrote a plain hostname fallback to `cache/banner`.

Install `figlet` and regenerate the cached banner:

```bash
# Debian / Ubuntu
sudo apt-get install -y figlet

# RHEL / Fedora / Oracle Linux
sudo dnf install -y figlet

# Arch Linux
sudo pacman -S figlet

# Regenerate the cached banner:
sudo /opt/dashmotd/bin/dashmotd-banner
```

## Why are the two columns misaligned (colors push the right column around)?

Older `column` from util-linux (for example **2.32** on Oracle Linux / RHEL 8) counts ANSI color escape bytes as visible width. dashmotd formats tables with an ANSI-aware helper instead. If you still see skewed columns after an old install, update:

```bash
sudo /opt/dashmotd/update.sh
```

## Why are column vertical separators (`│`) showing gaps or broken characters?

`dashmotd` uses the Unicode box-drawing character `│` (`U+2502`) as a column separator. Terminals like Ghostty or Kitty render box-drawing characters as continuous full-cell sprites without line-height gaps.

If vertical bars show gaps or unexpected characters:
- Ensure your terminal emulator encoding is set to **UTF-8**.
- Use a font that properly supports Unicode box-drawing glyphs, or enable box-drawing character sprite rendering in your terminal configuration.
- Re-run `sudo /opt/dashmotd/update.sh` to ensure `dashmotd-render` is updated to the latest script version using `U+2502`.

## Why are disk SMART health or package updates missing or empty?

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

## Why is the dashboard rendered twice or not displaying in tmux / subshells?

- **Double rendering:** if upgrading from older versions, check for leftover manual hooks in `~/.bashrc` or `~/.bashrc.d/21-dashmotd.sh`. `update.sh` automatically removes legacy per-user hooks in favor of the system-wide hook.
- **`sudo su -` / `chezmoi cd` / nested `bash`:** these should not show the dashboard again. Current releases mark the session (`DASHMOTD_SHOWN` + a per-tty stamp in `/tmp/dashmotd-once`) and skip elevation via `su`. Update with `sudo /opt/dashmotd/update.sh` if you still see repeats.
- **Subshell rendering:** `dashmotd` hooks into system-wide interactive shells (`/etc/bash.bashrc` on Debian/Ubuntu/Arch/SUSE, `/etc/bashrc` on RHEL/Fedora). Ensure your user `~/.bashrc` sources the system bashrc file if using customized shell configs. New tmux/byobu panes still get one display (new pts); nested shells in the same pane do not.
- **Force a preview:** `/opt/dashmotd/bin/dashmotd-render` or `DASHMOTD_FORCE=1 DASHMOTD_AUTO=1 /opt/dashmotd/bin/dashmotd-render`

## Disk health (`smartctl`) needs root

Disk health (`smartctl`) needs root to read SMART attributes.
Disks with no usable SMART data (e.g. unknown USB bridges) are omitted from
the list. A non-root `./test.sh` still passes, but the disks section may be
empty until collect has run as root. Use `sudo ./test.sh` for a full preview,
or rely on the installed systemd unit which runs `dashmotd-collect` as root.

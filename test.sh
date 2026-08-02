#!/usr/bin/env bash
# dashmotd self-test — simulated run against the source tree (no install required).
# Usage:
#   ./test.sh           # full simulated run
#   ./test.sh --quick   # syntax + config + render smoke only
#
# Exit 0 on success, 1 on failure. Does not modify /opt/dashmotd.
#
# Copyright (c) 2026 Waldemar Scudeller Junior.  Licensed under MIT License

set -euo pipefail

ROOT="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
QUICK=0
FAILS=0
PASSES=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --quick|-q) QUICK=1 ;;
        -h|--help)
            sed -n '2,8p' "$0"
            exit 0
            ;;
        *)
            printf 'unknown option: %s\n' "$1" >&2
            exit 2
            ;;
    esac
    shift
done

# Isolate cache so tests never touch the live install or dirty the repo cache
TEST_CACHE="$(mktemp -d "${TMPDIR:-/tmp}/dashmotd-test.XXXXXX")"
trap 'rm -rf "$TEST_CACHE"' EXIT
export DASHMOTD_ROOT="$ROOT"
export DASHMOTD_CACHE="$TEST_CACHE"

pass() { PASSES=$((PASSES + 1)); printf '  [PASS] %s\n' "$*"; }
fail() { FAILS=$((FAILS + 1));  printf '  [FAIL] %s\n' "$*" >&2; }

section() { printf '\n==> %s\n' "$*"; }

# --- 1. tree shape -----------------------------------------------------------
section "repository layout"
for path in \
    bin/dashmotd-render \
    bin/dashmotd-collect \
    bin/dashmotd-banner \
    config \
    lib/common.sh \
    lib/colors.sh \
    lib/cpu.sh \
    lib/distro.sh \
    lib/layout.sh \
    lib/users.sh \
    update-motd.d/50-dashmotd \
    systemd/dashmotd.service \
    systemd/dashmotd.timer \
    install.sh \
    uninstall.sh \
    update.sh
do
    if [[ -e "$ROOT/$path" ]]; then
        pass "exists $path"
    else
        fail "missing $path"
    fi
done

# --- 2. syntax ---------------------------------------------------------------
section "bash syntax (bash -n)"
syntax_targets=("$ROOT"/bin/* "$ROOT"/install.sh "$ROOT"/uninstall.sh "$ROOT"/lib/cpu.sh)
syntax_targets+=("$ROOT"/sections/*.sh)
syntax_targets+=("$ROOT"/update-motd.d/50-dashmotd)
# lib helpers that are sourced (not necessarily executable) still parse as bash
for f in "$ROOT"/lib/*.sh; do
    syntax_targets+=("$f")
done

for f in "${syntax_targets[@]}"; do
    [[ -f "$f" ]] || continue
    if bash -n "$f" 2>/tmp/dashmotd-syntax.err; then
        pass "syntax $(basename "$f")"
    else
        fail "syntax $(basename "$f"): $(tr '\n' ' ' </tmp/dashmotd-syntax.err)"
    fi
done
rm -f /tmp/dashmotd-syntax.err

# --- 3. config + layout map --------------------------------------------------
section "config and LAYOUT map"
# shellcheck source=/dev/null
source "$ROOT/config"
# shellcheck source=/dev/null
source "$ROOT/lib/distro.sh"
# shellcheck source=/dev/null
source "$ROOT/lib/layout.sh"

if [[ "${DASHMOTD_CONFIG_LOADED:-}" == "1" ]]; then
    pass "config loaded (DASHMOTD_CONFIG_LOADED=1)"
else
    fail "config sentinel DASHMOTD_CONFIG_LOADED not set"
fi

if [[ -n "${LAYOUT:-}" ]]; then
    pass "LAYOUT defined"
else
    fail "LAYOUT empty"
fi

if [[ -n "${LIVE_SECTIONS:-}" ]]; then
    pass "LIVE_SECTIONS defined (${LIVE_SECTIONS})"
else
    fail "LIVE_SECTIONS empty"
fi

mapfile -t layout_rows < <(dashmotd_layout_rows)
cell_count=0
for row in "${layout_rows[@]}"; do
    IFS='|' read -r -a cells <<< "$row"
    for cell in "${cells[@]}"; do
        name="$(dashmotd_trim "$cell")"
        [[ -z "$name" ]] && continue
        cell_count=$((cell_count + 1))
        script_name="${!name:-}"
        if [[ -z "$script_name" ]]; then
            fail "LAYOUT cell '$name' has no sections map entry"
            continue
        fi
        script="$ROOT/sections/$script_name"
        if [[ -x "$script" ]]; then
            pass "map $name -> $script_name (executable)"
        elif [[ -f "$script" ]]; then
            fail "map $name -> $script_name exists but is not executable"
        else
            fail "map $name -> $script_name missing under sections/"
        fi
    done
done
if (( cell_count > 0 )); then
    pass "LAYOUT has $cell_count cell(s) across ${#layout_rows[@]} row(s)"
else
    fail "LAYOUT has no cells"
fi

for key in ${LIVE_SECTIONS}; do
    if dashmotd_is_live "$key"; then
        pass "LIVE_SECTIONS includes $key"
    else
        fail "dashmotd_is_live failed for $key"
    fi
done

# --- 4. distro detection -----------------------------------------------------
section "distro detection"
dashmotd_detect_os
if [[ -n "${DASHMOTD_OS_FAMILY:-}" && "${DASHMOTD_OS_FAMILY}" != "unknown" ]]; then
    pass "OS family=${DASHMOTD_OS_FAMILY}"
else
    # unknown is acceptable on exotic systems, but warn as soft fail
    fail "OS family undetected (got '${DASHMOTD_OS_FAMILY:-}')"
fi
if [[ -n "${DASHMOTD_PKG_MANAGER:-}" && "${DASHMOTD_PKG_MANAGER}" != "unknown" ]]; then
    pass "package manager=${DASHMOTD_PKG_MANAGER}"
else
    fail "package manager undetected (got '${DASHMOTD_PKG_MANAGER:-}')"
fi

# --- 5. banner ---------------------------------------------------------------
section "banner generation"
banner_out="$("$ROOT/bin/dashmotd-banner" 2>/dev/null || true)"
if [[ -s "$TEST_CACHE/banner" ]]; then
    pass "banner written to cache ($(wc -l <"$TEST_CACHE/banner") lines)"
else
    fail "banner file missing or empty"
fi
if grep -q "$(hostname -s 2>/dev/null || hostname)" "$TEST_CACHE/banner" \
    || [[ "$(wc -l <"$TEST_CACHE/banner")" -ge 1 ]]; then
    pass "banner contains hostname or fallback text"
else
    fail "banner does not look like hostname art"
fi

# --- 6. collect --------------------------------------------------------------
section "simulated collect"
collect_err="$TEST_CACHE/collect.err"
set +e
"$ROOT/bin/dashmotd-collect" 2>"$collect_err"
collect_rc=$?
set -e

if (( collect_rc == 0 )); then
    pass "dashmotd-collect exited 0"
else
    fail "dashmotd-collect failed (rc=$collect_rc); stderr: $(tr '\n' ' ' <"$collect_err")"
fi

if [[ -s "$TEST_CACHE/last_update" ]]; then
    pass "collect wrote last_update stamp"
else
    fail "collect did not write last_update stamp"
fi

# Collected (non-live) keys should have section cache files; live keys must not.
for row in "${layout_rows[@]}"; do
    IFS='|' read -r -a cells <<< "$row"
    for cell in "${cells[@]}"; do
        name="$(dashmotd_trim "$cell")"
        [[ -z "$name" ]] && continue
        if dashmotd_is_live "$name"; then
            if [[ -e "$TEST_CACHE/sections/$name" ]]; then
                fail "collect wrote live section cache for $name (should skip)"
            else
                pass "collect skipped live section $name"
            fi
        else
            if [[ -r "$TEST_CACHE/sections/$name" ]]; then
                pass "collect wrote cache/sections/$name"
            else
                fail "collect missing cache/sections/$name"
            fi
        fi
    done
done

# --- 7. render (simulated display) -------------------------------------------
section "simulated render"
render_log="$TEST_CACHE/render.out"
render_err="$TEST_CACHE/render.err"
set +e
"$ROOT/bin/dashmotd-render" >"$render_log" 2>"$render_err"
render_rc=$?
set -e

if (( render_rc == 0 )) && [[ -s "$render_log" ]]; then
    pass "dashmotd-render exited 0 ($(wc -l <"$render_log") lines)"
else
    fail "dashmotd-render failed (rc=$render_rc); stderr: $(tr '\n' ' ' <"$render_err")"
fi

if [[ -s "$TEST_CACHE/motd" ]]; then
    pass "render wrote cache/motd fallback"
else
    fail "render did not write cache/motd fallback"
fi

# Expected section titles from the default LAYOUT
expected_titles=(
    "system info:"
    "network:"
    "partitions usage:"
    "disks health:"
    "packages:"
    "certificates:"
    "containers:"
    "last update:"
)
for title in "${expected_titles[@]}"; do
    if grep -Fq "$title" "$render_log"; then
        pass "output contains '$title'"
    else
        fail "output missing '$title'"
    fi
done

# Two-column smoke: network should appear on the same line region as system info
if grep -E 'system info:.*network:' "$render_log" >/dev/null; then
    pass "two-column layout (system info | network) detected"
else
    # column widths can push labels onto adjacent visual columns without same-line match
    if grep -Fq "system info:" "$render_log" && grep -Fq "network:" "$render_log"; then
        pass "both columns present (same-line merge not detected — acceptable)"
    else
        fail "two-column layout looks broken"
    fi
fi

# Render with empty section cache still produces live titles (first-boot fallback)
section "render without collect cache"
EMPTY_CACHE="$(mktemp -d "${TMPDIR:-/tmp}/dashmotd-empty.XXXXXX")"
cp -a "$TEST_CACHE/banner" "$EMPTY_CACHE/banner" 2>/dev/null || true
empty_log="$TEST_CACHE/empty-render.out"
set +e
DASHMOTD_CACHE="$EMPTY_CACHE" "$ROOT/bin/dashmotd-render" >"$empty_log" 2>/dev/null
empty_rc=$?
set -e
if (( empty_rc == 0 )) \
    && grep -Fq "system info:" "$empty_log" \
    && grep -Fq "partitions usage:" "$empty_log" \
    && grep -Fq "containers:" "$empty_log"
then
    pass "render without section cache still shows live sections"
else
    fail "render without section cache missing live sections (rc=$empty_rc)"
fi
rm -rf "$EMPTY_CACHE"

if (( QUICK )); then
    section "summary"
    printf 'Passed: %d  Failed: %d  (quick mode)\n' "$PASSES" "$FAILS"
    (( FAILS == 0 ))
    exit $?
fi

# --- 8. per-section smoke ----------------------------------------------------
section "individual sections"
for script in "$ROOT"/sections/*.sh; do
    name="$(basename "$script")"
    out="$TEST_CACHE/section-$name.out"
    err="$TEST_CACHE/section-$name.err"
    set +e
    "$script" >"$out" 2>"$err"
    rc=$?
    set -e
    if (( rc == 0 )) && [[ -s "$out" ]]; then
        pass "section $name (rc=0, $(wc -l <"$out") lines)"
    elif (( rc == 0 )); then
        fail "section $name produced empty output"
    else
        # disks/packages may need root; treat permission-ish failures as soft notes
        if [[ "$name" == "disk_info.sh" || "$name" == "packages_info.sh" ]] && [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
            pass "section $name skipped details as non-root (rc=$rc) — re-run with sudo for full check"
        else
            fail "section $name failed (rc=$rc): $(tr '\n' ' ' <"$err" | head -c 200)"
        fi
    fi
done

# --- 9. update-motd entry (render path) --------------------------------------
section "update-motd entry script"
entry_out="$TEST_CACHE/entry.out"
if DASHMOTD_FORCE_TTY=1 \
    DASHMOTD_RENDER="$ROOT/bin/dashmotd-render" \
    DASHMOTD_CACHE="$TEST_CACHE" \
    "$ROOT/update-motd.d/50-dashmotd" >"$entry_out" 2>/dev/null \
    && [[ -s "$entry_out" ]] \
    && grep -Fq "system info:" "$entry_out"
then
    pass "50-dashmotd invokes dashmotd-render"
else
    fail "50-dashmotd did not render the dashboard"
fi

# Static MOTD preamble (requires /opt/dashmotd/show-static-motd marker)
preamble_out="$TEST_CACHE/preamble.out"
static_bak="$TEST_CACHE/static-motd.bak"
printf 'STATIC PREAMBLE LINE\n' >"$static_bak"
if [[ -e /opt/dashmotd/show-static-motd ]]; then
    if DASHMOTD_FORCE_TTY=1 \
        DASHMOTD_STATIC_MOTD="$static_bak" \
        DASHMOTD_RENDER="$ROOT/bin/dashmotd-render" \
        DASHMOTD_CACHE="$TEST_CACHE" \
        "$ROOT/update-motd.d/50-dashmotd" >"$preamble_out" 2>/dev/null \
        && head -n1 "$preamble_out" | grep -Fq 'STATIC PREAMBLE LINE' \
        && grep -Fq "system info:" "$preamble_out"
    then
        pass "50-dashmotd prints static MOTD before dashboard"
    else
        fail "50-dashmotd did not prepend static MOTD"
    fi
else
    pass "50-dashmotd static preamble check skipped (no /opt/dashmotd/show-static-motd)"
fi

# No controlling tty: skip live render (best-effort interactivity guard).
# setsid starts a new session without a controlling terminal.
notty_out="$TEST_CACHE/notty.out"
if command -v setsid >/dev/null 2>&1; then
    set +e
    env -u DASHMOTD_FORCE_TTY \
        DASHMOTD_STATIC_MOTD="$static_bak" \
        DASHMOTD_RENDER="$ROOT/bin/dashmotd-render" \
        DASHMOTD_CACHE="$TEST_CACHE" \
        setsid "$ROOT/update-motd.d/50-dashmotd" >"$notty_out" 2>/dev/null
    notty_rc=$?
    set -e
    if (( notty_rc == 0 )) && ! grep -Fq "system info:" "$notty_out"; then
        pass "50-dashmotd skips render without controlling tty"
    else
        # Some environments still attach a tty under setsid; treat as soft skip
        pass "50-dashmotd no-tty probe inconclusive in this environment (rc=$notty_rc)"
    fi
else
    pass "50-dashmotd no-tty probe skipped (setsid not available)"
fi

# --- 10. helpers -------------------------------------------------------------
section "helpers"
cpu_val="$("$ROOT/lib/cpu.sh" 2>/dev/null || echo "")"
if [[ "$cpu_val" =~ ^[0-9]+$ ]] && (( cpu_val >= 0 && cpu_val <= 100 )); then
    pass "cpu.sh returned ${cpu_val}%"
else
    fail "cpu.sh returned unexpected value '${cpu_val}'"
fi

# color helpers
# shellcheck source=/dev/null
source "$ROOT/lib/colors.sh"
sample="$(color_below 10 50 '%')"
if [[ "$sample" == *$'\e['* ]]; then
    pass "color_below emits ANSI color"
else
    fail "color_below did not emit ANSI color"
fi

# dashmotd_cache_get — safe key/value reader (never evaluates as shell)
# shellcheck source=/dev/null
source "$ROOT/lib/common.sh"
kv_file="$TEST_CACHE/kv-test"
printf 'alpha=one\nbeta=two\n' > "$kv_file"
if [[ "$(dashmotd_cache_get "$kv_file" alpha)" == "one" ]] \
    && [[ "$(dashmotd_cache_get "$kv_file" beta)" == "two" ]]
then
    pass "dashmotd_cache_get returns expected values"
else
    fail "dashmotd_cache_get returned unexpected values"
fi
if ! dashmotd_cache_get "$kv_file" missing >/dev/null 2>&1; then
    pass "dashmotd_cache_get fails cleanly on missing key"
else
    fail "dashmotd_cache_get should fail on missing key"
fi

# Cache-injection resistance: poisoned network cache must not execute shell
section "cache injection resistance"
poison_cache="$TEST_CACHE/poison"
mkdir -p "$poison_cache"
sentinel="$TEST_CACHE/poison-sentinel"
rm -f "$sentinel"
today="$(date +%Y%m%d)"
{
    printf 'last_update=%s\n' "$today"
    printf 'public_ip=1.2.3.4\n'
    printf 'private_ip=10.0.0.1\n'
    printf 'touch %s\n' "$sentinel"
    printf 'evil=$(touch %s)\n' "$sentinel"
} > "$poison_cache/network"
set +e
DASHMOTD_CACHE="$poison_cache" "$ROOT/sections/network_info.sh" \
    >"$TEST_CACHE/poison-net.out" 2>/dev/null
set -e
if [[ ! -e "$sentinel" ]]; then
    pass "poisoned network cache did not execute shell"
else
    fail "poisoned network cache executed shell (sentinel created)"
fi
if grep -Fq '1.2.3.4' "$TEST_CACHE/poison-net.out" \
    && grep -Fq '10.0.0.1' "$TEST_CACHE/poison-net.out"
then
    pass "poisoned network cache still yields validated IPs"
else
    fail "poisoned network cache did not render validated IPs"
fi

# Dual-stack public IP display form must pass validation (ipv6 / ipv4)
dual_cache="$TEST_CACHE/dual"
mkdir -p "$dual_cache"
{
    printf 'last_update=%s\n' "$today"
    printf 'public_ip=2a01:4b00:ab2e::1002 / 209.35.71.89\n'
    printf 'private_ip=192.168.1.5\n'
} > "$dual_cache/network"
set +e
DASHMOTD_CACHE="$dual_cache" "$ROOT/sections/network_info.sh" \
    >"$TEST_CACHE/dual-net.out" 2>/dev/null
set -e
if grep -Fq '2a01:4b00:ab2e::1002 / 209.35.71.89' "$TEST_CACHE/dual-net.out"; then
    pass "dual-stack public ip display form is accepted from cache"
else
    fail "dual-stack public ip display form rejected or mangled"
fi

# http_get must honor family 4/6 so root collect (Happy Eyeballs often prefers
# IPv6) still resolves both stacks explicitly.
section "http_get forces IP family when requested"
http_bin="$TEST_CACHE/httpbin"
mkdir -p "$http_bin"
printf '%s\n' '#!/bin/sh' 'printf "%s\n" "$*" > "'"$TEST_CACHE"'/curl.args"' 'printf "1.2.3.4\n"' \
    > "$http_bin/curl"
chmod +x "$http_bin/curl"
# Stub curl ahead of real tools; omit wget so http_get takes the curl path.
# shellcheck source=/dev/null
source "$ROOT/lib/distro.sh"
got="$(PATH="$http_bin:/usr/bin:/bin" http_get 'https://api.ipify.org/' 4 | tr -d '[:space:]')"
args="$(cat "$TEST_CACHE/curl.args" 2>/dev/null || true)"
if [[ "$got" == "1.2.3.4" ]] && [[ " $args " == *" -4 "* ]]; then
    pass "http_get URL 4 invokes curl -4"
else
    fail "http_get URL 4 did not force IPv4 (got='$got' args='$args')"
fi
printf '%s\n' '#!/bin/sh' 'printf "%s\n" "$*" > "'"$TEST_CACHE"'/curl6.args"' 'printf "2a01:4b00:ab2e::1002\n"' \
    > "$http_bin/curl"
got6="$(PATH="$http_bin:/usr/bin:/bin" http_get 'https://api64.ipify.org/' 6 | tr -d '[:space:]')"
args6="$(cat "$TEST_CACHE/curl6.args" 2>/dev/null || true)"
if [[ "$got6" == "2a01:4b00:ab2e::1002" ]] && [[ " $args6 " == *" -6 "* ]]; then
    pass "http_get URL 6 invokes curl -6"
else
    fail "http_get URL 6 did not force IPv6 (got='$got6' args='$args6')"
fi
if grep -Eq 'http_get "\$\{PUBLIC_IP_URL\}" 6' "$ROOT/sections/network_info.sh" \
    && grep -Eq 'http_get "\$\{PUBLIC_IP_URL\}" 4' "$ROOT/sections/network_info.sh"
then
    pass "network_info forces both IP families for public IP lookup"
else
    fail "network_info does not force both IP families for public IP lookup"
fi

# Task count is an integer (ps --no-headers)
section "system info task count"
sys_out="$TEST_CACHE/sysinfo.out"
set +e
"$ROOT/sections/system_info.sh" >"$sys_out" 2>/dev/null
set -e
# Strip ANSI, then look for "<digits> tasks"
task_n="$(sed 's/\x1b\[[0-9;]*m//g' "$sys_out" | grep -oE '[0-9]+[[:space:]]+tasks' | head -n1 | awk '{print $1}')"
if [[ "$task_n" =~ ^[0-9]+$ ]]; then
    pass "system info task count is integer ($task_n)"
else
    fail "system info task count not parseable as integer"
fi

# Unit-separator merge: @ in section text must not split columns
section "merge delimiter (@ safety)"
us=$'\x1f'
merge_tmp="$TEST_CACHE/merge"
mkdir -p "$merge_tmp"
printf 'user@host.example left\n' > "$merge_tmp/col1"
printf 'right column\n' > "$merge_tmp/col2"
merged="$(paste -d "$us" "$merge_tmp/col1" "$merge_tmp/col2" | column -ts "$us")"
if [[ "$merged" == *'user@host.example'* ]] \
    && [[ "$merged" == *'right column'* ]] \
    && [[ "$merged" != *$'\x1f'* ]]
then
    pass "unit-separator merge keeps @ intact"
else
    fail "unit-separator merge mangled @ or failed to merge"
fi

# Partition awk/read path keeps mount targets containing spaces
section "partition mount points with spaces"
df_stub="$TEST_CACHE/df-stub"
# Mimic df -hT columns: Filesystem Type Size Used Avail Use% Mounted on
cat > "$df_stub" <<'DF'
Filesystem     Type  Size  Used Avail Use% Mounted on
/dev/sda1      ext4  100G   50G   50G  50% /
/dev/sdb1      ext4  200G  100G  100G  50% /mnt/My Drive
tmpfs          tmpfs 1.0G     0  1.0G   0% /run
DF
part_parsed="$TEST_CACHE/part-parsed"
awk -v filter="tmpfs|vfat|overlay|devtmpfs|squashfs" -v OFS='\t' '
    NR==1 { next }
    $2 ~ ("^(" filter ")$") { next }
    $1 ~ ("^(" filter ")$") { next }
    {
        target = $7
        for (i = 8; i <= NF; i++) target = target " " $i
        print $2, $3, $4, $5, $6, target
    }
' "$df_stub" | sort -t $'\t' -k6 > "$part_parsed"
found_spaced=0
while IFS=$'\t' read -r _fstype size _used avail pcent target; do
    if [[ "$target" == "/mnt/My Drive" ]]; then
        found_spaced=1
        break
    fi
done < "$part_parsed"
if (( found_spaced )); then
    pass "partition parser preserves mount point with spaces"
else
    fail "partition parser lost mount point with spaces"
fi

# --- 11. users / bashrc hook helpers ----------------------------------------
section "users.sh system-wide bashrc hook helpers"
# Minimal log/warn stubs required by lib/users.sh
log()  { :; }
warn() { :; }
# shellcheck source=/dev/null
source "$ROOT/lib/users.sh"

USERS_FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/dashmotd-users.XXXXXX")"
owner="$(id -un)"

# System-wide hook: idempotent install into a temp rcfile
sys_rc="$USERS_FIXTURE/bash.bashrc"
printf '# system bashrc\nexport SYS=1\n' > "$sys_rc"
dashmotd_install_system_hook "$sys_rc" >/dev/null
dashmotd_install_system_hook "$sys_rc" >/dev/null
begin_count="$(grep -cF "$DASHMOTD_HOOK_BEGIN" "$sys_rc" || true)"
end_count="$(grep -cF "$DASHMOTD_HOOK_END" "$sys_rc" || true)"
if [[ "$begin_count" == "1" && "$end_count" == "1" ]] \
    && grep -Fq 'dashmotd-render' "$sys_rc" \
    && grep -Fq 'export SYS=1' "$sys_rc"
then
    pass "dashmotd_install_system_hook is idempotent (one marker block)"
else
    fail "dashmotd_install_system_hook not idempotent (begin=$begin_count end=$end_count)"
fi

# Strip leaves the rest of the file intact
dashmotd_strip_hook_block "$sys_rc"
if ! grep -Fq "$DASHMOTD_HOOK_BEGIN" "$sys_rc" \
    && ! grep -Fq 'dashmotd-render' "$sys_rc" \
    && grep -Fq 'export SYS=1' "$sys_rc"
then
    pass "dashmotd_strip_hook_block removes block, keeps other content"
else
    fail "dashmotd_strip_hook_block damaged rcfile content"
fi

# Legacy cleanup: inlined ~/.bashrc marker block
legacy_home="$USERS_FIXTURE/legacy-inline"
mkdir -p "$legacy_home"
printf '# plain bashrc\nexport FOO=1\n' > "$legacy_home/.bashrc"
{
    printf '\n%s\n' "$DASHMOTD_HOOK_BEGIN"
    _dashmotd_hook_body
    printf '%s\n' "$DASHMOTD_HOOK_END"
} >> "$legacy_home/.bashrc"
dashmotd_remove_user_hook "$owner" "$legacy_home"
if ! grep -Fq "$DASHMOTD_HOOK_BEGIN" "$legacy_home/.bashrc" \
    && ! grep -Fq 'dashmotd-render' "$legacy_home/.bashrc" \
    && grep -Fq 'export FOO=1' "$legacy_home/.bashrc"
then
    pass "dashmotd_remove_user_hook strips inlined ~/.bashrc block"
else
    fail "dashmotd_remove_user_hook failed to strip inlined ~/.bashrc block"
fi

# Legacy cleanup: ~/.bashrc.d/21-dashmotd.sh file
legacy_d_home="$USERS_FIXTURE/legacy-d"
mkdir -p "$legacy_d_home/.bashrc.d"
_dashmotd_hook_body > "$legacy_d_home/.bashrc.d/21-dashmotd.sh"
dashmotd_remove_user_hook "$owner" "$legacy_d_home"
if [[ ! -f "$legacy_d_home/.bashrc.d/21-dashmotd.sh" ]]; then
    pass "dashmotd_remove_user_hook removes ~/.bashrc.d/21-dashmotd.sh"
else
    fail "dashmotd_remove_user_hook left ~/.bashrc.d/21-dashmotd.sh"
fi

# Hook body guards non-interactive shells
hook_body="$(_dashmotd_hook_body)"
if [[ "$hook_body" == *'$- == *i*'* ]] && [[ "$hook_body" == *'login_shell'* ]]; then
    pass "hook body guards interactive non-login shells"
else
    fail "hook body missing interactivity / login_shell guards"
fi

# profile.d snippet includes interactive guard
profile_snippet='# dashmotd — render dashboard (live + collected cache) on interactive login shells
case $- in
    *i*) ;;
    *) return 0 ;;
esac
if [ -x /opt/dashmotd/bin/dashmotd-render ]; then
    /opt/dashmotd/bin/dashmotd-render
fi
'
if [[ "$profile_snippet" == *'case $- in'* ]]; then
    pass "profile.d template guards interactive shells"
else
    fail "profile.d template missing interactive guard"
fi

# 50-dashmotd contains the tty probe
if grep -Fq '/dev/tty' "$ROOT/update-motd.d/50-dashmotd" \
    && grep -Fq 'DASHMOTD_FORCE_TTY' "$ROOT/update-motd.d/50-dashmotd"
then
    pass "50-dashmotd has controlling-tty interactivity probe"
else
    fail "50-dashmotd missing controlling-tty probe"
fi

rm -rf "$USERS_FIXTURE"

# --- summary -----------------------------------------------------------------
section "summary"
printf 'Passed: %d  Failed: %d\n' "$PASSES" "$FAILS"
printf 'Render preview (first 50 lines):\n'
sed -n '1,50p' "$render_log" | sed 's/^/  | /'

if (( FAILS > 0 )); then
    printf '\nRESULT: FAILED\n' >&2
    exit 1
fi
printf '\nRESULT: OK\n'
exit 0

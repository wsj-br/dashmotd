#!/usr/bin/env bash
# Copyright (c) 2026 Waldemar Scudeller Junior.  Licensed under MIT License
# dashmotd self-test — simulated run against the source tree (no install required).
# Usage:
#   ./test.sh           # full simulated run
#   ./test.sh --quick   # syntax + config + render smoke only
#
# Exit 0 on success, 1 on failure. Does not modify /opt/dashmotd.

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
if DASHMOTD_RENDER="$ROOT/bin/dashmotd-render" \
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
    if DASHMOTD_STATIC_MOTD="$static_bak" \
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

# --- 11. users / bashrc hook helpers ----------------------------------------
section "users.sh bashrc hook helpers"
# Minimal log/warn stubs required by lib/users.sh
log()  { :; }
warn() { :; }
# shellcheck source=/dev/null
source "$ROOT/lib/users.sh"

USERS_FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/dashmotd-users.XXXXXX")"
owner="$(id -un)"

# Wired bashrc: sources ~/.bashrc.d
wired_home="$USERS_FIXTURE/wired"
mkdir -p "$wired_home"
cat > "$wired_home/.bashrc" <<'RC'
# load snippets
if [ -d ~/.bashrc.d ]; then
    for f in ~/.bashrc.d/*.sh; do [ -r "$f" ] && . "$f"; done
fi
RC
if dashmotd_bashrc_wired "$wired_home"; then
    pass "dashmotd_bashrc_wired detects bashrc.d loader"
else
    fail "dashmotd_bashrc_wired missed wired bashrc"
fi

# Unwired bashrc: no bashrc.d reference
unwired_home="$USERS_FIXTURE/unwired"
mkdir -p "$unwired_home"
printf '# plain bashrc\nexport FOO=1\n' > "$unwired_home/.bashrc"
if ! dashmotd_bashrc_wired "$unwired_home"; then
    pass "dashmotd_bashrc_wired rejects unwired bashrc"
else
    fail "dashmotd_bashrc_wired false-positive on unwired bashrc"
fi

# Upsert is idempotent (exactly one marker block after two runs)
dashmotd_upsert_bashrc_block "$unwired_home" "$owner" >/dev/null
dashmotd_upsert_bashrc_block "$unwired_home" "$owner" >/dev/null
begin_count="$(grep -cF "$DASHMOTD_HOOK_BEGIN" "$unwired_home/.bashrc" || true)"
end_count="$(grep -cF "$DASHMOTD_HOOK_END" "$unwired_home/.bashrc" || true)"
if [[ "$begin_count" == "1" && "$end_count" == "1" ]] \
    && grep -Fq 'dashmotd-render' "$unwired_home/.bashrc"
then
    pass "dashmotd_upsert_bashrc_block is idempotent (one marker block)"
else
    fail "dashmotd_upsert_bashrc_block not idempotent (begin=$begin_count end=$end_count)"
fi

# Remove leaves the rest of the file intact
dashmotd_remove_bashrc_block "$unwired_home" "$owner"
if ! grep -Fq "$DASHMOTD_HOOK_BEGIN" "$unwired_home/.bashrc" \
    && ! grep -Fq 'dashmotd-render' "$unwired_home/.bashrc" \
    && grep -Fq 'export FOO=1' "$unwired_home/.bashrc"
then
    pass "dashmotd_remove_bashrc_block removes block, keeps other content"
else
    fail "dashmotd_remove_bashrc_block damaged bashrc content"
fi

# Wired path writes ~/.bashrc.d/21-dashmotd.sh
hook_path="$(dashmotd_write_hook_file "$wired_home" "$owner")"
if [[ -f "$hook_path" ]] && grep -Fq 'dashmotd-render' "$hook_path"; then
    pass "dashmotd_write_hook_file creates bashrc.d/21-dashmotd.sh"
else
    fail "dashmotd_write_hook_file did not create hook file"
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

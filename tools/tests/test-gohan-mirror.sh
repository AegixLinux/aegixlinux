#!/usr/bin/env bash
# Test harness for tools/publish-gohan-mirror.sh against a scratch monorepo.
# Usage: ./test-gohan-mirror.sh
# Exits 0 if all asserts pass, non-zero otherwise.

set -euo pipefail

TESTS_RUN=0
TESTS_FAILED=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL="$(dirname "$SCRIPT_DIR")/publish-gohan-mirror.sh"

log()  { printf '\033[36m[test]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; TESTS_RUN=$((TESTS_RUN+1)); }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*"; TESTS_RUN=$((TESTS_RUN+1)); TESTS_FAILED=$((TESTS_FAILED+1)); }
assert_eq()       { [[ "$1" == "$2" ]] && pass "$3" || fail "$3 (expected=[$1] actual=[$2])"; }
assert_exists()   { [[ -e "$1" ]] && pass "$2" || fail "$2 (missing $1)"; }
assert_absent()   { [[ ! -e "$1" ]] && pass "$2" || fail "$2 (still present $1)"; }
assert_contains() { [[ "$1" == *"$2"* ]] && pass "$3" || fail "$3 (needle=[$2])"; }

WS="$(mktemp -d)"
trap 'rm -rf "$WS"' EXIT

make_fixture() {
    rm -rf "$WS/root"
    local skel="$WS/root/iso-profile/live-overlay/etc/skel"
    mkdir -p "$skel/.local/bin" "$skel/.local/src/dwm" "$skel/.config/shell" "$WS/root/sync" "$WS/root/gohan/.local/bin" "$WS/root/gohan/.cache/wal"
    echo 'new script'      > "$skel/.local/bin/wifimenu"
    echo 'menu v2'         > "$skel/.local/bin/dmenu-master"
    echo 'aliases'         > "$skel/.config/shell/aliasrc"
    echo 'dwm source'      > "$skel/.local/src/dwm/config.h"
    printf 'forbid\t${LIVE_USER}\tusername must not ship\n' > "$WS/root/sync/sanitize.rules"
    (cd "$WS/root/gohan" && git init -q && echo '# gohan' > README.md && echo MIT > LICENSE \
        && echo 'menu v1' > .local/bin/dmenu-master && echo 'stale' > .local/bin/oldscript \
        && echo 'generated' > .cache/wal/colors && echo 'aliases' > .config-placeholder \
        && git add -A && git -c user.name=t -c user.email=t@t commit -qm init \
        && echo 'plugged/' > .gitignore && mkdir -p plugged && echo 'local /home/leakyuser' > plugged/plugin.vim \
        && echo 'scratch' > untracked-note \
        && mkdir -p .config/pulse && echo 'tracked' > .config/pulse/daemon.conf && git add .config/pulse \
        && git -c user.name=t -c user.email=t@t commit -qm pulse && echo 'secret' > .config/pulse/cookie)
}

log "dry run reports and changes nothing"
make_fixture
out=$(AEGIX_ROOT="$WS/root" LIVE_USER=nobody-xyz "$TOOL")
assert_contains "$out" "add     .local/bin/wifimenu" "reports new file"
assert_contains "$out" "update  .local/bin/dmenu-master" "reports changed file"
assert_contains "$out" "delete  .local/bin/oldscript" "reports gohan-only file"
assert_contains "$out" "Dry run" "says dry run"
assert_absent "$WS/root/gohan/.local/bin/wifimenu" "dry run copies nothing"
assert_exists "$WS/root/gohan/.local/bin/oldscript" "dry run deletes nothing"

log "--apply mirrors skel, keeps repo files, skips .local/src"
out=$(AEGIX_ROOT="$WS/root" LIVE_USER=nobody-xyz "$TOOL" --apply)
assert_eq "new script" "$(cat "$WS/root/gohan/.local/bin/wifimenu")" "new file copied"
assert_eq "menu v2" "$(cat "$WS/root/gohan/.local/bin/dmenu-master")" "changed file updated"
assert_absent "$WS/root/gohan/.local/bin/oldscript" "gohan-only script deleted"
assert_absent "$WS/root/gohan/.cache/wal/colors" "gohan-only cache deleted"
assert_exists "$WS/root/gohan/README.md" "README kept"
assert_exists "$WS/root/gohan/LICENSE" "LICENSE kept"
assert_exists "$WS/root/gohan/.git" ".git kept"
assert_absent "$WS/root/gohan/.local/src" ".local/src not mirrored"
assert_contains "$out" "Leak gate passed" "leak gate runs"
assert_exists "$WS/root/gohan/plugged/plugin.vim" "gitignored local file untouched"
assert_exists "$WS/root/gohan/untracked-note" "untracked local file untouched"

log "second run is a no-op"
out=$(AEGIX_ROOT="$WS/root" LIVE_USER=nobody-xyz "$TOOL")
assert_eq "gohan mirror is current." "$out" "idempotent"

log "leak gate ignores gitignored files (they never publish)"
make_fixture
set +e
out=$(AEGIX_ROOT="$WS/root" LIVE_USER=leakyuser "$TOOL" --apply 2>&1); rc=$?
set -e
assert_eq 0 "$rc" "gitignored leak does not fail the gate"

log "leak gate fails on a forbidden pattern"
make_fixture
echo 'home=/home/leakyuser' > "$WS/root/iso-profile/live-overlay/etc/skel/.config/shell/aliasrc"
set +e
out=$(AEGIX_ROOT="$WS/root" LIVE_USER=leakyuser "$TOOL" --apply 2>&1); rc=$?
set -e
assert_eq 2 "$rc" "exit code 2 on leak"
assert_contains "$out" "LEAK GATE" "names the leak"

echo
if [[ $TESTS_FAILED -eq 0 ]]; then
    printf '\033[32mAll %d asserts passed.\033[0m\n' "$TESTS_RUN"
else
    printf '\033[31m%d of %d asserts failed.\033[0m\n' "$TESTS_FAILED" "$TESTS_RUN"; exit 1
fi

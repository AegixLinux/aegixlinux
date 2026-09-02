#!/usr/bin/env bash
# Test harness for tools/src-gate: the leak gate over standalone source repos.
# Fixture-isolated: builds throwaway git repos + a fixture sanitize.rules in
# mktemp, never touches real repos or the real rules.
# Usage: ./test-src-gate.sh
# Exits 0 if all asserts pass, non-zero otherwise.

set -euo pipefail

TESTS_RUN=0
TESTS_FAILED=0
WORKSPACE=""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS_DIR="$(dirname "$SCRIPT_DIR")"
SRC_GATE="$TOOLS_DIR/src-gate"

log()  { printf '\033[36m[test]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; TESTS_RUN=$((TESTS_RUN+1)); }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*"; TESTS_RUN=$((TESTS_RUN+1)); TESTS_FAILED=$((TESTS_FAILED+1)); }

assert_eq() {
  local expected="$1" actual="$2" msg="${3:-values equal}"
  if [[ "$expected" == "$actual" ]]; then
    pass "$msg"
  else
    fail "$msg (expected=[$expected] actual=[$actual])"
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" msg="${3:-contains needle}"
  if [[ "$haystack" == *"$needle"* ]]; then pass "$msg"; else fail "$msg (needle=[$needle])"; fi
}

setup_workspace() {
  WORKSPACE="$(mktemp -d /tmp/src-gate-test.XXXXXX)"
  export AEGIX_SYNC_DIR="$WORKSPACE/sync"
  mkdir -p "$AEGIX_SYNC_DIR"
  # Fixture rules: a username forbid, an IP forbid with one allowed placeholder.
  # LIVE_USER expansion is exercised via the env override.
  export LIVE_USER="fixtureuser"
  export LIVE_EMAIL="fixture@example.invalid"
  printf 'forbid\t${LIVE_USER}\tusername must not ship\n'         >  "$AEGIX_SYNC_DIR/sanitize.rules"
  printf 'forbid\t192\\.168\\.[0-9]+\\.[0-9]+\tprivate IPs\n'     >> "$AEGIX_SYNC_DIR/sanitize.rules"
  printf 'allow\t192\\.168\\.1\\.1\n'                             >> "$AEGIX_SYNC_DIR/sanitize.rules"
}

teardown_workspace() {
  [[ -n "$WORKSPACE" && -d "$WORKSPACE" ]] && rm -rf "$WORKSPACE"
  WORKSPACE=""
}

# make_repo <name>: create a git repo with one clean committed file, echo path.
make_repo() {
  local name="$1"
  local dir="$WORKSPACE/$name"
  mkdir -p "$dir"
  git -C "$dir" init -q -b main
  git -C "$dir" -c user.name=t -c user.email=t@t config commit.gpgsign false
  echo '#define BROWSER "brave"' > "$dir/config.h"
  git -C "$dir" add -A
  git -C "$dir" -c user.name=t -c user.email=t@t commit -qm init
  echo "$dir"
}

commit_all() {
  local dir="$1" msg="${2:-update}"
  git -C "$dir" add -A
  git -C "$dir" -c user.name=t -c user.email=t@t commit -qm "$msg"
}

run_gate() {
  # Runs src-gate, captures combined output; sets GATE_RC and GATE_OUT.
  set +e
  GATE_OUT="$("$SRC_GATE" "$@" 2>&1)"
  GATE_RC=$?
  set -e
}

# --- Tests ---

test_clean_repo_passes() {
  log "1. clean repo passes"
  setup_workspace
  local repo; repo="$(make_repo clean)"
  run_gate "$repo"
  assert_eq 0 "$GATE_RC" "clean repo exits 0"
  teardown_workspace
}

test_committed_forbid_fails() {
  log "2. forbid string committed in a text file fails"
  setup_workspace
  local repo; repo="$(make_repo dirty)"
  echo '#define BROWSER "/home/fixtureuser/.local/bin/brave"' > "$repo/config.h"
  commit_all "$repo"
  run_gate "$repo"
  assert_eq 1 "$GATE_RC" "committed leak exits 1"
  assert_contains "$GATE_OUT" "VERIFY FAIL" "failure names the standard VERIFY FAIL line"
  assert_contains "$GATE_OUT" "config.h" "failure names the offending file"
  teardown_workspace
}

test_uncommitted_forbid_passes() {
  log "3. forbid string only in working tree passes (gate checks HEAD)"
  setup_workspace
  local repo; repo="$(make_repo wt)"
  echo 'scratch note for fixtureuser only' > "$repo/notes.txt"   # NOT committed
  run_gate "$repo"
  assert_eq 0 "$GATE_RC" "uncommitted leak cannot be pushed, exits 0"
  teardown_workspace
}

test_committed_binary_fails() {
  log "4. committed binary with embedded secret fails hard (past a NUL run)"
  setup_workspace
  local repo; repo="$(make_repo bin)"
  # Secret sits after 512 NUL bytes: the exact class bash var transit mangles.
  { head -c 512 /dev/zero; printf 'built by fixtureuser'; head -c 64 /dev/zero; } > "$repo/dwm.o"
  commit_all "$repo"
  run_gate "$repo"
  assert_eq 1 "$GATE_RC" "committed binary leak exits 1"
  assert_contains "$GATE_OUT" "binary content matches" "binary path uses the hard-fail scan"
  teardown_workspace
}

test_allow_is_match_scoped() {
  log "5. allow-listed placeholder passes; unlisted IP on same line still fails"
  setup_workspace
  local repo; repo="$(make_repo allow)"
  echo 'gateway=192.168.1.1' > "$repo/net.conf"
  commit_all "$repo"
  run_gate "$repo"
  assert_eq 0 "$GATE_RC" "allowed placeholder alone exits 0"

  echo 'gateway=192.168.1.1 target=192.168.7.42' > "$repo/net.conf"
  commit_all "$repo"
  run_gate "$repo"
  assert_eq 1 "$GATE_RC" "unlisted IP beside allowed one still exits 1"
  teardown_workspace
}

test_empty_repo_errors() {
  log "6. repo with no commits errors, does not silently pass"
  setup_workspace
  local dir="$WORKSPACE/empty"
  mkdir -p "$dir"
  git -C "$dir" init -q -b main
  run_gate "$dir"
  if [[ "$GATE_RC" -ne 0 ]]; then
    pass "empty repo exits non-zero"
  else
    fail "empty repo exited 0 (silent pass)"
  fi
  teardown_workspace
}

test_multi_repo_any_failure_fails() {
  log "7. multiple repos: one dirty repo fails the whole run"
  setup_workspace
  local clean dirty
  clean="$(make_repo multi-clean)"
  dirty="$(make_repo multi-dirty)"
  echo 'owner fixtureuser' > "$dirty/config.h"
  commit_all "$dirty"
  run_gate "$clean" "$dirty"
  assert_eq 1 "$GATE_RC" "one dirty repo of two exits 1"
  assert_contains "$GATE_OUT" "multi-dirty" "output names the dirty repo"
  teardown_workspace
}

# --- Run ---

trap 'teardown_workspace' EXIT

test_clean_repo_passes
test_committed_forbid_fails
test_uncommitted_forbid_passes
test_committed_binary_fails
test_allow_is_match_scoped
test_empty_repo_errors
test_multi_repo_any_failure_fails

echo
if [[ "$TESTS_FAILED" -eq 0 ]]; then
  printf '\033[32mAll %d assertions passed.\033[0m\n' "$TESTS_RUN"
  exit 0
else
  printf '\033[31m%d of %d assertions FAILED.\033[0m\n' "$TESTS_FAILED" "$TESTS_RUN"
  exit 1
fi

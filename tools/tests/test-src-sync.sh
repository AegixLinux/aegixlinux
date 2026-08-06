#!/usr/bin/env bash
# Test harness for aegix-src-sync. Runs against disposable tmp git repos.
# Usage: ./test-src-sync.sh
# Exits 0 if all asserts pass, non-zero otherwise.

set -euo pipefail

# --- Test state ---
TESTS_RUN=0
TESTS_FAILED=0
WORKSPACE=""

# --- Resolve repo-under-test root ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS_DIR="$(dirname "$SCRIPT_DIR")"

# --- Helpers ---

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

assert_file_exists() {
  local path="$1" msg="${2:-file exists: $1}"
  if [[ -e "$path" ]]; then pass "$msg"; else fail "$msg (path=$path)"; fi
}

assert_contains() {
  local haystack="$1" needle="$2" msg="${3:-contains needle}"
  if [[ "$haystack" == *"$needle"* ]]; then pass "$msg"; else fail "$msg (needle=[$needle] haystack=[$haystack])"; fi
}

# --- Fake repo builders ---

setup_workspace() {
  WORKSPACE="$(mktemp -d -t aegix-src-sync-test.XXXXXX)"
  log "workspace: $WORKSPACE"
  mkdir -p "$WORKSPACE/bare" "$WORKSPACE/live" "$WORKSPACE/aegix"
}

teardown_workspace() {
  if [[ -n "$WORKSPACE" && -d "$WORKSPACE" ]]; then
    rm -rf "$WORKSPACE"
  fi
}

# Build a fake repo pair: a bare "remote", a "live" clone, and an "AEGIX parent"
# that has the live repo as a submodule pointing at the bare.
# Args: $1 = repo name (e.g. "dwm")
# Populates: $WORKSPACE/{bare,live,aegix}/<repo>
build_fake_pair() {
  local name="$1"
  git init --bare -q "$WORKSPACE/bare/$name.git"

  # Seed the bare with an initial commit via a scratch clone
  local scratch="$WORKSPACE/.scratch-$name"
  git clone -q "$WORKSPACE/bare/$name.git" "$scratch"
  ( cd "$scratch"
    git config user.email "test@example.com"
    git config user.name "Test"
    echo "initial $name" > README.md
    git add README.md
    git commit -q -m "initial $name commit"
    git branch -M master
    git push -q origin master )
  rm -rf "$scratch"
  # Fix HEAD in bare repo to point to master (not main)
  git -C "$WORKSPACE/bare/$name.git" symbolic-ref HEAD refs/heads/master >/dev/null 2>&1 || true

  # Live clone
  git clone -q "$WORKSPACE/bare/$name.git" "$WORKSPACE/live/$name"
  ( cd "$WORKSPACE/live/$name"
    git config user.email "test@example.com"
    git config user.name "Test" )

  # AEGIX parent with a submodule pointing at the bare
  if [[ ! -d "$WORKSPACE/aegix/.git" ]]; then
    git init -q "$WORKSPACE/aegix"
    ( cd "$WORKSPACE/aegix"
      git config user.email "test@example.com"
      git config user.name "Test"
      echo "# AEGIX fake" > README.md
      git add README.md
      git commit -q -m "initial aegix commit"
      git branch -M master )
  fi
  ( cd "$WORKSPACE/aegix"
    git -c protocol.file.allow=always submodule add -q "$WORKSPACE/bare/$name.git" "$name"
    git commit -q -m "add $name submodule" )
}

# Write a temporary conf file listing fake pairs.
# Args: $@ = repo names
write_fake_conf() {
  local conf="$WORKSPACE/src-sync.conf"
  : > "$conf"
  for name in "$@"; do
    printf '%s/live/%s  %s/aegix/%s\n' "$WORKSPACE" "$name" "$WORKSPACE" "$name" >> "$conf"
  done
  echo "$conf"
}

# run_test: run a test function in a fresh workspace.
# Ensures each test gets isolated fake repos — no cross-test state.
# Args: $1 = test function name (must be already defined)
run_test() {
  local fn="$1"
  setup_workspace
  "$fn"
  teardown_workspace
  WORKSPACE=""
}

# --- Test: parse_conf ---
test_parse_conf() {
  log "test_parse_conf"
  local conf="$WORKSPACE/conf-basic"
  cat > "$conf" <<EOF
# A comment
~/.local/src/dwm           ~/code/PROJECTS/AEGIX/dwm

~/.local/src/st            ~/code/PROJECTS/AEGIX/st
EOF

  source "$TOOLS_DIR/src-sync-lib.sh"
  local lines
  lines="$(parse_conf "$conf")"
  assert_eq "2" "$(echo "$lines" | wc -l | tr -d ' ')" "parse_conf ignores comments and blanks"

  local first_line
  first_line="$(echo "$lines" | head -1)"
  assert_contains "$first_line" "/.local/src/dwm" "first entry contains dwm path"
  assert_contains "$first_line" "/code/PROJECTS/AEGIX/dwm" "first entry contains aegix dwm path"
}

# --- Test: find_aegix_path ---
test_find_aegix_path() {
  log "test_find_aegix_path"
  local conf="$WORKSPACE/conf-lookup"
  cat > "$conf" <<EOF
/home/user/.local/src/dwm  /home/user/code/AEGIX/dwm
/home/user/.local/src/st   /home/user/code/AEGIX/st
EOF

  source "$TOOLS_DIR/src-sync-lib.sh"
  local got
  got="$(find_aegix_path "$conf" "/home/user/.local/src/dwm")"
  assert_eq "/home/user/code/AEGIX/dwm" "$got" "find_aegix_path resolves dwm"

  got="$(find_aegix_path "$conf" "/home/user/.local/src/nope" || echo NOTFOUND)"
  assert_eq "NOTFOUND" "$got" "find_aegix_path returns error for unknown repo"
}

# --- Test: find_aegix_path drains parse_conf (no EPIPE noise in hooks) ---
# find_aegix_path used to return from inside its read loop on the first match,
# closing the process substitution while parse_conf was still writing the rest
# of the conf. git runs hooks with SIGPIPE ignored, so those writes failed
# loudly with "printf: write error: Broken pipe" -- once per entry after the
# match, on every single commit. Match on the FIRST of several entries so a
# regression has something left to write, and ignore SIGPIPE as git does.
test_find_aegix_path_no_sigpipe() {
  log "test_find_aegix_path_no_sigpipe"
  local conf="$WORKSPACE/conf-sigpipe"
  {
    echo "/home/user/.local/src/dwm  /home/user/code/AEGIX/dwm"
    local i
    for i in 1 2 3 4 5 6 7 8; do
      echo "/home/user/.local/src/pad$i  /home/user/code/AEGIX/pad$i"
    done
  } > "$conf"

  # stdout is discarded inside the group, so 2>&1 captures stderr only.
  local stderr_out
  stderr_out="$( {
    trap '' PIPE
    source "$TOOLS_DIR/src-sync-lib.sh"
    find_aegix_path "$conf" "/home/user/.local/src/dwm" >/dev/null
  } 2>&1 )"
  assert_eq "" "$stderr_out" "find_aegix_path writes nothing to stderr when SIGPIPE is ignored"
}

# --- Test: log_line ---
test_log_line() {
  log "test_log_line"
  local logfile="$WORKSPACE/log-test"
  source "$TOOLS_DIR/src-sync-lib.sh"
  SRC_SYNC_LOG="$logfile" log_line "dwm" "OK" "abc123..def456 staged"
  assert_file_exists "$logfile" "log file created"
  local content
  content="$(cat "$logfile")"
  assert_contains "$content" "dwm" "log contains repo name"
  assert_contains "$content" "OK" "log contains status"
  assert_contains "$content" "abc123..def456" "log contains detail"
}

# --- Test: sync_repo happy path ---
test_sync_repo_happy() {
  log "test_sync_repo_happy"
  build_fake_pair "dwm"
  source "$TOOLS_DIR/src-sync-lib.sh"

  # Capture AEGIX submodule HEAD before
  local before_aegix_head
  before_aegix_head="$(git -C "$WORKSPACE/aegix/dwm" rev-parse HEAD)"

  # Make a commit in live
  ( cd "$WORKSPACE/live/dwm"
    echo "live change" >> README.md
    git add README.md
    git commit -q -m "live change" )
  local live_head
  live_head="$(git -C "$WORKSPACE/live/dwm" rev-parse HEAD)"

  # Call sync_repo (log to a test file)
  SRC_SYNC_LOG="$WORKSPACE/sync.log" \
    sync_repo "$WORKSPACE/live/dwm" "$WORKSPACE/aegix/dwm" "$WORKSPACE/aegix"

  # AEGIX submodule HEAD should now match live HEAD
  local after_aegix_head
  after_aegix_head="$(git -C "$WORKSPACE/aegix/dwm" rev-parse HEAD)"
  assert_eq "$live_head" "$after_aegix_head" "aegix submodule HEAD matches live HEAD"

  # AEGIX parent should have the submodule staged
  local staged
  staged="$(git -C "$WORKSPACE/aegix" diff --cached --name-only)"
  assert_eq "dwm" "$staged" "aegix parent has dwm staged"

  # Log entry should exist and mark OK
  local logline
  logline="$(cat "$WORKSPACE/sync.log" 2>/dev/null || echo MISSING)"
  assert_contains "$logline" "OK" "log line says OK"
  assert_contains "$logline" "dwm" "log line names dwm"
}

# --- Test: hook triggers sync on master commit ---
test_hook_on_master() {
  log "test_hook_on_master"
  build_fake_pair "dwm"
  local conf
  conf="$(write_fake_conf dwm)"

  # Install hook in fake live/dwm
  ln -sf "$TOOLS_DIR/src-sync-post-commit" "$WORKSPACE/live/dwm/.git/hooks/post-commit"
  chmod +x "$TOOLS_DIR/src-sync-post-commit"

  ( cd "$WORKSPACE/live/dwm"
    echo "hook change" >> README.md
    git add README.md
    SRC_SYNC_CONF="$conf" \
    SRC_SYNC_AEGIX_PARENT="$WORKSPACE/aegix" \
    SRC_SYNC_LOG="$WORKSPACE/hook.log" \
      git commit -q -m "hook-triggered change" )

  # Assert AEGIX advanced
  local live_head aegis_head
  live_head="$(git -C "$WORKSPACE/live/dwm" rev-parse HEAD)"
  aegis_head="$(git -C "$WORKSPACE/aegix/dwm" rev-parse HEAD)"
  assert_eq "$live_head" "$aegis_head" "hook advanced AEGIX submodule HEAD"

  # Log has OK
  assert_contains "$(cat "$WORKSPACE/hook.log")" "OK" "hook wrote OK log entry"
}

# --- Test: hook skips on non-master branch ---
test_hook_skips_feature_branch() {
  log "test_hook_skips_feature_branch"
  build_fake_pair "st"
  local conf
  conf="$(write_fake_conf st)"
  ln -sf "$TOOLS_DIR/src-sync-post-commit" "$WORKSPACE/live/st/.git/hooks/post-commit"

  local aegis_head_before
  aegis_head_before="$(git -C "$WORKSPACE/aegix/st" rev-parse HEAD)"

  ( cd "$WORKSPACE/live/st"
    git checkout -q -b feature/foo
    echo "feature change" >> README.md
    git add README.md
    SRC_SYNC_CONF="$conf" \
    SRC_SYNC_AEGIX_PARENT="$WORKSPACE/aegix" \
    SRC_SYNC_LOG="$WORKSPACE/hook.log" \
      git commit -q -m "feature change" )

  local aegis_head_after
  aegis_head_after="$(git -C "$WORKSPACE/aegix/st" rev-parse HEAD)"
  assert_eq "$aegis_head_before" "$aegis_head_after" "AEGIX st HEAD unchanged after feature-branch commit"

  assert_contains "$(cat "$WORKSPACE/hook.log")" "SKIP" "hook logged SKIP for non-master"
}

# --- Test: hook also syncs on a `main` branch ---
# Aegix is standardising on main. The precondition used to accept only master,
# and it skips *quietly* -- so after a rename the first symptom would have been
# submodule pointers silently going stale rather than any visible error.
test_hook_on_main() {
  log "test_hook_on_main"
  build_fake_pair "dmenu"
  local conf
  conf="$(write_fake_conf dmenu)"
  ln -sf "$TOOLS_DIR/src-sync-post-commit" "$WORKSPACE/live/dmenu/.git/hooks/post-commit"

  ( cd "$WORKSPACE/live/dmenu"
    git branch -M main
    echo "main-branch change" >> README.md
    git add README.md
    SRC_SYNC_CONF="$conf" \
    SRC_SYNC_AEGIX_PARENT="$WORKSPACE/aegix" \
    SRC_SYNC_LOG="$WORKSPACE/hook.log" \
      git commit -q -m "change on main" )

  local live_head aegis_head
  live_head="$(git -C "$WORKSPACE/live/dmenu" rev-parse HEAD)"
  aegis_head="$(git -C "$WORKSPACE/aegix/dmenu" rev-parse HEAD)"
  assert_eq "$live_head" "$aegis_head" "hook advanced AEGIX submodule HEAD from a main branch"
}

# --- Test: hook backs up dirty AEGIX submodule before reset ---
test_hook_backs_up_dirty_aegix() {
  log "test_hook_backs_up_dirty_aegix"
  build_fake_pair "dmenu"
  local conf
  conf="$(write_fake_conf dmenu)"
  ln -sf "$TOOLS_DIR/src-sync-post-commit" "$WORKSPACE/live/dmenu/.git/hooks/post-commit"

  # Dirty the AEGIX submodule
  echo "aegix-side edit" >> "$WORKSPACE/aegix/dmenu/README.md"

  ( cd "$WORKSPACE/live/dmenu"
    echo "live change" >> README.md
    git add README.md
    SRC_SYNC_CONF="$conf" \
    SRC_SYNC_AEGIX_PARENT="$WORKSPACE/aegix" \
    SRC_SYNC_LOG="$WORKSPACE/hook.log" \
    SRC_SYNC_BACKUP_DIR="$WORKSPACE/backups" \
      git commit -q -m "live change with dirty aegix" )

  # A backup patch should exist
  local backup_count
  backup_count="$(find "$WORKSPACE/backups" -name 'dmenu-aegix-wip-*.patch' 2>/dev/null | wc -l | tr -d ' ')"
  assert_eq "1" "$backup_count" "backup patch was written"
}

# --- Test: sync-one.sh runs the core sync against a named repo ---
test_sync_one() {
  log "test_sync_one"
  build_fake_pair "dwmblocks"
  local conf
  conf="$(write_fake_conf dwmblocks)"

  # Make a commit in live WITHOUT any hook (simulating the "hook bailed" case)
  ( cd "$WORKSPACE/live/dwmblocks"
    echo "manual change" >> README.md
    git add README.md
    git commit -q -m "manual change" )
  local live_head
  live_head="$(git -C "$WORKSPACE/live/dwmblocks" rev-parse HEAD)"

  # Run sync-one.sh manually with overrides
  SRC_SYNC_CONF="$conf" \
  SRC_SYNC_AEGIX_PARENT="$WORKSPACE/aegix" \
  SRC_SYNC_LOG="$WORKSPACE/sync-one.log" \
    bash "$TOOLS_DIR/sync-one.sh" dwmblocks

  local aegix_head
  aegix_head="$(git -C "$WORKSPACE/aegix/dwmblocks" rev-parse HEAD)"
  assert_eq "$live_head" "$aegix_head" "sync-one advanced AEGIX submodule"
  assert_contains "$(cat "$WORKSPACE/sync-one.log")" "OK" "sync-one log says OK"
}

# --- Test: installer symlinks the hook and is idempotent ---
test_installer() {
  log "test_installer"
  build_fake_pair "dwm"
  build_fake_pair "st"
  local conf
  conf="$(write_fake_conf dwm st)"

  SRC_SYNC_CONF="$conf" bash "$TOOLS_DIR/install-src-sync.sh" >/dev/null

  assert_file_exists "$WORKSPACE/live/dwm/.git/hooks/post-commit" "dwm hook installed"
  assert_file_exists "$WORKSPACE/live/st/.git/hooks/post-commit" "st hook installed"

  # Idempotency: second run should not fail
  SRC_SYNC_CONF="$conf" bash "$TOOLS_DIR/install-src-sync.sh" >/dev/null
  assert_file_exists "$WORKSPACE/live/dwm/.git/hooks/post-commit" "hook still present after rerun"

  # Symlink points at the expected target
  local target
  target="$(readlink "$WORKSPACE/live/dwm/.git/hooks/post-commit")"
  assert_eq "$TOOLS_DIR/src-sync-post-commit" "$target" "hook symlink points at template"
}

# --- Test: bootstrap reconciles divergent repos, live wins ---
test_bootstrap_reconcile() {
  log "test_bootstrap_reconcile"
  build_fake_pair "dwm"
  local conf
  conf="$(write_fake_conf dwm)"

  # Diverge: commit in live (push), commit separately in aegix submodule
  ( cd "$WORKSPACE/live/dwm"
    echo "live-only" >> README.md
    git add README.md
    git commit -q -m "live ahead"
    git push -q origin master )

  # Aegix-side dirty edit
  echo "aegix-side edit" >> "$WORKSPACE/aegix/dwm/README.md"

  SRC_SYNC_CONF="$conf" \
  SRC_SYNC_AEGIX_PARENT="$WORKSPACE/aegix" \
  SRC_SYNC_BACKUP_DIR="$WORKSPACE/backups" \
  SRC_SYNC_LOG="$WORKSPACE/bootstrap.log" \
  SRC_SYNC_SKIP_REMOTE_SWAP=1 \
    bash "$TOOLS_DIR/bootstrap-src-sync.sh" >/dev/null

  # Backup exists
  local backup_count
  backup_count="$(find "$WORKSPACE/backups" -name 'dwm-aegix-wip-*.patch' 2>/dev/null | wc -l | tr -d ' ')"
  assert_eq "1" "$backup_count" "bootstrap wrote backup patch"

  # Aegix now matches live
  local live_head aegix_head
  live_head="$(git -C "$WORKSPACE/live/dwm" rev-parse HEAD)"
  aegix_head="$(git -C "$WORKSPACE/aegix/dwm" rev-parse HEAD)"
  assert_eq "$live_head" "$aegix_head" "bootstrap reset AEGIX submodule to live HEAD"

  # Staged bump
  local staged
  staged="$(git -C "$WORKSPACE/aegix" diff --cached --name-only)"
  assert_contains "$staged" "dwm" "bootstrap staged aegix pointer bump"
}

# --- Test: bootstrap --dry-run touches nothing ---
test_bootstrap_dry_run() {
  log "test_bootstrap_dry_run"
  build_fake_pair "st"
  local conf
  conf="$(write_fake_conf st)"

  ( cd "$WORKSPACE/live/st"
    echo "live-only" >> README.md
    git add README.md
    git commit -q -m "live ahead"
    git push -q origin master )

  local aegix_head_before
  aegix_head_before="$(git -C "$WORKSPACE/aegix/st" rev-parse HEAD)"

  SRC_SYNC_CONF="$conf" \
  SRC_SYNC_AEGIX_PARENT="$WORKSPACE/aegix" \
  SRC_SYNC_BACKUP_DIR="$WORKSPACE/backups" \
  SRC_SYNC_SKIP_REMOTE_SWAP=1 \
    bash "$TOOLS_DIR/bootstrap-src-sync.sh" --dry-run >/dev/null

  local aegix_head_after
  aegix_head_after="$(git -C "$WORKSPACE/aegix/st" rev-parse HEAD)"
  assert_eq "$aegix_head_before" "$aegix_head_after" "dry-run left aegix HEAD unchanged"
}

run_all_tests() {
  run_test test_parse_conf
  run_test test_find_aegix_path
  run_test test_find_aegix_path_no_sigpipe
  run_test test_log_line
  run_test test_sync_repo_happy
  run_test test_hook_on_master
  run_test test_hook_skips_feature_branch
  run_test test_hook_on_main
  run_test test_hook_backs_up_dirty_aegix
  run_test test_sync_one
  run_test test_installer
  run_test test_bootstrap_reconcile
  run_test test_bootstrap_dry_run
}

# --- Entry point ---

# Safety net: if a test crashes mid-run, still clean up the current workspace.
trap teardown_workspace EXIT
run_all_tests

printf '\n'
if [[ $TESTS_FAILED -eq 0 ]]; then
  log "$TESTS_RUN test(s) passed"
  exit 0
else
  log "$TESTS_FAILED of $TESTS_RUN test(s) failed"
  exit 1
fi

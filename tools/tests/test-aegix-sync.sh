#!/usr/bin/env bash
# Test harness for aegix-sync library. Tests files.manifest parsing and lookup.
# Usage: ./test-aegix-sync.sh
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

# --- Setup and teardown ---

setup_workspace() {
  WORKSPACE="$(mktemp -d /tmp/aegix-sync-test.XXXXXX)"
  export AEGIX_SYNC_HOME="$WORKSPACE/home"
  export AEGIX_SYNC_REPO="$WORKSPACE/repo"
  export AEGIX_SYNC_PROFILE="$WORKSPACE/repo/iso-profile"
  export AEGIX_SYNC_DIR="$WORKSPACE/repo/sync"
  export AEGIX_SYNC_SKEL="$AEGIX_SYNC_PROFILE/live-overlay/etc/skel"
  mkdir -p "$AEGIX_SYNC_HOME" "$AEGIX_SYNC_DIR" \
           "$AEGIX_SYNC_PROFILE/live-overlay/etc/skel"
}

teardown() {
  rm -rf "$WORKSPACE"
}

# --- Source library once at top ---
source "$TOOLS_DIR/aegix-sync-lib.sh"

# --- Tests ---

test_fm_load_and_lookup() {
  log "files.manifest: load + precedence"
  setup_workspace
  printf 'ship\t.config/zsh/\nnever\t.config/zsh/private/\nship\t.zshenv\nwatch\t.local/bin/\n' \
    > "$AEGIX_SYNC_DIR/files.manifest"

  fm_load "$AEGIX_SYNC_DIR/files.manifest"
  assert_eq "ship"      "$(fm_lookup .config/zsh/.zshrc)"          "dir prefix ships"
  assert_eq "never"     "$(fm_lookup .config/zsh/private/token)"    "longer pattern wins"
  assert_eq "ship"      "$(fm_lookup .zshenv)"                      "exact file"
  assert_eq "undecided" "$(fm_lookup .local/bin/newscript)"         "watch alone decides nothing"

  teardown
}

test_fm_load_rejects_contradiction() {
  log "files.manifest: contradiction is a load error"
  setup_workspace
  printf 'ship\t.zshenv\nnever\t.zshenv\n' > "$AEGIX_SYNC_DIR/files.manifest"
  local rc=0
  ( source "$TOOLS_DIR/aegix-sync-lib.sh"; fm_load "$AEGIX_SYNC_DIR/files.manifest" ) 2>/dev/null || rc=$?
  assert_eq "1" "$rc" "contradictory decisions rejected"
  teardown
}

test_pm_load_and_diff() {
  log "packages.manifest: load + pacman diff"
  setup_workspace
  cat > "$AEGIX_SYNC_DIR/packages.manifest" <<'EOF'
rootfs,barbs	xorg-server	"is the graphical server"
rootfs	sxiv	"is a minimalist image viewer"
aur	brave-bin	"privacy browser"
git	dwm	https://github.com/aegixlinux/dwm.git	"window manager"
livefs	gparted	"partitioner (live session only)"
never	electrum
EOF
  pm_load "$AEGIX_SYNC_DIR/packages.manifest"
  assert_eq "rootfs,barbs" "${PM_TAGS[xorg-server]}" "tag set parsed"
  assert_eq "https://github.com/aegixlinux/dwm.git" "${PM_URL[dwm]}" "git url parsed"
  printf 'xorg-server\nsxiv\nbtop\nelectrum\n' > "$WORKSPACE/installed"
  assert_eq "btop" "$(pm_new_packages "$WORKSPACE/installed")" "new pkg found, never pkg not re-asked"
  assert_eq "brave-bin
dwm" "$(pm_gone_packages "$WORKSPACE/installed")" "gone pkgs exclude never + livefs-only"
  teardown
}

test_pm_load_rejects_never_contradiction() {
  log "packages.manifest: never must be sole tag"
  setup_workspace
  printf 'never,rootfs\tfoo\n' > "$AEGIX_SYNC_DIR/packages.manifest"
  local rc=0
  ( source "$TOOLS_DIR/aegix-sync-lib.sh"; pm_load "$AEGIX_SYNC_DIR/packages.manifest" ) 2>/dev/null || rc=$?
  assert_eq "1" "$rc" "never as non-sole tag rejected"
  teardown
}

test_sanitize_tree() {
  log "sanitize: sub, strip-line, strip-block, glob scoping, placeholders"
  setup_workspace
  export LIVE_USER=fakeuser LIVE_EMAIL=fake@example.com
  local skel="$AEGIX_SYNC_PROFILE/live-overlay/etc/skel"
  mkdir -p "$skel/.config/shell" "$skel/.local/bin"
  cat > "$skel/.config/shell/aliasrc" <<'EOF'
alias v=nvim
# ===== PERSONAL: DO NOT SYNC TO AEGIX =====
alias work='ssh fakeuser@10.0.0.5'
# ===== END PERSONAL =====
pubkey=AAAA
echo /home/fakeuser/notes
EOF
  printf 'ping_thing_1="10.9.8.7"\n' > "$skel/.local/bin/ploop"
  cat > "$AEGIX_SYNC_DIR/sanitize.rules" <<'EOF'
strip-block	^# ===== PERSONAL: DO NOT SYNC TO AEGIX =====	^# ===== END PERSONAL =====
strip-line	pubkey=
sub	/home/${LIVE_USER}	$HOME
sub	ping_thing_1="[0-9.]+"	ping_thing_1="192.168.1.1"	live-overlay/etc/skel/.local/bin/ploop
EOF
  rules_load "$AEGIX_SYNC_DIR/sanitize.rules"
  sanitize_tree "$AEGIX_SYNC_PROFILE"
  local out; out="$(cat "$skel/.config/shell/aliasrc")"
  assert_contains "$out" "alias v=nvim" "benign line kept"
  assert_eq "" "$(grep -c fakeuser "$skel/.config/shell/aliasrc" | grep -v '^0$' || true)" "personal block + home path gone"
  assert_contains "$out" '$HOME/notes' "home path rewritten"
  assert_eq 'ping_thing_1="192.168.1.1"' "$(cat "$skel/.local/bin/ploop")" "glob-scoped sub applied"
  teardown
}

test_verify_gate_blocks_leak() {
  log "verify: planted leak aborts; allowlist suppresses"
  setup_workspace
  unset LIVE_USER LIVE_EMAIL  # clear from prior test
  local skel="$AEGIX_SYNC_PROFILE/live-overlay/etc/skel"
  mkdir -p "$skel"
  printf 'PGPASSWORD=$(pass pg-prod-x) psql\n' > "$skel/badfile"
  printf 'ping 192.168.1.1\n' > "$skel/okfile"
  cat > "$AEGIX_SYNC_DIR/sanitize.rules" <<'EOF'
forbid	pass (pg|otp)-	pass-store reference
forbid	PGPASSWORD	db password
forbid	192\.168\.[0-9]+\.[0-9]+	private IP
allow	192\.168\.1\.1
EOF
  rules_load "$AEGIX_SYNC_DIR/sanitize.rules"
  local rc=0; verify_tree "$AEGIX_SYNC_PROFILE" 2>"$WORKSPACE/hits" || rc=$?
  assert_eq "1" "$rc" "leak blocks"
  assert_contains "$(cat "$WORKSPACE/hits")" "badfile" "hit names the file"
  rm "$skel/badfile"
  rc=0; verify_tree "$AEGIX_SYNC_PROFILE" 2>/dev/null || rc=$?
  assert_eq "0" "$rc" "allowlisted placeholder passes"
  teardown
}

test_verify_gate_match_scoped_allow() {
  log "verify: allow is match-scoped, not line-scoped"
  setup_workspace
  unset LIVE_USER LIVE_EMAIL
  local skel="$AEGIX_SYNC_PROFILE/live-overlay/etc/skel"
  mkdir -p "$skel"
  # Line with multiple forbid matches: PGPASSWORD leak, pass-store ref, AND allowed IP
  printf 'alias dbwork="PGPASSWORD=$(pass pg-prod-x) psql -h 192.168.1.1"\n' > "$skel/cooccur"
  # Line with only allowed IP
  printf 'ping 192.168.1.1\n' > "$skel/iponly"
  cat > "$AEGIX_SYNC_DIR/sanitize.rules" <<'EOF'
forbid	pass (pg|otp)-	pass-store reference
forbid	PGPASSWORD	db password
forbid	192\.168\.[0-9]+\.[0-9]+	private IP
allow	192\.168\.1\.1
EOF
  rules_load "$AEGIX_SYNC_DIR/sanitize.rules"
  local rc=0; verify_tree "$AEGIX_SYNC_PROFILE" 2>"$WORKSPACE/hits" || rc=$?
  assert_eq "1" "$rc" "cooccur line blocks (forbids not suppressed by unrelated allow)"
  assert_contains "$(cat "$WORKSPACE/hits")" "PGPASSWORD" "PGPASSWORD leak reported"
  assert_contains "$(cat "$WORKSPACE/hits")" "pass pg-prod-x" "pass-store leak reported"
  assert_contains "$(cat "$WORKSPACE/hits")" "cooccur" "cooccur filename in output"
  teardown
}

test_verify_gate_nonexistent_root() {
  log "verify: nonexistent root fails loudly"
  setup_workspace
  cat > "$AEGIX_SYNC_DIR/sanitize.rules" <<'EOF'
forbid	badpat	test
EOF
  rules_load "$AEGIX_SYNC_DIR/sanitize.rules"
  local rc=0; verify_tree "$WORKSPACE/nonexistent" 2>"$WORKSPACE/err" || rc=$?
  assert_eq "1" "$rc" "nonexistent root returns 1"
  assert_contains "$(cat "$WORKSPACE/err")" "root not found" "error message on stderr"
  teardown
}

test_verify_gate_binary_content() {
  log "verify: forbidden string past a long NUL run in binary content is not vacuously suppressed"
  setup_workspace
  unset LIVE_USER LIVE_EMAIL
  local skel="$AEGIX_SYNC_PROFILE/live-overlay/etc/skel"
  mkdir -p "$skel"
  # A real compiled binary's NUL runs are hundreds of bytes long, not a
  # couple of stray bytes: bash's `read`/`$()` were verified to silently
  # truncate content at that scale (grep itself reports the full ~KB
  # matching line; a bash variable captured only the first few dozen bytes),
  # which is exactly what made the old text-path "fix" (grep -a into a bash
  # variable) pass vacuously on real binaries despite working on toy
  # fixtures. verify_tree must never pipe binary content through bash at
  # all — it greps the file directly instead.
  { head -c 200 /dev/zero; printf 'pass pg-secret'; head -c 200 /dev/zero; } > "$skel/binaryfile"
  cat > "$AEGIX_SYNC_DIR/sanitize.rules" <<'EOF'
forbid	pass (pg|otp)-	pass-store reference
EOF
  rules_load "$AEGIX_SYNC_DIR/sanitize.rules"
  local rc=0; verify_tree "$AEGIX_SYNC_PROFILE" 2>"$WORKSPACE/hits" || rc=$?
  assert_eq "1" "$rc" "leak past long NUL run blocks"
  assert_contains "$(cat "$WORKSPACE/hits")" "binaryfile" "binary file named in output"
  teardown
}

test_verify_gate_binary_compiled() {
  log "verify: forbidden string in .rodata of a real compiled binary blocks"
  setup_workspace
  unset LIVE_USER LIVE_EMAIL
  local cc; cc="$(command -v cc || command -v gcc || true)"
  if [[ -z "$cc" ]]; then
    log "SKIP: no C compiler available, skipping compiled-binary verify test"
    teardown
    return 0
  fi
  local skel="$AEGIX_SYNC_PROFILE/live-overlay/etc/skel"
  mkdir -p "$skel"
  cat > "$WORKSPACE/leak.c" <<'EOF'
static const char secret[] = "pass pg-secret";
int main(void) { return (int)secret[0]; }
EOF
  "$cc" -O0 -o "$skel/leak" "$WORKSPACE/leak.c"
  cat > "$AEGIX_SYNC_DIR/sanitize.rules" <<'EOF'
forbid	pass (pg|otp)-	pass-store reference
EOF
  rules_load "$AEGIX_SYNC_DIR/sanitize.rules"
  local rc=0; verify_tree "$AEGIX_SYNC_PROFILE" 2>"$WORKSPACE/hits" || rc=$?
  assert_eq "1" "$rc" "leak inside compiled binary blocks"
  assert_contains "$(cat "$WORKSPACE/hits")" "leak" "compiled binary named in output"
  teardown
}

test_verify_gate_binary_clean() {
  log "verify: binary content with no forbidden string passes"
  setup_workspace
  unset LIVE_USER LIVE_EMAIL
  local skel="$AEGIX_SYNC_PROFILE/live-overlay/etc/skel"
  mkdir -p "$skel"
  { printf 'no secrets here just zeros'; head -c 300 /dev/zero; } > "$skel/binaryfile"
  cat > "$AEGIX_SYNC_DIR/sanitize.rules" <<'EOF'
forbid	pass (pg|otp)-	pass-store reference
EOF
  rules_load "$AEGIX_SYNC_DIR/sanitize.rules"
  local rc=0; verify_tree "$AEGIX_SYNC_PROFILE" 2>"$WORKSPACE/hits" || rc=$?
  assert_eq "0" "$rc" "clean binary content passes"
  teardown
}

test_generation() {
  log "generate: profile.yaml + CSV from packages.manifest"
  setup_workspace
  cat > "$AEGIX_SYNC_DIR/packages.manifest" <<'EOF'
rootfs,barbs	xorg-server	"graphical server"
rootfs	nsxiv	"image viewer"
rootfs-init	dbus-runit
livefs	gparted	"partitioner"
livefs-init	artix-live-runit
aur	brave-bin	"browser"
git	dwm	https://github.com/aegixlinux/dwm.git	"window manager"
never	electrum
EOF
  pm_load "$AEGIX_SYNC_DIR/packages.manifest"
  cat > "$WORKSPACE/tmpl" <<'EOF'
rootfs:
  packages:
@ROOTFS_PACKAGES@
  packages-init:
    runit:
@ROOTFS_INIT_RUNIT@
livefs:
  packages:
@LIVEFS_PACKAGES@
  packages-init:
    runit:
@LIVEFS_INIT_RUNIT@
EOF
  gen_profile_yaml "$WORKSPACE/tmpl" "$WORKSPACE/out.yaml"
  assert_contains "$(cat "$WORKSPACE/out.yaml")" "    - xorg-server" "rootfs pkg emitted"
  assert_contains "$(cat "$WORKSPACE/out.yaml")" "    - artix-live-runit" "livefs-init emitted"
  assert_eq "" "$(grep -E 'electrum|@[A-Z_]+@' "$WORKSPACE/out.yaml" || true)" "no never pkgs, no markers left"
  gen_barbs_csv "$WORKSPACE/out.csv"
  assert_eq ',xorg-server,"graphical server"' "$(head -1 "$WORKSPACE/out.csv")" "barbs row"
  assert_contains "$(cat "$WORKSPACE/out.csv")" 'A,brave-bin,"browser"' "aur row"
  assert_contains "$(cat "$WORKSPACE/out.csv")" 'G,https://github.com/aegixlinux/dwm.git,"window manager"' "git row"
  gen_barbs_csv "$WORKSPACE/out2.csv"; cmp -s "$WORKSPACE/out.csv" "$WORKSPACE/out2.csv" \
    && pass "deterministic" || fail "deterministic"
  teardown
}

test_generation_rejects_whitespace_wrapped_marker() {
  log "generate: reject whitespace-wrapped markers"
  setup_workspace
  cat > "$AEGIX_SYNC_DIR/packages.manifest" <<'EOF'
rootfs	xorg-server	"graphical server"
EOF
  pm_load "$AEGIX_SYNC_DIR/packages.manifest"
  cat > "$WORKSPACE/tmpl" <<'EOF'
rootfs:
  packages:
  @ROOTFS_PACKAGES@
EOF
  local rc=0
  ( gen_profile_yaml "$WORKSPACE/tmpl" "$WORKSPACE/out.yaml" 2>/dev/null ) || rc=$?
  assert_eq "1" "$rc" "whitespace-wrapped marker rejected"
  teardown
}

test_capture_run() {
  log "capture: ship dirs/files, deletions, never-pruning, src excludes"
  setup_workspace
  local h="$AEGIX_SYNC_HOME" skel="$AEGIX_SYNC_PROFILE/live-overlay/etc/skel"
  mkdir -p "$h/.config/zsh/private" "$h/.local/bin" "$h/.local/src/dwm/.git"
  printf 'zshrc-live\n' > "$h/.config/zsh/.zshrc"
  printf 'SECRET\n'     > "$h/.config/zsh/private/token"
  printf 'newtool\n'    > "$h/.local/bin/tool-a"
  printf 'int main(){}\n' > "$h/.local/src/dwm/dwm.c"
  printf 'ELF\n' > "$h/.local/src/dwm/dwm"; printf 'obj\n' > "$h/.local/src/dwm/dwm.o"
  mkdir -p "$skel/.local/bin" "$skel/.config/zsh"
  printf 'stale\n' > "$skel/.local/bin/ghost"
  # curated iso file inside a shipped dir: git copy must survive live-wins rsync
  git -C "$AEGIX_SYNC_REPO" init -q
  git -C "$AEGIX_SYNC_REPO" config user.email t@e.st; git -C "$AEGIX_SYNC_REPO" config user.name t
  printf 'curated\n' > "$skel/.config/zsh/curated-defaults"
  git -C "$AEGIX_SYNC_REPO" add -A; git -C "$AEGIX_SYNC_REPO" commit -qm fixture
  printf 'personal-live\n' > "$h/.config/zsh/curated-defaults"
  printf 'ship\t.config/zsh/\nnever\t.config/zsh/private/\niso\t.config/zsh/curated-defaults\nship\t.local/bin/tool-a\nship\t.local/bin/ghost\nship\t.local/src/dwm/\n' \
    > "$AEGIX_SYNC_DIR/files.manifest"
  fm_load "$AEGIX_SYNC_DIR/files.manifest"
  capture_run
  assert_eq "zshrc-live" "$(cat "$skel/.config/zsh/.zshrc")" "dir capture"
  assert_eq "curated" "$(cat "$skel/.config/zsh/curated-defaults")" "iso file restored from git, live copy did not win"
  assert_file_exists "$skel/.local/bin/tool-a" "file capture"
  [[ ! -e "$skel/.config/zsh/private/token" ]] && pass "never pruned" || fail "never pruned"
  [[ ! -e "$skel/.local/bin/ghost" ]] && pass "live deletion propagates" || fail "live deletion propagates"
  assert_file_exists "$skel/.local/src/dwm/dwm.c" "src captured"
  [[ ! -e "$skel/.local/src/dwm/dwm" && ! -e "$skel/.local/src/dwm/dwm.o" && ! -e "$skel/.local/src/dwm/.git" ]] \
    && pass "src excludes" || fail "src excludes"
  teardown
}

test_capture_symlinks() {
  log "capture: symlink handling (never-pruning, undecided removal, iso-restore, exact-file preservation)"
  setup_workspace
  local h="$AEGIX_SYNC_HOME" skel="$AEGIX_SYNC_PROFILE/live-overlay/etc/skel"
  mkdir -p "$h/.config" "$h/.local/bin" "$skel/.config"
  # Setup: live has symlinks
  ln -s .config/shell "$h/.config/profile"  # exact-file ship symlink (relative)
  ln -s /home/user/secret "$h/.config/leak" # never-marked symlink
  mkdir -p "$h/.local/bin"; ln -s ../share/tool "$h/.local/bin/mytool"  # undecided symlink
  git -C "$AEGIX_SYNC_REPO" init -q
  git -C "$AEGIX_SYNC_REPO" config user.email t@e.st; git -C "$AEGIX_SYNC_REPO" config user.name t
  # Skel has curated file that git will track
  printf 'curated-content\n' > "$skel/.config/curated"
  git -C "$AEGIX_SYNC_REPO" add -A; git -C "$AEGIX_SYNC_REPO" commit -qm fixture
  printf 'ship\t.config/\nnever\t.config/leak\niso\t.config/curated\nship\t.config/profile\nship\t.local/bin/mytool\n' \
    > "$AEGIX_SYNC_DIR/files.manifest"
  fm_load "$AEGIX_SYNC_DIR/files.manifest"
  capture_run
  # Exact-file symlink should be preserved (link, not dereferenced)
  [[ -L "$skel/.config/profile" && "$(readlink "$skel/.config/profile")" == ".config/shell" ]] \
    && pass "exact-file symlink preserved as link" || fail "exact-file symlink preserved as link"
  # Never-marked symlink inside shipped dir should be removed
  [[ ! -e "$skel/.config/leak" ]] && pass "never-marked symlink removed" || fail "never-marked symlink removed"
  # Undecided symlink should be removed
  [[ ! -e "$skel/.local/bin/mytool" ]] && pass "undecided symlink removed" || fail "undecided symlink removed"
  # Iso-marked file should survive (restored from git despite rsync --delete)
  assert_eq "curated-content" "$(cat "$skel/.config/curated")" "iso file preserved"
  teardown
}

test_capture_iso_restore_custom_profile() {
  log "capture: iso-restore works with non-default AEGIX_SYNC_PROFILE path"
  setup_workspace
  # Override profile path to use a custom directory name
  export AEGIX_SYNC_PROFILE="$WORKSPACE/repo/custom-profile-dir"
  export AEGIX_SYNC_SKEL="$AEGIX_SYNC_PROFILE/live-overlay/etc/skel"
  mkdir -p "$AEGIX_SYNC_SKEL/.config/app" "$AEGIX_SYNC_HOME/.config/app"
  local h="$AEGIX_SYNC_HOME" skel="$AEGIX_SYNC_SKEL"
  git -C "$AEGIX_SYNC_REPO" init -q
  git -C "$AEGIX_SYNC_REPO" config user.email t@e.st; git -C "$AEGIX_SYNC_REPO" config user.name t
  # Skel has curated file
  printf 'CURATED-VALUE\n' > "$skel/.config/app/settings"
  git -C "$AEGIX_SYNC_REPO" add -A; git -C "$AEGIX_SYNC_REPO" commit -qm fixture
  # Live has a different value for the iso-marked file
  printf 'live-override\n' > "$h/.config/app/settings"
  printf 'ship\t.config/app/\niso\t.config/app/settings\n' > "$AEGIX_SYNC_DIR/files.manifest"
  fm_load "$AEGIX_SYNC_DIR/files.manifest"
  capture_run
  # Curated version should survive, not live override (git path derivation must work with custom profile path)
  assert_eq "CURATED-VALUE" "$(cat "$skel/.config/app/settings")" "iso file survives with custom profile path"
  teardown
}

test_verify_symlink_targets() {
  log "verify: symlink target content scanning with allow/forbid"
  setup_workspace
  unset LIVE_USER LIVE_EMAIL
  local skel="$AEGIX_SYNC_PROFILE/live-overlay/etc/skel"
  mkdir -p "$skel/.config"
  # Symlink pointing to /home/fakeuser/secret (forbidden)
  ln -s /home/fakeuser/secret "$skel/.config/badlink"
  # Symlink pointing to relative path (allowed)
  ln -s .config/shell "$skel/.config/goodlink"
  # Symlink pointing to allowlisted IP (allowed)
  ln -s /etc/hosts.192.168.1.1 "$skel/.config/iplink"
  cat > "$AEGIX_SYNC_DIR/sanitize.rules" <<'EOF'
forbid	/home/fakeuser	private home path
forbid	192\.168\.[0-9]+\.[0-9]+	private IP
allow	192\.168\.1\.1
EOF
  rules_load "$AEGIX_SYNC_DIR/sanitize.rules"
  local rc=0; verify_tree "$AEGIX_SYNC_PROFILE" 2>"$WORKSPACE/hits" || rc=$?
  assert_eq "1" "$rc" "symlink with forbidden target blocks"
  assert_contains "$(cat "$WORKSPACE/hits")" "badlink" "forbidden symlink named"
  assert_contains "$(cat "$WORKSPACE/hits")" "/home/fakeuser/secret" "target shown in output"
  rm "$skel/.config/badlink"
  rc=0; verify_tree "$AEGIX_SYNC_PROFILE" 2>/dev/null || rc=$?
  assert_eq "0" "$rc" "relative symlink passes"
  teardown
}

test_capture_iso_no_git_history() {
  log "capture: iso entry with zero git history + live file must be deleted"
  setup_workspace
  local h="$AEGIX_SYNC_HOME" skel="$AEGIX_SYNC_PROFILE/live-overlay/etc/skel"
  mkdir -p "$h/.config" "$skel/.config"
  git -C "$AEGIX_SYNC_REPO" init -q
  git -C "$AEGIX_SYNC_REPO" config user.email t@e.st; git -C "$AEGIX_SYNC_REPO" config user.name t
  # Initial git state: skel/.config exists but has no iso-marked content
  git -C "$AEGIX_SYNC_REPO" add -A; git -C "$AEGIX_SYNC_REPO" commit -qm fixture || true
  # Live has a file that will become iso-marked
  printf 'LEAKED-CONTENT\n' > "$h/.config/settings"
  printf 'ship\t.config/\niso\t.config/settings\n' > "$AEGIX_SYNC_DIR/files.manifest"
  fm_load "$AEGIX_SYNC_DIR/files.manifest"
  capture_run
  # iso entry with no git history: live file must be deleted, not shipped
  [[ ! -e "$skel/.config/settings" ]] && pass "iso file with no git history deleted" \
    || fail "iso file with no git history deleted (file exists: $(cat "$skel/.config/settings"))"
  teardown
}

test_capture_iso_dir_untracked_stray() {
  log "capture: directory-type iso pattern, git content tracked, live stray untracked"
  setup_workspace
  local h="$AEGIX_SYNC_HOME" skel="$AEGIX_SYNC_PROFILE/live-overlay/etc/skel"
  mkdir -p "$h/.config/app" "$skel/.config/app"
  git -C "$AEGIX_SYNC_REPO" init -q
  git -C "$AEGIX_SYNC_REPO" config user.email t@e.st; git -C "$AEGIX_SYNC_REPO" config user.name t
  # Git has curated content in skel
  printf 'GIT-TRACKED\n' > "$skel/.config/app/config"
  git -C "$AEGIX_SYNC_REPO" add -A; git -C "$AEGIX_SYNC_REPO" commit -qm fixture
  # Live has the curated file AND an extra untracked stray
  printf 'GIT-TRACKED\n' > "$h/.config/app/config"
  printf 'UNTRACKED-STRAY\n' > "$h/.config/app/stray"
  # .config/ is shipped (rsync happens), .config/app/ is iso (only git content allowed)
  printf 'ship\t.config/\niso\t.config/app/\n' > "$AEGIX_SYNC_DIR/files.manifest"
  fm_load "$AEGIX_SYNC_DIR/files.manifest"
  capture_run
  # Tracked content should be present, untracked stray must be gone (rm fallback in iso reconcile case)
  assert_eq "GIT-TRACKED" "$(cat "$skel/.config/app/config")" "iso dir: git content preserved"
  [[ ! -e "$skel/.config/app/stray" ]] && pass "iso dir: untracked live stray deleted" \
    || fail "iso dir: untracked live stray deleted (file exists)"
  teardown
}

test_capture_gitignore_purge() {
  log "capture: captured .gitignore doesn't create an invisible ship channel"
  setup_workspace
  local h="$AEGIX_SYNC_HOME" skel="$AEGIX_SYNC_PROFILE/live-overlay/etc/skel"
  mkdir -p "$h/.local/src/stool"
  git -C "$h/.local/src/stool" init -q
  git -C "$h/.local/src/stool" config user.email t@e.st
  git -C "$h/.local/src/stool" config user.name t
  printf 'stest\n' > "$h/.local/src/stool/.gitignore"
  printf 'int main(){}\n' > "$h/.local/src/stool/stool.c"
  git -C "$h/.local/src/stool" add -A
  git -C "$h/.local/src/stool" commit -qm fixture
  # built binary the live repo's own .gitignore hides — never staged/tracked
  printf 'ELFBIN\n' > "$h/.local/src/stool/stest"
  printf 'ship\t.local/src/stool/\n' > "$AEGIX_SYNC_DIR/files.manifest"
  fm_load "$AEGIX_SYNC_DIR/files.manifest"
  capture_run
  assert_file_exists "$skel/.local/src/stool/stool.c" "source captured"
  [[ ! -e "$skel/.local/src/stool/.gitignore" ]] && pass ".gitignore itself not shipped" \
    || fail ".gitignore itself not shipped"
  [[ ! -e "$skel/.local/src/stool/stest" ]] && pass "gitignored build artifact not shipped" \
    || fail "gitignored build artifact not shipped"
  teardown
}

test_discover_and_triage() {
  log "triage: discovery, dir granularity, answers file, manifest writeback"
  setup_workspace
  local h="$AEGIX_SYNC_HOME"
  mkdir -p "$h/.local/bin" "$h/.config/newtool"
  printf 'x\n' > "$h/.local/bin/sb-cpu"; printf 'x\n' > "$h/.local/bin/passmenu-secure"
  printf 'x\n' > "$h/.config/newtool/conf"
  printf 'watch\t.local/bin\nwatch\t.config\n' > "$AEGIX_SYNC_DIR/files.manifest"
  fm_load "$AEGIX_SYNC_DIR/files.manifest"
  local und; und="$(discover_undecided)"
  assert_contains "$und" ".local/bin/sb-cpu" "file discovered"
  assert_contains "$und" "DIR .config/newtool/" "new dir collapsed"

  cat > "$AEGIX_SYNC_DIR/packages.manifest" <<'EOF'
rootfs	xorg-server	"graphical server"
EOF
  pm_load "$AEGIX_SYNC_DIR/packages.manifest"
  printf 'xorg-server\nelectrum\n' > "$WORKSPACE/installed"

  printf 'ship\t.local/bin/sb-*\nnever\t.local/bin/passmenu-secure\nship\t.config/newtool/\nnever\telectrum\n' > "$WORKSPACE/answers"
  triage_run "$WORKSPACE/answers" "$WORKSPACE/installed"
  fm_load "$AEGIX_SYNC_DIR/files.manifest"   # reload after writeback
  pm_load "$AEGIX_SYNC_DIR/packages.manifest"
  assert_eq "ship"  "$(fm_lookup .local/bin/sb-cpu)" "glob answer recorded"
  assert_eq "never" "$(fm_lookup .local/bin/passmenu-secure)" "never recorded"
  assert_eq "ship"  "$(fm_lookup .config/newtool/conf)" "dir answer recorded"
  assert_eq "" "$(discover_undecided)" "nothing undecided after triage"
  assert_eq "never" "${PM_TAGS[electrum]}" "package triage: never electrum recorded"
  assert_eq "" "$(pm_new_packages "$WORKSPACE/installed")" "package triage: electrum not re-asked"
  teardown
}

test_discover_dotfiles() {
  log "discover: dot-entries directly under a watch dir are not blind spots"
  setup_workspace
  local h="$AEGIX_SYNC_HOME"
  mkdir -p "$h/.config/.hiddendir"
  printf 'x\n' > "$h/.config/.hiddenfile"
  printf 'y\n' > "$h/.config/.hiddendir/inner"
  printf 'watch\t.config\n' > "$AEGIX_SYNC_DIR/files.manifest"
  fm_load "$AEGIX_SYNC_DIR/files.manifest"
  local und; und="$(discover_undecided)"
  assert_contains "$und" ".config/.hiddenfile" "dot-file directly under watch dir surfaces"
  assert_contains "$und" "DIR .config/.hiddendir/" "dot-dir directly under watch dir surfaces"
  teardown
}

test_discover_descend_symlinks() {
  log "discover: symlinks aren't skipped when auto-descending a partially-decided dir"
  setup_workspace
  local h="$AEGIX_SYNC_HOME"
  mkdir -p "$h/.config/appdir"
  printf 'x\n' > "$h/.config/appdir/known"
  ln -s /nonexistent-target "$h/.config/appdir/link"
  printf 'watch\t.config\nship\t.config/appdir/known\n' > "$AEGIX_SYNC_DIR/files.manifest"
  fm_load "$AEGIX_SYNC_DIR/files.manifest"
  local und; und="$(discover_undecided)"
  assert_contains "$und" ".config/appdir/link" "symlink surfaces when descending a partially-decided dir"
  printf 'never\t.config/appdir/link\n' > "$WORKSPACE/answers"
  triage_run "$WORKSPACE/answers"
  fm_load "$AEGIX_SYNC_DIR/files.manifest"
  assert_eq "never" "$(fm_lookup .config/appdir/link)" "never answer for symlink honored end-to-end"
  teardown
}

test_triage_descend_ordering() {
  log "triage: descend answers line doesn't shadow later specific answers, symlinks included"
  setup_workspace
  local h="$AEGIX_SYNC_HOME"
  mkdir -p "$h/.config/newdir"
  printf 'x\n' > "$h/.config/newdir/conf"
  printf 'y\n' > "$h/.config/newdir/secret"
  ln -s /nonexistent-target "$h/.config/newdir/link"
  printf 'watch\t.config\n' > "$AEGIX_SYNC_DIR/files.manifest"
  fm_load "$AEGIX_SYNC_DIR/files.manifest"
  local und; und="$(discover_undecided)"
  assert_contains "$und" "DIR .config/newdir/" "whole new dir still collapses before any decision"
  printf 'descend\t.config/newdir/\nship\t.config/newdir/conf\nnever\t.config/newdir/secret\nnever\t.config/newdir/link\n' > "$WORKSPACE/answers"
  triage_run "$WORKSPACE/answers"
  fm_load "$AEGIX_SYNC_DIR/files.manifest"
  assert_eq "ship"  "$(fm_lookup .config/newdir/conf)"   "descend line doesn't shadow later ship answer"
  assert_eq "never" "$(fm_lookup .config/newdir/secret)" "descend line doesn't shadow later never answer"
  assert_eq "never" "$(fm_lookup .config/newdir/link)"   "symlink resolved via triage-side descend"
  assert_eq "" "$(discover_undecided)" "nothing undecided after descend-triage"
  teardown
}

test_drift_status() {
  log "drift_status: read-only report — file drift, undecided, package drift; no mutation"
  setup_workspace
  local h="$AEGIX_SYNC_HOME" skel="$AEGIX_SYNC_PROFILE/live-overlay/etc/skel"
  mkdir -p "$h/.config/app" "$h/.local/bin" "$skel/.config/app"
  printf 'skel-old-value\n' > "$skel/.config/app/conf"   # shipped file, real skel
  printf 'live-new-value\n' > "$h/.config/app/conf"      # same file, live has since drifted
  printf 'x\n' > "$h/.local/bin/newscript"                # undecided (watch, no decision)
  printf 'ship\t.config/app/conf\nwatch\t.local/bin\n' > "$AEGIX_SYNC_DIR/files.manifest"
  fm_load "$AEGIX_SYNC_DIR/files.manifest"
  : > "$AEGIX_SYNC_DIR/sanitize.rules"
  rules_load "$AEGIX_SYNC_DIR/sanitize.rules"
  cat > "$AEGIX_SYNC_DIR/packages.manifest" <<'EOF'
rootfs	xorg-server	"graphical server"
EOF
  pm_load "$AEGIX_SYNC_DIR/packages.manifest"
  printf 'xorg-server\nnewpkg\n' > "$WORKSPACE/installed"
  export AEGIX_SYNC_PKGLIST_CMD="cat $WORKSPACE/installed"

  local out; out="$(drift_status)"
  assert_eq "1 files drifted, 1 undecided, 1 new packages, 0 gone packages" "$out" "drift line exact"
  assert_eq "skel-old-value" "$(cat "$skel/.config/app/conf")" "real skel untouched after drift_status"

  local out2; out2="$(drift_status)"
  assert_eq "$out" "$out2" "drift_status idempotent (second call, same line)"
  assert_eq "skel-old-value" "$(cat "$skel/.config/app/conf")" "real skel still untouched after second call"

  teardown
}

test_drift_status_iso_no_false_positive() {
  log "drift_status: ship dir with nested iso file, live missing it -> no false drift (fix round 1)"
  setup_workspace
  local h="$AEGIX_SYNC_HOME" skel="$AEGIX_SYNC_PROFILE/live-overlay/etc/skel"
  mkdir -p "$h/.config/shell" "$skel/.config/shell"
  git -C "$AEGIX_SYNC_REPO" init -q
  git -C "$AEGIX_SYNC_REPO" config user.email t@e.st; git -C "$AEGIX_SYNC_REPO" config user.name t
  printf 'curated-bm-dirs\n' > "$skel/.config/shell/bm-dirs"
  git -C "$AEGIX_SYNC_REPO" add -A; git -C "$AEGIX_SYNC_REPO" commit -qm fixture
  # live intentionally has NO bm-dirs at all — iso content must come from the
  # repo's index during the scratch replay, not from a live copy that isn't there.
  printf 'ship\t.config/shell/\niso\t.config/shell/bm-dirs\n' > "$AEGIX_SYNC_DIR/files.manifest"
  fm_load "$AEGIX_SYNC_DIR/files.manifest"
  : > "$AEGIX_SYNC_DIR/sanitize.rules"
  rules_load "$AEGIX_SYNC_DIR/sanitize.rules"
  cat > "$AEGIX_SYNC_DIR/packages.manifest" <<'EOF'
rootfs	xorg-server	"graphical server"
EOF
  pm_load "$AEGIX_SYNC_DIR/packages.manifest"
  printf 'xorg-server\n' > "$WORKSPACE/installed"
  export AEGIX_SYNC_PKGLIST_CMD="cat $WORKSPACE/installed"

  local out; out="$(drift_status)"
  assert_eq "0 files drifted, 0 undecided, 0 new packages, 0 gone packages" "$out" \
    "iso-restored-from-git file causes no false drift"
  assert_eq "curated-bm-dirs" "$(cat "$skel/.config/shell/bm-dirs")" "real skel iso file untouched"

  teardown
}

test_drift_status_missing_profile() {
  log "drift_status: nonexistent profile survives under set -e, reports '?' instead of lying 0"
  setup_workspace
  rm -rf "$AEGIX_SYNC_PROFILE"
  cat > "$AEGIX_SYNC_DIR/files.manifest" <<'EOF'
EOF
  fm_load "$AEGIX_SYNC_DIR/files.manifest"
  : > "$AEGIX_SYNC_DIR/sanitize.rules"
  rules_load "$AEGIX_SYNC_DIR/sanitize.rules"
  cat > "$AEGIX_SYNC_DIR/packages.manifest" <<'EOF'
rootfs	xorg-server	"graphical server"
EOF
  pm_load "$AEGIX_SYNC_DIR/packages.manifest"
  printf 'xorg-server\n' > "$WORKSPACE/installed"
  export AEGIX_SYNC_PKGLIST_CMD="cat $WORKSPACE/installed"

  # Direct (unwrapped) call inside a set -e script — this is exactly how
  # Task 9's `--status` will invoke it. Must not kill the caller.
  local out rc=0
  out="$(bash -euo pipefail -c '
    source "'"$TOOLS_DIR"'/aegix-sync-lib.sh"
    export AEGIX_SYNC_HOME AEGIX_SYNC_REPO AEGIX_SYNC_PROFILE AEGIX_SYNC_DIR AEGIX_SYNC_SKEL AEGIX_SYNC_PKGLIST_CMD
    fm_load "$AEGIX_SYNC_DIR/files.manifest"
    rules_load "$AEGIX_SYNC_DIR/sanitize.rules"
    pm_load "$AEGIX_SYNC_DIR/packages.manifest"
    drift_status
    echo "SURVIVED"
  ' 2>/dev/null)" || rc=$?
  assert_eq "0" "$rc" "unwrapped drift_status call under set -e still exits 0"
  assert_contains "$out" "? files drifted, ? undecided, ? new packages, ? gone packages" "unknown report line printed"
  assert_contains "$out" "SURVIVED" "script continued past drift_status call"

  teardown
}

# --- Orchestrator (tools/aegix-sync) tests ---

# _setup_orchestrator_fixture: minimal git repo + manifests + live home shared
# by the orchestrator tests. Assumes setup_workspace already ran.
_setup_orchestrator_fixture() {
  git -C "$AEGIX_SYNC_REPO" init -q
  git -C "$AEGIX_SYNC_REPO" config user.email t@e.st
  git -C "$AEGIX_SYNC_REPO" config user.name t
  mkdir -p "$AEGIX_SYNC_HOME/.local/bin"
  printf 'echo hi\n' > "$AEGIX_SYNC_HOME/.local/bin/tool-a"
  printf 'ship\t.local/bin/tool-a\nwatch\t.local/bin\n' > "$AEGIX_SYNC_DIR/files.manifest"
  printf 'rootfs\tnsxiv\t"viewer"\n' > "$AEGIX_SYNC_DIR/packages.manifest"
  printf 'forbid\tSECRETMARKER\tplanted\n' > "$AEGIX_SYNC_DIR/sanitize.rules"
  printf 'rootfs:\n  packages:\n@ROOTFS_PACKAGES@\n  packages-init:\n    runit:\n@ROOTFS_INIT_RUNIT@\nlivefs:\n  packages:\n@LIVEFS_PACKAGES@\n  packages-init:\n    runit:\n@LIVEFS_INIT_RUNIT@\n' \
    > "$AEGIX_SYNC_PROFILE/profile.yaml.tmpl"
  mkdir -p "$AEGIX_SYNC_PROFILE/live-overlay/root"
  printf '#!/bin/sh\necho install\n' > "$AEGIX_SYNC_PROFILE/live-overlay/root/install.sh"
  git -C "$AEGIX_SYNC_REPO" add -A; git -C "$AEGIX_SYNC_REPO" commit -qm init
  export AEGIX_SYNC_PKGLIST_CMD="printf 'nsxiv\n'"
}

test_orchestrator_end_to_end() {
  log "aegix-sync: e2e — clean run commits; planted leak aborts uncommitted"
  setup_workspace
  _setup_orchestrator_fixture
  "$TOOLS_DIR/aegix-sync" --yes --no-deploy >/dev/null
  assert_file_exists "$AEGIX_SYNC_PROFILE/live-overlay/etc/skel/.local/bin/tool-a" "captured"
  assert_file_exists "$AEGIX_SYNC_PROFILE/profile.yaml" "generated yaml"
  assert_contains "$(git -C "$AEGIX_SYNC_REPO" log -1 --format=%s)" "sync: " "committed"
  # planted leak: aborts, nothing committed
  printf 'SECRETMARKER\n' > "$AEGIX_SYNC_HOME/.local/bin/tool-a"
  local before rc=0; before="$(git -C "$AEGIX_SYNC_REPO" rev-parse HEAD)"
  "$TOOLS_DIR/aegix-sync" --yes --no-deploy >/dev/null 2>&1 || rc=$?
  assert_eq "1" "$rc" "verify gate aborts run"
  assert_eq "$before" "$(git -C "$AEGIX_SYNC_REPO" rev-parse HEAD)" "no commit on leak"
  assert_eq "" "$(git -C "$AEGIX_SYNC_REPO" status --porcelain)" "tree restored after abort"
  teardown
}

test_orchestrator_status() {
  log "aegix-sync: --status reports drift and exits 0 without mutating"
  setup_workspace
  _setup_orchestrator_fixture
  local out rc=0
  out="$("$TOOLS_DIR/aegix-sync" --status)" || rc=$?
  assert_eq "0" "$rc" "--status exits 0"
  assert_contains "$out" "files drifted" "--status prints drift line"
  assert_eq "" "$(git -C "$AEGIX_SYNC_REPO" status --porcelain)" "--status makes no repo changes"
  teardown
}

test_orchestrator_dry_run() {
  log "aegix-sync: --dry-run leaves tree dirty and HEAD unchanged; re-run after restore works"
  setup_workspace
  _setup_orchestrator_fixture
  local before rc=0
  before="$(git -C "$AEGIX_SYNC_REPO" rev-parse HEAD)"
  "$TOOLS_DIR/aegix-sync" --dry-run --no-deploy >/dev/null || rc=$?
  assert_eq "0" "$rc" "--dry-run exits 0"
  assert_eq "$before" "$(git -C "$AEGIX_SYNC_REPO" rev-parse HEAD)" "--dry-run makes no commit"
  if [[ -n "$(git -C "$AEGIX_SYNC_REPO" status --porcelain -- iso-profile sync)" ]]; then
    pass "--dry-run leaves tree dirty"
  else
    fail "--dry-run leaves tree dirty"
  fi
  git -C "$AEGIX_SYNC_REPO" checkout -q -- iso-profile sync
  git -C "$AEGIX_SYNC_REPO" clean -qfd iso-profile sync
  assert_eq "" "$(git -C "$AEGIX_SYNC_REPO" status --porcelain)" "tree restored before re-run"
  "$TOOLS_DIR/aegix-sync" --yes --no-deploy >/dev/null
  assert_contains "$(git -C "$AEGIX_SYNC_REPO" log -1 --format=%s)" "sync: " "second run commits after restore"
  teardown
}

test_orchestrator_generate_failure_restores() {
  log "aegix-sync: gen_profile_yaml failure restores tree, nothing committed"
  setup_workspace
  _setup_orchestrator_fixture
  # Commit a broken template (unconsumed marker) so preflight sees a clean
  # tree and the failure is genuinely from the generate phase, not preflight.
  printf '@BOGUS_MARKER@\n' >> "$AEGIX_SYNC_PROFILE/profile.yaml.tmpl"
  git -C "$AEGIX_SYNC_REPO" add -A; git -C "$AEGIX_SYNC_REPO" commit -qm "break template"
  local before rc=0; before="$(git -C "$AEGIX_SYNC_REPO" rev-parse HEAD)"
  "$TOOLS_DIR/aegix-sync" --yes --no-deploy >/dev/null 2>&1 || rc=$?
  assert_eq "1" "$rc" "generate failure aborts run"
  assert_eq "$before" "$(git -C "$AEGIX_SYNC_REPO" rev-parse HEAD)" "no commit on generate failure"
  assert_eq "" "$(git -C "$AEGIX_SYNC_REPO" status --porcelain)" "tree restored after generate failure"
  teardown
}

test_orchestrator_bogus_answers_file() {
  log "aegix-sync: --answers pointing at a nonexistent file exits 2, no mutation"
  setup_workspace
  _setup_orchestrator_fixture
  local before rc=0; before="$(git -C "$AEGIX_SYNC_REPO" rev-parse HEAD)"
  "$TOOLS_DIR/aegix-sync" --yes --no-deploy --answers "$WORKSPACE/does-not-exist" >/dev/null 2>&1 || rc=$?
  assert_eq "2" "$rc" "bogus answers file exits 2"
  assert_eq "$before" "$(git -C "$AEGIX_SYNC_REPO" rev-parse HEAD)" "no commit with bogus answers file"
  assert_eq "" "$(git -C "$AEGIX_SYNC_REPO" status --porcelain)" "tree clean with bogus answers file"
  teardown
}

test_orchestrator_preflight_staged_elsewhere() {
  log "aegix-sync: staged changes anywhere in the repo abort before capture"
  setup_workspace
  _setup_orchestrator_fixture
  mkdir -p "$AEGIX_SYNC_REPO/unrelated"
  printf 'staged content\n' > "$AEGIX_SYNC_REPO/unrelated/file.txt"
  git -C "$AEGIX_SYNC_REPO" add unrelated/file.txt
  local before rc=0; before="$(git -C "$AEGIX_SYNC_REPO" rev-parse HEAD)"
  "$TOOLS_DIR/aegix-sync" --yes --no-deploy >/dev/null 2>&1 || rc=$?
  assert_eq "1" "$rc" "staged-elsewhere aborts"
  assert_eq "$before" "$(git -C "$AEGIX_SYNC_REPO" rev-parse HEAD)" "no commit"
  assert_contains "$(git -C "$AEGIX_SYNC_REPO" status --porcelain)" "unrelated/file.txt" "staged file still staged"
  [[ ! -e "$AEGIX_SYNC_PROFILE/live-overlay/etc/skel/.local/bin/tool-a" ]] \
    && pass "capture never ran" || fail "capture never ran"
  teardown
}

test_deploy_full_scope() {
  log "iso-profile-deploy: full profile scope with --delete"
  setup_workspace
  local src="$WORKSPACE/profile-src" dst="$WORKSPACE/profile-dst"
  mkdir -p "$src" "$dst"
  # Create source fixture: profile.yaml, profile.yaml.tmpl (excluded), README.md (excluded)
  printf 'rootfs:\n  packages:\n    - xorg-server\n' > "$src/profile.yaml"
  printf 'template content\n' > "$src/profile.yaml.tmpl"
  printf '# README\n' > "$src/README.md"
  # Add root-overlay and live-overlay files
  mkdir -p "$src/root-overlay/etc" "$src/live-overlay/etc/skel"
  printf 'aegix-hostname\n' > "$src/root-overlay/etc/hostname"
  printf 'export TEST_VAR=1\n' > "$src/live-overlay/etc/skel/.zshenv"
  # Populate with enough files (>100) for minimum file count validation
  for i in {1..110}; do printf 'file %d\n' "$i" > "$src/file_$i"; done
  # Pre-seed destination with stale file
  printf 'stale backup\n' > "$dst/profile.yaml.bak"
  # Run deploy with env vars set (test mode: no sudo)
  export ISO_PROFILE_DEST="$dst"
  export AEGIX_SYNC_PROFILE="$src"
  bash "$TOOLS_DIR/iso-profile-deploy.sh"
  # Assert profile.yaml deployed
  assert_file_exists "$dst/profile.yaml" "profile.yaml deployed"
  assert_contains "$(cat "$dst/profile.yaml")" "xorg-server" "profile.yaml content correct"
  # Assert root-overlay deployed
  assert_file_exists "$dst/root-overlay/etc/hostname" "root-overlay/etc/hostname deployed"
  assert_eq "aegix-hostname" "$(cat "$dst/root-overlay/etc/hostname")" "hostname content correct"
  # Assert live-overlay deployed
  assert_file_exists "$dst/live-overlay/etc/skel/.zshenv" "live-overlay/.zshenv deployed"
  assert_contains "$(cat "$dst/live-overlay/etc/skel/.zshenv")" "TEST_VAR" "live-overlay file content correct"
  # Assert excluded files NOT deployed
  [[ ! -e "$dst/profile.yaml.tmpl" ]] && pass "profile.yaml.tmpl excluded" || fail "profile.yaml.tmpl excluded"
  [[ ! -e "$dst/README.md" ]] && pass "README.md excluded" || fail "README.md excluded"
  # Assert stale file deleted by --delete
  [[ ! -e "$dst/profile.yaml.bak" ]] && pass "stale file deleted by --delete" || fail "stale file deleted by --delete"
  teardown
}

test_deploy_empty_dest_variable() {
  log "iso-profile-deploy: set-but-empty ISO_PROFILE_DEST exits 2"
  setup_workspace
  local src="$WORKSPACE/profile-src" dst="$WORKSPACE/profile-dst"
  mkdir -p "$src" "$dst"
  printf 'rootfs:\n  packages:\n' > "$src/profile.yaml"
  for i in {1..100}; do printf 'f%d\n' "$i" > "$src/f_$i"; done
  # Run with ISO_PROFILE_DEST explicitly empty
  export ISO_PROFILE_DEST=""
  export AEGIX_SYNC_PROFILE="$src"
  local rc=0
  bash "$TOOLS_DIR/iso-profile-deploy.sh" >/dev/null 2>&1 || rc=$?
  assert_eq "2" "$rc" "set-but-empty DEST exits 2"
  [[ ! -e "$dst/profile.yaml" ]] && pass "DEST untouched" || fail "DEST untouched"
  teardown
}

test_deploy_no_prod_no_dest() {
  log "iso-profile-deploy: no --prod and no ISO_PROFILE_DEST exits 2"
  setup_workspace
  local src="$WORKSPACE/profile-src"
  mkdir -p "$src"
  printf 'rootfs:\n  packages:\n' > "$src/profile.yaml"
  for i in {1..100}; do printf 'f%d\n' "$i" > "$src/f_$i"; done
  # Run with neither --prod nor ISO_PROFILE_DEST set
  unset ISO_PROFILE_DEST 2>/dev/null || true
  export AEGIX_SYNC_PROFILE="$src"
  local rc=0
  bash "$TOOLS_DIR/iso-profile-deploy.sh" >/dev/null 2>&1 || rc=$?
  assert_eq "2" "$rc" "no --prod and no DEST exits 2"
  teardown
}

test_deploy_empty_src() {
  log "iso-profile-deploy: empty source directory (too few files) aborts"
  setup_workspace
  local src="$WORKSPACE/profile-src" dst="$WORKSPACE/profile-dst"
  mkdir -p "$src" "$dst"
  printf 'rootfs:\n  packages:\n' > "$src/profile.yaml"
  # Only 1 file, well below 100 minimum
  printf 'placeholder\n' > "$dst/existing"
  export ISO_PROFILE_DEST="$dst"
  export AEGIX_SYNC_PROFILE="$src"
  local rc=0
  bash "$TOOLS_DIR/iso-profile-deploy.sh" >/dev/null 2>&1 || rc=$?
  assert_eq "1" "$rc" "low file count aborts"
  [[ -e "$dst/existing" ]] && pass "DEST untouched" || fail "DEST untouched"
  teardown
}

test_deploy_missing_profile_yaml() {
  log "iso-profile-deploy: missing profile.yaml in source aborts"
  setup_workspace
  local src="$WORKSPACE/profile-src" dst="$WORKSPACE/profile-dst"
  mkdir -p "$src" "$dst"
  # Populate with 100+ files but NO profile.yaml
  for i in {1..101}; do printf 'f%d\n' "$i" > "$src/f_$i"; done
  printf 'existing\n' > "$dst/existing"
  export ISO_PROFILE_DEST="$dst"
  export AEGIX_SYNC_PROFILE="$src"
  local rc=0
  bash "$TOOLS_DIR/iso-profile-deploy.sh" >/dev/null 2>&1 || rc=$?
  assert_eq "1" "$rc" "missing profile.yaml aborts"
  [[ -e "$dst/existing" ]] && pass "DEST untouched" || fail "DEST untouched"
  teardown
}

test_deploy_mass_delete() {
  log "iso-profile-deploy: >25 deletions aborts; --allow-mass-delete overrides"
  setup_workspace
  local src="$WORKSPACE/profile-src" dst="$WORKSPACE/profile-dst"
  mkdir -p "$src" "$dst"
  printf 'rootfs:\n  packages:\n' > "$src/profile.yaml"
  for i in {1..100}; do printf 'f%d\n' "$i" > "$src/f_$i"; done
  # Pre-seed destination with 30+ old files (will trigger mass-delete gate)
  for i in {1..30}; do printf 'old_%d\n' "$i" > "$dst/old_$i"; done
  export ISO_PROFILE_DEST="$dst"
  export AEGIX_SYNC_PROFILE="$src"
  local rc=0
  bash "$TOOLS_DIR/iso-profile-deploy.sh" >/dev/null 2>&1 || rc=$?
  assert_eq "1" "$rc" "mass delete aborts (>25 threshold)"
  # Verify old files still present (abort prevented deletion)
  [[ -e "$dst/old_1" && -e "$dst/old_30" ]] && pass "DEST untouched on abort" \
    || fail "DEST untouched on abort"
  # Now retry with --allow-mass-delete
  rc=0
  bash "$TOOLS_DIR/iso-profile-deploy.sh" --allow-mass-delete >/dev/null 2>&1 || rc=$?
  assert_eq "0" "$rc" "--allow-mass-delete succeeds"
  # Verify old files are now gone
  [[ ! -e "$dst/old_1" && ! -e "$dst/old_30" ]] && pass "old files deleted with override" \
    || fail "old files deleted with override"
  # Verify new profile deployed
  assert_file_exists "$dst/profile.yaml" "profile.yaml deployed after override"
  teardown
}

test_deploy_delete_gate_unit() {
  log "iso-profile-deploy: _deploy_delete_gate unit tests (rc, count logic)"
  setup_workspace
  # Unit-test the gate helper directly
  # Source the deploy script to get the helper
  local deploy_script="$TOOLS_DIR/iso-profile-deploy.sh"
  # Extract helper and test it
  local output

  # Test 1: rc!=0 && count==0 → should fail (abort)
  output=$(bash -c "source <(sed -n '/^_deploy_delete_gate/,/^}/p' '$deploy_script'); _deploy_delete_gate 23 0" 2>&1 || true)
  [[ -z "$output" ]] || { echo "$output" | grep -q "Error: could not verify" && pass "_deploy_delete_gate(23, 0) fails" || fail "_deploy_delete_gate(23, 0) fails"; }

  # Test 2: rc!=0 && count>0 → proceeds (partial error, but counted some)
  bash -c "source <(sed -n '/^_deploy_delete_gate/,/^}/p' '$deploy_script'); _deploy_delete_gate 23 3" 2>/dev/null \
    && pass "_deploy_delete_gate(23, 3) proceeds" || fail "_deploy_delete_gate(23, 3) proceeds"

  # Test 3: rc==0 && count==0 → proceeds (success, zero deletions)
  bash -c "source <(sed -n '/^_deploy_delete_gate/,/^}/p' '$deploy_script'); _deploy_delete_gate 0 0" 2>/dev/null \
    && pass "_deploy_delete_gate(0, 0) proceeds" || fail "_deploy_delete_gate(0, 0) proceeds"

  # Test 4: rc==0 && count>25 && !allow → fails (mass delete gate)
  bash -c "ALLOW_MASS_DELETE=0; source <(sed -n '/^_deploy_delete_gate/,/^}/p' '$deploy_script'); _deploy_delete_gate 0 30" 2>/dev/null \
    && fail "_deploy_delete_gate(0, 30) should abort mass delete" || pass "_deploy_delete_gate(0, 30) aborts"

  teardown
}

test_deploy_dry_run_scan_failure() {
  log "iso-profile-deploy: partial dry-run failure (rc!=0, count>0 proceeds)"
  setup_workspace
  local src="$WORKSPACE/profile-src" dst="$WORKSPACE/profile-dst"
  mkdir -p "$src" "$dst"
  printf 'rootfs:\n  packages:\n' > "$src/profile.yaml"
  for i in {1..100}; do printf 'f%d\n' "$i" > "$src/f_$i"; done
  # Create a protected subdirectory in dst that will cause rsync to fail on that subtree
  # (permission denied on traverse). rsync will still scan accessible files and return rc!=0.
  mkdir -p "$dst/protected-dir"
  printf 'protected-content\n' > "$dst/protected-dir/canary"
  chmod 000 "$dst/protected-dir"
  # Also create an unprotected file in dst that rsync WILL delete (not in src)
  printf 'stale-unprotected\n' > "$dst/stale.txt"
  # Run deploy; rsync -n will partially fail but parse stale.txt as deletable
  export ISO_PROFILE_DEST="$dst"
  export AEGIX_SYNC_PROFILE="$src"
  local rc=0
  bash "$TOOLS_DIR/iso-profile-deploy.sh" >/dev/null 2>&1 || rc=$?
  # Contract: rc!=0 && count>0 (partial error) legitimately proceeds
  # So: stale.txt WILL be deleted (rsync ran), but protected-dir cannot be entered
  [[ ! -e "$dst/stale.txt" ]] && pass "stale file deleted (partial scan allowed proceed)" \
    || fail "stale file deleted (partial scan allowed proceed)"
  [[ -d "$dst/protected-dir" ]] && pass "protected-dir preserved (inaccessible)" \
    || fail "protected-dir preserved (inaccessible)"
  # Clean up: restore perms for workspace cleanup
  chmod 755 "$dst/protected-dir" 2>/dev/null || true
  teardown
}

test_deploy_zero_deletions_already_in_sync() {
  log "iso-profile-deploy: DEST already in sync (zero deletions pending) succeeds"
  setup_workspace
  local src="$WORKSPACE/profile-src" dst="$WORKSPACE/profile-dst"
  mkdir -p "$src" "$dst"
  printf 'rootfs:\n  packages:\n    - xorg-server\n' > "$src/profile.yaml"
  for i in {1..100}; do printf 'file %d\n' "$i" > "$src/file_$i"; done
  # Mirror dst to be byte-for-byte identical to src: dry-run will report
  # zero "deleting " lines, which previously tripped `grep | wc -l` under
  # pipefail and killed the script silently (unguarded pipeline exit).
  cp -a "$src/." "$dst/"
  export ISO_PROFILE_DEST="$dst"
  export AEGIX_SYNC_PROFILE="$src"
  local rc=0
  bash "$TOOLS_DIR/iso-profile-deploy.sh" >/dev/null 2>&1 || rc=$?
  assert_eq "0" "$rc" "deploy exits 0 when nothing to delete"
  assert_file_exists "$dst/profile.yaml" "profile.yaml still present"
  assert_contains "$(cat "$dst/profile.yaml")" "xorg-server" "profile.yaml content correct"
  teardown
}

test_deploy_first_run_empty_dest() {
  log "iso-profile-deploy: first deploy to an empty DEST succeeds and files arrive"
  setup_workspace
  local src="$WORKSPACE/profile-src" dst="$WORKSPACE/profile-dst"
  mkdir -p "$src" "$dst"
  printf 'rootfs:\n  packages:\n    - xorg-server\n' > "$src/profile.yaml"
  mkdir -p "$src/root-overlay/etc" "$src/live-overlay/etc/skel"
  printf 'aegix-hostname\n' > "$src/root-overlay/etc/hostname"
  printf 'export TEST_VAR=1\n' > "$src/live-overlay/etc/skel/.zshenv"
  for i in {1..100}; do printf 'file %d\n' "$i" > "$src/file_$i"; done
  # dst exists but is completely empty: dry-run finds nothing to delete
  # (same zero-match pipeline as the already-in-sync case).
  export ISO_PROFILE_DEST="$dst"
  export AEGIX_SYNC_PROFILE="$src"
  local rc=0
  bash "$TOOLS_DIR/iso-profile-deploy.sh" >/dev/null 2>&1 || rc=$?
  assert_eq "0" "$rc" "first deploy to empty DEST exits 0"
  assert_file_exists "$dst/profile.yaml" "profile.yaml arrived"
  assert_file_exists "$dst/root-overlay/etc/hostname" "root-overlay file arrived"
  assert_file_exists "$dst/live-overlay/etc/skel/.zshenv" "live-overlay file arrived"
  teardown
}

test_orchestrator_deploy_includes_prod_flag() {
  log "aegix-sync: orchestrator calls deploy with --prod"
  setup_workspace
  _setup_orchestrator_fixture
  # Verify that the orchestrator script includes --prod when calling deploy
  grep -q '\$AEGIX_SYNC_REPO/tools/iso-profile-deploy\.sh.*--prod' "$TOOLS_DIR/aegix-sync" \
    && pass "orchestrator calls deploy with --prod" \
    || fail "orchestrator calls deploy with --prod"
  teardown
}

test_deploy_refuses_dirty_profile() {
  log "iso-profile-deploy: uncommitted iso-profile refuses; --force-dirty overrides"
  setup_workspace
  # The dirty-check derives its repo root from the deploy script's own
  # location ($0), same as SRC's default. Run it out of a throwaway git repo
  # (script copied in) so this test never touches the real aegix-sync
  # worktree — only $dst is scratch on the other existing deploy tests.
  local fake_repo="$WORKSPACE/fake-repo" dst="$WORKSPACE/deploy-dst"
  mkdir -p "$fake_repo/tools" "$fake_repo/iso-profile" "$dst"
  cp "$TOOLS_DIR/iso-profile-deploy.sh" "$fake_repo/tools/iso-profile-deploy.sh"
  printf 'rootfs:\n  packages:\n    - xorg-server\n' > "$fake_repo/iso-profile/profile.yaml"
  for i in {1..100}; do printf 'file %d\n' "$i" > "$fake_repo/iso-profile/file_$i"; done
  git -C "$fake_repo" init -q
  git -C "$fake_repo" config user.email t@e.st
  git -C "$fake_repo" config user.name t
  git -C "$fake_repo" add -A
  git -C "$fake_repo" commit -qm init
  # Dirty the tracked profile
  printf 'uncommitted edit\n' >> "$fake_repo/iso-profile/profile.yaml"
  unset AEGIX_SYNC_PROFILE
  export ISO_PROFILE_DEST="$dst"
  local rc=0
  bash "$fake_repo/tools/iso-profile-deploy.sh" >/dev/null 2>&1 || rc=$?
  assert_eq "1" "$rc" "dirty tracked iso-profile refuses"
  [[ ! -e "$dst/profile.yaml" ]] && pass "DEST untouched on refusal" || fail "DEST untouched on refusal"
  rc=0
  bash "$fake_repo/tools/iso-profile-deploy.sh" --force-dirty >/dev/null 2>&1 || rc=$?
  assert_eq "0" "$rc" "--force-dirty proceeds"
  assert_file_exists "$dst/profile.yaml" "profile.yaml deployed with --force-dirty"
  teardown
}

# --- Main test runner ---

test_orchestrator_triage_recaptures() {
  log "aegix-sync: newly shipped path is captured in the SAME run"
  setup_workspace
  git -C "$AEGIX_SYNC_REPO" init -q
  git -C "$AEGIX_SYNC_REPO" config user.email t@e.st; git -C "$AEGIX_SYNC_REPO" config user.name t
  mkdir -p "$AEGIX_SYNC_HOME/.local/bin" "$AEGIX_SYNC_PROFILE/live-overlay/root"
  printf 'echo hi\n' > "$AEGIX_SYNC_HOME/.local/bin/tool-a"
  printf 'echo new\n' > "$AEGIX_SYNC_HOME/.local/bin/brand-new"
  printf 'ship\t.local/bin/tool-a\nwatch\t.local/bin\n' > "$AEGIX_SYNC_DIR/files.manifest"
  printf 'rootfs\tnsxiv\t"viewer"\n' > "$AEGIX_SYNC_DIR/packages.manifest"
  printf 'forbid\tSECRETMARKER\tplanted\n' > "$AEGIX_SYNC_DIR/sanitize.rules"
  printf 'rootfs:\n  packages:\n@ROOTFS_PACKAGES@\n  packages-init:\n    runit:\n@ROOTFS_INIT_RUNIT@\nlivefs:\n  packages:\n@LIVEFS_PACKAGES@\n  packages-init:\n    runit:\n@LIVEFS_INIT_RUNIT@\n' > "$AEGIX_SYNC_PROFILE/profile.yaml.tmpl"
  git -C "$AEGIX_SYNC_REPO" add -A >/dev/null; git -C "$AEGIX_SYNC_REPO" commit -qm init
  printf 'ship\t.local/bin/brand-new\n' > "$WORKSPACE/answers"
  AEGIX_SYNC_PKGLIST_CMD="printf 'nsxiv\n'" "$TOOLS_DIR/aegix-sync" --yes --no-deploy --answers "$WORKSPACE/answers" >/dev/null 2>&1
  assert_file_exists "$AEGIX_SYNC_SKEL/.local/bin/brand-new" "newly triaged ship captured in same run"
  teardown
}

test_deploy_excludes_are_root_anchored() {
  log "deploy: only the profile's own README is excluded, not nested ones"
  setup_workspace
  mkdir -p "$AEGIX_SYNC_PROFILE/live-overlay/root" "$AEGIX_SYNC_PROFILE/live-overlay/etc/skel/Applications" "$WORKSPACE/dest"
  printf 'profile docs\n' > "$AEGIX_SYNC_PROFILE/README.md"
  printf 'install me\n'   > "$AEGIX_SYNC_PROFILE/live-overlay/root/README.md"
  printf 'appimages\n'    > "$AEGIX_SYNC_PROFILE/live-overlay/etc/skel/Applications/README.md"
  printf 'x\n' > "$AEGIX_SYNC_PROFILE/profile.yaml"
  i=0; while [ "$i" -lt 105 ]; do printf 'f\n' > "$AEGIX_SYNC_PROFILE/live-overlay/pad$i"; i=$((i+1)); done
  ISO_PROFILE_DEST="$WORKSPACE/dest" AEGIX_SYNC_PROFILE="$AEGIX_SYNC_PROFILE" \
    "$TOOLS_DIR/iso-profile-deploy.sh" >/dev/null 2>&1
  assert_file_exists "$WORKSPACE/dest/live-overlay/root/README.md" "nested root README deploys"
  assert_file_exists "$WORKSPACE/dest/live-overlay/etc/skel/Applications/README.md" "nested skel README deploys"
  [[ ! -f "$WORKSPACE/dest/README.md" ]] && pass "profile's own README still excluded" || fail "profile's own README leaked"
  teardown
}

main() {
  test_fm_load_and_lookup
  test_fm_load_rejects_contradiction
  test_pm_load_and_diff
  test_pm_load_rejects_never_contradiction
  test_sanitize_tree
  test_verify_gate_blocks_leak
  test_verify_gate_match_scoped_allow
  test_verify_gate_nonexistent_root
  test_verify_gate_binary_content
  test_verify_gate_binary_compiled
  test_verify_gate_binary_clean
  test_generation
  test_generation_rejects_whitespace_wrapped_marker
  test_capture_run
  test_capture_symlinks
  test_capture_iso_restore_custom_profile
  test_verify_symlink_targets
  test_capture_iso_no_git_history
  test_capture_iso_dir_untracked_stray
  test_capture_gitignore_purge
  test_discover_and_triage
  test_discover_dotfiles
  test_discover_descend_symlinks
  test_triage_descend_ordering
  test_drift_status
  test_drift_status_iso_no_false_positive
  test_drift_status_missing_profile
  test_orchestrator_status
  test_orchestrator_dry_run
  test_orchestrator_triage_recaptures
  test_orchestrator_end_to_end
  test_orchestrator_generate_failure_restores
  test_orchestrator_bogus_answers_file
  test_orchestrator_preflight_staged_elsewhere
  test_deploy_excludes_are_root_anchored
  test_deploy_full_scope
  test_deploy_empty_dest_variable
  test_deploy_no_prod_no_dest
  test_deploy_empty_src
  test_deploy_missing_profile_yaml
  test_deploy_mass_delete
  test_deploy_delete_gate_unit
  test_deploy_dry_run_scan_failure
  test_deploy_zero_deletions_already_in_sync
  test_deploy_first_run_empty_dest
  test_orchestrator_deploy_includes_prod_flag
  test_deploy_refuses_dirty_profile
  printf '\n%d run, %d failed\n' "$TESTS_RUN" "$TESTS_FAILED"
  [[ "$TESTS_FAILED" -eq 0 ]]
}

main

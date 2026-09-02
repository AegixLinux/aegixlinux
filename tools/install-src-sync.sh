#!/usr/bin/env bash
# Idempotent installer. Symlinks src-sync-post-commit into each live repo's
# .git/hooks/post-commit, based on src-sync.conf.
#
# Usage: install-src-sync.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

: "${SRC_SYNC_CONF:=$SCRIPT_DIR/src-sync.conf}"
HOOK_TEMPLATE="$SCRIPT_DIR/src-sync-post-commit"
GATE_TEMPLATE="$SCRIPT_DIR/src-gate-pre-push"

source "$SCRIPT_DIR/src-sync-lib.sh"

if [[ ! -x "$HOOK_TEMPLATE" ]]; then
  echo "install: $HOOK_TEMPLATE missing or not executable" >&2
  exit 1
fi
if [[ ! -x "$GATE_TEMPLATE" ]]; then
  echo "install: $GATE_TEMPLATE missing or not executable" >&2
  exit 1
fi

# install_gate <live-repo-path>: symlink the pre-push leak gate into a repo.
install_gate() {
  ln -sf "$GATE_TEMPLATE" "$1/.git/hooks/pre-push"
}

printf '%-30s %-40s %s\n' "LIVE_REPO" "AEGIX_SUBMODULE" "STATUS"
printf '%-30s %-40s %s\n' "---------" "---------------" "------"

while read -r live aegix; do
  name="$(basename "$live")"
  hook_path="$live/.git/hooks/post-commit"

  # Check live repo exists
  if [[ ! -d "$live/.git" ]]; then
    printf '%-30s %-40s %s\n' "$name" "$aegix" "✗ live .git missing"
    continue
  fi

  # Check AEGIX submodule exists (as dir or file gitlink)
  if [[ ! -e "$aegix" ]]; then
    printf '%-30s %-40s %s\n' "$name" "$aegix" "✗ aegix path missing"
    continue
  fi

  # Install or refresh the symlinks (post-commit sync + pre-push leak gate)
  ln -sf "$HOOK_TEMPLATE" "$hook_path"
  chmod +x "$HOOK_TEMPLATE"
  install_gate "$live"
  printf '%-30s %-40s %s\n' "$name" "$aegix" "✓ hooks installed (post-commit, pre-push)"
done < <(parse_conf "$SRC_SYNC_CONF")

# Gate-only repos: public repos the gate must cover that src-sync does not
# sync (no submodule). Declared as "#gate-extra <path>" lines in the conf.
while IFS= read -r line; do
  [[ "$line" =~ ^#gate-extra[[:space:]]+(.+)$ ]] || continue
  extra="${BASH_REMATCH[1]}"
  extra="${extra/#\~/$HOME}"
  name="$(basename "$extra")"
  if [[ ! -d "$extra/.git" ]]; then
    printf '%-30s %-40s %s\n' "$name" "(gate only)" "✗ live .git missing"
    continue
  fi
  install_gate "$extra"
  printf '%-30s %-40s %s\n' "$name" "(gate only)" "✓ pre-push gate installed"
done < "$SRC_SYNC_CONF"

echo
echo "Done. To remove hooks later: rm <live>/.git/hooks/post-commit <live>/.git/hooks/pre-push"

#!/usr/bin/env bash
# Idempotent installer. Symlinks src-sync-post-commit into each live repo's
# .git/hooks/post-commit, based on src-sync.conf.
#
# Usage: install-src-sync.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

: "${SRC_SYNC_CONF:=$SCRIPT_DIR/src-sync.conf}"
HOOK_TEMPLATE="$SCRIPT_DIR/src-sync-post-commit"

source "$SCRIPT_DIR/src-sync-lib.sh"

if [[ ! -x "$HOOK_TEMPLATE" ]]; then
  echo "install: $HOOK_TEMPLATE missing or not executable" >&2
  exit 1
fi

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

  # Install or refresh the symlink
  ln -sf "$HOOK_TEMPLATE" "$hook_path"
  chmod +x "$HOOK_TEMPLATE"
  printf '%-30s %-40s %s\n' "$name" "$aegix" "✓ hook installed"
done < <(parse_conf "$SRC_SYNC_CONF")

echo
echo "Done. To remove a hook later: rm <live>/.git/hooks/post-commit"

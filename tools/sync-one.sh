#!/usr/bin/env bash
# Recovery utility. Runs the core sync against a single repo listed in
# src-sync.conf, bypassing the hook's precondition checks.
#
# Usage: sync-one.sh <repo-name>
# Example: sync-one.sh dwm

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

: "${SRC_SYNC_CONF:=$HOME/code/PROJECTS/AEGIX/tools/src-sync.conf}"
: "${SRC_SYNC_AEGIX_PARENT:=$HOME/code/PROJECTS/AEGIX}"

source "$SCRIPT_DIR/src-sync-lib.sh"

if [[ $# -ne 1 ]]; then
  echo "usage: $(basename "$0") <repo-name>" >&2
  exit 2
fi

REPO_NAME="$1"

# Find live path by matching the basename in conf.
LIVE_PATH=""
AEGIX_PATH=""
while read -r live aegix; do
  if [[ "$(basename "$live")" == "$REPO_NAME" ]]; then
    LIVE_PATH="$live"
    AEGIX_PATH="$aegix"
    break
  fi
done < <(parse_conf "$SRC_SYNC_CONF")

if [[ -z "$LIVE_PATH" ]]; then
  echo "sync-one: repo '$REPO_NAME' not found in $SRC_SYNC_CONF" >&2
  exit 1
fi

# Back up AEGIX WIP if dirty (same safety as the hook).
if BACKUP_PATH="$(backup_aegix_wip "$AEGIX_PATH")" && [[ -n "$BACKUP_PATH" ]]; then
  printf '[aegix-src-sync] %s: AEGIX-side WIP saved to %s\n' "$REPO_NAME" "$BACKUP_PATH"
fi

sync_repo "$LIVE_PATH" "$AEGIX_PATH" "$SRC_SYNC_AEGIX_PARENT"

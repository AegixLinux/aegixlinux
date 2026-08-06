#!/usr/bin/env bash
# One-shot reconciler. Makes AEGIX submodules match live's HEAD, backing up
# any AEGIX-side uncommitted edits first. Also swaps live remotes HTTPS→SSH
# so the post-commit hook's git push runs non-interactively.
#
# Usage:
#   bootstrap-src-sync.sh             # do the work
#   bootstrap-src-sync.sh --dry-run   # print what it would do, change nothing

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

: "${SRC_SYNC_CONF:=$SCRIPT_DIR/src-sync.conf}"
: "${SRC_SYNC_AEGIX_PARENT:=$HOME/code/PROJECTS/AEGIX}"

source "$SCRIPT_DIR/src-sync-lib.sh"

DRY_RUN=0
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=1
fi

say() {
  if [[ $DRY_RUN -eq 1 ]]; then
    printf '[dry-run] %s\n' "$*"
  else
    printf '[bootstrap] %s\n' "$*"
  fi
}

swap_remote_to_ssh() {
  local live="$1"
  local url
  url="$(git -C "$live" remote get-url origin)"
  if [[ "$url" =~ ^https://github\.com/([^/]+)/(.+)(\.git)?$ ]]; then
    local owner="${BASH_REMATCH[1]}"
    local repo="${BASH_REMATCH[2]%.git}"
    local new_url="git@github.com:${owner}/${repo}.git"
    say "swap remote in $live: $url → $new_url"
    if [[ $DRY_RUN -eq 0 ]]; then
      git -C "$live" remote set-url origin "$new_url"
    fi
  else
    say "remote already SSH or non-github in $live: $url (skipping swap)"
  fi
}

echo "bootstrap-src-sync.sh (dry-run=$DRY_RUN)"
echo "conf: $SRC_SYNC_CONF"
echo "aegix parent: $SRC_SYNC_AEGIX_PARENT"
echo

while read -r live aegix; do
  name="$(basename "$live")"
  echo "--- $name ---"

  # Back up AEGIX WIP if dirty
  if [[ -n "$(git -C "$aegix" status --porcelain 2>/dev/null)" ]]; then
    if [[ $DRY_RUN -eq 1 ]]; then
      say "would back up AEGIX-side edits in $aegix"
    else
      if path="$(backup_aegix_wip "$aegix")" && [[ -n "$path" ]]; then
        say "backed up AEGIX WIP to $path"
      fi
    fi
  fi

  # Reset AEGIX submodule to match live HEAD
  live_head="$(git -C "$live" rev-parse HEAD)"
  aegix_head="$(git -C "$aegix" rev-parse HEAD 2>/dev/null || echo NONE)"
  if [[ "$live_head" == "$aegix_head" ]]; then
    say "$name: already in sync at $aegix_head"
  else
    say "$name: reset AEGIX $aegix_head → $live_head"
    if [[ $DRY_RUN -eq 0 ]]; then
      # Fetch from live directly (not origin) in case live has unpushed commits
      # during the bootstrap itself. Fetch live's current HEAD rather than a
      # hardcoded branch name -- Aegix is moving these repos from master to
      # main, and naming the branch here would break the moment one is renamed.
      git -C "$aegix" fetch -q "$live" HEAD
      git -C "$aegix" reset --hard FETCH_HEAD >/dev/null
      # Stage the pointer bump in AEGIX parent
      git -C "$SRC_SYNC_AEGIX_PARENT" add "$name"
    fi
  fi

  # Swap live remote HTTPS → SSH (skippable for tests via SRC_SYNC_SKIP_REMOTE_SWAP=1)
  if [[ "${SRC_SYNC_SKIP_REMOTE_SWAP:-0}" != "1" ]]; then
    swap_remote_to_ssh "$live"
  fi

  echo
done < <(parse_conf "$SRC_SYNC_CONF")

if [[ $DRY_RUN -eq 1 ]]; then
  echo "Dry-run complete. Nothing changed. Re-run without --dry-run to apply."
else
  echo "Bootstrap complete."
  echo "Review staged bumps in $SRC_SYNC_AEGIX_PARENT (git status), then:"
  echo "  cd $SRC_SYNC_AEGIX_PARENT && git commit -m 'Bump suckless pins from live src'"
  echo "Then run: $SCRIPT_DIR/install-src-sync.sh to enable post-commit hooks."
fi

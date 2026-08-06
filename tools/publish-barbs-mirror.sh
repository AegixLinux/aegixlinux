#!/usr/bin/env bash
# publish-barbs-mirror.sh: push the canonical BARBS into the barbs repo.
#
# iso-profile/live-overlay/root/ holds the barbs.sh and aegix-programs.csv
# that actually ship. github.com/aegixlinux/barbs exists so people can run
# BARBS standalone on an existing Artix install, so it must mirror those, the
# same way gohan mirrors the dotfiles rather than sourcing them.
#
# Usage: tools/publish-barbs-mirror.sh [--apply]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/iso-profile/live-overlay/root"
DEST="$ROOT/barbs"
APPLY=0; [ "${1:-}" = "--apply" ] && APPLY=1

git -C "$DEST" rev-parse --git-dir >/dev/null 2>&1 || { echo "barbs submodule not initialised at $DEST" >&2; exit 1; }

changed=0
for f in barbs.sh aegix-programs.csv; do
    if cmp -s "$SRC/$f" "$DEST/$f"; then
        printf '  same    %s\n' "$f"
    else
        changed=$((changed+1))
        printf '  %-7s %s\n' "$([ "$APPLY" = 1 ] && echo update || echo STALE)" "$f"
        [ "$APPLY" = 1 ] && cp "$SRC/$f" "$DEST/$f"
    fi
done

[ "$changed" -eq 0 ] && { echo "barbs mirror is current."; exit 0; }
[ "$APPLY" = 1 ] || { echo; echo "Re-run with --apply to update the mirror."; exit 0; }
cat <<MSG

Updated $changed file(s) in $DEST. To publish:
  cd $DEST && git add -A && git commit && git push
  cd $ROOT  && git add barbs && git commit && git push
MSG

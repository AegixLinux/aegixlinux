#!/usr/bin/env bash
# publish-gohan-mirror.sh: make the gohan repo an exact mirror of the ISO skel.
#
# iso-profile/live-overlay/etc/skel/ holds the dotfiles that actually ship.
# github.com/aegixlinux/gohan exists so BARBS can deploy those dotfiles when it
# runs standalone on a system without the Aegix skel, so it must mirror skel,
# the same way the barbs repo mirrors barbs.sh and aegix-programs.csv.
#
# Mirror rules:
#   - every file under skel is copied to gohan (added or updated)
#   - files only in gohan are deleted, except gohan's own repo files (KEEP)
#   - skel paths in SKIP are never mirrored (.local/src: BARBS clones and
#     builds the suckless repos there itself)
#
# After --apply, a leak gate scans gohan with the `forbid` rules from
# sync/sanitize.rules plus a few fixed patterns, and fails loudly on a hit.
#
# Usage: tools/publish-gohan-mirror.sh [--apply]
#   (no flag)  dry run: list what would change, touch nothing
#   --apply    copy/delete, run the leak gate, print the publish commands
#
# Env (tests): AEGIX_ROOT overrides the monorepo root.
set -euo pipefail

ROOT="${AEGIX_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
SRC="$ROOT/iso-profile/live-overlay/etc/skel"
DEST="$ROOT/gohan"
RULES="$ROOT/sync/sanitize.rules"
APPLY=0; [ "${1:-}" = "--apply" ] && APPLY=1

# Repo files that live only in gohan and must survive the mirror.
KEEP=(/.git /.gitignore /.gitmodules /README.md /LICENSE /FUNDING.yml
      /.config/mpv/script_modules/mpvSockets)
# Skel paths that never go to gohan.
SKIP=(/.local/src)

[ -d "$SRC" ] || { echo "skel not found at $SRC" >&2; exit 1; }
git -C "$DEST" rev-parse --git-dir >/dev/null 2>&1 || { echo "gohan repo not initialised at $DEST" >&2; exit 1; }
command -v rsync >/dev/null || { echo "rsync is required" >&2; exit 1; }

filters=()
for p in "${KEEP[@]}"; do filters+=(--filter="protect $p"); done
# Untracked and gitignored files in the gohan checkout (nvim plugins, caches,
# logs) never reach GitHub; the mirror leaves them alone.
while IFS= read -r p; do
    [ -n "$p" ] && filters+=(--filter="protect /${p%/}")
done < <(git -C "$DEST" ls-files --others --directory)
for p in "${SKIP[@]}"; do filters+=(--filter="exclude $p"); done

run_rsync() {
    rsync -a --checksum --delete --itemize-changes "${filters[@]}" "$@" "$SRC/" "$DEST/"
}

# Keep only itemized change lines; drop unchanged dirs and rsync notices such as
# "cannot delete non-empty directory" (a protected untracked file lives inside).
# Also drop timestamp-only differences: git does not track mtimes.
changes=$(run_rsync --dry-run | grep -E '^(\*deleting|[<>ch.][fdLDS])' | grep -vE '^\.d' \
    | grep -vE '^[.>][fL][.t]{9} ' || true)
if [ -z "$changes" ]; then
    echo "gohan mirror is current."
    exit 0
fi

added=$(printf '%s\n' "$changes" | grep -cE '^>f\+{9}|^cL\+{9}' || true)
deleted=$(printf '%s\n' "$changes" | grep -c '^\*deleting' || true)
total=$(printf '%s\n' "$changes" | grep -c . || true)
updated=$((total - added - deleted))

printf '%s\n' "$changes" | sed -E \
    -e 's/^\*deleting +/  delete  /' \
    -e 's/^[>c][fL]\+{9} /  add     /' \
    -e 's/^[>c.][fL][^ ]* /  update  /' \
    -e 's/^cd\+{9} /  mkdir   /'
echo
echo "gohan: +$added added, ~$updated updated, -$deleted deleted"

if [ "$APPLY" != 1 ]; then
    echo
    echo "Dry run. Re-run with --apply to update the mirror."
    exit 0
fi

run_rsync >/dev/null

# ---- leak gate -------------------------------------------------------------
live_user="${LIVE_USER:-$(id -un)}"
live_email="${LIVE_EMAIL:-$(git config user.email 2>/dev/null || true)}"
patterns=('code/(STRIDE|PROJECTS)' 'k12\.com')
if [ -r "$RULES" ]; then
    while IFS=$'\t' read -r kind pat _; do
        [ "$kind" = forbid ] || continue
        pat=${pat//'${LIVE_USER}'/$live_user}
        pat=${pat//'${LIVE_EMAIL}'/$live_email}
        # A rule whose variable resolved to empty would match everything.
        [[ "$pat" == *'||'* || "$pat" == '|'* || "$pat" == *'|' || -z "$pat" ]] && continue
        patterns+=("$pat")
    done < "$RULES"
fi
# Scan only what a `git add -A` would publish: tracked + new, not gitignored.
mapfile -t publish < <(cd "$DEST" && git ls-files --cached --others --exclude-standard | while IFS= read -r f; do [ -f "$f" ] && printf '%s\n' "$f"; done)
leaks=0
for pat in "${patterns[@]}"; do
    hits=$(cd "$DEST" && printf '%s\0' "${publish[@]}" | xargs -0 -r grep -lIE -e "$pat" 2>/dev/null || true)
    names=$(printf '%s\n' "${publish[@]}" | grep -E -e "$pat" || true)
    if [ -n "$hits$names" ]; then
        leaks=1
        echo "LEAK GATE: pattern '$pat' matched:" >&2
        printf '%s\n%s\n' "$hits" "$names" | grep . | sort -u | sed 's/^/    /' >&2
    fi
done
if [ "$leaks" = 1 ]; then
    echo >&2
    echo "Leak gate FAILED. gohan was updated on disk but nothing is committed." >&2
    echo "Fix skel (and sync/sanitize.rules), then re-run. To discard: git -C $DEST checkout -- . && git -C $DEST clean -fd" >&2
    exit 2
fi
echo "Leak gate passed (${#patterns[@]} patterns)."

cat <<MSG

Updated $DEST. To publish:
  cd $DEST && git add -A && git commit && git push
  cd $ROOT  && git add gohan && git commit && git push
MSG

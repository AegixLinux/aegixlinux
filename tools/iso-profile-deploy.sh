#!/bin/bash
# iso-profile-deploy.sh — push the WHOLE tracked iso-profile/ into the artools
# profile dir. --delete makes the system side a pure mirror of git.
# SAFETY: requires --prod for production, detects set-but-empty ISO_PROFILE_DEST,
# guards against empty SRC, and mass deletions. Dry-run gate fails closed.
set -euo pipefail

PROD_MODE=0
ALLOW_MASS_DELETE=0
FORCE_DIRTY=0

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prod) PROD_MODE=1; shift ;;
    --allow-mass-delete) ALLOW_MASS_DELETE=1; shift ;;
    --force-dirty) FORCE_DIRTY=1; shift ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

# Resolve source and destination
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${AEGIX_SYNC_PROFILE:-$REPO_ROOT/iso-profile}"
DST="${ISO_PROFILE_DEST-unset}"

# Detect set-but-empty ISO_PROFILE_DEST (critical safety check)
if [[ "${ISO_PROFILE_DEST+x}" == "x" && -z "$ISO_PROFILE_DEST" ]]; then
  echo "Error: ISO_PROFILE_DEST is set but empty (potential production wipe risk)" >&2
  exit 2
fi

# Route to test or production
if [[ "$DST" == "unset" ]]; then
  # No ISO_PROFILE_DEST set: production mode required
  if [[ $PROD_MODE -eq 0 ]]; then
    echo "Error: Production mode requires --prod flag" >&2
    echo "  For testing: set ISO_PROFILE_DEST=/path/to/scratch" >&2
    exit 2
  fi
  DST="/usr/share/artools/iso-profiles/aegix"
fi

# Validate source directory and contents
[ -d "$SRC" ] || { echo "Source missing: $SRC" >&2; exit 1; }
[ -f "$SRC/profile.yaml" ] || { echo "Source corrupted (profile.yaml missing): $SRC" >&2; exit 1; }
file_count=$(find "$SRC" -type f | wc -l) || { echo "Error scanning source: $SRC" >&2; exit 1; }
if [[ $file_count -lt 100 ]]; then
  echo "Error: source has only $file_count files (expected ~100+); possible corruption" >&2
  exit 1
fi

# Refuse to deploy an in-progress edit: uncommitted changes under the actual
# source being deployed could be unsanitized content that never went through
# the sync verify gate. --force-dirty overrides for deliberate local
# iteration. Keyed off $SRC's own git status (not a hardcoded
# $REPO_ROOT/iso-profile) so an AEGIX_SYNC_PROFILE override that points SRC
# somewhere else is still covered; skipped (with a note) when $SRC isn't
# inside a git work tree at all.
if [[ $FORCE_DIRTY -eq 0 ]]; then
  src_repo_root="$(git -C "${SRC%/}" rev-parse --show-toplevel 2>/dev/null || true)"
  if [[ -n "$src_repo_root" ]]; then
    src_rel="${SRC%/}"; src_rel="${src_rel#"$src_repo_root"/}"
    dirty_profile="$(git -C "$src_repo_root" status --porcelain -- "$src_rel" 2>/dev/null || true)"
    if [[ -n "$dirty_profile" ]]; then
      echo "Error: $src_rel has uncommitted changes in $src_repo_root — refusing to deploy possibly-unsanitized content" >&2
      echo "$dirty_profile" >&2
      echo "Commit or stash first, or pass --force-dirty to override." >&2
      exit 1
    fi
  else
    echo "Note: $SRC is not inside a git work tree — skipping dirty-profile check" >&2
  fi
fi

# Helper: evaluate dry-run result and decide whether to proceed
# Fails CLOSED: if dry-run fails to scan (rc != 0) and we parsed 0 deletions,
# abort immediately without attempting the privileged operation.
_deploy_delete_gate() {
  local dryrun_rc="$1" count="$2"

  # Scan failure with zero deletions parsed: fail closed
  if [[ $dryrun_rc -ne 0 && $count -eq 0 ]]; then
    echo "Error: could not verify deletion scope, dry-run scan failed" >&2
    return 1
  fi

  # Scan succeeded or produced parseable deletions: apply threshold gate
  if [[ $count -gt 25 && $ALLOW_MASS_DELETE -eq 0 ]]; then
    echo "Error: would delete $count files (> 25 threshold)" >&2
    echo "Mass deletion detected. Use --allow-mass-delete if this is intentional." >&2
    return 1
  fi

  return 0
}

# Deletion gate: dry run to count deletions
RSYNC=(rsync -av --no-times --delete --exclude /profile.yaml.tmpl --exclude /README.md)
# Note: rsync --delete + --exclude preserves pre-existing excluded files in DEST
# (i.e., stale profile.yaml.tmpl or README.md copies can accumulate by design).
# Capture rc in parent shell (not subshell) so gate can verify scan success.
dryrun_rc=0
if dryrun_output=$("${RSYNC[@]}" -n "$SRC/" "$DST/" 2>/dev/null); then
  dryrun_rc=0
else
  dryrun_rc=$?
fi
# grep -c prints the match count itself (including "0"), so the pipeline
# succeeds even with zero matches; `|| true` guards against grep's own
# nonzero exit status still tripping pipefail in that same zero-match case.
deletion_count=$(echo "$dryrun_output" | grep -c "^deleting " || true)

if ! _deploy_delete_gate "$dryrun_rc" "$deletion_count"; then
  if [[ $dryrun_rc -ne 0 && $deletion_count -eq 0 ]]; then
    # Scan failed, abort without touching DEST
    exit 1
  else
    # Mass deletion gate triggered, show sample
    echo "Sample deletions:" >&2
    echo "$dryrun_output" | grep "^deleting " | head -5 | sed 's/^/  /' >&2
    exit 1
  fi
fi

# Execute the actual rsync
# Note: --prod means both "may fall back to hardcoded production default path"
# AND "use sudo+chown regardless of destination" when combined with explicit ISO_PROFILE_DEST.
if [[ $PROD_MODE -eq 1 ]]; then
  sudo "${RSYNC[@]}" --chown=root:root "$SRC/" "$DST/"
else
  "${RSYNC[@]}" "$SRC/" "$DST/"
fi

echo "Deployed $SRC -> $DST"
if [[ $PROD_MODE -eq 1 ]]; then
  echo "To rebuild: sudo rm -f /var/lib/artools/buildiso/aegix/aegix/*.lock && sudo buildiso -p aegix -i runit"
fi

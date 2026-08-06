#!/usr/bin/env bash
# build-aegix-iso.sh: one-command Aegix ISO build with proper naming.
#
# artools' buildiso hardcodes the "artix-<profile>-<init>" filename prefix
# (gen_iso_fn in /usr/bin/buildiso; patching that binary does not survive
# package upgrades, which is how the old aegix- prefix silently reverted).
# Aegix is runit by definition, so the shipped artifact is renamed to
#   aegix-<version>-<arch>.iso
# If Aegix ever ships a different init, that ISO gets its own distinct name.
#
# Usage: tools/build-aegix-iso.sh
set -euo pipefail

ISO_DIR="$HOME/artools-workspace/iso/aegix"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROFILE_DEST="${ISO_PROFILE_DEST:-/usr/share/artools/iso-profiles/aegix}"

# Stamp the deployed profile with build provenance so any installed system can
# say exactly which ISO it came from. Written to the deployed profile (not the
# tracked one) so builds never dirty git or trip the deploy cleanliness gate.
commit="$(git -C "$REPO_ROOT" rev-parse --short HEAD)"
dirty="clean"; git -C "$REPO_ROOT" diff --quiet -- iso-profile sync || dirty="dirty"
stamp="$(date +%Y%m%d)"
sudo tee "$PROFILE_DEST/live-overlay/etc/aegix-release" >/dev/null <<STAMP
AEGIX_ISO_VERSION=$stamp
AEGIX_ISO_BUILD_DATE=$(date -Is)
AEGIX_PROFILE_COMMIT=$commit
AEGIX_PROFILE_STATE=$dirty
AEGIX_ISO_NAME=aegix-$stamp-x86_64.iso
STAMP
echo "stamped: commit $commit ($dirty)"

sudo bash -c 'rm -f /var/lib/artools/buildiso/aegix/aegix/*.lock 2>/dev/null
              exec buildiso -p aegix -i runit'

raw=$(ls -t "$ISO_DIR"/artix-aegix-runit-*.iso 2>/dev/null | head -1)
[ -n "$raw" ] || { echo "build-aegix-iso: no artix-aegix-runit-*.iso found in $ISO_DIR" >&2; exit 1; }

# artix-aegix-runit-<version>-<arch>.iso -> aegix-<version>-<arch>.iso
final="$ISO_DIR/aegix-$(basename "$raw" | sed 's/^artix-aegix-runit-//')"
mv "$raw" "$final"
echo "ISO ready: $final"
echo "Next: tools/qemu-test-aegix.sh (interactive) or tools/qemu-headless-validate.sh start"

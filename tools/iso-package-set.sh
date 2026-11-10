#!/usr/bin/env bash
# iso-package-set.sh: print the exact "name version" package list inside an
# Aegix ISO, read from the pacman database in LiveOS/rootfs.img.
#
# build-aegix-iso.sh saves this as aegix-<date>-packages.txt next to the ISO,
# so tools/security-weekly.sh can later ask "does the RELEASED ISO ship a
# package with a known, fixed vulnerability?" without rebuilding anything.
#
# Usage: tools/iso-package-set.sh ISO > packages.txt   (needs sudo: mount)
set -euo pipefail

ISO="${1:?usage: iso-package-set.sh ISO}"
[ -r "$ISO" ] || { echo "cannot read $ISO" >&2; exit 1; }
command -v unsquashfs >/dev/null || { echo "unsquashfs (squashfs-tools) is required" >&2; exit 1; }

TMP="$(mktemp -d)"
cleanup() { sudo umount "$TMP/mnt" 2>/dev/null || true; sudo rm -rf "$TMP"; }
trap cleanup EXIT
mkdir -p "$TMP/mnt"

sudo mount -o loop,ro "$ISO" "$TMP/mnt"
sudo unsquashfs -q -d "$TMP/root" "$TMP/mnt/LiveOS/rootfs.img" var/lib/pacman/local >/dev/null

# Each package dir holds a desc file with %NAME% and %VERSION% blocks.
for desc in "$TMP"/root/var/lib/pacman/local/*/desc; do
    sudo awk '/^%NAME%$/{getline; n=$0} /^%VERSION%$/{getline; v=$0} END{print n, v}' "$desc"
done | sort

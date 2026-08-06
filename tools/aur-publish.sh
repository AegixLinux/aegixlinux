#!/usr/bin/env bash
# aur-publish.sh — local verify helper for AUR packages.
# Regenerates .SRCINFO, runs namcap, then clean-sandbox makepkg -s.
# Does NOT push to AUR — caller does `git commit && git push` manually
# after reviewing this script's output.
#
# Usage: aur-publish.sh <pkgname>
# Example: aur-publish.sh dwm-aegix-git

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $(basename "$0") <pkgname>" >&2
  exit 2
fi

PKG="$1"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG_DIR="$REPO_ROOT/aur/$PKG"

if [[ ! -d "$PKG_DIR" ]]; then
  echo "error: $PKG_DIR does not exist" >&2
  exit 1
fi

if [[ ! -f "$PKG_DIR/PKGBUILD" ]]; then
  echo "error: $PKG_DIR/PKGBUILD does not exist" >&2
  exit 1
fi

cd "$PKG_DIR"

echo "=== [1/3] Linting PKGBUILD with namcap ==="
namcap_output="$(namcap PKGBUILD 2>&1 || true)"
if [[ -z "$namcap_output" ]]; then
  echo "  namcap: clean"
else
  echo "$namcap_output"
  # namcap errors are prefixed "E:", warnings are "W:". Block on E:, allow W:.
  if echo "$namcap_output" | grep -q '^PKGBUILD E:'; then
    echo
    echo "  namcap reported ERRORS — fix PKGBUILD before publishing."
    exit 1
  fi
fi
echo

echo "=== [2/3] Clean-sandbox build test (makepkg -s --clean) ==="
# For -git packages, makepkg runs pkgver() and rewrites the PKGBUILD's pkgver
# in place. We need .SRCINFO generated AFTER this step so it reflects the real
# version, not the initial dummy r0.0000000 placeholder.
makepkg -s --clean --noconfirm
echo

echo "=== [3/3] Regenerating .SRCINFO from post-build PKGBUILD ==="
makepkg --printsrcinfo > .SRCINFO
echo "  .SRCINFO written ($(wc -l < .SRCINFO) lines), pkgver=$(grep -m1 '^\s*pkgver' .SRCINFO | awk '{print $3}')"
echo

echo "=== PASS: $PKG verified ==="
echo "Next: review git diff, then push to AUR:"
echo "  cd $PKG_DIR"
echo "  git add PKGBUILD .SRCINFO"
echo "  git commit -m '<message>'"
echo "  git push"

#!/bin/sh
# Publish the Aegix payload to aegixlinux.org.
#
# The installer payload is served straight from the ISO profile, which is the
# single source of truth: iso-profile/live-overlay/root/ holds exactly the
# install.sh, barbs.sh and aegix-programs.csv that ship on the ISO. They used
# to be maintained separately here and in barbs/, and drifted five months
# behind before anyone noticed.
set -eu

PAYLOAD=iso-profile/live-overlay/root
DEST=vultr:/var/www/aegixlinux.org

rsync -v "$PAYLOAD/install.sh"         "$DEST"
rsync -v "$PAYLOAD/barbs.sh"           "$DEST"
rsync -v "$PAYLOAD/aegix-programs.csv" "$DEST"
rsync -v ascii-aegix                   "$DEST"
rsync -v README.md                     "$DEST"
rsync -vhrla images/                   "$DEST/images"

echo
echo "Published. Verify:"
echo "  curl -s https://aegixlinux.org/install.sh | diff -q - $PAYLOAD/install.sh"

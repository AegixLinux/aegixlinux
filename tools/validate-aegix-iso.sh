#!/bin/bash
# validate-aegix-iso.sh — Validate an Aegix ISO without booting
# Usage: sudo ./validate-aegix-iso.sh /path/to/aegix.iso

set -euo pipefail
ISO="${1:?Usage: $0 <iso-path>}"
WORK="/tmp/aegix-validate-$$"
ISO_MNT="$WORK/iso"
ROOTFS_MNT="$WORK/rootfs"
LIVEFS_MNT="$WORK/livefs"
MERGED="$WORK/merged"

cleanup() {
    umount "$ISO_MNT" 2>/dev/null || true
    rm -rf "$WORK"
}
trap cleanup EXIT

mkdir -p "$ISO_MNT" "$ROOTFS_MNT" "$LIVEFS_MNT" "$MERGED"

echo "=== Mounting ISO ==="
mount -o loop,ro "$ISO" "$ISO_MNT"

echo "=== Extracting rootfs (key dirs only) ==="
unsquashfs -f -d "$ROOTFS_MNT" "$ISO_MNT/LiveOS/rootfs.img" \
    etc/runit etc/hostname etc/os-release usr/lib/os-release etc/lsb-release \
    etc/artools etc/default/grub etc/skel 2>/dev/null

echo "=== Extracting livefs ==="
unsquashfs -f -d "$LIVEFS_MNT" "$ISO_MNT/LiveOS/livefs.img" 2>/dev/null

echo ""
echo "========================================="
echo "  AEGIX ISO VALIDATION"
echo "========================================="

PASS=0; FAIL=0
check() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then
        echo "  PASS: $desc"
        ((PASS++))
    else
        echo "  FAIL: $desc"
        ((FAIL++))
    fi
}

echo ""
echo "--- Boot Files ---"
check "vmlinuz exists"       test -f "$ISO_MNT/boot/vmlinuz-x86_64"
check "initramfs exists"     test -f "$ISO_MNT/boot/initramfs-x86_64.img"
check "GRUB config exists"   test -f "$ISO_MNT/boot/grub/grub.cfg"
check "rootfs.img exists"    test -f "$ISO_MNT/LiveOS/rootfs.img"
check "livefs.img exists"    test -f "$ISO_MNT/LiveOS/livefs.img"

echo ""
echo "--- Runit Services (merged) ---"
cp -a "$ROOTFS_MNT/etc/runit/runsvdir/default/"* "$MERGED/" 2>/dev/null || true
cp -a "$LIVEFS_MNT/etc/runit/runsvdir/default/"* "$MERGED/" 2>/dev/null || true
echo "  Enabled: $(ls -1 "$MERGED/" 2>/dev/null | tr '\n' ' ')"
check "NetworkManager"  test -L "$MERGED/NetworkManager"
check "dbus"            test -L "$MERGED/dbus"
check "udevd"           test -L "$MERGED/udevd"
check "agetty-tty1"     test -L "$MERGED/agetty-tty1"

echo ""
echo "--- Branding ---"
OS_REL="$LIVEFS_MNT/usr/lib/os-release"
[ ! -f "$OS_REL" ] && OS_REL="$ROOTFS_MNT/usr/lib/os-release"
check "os-release says Aegix"  grep -q "Aegix" "$OS_REL"
check "GRUB theme = aegix"    test -d "$ISO_MNT/boot/grub/themes/aegix"
check "variable.cfg -> aegix" grep -q "aegix" "$ISO_MNT/boot/grub/variable.cfg"

echo ""
echo "--- Live Session ---"
check "root autologin conf"   grep -q "autologin root" "$LIVEFS_MNT/etc/runit/sv/agetty-tty1/conf"
check "install.sh in /root"   test -f "$LIVEFS_MNT/root/install.sh"
check "install.sh in PATH"    test -f "$LIVEFS_MNT/usr/local/bin/install.sh"
check "pacman-init has archlinux" grep -q "populate archlinux" "$LIVEFS_MNT/etc/runit/sv/pacman-init/run"
check "elogind dbus masked"   grep -q "/bin/false" "$LIVEFS_MNT/usr/share/dbus-1/system-services/org.freedesktop.login1.service"

echo ""
echo "--- Sanitization ---"
check "no hardcoded username" bash -c "! grep -r 'trashh_panda' '$LIVEFS_MNT/etc/skel/' 2>/dev/null | grep -q ."

echo ""
echo "========================================="
echo "  TOTAL: $PASS passed, $FAIL failed"
echo "========================================="
exit $FAIL

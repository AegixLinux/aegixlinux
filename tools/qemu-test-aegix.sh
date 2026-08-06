#!/bin/bash
# qemu-test-aegix.sh — Boot Aegix ISO in QEMU for testing
#
# Usage:
#   ./qemu-test-aegix.sh                    # Latest ISO, UEFI mode
#   ./qemu-test-aegix.sh path/to.iso        # Specific ISO, UEFI mode
#   ./qemu-test-aegix.sh path/to.iso bios   # Specific ISO, BIOS mode
#   ./qemu-test-aegix.sh --installed        # Boot from installed disk (no ISO)
#   ./qemu-test-aegix.sh --installed bios   # Boot installed disk, BIOS mode
#   ./qemu-test-aegix.sh --reset            # Delete virtual disks and start fresh

set -euo pipefail

ISO_DIR="$HOME/artools-workspace/iso/aegix"
OVMF_CODE="/usr/share/edk2-ovmf/x64/OVMF_CODE.4m.fd"
OVMF_VARS_SRC="/usr/share/edk2-ovmf/x64/OVMF_VARS.4m.fd"
OVMF_VARS="/tmp/aegix-ovmf-vars.fd"
DISK_UEFI="/tmp/aegix-test-disk-uefi.qcow2"
DISK_BIOS="/tmp/aegix-test-disk-bios.qcow2"
DISK_SIZE="20G"
RAM="4096"
CPUS="2"

red()   { printf '\033[1;31m%s\033[0m\n' "$*"; }
green() { printf '\033[1;32m%s\033[0m\n' "$*"; }
bold()  { printf '\033[1m%s\033[0m\n' "$*"; }

usage() {
    bold "Aegix QEMU Test Launcher"
    echo ""
    echo "Usage:"
    echo "  $(basename "$0")                     Boot latest ISO (UEFI)"
    echo "  $(basename "$0") <iso> [uefi|bios]   Boot specific ISO"
    echo "  $(basename "$0") --installed [mode]   Boot installed disk (no ISO)"
    echo "  $(basename "$0") --reset              Delete test disks"
    echo "  $(basename "$0") --snap NAME          Snapshot test disk (e.g. after base install)"
    echo "  $(basename "$0") --restore NAME       Roll back to a snapshot"
    echo "  $(basename "$0") --snaps               List snapshots"
    echo ""
    bold "Test Checklist (Live Session):"
    echo "  [ ] GRUB menu shows Aegix branding"
    echo "  [ ] Auto-login to root TTY"
    echo "  [ ] aegix-welcome banner displays"
    echo "  [ ] ping 8.8.8.8        (network)"
    echo "  [ ] ping google.com     (DNS)"
    echo "  [ ] /root/install.sh exists"
    echo ""
    bold "Test Checklist (Post-Install — use --installed after installing):"
    echo "  [ ] GRUB shows Aegix branding"
    echo "  [ ] Login as created user"
    echo "  [ ] startx auto-launches on TTY1"
    echo "  [ ] dwm loads with dwmblocks status bar"
    echo "  [ ] Mod+Enter opens st terminal"
    echo "  [ ] Audio: pipewire running (wpctl status)"
    echo "  [ ] Network works"
}

reset_disks() {
    rm -f "$DISK_UEFI" "$DISK_BIOS" "$OVMF_VARS"
    green "Test disks cleaned."
}

ensure_disk() {
    local disk="$1"
    if [ ! -f "$disk" ]; then
        qemu-img create -f qcow2 "$disk" "$DISK_SIZE" >/dev/null 2>&1
        green "Created $DISK_SIZE virtual disk: $disk"
    fi
}

# Handle flags
case "${1:-}" in
    -h|--help)
        usage
        exit 0
        ;;
    --reset)
        reset_disks
        exit 0
        ;;
    --snap)
        # Save a named point-in-time state of the test disk. The intended use is
        # to snapshot right after install.sh finishes the base system but before
        # BARBS runs, so BARBS can be re-run repeatedly without repartitioning
        # and re-basestrapping (minutes -> seconds per iteration).
        [ -n "${2:-}" ] || { echo "usage: $0 --snap NAME" >&2; exit 2; }
        qemu-img snapshot -c "$2" "$DISK_UEFI" && echo "snapshot saved: $2"
        exit 0
        ;;
    --restore)
        [ -n "${2:-}" ] || { echo "usage: $0 --restore NAME" >&2; exit 2; }
        qemu-img snapshot -a "$2" "$DISK_UEFI" && echo "restored to snapshot: $2"
        exit 0
        ;;
    --snaps)
        qemu-img snapshot -l "$DISK_UEFI"
        exit 0
        ;;
esac

# Determine mode and ISO
INSTALLED=false
MODE="uefi"
ISO=""

if [ "${1:-}" = "--installed" ]; then
    INSTALLED=true
    MODE="${2:-uefi}"
elif [ -n "${1:-}" ] && [ -f "${1:-}" ]; then
    ISO="$1"
    MODE="${2:-uefi}"
else
    # Find latest ISO
    ISO=$(ls -t "$ISO_DIR"/*aegix*.iso 2>/dev/null | head -1)
    MODE="${1:-uefi}"
fi

if [ "$INSTALLED" = false ] && { [ -z "$ISO" ] || [ ! -f "$ISO" ]; }; then
    red "No ISO found. Build one first: sudo buildiso -p aegix -i runit"
    exit 1
fi

# Pick disk for this mode
if [ "$MODE" = "uefi" ]; then
    DISK="$DISK_UEFI"
else
    DISK="$DISK_BIOS"
fi

ensure_disk "$DISK"

bold "=== Aegix QEMU Test ==="
if [ "$INSTALLED" = true ]; then
    echo "Mode:    Installed disk ($MODE)"
else
    echo "ISO:     $ISO"
    echo "Mode:    $MODE"
fi
echo "Disk:    $DISK"
echo ""

# Build common QEMU args
# -machine q35: modern chipset, no legacy floppy controller (silences fd0 I/O errors)
ARGS=(
    -enable-kvm
    -machine q35
    -m "$RAM"
    -cpu host
    -smp "$CPUS"
    -drive "file=$DISK,format=qcow2,if=virtio"
    -display gtk
    -device virtio-net-pci,netdev=net0
    -netdev user,id=net0,hostfwd=tcp::2222-:22
)

# Add ISO as cdrom if not booting installed
if [ "$INSTALLED" = false ]; then
    ARGS+=(-cdrom "$ISO" -boot d)
fi

# Launch based on mode
if [ "$MODE" = "uefi" ]; then
    # Fresh OVMF vars for each UEFI session (unless booting installed)
    if [ "$INSTALLED" = false ] || [ ! -f "$OVMF_VARS" ]; then
        cp "$OVMF_VARS_SRC" "$OVMF_VARS"
    fi
    qemu-system-x86_64 \
        "${ARGS[@]}" \
        -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
        -drive if=pflash,format=raw,file="$OVMF_VARS" \
        -vga std
else
    qemu-system-x86_64 \
        "${ARGS[@]}" \
        -vga std
fi

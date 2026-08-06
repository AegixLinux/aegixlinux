#!/bin/bash
# qemu-headless-validate.sh — Boot Aegix ISO in QEMU headless and capture screendumps.
#
# Used for autonomous validation: boots without popping a GTK window on the
# host display, exposes a QEMU monitor socket so we can issue screendump
# commands programmatically, and redirects the guest's serial console to
# a log file.
#
# Usage:
#   ./qemu-headless-validate.sh start   # boot latest ISO headless
#   ./qemu-headless-validate.sh shot LABEL  # capture screen → /tmp/aegix-headless-shots/LABEL.png
#   ./qemu-headless-validate.sh stop    # power off the VM
#   ./qemu-headless-validate.sh reset   # wipe disks + monitor sock + serial log
#
# Files produced:
#   /tmp/aegix-headless.qcow2     – test disk
#   /tmp/aegix-headless.mon       – QEMU monitor unix socket
#   /tmp/aegix-headless.serial    – guest serial console log
#   /tmp/aegix-headless-shots/*.png – screendumps

set -euo pipefail

ISO_DIR="$HOME/artools-workspace/iso/aegix"
OVMF_CODE="/usr/share/edk2-ovmf/x64/OVMF_CODE.4m.fd"
OVMF_VARS_SRC="/usr/share/edk2-ovmf/x64/OVMF_VARS.4m.fd"
OVMF_VARS="/tmp/aegix-headless-ovmf-vars.fd"
DISK="/tmp/aegix-headless.qcow2"
MON="/tmp/aegix-headless.mon"
SERIAL="/tmp/aegix-headless.serial"
PIDFILE="/tmp/aegix-headless.pid"
SHOTDIR="/tmp/aegix-headless-shots"

cmd="${1:-help}"

case "$cmd" in
    start)
        mkdir -p "$SHOTDIR"
        if [ -e "$PIDFILE" ] && kill -0 "$(cat $PIDFILE)" 2>/dev/null; then
            echo "QEMU already running (pid $(cat $PIDFILE)). Use 'stop' first." >&2
            exit 1
        fi
        ISO=$(ls -t "$ISO_DIR"/*aegix*.iso 2>/dev/null | head -1)
        [ -z "$ISO" ] && { echo "No ISO found in $ISO_DIR" >&2; exit 1; }
        [ ! -f "$DISK" ] && qemu-img create -f qcow2 "$DISK" 20G >/dev/null
        cp "$OVMF_VARS_SRC" "$OVMF_VARS"
        rm -f "$MON" "$SERIAL"

        echo "ISO:    $ISO"
        echo "Disk:   $DISK"
        echo "Mon:    $MON"
        echo "Serial: $SERIAL"
        echo "Shots:  $SHOTDIR"

        nohup qemu-system-x86_64 \
            -enable-kvm -machine q35 -m 4096 -cpu host -smp 2 \
            -drive "file=$DISK,format=qcow2,if=virtio" \
            -device virtio-net-pci,netdev=net0 \
            -netdev user,id=net0,hostfwd=tcp::2222-:22 \
            -cdrom "$ISO" -boot d \
            -drive "if=pflash,format=raw,readonly=on,file=$OVMF_CODE" \
            -drive "if=pflash,format=raw,file=$OVMF_VARS" \
            -display none -vga std \
            -monitor "unix:$MON,server,nowait" \
            -serial "file:$SERIAL" \
            >/tmp/aegix-headless.qemu.log 2>&1 &
        echo $! > "$PIDFILE"
        echo "Started QEMU pid $(cat $PIDFILE)"
        ;;
    shot)
        label="${2:-shot-$(date +%H%M%S)}"
        ppm="$SHOTDIR/$label.ppm"
        png="$SHOTDIR/$label.png"
        # screendump needs an absolute path
        echo "screendump $ppm" | socat - UNIX-CONNECT:"$MON" >/dev/null
        # Wait briefly for QEMU to flush the file
        sleep 1
        convert "$ppm" "$png" 2>/dev/null && rm -f "$ppm"
        echo "$png"
        ;;
    stop)
        if [ -e "$MON" ]; then
            echo "system_powerdown" | socat - UNIX-CONNECT:"$MON" >/dev/null 2>&1 || true
            sleep 2
        fi
        if [ -e "$PIDFILE" ]; then
            kill "$(cat $PIDFILE)" 2>/dev/null || true
            rm -f "$PIDFILE"
        fi
        echo "Stopped."
        ;;
    reset)
        if [ -e "$PIDFILE" ] && kill -0 "$(cat $PIDFILE)" 2>/dev/null; then
            kill "$(cat $PIDFILE)" 2>/dev/null || true
        fi
        rm -f "$DISK" "$OVMF_VARS" "$MON" "$SERIAL" "$PIDFILE"
        rm -rf "$SHOTDIR"
        echo "Reset."
        ;;
    serial)
        cat "$SERIAL" 2>/dev/null || echo "(no serial log yet)"
        ;;
    *)
        sed -n '2,18p' "$0"
        ;;
esac

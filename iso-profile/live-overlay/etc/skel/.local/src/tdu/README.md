# tdu - terminal disk usage

An instant, visual answer to "what's eating my space" and "where do
things sit". Run `tdu`, see one row per attached device with a
chunky fill bar, drill into one with a keypress, quit.

The bars are whole-cell blocks in the Aegix st gruvbox colors:
green, then yellow past 70%, red past 90%. No daemon, no curses, no
dependencies beyond libc. The tool only ever reads.

Part of the Aegix Linux suckless-style tool set.

## The overview

    1  aegixluks     / +/home           [################........]  69%  1.2T/1.8T  581G free
    2  nvme0n1p1     /boot              [####....................]  15%  156M/1020M  864M free
    3  aegix-restic  /mnt/aegix-restic  [#######.................]  28%  241G/915G  627G free

One row per real device, instantly (statvfs, no scanning). A device
mounted in several places, as btrfs subvolumes are, shows once:
first mountpoint wins, the rest are listed after it (`/ +/home`).
Narrow terminals drop columns from the right; the bar never drops
below 10 cells.

## The drill-down

Press a row's key and tdu sizes each first-level directory on that
device, ranked, scaled to the largest:

    nvme0n1p1  /boot

      (files)                  [########################]   143M
      grub                     [██......................]    13M

Loose files in the mountpoint root aggregate into `(files)`. The
scan stays on the device (it stops at real mountpoints from the
mount table, so `/proc`, `/tmp` and sibling mounts are never
entered), never follows symlinks, counts hard links once, and skips
unreadable directories silently. A spinner shows progress; `q`
aborts mid-scan.

On btrfs, nested unmounted subvolumes and snapshots ARE descended
into, so their space is visible; shared extents count in full, so
drill-down totals can exceed the device's used figure.

## Usage

    tdu

Keys:

- `1`..`9`, then `a`.. inspect that device (drill-down)
- `r` refresh (or rescan, in the drill-down)
- `q`, Esc, Ctrl-C quit (or back, in the drill-down)

With stdout not a terminal (`tdu | cat`, docs, scripts) it prints
the overview as plain text once and exits; `COLUMNS` sets the
width.

## Numbers

Sizes are binary units, digits truncated, never rounded. Percent
and free match df's convention: used / (used + available-to-you),
so the figures line up with `df -h` within rounding. Drill-down
sizes are allocated blocks, like `du`, so sparse files count small.

## Install

    make clean install

Colors, thresholds, the drill-down's entry count, and the bar
glyphs live in config.h; rebuild after editing.

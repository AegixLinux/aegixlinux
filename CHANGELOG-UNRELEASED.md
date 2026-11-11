<!--
Changes that will ship in the NEXT Aegix ISO, newest at the top.

The contract:
- When a user-visible change lands, add one line here in (or beside) the
  commit that lands it. Write it for a user, not a developer.
- The site renders this file live at aegixlinux.org/#/releases as the
  "In development" section, straight from this branch. No site deploy needed.
- At release time the refresh-aegix-iso skill drains these entries into the
  GitHub release's "What's new" section and empties this file. Entries are
  written once, here, and never again.
- Plumbing (submodule bumps, mirror syncs, capture commits) does not get an
  entry. Site-only changes do not get an entry either: this file is the
  story of the ISO.
-->
- HiDPI displays are detected automatically at login: the new `aegix-dpi`
  tool reads the panel's true DPI, snaps to a sane step (96/120/144/192) and
  applies it as the one scaling knob. `aegix-dpi --info` shows the detection,
  `--set N` pins a value. Leftover Wayland-era scripts are gone from the
  default setup.
- st: zoom in with plain `Ctrl+=` (no shift needed), alongside `Ctrl+-` and
  `Ctrl+0`.
- File open and save dialogs work in apps that use desktop portals (Claude
  Desktop, Electron and Chromium apps): Aegix now ships a portal config for
  dwm and hands the X display to the session bus at login.
- Opening a terminal or starting an app no longer starts an extra D-Bus
  session daemon each time. Login shells inside your session reuse its bus.
- The `hostname` command exists on installed systems: the installer now
  includes `inetutils` (`hostname` plus classic clients like `ftp` and
  `telnet`), which Arch's base package no longer pulls in.

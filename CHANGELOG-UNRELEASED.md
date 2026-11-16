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
- New tool: `tdu`, terminal disk usage. One row per attached device with a
  colored fill bar, press a row's key to drill into what is eating the
  space, `r` rescans, `q` backs out. No dependencies, instant overview.
  Also in the main menu (`Mod+m`) as Disk Usage, right under WiFi. On the
  AUR as `tdu-aegix-git`.
- The `stopwatch` count-up timer is back (it fell out of 20261111) and now
  ships properly: built from source alongside `ttt`, with pause (`p`) and
  splits (Enter). AUR users of `ttt-aegix-git` get it on their next update.

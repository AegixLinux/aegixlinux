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
- Existing installs, upgrade note: if X dies instantly after pulling the
  current dotfiles onto a pre-2026-era install, your old
  `~/.config/shell/profile` is the cause: its PATH line uses zsh-only
  syntax, and the new xprofile sources that file from plain sh. Replace it
  with the current one from gohan (it is a stock file; yours almost
  certainly has no local edits). Found on a real upgrade; fresh installs
  are unaffected.

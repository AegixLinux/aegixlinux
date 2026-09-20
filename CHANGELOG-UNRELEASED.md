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

- st: browser-style zoom keys: `Ctrl+Shift+plus` and `Ctrl+minus` change the
  terminal font size, `Ctrl+0` resets it (the `Alt+Shift+K/J` binds remain).

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
- Airport and hotel WiFi no longer leaves you staring at a timed-out tab:
  wifimenu now probes for a captive portal after every connect, opens the
  login page in your browser and copies its URL to the clipboard. The menu
  gains a "Captive portal check" entry for networks joined via nmtui or
  auto-reconnect, and `wifimenu probe` reports online / portal / offline
  for scripts.
- Markdown is readable without leaving the terminal: `glow` ships by default,
  `md file.md` renders a file in a pager, lf previews `.md` files rendered,
  and neovim renders markdown in the buffer (`,M` toggles it, `,m` opens a
  glow view in a split).

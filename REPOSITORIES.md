# Aegix Linux: repository inventory

Every repository that makes up Aegix, what it is for, and where it is published.
All repositories are on `main`. There are no `master` branches (renamed
2026-08-04); clones and PKGBUILDs follow remote `HEAD`, so nothing pins a
branch name.

## The build system

| Repo | Remote | What it is |
| :-- | :-- | :-- |
| `AEGIX_AGENTIC` | `github.com/timbeach/AEGIX_AGENTIC` | The ISO pipeline: the tracked artools profile (`iso-profile/`), the sync manifests (`sync/`), and the tooling (`tools/`). **This is where ISO work happens.** |

Inside it:

- `iso-profile/` is the complete artools profile, ~275 files, including the
  installed-system skeleton (`live-overlay/etc/skel/`), the installer, and
  BARBS. It is deployed to `/usr/share/artools/iso-profiles/aegix/` to build.
- `sync/` holds three declarative files that drive everything:
  `files.manifest` (what ships), `packages.manifest` (which packages, with
  what mechanism), `sanitize.rules` (rewrites plus the leak gate).
- `tools/` holds `aegix-sync` (live machine to ISO), `build-aegix-iso.sh`,
  `iso-profile-deploy.sh`, `aegix-audit-install.sh`, the QEMU harnesses, and
  the 148-assertion test suite.

## The distro's own source

| Repo | Remote | What it is |
| :-- | :-- | :-- |
| `aegixlinux` (monorepo) | `github.com/AegixLinux/aegixlinux` | Umbrella repo; carries the suckless forks and dotfiles as submodules. |
| `dwm` | `github.com/aegixlinux/dwm` | Window manager. Aegix patches: centered status section, runtime colours for xrdb/pywal, a clickable menu region in the bar. |
| `st` | `github.com/aegixlinux/st` | Terminal. |
| `dmenu` | `github.com/aegixlinux/dmenu` | Launcher. Aegix patch: centered prompt. |
| `dwmblocks` | `github.com/aegixlinux/dwmblocks` | Status bar. Aegix patches: `;;` centre delimiter, async-signal-safe handlers (a real deadlock fix, see `tests/signal-deadlock-test.sh`). |
| `tabbed` | `github.com/AegixLinux/tabbed` | Tabbing container. |
| `nsxiv` | *(not yet published)* | Image viewer fork: key-handler absolute paths, Aegix defaults in `config.def.h`. Local at `~/code/PROJECTS/nsxiv-aegix`. Blocked on the `aegixlinux` GitHub token. |
| `barbs` | submodule of the monorepo | Beach Automation Routine for Building Systems: the post-install program installer. |
| `gohan` | submodule of the monorepo | Dotfiles. **Now a published mirror, not an install source** — since 2026-08-04 the installer seeds `/etc/skel` from the ISO instead. |

The four suckless repos are also checked out at `~/.local/src/<name>` on the
build machine, where they are edited directly. A post-commit hook
(`tools/src-sync-*`) advances the monorepo submodule pointers automatically.

## Companion tools

| Repo | Remote | What it is |
| :-- | :-- | :-- |
| `rushes` | `github.com/timbeach/rushes` | Review raw video captures as a thumbnail grid. Replaced `vidgrid`, which had a bug that overwrote the user's sxiv config on every run. |

## AUR packages

Published under the `timothason` AUR account, maintained from
`AEGIX_AGENTIC/aur/<pkgname>/`. All are `-git` packages that build from the
Aegix forks above and follow remote `HEAD`.

| Package | Builds from |
| :-- | :-- |
| `dwm-aegix-git` | `aegixlinux/dwm` |
| `st-aegix-git` | `aegixlinux/st` |
| `dmenu-aegix-git` | `aegixlinux/dmenu` |
| `dwmblocks-aegix-git` | `aegixlinux/dwmblocks` |
| `st-tabbed-aegix-git` | `AegixLinux/tabbed` |
| `nsxiv-aegix-git` | pending the `aegixlinux/nsxiv` publish |

Workflow: `tools/aur-publish.sh <pkg>` verifies locally (regenerates
`.SRCINFO`, runs `namcap`, builds in a clean sandbox) before you push. Use
`tools/aur-git <pkg> <git args>` so AUR git state stays out of the main repo.

## Website

`aegixlinux.org` serves `install.sh`, `barbs.sh`, `aegix-programs.csv` and the
background images. **These are now a fallback only** — since 2026-08-04 the
installer prefers the copies baked into the ISO, which are guaranteed to match
the ISO's skel and package set. The website copies should still be refreshed
when the ISO's change, for people who run BARBS standalone on an existing
Artix install.

## Where things are *not*

- Nothing about the ISO lives outside `AEGIX_AGENTIC` any more. The old
  `aegix-x11-iso/`, `capture-aegix.sh`, and `verify-sanitize.sh` were retired
  on 2026-08-04.
- `/usr/share/artools/iso-profiles/aegix/` is a **deploy target**, not a
  source. Never edit it directly; it is overwritten with `--delete`.

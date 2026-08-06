# Aegix suckless workflow

How changes flow from your editor to AUR users, on this machine.

## One-minute mental model

**github is your publish point.** Everything else fans out from there:

```
  ~/.local/src/<tool>/          ← you edit + build + test here
           │
           │ git commit
           ▼
  post-commit hook fires (local, no network)
           │
           ├──► ~/code/PROJECTS/AEGIX/<tool>/   ← AEGIX monorepo submodule advances
           └──► ~/code/PROJECTS/AEGIX/          ← parent stages pointer bump
           
           │ git push  (when you're ready to publish)
           ▼
  github.com/aegixlinux/<tool>  ← canonical source of truth for the world
           │
           │ pkgver() auto-resolves on every `yay -Syu`
           ▼
  AUR users get fresh builds of <tool>-aegix-git  ✨
```

You do two manual git operations when you want to publish: **commit** in `~/.local/src/<tool>` and **push** to github. Nothing else is required for AUR users to get your changes.

## Where everything lives

| Path | What it is | Source of truth? |
|---|---|---|
| `~/.local/src/{dwm,st,dmenu,dwmblocks}` | Your working copies. Edit configs, run `sudo make clean install`, commit here. | **Yes** (this is it) |
| `~/code/PROJECTS/AEGIX/{dwm,st,dmenu,dwmblocks}` | Submodules of the AEGIX monorepo. Auto-synced from live via the src-sync post-commit hook. **Do not edit directly** — next sync will clobber. | No (downstream) |
| `~/code/PROJECTS/AEGIX` | The AEGIX monorepo. Pins each submodule to a specific commit. | No (downstream) |
| `github.com/aegixlinux/{dwm,st,dmenu,dwmblocks}` | Where the world fetches your code. AUR packages pull from here. | Published copy |
| `~/AEGIX_AGENTIC/aur/<pkgname>-aegix-git` | AUR PKGBUILDs. Rarely touched. | Local PKGBUILD source |
| `aur.archlinux.org/packages/<pkgname>-aegix-git` | The AUR package itself. Receives PKGBUILD changes only, not source changes. | Published PKGBUILD |

## Daily workflow

### The common case — tweaking config.h or patching a source file

```bash
# 1. Edit
vim ~/.local/src/dwm/config.h

# 2. Rebuild + test live
cd ~/.local/src/dwm
sudo make clean install

# 3. Commit when you're happy
git commit -am "feat: new keybinding for foo"
```

At step 3, **this happens automatically**, without network:

- `~/code/PROJECTS/AEGIX/dwm` fast-forwards to your new commit.
- `~/code/PROJECTS/AEGIX` gets the submodule pointer bump staged.
- A line is written to `~/.local/state/aegix-src-sync.log`.

You'll see a message like:
```
[aegix-src-sync] dwm: 7e7400d → a1b2c3d, pointer staged in AEGIX parent
```

### Publishing (when you're ready for AUR users to see it)

```bash
cd ~/.local/src/dwm
git push origin master
```

That's it. **One command**, reaches github, `-git` PKGBUILD auto-resolves next time anyone runs `yay -Syu`.

You can batch several commits before pushing if you want — nothing requires pushing after every commit.

### Committing the AEGIX monorepo pointer bumps

Whenever the AEGIX parent's staged bumps accumulate to something worth recording (e.g. "I finished the gaps feature across dwm + dmenu"):

```bash
cd ~/code/PROJECTS/AEGIX
git status           # see which submodules are staged
git commit -m "Bump suckless pins for gaps feature"
```

You push this up to github/AEGIX when you want — totally orthogonal to the per-tool flow. The monorepo is for your own project history and ISO builds; AUR users don't care about it.

## What the automation does NOT do

- **Does not push** `~/.local/src/<tool>` to github on commit. Network action stays manual.
- **Does not auto-commit** the AEGIX parent's pointer bumps. Staging only — you batch them.
- **Does not mirror** WIP/uncommitted edits between `~/.local/src/<tool>` and `~/code/PROJECTS/AEGIX/<tool>`. Only committed changes propagate.
- **Does not touch AUR** during the normal flow. AUR stays frozen until you edit a PKGBUILD (rare).

## When do I touch the AUR package repo?

Almost never. Only when the **PKGBUILD itself** needs to change:

- Adding a new build dep (a new library you've started linking against)
- Fixing a `prepare()` step (like the `tic` workaround in `st-aegix-git` or the `PREFIX` sed in `dwmblocks-aegix-git`)
- Editing the package description or license line

For those cases:

```bash
vim ~/AEGIX_AGENTIC/aur/dwm-aegix-git/PKGBUILD

~/AEGIX_AGENTIC/tools/aur-publish.sh dwm-aegix-git
# runs: srcinfo regen, namcap lint, clean-sandbox makepkg test
# exits green if fine, loud if broken

~/AEGIX_AGENTIC/tools/aur-git dwm-aegix-git add PKGBUILD .SRCINFO
~/AEGIX_AGENTIC/tools/aur-git dwm-aegix-git commit -m "Add libxcb dep"
~/AEGIX_AGENTIC/tools/aur-git dwm-aegix-git push
```

That's it. The AUR web UI updates within seconds.

## Troubleshooting

### "I committed but nothing happened in AEGIX/"
Check the log: `tail -5 ~/.local/state/aegix-src-sync.log`

Common causes:
- Branch isn't `master` → hook skips with `SKIP branch=<name>`
- AEGIX submodule is on some other branch → hook logs `WARN`
- AEGIX/`<tool>` has dirty WIP → hook saves a backup patch to `~/AEGIX_AGENTIC/tools/backups/<tool>-aegix-wip-<timestamp>.patch` before resetting

If the hook bailed for any reason, manual recovery:
```bash
~/AEGIX_AGENTIC/tools/sync-one.sh <tool>
```

### "AUR users aren't seeing my recent commit"
You probably haven't pushed to github yet. `yay -Syu` fetches github, not your local `.git`.
```bash
cd ~/.local/src/<tool>
git log --oneline origin/master..HEAD     # shows local commits not on github
git push origin master
```

### "I need to verify an AUR package still builds"
```bash
~/AEGIX_AGENTIC/tools/aur-publish.sh <pkgname>-aegix-git
```
Runs the full verify pipeline (srcinfo regen, namcap, clean-sandbox makepkg). No push, no install.

## References

- **Spec:** `docs/superpowers/specs/2026-04-21-aegix-src-sync-design.md` (original sync design)
- **Updated spec:** `docs/superpowers/specs/2026-04-22-aegix-src-sync-local-only-design.md` (no-push revision)
- **AUR spec:** `docs/superpowers/specs/2026-04-23-aegix-aur-publishing-design.md`
- **AUR workspace:** `aur/README.md`
- **Tests:** `tools/tests/test-src-sync.sh` (28 asserts)
- **Smoke checks:** `tools/TESTING.md`

# aegix AUR packages

This directory contains the PKGBUILDs for the four Aegix suckless packages
published on the AUR:

- `dwm-aegix-git` — https://aur.archlinux.org/packages/dwm-aegix-git
- `st-aegix-git` — https://aur.archlinux.org/packages/st-aegix-git
- `dmenu-aegix-git` — https://aur.archlinux.org/packages/dmenu-aegix-git
- `dwmblocks-aegix-git` — https://aur.archlinux.org/packages/dwmblocks-aegix-git

AUR account: **timothason** (dedicated SSH key at `~/.ssh/id_ed25519_aur`,
routed to `aur.archlinux.org` via `~/.ssh/config`). Commits are GPG-signed
with key `0D46FA83EADB2394` (Timothy Beach).

## Layout

```
aur/
├── README.md               (this file)
├── .gitignore              (ignores .aur-git/ + build artifacts)
├── .aur-git/               (each package's isolated AUR git state — NOT tracked)
│   ├── dwm-aegix-git/      (real .git dir for aur/dwm-aegix-git/)
│   ├── st-aegix-git/
│   ├── dmenu-aegix-git/
│   └── dwmblocks-aegix-git/
├── dwm-aegix-git/          (work tree — PKGBUILD + .SRCINFO tracked by parent)
│   ├── .gitignore
│   ├── PKGBUILD
│   └── .SRCINFO
├── st-aegix-git/
├── dmenu-aegix-git/
└── dwmblocks-aegix-git/
```

Each package's `.git` is held outside its work tree so the parent
AEGIX_AGENTIC repo can track the PKGBUILDs as regular files. Git commands
against the AUR-side state go through the `aur-git` wrapper.

## Day-to-day: nothing

These are `-git` packages — `pkgver()` auto-computes from github HEAD.
Users running `yay -Syu` pick up new commits automatically from
`github.com/aegixlinux/<repo>/master`. You don't need to touch the
PKGBUILDs when config.h changes.

## When a PKGBUILD change is needed

(new dep, new `prepare()` step, description edit, license fix, etc.)

```bash
# 1. Edit the PKGBUILD
vim ~/AEGIX_AGENTIC/aur/<pkgname>/PKGBUILD

# 2. Verify locally (regenerate .SRCINFO, namcap, clean-sandbox build)
~/AEGIX_AGENTIC/tools/aur-publish.sh <pkgname>

# 3. Commit + push to AUR (via the aur-git wrapper)
~/AEGIX_AGENTIC/tools/aur-git <pkgname> add PKGBUILD .SRCINFO
~/AEGIX_AGENTIC/tools/aur-git <pkgname> commit -m 'Bump deps'
~/AEGIX_AGENTIC/tools/aur-git <pkgname> push

# 4. Commit to the parent AEGIX_AGENTIC repo too (for the local audit trail)
cd ~/AEGIX_AGENTIC
git add aur/<pkgname>/PKGBUILD aur/<pkgname>/.SRCINFO
git commit -m 'chore(aur): bump <pkgname> PKGBUILD'
```

## Adding a 5th package later

1. Create the work tree: `mkdir -p ~/AEGIX_AGENTIC/aur/<newpkg>`
2. Write `PKGBUILD` + a `.gitignore` that excludes the source clone dir
   (typically `/<_pkgname>/` where `_pkgname` matches the source var)
3. Verify: `~/AEGIX_AGENTIC/tools/aur-publish.sh <newpkg>`
4. Init the AUR-side git state:

   ```bash
   mkdir -p ~/AEGIX_AGENTIC/aur/.aur-git/<newpkg>
   git --git-dir=~/AEGIX_AGENTIC/aur/.aur-git/<newpkg> \
       --work-tree=~/AEGIX_AGENTIC/aur/<newpkg> \
       init -q -b master
   git --git-dir=~/AEGIX_AGENTIC/aur/.aur-git/<newpkg> \
       config core.worktree "$HOME/AEGIX_AGENTIC/aur/<newpkg>"
   git --git-dir=~/AEGIX_AGENTIC/aur/.aur-git/<newpkg> \
       remote add origin ssh://aur@aur.archlinux.org/<newpkg>.git
   ```
5. Push initial import:

   ```bash
   ~/AEGIX_AGENTIC/tools/aur-git <newpkg> add PKGBUILD .SRCINFO
   ~/AEGIX_AGENTIC/tools/aur-git <newpkg> commit -m "Initial import of <newpkg>"
   ~/AEGIX_AGENTIC/tools/aur-git <newpkg> push -u origin master
   ```

## References

- Spec: `../docs/superpowers/specs/2026-04-23-aegix-aur-publishing-design.md`
- Plan: `../docs/superpowers/plans/2026-04-23-aegix-aur-publishing.md`
- Helpers: `../tools/aur-publish.sh`, `../tools/aur-git`

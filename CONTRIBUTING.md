# Working on Aegix Linux

Aegix is an Artix-based, X11 + suckless distribution: dwm, st, dmenu,
dwmblocks, runit, mandatory full-disk encryption. This document is the
onboarding path for anyone joining, human or agent.

Start with [REPOSITORIES.md](REPOSITORIES.md) for the map of what lives where.

## The one idea that explains the whole project

**The ISO follows a real, running machine.**

Aegix is not assembled by hand. There is a maintainer's daily-driver machine,
and a pipeline that captures it into the ISO: sanitizing personal data,
blocking leaks, and remembering a decision for every file and package so
nothing drifts in silently. When the maintainer improves their setup, the
distro inherits it on the next sync.

That means: **you do not edit the ISO's dotfiles directly.** You change the
live system, then sync. The pipeline is the only path in.

```
live machine  --capture-->  sanitize  -->  verify gate  -->  git  -->  deploy  -->  ISO
                                              (blocks leaks)
```

## Getting set up

You need an Artix or Arch machine (Aegix itself is ideal).

```sh
git clone git@github.com:timbeach/AEGIX_AGENTIC.git
cd AEGIX_AGENTIC
sudo pacman -S --needed artools qemu-base edk2-ovmf rsync git
tools/tests/test-aegix-sync.sh        # 148 assertions; must pass before you start
```

The test suite runs entirely against fixtures in `mktemp` directories. It never
touches your real home directory or `/usr/share`. If it passes, your checkout
is sane.

## The everyday loop

```sh
tools/aegix-sync --status      # what has drifted from the live machine? (read-only)
tools/aegix-sync --dry-run     # full pipeline, stops before committing
tools/aegix-sync               # capture, sanitize, verify, triage, commit, deploy
tools/build-aegix-iso.sh       # build the ISO (names it aegix-<date>-x86_64.iso)
tools/qemu-test-aegix.sh       # boot it
```

`aegix-sync` will stop and ask you about anything new it finds on the live
machine: ship it, never ship it, or decide later. Your answer is recorded in
`sync/files.manifest` or `sync/packages.manifest` and never asked again.

### The manifests

- **`sync/files.manifest`** — one decision per path, relative to `$HOME`.
  `ship` (capture it, live wins, deletions propagate), `never` (silently
  ignored forever), `iso` (exists only in git; capture never overwrites it),
  `watch` (a directory to scan for undecided items). Longest matching pattern
  wins.
- **`sync/packages.manifest`** — one line per package with a tag set:
  `rootfs` (in the live ISO), `barbs` (installed post-install by pacman),
  `aur` (installed by yay), `git <url>` (cloned and `make`d), `never`
  (personal, never ships). `profile.yaml` and `aegix-programs.csv` are both
  *generated* from this file, so they cannot contradict each other.
- **`sync/sanitize.rules`** — `sub`/`strip-line`/`strip-block` rewrites, and
  `forbid`/`allow` assertions for the leak gate. Comments in this file are
  **full-line only**, because rules legitimately contain `#`.

### The leak gate

`verify_tree` runs every `forbid` rule over the entire staged profile before
anything is committed. **There is no bypass flag and there never will be.** If
it blocks you, the fix is one of:

1. Wrap the personal part in a `# ===== PERSONAL: DO NOT SYNC TO AEGIX =====`
   fence, which is stripped on capture.
2. Mark the file `never` in `files.manifest`.
3. Add a rule, if you have found a genuinely new class of leak.

Allow rules are match-scoped: they suppress only the exact substring a forbid
matched, so an allowlisted placeholder can never blind an unrelated secret on
the same line. Binary files fail hard on any forbid match, with no allow
narrowing, because a secret compiled into a binary is never legitimate.

## Testing changes

Never trust "it works on the build machine": that assumption has produced most
of this project's real bugs. A locale was set but never generated, so rofi died
on every install while working perfectly here. Users were created without the
`video` group, so brightness silently required root. Both looked fine locally.

```sh
tools/qemu-test-aegix.sh --snap base-installed   # after base install, before BARBS
tools/qemu-test-aegix.sh --restore base-installed # re-run BARBS in seconds
tools/aegix-audit-install.sh <host>               # diff a real install vs this machine
```

`aegix-audit-install.sh` is the highest-value check before shipping an ISO. It
compares an installed system against the shipped profile: per-file checksums,
whether every command dwm spawns resolves, group membership, passwordless
sudo, **locales referenced but not generated**, promised packages, services,
and suckless build IDs.

Every ISO stamps `/etc/aegix-release` with its version, the profile commit, and
whether the tree was clean. Any bug report should start with that file.

## Notes for agents

If you are an AI agent working on this repo, the constraints that matter:

- **`/usr/share/artools/iso-profiles/aegix/` is a deploy target.** Never edit
  it, never `rsync --delete` into it by hand. It was destroyed exactly once
  this way, by a well-meaning adversarial test of the deploy script; recovery
  took a btrfs snapshot. `tools/iso-profile-deploy.sh` now requires `--prod`
  explicitly, refuses an empty or dirty source, and gates mass deletions.
- **Never run `install.sh` unattended**, in QEMU or anywhere. Destructive
  installer flows are driven by a human, always.
- **Fix the pipeline, not the artifact.** If the ISO is wrong, the manifest or
  a tool is wrong. Editing the deployed profile by hand produces a fix that
  vanishes on the next sync.
- **Timestamps lie; build IDs do not.** `cp -f` preserves inodes, `make` skips
  targets that look newer than their sources, and committed `.o` files have
  silently shipped stale binaries here before. Compare build IDs and content
  hashes.
- **Prove a negative before believing it.** When a keybinding "does nothing",
  validate your test harness against a binding that does work, then wrap the
  spawned command in a tracer. The Mod+M bug looked like a missing file, then
  a stale binary, and was actually rofi dying on an ungenerated locale.
- Reports and design docs live in `docs/superpowers/{specs,plans}/`; session
  records are the `STATUS-*.md` files at the repo root.

## Contributing back

1. Branch from `main`.
2. Make the change in the right place: a suckless patch goes in that fork; a
   dotfile or script change goes on the live machine and comes in via
   `aegix-sync`; pipeline and installer changes go here.
3. `tools/tests/test-aegix-sync.sh` must pass. New behaviour needs a new
   assertion, and it should fail before your fix and pass after it.
4. Verify in QEMU, and on hardware when the change touches hardware.
5. Open a pull request describing what you tested, not just what you changed.

Questions, and the wider project: <https://aegixlinux.org>

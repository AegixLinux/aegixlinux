# Contributing to Aegix Linux

Aegix is an Artix-based, X11 + suckless distribution: dwm, st, dmenu,
dwmblocks, runit, and mandatory full-disk encryption. See
[REPOSITORIES.md](REPOSITORIES.md) for the map of what lives where.

## Read this first: how Aegix is built

Aegix is a **curated** distribution. There is a maintainer's daily-driver
machine, and a pipeline (`tools/aegix-sync`) that captures it into the ISO:
sanitizing personal data, blocking leaks with a hard gate, and recording a
decision for every file and package so nothing drifts in silently.

```
maintainer's machine --capture--> sanitize --> leak gate --> git --> ISO
```

That means **running the sync is inherently the maintainer's job** — it reads
from a machine only they have. This is not a wall put up to keep you out; it
is just what the tool does. Everything *downstream* of that capture is open,
and that is most of the distro.

If you have used projects where "contributing" means "reproduce the
maintainer's environment first", the good news is that Aegix asks the
opposite: you contribute by running the shipped artifact and improving the
things that are plain code.

## What you can work on

### 1. The suckless forks

Ordinary repositories, ordinary pull requests, no Aegix machine involved.

- [dwm](https://github.com/aegixlinux/dwm) · [st](https://github.com/aegixlinux/st) · [dmenu](https://github.com/aegixlinux/dmenu) · [dwmblocks](https://github.com/aegixlinux/dwmblocks) · [tabbed](https://github.com/AegixLinux/tabbed)

Build and test them the normal way (`make && sudo make install`). If you touch
signal handling, concurrency, or anything with a failure that only appears
under load, please include a regression test: `dwmblocks` has one at
`tests/signal-deadlock-test.sh` that is a reasonable model.

### 2. The installer and BARBS

`iso-profile/live-overlay/root/install.sh` and `barbs.sh` are plain shell
scripts. You can test both in a VM without any Aegix hardware:

```sh
tools/qemu-test-aegix.sh                       # boot the ISO
# install to the throwaway disk, then:
tools/qemu-test-aegix.sh --snap base-installed # snapshot before BARBS
tools/qemu-test-aegix.sh --restore base-installed
```

The snapshot turns a 40-minute install loop into a 2-minute one, which makes
installer work genuinely pleasant. The VM's only disk is a file in `/tmp`;
nothing can reach your real drives.

### 3. Install on your own hardware and report what the audit finds

This is the single most valuable thing an outside contributor can do, and it
needs nothing but a spare machine and a USB stick.

```sh
tools/aegix-audit-install.sh <host-or-ip>
```

It compares a real installed system against the shipped profile: per-file
checksums, whether every command dwm spawns resolves on `PATH`, group
membership, passwordless sudo, locales referenced but never generated,
promised packages, services, and suckless build IDs.

**Different hardware finds different bugs.** Recent examples, all found this
way and invisible on the maintainer's machine: a locale set but never
generated (killed rofi on every install), users created without the `video`
group (brightness silently needed root), and an rsync exclude that dropped
every `README.md` from the ISO. Your laptop's wifi chipset, GPU, and firmware
quirks are things no amount of local testing here can substitute for.

Include `/etc/aegix-release` in any report: it names the exact ISO build and
profile commit your system came from.

### 4. The tooling itself

`tools/` is where the pipeline lives, and it is all testable:

```sh
tools/tests/test-aegix-sync.sh     # 151 assertions, fixture-isolated
```

The suite runs entirely against `mktemp` fixtures — it never touches a real
home directory or `/usr/share`. New behaviour needs a new assertion, and that
assertion should fail before your change and pass after it.

### 5. Propose manifest decisions

You cannot run the capture, but you can propose what it should decide. The
three files in `sync/` are readable and reviewable:

- `files.manifest` — what ships (`ship`/`never`/`iso`/`watch`, longest match wins)
- `packages.manifest` — which packages and by what mechanism (`rootfs`,
  `barbs`, `aur`, `git <url>`, `never`); `profile.yaml` and
  `aegix-programs.csv` are both *generated* from it, so they cannot disagree
- `sanitize.rules` — rewrites plus the `forbid`/`allow` leak gate

"This package should be `aur`, not `barbs`, because it is not in the repos" is
a perfectly good pull request. So is a new `forbid` rule for a class of
personal data we are not catching yet.

## The leak gate

Every sync runs every `forbid` rule over the whole staged profile before
anything is committed. **There is no bypass flag, and adding one will not be
accepted.** If it blocks something, the legitimate fixes are:

1. Fence the personal part (`# ===== PERSONAL: DO NOT SYNC TO AEGIX =====`),
   which capture strips.
2. Mark the path `never` in `files.manifest`.
3. Add a rule, if you have found a genuinely new class of leak.

Allow rules are match-scoped: they suppress only the substring a forbid
matched, so an allowlisted placeholder can never blind an unrelated secret on
the same line. Binary files fail hard on any match, with no allow narrowing,
because a secret compiled into a binary is never intentional.

This matters more than it sounds. The gate has caught real leaks on their way
into a public ISO, including a script that would have synced a new user's
password store to the maintainer's server.

## Notes for AI agents

If you are an agent working in this repository, these constraints are load
bearing:

- **`/usr/share/artools/iso-profiles/aegix/` is a deploy target, not a
  source.** Never edit it, never `rsync --delete` into it by hand. It was
  destroyed exactly once that way, by an adversarial test of the deploy
  script; recovery needed a btrfs snapshot. `tools/iso-profile-deploy.sh` now
  requires `--prod`, refuses an empty or dirty source, and gates mass deletes.
- **Never run `install.sh` unattended**, in a VM or anywhere. Destructive
  installer flows are driven by a human.
- **Fix the pipeline, not the artifact.** If the ISO is wrong, a manifest or a
  tool is wrong. Hand-editing the deployed profile produces a fix that
  disappears at the next sync.
- **Timestamps lie; build IDs do not.** `cp -f` preserves inodes, `make` skips
  targets that look newer than their sources, and committed object files have
  shipped stale binaries here before. Compare build IDs and content hashes.
- **Verify the artifact, not your intent.** Three separate bugs here were
  found only by mounting the built ISO and looking. A green pipeline is not
  evidence that the right bytes shipped.
- **Prove a negative before believing it.** When something "does nothing",
  validate your test harness against a case that does work, then instrument
  the thing itself. A dead keybinding looked like a missing file, then a stale
  binary, and was actually rofi exiting on an ungenerated locale.

## Submitting

1. Branch from `main`. (There are no `master` branches anywhere in Aegix.)
2. `tools/tests/test-aegix-sync.sh` must pass.
3. Verify in QEMU; verify on hardware when the change touches hardware.
4. Describe **what you tested**, not only what you changed.

Project home: <https://aegixlinux.org>

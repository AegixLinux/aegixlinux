# aegix-src-sync — Manual Smoke Checks

Run these once per repo, after `bootstrap-src-sync.sh` has reconciled and
`install-src-sync.sh` has installed the hook.

## 1. Happy path (start with dwmblocks — smallest stakes)

```bash
cd ~/.local/src/dwmblocks
# make a trivial no-op change
echo "# smoke test $(date -u +%FT%TZ)" >> README.md
git add README.md
git commit -m "test: smoke"
```

Expected within ~2 seconds:
- Terminal shows: `[aegix-src-sync] dwmblocks: <old> → <new>, pointer staged in AEGIX parent`
- `git -C ~/code/PROJECTS/AEGIX status` shows `modified: dwmblocks`
- Last line of `~/.local/state/aegix-src-sync.log` is `... dwmblocks OK ...`

## 2. Feature branch is skipped

```bash
cd ~/.local/src/st
git checkout -b smoke/feature
echo "feature test" >> README.md
git add README.md
git commit -m "test: feature-branch smoke"
```

Expected:
- Terminal shows: `[aegix-src-sync] st: skipped (branch=smoke/feature)`
- `git -C ~/code/PROJECTS/AEGIX status` shows no change for `st`
- Log line ends with `SKIP  branch=smoke/feature (not master)`

Clean up:
```bash
git checkout master
git branch -D smoke/feature
```

## 3. Manual recovery

Simulate a push failure by temporarily breaking the remote:

```bash
cd ~/.local/src/dwm
ORIG_URL="$(git remote get-url origin)"
git remote set-url origin git@github.com:aegixlinux/definitely-not-a-repo.git
echo "recovery test" >> README.md
git add README.md
git commit -m "test: recovery"
# expect: [aegix-src-sync] dwm: push failed; AEGIX untouched

# Fix the remote and recover
git remote set-url origin "$ORIG_URL"
~/code/PROJECTS/AEGIX/tools/sync-one.sh dwm
# expect: [aegix-src-sync] dwm: <old> → <new>, pointer staged in AEGIX parent
```

## 4. Inspect the log

```bash
tail -20 ~/.local/state/aegix-src-sync.log
```

Each line: `<utc timestamp>  <repo>  <OK|WARN|SKIP>  <detail>`.

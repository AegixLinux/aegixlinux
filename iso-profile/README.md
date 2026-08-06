# iso-profile

`iso-profile/` is the **canonical full ISO profile** — every file the
artools build reads from `/usr/share/artools/iso-profiles/aegix/`
(system path, not under git control) is tracked here, generated and
kept in sync by `tools/aegix-sync` (not hand-edited piecemeal).

## Layout

```
iso-profile/
├── live-overlay/        mirrors /usr/share/artools/iso-profiles/aegix/live-overlay/
│   ├── etc/...
│   ├── root/.bash_profile
│   └── usr/...
├── root-overlay/        mirrors the profile's root-overlay/
└── profile.yaml          generated package/service list
```

## The `sync/` inputs

Three files under `sync/` (repo root) drive generation — edit these,
not the generated output:

- **`sync/files.manifest`** — which live-system paths get captured into
  `iso-profile/live-overlay/`, and how (verbatim, sanitized, skip).
- **`sync/packages.manifest`** — the package list reconciled into
  `iso-profile/profile.yaml`.
- **`sync/sanitize.rules`** — redaction rules (hostnames, usernames,
  keys, IPs) applied to captured files before they land here.

## Refreshing this directory: `tools/aegix-sync`

```sh
tools/aegix-sync --status   # drift nag — what's changed live vs. this dir, no writes
tools/aegix-sync            # full run: capture -> sanitize -> triage -> generate -> verify -> review -> commit -> deploy
```

Phases, in order: **preflight** (git tree must be clean under
`iso-profile/`/`sync/`) -> **capture** (pull live-system state per
`files.manifest`) -> **sanitize** (apply `sanitize.rules`) ->
**triage** (surface new/changed/removed files for review) ->
**generate** (write `profile.yaml` + overlays) -> **verify** (forbid/
allow gate — refuses to proceed if a rule fails) -> **review** (you
approve) -> **commit** (git commit in this repo) -> **deploy**
(`tools/iso-profile-deploy.sh --prod`, which requires `--prod` for a
production write and gates any mass-delete).

Supersedes the old `tools/capture-aegix.sh` / `tools/verify-sanitize.sh`
pair — see `docs/superpowers/specs/2026-07-28-aegix-live-to-iso-sync-design.md`
for the full design and back-story.

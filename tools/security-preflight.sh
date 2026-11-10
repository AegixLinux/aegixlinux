#!/usr/bin/env bash
# security-preflight.sh: gate an ISO build on known, fixable vulnerabilities.
#
# Resolves the full package set the ISO will ship (common.yaml + the aegix
# profile.yaml, runit init only, plus every dependency) against FRESH repo
# databases synced into a temp dir (no sudo, host db untouched), then checks
# it against the Arch Linux security tracker (security.archlinux.org).
#
#   FAIL  an ISO package is older than the tracker's fixed version
#         (High/Critical): the repos have not picked up the fix yet, so a
#         build now would ship a known-fixable hole. Wait or pin a mirror.
#   WARN  same, Medium/Low severity.
#   OPEN  a vulnerability with no fixed version anywhere yet: listed so the
#         release notes can be honest; never blocks, nothing newer exists.
#   HOST  the build machine itself is behind its repos or running an older
#         kernel than installed. Does not affect the ISO content.
#
# Usage: tools/security-preflight.sh [--report FILE]
# Exit:  0 clean or warnings only, 1 at least one FAIL, 2 tool error.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROFILE="$ROOT/iso-profile/profile.yaml"
COMMON="${ARTOOLS_COMMON:-/usr/share/artools/iso-profiles/common/common.yaml}"
TRACKER_URL="https://security.archlinux.org/all.json"
REPORT=""
[ "${1:-}" = "--report" ] && REPORT="${2:?--report needs a file}"

for c in pacman fakeroot vercmp curl python3; do
    command -v "$c" >/dev/null || { echo "missing required command: $c" >&2; exit 2; }
done
[ -r "$PROFILE" ] || { echo "profile not found: $PROFILE" >&2; exit 2; }
[ -r "$COMMON" ]  || { echo "artools common.yaml not found: $COMMON" >&2; exit 2; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/db/local" "$TMP/hostdb"

echo "==> Syncing fresh package databases (temp dir, no sudo)"
fakeroot -- pacman -Sy --disable-sandbox --dbpath "$TMP/db" --logfile /dev/null >/dev/null 2>"$TMP/sync.err" \
    || { cat "$TMP/sync.err" >&2; exit 2; }

echo "==> Fetching security tracker"
curl -fsSL --retry 3 "$TRACKER_URL" -o "$TMP/tracker.json" || { echo "tracker download failed" >&2; exit 2; }

# Profile package names: '- name' items, skipping init systems other than runit.
profile_pkgs() {
    awk '
        /^[^ #-][^:]*:/ { init = "" }
        /^[ ]+(openrc|s6|dinit|suite66|runit):[ ]*$/ { gsub(/[ :]/, ""); init = $0; next }
        /^[ ]+services:[ ]*$/ { skip = 1; next }
        /^[ ]*[A-Za-z_-]+:/ { skip = 0 }
        /^[ ]*- / { if (!skip && (init == "" || init == "runit")) { sub(/^[ ]*- /, ""); sub(/[ #].*/, ""); print } }
    ' "$@" | sort -u
}
pacman -Sl --dbpath "$TMP/db" | awk '{print $2}' | sort -u > "$TMP/available"
profile_pkgs "$COMMON" "$PROFILE" > "$TMP/wanted"
comm -23 "$TMP/wanted" "$TMP/available" > "$TMP/missing"
comm -12 "$TMP/wanted" "$TMP/available" > "$TMP/targets"

echo "==> Resolving the ISO package set"
# Empty local db => pacman prints the full dependency closure.
pacman -Sp --dbpath "$TMP/db" --print-format '%n %v' --noconfirm $(cat "$TMP/targets") \
    > "$TMP/iso-set" 2>"$TMP/resolve.err" || { cat "$TMP/resolve.err" >&2; exit 2; }

# Host drift: compare the real local db against the fresh sync dbs.
ln -s /var/lib/pacman/local "$TMP/hostdb/local"
ln -s "$TMP/db/sync" "$TMP/hostdb/sync"
pacman -Qu --dbpath "$TMP/hostdb" 2>/dev/null > "$TMP/host-behind" || true
running="$(uname -r)"
installed_kernel="$(pacman -Q linux 2>/dev/null | awk '{print $2}' | sed 's/\.artix/-artix/')"

python3 -I - "$TMP/tracker.json" "$TMP/iso-set" "$TMP/host-behind" "$TMP/missing" \
    "$running" "$installed_kernel" "${REPORT:-/dev/null}" <<'PY'
import json, subprocess, sys
tracker, iso_set, host_behind, missing, running, inst_kernel, report = sys.argv[1:]

iso = dict(line.split() for line in open(iso_set) if line.strip())
rank = {"Critical": 4, "High": 3, "Medium": 2, "Low": 1, "Unknown": 0}
def older(a, b):
    return int(subprocess.run(["vercmp", a, b], capture_output=True, text=True).stdout) < 0

fails, warns, opens = [], [], []
for g in json.load(open(tracker)):
    if g["status"] in ("Not affected", "Invalid"):
        continue
    for pkg in g["packages"]:
        if pkg not in iso:
            continue
        have, fixed, sev = iso[pkg], g.get("fixed"), g.get("severity", "Unknown")
        cves = ",".join(g.get("issues", [])[:4]) + ("..." if len(g.get("issues", [])) > 4 else "")
        if fixed:
            if older(have, fixed):
                row = f"{pkg:<22} {have:<26} fixed in {fixed:<22} [{sev}] {g['name']} {cves}"
                (fails if rank.get(sev, 0) >= 3 else warns).append((rank.get(sev, 0), row))
        elif g["status"] == "Vulnerable":
            opens.append((rank.get(sev, 0), f"{pkg:<22} {have:<26} no fix yet [{sev}] {g['name']} {cves}"))

host = [l.strip() for l in open(host_behind) if l.strip()]
miss = [l.strip() for l in open(missing) if l.strip()]
out = []
p = out.append
p(f"ISO package set: {len(iso)} packages (fresh repo dbs)")
p(f"Profile entries not in any repo (skipped by buildiso too): {', '.join(miss) or 'none'}")
for title, rows in (("FAIL (fixable High/Critical, repo still behind)", fails),
                    ("WARN (fixable Medium/Low, repo still behind)", warns),
                    ("OPEN (tracker lists no fix; many are stale tracker entries; informational)", opens)):
    p(f"\n{title}: {len(rows)}")
    for _, r in sorted(rows, reverse=True):
        p(f"  {r}")
p(f"\nHOST packages behind repos: {len(host)}")
for h in host[:30]:
    p(f"  {h}")
if inst_kernel and inst_kernel.replace("-", ".") not in running.replace("-", "."):
    p(f"HOST kernel: running {running}, installed {inst_kernel}: reboot the build host")
else:
    p(f"HOST kernel: running {running} (matches installed)")
p("\nRESULT: " + ("FAIL" if fails else "PASS"))
text = "\n".join(out)
print(text)
if report != "/dev/null":
    open(report, "w").write(text + "\n")
sys.exit(1 if fails else 0)
PY

#!/usr/bin/env bash
# security-preflight.sh: gate an ISO build on buildability and known,
# fixable vulnerabilities, in seconds instead of minutes into buildiso.
#
# Resolves the package set exactly as buildiso does: artools' own
# load_profile/load_pkgs (common.yaml + profile.yaml, runit) for the rootfs,
# livefs and bootfs stages, against freshly synced databases built from
# buildiso's own pacman config (iso-<arch>.conf, Artix repos only), in a temp
# dir with no sudo. The repo's iso-profile/ is checked (not the deployed
# copy), so it can run before deploying. Then the full dependency closure is
# checked against the Arch Linux security tracker.
#
#   BREAK a profile package is not in buildiso's repos: the build WILL fail
#         in make_rootfs ("target not found"). Fix the profile.
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
# Exit:  0 clean or warnings only, 1 at least one BREAK or FAIL, 2 tool error.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DATADIR="${DATADIR:-/usr/share/artools}"
INITSYS=runit
ARCH="$(uname -m)"
STABILITY="${STABILITY:-stable}"
TRACKER_URL="https://security.archlinux.org/all.json"
REPORT=""
[ "${1:-}" = "--report" ] && REPORT="${2:?--report needs a file}"

for c in pacman fakeroot vercmp curl python3 yq; do
    command -v "$c" >/dev/null || { echo "missing required command: $c" >&2; exit 2; }
done
[ -r "$ROOT/iso-profile/profile.yaml" ] || { echo "profile not found: $ROOT/iso-profile/profile.yaml" >&2; exit 2; }
[ -r "$DATADIR/lib/iso/profile.sh" ] || { echo "artools not found under $DATADIR" >&2; exit 2; }

# buildiso's pacman config selection (prepare_build in /usr/bin/buildiso).
pac_conf="iso-$ARCH.conf"
[ "$STABILITY" != stable ] && pac_conf="iso-$STABILITY-$ARCH.conf"
PAC_CONF="$DATADIR/pacman.conf.d/$pac_conf"
user_conf="${XDG_CONFIG_HOME:-$HOME/.config}/artools/pacman.conf.d/$pac_conf"
[ -f "$user_conf" ] && PAC_CONF="$user_conf"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/isodb/local" "$TMP/hostsync/local" "$TMP/hostdb" "$TMP/ws/iso-profiles"
# A throwaway artools workspace whose aegix profile IS the repo's iso-profile.
ln -s "$ROOT/iso-profile" "$TMP/ws/iso-profiles/aegix"
ln -s "$DATADIR/iso-profiles/common" "$TMP/ws/iso-profiles/common"

echo "==> Syncing fresh package databases (temp dir, no sudo)"
sync_db() {  # sync_db <dbpath> [pacman args...]
    local db="$1"; shift
    fakeroot -- pacman -Sy --disable-sandbox --dbpath "$db" --logfile /dev/null "$@" \
        >/dev/null 2>"$TMP/sync.err" || { cat "$TMP/sync.err" >&2; exit 2; }
}
sync_db "$TMP/isodb" --config "$PAC_CONF"   # what buildiso installs from
sync_db "$TMP/hostsync"                     # host's own repos, for HOST drift

echo "==> Fetching security tracker"
curl -fsSL --retry 3 "$TRACKER_URL" -o "$TMP/tracker.json" || { echo "tracker download failed" >&2; exit 2; }

echo "==> Loading package lists with artools ($pac_conf, $INITSYS)"
for stage in rootfs livefs bootfs; do
    DATADIR="$DATADIR" WORKSPACE_DIR="$TMP/ws" INITSYS="$INITSYS" STAGE="$stage" bash -c '
        set -e
        msg2() { :; }
        profile=aegix
        source "$DATADIR/lib/iso/profile.sh"
        load_profile
        load_pkgs "$STAGE"
        printf "%s\n" "${packages[@]}"
    ' | grep -v '^null$' | grep . | sort -u > "$TMP/list-$stage"
done

echo "==> Resolving the ISO package set"
: > "$TMP/iso-set"; : > "$TMP/missing"
for stage in rootfs livefs bootfs; do
    targets=$(cat "$TMP/list-$stage")
    [ -n "$targets" ] || continue
    # Empty local db => pacman prints the full dependency closure. On "target
    # not found", record the breakers and resolve the rest so the security
    # scan still covers everything that does exist.
    for _ in 1 2 3; do
        if pacman -Sp --config "$PAC_CONF" --dbpath "$TMP/isodb" --noconfirm \
               --print-format '%n %v' $targets >> "$TMP/iso-set" 2>"$TMP/resolve.err"; then
            break
        fi
        nf=$(sed -n 's/^error: target not found: //p' "$TMP/resolve.err")
        [ -n "$nf" ] || { cat "$TMP/resolve.err" >&2; exit 2; }
        for n in $nf; do echo "$stage: $n"; done >> "$TMP/missing"
        targets=$(printf '%s\n' $targets | grep -vxF -f <(printf '%s\n' $nf))
    done
done
sort -u -o "$TMP/iso-set" "$TMP/iso-set"

# Host drift: the real local db against the host's own fresh sync dbs.
ln -s /var/lib/pacman/local "$TMP/hostdb/local"
ln -s "$TMP/hostsync/sync" "$TMP/hostdb/sync"
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
p(f"ISO package set: {len(iso)} packages (buildiso repos, fresh dbs)")
p(f"\nBREAK (not in buildiso's repos, build would fail in make_rootfs): {len(miss)}")
for m in miss:
    p(f"  {m}")
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
bad = fails or miss
p("\nRESULT: " + ("FAIL" if bad else "PASS"))
text = "\n".join(out)
print(text)
if report != "/dev/null":
    open(report, "w").write(text + "\n")
sys.exit(1 if bad else 0)
PY

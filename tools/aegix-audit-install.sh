#!/usr/bin/env bash
# aegix-audit-install.sh: compare an installed Aegix system against this
# machine and against what the ISO profile intended to ship.
#
# Written after a run of field bugs that all had the same shape: something is
# right on the build machine and wrong on a fresh install, and nobody notices
# until a human clicks the thing. This asks the questions systematically.
#
# Usage:
#   tools/aegix-audit-install.sh <host>            # ssh key auth
#   AEGIX_AUDIT_PASS=<pw> tools/aegix-audit-install.sh <host> [user]
#
# Exits 0 always: this is a report, not a gate.
set -uo pipefail

HOST="${1:?usage: $0 <host> [user]}"
USER_NAME="${2:-aegix}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKEL="$REPO_ROOT/iso-profile/live-overlay/etc/skel"

if [ -n "${AEGIX_AUDIT_PASS:-}" ]; then
    command -v sshpass >/dev/null || { echo "sshpass not installed" >&2; exit 1; }
    SSH=(sshpass -e ssh)
    export SSHPASS="$AEGIX_AUDIT_PASS"
else
    SSH=(ssh)
fi
SSH+=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
      -o ConnectTimeout=10 -o LogLevel=ERROR "${USER_NAME}@${HOST}")

hr()  { printf '\n\033[1m== %s\033[0m\n' "$*"; }
ok()  { printf '  \033[32mok\033[0m   %s\n' "$*"; }
bad() { printf '  \033[31mDIFF\033[0m %s\n' "$*"; }

remote() { "${SSH[@]}" "$@" 2>/dev/null; }

remote true || { echo "cannot reach ${USER_NAME}@${HOST}" >&2; exit 1; }

hr "Provenance"
rel=$(remote 'cat /etc/aegix-release 2>/dev/null')
[ -n "$rel" ] && printf '%s\n' "$rel" | sed 's/^/  /' ||
    bad "/etc/aegix-release absent (installed from a pre-stamping ISO)"

hr "Home vs shipped skel (content drift)"
# Compare checksums of every regular file the skel ships against the remote
# home. Catches partial captures, stale copies, and post-install mutation.
( cd "$SKEL" && find . -type f -printf '%P\n' | sort ) > /tmp/.audit-skel-list
remote_sums=$(remote "cd \$HOME && while IFS= read -r f; do
        [ -f \"\$f\" ] && printf '%s  %s\n' \"\$(md5sum < \"\$f\" | cut -d' ' -f1)\" \"\$f\" || printf 'ABSENT  %s\n' \"\$f\"
    done" < /tmp/.audit-skel-list)
missing=0; differing=0; same=0
while IFS= read -r line; do
    sum=${line%%  *}; f=${line#*  }
    if [ "$sum" = "ABSENT" ]; then missing=$((missing+1)); [ "$missing" -le 8 ] && bad "absent in home: $f"
    elif [ "$sum" = "$(md5sum < "$SKEL/$f" | cut -d' ' -f1)" ]; then same=$((same+1))
    else differing=$((differing+1)); [ "$differing" -le 8 ] && bad "differs from skel: $f"; fi
done <<< "$remote_sums"
printf '  %d identical, %d differing, %d absent (of %d shipped)\n' \
    "$same" "$differing" "$missing" "$(wc -l < /tmp/.audit-skel-list)"

hr "Executables on PATH"
# Every command the shipped dwm config and statusbar scripts try to spawn.
# Only actual spawn targets: the first string of a spawn argv array, and the
# first word of an SHCMD. Anything else quoted in config.h is a setting name.
cmds=$( { grep -ohE 'const char\*\[\]\)\{ *"[^"]+"' "$SKEL/.local/src/dwm/config.h" 2>/dev/null |
            grep -oE '"[^"]+"' | tr -d '"'
          grep -ohE 'SHCMD\("[^" ;]+' "$SKEL/.local/src/dwm/config.h" 2>/dev/null |
            sed 's/SHCMD("//'
        } | grep -vE '^(/|\$)' | sort -u )
absent=$(remote "export PATH=\$HOME/.local/bin:\$PATH
    for c in $(echo $cmds | tr '\n' ' '); do command -v \$c >/dev/null || echo \$c; done")
if [ -z "$absent" ]; then ok "all referenced commands resolve"
else printf '%s\n' "$absent" | sed 's/^/  /' | head -15 | while read -r c; do bad "not on PATH: $c"; done; fi

hr "Groups, sudo, locale (the invisible-until-clicked layer)"
lgroups=$(id -nG | tr ' ' '\n' | sort | tr '\n' ' ')
rgroups=$(remote "id -nG" | tr ' ' '\n' | sort | tr '\n' ' ')
[ "$lgroups" = "$rgroups" ] && ok "groups match: $rgroups" || {
    bad "groups differ"; echo "    here:   $lgroups"; echo "    remote: $rgroups"; }
remote 'sudo -n true 2>/dev/null' && ok "sudo is passwordless for this user" ||
    bad "sudo prompts for a password (desktop actions needing root will hang)"
# Every locale referenced by locale.conf must actually be generated: a missing
# one takes down anything that calls setlocale() strictly (rofi, notably).
badloc=$(remote 'for l in $(grep -hoE "[a-zA-Z_]+\.UTF-8" /etc/locale.conf 2>/dev/null | sort -u); do
        locale -a | grep -qiE "^${l%.UTF-8}\.utf8$" || echo "$l"; done')
[ -z "$badloc" ] && ok "all locales in locale.conf are generated" ||
    printf '%s\n' "$badloc" | while read -r l; do bad "locale.conf references ungenerated locale: $l"; done

hr "Packages the profile promised"
# barbs/aur tags only: `rootfs` describes the live ISO environment, not what
# the installer puts on disk, so checking it here reports phantom gaps.
want=$(awk -F'\t' '$1 ~ /barbs|aur/ {print $2}' "$REPO_ROOT/sync/packages.manifest" | sort -u)
absent=$(remote "for p in $(echo $want | tr '\n' ' '); do pacman -Q \$p >/dev/null 2>&1 || echo \$p; done")
if [ -z "$absent" ]; then ok "all manifest packages installed"
else printf '  %d missing:\n' "$(printf '%s\n' "$absent" | wc -l)"
     printf '%s\n' "$absent" | head -20 | sed 's/^/    /'; fi

hr "Services"
for svc in NetworkManager dbus elogind cronie sshd; do
    remote "test -d /run/runit/service/$svc" && ok "$svc supervised" || bad "$svc not running"
done

hr "Suckless builds"
remote 'for t in dwm st dmenu dwmblocks; do
    b=$(command -v $t 2>/dev/null) || { echo "MISSING $t"; continue; }
    printf "  %-10s %s\n" "$t" "$(file -b "$b" | grep -o "BuildID[^,]*" || echo built)"
done'

printf '\n\033[1mDone.\033[0m Anything marked DIFF is worth explaining before the next ISO.\n'
rm -f /tmp/.audit-skel-list

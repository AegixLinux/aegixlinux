#!/usr/bin/env bash
# security-weekly.sh: the weekly "is it time to rebuild the ISO?" check.
#
# Two questions, two reports:
#   1. RELEASED: does the newest built ISO (its saved aegix-<date>-packages.txt)
#      ship a package with a known vulnerability that now has a fix?
#      -> that is the signal to cut a new ISO.
#   2. NEXT BUILD: would a build right now come out clean (no BREAK, no FAIL)?
#
# Reports land in ${XDG_STATE_HOME:-~/.local/state}/aegix-security/ and a
# desktop notification summarises them (critical when action is needed).
# Runs fine from cron/anacron: it finds the session D-Bus from the running
# notification daemon (Aegix starts dbus per X session, so the address
# changes every login and cannot be hardcoded).
#
# Scheduled by the user anacrontab (period 7). Manual run any time:
#   tools/security-weekly.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ISO_DIR="${ISO_DIR:-$HOME/artools-workspace/iso/aegix}"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/aegix-security"
mkdir -p "$STATE"
today="$(date +%F)"
log="$STATE/weekly.log"
exec >>"$log" 2>&1
echo "=== $(date -Is) security-weekly"

count() {  # count <CLASS> <report>: the N in "CLASS (...): N"
    sed -n "s/^$1 ([^)]*): \([0-9][0-9]*\)$/\1/p" "$2" | head -1
}

notify() {  # notify <urgency> <summary> <body>
    local bus pid
    for proc in dunst dwm Xorg; do
        pid="$(pgrep -u "$(id -u)" -x "$proc" | head -1)" || true
        [ -n "$pid" ] || continue
        bus="$(tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | sed -n 's/^DBUS_SESSION_BUS_ADDRESS=//p')"
        [ -n "$bus" ] && break
    done
    if [ -n "${bus:-}" ] && command -v notify-send >/dev/null; then
        DISPLAY="${DISPLAY:-:0}" DBUS_SESSION_BUS_ADDRESS="$bus" \
            notify-send -u "$1" -a aegix-security "$2" "$3" || echo "notify-send failed"
    else
        echo "no session bus found; notification skipped: $2 | $3"
    fi
}

# 1. Released ISO
pkgs="$(ls -t "$ISO_DIR"/aegix-*-packages.txt 2>/dev/null | head -1)"
rel_report="$STATE/$today-released.txt"
if [ -n "$pkgs" ]; then
    iso_ver="$(basename "$pkgs" | sed 's/^aegix-\([0-9]*\)-packages.txt$/\1/')"
    "$ROOT/tools/security-preflight.sh" --check-set "$pkgs" --report "$rel_report" >/dev/null
    rel_rc=$?
else
    iso_ver="(none)"; rel_rc=3
    echo "no aegix-*-packages.txt in $ISO_DIR" > "$rel_report"
fi

# 2. Next build
next_report="$STATE/$today-nextbuild.txt"
"$ROOT/tools/security-preflight.sh" --report "$next_report" >/dev/null
next_rc=$?

rel_fail="$(count FAIL "$rel_report")" rel_warn="$(count WARN "$rel_report")"
nb_break="$(count BREAK "$next_report")" nb_fail="$(count FAIL "$next_report")"
echo "released $iso_ver rc=$rel_rc fail=${rel_fail:-?} warn=${rel_warn:-?}; next build rc=$next_rc break=${nb_break:-?} fail=${nb_fail:-?}"

if [ "$rel_rc" -eq 2 ] || [ "$next_rc" -eq 2 ]; then
    notify normal "Aegix security check could not run" "Tool error (network?). Log: $log"
elif [ "${rel_fail:-0}" -gt 0 ]; then
    if [ "$next_rc" -eq 0 ]; then
        notify critical "Aegix ISO $iso_ver: rebuild now" \
            "$rel_fail High/Critical fixed vulnerabilities in the released ISO. A rebuild now comes out clean. Report: $rel_report"
    else
        notify critical "Aegix ISO $iso_ver: vulnerable, rebuild blocked" \
            "$rel_fail High/Critical fixes available, but the next build has BREAK=${nb_break:-?} FAIL=${nb_fail:-?}. Reports in $STATE"
    fi
elif [ "${rel_warn:-0}" -gt 0 ]; then
    notify normal "Aegix ISO $iso_ver: $rel_warn Medium/Low fixes available" \
        "Consider a rebuild. Report: $rel_report"
elif [ "$rel_rc" -eq 3 ]; then
    notify normal "Aegix security check: no package list" "Build an ISO with tools/build-aegix-iso.sh first."
else
    notify low "Aegix ISO $iso_ver: no known fixable vulnerabilities" \
        "Next build: $([ "$next_rc" -eq 0 ] && echo clean || echo "BREAK=${nb_break:-?} FAIL=${nb_fail:-?}")."
fi

# Keep 12 weeks of reports.
find "$STATE" -name '*-released.txt' -o -name '*-nextbuild.txt' | sort | head -n -24 | xargs -r rm -f
exit 0

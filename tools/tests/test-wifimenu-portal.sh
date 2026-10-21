#!/usr/bin/env bash
# Tests for `wifimenu probe` (captive portal detection) against a fake portal.
# Runs the skel copy in this repo, not whatever wifimenu is on PATH.
set -u
here=$(cd "$(dirname "$0")" && pwd)
port=18642
python3 -I "$here/wifimenu-fake-portal.py" "$port" & srv=$!
trap 'kill $srv 2>/dev/null' EXIT
sleep 0.5
base="http://127.0.0.1:$port"
wifimenu="$here/../../iso-profile/live-overlay/etc/skel/.local/bin/wifimenu"
pass=0; fail=0
check() {   # check <name> <expected-output> <expected-exit> <probe urls...>
    local name="$1" want="$2" wantrc="$3"; shift 3
    local got rc
    got=$(WIFIMENU_PROBE_URLS="$*" timeout 20 "$wifimenu" probe 2>&1); rc=$?
    if [[ "$got" == "$want" && "$rc" == "$wantrc" ]]; then
        echo "PASS $name"; pass=$((pass+1))
    else
        echo "FAIL $name: want [$want] rc=$wantrc, got [$got] rc=$rc"; fail=$((fail+1))
    fi
}
check 204-is-online           "online" 0 "$base/gen204"
check success-txt-is-online   "online" 0 "$base/success.txt"
check nm-check-is-online         "online" 0 "$base/nm-check.txt"
check 302-gives-location      "portal http://portal.test/login?token=abc" 1 "$base/redir"
check meta-refresh-extracted  "portal http://portal.test/meta" 1 "$base/html"
check js-location-extracted   "portal http://portal.test/js" 1 "$base/js"
check clt-js-variable-extracted "portal http://198.18.2.1:80/reg.php?ah_goal=index.html&ah_login=true&url=E2B8F3578D88E9B6" 1 "$base/clt"
check blank-200-falls-back-to-probe-url "portal $base/blank" 1 "$base/blank"
check 511-link-extracted      "portal http://portal.test/511" 1 "$base/511"
check nothing-listening-is-offline "offline" 2 "http://127.0.0.1:1/x"
check hang-is-offline         "offline" 2 "$base/hang"
check first-url-hang-second-online "online" 0 "$base/hang $base/gen204"
check first-url-dead-second-portal "portal http://portal.test/login?token=abc" 1 "http://127.0.0.1:1/x $base/redir"

# `wifimenu portal` opens the login page once: a second sighting of the same
# portal within 90s (connect path + watcher) must not open a second tab.
tmp=$(mktemp -d); printf '#!/bin/sh\necho "$1" >> "%s/opened"\n' "$tmp" > "$tmp/browser"; chmod +x "$tmp/browser"
XDG_RUNTIME_DIR="$tmp" BROWSER="$tmp/browser" WIFIMENU_PROBE_URLS="$base/redir" "$wifimenu" portal
XDG_RUNTIME_DIR="$tmp" BROWSER="$tmp/browser" WIFIMENU_PROBE_URLS="$base/redir" "$wifimenu" portal
sleep 0.3
if [[ "$(cat "$tmp/opened" 2>/dev/null)" == "http://portal.test/login?token=abc" ]]; then
    echo "PASS portal-opened-once"; pass=$((pass+1))
else
    echo "FAIL portal-opened-once: opened=[$(cat "$tmp/opened" 2>/dev/null)]"; fail=$((fail+1))
fi
pkill -f "$tmp" 2>/dev/null; rm -rf "$tmp"
echo "$pass passed, $fail failed"
[[ $fail -eq 0 ]]

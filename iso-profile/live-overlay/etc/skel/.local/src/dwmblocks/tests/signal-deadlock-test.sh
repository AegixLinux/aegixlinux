#!/bin/sh
# Regression test for the nested-signal-handler deadlock.
#
# Background
#   Stock dwmblocks does real work inside sighandler(): getsigcmds() -> getcmd()
#   (popen/fgets/pclose) and writestatus() -> setroot() (XOpenDisplay/XStoreName/
#   XCloseDisplay). None of that is async-signal-safe. If an RT signal lands while
#   the main loop is already inside one of those calls, the handler re-enters it on
#   the same thread and blocks forever on a non-recursive glibc/xcb mutex. The bar
#   then freezes at whatever it last displayed, with the process parked in
#   futex_do_wait and two RT signals stuck in SigBlk (nested handlers).
#
# What this does
#   Builds dwmblocks from SRC_DIR against a synthetic config whose blocks are
#   signal-driven, runs it against a private Xvfb, then hammers it with the two
#   signals until either the status stops advancing (deadlock -> FAIL) or the
#   storm completes with the bar still updating (PASS).
#
# Usage
#   tests/signal-deadlock-test.sh [SRC_DIR]
#   DURATION=30 tests/signal-deadlock-test.sh    # longer storm
#
# Exit codes
#   0 = no deadlock observed    1 = deadlock reproduced    2 = harness error

set -eu

SRC_DIR=${1:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
DURATION=${DURATION:-20}
STALL_LIMIT=${STALL_LIMIT:-8}   # consecutive unchanged samples (0.5s each) = stalled

WORK=$(mktemp -d) || exit 2
XVFB_PID=""
BLOCKS_PID=""
STORM_PID=""

cleanup() {
	[ -n "$STORM_PID" ]  && kill -9 "$STORM_PID"  2>/dev/null || true
	[ -n "$BLOCKS_PID" ] && kill -9 "$BLOCKS_PID" 2>/dev/null || true
	# SIGTERM, not SIGKILL: a killed Xvfb leaves /tmp/.X11-unix/X<n> behind, the
	# display picker below then treats that display as taken, and after ~30 runs
	# the whole range is exhausted and every further run dies as a harness error.
	if [ -n "$XVFB_PID" ]; then
		kill -TERM "$XVFB_PID" 2>/dev/null || true
		i=0
		while kill -0 "$XVFB_PID" 2>/dev/null && [ "$i" -lt 30 ]; do
			i=$((i + 1))
			sleep 0.1
		done
		kill -9 "$XVFB_PID" 2>/dev/null || true
	fi
	# Belt and braces, in case Xvfb was killed before it could tidy up.
	[ -n "${DISP:-}" ] && rm -f "/tmp/.X11-unix/X${DISP#:}" "/tmp/.X${DISP#:}-lock" 2>/dev/null
	rm -rf "$WORK"
	:
}
trap cleanup EXIT INT TERM

# --- pick a free X display -------------------------------------------------
DISP=""
n=99
while [ "$n" -lt 130 ]; do
	if [ ! -e "/tmp/.X11-unix/X$n" ]; then DISP=":$n"; break; fi
	n=$((n + 1))
done
[ -n "$DISP" ] || { echo "harness: no free X display"; exit 2; }

# --- build against a synthetic, signal-driven config -----------------------
cp "$SRC_DIR/dwmblocks.c" "$WORK/dwmblocks.c" || exit 2

# Two blocks on the same signals that collide in practice (clock=1, volume=10).
# `date +%s%N` guarantees the rendered string changes on every refresh, so a
# frozen status is unambiguous evidence of a hang rather than a no-op update.
cat > "$WORK/config.h" <<'EOF'
static const Block blocks[] = {
	{"A", "date +%s%N", 1,  1},
	{"B", "date +%s%N", 1, 10},
};
static char *delim = " | ";
static const int center_delim_after = -1;
EOF

# center_delim_after is an Aegix addition; drop it for upstream-shaped sources.
grep -q center_delim_after "$WORK/dwmblocks.c" || \
	sed -i '/center_delim_after/d' "$WORK/config.h"

cc -O0 -g -o "$WORK/dwmblocks" "$WORK/dwmblocks.c" -lX11 2>"$WORK/build.log" || {
	echo "harness: build failed"; cat "$WORK/build.log"; exit 2; }

# Fault injection: hold libX11's global lock (taken in _XConnectXCB) for a
# controlled interval so the sub-millisecond race becomes near-certain.
# See widen-xlib-lock.c for why this is a faithful amplification, not a cheat.
cc -shared -fPIC -o "$WORK/widen-xlib-lock.so" \
	"$(dirname -- "$0")/widen-xlib-lock.c" -ldl 2>>"$WORK/build.log" || {
	echo "harness: shim build failed"; cat "$WORK/build.log"; exit 2; }

# --- private X server ------------------------------------------------------
Xvfb "$DISP" -screen 0 640x480x8 >/dev/null 2>&1 &
XVFB_PID=$!
i=0
while [ ! -e "/tmp/.X11-unix/X${DISP#:}" ]; do
	i=$((i + 1)); [ "$i" -gt 100 ] && { echo "harness: Xvfb never came up"; exit 2; }
	sleep 0.1
done

WIDEN_LOCK_MS=${WIDEN_LOCK_MS:-50}
export WIDEN_LOCK_MS WIDEN_LOCK_VERBOSE=1

DISPLAY=$DISP LD_PRELOAD="$WORK/widen-xlib-lock.so" "$WORK/dwmblocks" 2>"$WORK/shim.log" &
BLOCKS_PID=$!
sleep 1
kill -0 "$BLOCKS_PID" 2>/dev/null || { echo "harness: dwmblocks died at startup"; exit 2; }

# A shim that silently fails to interpose would turn every run into a false
# PASS, so refuse to report anything unless we've seen it fire. The first
# setroot() lands one interval into statusloop, so poll rather than sample once.
i=0
until grep -q 'widen-xlib-lock: interposed' "$WORK/shim.log" 2>/dev/null; do
	i=$((i + 1))
	[ "$i" -gt 100 ] && {
		echo "harness: LD_PRELOAD shim never fired -- cannot trust this run"; exit 2; }
	kill -0 "$BLOCKS_PID" 2>/dev/null || {
		echo "harness: dwmblocks exited before first setroot"; exit 2; }
	sleep 0.1
done

echo "== signal-deadlock test =="
echo "   source:  $SRC_DIR"
echo "   display: $DISP   pid: $BLOCKS_PID   duration: ${DURATION}s"
echo "   lock window widened to ${WIDEN_LOCK_MS}ms via LD_PRELOAD"

# --- signal storm ----------------------------------------------------------
# Interleaved SIGRTMIN+1 / SIGRTMIN+10 with no delay, to land inside the
# main loop's own getcmd()/setroot() window as often as possible.
# NB: a full RT signal queue makes kill(1) fail with EAGAIN. That is expected
# under this much pressure and must NOT end the storm -- only the target going
# away should. Getting this wrong silently reduces the test to a no-op.
(
	sent=0
	while kill -0 "$BLOCKS_PID" 2>/dev/null; do
		kill -"$((34 + 1))"  "$BLOCKS_PID" 2>/dev/null && sent=$((sent + 1))
		kill -"$((34 + 10))" "$BLOCKS_PID" 2>/dev/null && sent=$((sent + 1))
		echo "$sent" > "$WORK/sent"
	done
) &
STORM_PID=$!

# --- watch for a stalled status -------------------------------------------
read_status() { DISPLAY=$DISP xprop -root WM_NAME 2>/dev/null || echo "<unreadable>"; }

last=$(read_status)
stalled=0
elapsed=0
samples=$(( DURATION * 2 ))

while [ "$samples" -gt 0 ]; do
	sleep 0.5
	elapsed=$((elapsed + 1))
	samples=$((samples - 1))

	kill -0 "$BLOCKS_PID" 2>/dev/null || { echo "FAIL: dwmblocks exited unexpectedly"; exit 1; }

	# Primary check. The deadlock is only a consequence of this; catching the
	# re-entrancy itself is exact and does not depend on winning a race.
	if grep -q 'REENTRANT ' "$WORK/shim.log" 2>/dev/null; then
		kill -9 "$STORM_PID" 2>/dev/null || true; STORM_PID=""
		echo
		echo "FAIL: signal handler re-entered async-signal-unsafe code on the same thread"
		echo "      signals sent: $(cat "$WORK/sent" 2>/dev/null || echo 0)"
		echo "      This is the defect behind the futex_do_wait hang: sighandler()"
		echo "      calls setroot() -> XOpenDisplay(), which is not async-signal-safe."
		echo "      Once a signal lands while the main loop holds _Xglobal_lock, the"
		echo "      handler blocks on a mutex only its own thread could release."
		exit 1
	fi

	now=$(read_status)
	if [ "$now" = "$last" ]; then
		stalled=$((stalled + 1))
	else
		stalled=0
		last=$now
	fi

	if [ "$stalled" -ge "$STALL_LIMIT" ]; then
		wchan=$(cat "/proc/$BLOCKS_PID/wchan" 2>/dev/null || echo '?')
		sigblk=$(awk '/^SigBlk:/{print $2}' "/proc/$BLOCKS_PID/status" 2>/dev/null || echo '?')
		blocked=$(python3 - "$sigblk" <<'PY' 2>/dev/null || echo '?'
import sys
m = int(sys.argv[1], 16)
print(','.join(f"SIGRTMIN+{i+1-34}" for i in range(64) if m >> i & 1 and i + 1 >= 34) or 'none')
PY
)
		kill -9 "$STORM_PID" 2>/dev/null || true; STORM_PID=""
		echo
		echo "FAIL: status frozen for $(echo "$stalled" | awk '{print $1/2}')s at ${elapsed}00ms mark"
		echo "      wchan:           $wchan"
		echo "      SigBlk:          $sigblk  ($blocked)"
		echo "      signals sent:    $(cat "$WORK/sent" 2>/dev/null || echo 0)"
		echo "      last status:     $last"
		[ "$wchan" = "futex_do_wait" ] && \
			echo "      => nested-signal-handler deadlock reproduced"
		command -v eu-stack >/dev/null 2>&1 && {
			echo "      --- stack ---"
			eu-stack -p "$BLOCKS_PID" 2>/dev/null | sed 's/^/      /' || true
		}
		exit 1
	fi
done

# Read the counter before stopping the storm; killing it mid-write can leave
# the file truncated.
sent_total=$(cat "$WORK/sent" 2>/dev/null || echo 0)
kill -9 "$STORM_PID" 2>/dev/null || true; STORM_PID=""
echo "PASS: survived ${DURATION}s signal storm, status still advancing"
echo "      signals delivered: ${sent_total:-0}"
echo "      last status: $last"
exit 0

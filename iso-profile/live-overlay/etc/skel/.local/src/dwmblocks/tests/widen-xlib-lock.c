/*
 * Fault-injection shim for tests/signal-deadlock-test.sh.
 *
 * The live hang we're reproducing had this stack (innermost first):
 *
 *   #1  pthread_mutex_lock  #2  _XConnectXCB+0x6a6  ... sighandler
 *   #8  pthread_mutex_lock  #9  _XConnectXCB+0x6a6  ... sighandler
 *   #14 __fcntl  #15 xcb_connect_to_fd  #16 xcb_connect_to_display_with_auth_info
 *   #17 _XConnectXCB+0x7b3  #18 XOpenDisplay  #19 setroot  #20 statusloop
 *
 * Note the two distinct offsets into _XConnectXCB: the main loop was past
 * +0x6a6 (it had taken libX11's lock) and down at +0x7b3 calling into libxcb,
 * while both signal handlers were stuck back at +0x6a6 waiting on that same
 * non-recursive mutex -- which only the now-blocked thread could release.
 *
 * So the lock is held across the call to xcb_connect_to_display_with_auth_info.
 * That is a libX11 -> libxcb call, i.e. it goes through the PLT and can be
 * interposed. (xcb_connect_to_fd, one frame deeper, is called from inside
 * libxcb and is NOT reliably interposable -- interposing it does nothing.)
 *
 * Sleeping here holds the existing lock for a controlled interval, turning a
 * sub-millisecond race that takes days to hit into a near-certain one. Nothing
 * about the program's semantics changes -- only how long an already-held lock
 * is held -- so a build that deadlocks here is genuinely reachable in
 * production, and a build that survives has really removed the re-entrancy.
 *
 * Delay via WIDEN_LOCK_MS (default 50). Set WIDEN_LOCK_VERBOSE=1 to confirm
 * the interposition is live; the harness relies on this to avoid a silent
 * no-op shim masquerading as a pass.
 *
 *   cc -shared -fPIC -o widen-xlib-lock.so widen-xlib-lock.c -ldl
 */

#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>
#include <string.h>
#include <signal.h>
#include <stdio.h>

/*
 * libX11 takes _Xglobal_lock through an indirect, NULL-guarded pointer:
 *
 *   mov  _XLockMutex_fn(%rip),%rax
 *   test %rax,%rax
 *   je   .skip                  <- no locking at all when threading is off
 *   mov  _Xglobal_lock(%rip),%rdi
 *   call *%rax
 *
 * so the global lock -- and therefore the deadlock -- only exists once libX11
 * threading has been initialized. The live process that hung had it enabled
 * (its handlers were blocked at the return address of that very call), but a
 * bare test process need not be, and without it this test can never fail.
 * Force it on so the harness exercises the same libX11 state as the real bar.
 *
 *
 * Re-entrancy detection
 * ---------------------
 * Waiting for an actual futex deadlock makes for a flaky test: it needs a
 * signal to land inside a lock window that may not even be armed. But the
 * deadlock is only ever a *consequence* of the real defect, which is exact and
 * always observable: an async-signal-unsafe function being entered again on the
 * same thread while an earlier call is still in progress -- i.e. a signal
 * handler re-entering it. If that never happens, the deadlock cannot.
 *
 * So the shim reports depth>1 directly. On a build whose sighandler calls
 * getcmd()/setroot() this fires within seconds; on a build whose handler only
 * sets flags it is unreachable by construction.
 */
static volatile sig_atomic_t xod_depth;
static volatile sig_atomic_t xod_reentered;
static volatile sig_atomic_t popen_depth;
static volatile sig_atomic_t popen_reentered;

static void report_reentry(const char *what, size_t len)
{
	/* write(2) is async-signal-safe; this runs inside signal handlers. */
	(void)!write(2, what, len);
}

/* Sleep for $env milliseconds, restarting across signals so the window stays
 * open for the full interval even while signals rain in. */
static void delay_ms(const char *env, long fallback)
{
	const char *val = getenv(env);
	long ms = val ? strtol(val, NULL, 10) : fallback;
	struct timespec ts;

	if (ms <= 0)
		return;
	ts.tv_sec = ms / 1000;
	ts.tv_nsec = (ms % 1000) * 1000000L;
	while (nanosleep(&ts, &ts) == -1)
		;
}

/*
 * getcmd() calls popen() before it ever reaches setroot(), and unlike setroot()
 * it has no "status unchanged" early-return to skip it. So on a build whose
 * handler does real work, popen re-entrancy fires almost immediately, whereas
 * XOpenDisplay re-entrancy needs two handlers to both survive the change check
 * and overlap -- which is exactly why the real bar ran for days before hanging.
 *
 * popen/malloc/stdio are no more async-signal-safe than Xlib: glibc's popen
 * mutates a global stream list under a lock. Re-entering it from a handler is
 * the same defect, caught one frame earlier and far more reliably.
 */
FILE *popen(const char *command, const char *type)
{
	static FILE *(*real)(const char *, const char *);
	FILE *ret;

	if (!real)
		real = (FILE *(*)(const char *, const char *))dlsym(RTLD_NEXT, "popen");

	/* Without this the test is only ~2/3 sensitive. When a second signal is
	 * already pending as a handler is entered, the nested handler tends to run
	 * to completion *before* the outer one reaches popen(), so the two windows
	 * never overlap and the re-entrancy goes unseen. Holding the window open
	 * makes the overlap reliable. As with the xcb delay this changes only
	 * timing, never semantics -- and the live hang proves the overlap is
	 * genuinely reachable without any help. */
	delay_ms("WIDEN_POPEN_MS", 20);

	if (++popen_depth > 1 && !popen_reentered) {
		static const char msg[] =
			"widen-xlib-lock: REENTRANT popen (signal handler re-entered stdio)\n";
		popen_reentered = 1;
		report_reentry(msg, sizeof(msg) - 1);
	}

	ret = real(command, type);
	--popen_depth;
	return ret;
}

void *XOpenDisplay(const char *name)
{
	static void *(*real)(const char *);
	static int threads_inited;
	void *ret;

	if (!real)
		real = (void *(*)(const char *))dlsym(RTLD_NEXT, "XOpenDisplay");

	if (!threads_inited) {
		int (*xinit)(void) = (int (*)(void))dlsym(RTLD_NEXT, "XInitThreads");
		threads_inited = 1;
		if (xinit)
			xinit();
	}

	if (++xod_depth > 1 && !xod_reentered) {
		static const char msg[] =
			"widen-xlib-lock: REENTRANT XOpenDisplay (signal handler re-entered Xlib)\n";
		xod_reentered = 1;
		(void)!write(2, msg, sizeof(msg) - 1);
	}

	ret = real(name);
	--xod_depth;
	return ret;
}

/* Declared with void* rather than the real xcb types so the shim builds
 * without xcb headers; the arguments are only ever passed straight through. */
void *xcb_connect_to_display_with_auth_info(const char *display, void *auth, int *screen)
{
	static void *(*real)(const char *, void *, int *);

	if (!real)
		real = (void *(*)(const char *, void *, int *))
			dlsym(RTLD_NEXT, "xcb_connect_to_display_with_auth_info");

	if (getenv("WIDEN_LOCK_VERBOSE")) {
		static const char msg[] = "widen-xlib-lock: interposed\n";
		/* write(2) is async-signal-safe; this shim runs inside handlers too. */
		(void)!write(2, msg, sizeof(msg) - 1);
	}

	/* Holds libX11's global lock, taken back in _XConnectXCB, for the interval. */
	delay_ms("WIDEN_LOCK_MS", 50);

	return real(display, auth, screen);
}

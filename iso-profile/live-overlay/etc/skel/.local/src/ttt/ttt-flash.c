/* ttt-flash - flash the whole X screen red a few times
 * See LICENSE for copyright and license details. */
#define _POSIX_C_SOURCE 199309L

#include <time.h>
#include <X11/Xlib.h>

#define FLASHES 3
#define ON_MS   160
#define OFF_MS  120
#define COLOR   0xff0000

static void
msleep(long ms)
{
	struct timespec ts = { ms / 1000, (ms % 1000) * 1000000L };

	nanosleep(&ts, NULL);
}

int
main(void)
{
	Display *dpy;
	Window win;
	XSetWindowAttributes wa;
	int scr, i;

	if (!(dpy = XOpenDisplay(NULL)))
		return 1;
	scr = DefaultScreen(dpy);
	wa.override_redirect = True;
	wa.background_pixel = COLOR;
	win = XCreateWindow(dpy, RootWindow(dpy, scr), 0, 0,
	                    (unsigned)DisplayWidth(dpy, scr),
	                    (unsigned)DisplayHeight(dpy, scr),
	                    0, CopyFromParent, InputOutput, CopyFromParent,
	                    CWOverrideRedirect | CWBackPixel, &wa);
	for (i = 0; i < FLASHES; i++) {
		XMapRaised(dpy, win);
		XFlush(dpy);
		msleep(ON_MS);
		XUnmapWindow(dpy, win);
		XFlush(dpy);
		msleep(OFF_MS);
	}
	XCloseDisplay(dpy);
	return 0;
}

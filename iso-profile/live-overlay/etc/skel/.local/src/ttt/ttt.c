/* ttt - terminal time timer
 *
 * A visual countdown in the spirit of the physical Time Timer:
 * a dial with 0 at the top, minutes running clockwise like a clock
 * face (15 east, 30 south, 45 west), and a red wedge whose edge
 * sweeps counterclockwise back to noon as time runs out.
 *
 * usage: ttt [minutes]
 * keys:  1-60 then Enter (or a short pause) sets the timer,
 *        two digits commit at once, q or Ctrl-C quits.
 *
 * See LICENSE for copyright and license details. */
#define _POSIX_C_SOURCE 200809L

#include <math.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/select.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>

#include "dial.h"
#include "input.h"
#include "config.h"

static struct termios savedtio;
static int rawmode;
static volatile sig_atomic_t winched = 1, quitreq;

static double
now(void)
{
	struct timespec ts;

	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ts.tv_sec + ts.tv_nsec / 1e9;
}

static void
restoreterm(void)
{
	if (rawmode)
		tcsetattr(STDIN_FILENO, TCSAFLUSH, &savedtio);
	fputs("\033[0m\033[?25h\033[?1049l", stdout);
	fflush(stdout);
}

static void
onsig(int sig)
{
	if (sig == SIGWINCH)
		winched = 1;
	else
		quitreq = 1;
}

static void
setupterm(void)
{
	struct termios tio;

	if (tcgetattr(STDIN_FILENO, &savedtio) < 0) {
		fputs("ttt: not a terminal\n", stderr);
		exit(1);
	}
	tio = savedtio;
	tio.c_lflag &= ~(tcflag_t)(ICANON | ECHO | ISIG);
	tio.c_iflag &= ~(tcflag_t)(IXON | ICRNL);
	tio.c_cc[VMIN] = 0;
	tio.c_cc[VTIME] = 0;
	tcsetattr(STDIN_FILENO, TCSAFLUSH, &tio);
	rawmode = 1;
	fputs("\033[?1049h\033[?25l", stdout);
}

static void
spawn(const char *cmd)
{
	if (fork() == 0) {
		execl("/bin/sh", "sh", "-c", cmd, (char *)NULL);
		_exit(127);
	}
}

/* How many vertical pixel units one column is worth, so the dial is
 * a true circle: half-block pixel width over height, measured from
 * the terminal's reported pixel size. Divided by the config xscale,
 * so xscale above 1.0 widens the dial. */
static double hscale = 1.0;

/* Color of one square pixel as 0xRRGGBB, or -1 for the terminal's
 * own background. Hard-thresholded: a pixel is painted solid when
 * at least half of it is covered. Chunky on purpose. The wedge
 * reaches under the ring like the physical disc under its bezel,
 * and the ring is drawn on top, so they always meet seamlessly. */
static long
pixel(double dx, double dy, double R, double frac)
{
	if (ring_coverage(dx, dy, R, 2.0) >= 0.5)
		return rimcolor;
	if (wedge_coverage(dx, dy, R + 2.0, frac) >= 0.5)
		return wedgecolor;
	return -1;
}

static void
setcolors(long fg, long bg, long *curfg, long *curbg)
{
	if (fg != *curfg) {
		if (fg < 0)
			fputs("\033[39m", stdout);
		else
			printf("\033[38;2;%d;%d;%dm",
			       (int)(fg >> 16 & 0xff),
			       (int)(fg >> 8 & 0xff),
			       (int)(fg & 0xff));
		*curfg = fg;
	}
	if (bg != *curbg) {
		if (bg < 0)
			fputs("\033[49m", stdout);
		else
			printf("\033[48;2;%d;%d;%dm",
			       (int)(bg >> 16 & 0xff),
			       (int)(bg >> 8 & 0xff),
			       (int)(bg & 0xff));
		*curbg = bg;
	}
}

static void
draw(int cols, int rows, double frac, int remsec, const Input *in)
{
	int x, y, col;
	long ct, cb, curfg = -2, curbg = -2;
	int drows = rows >= 10 ? rows - 2 : rows - 1; /* breathing row */
	int pw = cols, ph = drows * 2;
	double cx = pw / 2.0 - 0.5, cy = ph / 2.0 - 0.5, R;
	char text[16];

	R = fmin((pw / 2.0 - 1.0) * hscale, ph / 2.0 - 1.0) - 3.5;
	if (R < 3.0)
		R = fmin((pw / 2.0 - 1.0) * hscale, ph / 2.0 - 1.0);

	for (y = 0; y < drows; y++) {
		printf("\033[%d;1H", y + 1);
		for (x = 0; x < cols; x++) {
			ct = pixel((x - cx) * hscale, 2 * y - cy, R, frac);
			cb = pixel((x - cx) * hscale, 2 * y + 1 - cy, R, frac);
			if (ct < 0 && cb < 0) {
				setcolors(curfg, -1, &curfg, &curbg);
				putchar(' ');
			} else if (cb < 0) {
				setcolors(ct, -1, &curfg, &curbg);
				fputs("\xe2\x96\x80", stdout); /* upper half block */
			} else if (ct < 0) {
				setcolors(cb, -1, &curfg, &curbg);
				fputs("\xe2\x96\x84", stdout); /* lower half block */
			} else {
				setcolors(ct, cb, &curfg, &curbg);
				fputs("\xe2\x96\x80", stdout);
			}
		}
	}
	for (y = drows; y < rows - 1; y++)
		printf("\033[%d;1H\033[K", y + 1);
	if (in->len)
		snprintf(text, sizeof text, "set: %.*s", in->len, in->buf);
	else
		snprintf(text, sizeof text, "%02d:%02d",
		         remsec / 60, remsec % 60);
	setcolors(textcolor, -1, &curfg, &curbg);
	col = (cols - (int)strlen(text)) / 2 + 1;
	printf("\033[%d;1H\033[K\033[%d;%dH%s",
	       rows, rows, col > 0 ? col : 1, text);
	fflush(stdout);
}

int
main(int argc, char *argv[])
{
	static char obuf[1 << 18];
	int mins = 0, cols = 80, rows = 24;
	int sec, lastsec = -1, lastlen = 0, forcedraw = 1, alarmed = 0, m;
	double deadline = 0, t, rem;
	unsigned char c;
	Input in;
	struct winsize ws;
	struct sigaction sa;
	fd_set rfds;
	struct timeval tv;

	if (argc > 2 || (argc == 2 && ((mins = atoi(argv[1])) < 1 || mins > 60))) {
		fputs("usage: ttt [minutes]   (1 to 60)\n", stderr);
		return 1;
	}

	memset(&sa, 0, sizeof sa);
	sa.sa_handler = onsig;
	sigaction(SIGWINCH, &sa, NULL);
	sigaction(SIGINT, &sa, NULL);
	sigaction(SIGTERM, &sa, NULL);
	sigaction(SIGHUP, &sa, NULL);
	sa.sa_handler = SIG_IGN;
	sigaction(SIGCHLD, &sa, NULL); /* auto reap alarm commands */

	setvbuf(stdout, obuf, _IOFBF, sizeof obuf);
	setupterm();
	atexit(restoreterm);
	input_init(&in);

	if (mins)
		deadline = now() + mins * 60;

	while (!quitreq) {
		t = now();
		if (winched) {
			winched = 0;
			if (ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) == 0 &&
			    ws.ws_col > 0 && ws.ws_row > 1) {
				cols = ws.ws_col;
				rows = ws.ws_row;
				hscale = 1.0 / xscale;
				if (ws.ws_xpixel > 0 && ws.ws_ypixel > 0)
					hscale = 2.0 *
					         ((double)ws.ws_xpixel / cols) /
					         ((double)ws.ws_ypixel / rows) /
					         xscale;
				if (hscale < 0.25)
					hscale = 0.25;
				if (hscale > 4.0)
					hscale = 4.0;
			}
			forcedraw = 1;
		}
		rem = deadline - t;
		if (rem < 0)
			rem = 0;
		if (deadline > 0 && rem <= 0 && !alarmed) {
			alarmed = 1;
			spawn(alarmcmd);
			forcedraw = 1;
		}
		if ((m = input_tick(&in, t)) > 0) {
			deadline = t + m * 60;
			alarmed = 0;
			forcedraw = 1;
		}
		sec = (int)ceil(rem);
		if (forcedraw || sec != lastsec || in.len != lastlen) {
			draw(cols, rows, rem / 3600.0, sec, &in);
			lastsec = sec;
			lastlen = in.len;
			forcedraw = 0;
		}
		FD_ZERO(&rfds);
		FD_SET(STDIN_FILENO, &rfds);
		tv.tv_sec = 0;
		tv.tv_usec = 100000;
		if (select(STDIN_FILENO + 1, &rfds, NULL, NULL, &tv) > 0) {
			ssize_t n = read(STDIN_FILENO, &c, 1);

			if (n == 0) /* terminal closed */
				break;
			if (n == 1) {
				if (c == 'q' || c == 3)
					break;
				if ((m = input_feed(&in, c, now())) > 0) {
					deadline = now() + m * 60;
					alarmed = 0;
					forcedraw = 1;
				}
			}
		}
	}
	return 0;
}

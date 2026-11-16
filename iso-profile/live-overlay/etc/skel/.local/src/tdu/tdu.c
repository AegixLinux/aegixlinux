/* tdu - terminal disk usage
 * See LICENSE file for copyright and license details. */
#define _XOPEN_SOURCE 700
#include <errno.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/statvfs.h>
#include <termios.h>
#include <unistd.h>

#include "bar.h"
#include "fmt.h"
#include "mounts.h"
#include "row.h"
#include "scan.h"
#include "config.h"

static struct termios origterm;
static volatile sig_atomic_t winched, gotsig;

static void
onsig(int sig)
{
	if (sig == SIGWINCH)
		winched = 1;
	else
		gotsig = 1;
}

static void
setfg(long c)
{
	printf("\033[38;2;%ld;%ld;%ldm",
	       c >> 16 & 255, c >> 8 & 255, c & 255);
}

static int
termwidth(void)
{
	struct winsize ws;
	const char *c;

	if (ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) == 0 && ws.ws_col > 0)
		return ws.ws_col;
	if ((c = getenv("COLUMNS")) && atoi(c) > 0)
		return atoi(c);
	return 100;
}

/* /proc/mounts, kept for the drill-down boundary list too. */
static char mtext[1 << 16];

/* Devices with live statvfs numbers; rows that fail are dropped. */
static int
gather(Device *devs, Stats *stats, int max)
{
	FILE *f;
	size_t r;
	int n, i, k = 0;

	if (!(f = fopen("/proc/mounts", "r")))
		return 0;
	r = fread(mtext, 1, sizeof mtext - 1, f);
	fclose(f);
	mtext[r] = '\0';
	n = mounts_parse(mtext, devs, max);
	for (i = 0; i < n; i++) {
		struct statvfs vs;

		if (statvfs(devs[i].mnt, &vs) != 0)
			continue;
		if (k != i)
			devs[k] = devs[i];
		stats[k].total = (unsigned long long)vs.f_blocks * vs.f_frsize;
		stats[k].used = (unsigned long long)(vs.f_blocks - vs.f_bfree) *
		                vs.f_frsize;
		stats[k].avail = (unsigned long long)vs.f_bavail * vs.f_frsize;
		k++;
	}
	return k;
}

/* Print a rendered row, coloring the bar cells: '#' in the fill
 * color for this fraction, '.' as the track. */
static void
putrow(const char *line, double frac)
{
	long fill = bar_color(frac, warnat, critat,
	                      okcolor, warncolor, critcolor);
	const char *p;
	int inbar = 0;

	for (p = line; *p; p++) {
		if (*p == '[' && !inbar) {
			inbar = 1;
			putchar('[');
		} else if (*p == ']' && inbar) {
			inbar = 0;
			fputs("\033[0m]", stdout);
		} else if (inbar && *p == '#') {
			setfg(fill);
			fputs(barfill, stdout);
		} else if (inbar && *p == '.') {
			setfg(trackcolor);
			fputs(bartrack, stdout);
		} else {
			putchar(*p);
		}
	}
	fputs("\033[0m\r\n", stdout);
}

/* Spinner during a drill-down scan; q or Esc aborts it. */
static int
drill_progress(unsigned long long done, void *ud)
{
	static const char spin[] = "|/-\\";
	int *tick = ud;
	struct pollfd pf;
	unsigned char ch;

	if (gotsig)
		return 1;
	printf("\r%c scanned %llu items ", spin[(*tick)++ % 4], done);
	fflush(stdout);
	pf.fd = STDIN_FILENO;
	pf.events = POLLIN;
	while (poll(&pf, 1, 0) > 0) {
		if (read(STDIN_FILENO, &ch, 1) != 1)
			break;
		if (ch == 3) {
			gotsig = 1;
			return 1;
		}
		if (ch == 'q' || ch == 27)
			return 1;
	}
	return 0;
}

/* One-level drill-down into a device's first mountpoint. */
static void
drill(const Device *d)
{
	static Entry entries[512];
	static char all[MNT_MAX][MNT_PATH], excl[MNT_MAX][MNT_PATH];
	char bar[64 + 1], size[8];
	unsigned long long maxb;
	int nall, nx = 0, n, i, j, barw, cells, tick;

	nall = mounts_all(mtext, all, MNT_MAX);
	for (i = 0; i < nall; i++)
		if (strcmp(all[i], d->mnt) != 0)
			memcpy(excl[nx++], all[i], MNT_PATH);

	for (;;) {
		fputs("\033[H\033[2J", stdout);
		setfg(labelcolor);
		printf("%s  %s\033[0m\r\n\r\n", d->name, d->mnt);
		tick = 0;
		n = scan_root(d->mnt, excl, nx, entries, 512,
		              drill_progress, &tick);
		if (n < 0 || gotsig)
			return; /* aborted */
		qsort(entries, (size_t)n, sizeof *entries, entry_cmp);
		maxb = n > 0 ? entries[0].bytes : 0;

		for (;;) { /* display loop: redraws, never rescans */
			unsigned char ch;
			ssize_t r;

			barw = termwidth() - (2 + 24 + 2 + 2 + 2 + 8);
			if (barw > 24)
				barw = 24;
			if (barw < 10)
				barw = 10;
			fputs("\033[H\033[2J", stdout);
			setfg(labelcolor);
			printf("%s  %s\033[0m\r\n\r\n", d->name, d->mnt);
			for (i = 0; i < n && i < topn; i++) {
				char line[512];

				cells = maxb ?
				    bar_cells((double)entries[i].bytes /
				              (double)maxb, barw) : 0;
				for (j = 0; j < barw; j++)
					bar[j] = j < cells ? '#' : '.';
				bar[barw] = '\0';
				fmt_size(entries[i].bytes, size, sizeof size);
				snprintf(line, sizeof line,
				         "  %-24.24s [%s] %6s",
				         entries[i].name, bar, size);
				putrow(line, 0.0);
			}
			fputs("\r\n", stdout);
			setfg(labelcolor);
			fputs("q back   r rescan\033[0m", stdout);
			fflush(stdout);

			r = read(STDIN_FILENO, &ch, 1);
			if (gotsig)
				return;
			if (r < 0 && errno == EINTR) {
				winched = 0;
				continue; /* redraw at the new width */
			}
			if (r <= 0 || ch == 'q' || ch == 27)
				return;
			if (ch == 3) {
				gotsig = 1;
				return;
			}
			if (ch == 'r')
				break; /* rescan */
		}
	}
}

static void
draw_overview(Device *devs, Stats *stats, int n, int width)
{
	char line[512];
	int i;

	fputs("\033[H\033[2J", stdout);
	for (i = 0; i < n; i++) {
		row_render(&devs[i], &stats[i], i, width, line, sizeof line);
		putrow(line, frac_used(stats[i].used, stats[i].avail));
	}
	fputs("\r\n", stdout);
	setfg(labelcolor);
	fputs("q quit   r refresh   1.. inspect\033[0m", stdout);
	fflush(stdout);
}

int
main(void)
{
	Device devs[MNT_MAX];
	Stats stats[MNT_MAX];
	struct sigaction sa;
	struct termios t;
	int n, i;

	n = gather(devs, stats, MNT_MAX);

	if (!isatty(STDOUT_FILENO)) {
		char line[512];
		const char *c = getenv("COLUMNS");
		int w = (c && atoi(c) > 0) ? atoi(c) : 100;

		for (i = 0; i < n; i++) {
			row_render(&devs[i], &stats[i], i, w,
			           line, sizeof line);
			puts(line);
		}
		return 0;
	}

	memset(&sa, 0, sizeof sa);
	sa.sa_handler = onsig;
	sigaction(SIGWINCH, &sa, NULL);
	sigaction(SIGINT, &sa, NULL);
	sigaction(SIGTERM, &sa, NULL);

	tcgetattr(STDIN_FILENO, &origterm);
	t = origterm;
	t.c_lflag &= ~(tcflag_t)(ICANON | ECHO | ISIG);
	t.c_cc[VMIN] = 1;
	t.c_cc[VTIME] = 0;
	tcsetattr(STDIN_FILENO, TCSANOW, &t);
	fputs("\033[?1049h\033[?25l", stdout);

	while (!gotsig) {
		unsigned char ch;
		ssize_t r;

		draw_overview(devs, stats, n, termwidth());
		r = read(STDIN_FILENO, &ch, 1);
		if (gotsig)
			break;
		if (r < 0) {
			if (errno == EINTR) {
				winched = 0;
				continue;
			}
			break;
		}
		if (r == 0)
			break;
		if (ch == 'q' || ch == 27 || ch == 3)
			break;
		if (ch == 'r')
			n = gather(devs, stats, MNT_MAX);
		else if ((i = row_for_key(ch, n)) >= 0)
			drill(&devs[i]);
	}

	tcsetattr(STDIN_FILENO, TCSANOW, &origterm);
	fputs("\033[0m\033[?25h\033[?1049l", stdout);
	return 0;
}

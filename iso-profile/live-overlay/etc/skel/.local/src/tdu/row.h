/* row.h: overview row layout and selection keys, pure and testable */
#ifndef ROW_H
#define ROW_H

#include <stdio.h>
#include <string.h>

#include "bar.h"
#include "fmt.h"
#include "mounts.h"

typedef struct {
	unsigned long long total, used, avail; /* bytes */
} Stats;

/* Selection key for row i: '1'..'9', then letters from 'a',
 * skipping the reserved 'q' and 'r'. 0 when rows run out. */
static inline int
key_for_row(int i)
{
	int c;

	if (i < 9)
		return '1' + i;
	c = 'a' + (i - 9);
	if (c >= 'q')
		c += 2; /* q quits, r refreshes */
	return c > 'z' ? 0 : c;
}

/* Row for a pressed key among n rows, -1 when it is not one. */
static inline int
row_for_key(int ch, int n)
{
	int i;

	for (i = 0; i < n; i++)
		if (key_for_row(i) == ch)
			return i;
	return -1;
}

/* One attempt at a layout; succeeds when the row fits width. The
 * bar is '#' filled and '.' track, colored by the caller. */
static inline int
row_try(char *out, size_t n, int key, const char *name, const char *mnts,
        int namew, int mntw, double frac, int barw, const char *tail,
        int width)
{
	char bar[64 + 1];
	int i, cells, len;

	if (barw > 64)
		barw = 64;
	cells = bar_cells(frac, barw);
	for (i = 0; i < barw; i++)
		bar[i] = i < cells ? '#' : '.';
	bar[barw] = '\0';
	len = snprintf(out, n, "%c  %-*.*s  %-*.*s [%s]%s",
	               key ? key : ' ', namew, namew, name,
	               mntw, mntw, mnts, bar, tail);
	return len >= 0 && (size_t)len < n && len <= width;
}

/* Render row idx as plain text, never longer than width: columns
 * drop from the right (free, then used/total, then percent), the
 * bar shrinks last but never below 10 cells, then the mountpoint
 * and name columns give way. */
static inline void
row_render(const Device *d, const Stats *s, int idx, int width,
           char *out, size_t n)
{
	char mnts[2 * MNT_PATH], used[8], tot[8], avail[8], tail[48];
	double frac = frac_used(s->used, s->avail);
	int pct = (int)(frac * 100.0 + 0.5);
	int key = key_for_row(idx), barw, mntw, namew;

	fmt_size(s->used, used, sizeof used);
	fmt_size(s->total, tot, sizeof tot);
	fmt_size(s->avail, avail, sizeof avail);
	snprintf(mnts, sizeof mnts, "%s%s", d->mnt, d->extra);

	snprintf(tail, sizeof tail, " %3d%%  %s/%s  %s free",
	         pct, used, tot, avail);
	if (row_try(out, n, key, d->name, mnts, 12, 18, frac, 24, tail, width))
		return;
	snprintf(tail, sizeof tail, " %3d%%  %s/%s", pct, used, tot);
	if (row_try(out, n, key, d->name, mnts, 12, 18, frac, 24, tail, width))
		return;
	snprintf(tail, sizeof tail, " %3d%%", pct);
	if (row_try(out, n, key, d->name, mnts, 12, 18, frac, 24, tail, width))
		return;
	tail[0] = '\0';
	for (barw = 24; barw >= 10; barw--)
		if (row_try(out, n, key, d->name, mnts, 12, 18, frac, barw,
		            tail, width))
			return;
	for (mntw = 18; mntw >= 1; mntw--)
		if (row_try(out, n, key, d->name, mnts, 12, mntw, frac, 10,
		            tail, width))
			return;
	for (namew = 12; namew >= 1; namew--)
		if (row_try(out, n, key, d->name, mnts, namew, 1, frac, 10,
		            tail, width))
			return;
	/* width is hopeless; render minimal and cut at width */
	row_try(out, n, key, d->name, mnts, 1, 1, frac, 10, tail, (int)n);
	if (width >= 0 && (size_t)width < n)
		out[width] = '\0';
}

#endif

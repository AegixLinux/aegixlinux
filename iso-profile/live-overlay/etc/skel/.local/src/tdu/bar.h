/* bar.h: fill-bar math, pure and testable */
#ifndef BAR_H
#define BAR_H

/* Filled cells for a fraction of a width-cell bar, rounded to the
 * nearest cell, clamped to [0, width]. */
static inline int
bar_cells(double frac, int width)
{
	int cells = (int)(frac * width + 0.5);

	if (cells < 0)
		return 0;
	if (cells > width)
		return width;
	return cells;
}

/* Fill fraction the df way: used / (used + avail), with avail the
 * space available to unprivileged users. 0 when the sum is 0, so a
 * zero-block filesystem never divides by zero. */
static inline double
frac_used(unsigned long long used, unsigned long long avail)
{
	if (used + avail == 0)
		return 0.0;
	return (double)used / (double)(used + avail);
}

/* Bar color by fill: ok below warn, wc from warn, cc from crit. */
static inline long
bar_color(double frac, double warn, double crit, long ok, long wc, long cc)
{
	if (frac >= crit)
		return cc;
	if (frac >= warn)
		return wc;
	return ok;
}

#endif

/* dial.h: pure geometry for the ttt dial, shared by ttt.c and tests */
#ifndef DIAL_H
#define DIAL_H

#include <math.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

/* Fraction of a full turn, clockwise from 12 o'clock, in [0, 1).
 * (dx, dy) is a point relative to the dial center, screen y grows down.
 * Minutes read like a clock face: 15 east, 30 south, 45 west, so the
 * wedge edge sweeps counterclockwise back to noon as time runs out. */
static double
angfrac(double dx, double dy)
{
	double a = atan2(dx, -dy);

	if (a < 0)
		a += 2 * M_PI;
	return a / (2 * M_PI);
}

/* 1 if the point lies inside the remaining-time wedge.
 * frac is remaining time as a fraction of the full dial (0 to 1). */
static int
in_wedge(double dx, double dy, double frac)
{
	if (frac <= 0)
		return 0;
	if (frac >= 1)
		return 1;
	return angfrac(dx, dy) <= frac;
}

/* Fraction (0 to 1) of the unit pixel centered at (dx, dy) that is
 * covered by the wedge of radius R, by supersampling. Lets edge
 * pixels render on a color ramp instead of a hard staircase. */
static double
wedge_coverage(double dx, double dy, double R, double frac)
{
	int i, j, hit = 0;
	double sx, sy;

	for (i = 0; i < 4; i++) {
		for (j = 0; j < 4; j++) {
			sx = dx + (i + 0.5) / 4.0 - 0.5;
			sy = dy + (j + 0.5) / 4.0 - 0.5;
			if (sx * sx + sy * sy <= R * R &&
			    in_wedge(sx, sy, frac))
				hit++;
		}
	}
	return hit / 16.0;
}

/* Fraction of the unit pixel at (dx, dy) covered by the ring band
 * between radius R and R + w. */
static double
ring_coverage(double dx, double dy, double R, double w)
{
	int i, j, hit = 0;
	double sx, sy, r2;

	for (i = 0; i < 4; i++) {
		for (j = 0; j < 4; j++) {
			sx = dx + (i + 0.5) / 4.0 - 0.5;
			sy = dy + (j + 0.5) / 4.0 - 0.5;
			r2 = sx * sx + sy * sy;
			if (r2 > R * R && r2 <= (R + w) * (R + w))
				hit++;
		}
	}
	return hit / 16.0;
}

#endif

/* fmt.h: humanized byte sizes, pure and testable */
#ifndef FMT_H
#define FMT_H

#include <stdio.h>

/* Write bytes humanized into buf: "0B", "512B", "941M", "1.0G".
 * Binary units, suffixes B K M G T P, largest unit with value >= 1.
 * One decimal when the value is below 10 (B values excepted).
 * Digits truncate toward zero, never round. */
static inline void
fmt_size(unsigned long long bytes, char *buf, size_t n)
{
	static const char sufs[] = "BKMGTP";
	unsigned long long unit = 1;
	int i = 0;

	while (i < 5 && bytes >= unit * 1024) {
		unit *= 1024;
		i++;
	}
	if (i == 0)
		snprintf(buf, n, "%lluB", bytes);
	else if (bytes / unit < 10)
		snprintf(buf, n, "%d.%d%c", (int)(bytes / unit) % 10,
		         (int)(bytes % unit * 10 / unit) % 10, sufs[i]);
	else
		/* value is at most 16384 (2^64 / 2^50); the modulus only
		 * tells the compiler so, it never fires */
		snprintf(buf, n, "%u%c",
		         (unsigned)(bytes / unit) % 100000, sufs[i]);
}

#endif

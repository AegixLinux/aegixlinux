/* mounts.h: /proc/mounts parsing and device dedupe, pure and testable */
#ifndef MOUNTS_H
#define MOUNTS_H

#include <stdio.h>
#include <string.h>

enum { MNT_PATH = 256, MNT_NAME = 64, MNT_MAX = 64 };

typedef struct {
	char src[MNT_PATH];   /* /dev/mapper/aegixluks */
	char name[MNT_NAME];  /* basename of src */
	char mnt[MNT_PATH];   /* first mountpoint, unescaped */
	char extra[MNT_PATH]; /* "" or " +/home +/var" */
} Device;

/* Rewrite \040-style octal escapes in place; /proc/mounts emits
 * them for spaces, tabs, newlines and backslashes in paths. */
static inline void
mnt_unescape(char *s)
{
	char *r = s, *w = s;

	while (*r) {
		if (r[0] == '\\' &&
		    r[1] >= '0' && r[1] <= '3' &&
		    r[2] >= '0' && r[2] <= '7' &&
		    r[3] >= '0' && r[3] <= '7') {
			*w++ = (char)(((r[1] - '0') << 6) |
			              ((r[2] - '0') << 3) | (r[3] - '0'));
			r += 4;
		} else {
			*w++ = *r++;
		}
	}
	*w = '\0';
}

static inline void
mnt_copy(char *dst, size_t n, const char *tok, size_t len)
{
	if (len >= n)
		len = n - 1;
	memcpy(dst, tok, len);
	dst[len] = '\0';
}

/* Pull the first two space-separated fields out of one line.
 * Returns 0 on a line with fewer than two fields. */
static inline int
mnt_fields(const char *line, size_t len,
           const char **src, size_t *srclen,
           const char **mnt, size_t *mntlen)
{
	const char *sp1 = memchr(line, ' ', len), *sp2;
	size_t rest;

	if (!sp1)
		return 0;
	*src = line;
	*srclen = (size_t)(sp1 - line);
	*mnt = sp1 + 1;
	rest = len - *srclen - 1;
	sp2 = memchr(*mnt, ' ', rest);
	*mntlen = sp2 ? (size_t)(sp2 - *mnt) : rest;
	return *mntlen > 0;
}

/* One Device per /dev/-backed source in text (raw /proc/mounts
 * content). First mount wins; later mounts of the same source
 * append to extra as " +/path". Returns the device count. */
static inline int
mounts_parse(const char *text, Device *devs, int max)
{
	const char *p = text, *eol, *src, *mnt;
	size_t linelen, srclen, mntlen, have;
	int n = 0, i, found;

	while (*p) {
		eol = strchr(p, '\n');
		linelen = eol ? (size_t)(eol - p) : strlen(p);
		if (mnt_fields(p, linelen, &src, &srclen, &mnt, &mntlen) &&
		    srclen > 5 && !strncmp(src, "/dev/", 5)) {
			char srcbuf[MNT_PATH], mntbuf[MNT_PATH];
			const char *base;

			mnt_copy(srcbuf, sizeof srcbuf, src, srclen);
			mnt_copy(mntbuf, sizeof mntbuf, mnt, mntlen);
			mnt_unescape(mntbuf);
			found = -1;
			for (i = 0; i < n; i++)
				if (!strcmp(devs[i].src, srcbuf)) {
					found = i;
					break;
				}
			if (found >= 0) {
				have = strlen(devs[found].extra);
				snprintf(devs[found].extra + have,
				         sizeof devs[found].extra - have,
				         " +%s", mntbuf);
			} else if (n < max) {
				Device *d = &devs[n++];

				memcpy(d->src, srcbuf, sizeof d->src);
				base = strrchr(srcbuf, '/');
				mnt_copy(d->name, sizeof d->name,
				         base + 1, strlen(base + 1));
				memcpy(d->mnt, mntbuf, sizeof d->mnt);
				d->extra[0] = '\0';
			}
		}
		if (!eol)
			break;
		p = eol + 1;
	}
	return n;
}

/* Every mountpoint of every line, any fstype, unescaped: the
 * drill-down boundary list. Returns the count. */
static inline int
mounts_all(const char *text, char (*mnts)[MNT_PATH], int max)
{
	const char *p = text, *eol, *src, *mnt;
	size_t linelen, srclen, mntlen;
	int n = 0;

	while (*p && n < max) {
		eol = strchr(p, '\n');
		linelen = eol ? (size_t)(eol - p) : strlen(p);
		if (mnt_fields(p, linelen, &src, &srclen, &mnt, &mntlen)) {
			mnt_copy(mnts[n], MNT_PATH, mnt, mntlen);
			mnt_unescape(mnts[n]);
			n++;
		}
		if (!eol)
			break;
		p = eol + 1;
	}
	return n;
}

#endif

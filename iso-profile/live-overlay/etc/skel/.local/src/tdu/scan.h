/* scan.h: on-device directory sizing for the drill-down */
#ifndef SCAN_H
#define SCAN_H

#include <dirent.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#include "mounts.h" /* MNT_PATH */

enum { SCAN_NAME = 256, SCAN_PATH = 4096 };

typedef struct {
	char name[SCAN_NAME];
	unsigned long long bytes; /* st_blocks * 512, hard links once */
} Entry;

/* Called about every 256 items (and on the first); nonzero aborts. */
typedef int (*ScanProgress)(unsigned long long done, void *ud);

/* qsort comparator: Entry bytes, descending. */
static inline int
entry_cmp(const void *a, const void *b)
{
	const Entry *x = a, *y = b;

	if (x->bytes > y->bytes)
		return -1;
	return x->bytes < y->bytes;
}

/* dev/ino set for hard-link dedupe: open addressing, grows by
 * doubling. On allocation failure dedupe degrades to counting
 * duplicates rather than failing the scan. */
typedef struct {
	unsigned long long dev, ino;
	char used;
} InoSlot;

typedef struct {
	InoSlot *slots;
	size_t cap, len;
} InoSet;

/* Returns 1 when newly added, 0 when already present or on OOM. */
static inline int
inoset_add(InoSet *s, unsigned long long dev, unsigned long long ino)
{
	size_t i;

	if (s->len * 2 >= s->cap) {
		size_t ncap = s->cap ? s->cap * 2 : 1024, j;
		InoSlot *nslots = calloc(ncap, sizeof *nslots);

		if (!nslots)
			return 1;
		for (j = 0; j < s->cap; j++)
			if (s->slots[j].used) {
				i = (size_t)(s->slots[j].dev * 31 +
				             s->slots[j].ino) % ncap;
				while (nslots[i].used)
					i = (i + 1) % ncap;
				nslots[i] = s->slots[j];
			}
		free(s->slots);
		s->slots = nslots;
		s->cap = ncap;
	}
	i = (size_t)(dev * 31 + ino) % s->cap;
	while (s->slots[i].used) {
		if (s->slots[i].dev == dev && s->slots[i].ino == ino)
			return 0;
		i = (i + 1) % s->cap;
	}
	s->slots[i].dev = dev;
	s->slots[i].ino = ino;
	s->slots[i].used = 1;
	s->len++;
	return 1;
}

typedef struct {
	char (*excl)[MNT_PATH];
	int nexcl;
	InoSet set;
	unsigned long long done;
	ScanProgress progress;
	void *ud;
	int aborted;
	char path[SCAN_PATH];
} Scan;

static inline int
scan_excluded(const Scan *s)
{
	int i;

	for (i = 0; i < s->nexcl; i++)
		if (!strcmp(s->path, s->excl[i]))
			return 1;
	return 0;
}

static inline int
scan_tick(Scan *s)
{
	if (s->progress && s->done % 256 == 0 &&
	    s->progress(s->done, s->ud))
		s->aborted = 1;
	s->done++;
	return s->aborted;
}

/* Blocks of one non-directory, hard links counted once per scan. */
static inline unsigned long long
scan_file(Scan *s, const struct stat *st)
{
	if (st->st_nlink > 1 &&
	    !inoset_add(&s->set, (unsigned long long)st->st_dev,
	                (unsigned long long)st->st_ino))
		return 0;
	return (unsigned long long)st->st_blocks * 512;
}

/* Size the directory at s->path (len bytes long) recursively.
 * Never follows symlinks, never enters excluded paths, skips
 * unreadable directories silently. To keep one fd open at a time,
 * each level lists its subdirectories before descending. */
static inline unsigned long long
scan_walk(Scan *s, size_t len)
{
	DIR *d;
	struct dirent *de;
	struct stat st;
	unsigned long long bytes = 0;
	char *subs = NULL, *nsubs;
	size_t nsub = 0, capsub = 0, i, off, nlen;

	if ((d = opendir(s->path)) == NULL)
		return 0;
	while (!s->aborted && (de = readdir(d)) != NULL) {
		if (!strcmp(de->d_name, ".") || !strcmp(de->d_name, ".."))
			continue;
		if (scan_tick(s))
			break;
		nlen = strlen(de->d_name);
		if (len + 1 + nlen + 1 > sizeof s->path)
			continue; /* path too long, skip silently */
		s->path[len] = '/';
		memcpy(s->path + len + 1, de->d_name, nlen + 1);
		if (lstat(s->path, &st) != 0)
			continue;
		if (S_ISDIR(st.st_mode)) {
			if (scan_excluded(s))
				continue;
			bytes += (unsigned long long)st.st_blocks * 512;
			if (nsub + nlen + 1 > capsub) {
				capsub = (capsub + nlen + 64) * 2;
				nsubs = realloc(subs, capsub);
				if (!nsubs)
					continue;
				subs = nsubs;
			}
			memcpy(subs + nsub, de->d_name, nlen + 1);
			nsub += nlen + 1;
		} else {
			bytes += scan_file(s, &st);
		}
	}
	closedir(d);
	for (off = 0; off < nsub && !s->aborted; off += i + 1) {
		i = strlen(subs + off);
		s->path[len] = '/';
		memcpy(s->path + len + 1, subs + off, i + 1);
		bytes += scan_walk(s, len + 1 + i);
	}
	free(subs);
	s->path[len] = '\0';
	return bytes;
}

static inline int
scan_namecmp(const void *a, const void *b)
{
	return strcmp(a, b);
}

/* One Entry per first-level directory under root, scanned in
 * alphabetical order so hard-link attribution is deterministic,
 * plus one "(files)" Entry aggregating loose files in root when any
 * exist. Returns the entry count, or -1 when progress aborted. */
static inline int
scan_root(const char *root, char (*excl)[MNT_PATH], int nexcl,
          Entry *out, int max, ScanProgress progress, void *ud)
{
	Scan s;
	DIR *d;
	struct dirent *de;
	struct stat st;
	char (*names)[SCAN_NAME] = NULL, (*nn)[SCAN_NAME];
	size_t nname = 0, capname = 0, i, len, nlen;
	unsigned long long files = 0;
	int n = 0, nfiles = 0;

	memset(&s, 0, sizeof s);
	s.excl = excl;
	s.nexcl = nexcl;
	s.progress = progress;
	s.ud = ud;
	len = strlen(root);
	if (len + 1 >= sizeof s.path)
		return 0;
	memcpy(s.path, root, len + 1);
	while (len > 1 && s.path[len - 1] == '/')
		s.path[--len] = '\0';
	/* for the root directory itself, children join as "/name",
	 * never "//name", or exclusion paths would not match */
	if (len == 1 && s.path[0] == '/')
		s.path[--len] = '\0';

	if ((d = opendir(len ? s.path : "/")) == NULL)
		return 0;
	while (!s.aborted && (de = readdir(d)) != NULL) {
		if (!strcmp(de->d_name, ".") || !strcmp(de->d_name, ".."))
			continue;
		if (scan_tick(&s))
			break;
		nlen = strlen(de->d_name);
		if (nlen >= SCAN_NAME || len + 1 + nlen + 1 > sizeof s.path)
			continue;
		s.path[len] = '/';
		memcpy(s.path + len + 1, de->d_name, nlen + 1);
		if (lstat(s.path, &st) != 0)
			continue;
		if (S_ISDIR(st.st_mode)) {
			if (scan_excluded(&s))
				continue;
			if (nname == capname) {
				capname = capname ? capname * 2 : 64;
				nn = realloc(names, capname * SCAN_NAME);
				if (!nn)
					continue;
				names = nn;
			}
			memcpy(names[nname++], de->d_name, nlen + 1);
		} else {
			files += scan_file(&s, &st);
			nfiles++;
		}
	}
	closedir(d);
	s.path[len] = '\0';

	if (names)
		qsort(names, nname, SCAN_NAME, scan_namecmp);
	for (i = 0; i < nname && !s.aborted; i++) {
		struct stat dst;
		unsigned long long own = 0;

		nlen = strlen(names[i]);
		s.path[len] = '/';
		memcpy(s.path + len + 1, names[i], nlen + 1);
		if (lstat(s.path, &dst) == 0)
			own = (unsigned long long)dst.st_blocks * 512;
		if (n < max) {
			memcpy(out[n].name, names[i], nlen + 1);
			out[n].bytes = own + scan_walk(&s, len + 1 + nlen);
			n++;
		}
		s.path[len] = '\0';
	}
	free(names);
	free(s.set.slots);
	if (s.aborted)
		return -1;
	if (nfiles > 0 && n < max) {
		memcpy(out[n].name, "(files)", sizeof "(files)");
		out[n].bytes = files;
		n++;
	}
	return n;
}

#endif

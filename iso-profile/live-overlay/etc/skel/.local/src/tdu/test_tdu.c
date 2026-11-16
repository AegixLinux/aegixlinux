/* test_tdu: unit tests for tdu's pure headers */
#define _XOPEN_SOURCE 700
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "bar.h"
#include "fmt.h"
#include "mounts.h"
#include "row.h"
#include "scan.h"

static int ngroups = 0;

static void
ok(const char *name)
{
	ngroups++;
	printf("PASS %s\n", name);
}

static void
test_fmt_size(void)
{
	char b[8];

	fmt_size(0ULL, b, sizeof b);             assert(!strcmp(b, "0B"));
	fmt_size(512ULL, b, sizeof b);           assert(!strcmp(b, "512B"));
	fmt_size(986710016ULL, b, sizeof b);     assert(!strcmp(b, "941M"));
	fmt_size(1073741824ULL, b, sizeof b);    assert(!strcmp(b, "1.0G"));
	fmt_size(334958692991ULL, b, sizeof b);  assert(!strcmp(b, "311G"));
	fmt_size(1649267441664ULL, b, sizeof b); assert(!strcmp(b, "1.5T"));
	ok("fmt_size");
}

static void
test_bar(void)
{
	assert(bar_cells(0.0, 24) == 0);
	assert(bar_cells(1.0, 24) == 24);
	assert(bar_cells(0.67, 24) == 16);
	assert(bar_cells(1.7, 24) == 24);          /* clamp */
	assert(frac_used(0, 0) == 0.0);            /* zero-block fs */
	assert(frac_used(67, 33) == 0.67);
	assert(bar_color(0.69, 0.70, 0.90, 1, 2, 3) == 1);
	assert(bar_color(0.70, 0.70, 0.90, 1, 2, 3) == 2);
	assert(bar_color(0.95, 0.70, 0.90, 1, 2, 3) == 3);
	ok("bar");
}

static void
test_mounts(void)
{
	static const char mtext[] =
	    "/dev/mapper/aegixluks / btrfs rw 0 0\n"
	    "proc /proc proc rw 0 0\n"
	    "/dev/mapper/aegixluks /home btrfs rw 0 0\n"
	    "/dev/nvme0n1p1 /boot vfat rw 0 0\n"
	    "/dev/sdb1 /mnt/my\\040drive ext4 rw 0 0\n"
	    "tmpfs /tmp tmpfs rw 0 0\n";
	Device devs[MNT_MAX];
	char mnts[MNT_MAX][MNT_PATH];
	int n, i, seen = 0;

	n = mounts_parse(mtext, devs, MNT_MAX);
	assert(n == 3);
	assert(!strcmp(devs[0].src, "/dev/mapper/aegixluks"));
	assert(!strcmp(devs[0].name, "aegixluks"));
	assert(!strcmp(devs[0].mnt, "/"));
	assert(!strcmp(devs[0].extra, " +/home"));
	assert(!strcmp(devs[1].name, "nvme0n1p1"));
	assert(!strcmp(devs[1].extra, ""));
	assert(!strcmp(devs[2].mnt, "/mnt/my drive")); /* \040 unescaped */

	n = mounts_all(mtext, mnts, MNT_MAX);
	assert(n == 6);
	for (i = 0; i < n; i++)
		if (!strcmp(mnts[i], "/proc") || !strcmp(mnts[i], "/tmp") ||
		    !strcmp(mnts[i], "/mnt/my drive"))
			seen++;
	assert(seen == 3);
	ok("mounts");
}

static void
mkfile(const char *root, const char *rel, size_t kb)
{
	char p[512], buf[1024];
	FILE *f;
	size_t i;

	memset(buf, 'x', sizeof buf);
	snprintf(p, sizeof p, "%s/%s", root, rel);
	f = fopen(p, "w");
	assert(f);
	for (i = 0; i < kb; i++)
		assert(fwrite(buf, 1, sizeof buf, f) == sizeof buf);
	assert(fclose(f) == 0);
}

static unsigned long long
entry_bytes(const Entry *e, int n, const char *name)
{
	int i;

	for (i = 0; i < n; i++)
		if (!strcmp(e[i].name, name))
			return e[i].bytes;
	assert(!"entry not found");
	return 0;
}

static int
abort_cb(unsigned long long done, void *ud)
{
	(void)done;
	(void)ud;
	return 1;
}

static int
cap_cb(unsigned long long done, void *ud)
{
	(void)ud;
	return done > 5000; /* a correctly excluded scan stays tiny */
}

/* Exclusion must hold when the scan root is "/" itself: paths are
 * joined as "/name", not "//name", or the mount-table boundary list
 * never matches and the drill crosses into /proc and sibling
 * devices. */
static void
test_scan_rootfs(void)
{
	static char excl[256][MNT_PATH];
	DIR *d;
	struct dirent *de;
	Entry e[16];
	int nx = 0, n, i;

	d = opendir("/");
	assert(d);
	while ((de = readdir(d)) != NULL && nx < 256) {
		if (!strcmp(de->d_name, ".") || !strcmp(de->d_name, ".."))
			continue;
		snprintf(excl[nx], MNT_PATH, "/%.250s", de->d_name);
		nx++;
	}
	closedir(d);
	n = scan_root("/", excl, nx, e, 16, cap_cb, NULL);
	assert(n >= 0); /* excluded everything, so no deep descent */
	for (i = 0; i < n; i++)
		assert(!strcmp(e[i].name, "(files)"));
	ok("scan rootfs exclusion");
}

static void
test_scan(void)
{
	char root[] = "/tmp/tdu-test-XXXXXX";
	char p1[512], p2[512];
	char excl[1][MNT_PATH];
	Entry e[16];
	unsigned long long a, b, c, files;
	int n;

	assert(mkdtemp(root));
	snprintf(p1, sizeof p1, "%s/a", root);      assert(mkdir(p1, 0755) == 0);
	snprintf(p1, sizeof p1, "%s/a/sub", root);  assert(mkdir(p1, 0755) == 0);
	snprintf(p1, sizeof p1, "%s/b", root);      assert(mkdir(p1, 0755) == 0);
	snprintf(p1, sizeof p1, "%s/c", root);      assert(mkdir(p1, 0755) == 0);
	mkfile(root, "a/big", 200);
	mkfile(root, "a/sub/mid", 100);
	mkfile(root, "b/small", 50);
	mkfile(root, "top", 10);
	snprintf(p1, sizeof p1, "%s/a/big", root);
	snprintf(p2, sizeof p2, "%s/b/biglink", root);
	assert(link(p1, p2) == 0);
	snprintf(p1, sizeof p1, "%s/a", root);
	snprintf(p2, sizeof p2, "%s/c/loop", root);
	assert(symlink(p1, p2) == 0);

	n = scan_root(root, NULL, 0, e, 16, NULL, NULL);
	assert(n == 4); /* a, b, c, (files) */
	a = entry_bytes(e, n, "a");
	b = entry_bytes(e, n, "b");
	c = entry_bytes(e, n, "c");
	files = entry_bytes(e, n, "(files)");
	assert(a >= 300 * 1024ULL && a < 340 * 1024ULL);
	assert(b >= 50 * 1024ULL && b < 70 * 1024ULL);  /* biglink deduped */
	assert(c < 16 * 1024ULL);                       /* symlink not followed */
	assert(files >= 10 * 1024ULL && files < 20 * 1024ULL);

	qsort(e, (size_t)n, sizeof *e, entry_cmp);
	assert(!strcmp(e[0].name, "a"));                /* largest first */
	assert(entry_bytes(e, 1, "a") == a);

	/* drill-down bars scale to the largest entry */
	assert(bar_cells((double)e[0].bytes / (double)e[0].bytes, 24) == 24);
	assert(bar_cells((double)e[2].bytes / (double)e[0].bytes, 24) < 24);

	snprintf(excl[0], sizeof excl[0], "%s/a/sub", root);
	n = scan_root(root, excl, 1, e, 16, NULL, NULL);
	a = entry_bytes(e, n, "a");
	assert(a >= 200 * 1024ULL && a < 240 * 1024ULL); /* mid excluded */

	assert(scan_root(root, NULL, 0, e, 16, abort_cb, NULL) == -1);
	ok("scan");
}

static void
test_row(void)
{
	Device d;
	Stats s;
	char out[128];

	/* selection keys: digits, then letters skipping q and r */
	assert(key_for_row(0) == '1' && key_for_row(8) == '9');
	assert(key_for_row(9) == 'a');
	assert(key_for_row(25) == 's' && key_for_row(26) == 't');
	assert(row_for_key('2', 5) == 1 && row_for_key('q', 5) == -1);
	assert(row_for_key('a', 5) == -1); /* only 5 rows, a is row 9 */

	memset(&d, 0, sizeof d);
	strcpy(d.src, "/dev/mapper/aegixluks");
	strcpy(d.name, "aegixluks");
	strcpy(d.mnt, "/");
	strcpy(d.extra, " +/home");
	s.total = 1007ULL << 30;
	s.used = 671ULL << 30;
	s.avail = 331ULL << 30;
	row_render(&d, &s, 0, 100, out, sizeof out);
	assert(strstr(out, "1") && strstr(out, "aegixluks"));
	assert(strstr(out, "+/home"));
	assert(strstr(out, "[") && strstr(out, "%") && strstr(out, "free"));
	assert(strlen(out) <= 100);
	row_render(&d, &s, 0, 48, out, sizeof out);
	assert(strlen(out) <= 48 && !strstr(out, "free") && strstr(out, "["));
	ok("row");
}

int
main(void)
{
	test_fmt_size();
	test_bar();
	test_mounts();
	test_row();
	test_scan();
	test_scan_rootfs();
	printf("%d test groups passed\n", ngroups);
	return 0;
}

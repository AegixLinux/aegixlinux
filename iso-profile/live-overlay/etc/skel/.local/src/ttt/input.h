/* input.h: digit entry state machine for ttt, shared by ttt.c and tests */
#ifndef INPUT_H
#define INPUT_H

/* seconds a lone digit waits before committing */
#define INPUT_TIMEOUT 1.5

typedef struct {
	int len;
	char buf[3];
	double last; /* time of last keypress */
} Input;

static void
input_init(Input *in)
{
	in->len = 0;
	in->last = 0;
}

static int
input_commit(Input *in)
{
	int v = 0, i;

	for (i = 0; i < in->len; i++)
		v = v * 10 + (in->buf[i] - '0');
	in->len = 0;
	return (v >= 1 && v <= 60) ? v : 0;
}

/* Feed one key pressed at time t (seconds, any monotonic base).
 * Returns minutes 1..60 when an entry commits, 0 otherwise.
 * Invalid entries (0, over 60) are discarded silently. */
static int
input_feed(Input *in, int ch, double t)
{
	if (ch >= '0' && ch <= '9') {
		if (in->len < 2) {
			in->buf[in->len++] = (char)ch;
			in->last = t;
		}
		if (in->len == 2)
			return input_commit(in);
		return 0;
	}
	if ((ch == '\r' || ch == '\n') && in->len > 0)
		return input_commit(in);
	return 0;
}

/* Call periodically with the current time. Commits a pending
 * single digit after INPUT_TIMEOUT. Same return as input_feed. */
static int
input_tick(Input *in, double t)
{
	if (in->len > 0 && t - in->last >= INPUT_TIMEOUT)
		return input_commit(in);
	return 0;
}

#endif

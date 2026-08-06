#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <time.h>
#include <signal.h>
#include <errno.h>
#include <X11/Xlib.h>
#define LENGTH(X) (sizeof(X) / sizeof (X[0]))
#define CMDLENGTH		50

typedef struct {
	char* icon;
	char* command;
	unsigned int interval;
	unsigned int signal;
} Block;
void sighandler(int num);
void buttonhandler(int sig, siginfo_t *si, void *ucontext);
void replace(char *str, char old, char new);
void remove_all(char *str, char to_remove);
void getcmds(int time);
#ifndef __OpenBSD__
void getsigcmds(int signal);
void setupsignals();
void sighandler(int signum);
void drainsignals();
#else
#define drainsignals() ((void)0)
#endif
int getstatus(char *str, char *last);
void setroot();
void statusloop();
void termhandler(int signum);


#include "config.h"

static Display *dpy;
static int screen;
static Window root;
static char statusbar[LENGTH(blocks)][CMDLENGTH] = {0};
static char statusstr[2][256];
static int statusContinue = 1;
static void (*writestatus) () = setroot;

#ifndef __OpenBSD__
/* Signal handlers must not do the work themselves.
 *
 * getcmd() calls popen()/fgets()/pclose() and setroot() calls into Xlib; none
 * of those are async-signal-safe. Doing them inside a handler means that when a
 * signal lands while the main loop is already inside one of them, the handler
 * re-enters it on the same thread and blocks on a non-recursive glibc/libX11
 * mutex that only that -- now blocked -- thread could release. The bar then
 * hangs forever, frozen at whatever it last displayed, parked in futex_do_wait
 * with the nested signals stuck in SigBlk.
 *
 * So the handler now only records which signals arrived, and statusloop() does
 * the real work from normal context. Writing a volatile sig_atomic_t is the one
 * thing a handler may always safely do.
 *
 * Indexed by (signum - SIGRTMIN). Fixed size because SIGRTMIN/SIGRTMAX are not
 * compile-time constants on glibc; block signals are single/double digit, and
 * out-of-range values are simply ignored. */
#define MAXSIGSLOTS 64
static volatile sig_atomic_t sigpending_slot[MAXSIGSLOTS];
static volatile sig_atomic_t sigpending_any;
#endif

void replace(char *str, char old, char new)
{
	for(char * c = str; *c; c++)
		if(*c == old)
			*c = new;
}

// the previous function looked nice but unfortunately it didnt work if to_remove was in any position other than the last character
// theres probably still a better way of doing this
void remove_all(char *str, char to_remove) {
	char *read = str;
	char *write = str;
	while (*read) {
		if (*read != to_remove) {
			*write++ = *read;
		}
		++read;
	}
	*write = '\0';
}

int gcd(int a, int b)
{
	int temp;
	while (b > 0){
		temp = a % b;

		a = b;
		b = temp;
	}
	return a;
}


//opens process *cmd and stores output in *output
void getcmd(const Block *block, char *output)
{
	if (block->signal)
	{
		output[0] = block->signal;
		output++;
	}
	char *cmd = block->command;
	FILE *cmdf = popen(cmd,"r");
	if (!cmdf){
        //printf("failed to run: %s, %d\n", block->command, errno);
		return;
    }
    char tmpstr[CMDLENGTH] = "";
    // TODO decide whether its better to use the last value till next time or just keep trying while the error was the interrupt
    // this keeps trying to read if it got nothing and the error was an interrupt
    //  could also just read to a separate buffer and not move the data over if interrupted
    //  this way will take longer trying to complete 1 thing but will get it done
    //  the other way will move on to keep going with everything and the part that failed to read will be wrong till its updated again
    // either way you have to save the data to a temp buffer because when it fails it writes nothing and then then it gets displayed before this finishes
	char * s;
    int e;
    do {
        errno = 0;
        s = fgets(tmpstr, CMDLENGTH-(strlen(delim)+1), cmdf);
        e = errno;
    } while (!s && e == EINTR);
	pclose(cmdf);
	int i = strlen(block->icon);
	strcpy(output, block->icon);
    strcpy(output+i, tmpstr);
	remove_all(output, '\n');
	i = strlen(output);
    if ((i > 0 && block != &blocks[LENGTH(blocks) - 1])){
        strcat(output, delim);
    }
    i+=strlen(delim);
	output[i++] = '\0';
}

void getcmds(int time)
{
	const Block* current;
	for(int i = 0; i < LENGTH(blocks); i++)
	{
		current = blocks + i;
		if ((current->interval != 0 && time % current->interval == 0) || time == -1){
			getcmd(current,statusbar[i]);
        }
	}
}

#ifndef __OpenBSD__
void getsigcmds(int signal)
{
	const Block *current;
	for (int i = 0; i < LENGTH(blocks); i++)
	{
		current = blocks + i;
		if (current->signal == signal){
			getcmd(current,statusbar[i]);
        }
	}
}

void setupsignals()
{
	struct sigaction sa;
	struct sigaction block_sa;

	for(int i = SIGRTMIN; i <= SIGRTMAX; i++)
		signal(i, SIG_IGN);

	/* Installed without SA_RESTART on purpose. signal(3) would set it, and a
	 * restarted nanosleep(2) would resume for its remaining time without ever
	 * returning to the loop -- so a flagged update could sit unhandled for up
	 * to one interval. Letting nanosleep fail with EINTR wakes statusloop()
	 * immediately, which is what keeps signal-driven blocks feeling instant
	 * now that the handler no longer refreshes them itself. */
	memset(&block_sa, 0, sizeof(block_sa));
	block_sa.sa_handler = sighandler;
	sigemptyset(&block_sa.sa_mask);
	block_sa.sa_flags = 0;

	memset(&sa, 0, sizeof(sa));
	sigemptyset(&sa.sa_mask);

	for(int i = 0; i < LENGTH(blocks); i++)
	{
		if (blocks[i].signal > 0)
		{
			sigaction(SIGRTMIN+blocks[i].signal, &block_sa, NULL);
			sigaddset(&sa.sa_mask, SIGRTMIN+blocks[i].signal);
		}
	}
	sa.sa_sigaction = buttonhandler;
	sa.sa_flags = SA_SIGINFO;
	sigaction(SIGUSR1, &sa, NULL);
	struct sigaction sigchld_action = {
  		.sa_handler = SIG_DFL,
  		.sa_flags = SA_NOCLDWAIT
	};
	sigaction(SIGCHLD, &sigchld_action, NULL);

}
#endif

int getstatus(char *str, char *last)
{
	strcpy(last, str);
	str[0] = '\0';
	// Add leading separator for center section
	if (center_delim_after >= 0)
		strcat(str, "│ ");
    for(int i = 0; i < LENGTH(blocks); i++) {
		strcat(str, statusbar[i]);
		// Insert center delimiter after specified block (delim already added by getcmd)
		if (center_delim_after >= 0 && i == center_delim_after)
			strcat(str, ";;│ ");
        if (i == LENGTH(blocks) - 1)
            strcat(str, "│");  // trailing separator
    }
	return strcmp(str, last);//0 if they are the same
}

/* Opened once in main() and reused for the life of the process.
 *
 * This used to XOpenDisplay()/XCloseDisplay() on every single update, which
 * meant the process sat inside Xlib's connection setup -- holding libX11's
 * global lock -- several times a second, widening the window for the
 * re-entrancy hang described above. It was also unsound on its own terms: when
 * XOpenDisplay() failed it left dpy pointing at the display it had just closed
 * and used it anyway, then closed it a second time. */
void setroot()
{
	if (!getstatus(statusstr[0], statusstr[1]))//Only set root if text has changed.
		return;
	XStoreName(dpy, root, statusstr[0]);
	XFlush(dpy);
}

void pstdout()
{
	if (!getstatus(statusstr[0], statusstr[1]))//Only write out if text has changed.
		return;
	printf("%s\n",statusstr[0]);
	fflush(stdout);
}


void statusloop()
{
#ifndef __OpenBSD__
	setupsignals();
#endif
    // first figure out the default wait interval by finding the
    // greatest common denominator of the intervals
    unsigned int interval = -1;
    for(int i = 0; i < LENGTH(blocks); i++){
        if(blocks[i].interval){
            interval = gcd(blocks[i].interval, interval);
        }
    }
	unsigned int i = 0;
    int interrupted = 0;
    const struct timespec sleeptime = {interval, 0};
    struct timespec tosleep = sleeptime;
	getcmds(-1);
	while(statusContinue)
	{
        // sleep for tosleep (should be a sleeptime of interval seconds) and put what was left if interrupted back into tosleep
        interrupted = nanosleep(&tosleep, &tosleep);
        // if interrupted then service whatever signal woke us, then sleep out the remainder
        if(interrupted == -1){
            drainsignals();
            continue;
        }
        // if not interrupted then do the calling and writing
        drainsignals();
        getcmds(i);
        writestatus();
        // then increment since its actually been a second (plus the time it took the commands to run)
        i += interval;
        // set the time to sleep back to the sleeptime of 1s
        tosleep = sleeptime;
	}
}

#ifndef __OpenBSD__
/* Async-signal-safe: records the signal and returns. All refreshing happens in
 * drainsignals(), called from statusloop(). See the comment on
 * sigpending_slot[] for why doing the work here deadlocks. */
void sighandler(int signum)
{
	int slot = signum - SIGRTMIN;

	if (slot >= 0 && slot < MAXSIGSLOTS)
		sigpending_slot[slot] = 1;
	sigpending_any = 1;
}

/* Runs the blocks flagged by sighandler(), from normal context. */
void drainsignals()
{
	int updated = 0;

	if (!sigpending_any)
		return;
	sigpending_any = 0;

	for (int slot = 0; slot < MAXSIGSLOTS; slot++)
	{
		if (!sigpending_slot[slot])
			continue;
		/* Cleared before the refresh, so a signal arriving during it is
		 * kept rather than lost. */
		sigpending_slot[slot] = 0;
		getsigcmds(slot);
		updated = 1;
	}

	if (updated)
		writestatus();
}

void buttonhandler(int sig, siginfo_t *si, void *ucontext)
{
	char button[2] = {'0' + si->si_value.sival_int & 0xff, '\0'};
	pid_t process_id = getpid();
	sig = si->si_value.sival_int >> 8;
	if (fork() == 0)
	{
		const Block *current;
		for (int i = 0; i < LENGTH(blocks); i++)
		{
			current = blocks + i;
			if (current->signal == sig)
				break;
		}
		char shcmd[1024];
		sprintf(shcmd,"%s && kill -%d %d",current->command, current->signal+34,process_id);
		char *command[] = { "/bin/sh", "-c", shcmd, NULL };
		setenv("BLOCK_BUTTON", button, 1);
		setsid();
		execvp(command[0], command);
		exit(EXIT_SUCCESS);
	}
}

#endif

/* _exit(2), not exit(3): exit() runs atexit handlers and flushes stdio, neither
 * of which is async-signal-safe, so a SIGTERM arriving mid-popen could wedge the
 * process on the way out for the same reason the status updates used to. Nothing
 * here needs flushing -- pstdout() already fflush()es each line. */
void termhandler(int signum)
{
	statusContinue = 0;
	_exit(0);
}

int main(int argc, char** argv)
{
	for(int i = 0; i < argc; i++)
	{
		if (!strcmp("-d",argv[i]))
			delim = argv[++i];
		else if(!strcmp("-p",argv[i]))
			writestatus = pstdout;
	}
	/* Only the X writer needs a display; -p just prints to stdout, and should
	 * still work with no X server around. */
	if (writestatus == setroot)
	{
		dpy = XOpenDisplay(NULL);
		if (!dpy)
		{
			fprintf(stderr, "dwmblocks: cannot open display\n");
			return 1;
		}
		screen = DefaultScreen(dpy);
		root = RootWindow(dpy, screen);
	}
	signal(SIGTERM, termhandler);
	signal(SIGINT, termhandler);
	statusloop();
	if (dpy)
		XCloseDisplay(dpy);
	return 0;
}

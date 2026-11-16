/*
 * Portable stopwatch utility - uses standard POSIX headers and system calls:
 * - Standard C library headers (stdio.h, stdlib.h, string.h)
 * - POSIX terminal control (termios.h, unistd.h, fcntl.h)
 * - Standard time functions (sys/time.h, signal.h)
 * Should compile and run on any Unix-like system (Linux, macOS, BSD variants)
 */
#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <time.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/time.h>
#include <termios.h>
#include <fcntl.h>
#include <signal.h>
#include <string.h>

struct termios orig_termios;
int cleanup_done = 0;

void restore_terminal() {
    if (cleanup_done) return;
    cleanup_done = 1;
    tcsetattr(STDIN_FILENO, TCSAFLUSH, &orig_termios);
    printf("\nstopped\n");
}

void signal_handler(int sig) {
    (void)sig;
    restore_terminal();
    exit(0);
}

void setup_terminal() {
    tcgetattr(STDIN_FILENO, &orig_termios);
    atexit(restore_terminal);
    signal(SIGINT, signal_handler);
    signal(SIGTERM, signal_handler);
    
    struct termios raw = orig_termios;
    raw.c_lflag &= ~(ECHO | ICANON);
    tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw);
    
    int flags = fcntl(STDIN_FILENO, F_GETFL, 0);
    fcntl(STDIN_FILENO, F_SETFL, flags | O_NONBLOCK);
}

long long get_time_ms() {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return (long long)tv.tv_sec * 1000 + tv.tv_usec / 1000;
}

void format_time(long long ms, int *h, int *m, int *s, int *millisec) {
    *h = ms / 3600000;
    *m = (ms % 3600000) / 60000;
    *s = (ms % 60000) / 1000;
    *millisec = ms % 1000;
}

int main(int argc, char *argv[]) {
    if (argc > 1) {
        if (strcmp(argv[1], "--help") == 0 || strcmp(argv[1], "-h") == 0) {
            printf("aegix stopwatch 🐧\n\n");
            printf("USAGE:\n");
            printf("  stopwatch\n\n");
            printf("CONTROLS:\n");
            printf("  p        pause/resume\n");
            printf("  enter    create split\n");
            printf("  ctrl+c   stop\n\n");
            printf("DISPLAY:\n");
            printf("  HH:MM:SS.mmm [HH:MM:SS.mmm]\n");
            printf("  total time   [split time]\n\n");
            printf("PORTABILITY:\n");
            printf("  Uses standard POSIX headers and system calls:\n");
            printf("  - Standard C library headers (stdio.h, stdlib.h, string.h)\n");
            printf("  - POSIX terminal control (termios.h, unistd.h, fcntl.h)\n");
            printf("  - Standard time functions (sys/time.h, signal.h)\n");
            printf("  Should compile and run on any Unix-like system (Linux, macOS, BSD)\n\n");
            return 0;
        }
    }
    
    setup_terminal();
    
    printf("aegix stopwatch 🐧\n");
    printf("started\n");
    printf("'p' to pause, ctrl+c to stop, enter for new line\n\n");
    
    long long start_time = get_time_ms();
    long long split_time = start_time;
    long long pause_duration = 0;
    int paused = 0;
    long long pause_start = 0;
    int paused_h, paused_m, paused_s, paused_ms;
    
    while (1) {
        long long current_time = get_time_ms();
        long long elapsed = current_time - start_time - pause_duration;
        long long split_elapsed = current_time - split_time;
        
        int h, m, s, ms, sh, sm, ss, sms;
        format_time(elapsed, &h, &m, &s, &ms);
        format_time(split_elapsed, &sh, &sm, &ss, &sms);
        
        char c;
        if (read(STDIN_FILENO, &c, 1) > 0) {
            if (c == 'p') {
                if (!paused) {
                    paused = 1;
                    pause_start = current_time;
                    // Store the current time values when pausing
                    paused_h = h;
                    paused_m = m;
                    paused_s = s;
                    paused_ms = ms;
                } else {
                    paused = 0;
                    long long pause_length = current_time - pause_start;
                    pause_duration += pause_length;
                    split_time += pause_length;  // Adjust split_time to account for pause
                }
            } else if (c == '\n' || c == '\r') {
                if (!paused) {
                    printf("\nsplit: %02d:%02d:%02d.%03d\n\n", sh, sm, ss, sms);
                    split_time = current_time;
                }
            }
        }
        
        if (paused) {
            printf("\r⏸  PAUSED %02d:%02d:%02d.%03d - press 'p' to resume", paused_h, paused_m, paused_s, paused_ms);
        } else {
            printf("\r%02d:%02d:%02d.%03d [%02d:%02d:%02d.%03d]                    ", h, m, s, ms, sh, sm, ss, sms);
        }
        fflush(stdout);
        
        struct timespec tick = {0, 10000000}; /* 10ms */
        nanosleep(&tick, NULL);
    }
    
    return 0;
}
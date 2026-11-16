# ttt - terminal time timer
# See LICENSE file for copyright and license details.

PREFIX = /usr/local
CC = cc
CFLAGS = -std=c99 -pedantic -Wall -Wextra -Os
LDLIBS = -lm

all: ttt ttt-flash stopwatch

ttt: ttt.c config.h dial.h input.h
	$(CC) $(CFLAGS) -o $@ ttt.c $(LDLIBS)

ttt-flash: ttt-flash.c
	$(CC) $(CFLAGS) -o $@ ttt-flash.c -lX11

stopwatch: stopwatch.c
	$(CC) $(CFLAGS) -o $@ stopwatch.c

test: test_ttt
	./test_ttt

test_ttt: test_ttt.c dial.h input.h
	$(CC) $(CFLAGS) -o $@ test_ttt.c $(LDLIBS)

install: all
	mkdir -p $(DESTDIR)$(PREFIX)/bin
	cp -f ttt ttt-flash stopwatch $(DESTDIR)$(PREFIX)/bin
	chmod 755 $(DESTDIR)$(PREFIX)/bin/ttt $(DESTDIR)$(PREFIX)/bin/ttt-flash $(DESTDIR)$(PREFIX)/bin/stopwatch

uninstall:
	rm -f $(DESTDIR)$(PREFIX)/bin/ttt $(DESTDIR)$(PREFIX)/bin/ttt-flash $(DESTDIR)$(PREFIX)/bin/stopwatch

clean:
	rm -f ttt ttt-flash stopwatch test_ttt

.PHONY: all test install uninstall clean

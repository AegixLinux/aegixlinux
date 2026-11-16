# tdu - terminal disk usage
# See LICENSE file for copyright and license details.

PREFIX = /usr/local
CC = cc
CFLAGS = -std=c99 -pedantic -Wall -Wextra -Os

all: tdu

tdu: tdu.c config.h fmt.h bar.h mounts.h row.h scan.h
	$(CC) $(CFLAGS) -o $@ tdu.c

test: test_tdu
	./test_tdu

test_tdu: test_tdu.c fmt.h bar.h mounts.h row.h scan.h
	$(CC) $(CFLAGS) -o $@ test_tdu.c

install: all
	mkdir -p $(DESTDIR)$(PREFIX)/bin
	cp -f tdu $(DESTDIR)$(PREFIX)/bin
	chmod 755 $(DESTDIR)$(PREFIX)/bin/tdu

uninstall:
	rm -f $(DESTDIR)$(PREFIX)/bin/tdu

clean:
	rm -f tdu test_tdu

.PHONY: all test install uninstall clean

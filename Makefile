CFLAGS=-std=c99 -pedantic -Wall -Wextra -Werror

bin/sha3-256sum:
	cd third-party/libkeccak && $(MAKE) libkeccak.a
	cd third-party/sha3sum && $(MAKE) sha3-256sum \
		'CFLAGS=-std=c99 -Wall -Wextra $$(WARN) -O3 -I../libkeccak/' \
		'LDFLAGS=-s -lkeccak -L../libkeccak/'
	mkdir -p bin
	cp third-party/sha3sum/sha3-256sum $@

bin/nar: src/nar.c src/common.h
	$(CC) $(CFLAGS) -o $@ $<

bin/base24: src/base24.c src/common.h
	$(CC) $(CFLAGS) -o $@ $<

/* SPDX-License-Identifier: GPL-2.0-or-later
 * Copyright (c) 2026 Alexander Medvednikov
 *
 * Whole-filesystem persistence, as PID 1. A machine booted from its disk has
 * to keep a write made anywhere, not only one made below /root: this writes
 * into /etc, which on a RAM root is thrown away with the rest of the image,
 * restarts with reboot(2), and requires the file back afterwards.
 *
 * It also checks that the root really is the volume rather than the initramfs
 * the kernel falls back to, so a silent fallback fails the test instead of
 * passing it on a RAM root that happens to survive within one boot.
 */
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/reboot.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

static const char *marker = "/etc/vinix-disk-root";
static const char *installed = "/.vinix-image-id";
static const char payload[] = "vinix-disk-root-v1";
/* A file the host put on the volume, big enough to need indirect blocks. Its
 * bytes are a function of their offset, so a read that goes wrong reports
 * exactly where rather than only that it did. Executables and shared libraries
 * are how this would otherwise surface: the first pages are right, the loader
 * gets its headers, and the symbol table further in is zeroes. */
static const char *large = "/usr/share/vinix-large";
static const unsigned long large_bytes = 3u * 1024u * 1024u;

static unsigned char large_byte(unsigned long offset)
{
	return (unsigned char)((offset * 1103515245u + 12345u) >> 16);
}

static void say(const char *text)
{
	fputs(text, stdout);
	fflush(stdout);
}

/* The runner writes this into the volume when it installs the system, and
 * nothing puts it in the initramfs, so it is what tells the two apart. */
static int booted_from_disk(void)
{
	int fd = open(installed, O_RDONLY);
	if (fd < 0)
		return 0;
	close(fd);
	return 1;
}

static int write_marker(void)
{
	int fd = open(marker, O_CREAT | O_EXCL | O_WRONLY, 0644);
	if (fd < 0) {
		printf("VINIX DISK ROOT: FAIL create errno=%d\n", errno);
		return 1;
	}
	if (write(fd, payload, sizeof(payload) - 1) != (ssize_t)(sizeof(payload) - 1)) {
		printf("VINIX DISK ROOT: FAIL write errno=%d\n", errno);
		return 1;
	}
	if (close(fd) != 0) {
		printf("VINIX DISK ROOT: FAIL close errno=%d\n", errno);
		return 1;
	}
	return 0;
}

static int read_marker(void)
{
	char observed[sizeof(payload)] = {0};
	int fd = open(marker, O_RDONLY);
	if (fd < 0)
		return -1;
	ssize_t got = read(fd, observed, sizeof(observed));
	close(fd);
	if (got != (ssize_t)(sizeof(payload) - 1) ||
	    memcmp(observed, payload, sizeof(payload) - 1) != 0)
		return -1;
	return 0;
}

/* Read it twice: once straight through, and once with the whole file mapped,
 * because a shared library arrives through mmap rather than through read(). */
static int verify_large(void)
{
	static unsigned char buffer[65536];
	int fd = open(large, O_RDONLY);
	if (fd < 0) {
		printf("VINIX DISK ROOT: FAIL large open errno=%d\n", errno);
		return 1;
	}
	unsigned long offset = 0;
	for (;;) {
		ssize_t got = read(fd, buffer, sizeof(buffer));
		if (got < 0) {
			printf("VINIX DISK ROOT: FAIL large read errno=%d\n", errno);
			close(fd);
			return 1;
		}
		if (got == 0)
			break;
		for (ssize_t i = 0; i < got; ++i) {
			if (buffer[i] != large_byte(offset + (unsigned long)i)) {
				printf("VINIX DISK ROOT: FAIL large read differs at %lu\n",
				    offset + (unsigned long)i);
				close(fd);
				return 1;
			}
		}
		offset += (unsigned long)got;
	}
	if (offset != large_bytes) {
		printf("VINIX DISK ROOT: FAIL large is %lu bytes, not %lu\n",
		    offset, large_bytes);
		close(fd);
		return 1;
	}

	unsigned char *mapped = mmap(NULL, large_bytes, PROT_READ, MAP_PRIVATE, fd, 0);
	close(fd);
	if (mapped == MAP_FAILED) {
		printf("VINIX DISK ROOT: FAIL large mmap errno=%d\n", errno);
		return 1;
	}
	for (unsigned long i = 0; i < large_bytes; ++i) {
		if (mapped[i] != large_byte(i)) {
			printf("VINIX DISK ROOT: FAIL large mmap differs at %lu\n", i);
			munmap(mapped, large_bytes);
			return 1;
		}
	}
	munmap(mapped, large_bytes);

	/* A mapping that reaches past the end of the file is what every dynamic
	 * loader makes: one span over all of an object's segments, whose last one
	 * ends mid-page. Refusing it makes every shared library on the volume
	 * unloadable, which is how this was found -- as a shell that started and
	 * then could not resolve a single symbol. */
	fd = open(large, O_RDONLY);
	if (fd < 0) {
		printf("VINIX DISK ROOT: FAIL large reopen errno=%d\n", errno);
		return 1;
	}
	unsigned long past = large_bytes + 128 * 1024;
	mapped = mmap(NULL, past, PROT_READ | PROT_EXEC, MAP_PRIVATE, fd, 0);
	close(fd);
	if (mapped == MAP_FAILED) {
		printf("VINIX DISK ROOT: FAIL mmap past the end errno=%d\n", errno);
		return 1;
	}
	for (unsigned long i = 0; i < large_bytes; ++i) {
		if (mapped[i] != large_byte(i)) {
			printf("VINIX DISK ROOT: FAIL over-long mmap differs at %lu\n", i);
			munmap(mapped, past);
			return 1;
		}
	}
	munmap(mapped, past);
	say("VINIX DISK ROOT: LARGE FILE OK\n");
	return 0;
}

int main(void)
{
	setbuf(stdout, NULL);
	int console = open("/dev/console", O_WRONLY);
	if (console >= 0) {
		dup2(console, STDOUT_FILENO);
		dup2(console, STDERR_FILENO);
		if (console > STDERR_FILENO)
			close(console);
	}
	say("VINIX DISK ROOT: START\n");

	if (!booted_from_disk()) {
		say("VINIX DISK ROOT: FAIL booted from the initramfs, not the volume\n");
		return 1;
	}
	say("VINIX DISK ROOT: ON VOLUME\n");

	/* /tmp and /run are deliberately RAM: a disk root must not turn scratch
	 * into state that accumulates across every boot the machine ever makes. */
	struct stat scratch;
	if (stat("/tmp", &scratch) != 0 || !S_ISDIR(scratch.st_mode) ||
	    stat("/run", &scratch) != 0 || !S_ISDIR(scratch.st_mode)) {
		say("VINIX DISK ROOT: FAIL /tmp or /run is not a directory\n");
		return 1;
	}
	if (open("/tmp/vinix-scratch", O_CREAT | O_WRONLY, 0644) < 0) {
		say("VINIX DISK ROOT: FAIL /tmp is not writable\n");
		return 1;
	}

	if (verify_large() != 0)
		return 1;

	int found = read_marker();
	if (found == 0) {
		say("VINIX DISK ROOT: PASS\n");
		unlink(marker);
		sync();
		reboot(RB_POWER_OFF);
		say("VINIX DISK ROOT: FAIL power off refused\n");
		return 1;
	}
	if (errno != ENOENT && errno != 0) {
		printf("VINIX DISK ROOT: FAIL marker unreadable errno=%d\n", errno);
		return 1;
	}
	if (write_marker() != 0)
		return 1;
	/* No fsync and no O_SYNC: the restart is what has to get this out. */
	say("VINIX DISK ROOT: WROTE /etc MARKER, REBOOTING\n");
	reboot(RB_AUTOBOOT);
	printf("VINIX DISK ROOT: FAIL reboot returned errno=%d\n", errno);
	return 1;
}

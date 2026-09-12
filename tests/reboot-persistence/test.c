/* SPDX-License-Identifier: GPL-2.0-or-later
 * Copyright (c) 2026 Alexander Medvednikov
 *
 * The user-visible persistence contract, as PID 1: create a file in /root the
 * way a shell does -- buffered, closed, no O_SYNC and no fsync -- and then
 * restart the machine with reboot(2). The file has to still be there.
 *
 * This is one QEMU process throughout: the guest resets itself, so the reboot
 * path is what has to get the write to the disk, not a second launch.
 */
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/reboot.h>
#include <unistd.h>

static const char *marker = "/root/hello.txt";
static const char payload[] = "vinix-reboot-persistence-v1";

static void say(const char *text)
{
	fputs(text, stdout);
	fflush(stdout);
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
	say("VINIX REBOOT PERSISTENCE: START\n");

	int fd = open(marker, O_RDONLY);
	if (fd >= 0) {
		char observed[sizeof(payload)] = {0};
		ssize_t got = read(fd, observed, sizeof(observed));
		close(fd);
		if (got != (ssize_t)(sizeof(payload) - 1) ||
		    memcmp(observed, payload, sizeof(payload) - 1) != 0) {
			say("VINIX REBOOT PERSISTENCE: FAIL corrupt marker\n");
			return 1;
		}
		unlink(marker);
		/* Bracketed so a sync(2) that never returns is a failed run rather
		 * than a silent one: this is the call busybox reboot makes first. */
		say("VINIX REBOOT PERSISTENCE: SYNCING\n");
		sync();
		say("VINIX REBOOT PERSISTENCE: PASS\n");
		reboot(RB_POWER_OFF);
		say("VINIX REBOOT PERSISTENCE: FAIL power off refused\n");
		return 1;
	}
	if (errno != ENOENT) {
		printf("VINIX REBOOT PERSISTENCE: FAIL open errno=%d\n", errno);
		return 1;
	}

	fd = open(marker, O_CREAT | O_EXCL | O_WRONLY, 0600);
	if (fd < 0) {
		printf("VINIX REBOOT PERSISTENCE: FAIL create errno=%d\n", errno);
		return 1;
	}
	if (write(fd, payload, sizeof(payload) - 1) != (ssize_t)(sizeof(payload) - 1)) {
		printf("VINIX REBOOT PERSISTENCE: FAIL write errno=%d\n", errno);
		return 1;
	}
	if (close(fd) != 0) {
		printf("VINIX REBOOT PERSISTENCE: FAIL close errno=%d\n", errno);
		return 1;
	}
	/* Deliberately no fsync() and no O_SYNC: the restart owns this. sync(2)
	 * is called anyway because busybox reboot calls it before signalling
	 * init, so a shell's `reboot` goes through here too. */
	say("VINIX REBOOT PERSISTENCE: SYNCING\n");
	sync();
	say("VINIX REBOOT PERSISTENCE: WROTE MARKER, REBOOTING\n");
	reboot(RB_AUTOBOOT);
	printf("VINIX REBOOT PERSISTENCE: FAIL reboot returned errno=%d\n", errno);
	return 1;
}

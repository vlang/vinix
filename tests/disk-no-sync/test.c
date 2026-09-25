// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

/* SPDX-License-Identifier: GPL-2.0-or-later
 * Copyright (c) 2026 Alexander Medvednikov
 *
 * A change to an EXT2 directory or inode is on the disk by the time the call
 * that made it returns, with no sync(2) or fsync(2) anywhere. As PID 1, with
 * the persistent volume at /root, this makes one change per boot -- the step
 * the runner put in /no-sync-step -- says so, and waits. The runner stops the
 * machine at once and reads the volume with debugfs.
 *
 * None of these is flushed where it is made, with EXT2's lock held, but on the
 * thread's way back to userspace (flush_on_return in fs/ext2), or, for an inode
 * freed by closing a dying process' descriptors, before its parent can wait
 * for it, and by execve for the close-on-exec ones. The writeback thread's pass
 * every few seconds would cover for a flush that never happened, which is why
 * the machine is stopped rather than left to shut down.
 */
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

static void fail(const char *what)
{
	printf("VINIX NO SYNC: FAIL %s errno=%d\n", what, errno);
	fflush(stdout);
	for (;;)
		pause();
}

static void done(const char *step, unsigned long ino)
{
	printf("VINIX NO SYNC: DONE %s ino=%lu\n", step, ino);
	fflush(stdout);
	for (;;)
		pause();
}

/* Opened, unlinked and left open: its inode is freed by the close that
 * follows, which this thread never returns to userspace from. */
static unsigned long open_unlinked(const char *path, int flags)
{
	int fd = open(path, O_CREAT | O_EXCL | O_WRONLY | flags, 0644);
	if (fd < 0)
		fail("open");
	struct stat st;
	if (fstat(fd, &st) != 0)
		fail("fstat");
	if (unlink(path) != 0)
		fail("unlink");
	return (unsigned long)st.st_ino;
}

int main(int argc, char **argv)
{
	setbuf(stdout, NULL);
	int console = open("/dev/console", O_WRONLY);
	if (console >= 0) {
		dup2(console, STDOUT_FILENO);
		dup2(console, STDERR_FILENO);
		if (console > STDERR_FILENO)
			close(console);
	}

	/* What the exec step's child comes back as. */
	if (argc == 3 && strcmp(argv[1], "exec") == 0)
		done("exec", strtoul(argv[2], NULL, 10));

	char step[32] = {0};
	int fd = open("/no-sync-step", O_RDONLY);
	if (fd < 0 || read(fd, step, sizeof(step) - 1) <= 0)
		fail("reading /no-sync-step");
	close(fd);
	step[strcspn(step, "\n")] = 0;
	printf("VINIX NO SYNC: START %s\n", step);

	if (strcmp(step, "mkdir") == 0) {
		if (mkdir("/root/made", 0755) != 0)
			fail("mkdir");
	} else if (strcmp(step, "create") == 0) {
		/* Left open: a last close would sync the whole cache itself. */
		if (open("/root/named", O_CREAT | O_EXCL | O_WRONLY, 0644) < 0)
			fail("create");
	} else if (strcmp(step, "rename") == 0) {
		if (rename("/root/named", "/root/renamed") != 0)
			fail("rename");
	} else if (strcmp(step, "link") == 0) {
		if (link("/root/renamed", "/root/linked") != 0)
			fail("link");
	} else if (strcmp(step, "unlink") == 0) {
		if (unlink("/root/renamed") != 0)
			fail("unlink");
	} else if (strcmp(step, "chmod") == 0) {
		if (chmod("/root/linked", 0600) != 0)
			fail("chmod");
	} else if (strcmp(step, "exit") == 0) {
		int pipefd[2];
		if (pipe(pipefd) != 0)
			fail("pipe");
		pid_t child = fork();
		if (child < 0)
			fail("fork");
		if (child == 0) {
			unsigned long ino = open_unlinked("/root/made/exited", 0);
			if (write(pipefd[1], &ino, sizeof(ino)) != (ssize_t)sizeof(ino))
				fail("write");
			_exit(0);
		}
		unsigned long ino = 0;
		if (read(pipefd[0], &ino, sizeof(ino)) != (ssize_t)sizeof(ino))
			fail("read");
		int status = 0;
		if (waitpid(child, &status, 0) != child || !WIFEXITED(status) ||
		    WEXITSTATUS(status) != 0)
			fail("waitpid");
		done(step, ino);
	} else if (strcmp(step, "exec") == 0) {
		pid_t child = fork();
		if (child < 0)
			fail("fork");
		if (child == 0) {
			char ino[32];
			snprintf(ino, sizeof(ino), "%lu",
				 open_unlinked("/root/made/execed", O_CLOEXEC));
			char *args[] = { argv[0], "exec", ino, NULL };
			execv("/sbin/init", args);
			fail("execv");
		}
		for (;;)
			pause();
	} else {
		errno = 0;
		fail("unknown step");
	}
	done(step, 0);
}

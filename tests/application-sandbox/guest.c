/* SPDX-License-Identifier: GPL-2.0-or-later */
#define VINIX_SANDBOX_NO_MAIN
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <limits.h>
#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>
#include "../../tools/sandbox/sandbox_v.h"
int vinix_sandbox_main(int, char **);
#define sb_getids vksb_getids
#define sb_prctl vksb_prctl
#define sb_groups vksb_groups
#define sb_capget vksb_capget
#define sb_unveil vksb_unveil
#define sb_pledge vksb_pledge
#include <fcntl.h>
#include <signal.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <sys/mount.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/wait.h>

#define REQUIRE(condition) do { if (!(condition)) { \
	fprintf(stderr, "APPLICATION SANDBOX FAIL: line %d: %s (errno %d)\n", \
		__LINE__, #condition, errno); return 1; } } while (0)

static int target(const char *mode)
{
	uint32_t uid[3], gid[3];
	struct sb_cap_data caps[2];
	REQUIRE(sb_getids(uid, gid) == 0);
	for (int i = 0; i < 3; i++) REQUIRE(uid[i] == 1000 && gid[i] == 1000);
	REQUIRE(sb_prctl(SB_PR_GET_NO_NEW_PRIVS, 0) == 1);
	REQUIRE(sb_groups(0) == 0);
	REQUIRE(sb_capget(caps) == 0);
	for (int i = 0; i < 2; i++) REQUIRE(!caps[i].effective && !caps[i].permitted && !caps[i].inheritable);
	errno = 0;
	REQUIRE(fcntl(200, F_GETFD) == -1 && errno == EBADF);
	REQUIRE(getenv("UNTRUSTED") == NULL);
	REQUIRE(getenv("EXPLICIT") && !strcmp(getenv("EXPLICIT"), "literal;$(id)"));
	if (!strcmp(mode, "kill")) {
		socket(AF_INET, SOCK_STREAM, 0);
		return 1;
	}
	if (!strcmp(mode, "no-rpath")) {
		errno = 0;
		REQUIRE(open("/tmp/sandbox-readable", O_RDONLY) == -1 && errno == ENOSYS);
		return 0;
	}
	int fd = open("/tmp/sandbox-readable", O_RDONLY);
	REQUIRE(fd >= 0);
	char data[8] = { 0 };
	REQUIRE(read(fd, data, sizeof(data)) == 4 && !strcmp(data, "safe"));
	REQUIRE(close(fd) == 0);
	errno = 0;
	REQUIRE(open("/tmp/sandbox-hidden", O_RDONLY) == -1 && errno == ENOENT);
	errno = 0;
	REQUIRE(open("/tmp/sandbox-readable", O_WRONLY) == -1 && errno == EACCES);
	errno = 0;
	REQUIRE(socket(AF_INET, SOCK_STREAM, 0) == -1 && errno == ENOSYS);
	errno = 0;
	REQUIRE(mmap(NULL, 4096, PROT_READ | PROT_EXEC, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0) == MAP_FAILED
		&& errno == ENOSYS);
	errno = 0;
	REQUIRE(sb_unveil("/tmp/sandbox-hidden", "r") == -1 && errno == EPERM);
	errno = 0;
	REQUIRE(sb_pledge("stdio rpath wpath inet error unveil", NULL) == -1 && errno == EPERM);
	for (int cap = 0; cap <= 40; cap++) REQUIRE(sb_prctl(SB_PR_CAPBSET_READ, (unsigned long)cap) == 0);
	return 0;
}

static int run_case(const char *promises, const char *mode, const char *extra_path, const char *program,
	int exit_code, int signal_number)
{
	pid_t pid = fork();
	REQUIRE(pid >= 0);
	if (!pid) {
		char *args[] = { "vinix-sandbox", "--promises", (char *)promises,
			"--uid", "1000", "--gid", "1000", "--unveil", "/tmp/sandbox-readable", "r",
			"--env", "EXPLICIT=literal;$(id)", "--", (char *)program,
			"--sandbox-target", (char *)mode, NULL };
		if (extra_path) args[8] = (char *)extra_path;
		_exit(vinix_sandbox_main(16, args));
	}
	int status = 0;
	REQUIRE(waitpid(pid, &status, 0) == pid);
	if (signal_number) REQUIRE(WIFSIGNALED(status) && WTERMSIG(status) == signal_number);
	else REQUIRE(WIFEXITED(status) && WEXITSTATUS(status) == exit_code);
	return 0;
}

static int write_fixture(const char *path)
{
	int fd = open(path, O_CREAT | O_TRUNC | O_WRONLY, 0644);
	REQUIRE(fd >= 0 && write(fd, "safe", 4) == 4 && close(fd) == 0);
	REQUIRE(chmod(path, 0644) == 0);
	return 0;
}

int main(int argc, char **argv)
{
	if (argc == 3 && !strcmp(argv[1], "--sandbox-target")) return target(argv[2]);
	(void)mount("proc", "/proc", "proc", 0, NULL);
	REQUIRE(write_fixture("/tmp/sandbox-readable") == 0);
	REQUIRE(write_fixture("/tmp/sandbox-hidden") == 0);
	int fd = open("/tmp/sandbox-hidden", O_RDONLY);
	REQUIRE(fd >= 0 && dup2(fd, 200) == 200);
	if (fd != 200) close(fd);
	REQUIRE(setenv("UNTRUSTED", "do-not-inherit", 1) == 0);
	REQUIRE(run_case("stdio rpath wpath error unveil", "allowed", NULL, "/sbin/init", 0, 0) == 0);
	REQUIRE(run_case("stdio error", "no-rpath", NULL, "/sbin/init", 0, 0) == 0);
	REQUIRE(run_case("stdio rpath", "kill", NULL, "/sbin/init", 0, SIGABRT) == 0);
	REQUIRE(run_case("stdio unknown", "allowed", NULL, "/sbin/init", 125, 0) == 0);
	REQUIRE(run_case("stdio rpath error", "allowed", "/missing/parent/file", "/sbin/init", 125, 0) == 0);
	REQUIRE(run_case("stdio rpath error", "allowed", NULL, "/missing/parent/command", 125, 0) == 0);
	puts("APPLICATION SANDBOX GUEST PASS");
	fflush(NULL);
	for (;;) pause();
}

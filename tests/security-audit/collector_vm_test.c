/* SPDX-License-Identifier: GPL-2.0-or-later */
#define main collector_main
#include "../../tools/security-audit/collector.c"
#undef main
#include <sys/mount.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#define CHECK(x) do { if (!(x)) { printf("SECURITY AUDIT COLLECTOR VM FAIL line %d: %s errno=%d\n", __LINE__, #x, errno); return 1; } } while (0)
struct filter { uint16_t code; uint8_t jt, jf; uint32_t k; };
struct program { unsigned short length; struct filter *instructions; };

static int run_once(const char *path)
{
	char *args[] = { "vinix-security-audit", "--once", "--log", (char *)path, NULL };
	return collector_main(4, args);
}

static int tests(void)
{
	puts("SECURITY AUDIT COLLECTOR VM: producing events");
	if (access("/proc/security_audit", F_OK)) CHECK(mount("proc", "/proc", "proc", 0, NULL) == 0);
	pid_t child = fork();
	CHECK(child >= 0);
	if (!child) {
		struct filter code[] = { {0x20, 0, 0, 0}, {0x15, 0, 1, SYS_getpid},
			{0x06, 0, 0, 0x7ffc0000U}, {0x06, 0, 0, 0x7fff0000U} };
		struct program p = {4, code};
		if (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) || syscall(SYS_seccomp, 1, 0, &p)) _exit(1);
		for (int i = 0; i < 200; ++i) if (syscall(SYS_getpid) <= 0) _exit(2);
		_exit(0);
	}
	int status;
	CHECK(waitpid(child, &status, 0) == child && WIFEXITED(status) && WEXITSTATUS(status) == 0);
	puts("SECURITY AUDIT COLLECTOR VM: collecting first session");
	const char *path = "/root/audit-collector-test/seccomp.log";
	CHECK(run_once(path) == 0);
	int fd = open(path, O_RDONLY);
	CHECK(fd >= 0 && log_stat(fd, 0) == 0);
	char buffer[OUTPUT_BYTES] = {0};
	ssize_t used = read(fd, buffer, sizeof(buffer) - 1);
	CHECK(used > 0); close(fd);
	size_t decisions = 0;
	for (char *line = buffer; (line = strstr(line, "decision ")); ++line) ++decisions;
	CHECK(decisions == CAPACITY);
	CHECK(strstr(buffer, "first=1 last=72 count=72 reason=not_observed"));
	CHECK(strstr(buffer, "completed=1") && strstr(buffer, "reason=one_shot") && !strstr(buffer, "boot=unknown"));
	puts("SECURITY AUDIT COLLECTOR VM: collecting second session");
	CHECK(run_once(path) == 0);
	fd = open(path, O_RDONLY); CHECK(fd >= 0);
	used = read(fd, buffer, sizeof(buffer) - 1); CHECK(used > 0); buffer[used] = 0; close(fd);
	char *first = strstr(buffer, "session_start session="); CHECK(first != NULL);
	char *second = strstr(first + 1, "session_start session="); CHECK(second != NULL);
	CHECK(memcmp(first + strlen("session_start session="), second + strlen("session_start session="), 32));
	/* Verify the actual guest fstat, nofollow and flock behavior used in production. */
	puts("SECURITY AUDIT COLLECTOR VM: checking log protections");
	CHECK(chmod(path, 0644) == 0 && run_once(path) == 1 && chmod(path, 0600) == 0);
	fd = open_log(path, -1); CHECK(fd >= 0 && run_once(path) == 1); close(fd);
	CHECK(symlink(path, "/root/audit-collector-test/link.log") == 0);
	CHECK(run_once("/root/audit-collector-test/link.log") == 1);
	CHECK(link(path, "/root/audit-collector-test/hardlink.log") == 0 && run_once(path) == 1);
	CHECK(unlink("/root/audit-collector-test/hardlink.log") == 0);
	CHECK(run_once(path) == 0);
	puts("SECURITY AUDIT COLLECTOR VM PASS");
	return 0;
}

int main(void)
{
	setvbuf(stdout, NULL, _IONBF, 0);
	if (tests()) puts("SECURITY AUDIT COLLECTOR VM FAIL");
	for (;;) pause();
}

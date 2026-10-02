/* SPDX-License-Identifier: GPL-2.0-or-later */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <sched.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

#define CHECK(x) do { if (!(x)) { \
	printf("SECURITY AUDIT FAIL line %d: %s errno=%d\n", __LINE__, #x, errno); \
	return 1; } } while (0)
#define RET_ALLOW 0x7fff0000U
#define RET_LOG 0x7ffc0000U
#define RET_ERRNO 0x00050000U
#define RET_KILL 0x80000000U
struct filter { uint16_t code; uint8_t jt, jf; uint32_t k; };
struct program { unsigned short length; struct filter *instructions; };
struct cap_header { uint32_t version; int pid; };
struct cap_data { uint32_t effective, permitted, inheritable; };
static char buffer[65536];

static int install(unsigned nr, unsigned action)
{
	struct filter code[] = {
		{0x20, 0, 0, 0}, {0x15, 0, 1, nr},
		{0x06, 0, 0, action}, {0x06, 0, 0, RET_ALLOW}
	};
	struct program p = {4, code};
	if (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0)) return -1;
	return (int)syscall(SYS_seccomp, 1, 0, &p);
}

static int read_all(const char *path, int chunk, int churn)
{
	int fd = open(path, O_RDONLY);
	if (fd < 0) return -1;
	size_t used = 0;
	for (;;) {
		if (churn) syscall(SYS_getpid);
		ssize_t n = read(fd, buffer + used, (size_t)chunk);
		if (n < 0 || used + (size_t)n >= sizeof(buffer)) {
			close(fd); return -1;
		}
		if (!n) break;
		used += (size_t)n;
	}
	close(fd);
	buffer[used] = 0;
	return (int)used;
}

static int reap(pid_t pid)
{
	int status;
	while (waitpid(pid, &status, 0) < 0) if (errno != EINTR) return -1;
	return status;
}

static int permission_tests(void)
{
	int fd = open("/proc/security_audit", O_RDONLY);
	CHECK(fd >= 0);
	char first;
	CHECK(read(fd, &first, 1) == 1); // Cache a privileged snapshot before fork.
	pid_t child = fork();
	CHECK(child >= 0);
	if (!child) {
		char c;
		if (setuid(1000)) _exit(1);
		errno = 0;
		_exit(read(fd, &c, 1) == -1 && errno == EACCES ? 0 : 2);
	}
	CHECK(reap(child) == 0);
	child = fork();
	CHECK(child >= 0);
	if (!child) {
		struct cap_header h = {0x20080522U, 0};
		struct cap_data d[2] = {{0}};
		char c;
		if (syscall(SYS_capget, &h, d)) _exit(3);
		d[1].effective &= ~(1U << (37 - 32));
		if (syscall(SYS_capset, &h, d)) _exit(4);
		errno = 0;
		_exit(read(fd, &c, 1) == -1 && errno == EACCES ? 0 : 5);
	}
	CHECK(reap(child) == 0);
	child = fork();
	CHECK(child >= 0);
	if (!child) {
		char c;
		if (unshare(CLONE_NEWUSER)) _exit(6);
		errno = 0;
		_exit(read(fd, &c, 1) == -1 && errno == EACCES ? 0 : 7);
	}
	CHECK(reap(child) == 0);
	close(fd);
	return 0;
}

static int parse_record(char *line, unsigned long long v[15])
{
	for (int i = 0; i < 15; i++) {
		char *end;
		v[i] = strtoull(line, &end, 10);
		if (end == line) return -1;
		line = end;
	}
	return 0;
}

static unsigned long long slab_bytes(void)
{
	if (read_all("/proc/slabinfo", 4096, 0) < 0) return ~0ULL;
	unsigned long long total = 0;
	char *line = strtok(buffer, "\n");
	while (line) {
		unsigned long long size, live, pages;
		if (sscanf(line, "size-%*u %llu %llu %llu", &size, &live, &pages) == 3)
			total += size * live;
		line = strtok(NULL, "\n");
	}
	return total;
}

static int tests(void)
{
	if (access("/proc/slabinfo", F_OK))
		CHECK(mount("proc", "/proc", "proc", 0, NULL) == 0);
	CHECK(permission_tests() == 0);
	pid_t own = getpid();
	CHECK(install(SYS_getpid, RET_LOG) == 0);
	CHECK(syscall(SYS_getpid) == own);
	CHECK(read_all("/proc/security_audit", 4096, 0) > 0);
	char *line = strtok(buffer, "\n");
	CHECK(line && strstr(line, "version=1 capacity=128"));
	CHECK((line = strtok(NULL, "\n")) != NULL);
	CHECK((line = strtok(NULL, "\n")) != NULL);
	unsigned long long v[15];
	CHECK(parse_record(line, v) == 0);
	CHECK(v[3] == SYS_getpid && v[5] == (unsigned)own && v[6] == (unsigned)own);
	CHECK(v[7] == 0 && v[8] == 0 && v[9] == 0 && v[10] == 0);
	CHECK(v[11] == RET_LOG && v[12] == 1 && v[13] == (unsigned)own && v[14] == 0);
	CHECK(v[1] > 0 && v[4] > 0);
#if defined(__aarch64__)
	CHECK(v[2] == 0xc00000b7U);
#else
	CHECK(v[2] == 0xc000003eU);
#endif
	pid_t identified = fork();
	CHECK(identified >= 0);
	if (!identified) {
		if (setgid(1000) || setuid(1000)) _exit(1);
		if (syscall(SYS_getpid) <= 0) _exit(2);
		_exit(0);
	}
	CHECK(reap(identified) == 0);
	CHECK(read_all("/proc/security_audit", 4096, 0) > 0);
	int found_identity = 0;
	line = strtok(buffer, "\n");
	while ((line = strtok(NULL, "\n"))) {
		if (*line == '#') continue;
		CHECK(parse_record(line, v) == 0);
		if (v[5] == (unsigned)identified && v[11] == RET_LOG) {
			CHECK(v[7] == 1000 && v[8] == 1000 && v[9] == 1000 && v[10] == 1000);
			CHECK(v[12] == 1 && v[13] == (unsigned)identified && v[14] == 0);
			found_identity = 1;
		}
	}
	CHECK(found_identity);
	CHECK(install(SYS_getppid, RET_ERRNO | EPERM) == 0);
	errno = 0;
	CHECK(syscall(SYS_getppid) == -1 && errno == EPERM);
	CHECK(read_all("/proc/security_audit", 4096, 0) > 0);
	int found = 0;
	line = strtok(buffer, "\n");
	while ((line = strtok(NULL, "\n"))) {
		if (*line == '#') continue;
		CHECK(parse_record(line, v) == 0);
		if (v[3] == SYS_getppid && v[11] == (RET_ERRNO | EPERM)) {
			CHECK(v[12] == 1 && v[14] == EPERM);
			found = 1;
		}
	}
	CHECK(found);
	pid_t child = fork();
	CHECK(child >= 0);
	if (!child) {
		if (install(SYS_getppid, RET_KILL)) _exit(1);
		syscall(SYS_getppid);
		_exit(2);
	}
	int status = reap(child);
	CHECK(WIFSIGNALED(status) && WTERMSIG(status) == SIGSYS);
	CHECK(read_all("/proc/security_audit", 4096, 0) > 0);
	found = 0;
	line = strtok(buffer, "\n");
	while ((line = strtok(NULL, "\n"))) {
		if (*line == '#') continue;
		CHECK(parse_record(line, v) == 0);
		if (v[5] == (unsigned)child && v[11] == RET_KILL) {
			CHECK(v[12] == 0);
			found = 1;
		}
	}
	CHECK(found);
	for (int i = 0; i < 1000; i++) CHECK(syscall(SYS_getpid) == own);
	CHECK(read_all("/proc/security_audit", 17, 1) > 0);
	unsigned long long total, retained, dropped;
	line = strtok(buffer, "\n");
	CHECK(sscanf(line, "version=1 capacity=128 total=%llu retained=%llu dropped=%llu",
		&total, &retained, &dropped) == 3);
	CHECK(retained == 128 && total > 128 && dropped == total - 128);
	unsigned long long expected = total - retained + 1;
	line = strtok(NULL, "\n");
	CHECK(line && *line == '#');
	while ((line = strtok(NULL, "\n"))) {
		CHECK(parse_record(line, v) == 0 && v[0] == expected++);
	}
	CHECK(expected == total + 1);
	// Warm procfs buffers, then measure retained allocations on both the
	// producing and collecting paths, rather than relying on source inspection.
	for (int i = 0; i < 20; i++) CHECK(read_all("/proc/security_audit", 4096, 0) > 0);
	unsigned long long before = slab_bytes();
	CHECK(before != ~0ULL);
	for (int i = 0; i < 10000; i++) CHECK(syscall(SYS_getpid) == own);
	unsigned long long after = slab_bytes();
	printf("SECURITY AUDIT PRODUCE retained_bytes=%lld\n", (long long)(after - before));
	CHECK(after <= before + 1024);
	before = after;
	for (int i = 0; i < 1000; i++) CHECK(read_all("/proc/security_audit", 4096, 0) > 0);
	after = slab_bytes();
	printf("SECURITY AUDIT COLLECT retained_bytes=%lld\n", (long long)(after - before));
	CHECK(after <= before + 1024);
	puts("SECURITY AUDIT PASS");
	return 0;
}

int main(void)
{
	setvbuf(stdout, NULL, _IONBF, 0);
	int result = tests();
	if (result) puts("SECURITY AUDIT FAIL");
	for (;;) pause();
}

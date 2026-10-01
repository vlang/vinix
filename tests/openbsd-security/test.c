// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

/* SPDX-License-Identifier: BSD-2-Clause
 * In-guest regression coverage for Vinix's OpenBSD security features:
 * pledge(2), unveil(2), signed signal frames, random process ids, a
 * random program break, minherit(2), the network stack's random ports,
 * sequence numbers and IP IDs, memory layouts kept from other users, and
 * read-only files that no back door writes. Built statically for either
 * architecture and run
 * as PID 1; every case runs in a child, so a pledge violation that kills the
 * child is an outcome the parent can check. */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/ioctl.h>
#include <sys/mount.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/uio.h>
#include <sys/wait.h>
#include <net/if.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <poll.h>
#include <time.h>
#include <unistd.h>

#if defined(__aarch64__)
#define SYS_vinix_mimmutable 247
#define SYS_vinix_pledge 248
#define SYS_vinix_unveil 249
#define SYS_vinix_minherit 250
#elif defined(__x86_64__)
#define SYS_vinix_mimmutable 500
#define SYS_vinix_pledge 501
#define SYS_vinix_unveil 502
#define SYS_vinix_minherit 503
#else
#error "unsupported architecture"
#endif

#ifndef MADV_WIPEONFORK
#define MADV_WIPEONFORK 18
#define MADV_KEEPONFORK 19
#endif
#define MAP_INHERIT_SHARE 0
#define MAP_INHERIT_COPY 1
#define MAP_INHERIT_NONE 2
#define MAP_INHERIT_ZERO 3

/* chattr flags and their ioctls, from <linux/fs.h>, which a musl sysroot
 * refuses to include from userspace. */
#define FS_IOC_GETFLAGS 0x80086601UL
#define FS_IOC_SETFLAGS 0x40086602UL
#define FS_IMMUTABLE_FL 0x00000010
#define FS_APPEND_FL 0x00000020

static char *self_path = "/sbin/init";

static int pledge(const char *promises, const char *execpromises)
{
	return (int)syscall(SYS_vinix_pledge, promises, execpromises);
}

static int unveil(const char *path, const char *permissions)
{
	return (int)syscall(SYS_vinix_unveil, path, permissions);
}

#define CHECK(expression) do {                                               \
	if (!(expression)) {                                                   \
		printf("OPENBSD SECURITY FAIL line %d: %s (errno=%d)\n",       \
		    __LINE__, #expression, errno);                               \
		return 1;                                                       \
	}                                                                       \
} while (0)

/* The amd64 syscall exit has no restart, so a SIGCHLD can end the wait. */
static int reap(pid_t child)
{
	int status = -1;
	pid_t waited;
	do
		waited = waitpid(child, &status, 0);
	while (waited == -1 && errno == EINTR);
	return waited == child ? status : -1;
}

/* Run `body` in a child; answers its wait status. */
static int in_child(int (*body)(void))
{
	fflush(stdout);
	pid_t child = fork();
	if (child == 0)
		_exit(body());
	return child < 0 ? -1 : reap(child);
}

/* A call that had to fail with `expected`. The amd64 Linux ABI has no
 * rename, link, symlink or mount yet; there, ENOSYS is as good as a refusal. */
static int refused(int result, int expected)
{
	if (result != -1)
		return 0;
#if defined(__x86_64__)
	if (errno == ENOSYS)
		return 1;
#endif
	return errno == expected;
}

static void report_status(int status)
{
	if (WIFEXITED(status))
		printf("OPENBSD SECURITY: the child exited with %d\n", WEXITSTATUS(status));
	else if (WIFSIGNALED(status))
		printf("OPENBSD SECURITY: the child was killed by signal %d\n", WTERMSIG(status));
	else
		printf("OPENBSD SECURITY: the child's wait status is %#x\n", status);
}

static int exited_ok(int status)
{
	if (WIFEXITED(status) && WEXITSTATUS(status) == 0)
		return 1;
	report_status(status);
	return 0;
}

static int killed_by(int status, int signal)
{
	if (WIFSIGNALED(status) && WTERMSIG(status) == signal)
		return 1;
	report_status(status);
	return 0;
}

static int write_file(const char *path, const char *text)
{
	int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
	if (fd < 0)
		return -1;
	ssize_t length = (ssize_t)strlen(text);
	int ok = write(fd, text, (size_t)length) == length;
	close(fd);
	return ok ? 0 : -1;
}

/* ── pledge ─────────────────────────────────────────────────────────────── */

static int stdio_allows_io(void)
{
	CHECK(pledge("stdio", NULL) == 0);
	CHECK(write(STDOUT_FILENO, "", 0) == 0);
	CHECK(getpid() > 0);
	void *memory = mmap(NULL, 4096, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
	CHECK(memory != MAP_FAILED);
	CHECK(munmap(memory, 4096) == 0);
	/* Whitelisted for every pledged process: daemon(3) needs it. */
	int null = open("/dev/null", O_RDWR);
	CHECK(null >= 0);
	CHECK(close(null) == 0);
	/* A process may always signal itself. */
	CHECK(kill(getpid(), 0) == 0);
	return 0;
}

static int stdio_open_dies(void)
{
	CHECK(pledge("stdio", NULL) == 0);
	open("/tmp/pledge-file", O_RDONLY);
	return 0;
}

static int rpath_reads(void)
{
	CHECK(pledge("stdio rpath", NULL) == 0);
	int fd = open("/tmp/pledge-file", O_RDONLY);
	CHECK(fd >= 0);
	char buffer[8];
	CHECK(read(fd, buffer, sizeof(buffer)) > 0);
	CHECK(close(fd) == 0);
	struct stat st;
	CHECK(stat("/tmp/pledge-file", &st) == 0);
	return 0;
}

static int rpath_write_dies(void)
{
	CHECK(pledge("stdio rpath", NULL) == 0);
	open("/tmp/pledge-file", O_WRONLY);
	return 0;
}

static int error_promise_returns_enosys(void)
{
	CHECK(pledge("stdio error", NULL) == 0);
	errno = 0;
	CHECK(socket(AF_INET, SOCK_STREAM, 0) == -1 && errno == ENOSYS);
	errno = 0;
	CHECK(open("/tmp/pledge-file", O_RDONLY) == -1 && errno == ENOSYS);
	return 0;
}

static int promises_only_narrow(void)
{
	CHECK(pledge("stdio rpath", NULL) == 0);
	errno = 0;
	CHECK(pledge("stdio rpath wpath", NULL) == -1 && errno == EPERM);
	CHECK(pledge("stdio", NULL) == 0);
	errno = 0;
	CHECK(pledge("stdio rpath", NULL) == -1 && errno == EPERM);
	errno = 0;
	CHECK(pledge("stdio bogus", NULL) == -1 && errno == EINVAL);
	return 0;
}

static int prot_exec_dies(void)
{
	CHECK(pledge("stdio", NULL) == 0);
	mmap(NULL, 4096, PROT_READ | PROT_EXEC, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
	return 0;
}

static int fork_needs_proc(void)
{
	CHECK(pledge("stdio", NULL) == 0);
	fork();
	return 0;
}

static int kill_other_needs_proc(void)
{
	CHECK(pledge("stdio", NULL) == 0);
	kill(1, 0);
	return 0;
}

#if defined(__aarch64__)
static void *thread_body(void *argument)
{
	return argument;
}

static int threads_need_only_stdio(void)
{
	CHECK(pledge("stdio", NULL) == 0);
	pthread_t thread;
	CHECK(pthread_create(&thread, NULL, thread_body, (void *)0x5649) == 0);
	void *result = NULL;
	CHECK(pthread_join(thread, &result) == 0);
	CHECK(result == (void *)0x5649);
	return 0;
}
#endif

static int tmppath_makes_temporaries(void)
{
	CHECK(pledge("stdio tmppath", NULL) == 0);
	char name[] = "/tmp/pledge.XXXXXX";
	int fd = mkstemp(name);
	CHECK(fd >= 0);
	CHECK(write(fd, "x", 1) == 1);
	CHECK(close(fd) == 0);
	CHECK(unlink(name) == 0);
	return 0;
}

static int send_one_fd(int socket_fd, int fd)
{
	char byte = 'f';
	struct iovec iov = { .iov_base = &byte, .iov_len = 1 };
	union {
		struct cmsghdr header;
		char buffer[CMSG_SPACE(sizeof(int))];
	} control;
	memset(&control, 0, sizeof(control));
	struct msghdr message = {
		.msg_iov = &iov,
		.msg_iovlen = 1,
		.msg_control = control.buffer,
		.msg_controllen = sizeof(control.buffer),
	};
	struct cmsghdr *header = CMSG_FIRSTHDR(&message);
	header->cmsg_level = SOL_SOCKET;
	header->cmsg_type = SCM_RIGHTS;
	header->cmsg_len = CMSG_LEN(sizeof(int));
	memcpy(CMSG_DATA(header), &fd, sizeof(int));
	return (int)sendmsg(socket_fd, &message, 0);
}

static int sendfd_needs_promise(void)
{
	int pair[2];
	CHECK(socketpair(AF_UNIX, SOCK_STREAM, 0, pair) == 0);
	CHECK(pledge("stdio", NULL) == 0);
	send_one_fd(pair[0], STDOUT_FILENO);
	return 0;
}

static int sendfd_with_promise(void)
{
	int pair[2];
	CHECK(socketpair(AF_UNIX, SOCK_STREAM, 0, pair) == 0);
	CHECK(pledge("stdio sendfd recvfd", NULL) == 0);
	CHECK(send_one_fd(pair[0], STDOUT_FILENO) == 1);
	return 0;
}

static int dns_reaches_only_port_53(void)
{
	CHECK(pledge("stdio dns", NULL) == 0);
	int fd = socket(AF_INET, SOCK_DGRAM, 0);
	CHECK(fd >= 0);
	struct sockaddr_in address = { .sin_family = AF_INET, .sin_port = htons(53) };
	address.sin_addr.s_addr = htonl(0x0a000203);
	/* Whether it connects depends on the network; it must not be a violation. */
	connect(fd, (struct sockaddr *)&address, sizeof(address));
	address.sin_port = htons(80);
	connect(fd, (struct sockaddr *)&address, sizeof(address));
	return 0;
}

static int unix_socket_needs_unix(void)
{
	CHECK(pledge("stdio inet", NULL) == 0);
	socket(AF_UNIX, SOCK_STREAM, 0);
	return 0;
}

static int execpromises_carry_over(void)
{
	CHECK(pledge("stdio proc exec", "stdio") == 0);
	char *argv[] = { self_path, "--pledged-child-opens", NULL };
	execv(self_path, argv);
	return 1;
}

static int exec_without_execpromises_is_unpledged(void)
{
	CHECK(pledge("stdio proc exec", NULL) == 0);
	char *argv[] = { self_path, "--pledged-child-opens", NULL };
	execv(self_path, argv);
	return 1;
}

static int pledged_child_opens(void)
{
	int fd = open("/tmp/pledge-file", O_RDONLY);
	return fd >= 0 ? 0 : 1;
}

static int run_pledge_tests(void)
{
	CHECK(write_file("/tmp/pledge-file", "pledge") == 0);
	CHECK(exited_ok(in_child(stdio_allows_io)));
	CHECK(killed_by(in_child(stdio_open_dies), SIGABRT));
	CHECK(exited_ok(in_child(rpath_reads)));
	CHECK(killed_by(in_child(rpath_write_dies), SIGABRT));
	CHECK(exited_ok(in_child(error_promise_returns_enosys)));
	CHECK(exited_ok(in_child(promises_only_narrow)));
	puts("OPENBSD SECURITY PASS: pledge promises and violations");

	CHECK(killed_by(in_child(prot_exec_dies), SIGABRT));
	CHECK(killed_by(in_child(fork_needs_proc), SIGABRT));
	CHECK(killed_by(in_child(kill_other_needs_proc), SIGABRT));
#if defined(__aarch64__)
	/* The amd64 Linux ABI has no clone(2) for threads yet. */
	CHECK(exited_ok(in_child(threads_need_only_stdio)));
#endif
	CHECK(exited_ok(in_child(tmppath_makes_temporaries)));
	puts("OPENBSD SECURITY PASS: pledge proc, prot_exec and tmppath");

	CHECK(killed_by(in_child(sendfd_needs_promise), SIGABRT));
	CHECK(exited_ok(in_child(sendfd_with_promise)));
	CHECK(killed_by(in_child(dns_reaches_only_port_53), SIGABRT));
	CHECK(killed_by(in_child(unix_socket_needs_unix), SIGABRT));
	puts("OPENBSD SECURITY PASS: pledge sockets and descriptor passing");

	/* The exec'd program is pledged "stdio" and dies opening a file... */
	CHECK(killed_by(in_child(execpromises_carry_over), SIGABRT));
	/* ...unless no execpromises were given, when it runs unpledged. */
	CHECK(exited_ok(in_child(exec_without_execpromises_is_unpledged)));
	puts("OPENBSD SECURITY PASS: pledge execpromises");
	return 0;
}

/* ── unveil ─────────────────────────────────────────────────────────────── */

static int unveil_hides_and_limits(void)
{
	CHECK(unveil("/tmp/uv/ro", "r") == 0);
	CHECK(unveil("/tmp/uv/rw", "rwc") == 0);
	CHECK(unveil("/tmp/uv/rw/hidden", "") == 0);

	int fd = open("/tmp/uv/ro/file", O_RDONLY);
	CHECK(fd >= 0);
	CHECK(close(fd) == 0);
	errno = 0;
	CHECK(open("/tmp/uv/ro/file", O_WRONLY) == -1 && errno == EACCES);
	errno = 0;
	CHECK(open("/tmp/uv/secret", O_RDONLY) == -1 && errno == ENOENT);
	errno = 0;
	CHECK(open("/tmp/uv/rw/hidden/file", O_RDONLY) == -1 && errno == ENOENT);

	/* The directories above an unveiled path can be looked at, not read. */
	struct stat st;
	CHECK(stat("/tmp/uv", &st) == 0 && S_ISDIR(st.st_mode));
	CHECK(stat("/", &st) == 0);
	errno = 0;
	CHECK(open("/tmp/uv", O_RDONLY | O_DIRECTORY) == -1 && errno == ENOENT);
	errno = 0;
	CHECK(stat("/tmp/uv/secret", &st) == -1 && errno == ENOENT);

	/* "c" allows making and removing names; "r" alone does not. */
	CHECK(write_file("/tmp/uv/rw/new", "new") == 0);
	CHECK(mkdir("/tmp/uv/rw/dir", 0755) == 0);
	CHECK(rmdir("/tmp/uv/rw/dir") == 0);
	errno = 0;
	CHECK(mkdir("/tmp/uv/ro/dir", 0755) == -1 && errno == EACCES);
	errno = 0;
	CHECK(unlink("/tmp/uv/ro/file") == -1 && errno == EACCES);
	CHECK(refused(rename("/tmp/uv/ro/file", "/tmp/uv/rw/moved"), EACCES));
	/* A hard link may not grant more than the file's own name did. */
	CHECK(refused(link("/tmp/uv/ro/file", "/tmp/uv/rw/linked"), EACCES));
	CHECK(unlink("/tmp/uv/rw/new") == 0);

	/* A symbolic link is judged by where it leads. */
	if (symlink("/tmp/uv/secret", "/tmp/uv/rw/escape") == 0) {
		errno = 0;
		CHECK(open("/tmp/uv/rw/escape", O_RDONLY) == -1 && errno == ENOENT);
		CHECK(unlink("/tmp/uv/rw/escape") == 0);
	} else {
		CHECK(refused(-1, 0));
	}

	/* Relative paths are resolved before they are judged. */
	CHECK(chdir("/tmp/uv/ro") == 0);
	fd = open("file", O_RDONLY);
	CHECK(fd >= 0);
	CHECK(close(fd) == 0);
	errno = 0;
	CHECK(open("../secret", O_RDONLY) == -1 && errno == ENOENT);

	/* A path that does not exist yet can be unveiled for making. */
	CHECK(unveil("/tmp/uv/later", "rwc") == 0);
	CHECK(mkdir("/tmp/uv/later", 0755) == 0);
	CHECK(rmdir("/tmp/uv/later") == 0);

	/* Nothing may be mounted over an unveiled tree. */
	CHECK(refused(mount("none", "/tmp/uv/rw", "tmpfs", 0, NULL), EPERM));

	CHECK(unveil(NULL, NULL) == 0);
	errno = 0;
	CHECK(unveil("/tmp/uv/secret", "r") == -1 && errno == EPERM);
	return 0;
}

static int unveil_nothing_hides_everything(void)
{
	CHECK(unveil(NULL, NULL) == 0);
	errno = 0;
	CHECK(open("/tmp/uv/ro/file", O_RDONLY) == -1 && errno == ENOENT);
	return 0;
}

static int unveil_dropped_by_exec(void)
{
	CHECK(unveil(self_path, "x") == 0);
	CHECK(unveil(NULL, NULL) == 0);
	char *argv[] = { self_path, "--read-secret", NULL };
	execv(self_path, argv);
	return 1;
}

static int unveil_kept_with_execpromises(void)
{
	CHECK(unveil(self_path, "x") == 0);
	CHECK(unveil(NULL, NULL) == 0);
	CHECK(pledge("stdio rpath exec", "stdio rpath error") == 0);
	char *argv[] = { self_path, "--read-secret", NULL };
	execv(self_path, argv);
	return 1;
}

static int unveil_hides_exec(void)
{
	CHECK(unveil("/tmp/uv/ro", "r") == 0);
	char *argv[] = { self_path, "--read-secret", NULL };
	errno = 0;
	execv(self_path, argv);
	return errno == ENOENT ? 0 : 1;
}

static int unveil_needs_promise_when_pledged(void)
{
	CHECK(pledge("stdio rpath", NULL) == 0);
	unveil("/tmp/uv/ro", "r");
	return 0;
}

static int read_secret(void)
{
	int fd = open("/tmp/uv/secret", O_RDONLY);
	return fd >= 0 ? 0 : 3;
}

static int run_unveil_tests(void)
{
	CHECK(mkdir("/tmp/uv", 0755) == 0);
	CHECK(mkdir("/tmp/uv/ro", 0755) == 0);
	CHECK(mkdir("/tmp/uv/rw", 0755) == 0);
	CHECK(mkdir("/tmp/uv/rw/hidden", 0755) == 0);
	CHECK(write_file("/tmp/uv/ro/file", "ro") == 0);
	CHECK(write_file("/tmp/uv/rw/hidden/file", "hidden") == 0);
	CHECK(write_file("/tmp/uv/secret", "secret") == 0);

	CHECK(exited_ok(in_child(unveil_hides_and_limits)));
	CHECK(exited_ok(in_child(unveil_nothing_hides_everything)));
	puts("OPENBSD SECURITY PASS: unveil hides and limits paths");

	CHECK(exited_ok(in_child(unveil_dropped_by_exec)));
	int status = in_child(unveil_kept_with_execpromises);
	CHECK(WIFEXITED(status) && WEXITSTATUS(status) == 3);
	CHECK(exited_ok(in_child(unveil_hides_exec)));
	CHECK(killed_by(in_child(unveil_needs_promise_when_pledged), SIGABRT));
	puts("OPENBSD SECURITY PASS: unveil across exec and pledge");
	return 0;
}

/* ── signed signal frames ───────────────────────────────────────────────── */

static volatile sig_atomic_t handled;

static void count_signal(int signal)
{
	(void)signal;
	handled++;
}

static void nest_signal(int signal)
{
	(void)signal;
	handled++;
	kill(getpid(), SIGUSR2);
}

/* kill() rather than raise(): musl's raise() is tkill(2), which the amd64
 * Linux ABI does not have yet. */
static int handlers_return(void)
{
	struct sigaction action = { .sa_handler = count_signal };
	CHECK(sigaction(SIGUSR1, &action, NULL) == 0);
	CHECK(sigaction(SIGUSR2, &action, NULL) == 0);
	for (int i = 0; i < 64; i++)
		CHECK(kill(getpid(), SIGUSR1) == 0);
	CHECK(handled == 64);
	/* A frame pushed while another is live returns through both. */
	action.sa_handler = nest_signal;
	CHECK(sigaction(SIGUSR1, &action, NULL) == 0);
	CHECK(kill(getpid(), SIGUSR1) == 0);
	CHECK(handled == 66);
	return 0;
}

static void forged_target(void)
{
	/* Reached only if rt_sigreturn believed the forged frame. */
	_exit(42);
}

static uint64_t forged_stack[512] __attribute__((aligned(16)));
static uint64_t forged_frame[1024] __attribute__((aligned(16)));

/* Sigreturn-oriented programming: a frame on the stack that no signal put
 * there, naming a program counter of the attacker's choosing. Every check
 * but the cookie passes, so without it the process would exit with 42. */
static int forged_frame_dies(void)
{
	uint64_t stack_top = (uint64_t)&forged_stack[500];
#if defined(__aarch64__)
	/* The mask, the ucontext address (none: the registers alone), then the
	 * registers x0..x30, sp, pc, pstate and tpidr_el0. */
	forged_frame[2 + 31] = stack_top;
	forged_frame[2 + 32] = (uint64_t)forged_target;
	__asm__ volatile("mov sp, %0\n\tmov x8, #139\n\tsvc #0"
	    : : "r"(forged_frame) : "x8", "memory");
#elif defined(__x86_64__)
	/* rt_sigframe: the return address, then a ucontext whose mcontext holds
	 * rsp at 120 and rip at 128, as Linux lays it out. */
	unsigned char *frame = (unsigned char *)forged_frame;
	*(uint64_t *)(frame + 48 + 120) = stack_top - 8;
	*(uint64_t *)(frame + 48 + 128) = (uint64_t)forged_target;
	*(uint64_t *)(frame + 48 + 136) = 0x202;
	__asm__ volatile("lea 8(%0), %%rsp\n\tmov $15, %%eax\n\tsyscall"
	    : : "r"(frame) : "rax", "rcx", "r11", "memory");
#endif
	return 1;
}

static int run_signal_tests(void)
{
	CHECK(exited_ok(in_child(handlers_return)));
	CHECK(killed_by(in_child(forged_frame_dies), SIGSEGV));
	puts("OPENBSD SECURITY PASS: signal frames are signed");
	return 0;
}

/* ── random process ids and break ───────────────────────────────────────── */

static int exit_at_once(void)
{
	return 0;
}

/* The break a freshly executed copy of this program starts with. */
static int exec_break(uintptr_t *out)
{
	int channel[2];
	CHECK(pipe(channel) == 0);
	fflush(stdout);
	pid_t child = fork();
	CHECK(child >= 0);
	if (child == 0) {
		dup2(channel[1], STDOUT_FILENO);
		char *argv[] = { self_path, "--print-break", NULL };
		execv(self_path, argv);
		_exit(1);
	}
	close(channel[1]);
	char text[32] = { 0 };
	ssize_t length = read(channel[0], text, sizeof(text) - 1);
	close(channel[0]);
	CHECK(exited_ok(reap(child)));
	CHECK(length > 0);
	*out = (uintptr_t)strtoull(text, NULL, 16);
	return 0;
}

static int run_pid_tests(void)
{
	/* Back-to-back forks: sequential ids would differ by one every time. */
	pid_t previous = 0;
	int consecutive = 0;
	for (int i = 0; i < 16; i++) {
		fflush(stdout);
		pid_t child = fork();
		CHECK(child >= 0);
		if (child == 0)
			_exit(exit_at_once());
		CHECK(exited_ok(reap(child)));
		if (previous != 0 && child == previous + 1)
			consecutive++;
		previous = child;
	}
	CHECK(consecutive < 4);
	puts("OPENBSD SECURITY PASS: process ids are random");
	return 0;
}

static int run_break_tests(void)
{
	uintptr_t first = 0, second = 0;
	CHECK(exec_break(&first) == 0);
	CHECK(exec_break(&second) == 0);
	CHECK(first != 0 && second != 0 && first != second);
	/* A forked child has its parent's heap, and so its break. */
	uintptr_t parent_break = (uintptr_t)sbrk(0);
	int channel[2];
	CHECK(pipe(channel) == 0);
	fflush(stdout);
	pid_t child = fork();
	CHECK(child >= 0);
	if (child == 0) {
		uintptr_t child_break = (uintptr_t)sbrk(0);
		_exit(write(channel[1], &child_break, sizeof(child_break)) == sizeof(child_break) ? 0 : 1);
	}
	uintptr_t child_break = 0;
	CHECK(read(channel[0], &child_break, sizeof(child_break)) == sizeof(child_break));
	CHECK(exited_ok(reap(child)));
	CHECK(child_break == parent_break);
	close(channel[0]);
	close(channel[1]);
	puts("OPENBSD SECURITY PASS: the program break is random");
	return 0;
}

static int minherit(void *address, size_t length, int inherit)
{
	return (int)syscall(SYS_vinix_minherit, address, length, inherit);
}

static size_t page;

/* Every byte of `length` at `address` is `value`. */
static int filled(const unsigned char *address, size_t length, unsigned char value)
{
	for (size_t i = 0; i < length; i++)
		if (address[i] != value)
			return 0;
	return 1;
}

/* A child that reads a byte of each page it is given, to be killed by
 * SIGSEGV on one its parent left out of it. */
static volatile unsigned char *probe_address;

static int probe_reads(void)
{
	return probe_address[0] == 0x5a ? 0 : 2;
}

static unsigned char *inherit_pages;

/* What a forked child sees of the pages run_inherit_tests set up. */
static int inherit_child(void)
{
	unsigned char *p = inherit_pages;
	CHECK(filled(p, page, 0));             /* MADV_WIPEONFORK */
	CHECK(filled(p + 2 * page, page, 0));  /* MAP_INHERIT_ZERO */
	CHECK(filled(p + 3 * page, page, 4));  /* copied as usual */
	/* MADV_DONTFORK: not mapped in the child at all. */
	CHECK(refused(minherit(p + page, page, MAP_INHERIT_COPY), ENOMEM));
	probe_address = p + page;
	CHECK(killed_by(in_child(probe_reads), SIGSEGV));
	/* A wiped range stays so in the child, and is wiped again for its own. */
	memset(p, 7, page);
	probe_address = p;
	int status = in_child(probe_reads);
	CHECK(WIFEXITED(status) && WEXITSTATUS(status) == 2);
	CHECK(filled(p, page, 7));
	return 0;
}

static int inherit_split_child(void)
{
	CHECK(filled(inherit_pages, page, 1));
	CHECK(filled(inherit_pages + page, page, 0));
	CHECK(filled(inherit_pages + 2 * page, page, 3));
	return 0;
}

static int inherit_kept_child(void)
{
	CHECK(filled(inherit_pages, 3 * page, 9));
	return 0;
}

static int inherit_hole_child(void)
{
	CHECK(filled(inherit_pages, page, 9));
	CHECK(filled(inherit_pages + 2 * page, page, 9));
	return 0;
}

static int pledged_minherit(void)
{
	CHECK(pledge("stdio", NULL) == 0);
	unsigned char *p = mmap(NULL, page, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
	CHECK(p != MAP_FAILED);
	CHECK(minherit(p, page, MAP_INHERIT_ZERO) == 0);
	CHECK(madvise(p, page, MADV_WIPEONFORK) == 0);
	return 0;
}

static int run_inherit_tests(void)
{
	page = (size_t)sysconf(_SC_PAGESIZE);

	/* Each of four pages inherited its own way. */
	unsigned char *p = mmap(NULL, 4 * page, PROT_READ | PROT_WRITE,
	    MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
	CHECK(p != MAP_FAILED);
	for (int i = 0; i < 4; i++)
		memset(p + i * page, i + 1, page);
	CHECK(madvise(p, page, MADV_WIPEONFORK) == 0);
	CHECK(madvise(p + page, page, MADV_DONTFORK) == 0);
	CHECK(minherit(p + 2 * page, page, MAP_INHERIT_ZERO) == 0);
	inherit_pages = p;
	CHECK(exited_ok(in_child(inherit_child)));
	/* The parent keeps what it had. */
	for (int i = 0; i < 4; i++)
		CHECK(filled(p + i * page, page, i + 1));
	CHECK(munmap(p, 4 * page) == 0);

	/* The middle of a range, which splits it in three. */
	p = mmap(NULL, 3 * page, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
	CHECK(p != MAP_FAILED);
	for (int i = 0; i < 3; i++)
		memset(p + i * page, i + 1, page);
	CHECK(minherit(p + page, page, MAP_INHERIT_ZERO) == 0);
	inherit_pages = p;
	CHECK(exited_ok(in_child(inherit_split_child)));

	/* Undone: MADV_KEEPONFORK, MADV_DOFORK and MAP_INHERIT_COPY. */
	memset(p, 9, 3 * page);
	CHECK(madvise(p, 3 * page, MADV_KEEPONFORK) == 0);
	CHECK(madvise(p, 3 * page, MADV_DONTFORK) == 0);
	CHECK(madvise(p, 3 * page, MADV_DOFORK) == 0);
	CHECK(minherit(p, 3 * page, MAP_INHERIT_NONE) == 0);
	CHECK(minherit(p, 3 * page, MAP_INHERIT_COPY) == 0);
	CHECK(exited_ok(in_child(inherit_kept_child)));

	/* A hole refuses the whole request: nothing before it changed. */
	CHECK(munmap(p + page, page) == 0);
	CHECK(refused(minherit(p, 3 * page, MAP_INHERIT_ZERO), ENOMEM));
	CHECK(refused(madvise(p, 3 * page, MADV_WIPEONFORK), ENOMEM));
	inherit_pages = p;
	CHECK(exited_ok(in_child(inherit_hole_child)));
	CHECK(munmap(p, 3 * page) == 0);

	/* Wiping is for private anonymous memory; a shared mapping stays one. */
	p = mmap(NULL, page, PROT_READ | PROT_WRITE, MAP_SHARED | MAP_ANONYMOUS, -1, 0);
	CHECK(p != MAP_FAILED);
	CHECK(refused(madvise(p, page, MADV_WIPEONFORK), EINVAL));
	CHECK(refused(minherit(p, page, MAP_INHERIT_ZERO), EINVAL));
	CHECK(refused(minherit(p, page, MAP_INHERIT_COPY), EINVAL));
	CHECK(minherit(p, page, MAP_INHERIT_SHARE) == 0);
	CHECK(refused(minherit(p, page, 7), EINVAL));
	CHECK(munmap(p, page) == 0);

	/* mimmutable(2) fixes how a range is inherited too. */
	p = mmap(NULL, page, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
	CHECK(p != MAP_FAILED);
	CHECK(syscall(SYS_vinix_mimmutable, p, page) == 0);
	CHECK(refused(minherit(p, page, MAP_INHERIT_ZERO), EPERM));
	CHECK(refused(madvise(p, page, MADV_DONTFORK), EPERM));

	/* The stdio promise allows it. */
	CHECK(exited_ok(in_child(pledged_minherit)));
	puts("OPENBSD SECURITY PASS: minherit and fork-time wiping");
	return 0;
}

/* The port getsockname() gives an IPv4 socket, or 0. */
static unsigned local_port(int fd)
{
	struct sockaddr_in address;
	socklen_t length = sizeof(address);
	if (getsockname(fd, (struct sockaddr *)&address, &length) != 0)
		return 0;
	return ntohs(address.sin_port);
}

/* How many of `count` ports come right after the one before. */
static int in_sequence(const unsigned *ports, int count)
{
	int consecutive = 0;
	for (int i = 1; i < count; i++)
		if (ports[i] == ports[i - 1] + 1)
			consecutive++;
	return consecutive;
}

static int ephemeral(unsigned port)
{
	return port >= 49152 && port <= 65535;
}

static struct sockaddr_in ipv4_address(const char *text, unsigned port)
{
	struct sockaddr_in address;
	memset(&address, 0, sizeof(address));
	address.sin_family = AF_INET;
	address.sin_port = htons((uint16_t)port);
	inet_pton(AF_INET, text, &address.sin_addr);
	return address;
}

static double seconds_now(void)
{
	struct timespec now;
	clock_gettime(CLOCK_MONOTONIC, &now);
	return (double)now.tv_sec + now.tv_nsec / 1e9;
}

/* Whether eth0 has an address from DHCP by `deadline`. */
static int wait_for_address(double deadline)
{
	int fd = socket(AF_INET, SOCK_DGRAM, 0);
	if (fd < 0)
		return 0;
	for (;;) {
		struct ifreq request;
		memset(&request, 0, sizeof(request));
		strcpy(request.ifr_name, "eth0");
		if (ioctl(fd, SIOCGIFADDR, &request) == 0) {
			close(fd);
			return 1;
		}
		if (seconds_now() > deadline) {
			close(fd);
			return 0;
		}
		usleep(100000);
	}
}

/* Rounds of connections and datagrams to QEMU's host, whose sequence
 * numbers, ports and IP IDs run_vm.py reads from its capture. Port 9 is
 * discard; whether anything answers does not matter. */
enum { wire_rounds = 8 };

static void send_to_host(void)
{
	struct sockaddr_in host = ipv4_address("10.0.2.2", 9);
	for (int i = 0; i < wire_rounds; i++) {
		int stream = socket(AF_INET, SOCK_STREAM | SOCK_NONBLOCK, 0);
		if (stream >= 0) {
			connect(stream, (struct sockaddr *)&host, sizeof(host));
			struct pollfd wait = {.fd = stream, .events = POLLOUT};
			poll(&wait, 1, 500);
			close(stream);
		}
		int datagram = socket(AF_INET, SOCK_DGRAM, 0);
		if (datagram >= 0) {
			sendto(datagram, "vinix", 5, 0, (struct sockaddr *)&host, sizeof(host));
			close(datagram);
		}
	}
	puts("OPENBSD SECURITY WIRE: sent");
}

static int run_network_tests(void)
{
	enum { count = 16 };
	unsigned ports[count];
	int fds[count];
	struct sockaddr_in loopback = ipv4_address("127.0.0.1", 0);

	/* bind() to port 0. */
	for (int i = 0; i < count; i++) {
		fds[i] = socket(AF_INET, SOCK_DGRAM, 0);
		CHECK(fds[i] >= 0);
		CHECK(bind(fds[i], (struct sockaddr *)&loopback, sizeof(loopback)) == 0);
		ports[i] = local_port(fds[i]);
		CHECK(ephemeral(ports[i]));
	}
	CHECK(in_sequence(ports, count) < 3);
	/* sendto() and connect() on a socket bound to nothing. */
	struct sockaddr_in target = ipv4_address("127.0.0.1", local_port(fds[0]));
	for (int i = 0; i < count; i++) {
		int fd = socket(AF_INET, SOCK_DGRAM, 0);
		CHECK(fd >= 0);
		if (i % 2 == 0)
			CHECK(sendto(fd, "x", 1, 0, (struct sockaddr *)&target, sizeof(target)) == 1);
		else
			CHECK(connect(fd, (struct sockaddr *)&target, sizeof(target)) == 0);
		ports[i] = local_port(fd);
		CHECK(ephemeral(ports[i]));
		close(fd);
	}
	CHECK(in_sequence(ports, count) < 3);
	for (int i = 0; i < count; i++)
		close(fds[i]);

	/* TCP: a listener that never bound, and connections to it. */
	int listener = socket(AF_INET, SOCK_STREAM, 0);
	CHECK(listener >= 0);
	CHECK(listen(listener, count) == 0);
	unsigned listening = local_port(listener);
	CHECK(ephemeral(listening));
	struct sockaddr_in server = ipv4_address("127.0.0.1", listening);
	for (int i = 0; i < count; i++) {
		int client = socket(AF_INET, SOCK_STREAM, 0);
		CHECK(client >= 0);
		CHECK(connect(client, (struct sockaddr *)&server, sizeof(server)) == 0);
		ports[i] = local_port(client);
		CHECK(ephemeral(ports[i]) && ports[i] != listening);
		int accepted = accept(listener, NULL, NULL);
		CHECK(accepted >= 0);
		close(accepted);
		close(client);
	}
	CHECK(in_sequence(ports, count) < 3);
	close(listener);

	/* On the wire, once DHCP has given eth0 an address. */
	CHECK(wait_for_address(seconds_now() + 120));
	send_to_host();
	puts("OPENBSD SECURITY PASS: ports, sequence numbers and IP IDs are random");
	return 0;
}

/* 1 if `path` can be opened and read, -errno if not. */
static int readable(const char *path)
{
	int fd = open(path, O_RDONLY);
	if (fd < 0)
		return -errno;
	char buffer[64];
	ssize_t length = read(fd, buffer, sizeof(buffer));
	int error = errno;
	close(fd);
	return length >= 0 ? 1 : -error;
}

static int proc_readable(pid_t pid, const char *file)
{
	char path[64];
	snprintf(path, sizeof(path), "/proc/%d/%s", (int)pid, file);
	return readable(path);
}

static int become(uid_t id)
{
	return setresgid(id, id, id) == 0 && setresuid(id, id, id) == 0 ? 0 : -1;
}

/* Processes of users 1000 and 1001, waiting to be told to exit. */
static pid_t layout_same, layout_other;

static pid_t user_process(uid_t id, const int ready[2], const int done[2])
{
	fflush(stdout);
	pid_t child = fork();
	if (child == 0) {
		char byte = 0;
		close(done[1]);
		_exit(become(id) == 0 && write(ready[1], &byte, 1) == 1 && read(done[0], &byte, 1) >= 0 ? 0 : 1);
	}
	char byte;
	return child > 0 && read(ready[0], &byte, 1) == 1 ? child : -1;
}

static int layout_reader(void)
{
	static const char *const layout[] = {"maps", "smaps", "auxv"};
	CHECK(become(1000) == 0);
	for (int i = 0; i < 3; i++) {
		CHECK(proc_readable(getpid(), layout[i]) == 1);
		CHECK(proc_readable(layout_same, layout[i]) == 1);
		CHECK(proc_readable(1, layout[i]) == -EACCES);
		CHECK(proc_readable(layout_other, layout[i]) == -EACCES);
	}
	CHECK(readable("/proc/self/maps") == 1);
	/* What any process may know of another stays public. */
	CHECK(proc_readable(1, "status") == 1);
	CHECK(proc_readable(layout_other, "stat") == 1);
	return 0;
}

static int run_layout_tests(void)
{
	int ready[2], done[2];
	CHECK(pipe(ready) == 0 && pipe(done) == 0);
	layout_same = user_process(1000, ready, done);
	layout_other = user_process(1001, ready, done);
	CHECK(layout_same > 0 && layout_other > 0);
	CHECK(proc_readable(layout_other, "maps") == 1);
	int status = in_child(layout_reader);
	close(done[1]);
	CHECK(exited_ok(reap(layout_same)));
	CHECK(exited_ok(reap(layout_other)));
	CHECK(exited_ok(status));
	close(ready[0]);
	close(ready[1]);
	close(done[0]);
	puts("OPENBSD SECURITY PASS: memory layouts are private");
	return 0;
}

/* A root-owned file uid 1000 may only read, and one of uid 1000's own. */
static const char read_only_path[] = "/tmp/vinix-read-only";
static const char own_path[] = "/tmp/vinix-own";

static int read_only_writer(void)
{
	size_t size = (size_t)sysconf(_SC_PAGESIZE);
	CHECK(become(1000) == 0);
	CHECK(open(read_only_path, O_RDWR) == -1 && errno == EACCES);
	int fd = open(read_only_path, O_RDONLY);
	CHECK(fd >= 0);
	/* mprotect() may not make a shared mapping of it writable... */
	char *shared = mmap(NULL, size, PROT_READ, MAP_SHARED, fd, 0);
	CHECK(shared != MAP_FAILED);
	CHECK(mprotect(shared, size, PROT_READ | PROT_WRITE) == -1 && errno == EACCES);
	CHECK(munmap(shared, size) == 0);
	/* ...though it may a private one, which is a copy. */
	char *copy = mmap(NULL, size, PROT_READ, MAP_PRIVATE, fd, 0);
	CHECK(copy != MAP_FAILED);
	CHECK(mprotect(copy, size, PROT_READ | PROT_WRITE) == 0);
	copy[0] = 'X';
	CHECK(munmap(copy, size) == 0);
	/* Nor may copy_file_range() or splice() write it. */
	int own = open(own_path, O_RDWR | O_TRUNC);
	CHECK(own >= 0 && write(own, "attacker", 8) == 8);
	loff_t from = 0, to = 0;
	CHECK(refused((int)copy_file_range(own, &from, fd, &to, 8, 0), EBADF));
	int channel[2];
	CHECK(pipe(channel) == 0 && write(channel[1], "attacker", 8) == 8);
	to = 0;
	CHECK(refused((int)splice(channel[0], NULL, fd, &to, 8, 0), EBADF));
	/* Or read what was opened only for writing. */
	int write_only = open(own_path, O_WRONLY);
	CHECK(write_only >= 0);
	from = 0;
	CHECK(refused((int)splice(write_only, &from, channel[1], NULL, 8, 0), EBADF));
	/* A file opened for writing too can still be mapped shared and raised. */
	shared = mmap(NULL, size, PROT_READ, MAP_SHARED, own, 0);
	CHECK(shared != MAP_FAILED);
	CHECK(mprotect(shared, size, PROT_READ | PROT_WRITE) == 0);
	CHECK(munmap(shared, size) == 0);
	/* O_PATH asks no permission, so it may not be mapped at all. */
	int path_fd = open(read_only_path, O_PATH);
	CHECK(path_fd >= 0);
	CHECK(mmap(NULL, size, PROT_READ, MAP_PRIVATE, path_fd, 0) == MAP_FAILED && errno == EBADF);
	close(path_fd);
	/* vmsplice may not write into a pipe's read end. */
	struct iovec piece = {.iov_base = (void *)"attacker", .iov_len = 8};
	CHECK(vmsplice(channel[0], &piece, 1, 0) == -1 && errno == EBADF);
	return 0;
}

static int run_read_only_tests(void)
{
	CHECK(write_file(read_only_path, "original") == 0);
	CHECK(chmod(read_only_path, 0644) == 0);
	/* The test image's /tmp may not be one that anyone can create files in. */
	CHECK(write_file(own_path, "") == 0 && chown(own_path, 1000, 1000) == 0);
	CHECK(exited_ok(in_child(read_only_writer)));
	char text[16] = {0};
	int fd = open(read_only_path, O_RDONLY);
	CHECK(fd >= 0 && read(fd, text, sizeof(text) - 1) == 8);
	close(fd);
	CHECK(strcmp(text, "original") == 0);
	CHECK(unlink(read_only_path) == 0 && unlink(own_path) == 0);
	puts("OPENBSD SECURITY PASS: read-only files stay read-only");
	return 0;
}

/* chattr's immutable and append-only bits, FS_IOC_SETFLAGS, on a file and a
 * directory, and that securelevel keeps them from being cleared. Run as root
 * (this test is PID 1), the way a file is sealed on a real system. */
static int getflags(const char *path, int *flags)
{
	int fd = open(path, O_RDONLY);
	if (fd < 0)
		return -1;
	int ok = ioctl(fd, FS_IOC_GETFLAGS, flags);
	close(fd);
	return ok;
}

static int setflags(const char *path, int flags)
{
	int fd = open(path, O_RDONLY);
	if (fd < 0)
		return -1;
	int ok = ioctl(fd, FS_IOC_SETFLAGS, &flags);
	int saved = errno;
	close(fd);
	errno = saved;
	return ok;
}

static int write_securelevel(int level)
{
	int fd = open("/proc/sys/kernel/securelevel", O_WRONLY);
	if (fd < 0)
		return -1;
	char text[8];
	int n = snprintf(text, sizeof(text), "%d", level);
	int ok = write(fd, text, (size_t)n) == n ? 0 : -1;
	close(fd);
	return ok;
}

static int run_attribute_tests(void)
{
	const char *file = "/tmp/vinix-immutable";
	const char *dir = "/tmp/vinix-immutable-dir";
	CHECK(write_file(file, "sealed") == 0);
	CHECK(mkdir(dir, 0755) == 0);
	int flags = -1;
	CHECK(getflags(file, &flags) == 0 && flags == 0);

	/* Immutable: no write, truncate, chmod, rename or unlink. */
	CHECK(setflags(file, FS_IMMUTABLE_FL) == 0);
	CHECK(getflags(file, &flags) == 0 && (flags & FS_IMMUTABLE_FL));
	CHECK(open(file, O_WRONLY) == -1 && errno == EPERM);
	CHECK(truncate(file, 0) == -1 && errno == EPERM);
	CHECK(chmod(file, 0600) == -1 && errno == EPERM);
	CHECK(rename(file, "/tmp/vinix-moved") == -1 && errno == EPERM);
	CHECK(unlink(file) == -1 && errno == EPERM);
	CHECK(link(file, "/tmp/vinix-link") == -1 && errno == EPERM);
	/* Cleared again, it is an ordinary file. */
	CHECK(setflags(file, 0) == 0);
	CHECK(open(file, O_WRONLY) >= 0);

	/* Append-only: opens only O_APPEND, no truncate, no unlink. */
	CHECK(setflags(file, FS_APPEND_FL) == 0);
	CHECK(open(file, O_WRONLY) == -1 && errno == EPERM);
	CHECK(open(file, O_WRONLY | O_TRUNC | O_APPEND) == -1 && errno == EPERM);
	int afd = open(file, O_WRONLY | O_APPEND);
	CHECK(afd >= 0 && write(afd, "more", 4) == 4);
	/* pwrite and fallocate may not reach past the append, nor overwrite it. */
	CHECK(pwrite(afd, "zz", 2, 0) == -1 && errno == EPERM);
	CHECK(fallocate(afd, 0, 0, 4096) == -1 && errno == EPERM);
	close(afd);
	CHECK(link(file, "/tmp/vinix-append-link") == -1 && errno == EPERM);
	CHECK(unlink(file) == -1 && errno == EPERM);
	/* chmod is allowed on an append-only file, as on Linux. */
	CHECK(chmod(file, 0640) == 0);
	CHECK(setflags(file, 0) == 0);

	/* Immutable directory: nothing made or removed in it. */
	CHECK(write_file("/tmp/vinix-immutable-dir/keep", "x") == 0);
	CHECK(setflags(dir, FS_IMMUTABLE_FL) == 0);
	CHECK(open("/tmp/vinix-immutable-dir/new", O_WRONLY | O_CREAT, 0644) == -1 && errno == EPERM);
	CHECK(mkdir("/tmp/vinix-immutable-dir/sub", 0755) == -1 && errno == EPERM);
	CHECK(unlink("/tmp/vinix-immutable-dir/keep") == -1 && errno == EPERM);
	CHECK(setflags(dir, 0) == 0);
	CHECK(unlink("/tmp/vinix-immutable-dir/keep") == 0);
	CHECK(rmdir(dir) == 0);

	/* securelevel: a set bit cannot be cleared above 0, even by root. */
	CHECK(setflags(file, FS_IMMUTABLE_FL) == 0);
	CHECK(write_securelevel(1) == 0);
	CHECK(setflags(file, 0) == -1 && errno == EPERM);
	CHECK(getflags(file, &flags) == 0 && (flags & FS_IMMUTABLE_FL));
	/* Raising a bit, without clearing the set one, is still allowed. */
	CHECK(setflags(file, FS_IMMUTABLE_FL | FS_APPEND_FL) == 0);
	puts("OPENBSD SECURITY PASS: immutable and append-only files");
	return 0;
}

static int run_tests(void)
{
	if (run_pledge_tests() != 0 || run_unveil_tests() != 0 || run_signal_tests() != 0
	    || run_pid_tests() != 0 || run_break_tests() != 0 || run_inherit_tests() != 0
	    || run_network_tests() != 0 || run_layout_tests() != 0
	    || run_read_only_tests() != 0 || run_attribute_tests() != 0)
		return 1;
	puts("VINIX OPENBSD SECURITY: PASS");
	return 0;
}

int main(int argc, char **argv)
{
	if (argc == 2 && strcmp(argv[1], "--pledged-child-opens") == 0)
		return pledged_child_opens();
	if (argc == 2 && strcmp(argv[1], "--read-secret") == 0)
		return read_secret();
	if (argc == 2 && strcmp(argv[1], "--print-break") == 0) {
		printf("%lx\n", (unsigned long)(uintptr_t)sbrk(0));
		return 0;
	}
	setbuf(stdout, NULL);
	setbuf(stderr, NULL);
	if (getpid() != 1)
		return run_tests();
	/* amd64 has its serial port as /dev/com1; arm64 routes the console to
	 * serial already. */
	int console = open("/dev/com1", O_WRONLY);
	if (console < 0)
		console = open("/dev/console", O_WRONLY);
	if (console >= 0) {
		dup2(console, STDOUT_FILENO);
		dup2(console, STDERR_FILENO);
		close(console);
	}
	mkdir("/tmp", 01777);
	puts("VINIX OPENBSD SECURITY: START");
	pid_t worker = fork();
	if (worker == 0)
		_exit(run_tests());
	if (worker < 0 || !exited_ok(reap(worker)))
		puts("VINIX OPENBSD SECURITY: FAIL");
	for (;;)
		sleep(1);
}

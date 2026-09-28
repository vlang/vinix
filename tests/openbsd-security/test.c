// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

/* SPDX-License-Identifier: BSD-2-Clause
 * In-guest regression coverage for Vinix's OpenBSD security features:
 * pledge(2), unveil(2) and signed signal frames. Built statically for either architecture and run
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
#include <sys/mount.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/uio.h>
#include <sys/wait.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>

#if defined(__aarch64__)
#define SYS_vinix_pledge 248
#define SYS_vinix_unveil 249
#elif defined(__x86_64__)
#define SYS_vinix_pledge 501
#define SYS_vinix_unveil 502
#else
#error "unsupported architecture"
#endif

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

static int run_tests(void)
{
	if (run_pledge_tests() != 0 || run_unveil_tests() != 0 || run_signal_tests() != 0)
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

#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/reboot.h>
#include <sys/select.h>
#include <sys/stat.h>
#include <sys/statfs.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

struct snapshot {
	long free_kib, slab_kib, cached_kib;
	long size[32], objects[32], pages[32], large_pages;
	size_t classes;
};

static int failures, null_fd;
#ifdef CHURN_DIRECTORIES_ONLY
#define COHORT_RUNS 200
#else
#define COHORT_RUNS 300
#endif
static unsigned long long now_ns(void) {
	struct timespec time;
	if (clock_gettime(CLOCK_MONOTONIC, &time)) { failures++; return 0; }
	return (unsigned long long)time.tv_sec * 1000000000ull + time.tv_nsec;
}
static void pause_until(unsigned long long deadline) {
	for (;;) {
		unsigned long long now = now_ns();
		if (now >= deadline) return;
		unsigned long long left = deadline - now;
		struct timespec requested = {left / 1000000000ull, left % 1000000000ull};
		if (nanosleep(&requested, NULL) && errno != EINTR) { failures++; return; }
	}
}
static int run(char *const argv[]) {
	pid_t child = fork();
	if (child < 0) return -1;
	if (!child) {
		if (argv) {
			dup2(null_fd, STDOUT_FILENO); dup2(null_fd, STDERR_FILENO);
			execv(argv[0], argv); _exit(127);
		}
		_exit(0);
	}
	int status;
	while (waitpid(child, &status, 0) < 0) if (errno != EINTR) return -1;
	return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
}
static void settle(const char *program, int cohort) {
	unsigned long long start = now_ns();
	pause_until(start + 6000000000ull);
	// Quarantine draining happens at another reap, not merely as time passes.
	failures += run(NULL) != 0;
	pause_until(now_ns() + 100000000ull);
	unsigned long long elapsed = now_ns() - start;
	if (elapsed < 6000000000ull) failures++;
	printf("CHURN GRACE program=%s cohort=%d elapsed_ns=%llu\n",
		program, cohort, elapsed);
}
static void copy_proc(const char *path, const char *label, int cohort) {
	FILE *file = fopen(path, "r");
	if (!file) { failures++; return; }
	char line[2048];
	while (fgets(line, sizeof line, file))
		if (label) printf("PERF-SITE program=%s cohort=%d %s", label, cohort, line);
	fclose(file);
}
static struct snapshot sample(void) {
	struct snapshot result = {.free_kib = -1, .slab_kib = -1, .cached_kib = -1};
	FILE *file = fopen("/proc/meminfo", "r");
	if (!file) { failures++; return result; }
	char line[256], name[64]; long value;
	while (fgets(line, sizeof line, file)) if (sscanf(line, "%63s %ld", name, &value) == 2) {
		if (!strcmp(name, "MemFree:")) result.free_kib = value;
		if (!strcmp(name, "Slab:")) result.slab_kib = value;
		if (!strcmp(name, "Cached:")) result.cached_kib = value;
	}
	fclose(file);
	file = fopen("/proc/slabinfo", "r");
	if (!file) { failures++; return result; }
	while (fgets(line, sizeof line, file)) {
		long label, size, objects, pages;
		if (sscanf(line, "size-%ld %ld %ld %ld", &label, &size, &objects, &pages) == 4) {
			if (result.classes == 32 || label != size) { failures++; continue; }
			size_t i = result.classes++;
			result.size[i] = size; result.objects[i] = objects; result.pages[i] = pages;
		} else if (sscanf(line, "large - - %ld", &pages) == 1) result.large_pages = pages;
	}
	fclose(file);
	if (result.free_kib < 0 || result.slab_kib < 0 || result.cached_kib < 0) failures++;
	return result;
}
static void report(const char *name, int cohort, struct snapshot initial,
                   struct snapshot before, struct snapshot after) {
	printf("CHURN MEASURE program=%s cohort=%d runs=%d used_delta_kib=%ld cumulative_used_kib=%ld slab_delta_kib=%ld cumulative_slab_kib=%ld cached_delta_kib=%ld large_pages_delta=%ld\n",
		name, cohort, COHORT_RUNS, before.free_kib - after.free_kib, initial.free_kib - after.free_kib,
		after.slab_kib - before.slab_kib, after.slab_kib - initial.slab_kib,
		after.cached_kib - before.cached_kib, after.large_pages - before.large_pages);
	if (after.classes != before.classes) failures++;
	for (size_t i = 0; i < after.classes; i++) {
		if (after.size[i] != before.size[i]) failures++;
		if (after.objects[i] != before.objects[i] || after.pages[i] != before.pages[i])
			printf("CHURN CLASS program=%s cohort=%d size=%ld objects_delta=%ld cumulative_objects=%ld pages_delta=%ld\n",
				name, cohort, after.size[i], after.objects[i] - before.objects[i],
				after.objects[i] - initial.objects[i], after.pages[i] - before.pages[i]);
	}
	copy_proc("/proc/allocsites", name, cohort);
}
#ifdef CHURN_WAITS_ONLY
static int fork_path_check(void) {
	char expected[128], actual[128];
	ssize_t length = readlink("/proc/self/exe", expected, sizeof expected);
	if (length <= 0 || (size_t)length >= sizeof expected) return -1;
	pid_t child = fork();
	if (child < 0) return -1;
	if (!child) {
		ssize_t copied = readlink("/proc/self/exe", actual, sizeof actual);
		_exit(copied != length || memcmp(expected, actual, length) != 0);
	}
	int status;
	while (waitpid(child, &status, 0) < 0) if (errno != EINTR) return -1;
	return WIFEXITED(status) && WEXITSTATUS(status) == 0 ? 0 : -1;
}
static void wait_operation(int probe) {
	if (probe == 0) return;
	if (probe == 3) { failures += run(NULL) != 0; return; }
	struct timespec requested = {.tv_nsec = 1000000}, remain = {0};
	for (;;) {
		long result = probe == 1 ? syscall(SYS_nanosleep, &requested, &remain)
			: syscall(SYS_clock_nanosleep, CLOCK_MONOTONIC, 0, &requested, &remain);
		if (!result) return;
		if (errno != EINTR) { failures++; return; }
		requested = remain;
	}
}
static int waits_measurement(void) {
	if (fork_path_check()) {
		puts("PROCESS CHURN: FAIL inherited executable path"); return 1;
	}
	puts("CHURN SEMANTICS: fork executable path preserved");
	const char *names[] = {"idle_control", "nanosleep", "clock_nanosleep", "fork_reap"};
	for (int probe = 0; probe < 4; probe++) {
		for (int i = 0; i < 20; i++) wait_operation(probe);
		settle(names[probe], 0); (void)sample();
		copy_proc("/proc/allocstart", NULL, 0);
		struct snapshot initial = sample(), before = initial;
		for (int cohort = 1; cohort <= 3; cohort++) {
			unsigned long long started = now_ns();
			for (int i = 0; i < 300; i++) {
				wait_operation(probe);
				if (probe == 3 && (i + 1) % 25 == 0)
					printf("CHURN PROGRESS program=%s cohort=%d completed=%d\n",
						names[probe], cohort, i + 1);
			}
			printf("CHURN WORK program=%s cohort=%d calls=300 elapsed_ns=%llu\n",
				names[probe], cohort, now_ns() - started);
			settle(names[probe], cohort);
			struct snapshot after = sample();
			report(names[probe], cohort, initial, before, after); before = after;
		}
	}
	printf("PROCESS CHURN: %s failures=%d\n", failures ? "FAIL" : "DONE", failures);
	sync(); reboot(RB_POWER_OFF); return failures != 0;
}
#endif
#ifdef CHURN_DIRECTORIES_ONLY
static void directory_operation(const char *parent, int i) {
	char path[128];
	snprintf(path, sizeof path, "%s/churn-dir-%d", parent, i);
	if (mkdir(path, 0755) || rmdir(path)) failures++;
}
static void trigger_retirement(void) {
	// Retire one regular-file node after the grace period, so already-due
	// removals are actively drained. Its bounded final node is present in
	// the initial snapshot as well as each later one.
	int fd = open("/tmp/churn-drain", O_CREAT | O_WRONLY | O_TRUNC, 0600);
	if (fd < 0) { failures++; return; }
	if (close(fd) || unlink("/tmp/churn-drain")) failures++;
}
static int directories_measurement(void) {
	const char *parents[] = {"/tmp", "/root"};
	const char *names[] = {"mkdir_tmpfs", "mkdir_ext2"};
	const unsigned long expected[] = {0x01021994, 0xef53};
	for (int probe = 0; probe < 2; probe++) {
		struct statfs filesystem;
		if (statfs(parents[probe], &filesystem) || (unsigned long)filesystem.f_type != expected[probe]) {
			printf("PROCESS CHURN: FAIL filesystem=%s\n", parents[probe]); failures++; break;
		}
		printf("CHURN FILESYSTEM program=%s type=%lx\n", names[probe], (unsigned long)filesystem.f_type);
		for (int i = 0; i < 20; i++) directory_operation(parents[probe], i);
		settle(names[probe], 0); trigger_retirement(); (void)sample();
		copy_proc("/proc/allocstart", NULL, 0);
		struct snapshot initial = sample(), before = initial;
		for (int cohort = 1; cohort <= 3; cohort++) {
			for (int i = 0; i < 200; i++) directory_operation(parents[probe], i);
			settle(names[probe], cohort); trigger_retirement();
			struct snapshot after = sample();
			report(names[probe], cohort, initial, before, after); before = after;
		}
	}
	printf("PROCESS CHURN: %s failures=%d\n", failures ? "FAIL" : "DONE", failures);
	sync(); reboot(RB_POWER_OFF); return failures != 0;
}
#endif
#ifdef CHURN_PIPES_ONLY
static void pipe_operation(void) {
	int descriptors[2];
	if (pipe(descriptors)) { failures++; return; }
	const unsigned char sent = 0x5a;
	unsigned char received = 0;
	if (write(descriptors[1], &sent, 1) != 1 ||
		read(descriptors[0], &received, 1) != 1 || received != sent) failures++;
	if (close(descriptors[0])) failures++;
	if (close(descriptors[1])) failures++;
}
static int pipes_measurement(void) {
	for (int i = 0; i < 20; i++) pipe_operation();
	settle("pipe", 0); (void)sample();
	copy_proc("/proc/allocstart", NULL, 0);
	struct snapshot initial = sample(), before = initial;
	for (int cohort = 1; cohort <= 3; cohort++) {
		for (int i = 0; i < 300; i++) pipe_operation();
		settle("pipe", cohort);
		struct snapshot after = sample();
		report("pipe", cohort, initial, before, after); before = after;
	}
	printf("PROCESS CHURN: %s failures=%d\n", failures ? "FAIL" : "DONE", failures);
	sync(); reboot(RB_POWER_OFF); return failures != 0;
}
#endif
#ifdef CHURN_SAMPLING_ONLY
static int sampling_measurement(void) {
	for (int i = 0; i < 20; i++) (void)sample();
	settle("sampling", 0); (void)sample();
	copy_proc("/proc/allocstart", NULL, 0);
	struct snapshot initial = sample(), before = initial;
	for (int cohort = 1; cohort <= 3; cohort++) {
		for (int i = 0; i < 300; i++) (void)sample();
		settle("sampling", cohort);
		struct snapshot after = sample();
		report("sampling", cohort, initial, before, after); before = after;
	}
	printf("PROCESS CHURN: %s failures=%d\n", failures ? "FAIL" : "DONE", failures);
	sync(); reboot(RB_POWER_OFF); return failures != 0;
}
#endif
#ifdef CHURN_SELECT_ONLY
static volatile sig_atomic_t select_signals;
static void select_signal(int number) { (void)number; select_signals++; }
struct select_mask_arg { uint64_t address, size; };
#define SELECT_REQUIRE(condition) do { \
	if (!(condition)) { \
		printf("PROCESS CHURN: FAIL select semantics line=%d errno=%d\n", __LINE__, errno); \
		return -1; \
	} \
} while (0)
static int select_semantics(int ready_fd) {
	fd_set readable;
	struct timespec timeout = {.tv_nsec = 1000000};
	uint64_t mask = 0;
	struct select_mask_arg argument = {.address = (uintptr_t)&mask, .size = 8};
	errno = 0;
	SELECT_REQUIRE(syscall(SYS_pselect6, ready_fd + 1, (void *)1, NULL, NULL,
		&timeout, NULL) == -1 && errno == EFAULT);
	errno = 0;
	SELECT_REQUIRE(syscall(SYS_pselect6, ready_fd + 1, NULL, NULL, NULL,
		(void *)1, NULL) == -1 && errno == EFAULT);
	errno = 0;
	SELECT_REQUIRE(syscall(SYS_pselect6, ready_fd + 1, NULL, NULL, NULL,
		&timeout, (void *)1) == -1 && errno == EFAULT);
	argument.address = 1;
	errno = 0;
	SELECT_REQUIRE(syscall(SYS_pselect6, ready_fd + 1, NULL, NULL, NULL,
		&timeout, &argument) == -1 && errno == EFAULT);
	argument.address = (uintptr_t)&mask; argument.size = 7;
	errno = 0;
	SELECT_REQUIRE(syscall(SYS_pselect6, ready_fd + 1, NULL, NULL, NULL,
		&timeout, &argument) == -1 && errno == EINVAL);
	argument.size = 8;
	struct sigaction action = {.sa_handler = select_signal}, previous_action;
	sigemptyset(&action.sa_mask);
	SELECT_REQUIRE(sigaction(SIGUSR1, &action, &previous_action) == 0);
	sigset_t blocked, original, observed;
	sigemptyset(&blocked); sigaddset(&blocked, SIGUSR1);
	SELECT_REQUIRE(sigprocmask(SIG_BLOCK, &blocked, &original) == 0);
	FD_ZERO(&readable); FD_SET(ready_fd, &readable);
	SELECT_REQUIRE(syscall(SYS_pselect6, ready_fd + 1, &readable, NULL, NULL,
		&timeout, &argument) == 1 && FD_ISSET(ready_fd, &readable));
	SELECT_REQUIRE(sigprocmask(SIG_BLOCK, NULL, &observed) == 0 &&
		sigismember(&observed, SIGUSR1));
	int empty[2];
	SELECT_REQUIRE(pipe(empty) == 0 && empty[0] < FD_SETSIZE);
	FD_ZERO(&readable); FD_SET(empty[0], &readable);
	timeout.tv_nsec = 10000000;
	unsigned long long started = now_ns();
	SELECT_REQUIRE(syscall(SYS_pselect6, empty[0] + 1, &readable, NULL, NULL,
		&timeout, &argument) == 0 && !FD_ISSET(empty[0], &readable));
	SELECT_REQUIRE(now_ns() - started >= 10000000);
	SELECT_REQUIRE(sigprocmask(SIG_BLOCK, NULL, &observed) == 0 &&
		sigismember(&observed, SIGUSR1));
	SELECT_REQUIRE(kill(getpid(), SIGUSR1) == 0);
	FD_ZERO(&readable); FD_SET(empty[0], &readable);
	timeout = (struct timespec){.tv_sec = 1};
	errno = 0;
	SELECT_REQUIRE(syscall(SYS_pselect6, empty[0] + 1, &readable, NULL, NULL,
		&timeout, &argument) == -1 && errno == EINTR && select_signals == 1);
	SELECT_REQUIRE(sigprocmask(SIG_BLOCK, NULL, &observed) == 0 &&
		sigismember(&observed, SIGUSR1));
	SELECT_REQUIRE(sigpending(&observed) == 0 && !sigismember(&observed, SIGUSR1));
	pid_t child = fork();
	SELECT_REQUIRE(child >= 0);
	if (!child) {
		struct timespec delay = {.tv_nsec = 50000000};
		while (nanosleep(&delay, &delay)) if (errno != EINTR) _exit(2);
		_exit(write(empty[1], "w", 1) == 1 ? 0 : 3);
	}
	FD_ZERO(&readable); FD_SET(empty[0], &readable);
	SELECT_REQUIRE(syscall(SYS_pselect6, empty[0] + 1, &readable, NULL, NULL,
		&timeout, &argument) == 1 && FD_ISSET(empty[0], &readable));
	unsigned char value = 0;
	SELECT_REQUIRE(read(empty[0], &value, 1) == 1 && value == 'w');
	int status;
	while (waitpid(child, &status, 0) < 0) SELECT_REQUIRE(errno == EINTR);
	SELECT_REQUIRE(WIFEXITED(status) && WEXITSTATUS(status) == 0);
	SELECT_REQUIRE(sigprocmask(SIG_BLOCK, NULL, &observed) == 0 &&
		sigismember(&observed, SIGUSR1));
	SELECT_REQUIRE(sigprocmask(SIG_SETMASK, &original, NULL) == 0);
	SELECT_REQUIRE(sigaction(SIGUSR1, &previous_action, NULL) == 0);
	SELECT_REQUIRE(close(empty[0]) == 0 && close(empty[1]) == 0);
	puts("CHURN SEMANTICS: pselect pointers, masks, timeout, interruption, wake");
	return 0;
}
static void select_operation(int probe, int fd, int iteration) {
	fd_set readable;
	FD_ZERO(&readable); FD_SET(fd, &readable);
	struct timeval relative = {.tv_usec = 1000};
	struct timespec duration = {.tv_nsec = 1000000};
	long ready = probe == 0
		? select(fd + 1, &readable, NULL, NULL, iteration % 2 ? &relative : NULL)
		: syscall(SYS_pselect6, fd + 1, &readable, NULL, NULL,
			iteration % 2 ? &duration : NULL, NULL);
	if (ready != 1 || !FD_ISSET(fd, &readable)) failures++;
}
static int select_measurement(void) {
	int descriptors[2];
	const unsigned char sent = 0x5a;
	if (pipe(descriptors) || descriptors[0] >= FD_SETSIZE ||
		write(descriptors[1], &sent, 1) != 1) {
		puts("PROCESS CHURN: FAIL select fixture"); return 1;
	}
	if (select_semantics(descriptors[0])) return 1;
	const char *names[] = {"select_ready", "pselect_ready"};
	for (int probe = 0; probe < 2; probe++) {
		for (int i = 0; i < 20; i++) select_operation(probe, descriptors[0], i);
		settle(names[probe], 0); (void)sample();
		copy_proc("/proc/allocstart", NULL, 0);
		struct snapshot initial = sample(), before = initial;
		for (int cohort = 1; cohort <= 3; cohort++) {
			for (int i = 0; i < 300; i++) select_operation(probe, descriptors[0], i);
			settle(names[probe], cohort);
			struct snapshot after = sample();
			report(names[probe], cohort, initial, before, after); before = after;
		}
	}
	unsigned char received = 0;
	if (read(descriptors[0], &received, 1) != 1 || received != sent) failures++;
	if (close(descriptors[0])) failures++;
	if (close(descriptors[1])) failures++;
	printf("PROCESS CHURN: %s failures=%d\n", failures ? "FAIL" : "DONE", failures);
	sync(); reboot(RB_POWER_OFF); return failures != 0;
}
#endif
#ifdef CHURN_SLABINFO_ONLY
static int slabinfo_measurement(void) {
	settle("slabinfo", 0); (void)sample();
	copy_proc("/proc/allocstart", NULL, 0);
	struct snapshot initial = sample(), before = initial;
	for (int cohort = 1; cohort <= 3; cohort++) {
		for (int i = 0; i < 300; i++) copy_proc("/proc/slabinfo", NULL, 0);
		settle("slabinfo", cohort);
		struct snapshot after = sample();
		report("slabinfo", cohort, initial, before, after); before = after;
	}
	printf("PROCESS CHURN: %s failures=%d\n", failures ? "FAIL" : "DONE", failures);
	sync(); reboot(RB_POWER_OFF); return failures != 0;
}
#endif
int main(void) {
#if defined(__x86_64__)
	int serial = open("/dev/com1", O_WRONLY | O_NOCTTY);
	if (serial >= 0) { dup2(serial, STDOUT_FILENO); dup2(serial, STDERR_FILENO); close(serial); }
#endif
	setvbuf(stdout, NULL, _IONBF, 0);
	puts("PROCESS CHURN: START");
#ifdef CHURN_SLABINFO_ONLY
	return slabinfo_measurement();
#endif
#ifdef CHURN_WAITS_ONLY
	return waits_measurement();
#endif
#ifdef CHURN_DIRECTORIES_ONLY
	return directories_measurement();
#endif
#ifdef CHURN_PIPES_ONLY
	return pipes_measurement();
#endif
#ifdef CHURN_SAMPLING_ONLY
	return sampling_measurement();
#endif
#ifdef CHURN_SELECT_ONLY
	return select_measurement();
#endif
	setenv("PATH", "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin", 1);
	setenv("HOME", "/root", 1); setenv("TERM", "linux", 1);
	setenv("USER", "root", 1); setenv("LOGNAME", "root", 1);
	setenv("SHELL", "/bin/zsh", 1); setenv("LD_LIBRARY_PATH", "/usr/lib:/usr/lib/xorg/modules", 1);
	setenv("XDG_RUNTIME_DIR", "/run/user/0", 1);
	setenv("XDG_CONFIG_HOME", "/root/.config", 1); setenv("XDG_CACHE_HOME", "/root/.cache", 1);
	null_fd = open("/dev/null", O_RDWR | O_NOCTTY);
	if (null_fd < 0) return 1;
	char *programs[][5] = {{"/bin/true", NULL}, {"/bin/sleep", "0", NULL},
		{"/usr/bin/curl", "--version", NULL}, {"/bin/busybox", "awk", "BEGIN{}", NULL}};
	const char *names[] = {"true", "sleep", "curl", "awk"};
	for (size_t program = 0; program < sizeof programs / sizeof *programs; program++) {
		for (int i = 0; i < 20; i++) failures += run(programs[program]) != 0;
		settle(names[program], 0); (void)sample();
		copy_proc("/proc/allocstart", NULL, 0);
		struct snapshot initial = sample(), before = initial;
		for (int cohort = 1; cohort <= 3; cohort++) {
			for (int i = 0; i < 300; i++) failures += run(programs[program]) != 0;
			settle(names[program], cohort);
			struct snapshot after = sample();
			report(names[program], cohort, initial, before, after);
			before = after;
		}
	}
	close(null_fd);
	printf("PROCESS CHURN: %s failures=%d\n", failures ? "FAIL" : "DONE", failures);
	sync(); reboot(RB_POWER_OFF); return failures != 0;
}

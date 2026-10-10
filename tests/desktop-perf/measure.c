/*
 * Measure the desktop's CPU and memory from inside the guest.
 *
 * Reads /dev/processes, the same snapshot the Activity Monitor uses, at the
 * start and end of a window. CPU is the growth of each process' CPU-time
 * counter over the kernel's own sample clock, as a percentage of one CPU.
 * Memory is sampled every few seconds through the window and reported as the
 * mean, so a single sample that caught a process mid-remap (the kernel reports
 * it as 0) cannot decide the result.
 *
 * The kernel's per-process figure is the memory each process has resident,
 * each page counted as its share. The total is also measured another way: the
 * machine's used memory while the desktop runs, less what was used just before
 * it started (`measure used`); nothing else changes between those two
 * readings, and it includes what the kernel keeps for the processes.
 *
 * The desktop is the compositor and every process below it: its native
 * application processes and whatever those started, such as the Terminal's
 * shell. The image carries no Python, so this is a static C program.
 *
 * Usage:
 *     measure used                                print the bytes in use now
 *     measure sample PID SECONDS USED LABEL...    print PERF-RESULT and PERF-PROC
 *                                                 lines; USED is `measure used`
 *                                                 from before the desktop started
 *     measure tree PID                            print the pids below PID, deepest first
 *     measure wakeups MS SECONDS LABEL...         sleep MS at a time, first with
 *                                                 nanosleep and then with poll, and
 *                                                 print the CPU time each cost: the
 *                                                 kernel's share of the compositor's
 *                                                 frame pacing, with nothing drawn
 *     measure ops COUNT LABEL...                  do each common kind of system call
 *                                                 COUNT times and print what the
 *                                                 kernel heap kept, per size class
 *                                                 from /proc/slabinfo: what a desktop
 *                                                 doing it all day would leak
 *     measure churn COUNT LABEL...                run short programs with one
 *                                                 observer across both snapshots
 */
#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <pthread.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/epoll.h>
#include <sys/eventfd.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/timerfd.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <netinet/in.h>
#include <time.h>
#include <unistd.h>

#define MAX_RECORDS 512
#define NAME_LEN 64
#define MEMORY_PERIOD_S 5

/* Mirrors kernel/dev/procdev/procdev.v, as desktop/activity.v does. */
struct table {
	uint32_t version, record_size, count, total;
	uint64_t sample_ns, total_memory, free_memory;
};

struct record {
	int32_t pid, ppid, threads, reserved;
	uint64_t memory_bytes, cpu_time_ns;
	char name[NAME_LEN];
};

struct snapshot {
	struct table header;
	struct record records[MAX_RECORDS];
};

static int take(struct snapshot *out) {
	static unsigned char buffer[sizeof(struct table) + MAX_RECORDS * sizeof(struct record)];
	int fd = open("/dev/processes", O_RDONLY);
	if (fd < 0)
		return -1;
	ssize_t got = read(fd, buffer, sizeof buffer);
	close(fd);
	if (got < (ssize_t)sizeof(struct table))
		return -1;
	memcpy(&out->header, buffer, sizeof out->header);
	uint32_t size = out->header.record_size;
	if (size == 0 || size > sizeof(struct record))
		size = sizeof(struct record);
	if (out->header.count > MAX_RECORDS)
		out->header.count = MAX_RECORDS;
	memset(out->records, 0, sizeof out->records);
	for (uint32_t i = 0; i < out->header.count; i++)
		memcpy(&out->records[i], buffer + sizeof(struct table) + i * size, size);
	return 0;
}

static const struct record *find(const struct snapshot *s, int pid) {
	for (uint32_t i = 0; i < s->header.count; i++)
		if (s->records[i].pid == pid)
			return &s->records[i];
	return NULL;
}

/* root followed by every pid below it, parents before children. */
static int tree(const struct snapshot *s, int root, int *out) {
	int n = 0;
	out[n++] = root;
	for (int next = 0; next < n; next++)
		for (uint32_t i = 0; i < s->header.count && n < MAX_RECORDS; i++)
			if (s->records[i].ppid == out[next] && s->records[i].pid != root)
				out[n++] = s->records[i].pid;
	return n;
}

static int member(const int *pids, int n, int pid) {
	for (int i = 0; i < n; i++)
		if (pids[i] == pid)
			return 1;
	return 0;
}

static struct snapshot first, current, last;

static int sample(int root, int seconds, uint64_t base_used, const char *label) {
	static int pids[MAX_RECORDS], memory_pids[MAX_RECORDS];
	static uint64_t memory_sum[MAX_RECORDS];
	static int memory_count[MAX_RECORDS];
	int memory_n = 0;
	uint64_t used_sum = 0;
	int used_count = 0;

	if (take(&first) < 0) {
		printf("PERF-ERROR %s cannot read /dev/processes\n", label);
		return 1;
	}
	struct timespec started;
	clock_gettime(CLOCK_MONOTONIC, &started);
	for (;;) {
		struct timespec now;
		clock_gettime(CLOCK_MONOTONIC, &now);
		long remaining = seconds - (now.tv_sec - started.tv_sec);
		if (remaining <= 0)
			break;
		sleep(remaining < MEMORY_PERIOD_S ? (unsigned)remaining : MEMORY_PERIOD_S);
		if (take(&current) < 0)
			continue;
		used_sum += current.header.total_memory - current.header.free_memory;
		used_count++;
		int n = tree(&current, root, pids);
		for (int i = 0; i < n; i++) {
			const struct record *r = find(&current, pids[i]);
			if (!r || r->memory_bytes == 0)
				continue;
			int slot = 0;
			while (slot < memory_n && memory_pids[slot] != pids[i])
				slot++;
			if (slot == memory_n) {
				if (memory_n == MAX_RECORDS)
					continue;
				memory_pids[memory_n++] = pids[i];
			}
			memory_sum[slot] += r->memory_bytes;
			memory_count[slot]++;
		}
	}
	if (take(&last) < 0) {
		printf("PERF-ERROR %s cannot read /dev/processes\n", label);
		return 1;
	}

	uint64_t span = last.header.sample_ns - first.header.sample_ns;
	if (span == 0) {
		printf("PERF-ERROR %s the sample clock did not advance\n", label);
		return 1;
	}
	int n = tree(&last, root, pids);
	double desktop_cpu = 0, apps_cpu = 0;
	uint64_t desktop_memory = 0, apps_memory = 0;
	for (int i = 0; i < n; i++) {
		const struct record *after = find(&last, pids[i]);
		if (!after)
			continue;
		const struct record *before = find(&first, pids[i]);
		uint64_t cpu_ns = after->cpu_time_ns - (before ? before->cpu_time_ns : 0);
		double cpu = 100.0 * (double)cpu_ns / (double)span;
		uint64_t memory = after->memory_bytes;
		for (int slot = 0; slot < memory_n; slot++)
			if (memory_pids[slot] == pids[i] && memory_count[slot] > 0)
				memory = memory_sum[slot] / (uint64_t)memory_count[slot];
		if (pids[i] == root) {
			desktop_cpu = cpu;
			desktop_memory = memory;
		} else {
			apps_cpu += cpu;
			apps_memory += memory;
		}
		printf("PERF-PROC %s pid=%d ppid=%d name=%s threads=%d cpu=%.2f memory_mb=%.1f\n",
		       label, after->pid, after->ppid, after->name, after->threads, cpu,
		       (double)memory / 1e6);
	}

	/* Everything else on the machine, for context: a background task that
	 * woke during the window shows up here and not in the desktop's figures. */
	int shown[5];
	for (int count = 0; count < 5; count++) {
		const struct record *top = NULL;
		uint64_t top_ns = 0;
		for (uint32_t i = 0; i < last.header.count; i++) {
			const struct record *after = &last.records[i];
			if (member(pids, n, after->pid) || member(shown, count, after->pid))
				continue;
			const struct record *before = find(&first, after->pid);
			uint64_t cpu_ns = after->cpu_time_ns - (before ? before->cpu_time_ns : 0);
			if (cpu_ns > top_ns) {
				top_ns = cpu_ns;
				top = after;
			}
		}
		if (!top)
			break;
		shown[count] = top->pid;
		printf("PERF-OTHER %s pid=%d name=%s cpu=%.2f\n", label, top->pid, top->name,
		       100.0 * (double)top_ns / (double)span);
	}

	uint64_t used = used_count ? used_sum / (uint64_t)used_count
	                           : last.header.total_memory - last.header.free_memory;
	printf("PERF-RESULT %s seconds=%.1f processes=%d desktop_cpu=%.2f apps_cpu=%.2f "
	       "total_cpu=%.2f desktop_mb=%.1f apps_mb=%.1f total_mb=%.1f system_used_mb=%.1f "
	       "physical_mb=%.1f\n",
	       label, (double)span / 1e9, n, desktop_cpu, apps_cpu, desktop_cpu + apps_cpu,
	       (double)desktop_memory / 1e6, (double)apps_memory / 1e6,
	       (double)(desktop_memory + apps_memory) / 1e6, (double)used / 1e6,
	       ((double)used - (double)base_used) / 1e6);
	return 0;
}

static double seconds_of(clockid_t clock) {
	struct timespec now;
	clock_gettime(clock, &now);
	return (double)now.tv_sec + (double)now.tv_nsec / 1e9;
}

static void wakeups(int ms, int seconds, const char *label) {
	for (int use_poll = 0; use_poll < 2; use_poll++) {
		double wall = seconds_of(CLOCK_MONOTONIC);
		double cpu = seconds_of(CLOCK_PROCESS_CPUTIME_ID);
		long count = 0;
		while (seconds_of(CLOCK_MONOTONIC) - wall < seconds) {
			if (use_poll) {
				poll(NULL, 0, ms);
			} else {
				struct timespec interval = {ms / 1000, (long)(ms % 1000) * 1000000};
				nanosleep(&interval, NULL);
			}
			count++;
		}
		double spent = seconds_of(CLOCK_PROCESS_CPUTIME_ID) - cpu;
		wall = seconds_of(CLOCK_MONOTONIC) - wall;
		printf("PERF-WAKEUPS %s via=%s interval_ms=%d wakeups=%ld per_second=%.1f cpu=%.2f "
		       "us_per_wakeup=%.0f\n", label, use_poll ? "poll" : "nanosleep", ms, count,
		       count / wall, 100.0 * spent / wall, 1e6 * spent / count);
	}
}

/* ── ops: what each kind of system call leaves in the kernel heap ── */

#define MAX_CLASSES 32

struct heap {
	int count;
	long size[MAX_CLASSES];
	long objects[MAX_CLASSES];
	long pages[MAX_CLASSES];
	long large_pages;
};

static int read_heap(struct heap *h) {
	FILE *f = fopen("/proc/slabinfo", "r");
	if (!f)
		return -1;
	char line[256];
	h->count = 0;
	h->large_pages = 0;
	while (fgets(line, sizeof line, f)) {
		long size, objects, pages;
		if (sscanf(line, "size-%*ld %ld %ld %ld", &size, &objects, &pages) == 3 &&
		    h->count < MAX_CLASSES) {
			h->size[h->count] = size;
			h->objects[h->count] = objects;
			h->pages[h->count] = pages;
			h->count++;
		} else if (sscanf(line, "large - - %ld", &pages) == 1) {
			h->large_pages = pages;
		}
	}
	fclose(f);
	return 0;
}

static const char *scratch_dir = "/tmp";

/* Each line of `path` to `out` after `prefix`, or just read when out is NULL. */
static void copy_lines(const char *path, const char *prefix, FILE *out) {
	FILE *f = fopen(path, "r");
	if (!f)
		return;
	char line[512];
	while (fgets(line, sizeof line, f))
		if (out)
			fprintf(out, "%s %s", prefix, line);
	fclose(f);
}

static void op_tmp_file(int i) {
	char path[64];
	snprintf(path, sizeof path, "%s/ops-file-%d", scratch_dir, i);
	int fd = open(path, O_CREAT | O_WRONLY | O_TRUNC, 0644);
	if (fd >= 0) {
		write(fd, "x", 1);
		close(fd);
	}
	unlink(path);
}

static void op_rename(int i) {
	char from[64], to[64];
	snprintf(from, sizeof from, "%s/ops-from-%d", scratch_dir, i);
	snprintf(to, sizeof to, "%s/ops-to-%d", scratch_dir, i);
	int fd = open(from, O_CREAT | O_WRONLY | O_TRUNC, 0644);
	if (fd >= 0)
		close(fd);
	rename(from, to);
	unlink(to);
}

static void op_unlink_open(int i) {
	char path[64];
	snprintf(path, sizeof path, "%s/ops-open-%d", scratch_dir, i);
	int fd = open(path, O_CREAT | O_RDWR | O_TRUNC, 0644);
	if (fd < 0)
		return;
	/* Removed while open: the file lives on until the close. */
	unlink(path);
	write(fd, "x", 1);
	close(fd);
}

static void op_rename_over(int i) {
	char from[64], to[64];
	snprintf(from, sizeof from, "%s/ops-new-%d", scratch_dir, i);
	snprintf(to, sizeof to, "%s/ops-old-%d", scratch_dir, i);
	int fd = open(to, O_CREAT | O_WRONLY | O_TRUNC, 0644);
	if (fd >= 0)
		close(fd);
	fd = open(from, O_CREAT | O_WRONLY | O_TRUNC, 0644);
	if (fd >= 0)
		close(fd);
	/* As mv -f replaces a file. */
	rename(from, to);
	unlink(to);
}

static void op_hardlink(int i) {
	char path[64], other[64];
	snprintf(path, sizeof path, "%s/ops-name-%d", scratch_dir, i);
	snprintf(other, sizeof other, "%s/ops-alias-%d", scratch_dir, i);
	int fd = open(path, O_CREAT | O_WRONLY | O_TRUNC, 0644);
	if (fd >= 0)
		close(fd);
	link(path, other);
	unlink(path);
	unlink(other);
}

static void op_mkdir(int i) {
	char path[64];
	snprintf(path, sizeof path, "%s/ops-dir-%d", scratch_dir, i);
	mkdir(path, 0755);
	rmdir(path);
}

static void op_symlink(int i) {
	char path[64], target[64];
	snprintf(path, sizeof path, "%s/ops-link-%d", scratch_dir, i);
	symlink("/usr/bin/curl", path);
	readlink(path, target, sizeof target);
	unlink(path);
}

static void op_stat(int i) {
	(void)i;
	struct stat st;
	stat("/usr/bin/curl", &st);
	stat("/usr/lib/../bin/./curl", &st);
}

static void op_pipe(int i) {
	(void)i;
	int fds[2];
	char c;
	if (pipe(fds) == 0) {
		write(fds[1], "x", 1);
		read(fds[0], &c, 1);
		close(fds[0]);
		close(fds[1]);
	}
}

static void op_socketpair(int i) {
	(void)i;
	int fds[2];
	char c;
	if (socketpair(AF_UNIX, SOCK_STREAM, 0, fds) == 0) {
		write(fds[0], "x", 1);
		read(fds[1], &c, 1);
		close(fds[0]);
		close(fds[1]);
	}
}

static void op_unix_connect(int i) {
	struct sockaddr_un addr = {.sun_family = AF_UNIX};
	snprintf(addr.sun_path, sizeof addr.sun_path, "%s/ops-sock-%d", scratch_dir, i);
	int listener = socket(AF_UNIX, SOCK_STREAM, 0);
	if (listener < 0)
		return;
	if (bind(listener, (struct sockaddr *)&addr, sizeof addr) == 0 && listen(listener, 1) == 0) {
		int client = socket(AF_UNIX, SOCK_STREAM, 0);
		if (client >= 0) {
			if (connect(client, (struct sockaddr *)&addr, sizeof addr) == 0) {
				int server = accept(listener, NULL, NULL);
				if (server >= 0)
					close(server);
			}
			close(client);
		}
	}
	close(listener);
	unlink(addr.sun_path);
}

static void op_unix_datagram(int i) {
	struct sockaddr_un addr = {.sun_family = AF_UNIX};
	snprintf(addr.sun_path, sizeof addr.sun_path, "%s/ops-dgram-%d", scratch_dir, i);
	int receiver = socket(AF_UNIX, SOCK_DGRAM, 0);
	if (receiver < 0)
		return;
	if (bind(receiver, (struct sockaddr *)&addr, sizeof addr) == 0) {
		int sender = socket(AF_UNIX, SOCK_DGRAM, 0);
		if (sender >= 0) {
			char c;
			/* As syslog(3) sends to /dev/log. */
			if (connect(sender, (struct sockaddr *)&addr, sizeof addr) == 0 &&
			    send(sender, "x", 1, 0) == 1)
				recv(receiver, &c, 1, 0);
			close(sender);
		}
	}
	close(receiver);
	unlink(addr.sun_path);
}

static void op_inet_socket(int i) {
	(void)i;
	int tcp = socket(AF_INET, SOCK_STREAM, 0);
	if (tcp >= 0)
		close(tcp);
	int udp = socket(AF_INET, SOCK_DGRAM, 0);
	if (udp >= 0)
		close(udp);
}

static void op_eventfd(int i) {
	(void)i;
	int fd = eventfd(0, 0);
	if (fd >= 0)
		close(fd);
}

static void op_epoll(int i) {
	(void)i;
	int fds[2];
	int ep = epoll_create1(0);
	if (ep < 0)
		return;
	if (pipe(fds) == 0) {
		struct epoll_event event = {.events = EPOLLIN, .data.fd = fds[0]};
		epoll_ctl(ep, EPOLL_CTL_ADD, fds[0], &event);
		write(fds[1], "x", 1);
		epoll_wait(ep, &event, 1, 0);
		close(fds[0]);
		close(fds[1]);
	}
	close(ep);
}

static void op_timerfd(int i) {
	(void)i;
	int fd = timerfd_create(CLOCK_MONOTONIC, 0);
	if (fd >= 0) {
		struct itimerspec spec = {.it_value = {.tv_nsec = 1000}};
		timerfd_settime(fd, 0, &spec, NULL);
		close(fd);
	}
}

static void op_poll(int i) {
	(void)i;
	int fds[2];
	if (pipe(fds) == 0) {
		struct pollfd p = {.fd = fds[0], .events = POLLIN};
		poll(&p, 1, 0);
		struct timespec zero = {0};
		ppoll(&p, 1, &zero, NULL);
		close(fds[0]);
		close(fds[1]);
	}
}

static void op_proc_read(int i) {
	(void)i;
	static const char *files[] = {"/proc/self/stat", "/proc/self/status", "/proc/meminfo",
	                              "/proc/uptime", "/proc/self/maps", "/proc/stat"};
	char buffer[4096];
	for (unsigned f = 0; f < sizeof files / sizeof files[0]; f++) {
		int fd = open(files[f], O_RDONLY);
		if (fd >= 0) {
			while (read(fd, buffer, sizeof buffer) > 0) {
			}
			close(fd);
		}
	}
}

static void op_proc_list(int i) {
	(void)i;
	DIR *dir = opendir("/proc");
	if (!dir)
		return;
	struct dirent *entry;
	while ((entry = readdir(dir)) != NULL) {
	}
	closedir(dir);
}

static void op_readdir(int i) {
	(void)i;
	DIR *dir = opendir("/usr/bin");
	if (!dir)
		return;
	struct dirent *entry;
	while ((entry = readdir(dir)) != NULL) {
	}
	closedir(dir);
}

static void op_dup(int i) {
	(void)i;
	int fd = open("/dev/null", O_RDWR);
	if (fd >= 0) {
		int copy = dup(fd);
		if (copy >= 0)
			close(copy);
		close(fd);
	}
}

static void op_mmap(int i) {
	(void)i;
	size_t page = (size_t)sysconf(_SC_PAGESIZE);
	char *p = mmap(NULL, 4 * page, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
	if (p == MAP_FAILED)
		return;
	p[0] = 1;
	p[3 * page] = 1;
	/* A split: the middle pages read-only, then the whole range gone. */
	mprotect(p + page, page, PROT_READ);
	munmap(p, 4 * page);
}

static void *thread_body(void *arg) {
	return arg;
}

static void op_thread(int i) {
	(void)i;
	pthread_t thread;
	if (pthread_create(&thread, NULL, thread_body, NULL) == 0)
		pthread_join(thread, NULL);
}

static volatile sig_atomic_t signals_seen;

static void on_signal(int number) {
	(void)number;
	signals_seen++;
}

static void op_signal(int i) {
	(void)i;
	sigset_t set, old;
	sigemptyset(&set);
	sigaddset(&set, SIGUSR2);
	sigprocmask(SIG_BLOCK, &set, &old);
	sigprocmask(SIG_SETMASK, &old, NULL);
	raise(SIGUSR1);
}

static char *fault_page;
static size_t fault_page_size;

static void on_fault(int number) {
	(void)number;
	mprotect(fault_page, fault_page_size, PROT_READ | PROT_WRITE);
}

/* A write to a read-only page that the handler then lets through: SIGSEGV as
 * a translator or a collector with a write barrier uses it, as a matter of
 * course rather than on the way to a crash. */
static void op_fault(int i) {
	(void)i;
	if (fault_page == NULL) {
		fault_page_size = (size_t)sysconf(_SC_PAGESIZE);
		char *page = mmap(NULL, fault_page_size, PROT_READ | PROT_WRITE,
		                  MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
		if (page == MAP_FAILED)
			return;
		fault_page = page;
		struct sigaction action = {.sa_handler = on_fault};
		sigaction(SIGSEGV, &action, NULL);
	}
	fault_page[0] = 1;
	mprotect(fault_page, fault_page_size, PROT_READ);
	*(volatile char *)fault_page = 2;
}

static void op_fork(int i) {
	(void)i;
	pid_t pid = fork();
	if (pid == 0)
		_exit(0);
	if (pid > 0)
		waitpid(pid, NULL, 0);
}

static void op_memfd(int i) {
	(void)i;
	int fd = (int)syscall(SYS_memfd_create, "ops", 0);
	if (fd >= 0)
		close(fd);
}

struct op {
	const char *name;
	void (*run)(int);
};

static void measure_op(const struct op *op, int count, const char *label) {
	/* Warm the same cohort size. Deferred inode release makes a burst use
	 * distinct disk blocks; a smaller warmup leaves their page cache cold. */
	for (int i = 0; i < count; i++)
		op->run(i);
	sleep(13);
	struct heap before, after;
	if (read_heap(&before) < 0) {
		printf("PERF-ERROR %s cannot read /proc/slabinfo\n", label);
		return;
	}
	/* A kernel built with ALLOC_TRACK=1 can also say where from. */
	int tracked = access("/proc/allocstart", R_OK) == 0;
	if (tracked)
		copy_lines("/proc/allocstart", NULL, NULL);
	for (int i = 0; i < count; i++)
		op->run(i);
	/* A namespace release can retire its closed UNIX endpoint for a second
	 * grace. Let both five-second periods and worker scans finish. */
	sleep(13);
	read_heap(&after);
	if (tracked) {
		char prefix[640];
		snprintf(prefix, sizeof prefix, "PERF-SITE %s op=%s dir=%s", label, op->name,
		         scratch_dir);
		copy_lines("/proc/allocsites", prefix, stdout);
	}
	long bytes = (after.large_pages - before.large_pages) * sysconf(_SC_PAGESIZE);
	char classes[512] = "";
	for (int c = 0; c < after.count && c < before.count; c++) {
		long delta = after.objects[c] - before.objects[c];
		if (delta == 0)
			continue;
		bytes += delta * after.size[c];
		char part[48];
		snprintf(part, sizeof part, " size-%ld:%+ld", after.size[c], delta);
		strncat(classes, part, sizeof classes - strlen(classes) - 1);
	}
	if (after.large_pages != before.large_pages) {
		char part[48];
		snprintf(part, sizeof part, " large_pages:%+ld", after.large_pages - before.large_pages);
		strncat(classes, part, sizeof classes - strlen(classes) - 1);
	}
	printf("PERF-OPS %s op=%s dir=%s count=%d bytes_per_op=%ld%s\n", label, op->name,
	       scratch_dir, count, bytes / count, classes);
}

static int run_program(char *const argv[]) {
	pid_t child = fork();
	if (child == 0) {
		int null = open("/dev/null", O_WRONLY);
		if (null >= 0) { dup2(null, STDOUT_FILENO); dup2(null, STDERR_FILENO); close(null); }
		execv(argv[0], argv); _exit(127);
	}
	if (child < 0) {
		printf("PERF-ERROR program=\"%s\" fork errno=%d\n", argv[0], errno); return 0;
	}
	int status = 0; pid_t waited;
	do { waited = waitpid(child, &status, 0); } while (waited < 0 && errno == EINTR);
	if (waited == child && WIFEXITED(status) && WEXITSTATUS(status) == 0) return 1;
	printf("PERF-ERROR program=\"%s\" wait=%d status=%d errno=%d\n", argv[0], (int)waited, status, errno);
	return 0;
}

/* Keep the observer process alive across both snapshots. Shell cat/awk/sleep
 * helpers otherwise leave fresh process corpses and diagnostic descriptors
 * only in the after snapshot, disguising those as program retention. */
static int churn(int count, const char *label) {
	/* take() clears its 48 KiB output buffer after capturing the memory
	 * header. Warm the slab parser's buffers and stack storage as well. */
	struct heap before, after;
	if (take(&last) < 0 || read_heap(&before) < 0 || read_heap(&after) < 0) return 1;
	char *programs[][4] = {{"/bin/true", NULL}, {"/bin/sleep", "0", NULL},
		{"/usr/bin/curl", "--version", NULL}, {"/bin/busybox", "awk", "BEGIN{}", NULL}};
	const char *names[] = {"/bin/true", "/bin/sleep 0", "/usr/bin/curl --version", "/bin/busybox awk BEGIN{}"};
	for (unsigned p = 0; p < sizeof programs / sizeof programs[0]; ++p) {
		copy_lines("/proc/allocstart", NULL, NULL);
		/* Match the measured quarantine/slab peak before the first snapshot. */
		for (int i = 0; i < count; ++i) if (!run_program(programs[p])) return 1;
		sync(); sleep(7);
		/* Collect the memory header after the diagnostic reads have touched
		 * their output pages, including writes to fork/COW observer pages. */
		if (take(&last) < 0 || read_heap(&before) < 0 || take(&last) < 0) return 1;
		uint64_t used = last.header.total_memory - last.header.free_memory;
		copy_lines("/proc/allocstart", NULL, NULL);
		for (int i = 0; i < count; ++i) if (!run_program(programs[p])) return 1;
		sync(); sleep(7);
		if (take(&last) < 0 || read_heap(&after) < 0 || take(&last) < 0) return 1;
		int64_t delta = (int64_t)(last.header.total_memory - last.header.free_memory) - (int64_t)used;
		printf("PERF-CHURN %s program=\"%s\" runs=%d retained_kb=%lld per_run_bytes=%lld\n",
			label, names[p], count, (long long)(delta / 1024), (long long)(delta / count));
		for (int c = 0; c < after.count && c < before.count; ++c) {
			long objects = after.objects[c] - before.objects[c];
			long pages = after.pages[c] - before.pages[c];
			if (objects || pages) printf("PERF-SLAB %s program=\"%s\" class=size-%ld objects=%+ld pages=%+ld\n",
				label, names[p], after.size[c], objects, pages);
		}
		if (after.large_pages != before.large_pages)
			printf("PERF-SLAB %s program=\"%s\" class=large pages=%+ld\n", label, names[p], after.large_pages - before.large_pages);
		char prefix[640]; snprintf(prefix, sizeof prefix, "PERF-SITE %s program=\"%s\"", label, names[p]);
		copy_lines("/proc/allocsites", prefix, stdout);
	}
	return 0;
}

static void ops(int count, const char *label) {
	copy_lines("/proc/allocstart", NULL, NULL);
	static const struct op table[] = {
		{"stat", op_stat},               {"pipe", op_pipe},
		{"socketpair", op_socketpair},   {"inet_socket", op_inet_socket},
		{"eventfd", op_eventfd},         {"epoll", op_epoll},
		{"timerfd", op_timerfd},         {"poll", op_poll},
		{"proc_read", op_proc_read},     {"proc_list", op_proc_list},
		{"readdir", op_readdir},         {"dup", op_dup},
		{"mmap", op_mmap},               {"thread", op_thread},
		{"signal", op_signal},           {"fault", op_fault},
		{"fork", op_fork},               {"memfd", op_memfd},
	};
	/* The ones that make and remove names, on the RAM root and on ext2. */
	static const struct op files[] = {
		{"file", op_tmp_file},          {"rename", op_rename},
		{"unlink_open", op_unlink_open}, {"rename_over", op_rename_over},
		{"hardlink", op_hardlink},       {"mkdir", op_mkdir},
		{"symlink", op_symlink},         {"unix_connect", op_unix_connect},
		{"unix_datagram", op_unix_datagram},
	};
	struct sigaction action = {.sa_handler = on_signal};
	sigaction(SIGUSR1, &action, NULL);
	for (unsigned t = 0; t < sizeof table / sizeof table[0]; t++)
		measure_op(&table[t], count, label);
	static const char *dirs[] = {"/tmp", "/root"};
	for (unsigned d = 0; d < sizeof dirs / sizeof dirs[0]; d++) {
		scratch_dir = dirs[d];
		for (unsigned t = 0; t < sizeof files / sizeof files[0]; t++)
			measure_op(&files[t], count, label);
	}
}

int main(int argc, char **argv) {
	setvbuf(stdout, NULL, _IOLBF, 0);
	if (argc >= 5 && strcmp(argv[1], "wakeups") == 0) {
		char label[512] = "";
		for (int i = 4; i < argc; i++) {
			if (i > 4)
				strncat(label, " ", sizeof label - strlen(label) - 1);
			strncat(label, argv[i], sizeof label - strlen(label) - 1);
		}
		wakeups(atoi(argv[2]), atoi(argv[3]), label);
		return 0;
	}
	if (argc >= 4 && (strcmp(argv[1], "ops") == 0 || strcmp(argv[1], "churn") == 0)) {
		char label[512] = "";
		for (int i = 3; i < argc; i++) {
			if (i > 3)
				strncat(label, " ", sizeof label - strlen(label) - 1);
			strncat(label, argv[i], sizeof label - strlen(label) - 1);
		}
		int count = atoi(argv[2]);
		if (count <= 0) return 1;
		if (strcmp(argv[1], "churn") == 0) return churn(count, label);
		ops(count, label);
		return 0;
	}
	if (argc == 2 && strcmp(argv[1], "used") == 0) {
		if (take(&last) < 0)
			return 1;
		printf("%llu\n", (unsigned long long)(last.header.total_memory - last.header.free_memory));
		return 0;
	}
	if (argc >= 6 && strcmp(argv[1], "sample") == 0) {
		char label[512] = "";
		for (int i = 5; i < argc; i++) {
			if (i > 5)
				strncat(label, " ", sizeof label - strlen(label) - 1);
			strncat(label, argv[i], sizeof label - strlen(label) - 1);
		}
		return sample(atoi(argv[2]), atoi(argv[3]), strtoull(argv[4], NULL, 10), label);
	}
	if (argc == 3 && strcmp(argv[1], "tree") == 0) {
		static int pids[MAX_RECORDS];
		if (take(&last) < 0)
			return 1;
		int n = tree(&last, atoi(argv[2]), pids);
		for (int i = n - 1; i > 0; i--)
			printf("%d%s", pids[i], i > 1 ? " " : "");
		printf("\n");
		return 0;
	}
	fprintf(stderr, "usage: measure used | measure sample PID SECONDS USED LABEL... | measure tree PID\n");
	return 2;
}

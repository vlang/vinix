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
 */
#include <fcntl.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
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

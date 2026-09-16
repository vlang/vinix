// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Guest side of the AArch64 real-time scheduling regression. Runs as PID 1 and
// checks that the scheduling policies are real: that the syscalls carry them,
// that a thread holding one is picked ahead of a thread that does not, that a
// runaway one cannot take the machine away from everything else, and that a
// thread which asked to be woken on time is.
//
// Almost every check below shares one rig: two spinner threads pinned to the
// same CPU, each counting laps of a loop for a fixed wall-clock interval. Who
// ran is read off the two counts. A single CPU between them is what makes the
// answer mean anything -- on four CPUs both threads simply run.
//
// The runner boots with -smp 4, so CPU 3 is free for the spinners while the
// main thread and everything else stay on the others.

#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <sched.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#ifndef SCHED_BATCH
#define SCHED_BATCH 3
#endif
#ifndef SCHED_IDLE
#define SCHED_IDLE 5
#endif
#ifndef SCHED_DEADLINE
#define SCHED_DEADLINE 6
#endif
#ifndef SCHED_RESET_ON_FORK
#define SCHED_RESET_ON_FORK 0x40000000
#endif

#ifndef SYS_sched_setattr
#define SYS_sched_setattr 274
#endif
#ifndef SYS_sched_getattr
#define SYS_sched_getattr 275
#endif

// The CPU every spinner is pinned to, so that the two of them have to share it.
#define SPIN_CPU 3

// struct sched_attr, as sched_setattr(2) and sched_getattr(2) carry it.
struct sched_attr_t {
	uint32_t size;
	uint32_t sched_policy;
	uint64_t sched_flags;
	int32_t sched_nice;
	uint32_t sched_priority;
	uint64_t sched_runtime;
	uint64_t sched_deadline;
	uint64_t sched_period;
};

static int failures;

static void fail(const char *fmt, ...) {
	va_list args;
	va_start(args, fmt);
	fputs("QEMU RT FAIL: ", stdout);
	vprintf(fmt, args);
	va_end(args);
	fputc('\n', stdout);
	fflush(stdout);
	failures++;
}

static void pass(const char *what) {
	printf("QEMU RT PASS: %s\n", what);
	fflush(stdout);
}

static void note(const char *fmt, ...) {
	va_list args;
	va_start(args, fmt);
	fputs("QEMU RT: ", stdout);
	vprintf(fmt, args);
	va_end(args);
	fputc('\n', stdout);
	fflush(stdout);
}

static pid_t thread_id(void) {
	return (pid_t)syscall(SYS_gettid);
}

static int set_policy(pid_t tid, int policy, int priority) {
	struct sched_param param = {.sched_priority = priority};
	return (int)syscall(SYS_sched_setscheduler, tid, policy, &param);
}

static int get_policy(pid_t tid) {
	return (int)syscall(SYS_sched_getscheduler, tid);
}

static int get_priority(pid_t tid) {
	struct sched_param param = {.sched_priority = -1};
	if (syscall(SYS_sched_getparam, tid, &param) != 0) {
		return -1;
	}
	return param.sched_priority;
}

static uint64_t monotonic_ns(void) {
	struct timespec now;
	clock_gettime(CLOCK_MONOTONIC, &now);
	return (uint64_t)now.tv_sec * 1000000000u + (uint64_t)now.tv_nsec;
}

static void pin_to(int cpu) {
	cpu_set_t set;
	CPU_ZERO(&set);
	CPU_SET(cpu, &set);
	if (sched_setaffinity(0, sizeof(set), &set) != 0) {
		fail("sched_setaffinity(cpu %d): %s", cpu, strerror(errno));
	}
}

// ── the shared spinner rig ──────────────────────────────────────────────────

struct spinner {
	// What the thread should become once it is on its CPU.
	int policy;
	int priority;
	uint64_t dl_runtime_ns;
	uint64_t dl_period_ns;
	// Laps counted, which is the measurement.
	volatile uint64_t laps;
	volatile int ready;
	volatile int stop;
	int setup_error;
	// What the thread saw of itself while it was running, so that a surprising
	// result can be told apart from a thread that never got where it was sent.
	volatile int observed_cpu;
	volatile int observed_policy;
	volatile unsigned long observed_mask;
};

static void *spin(void *argument) {
	struct spinner *self = argument;

	pin_to(SPIN_CPU);

	if (self->policy == SCHED_DEADLINE) {
		struct sched_attr_t attr = {
			.size = sizeof(attr),
			.sched_policy = SCHED_DEADLINE,
			.sched_runtime = self->dl_runtime_ns,
			.sched_deadline = self->dl_period_ns,
			.sched_period = self->dl_period_ns,
		};
		if (syscall(SYS_sched_setattr, 0, &attr, 0u) != 0) {
			self->setup_error = errno;
		}
	} else if (self->policy != SCHED_OTHER) {
		if (set_policy(thread_id(), self->policy, self->priority) != 0) {
			self->setup_error = errno;
		}
	}

	unsigned long mask = 0;
	syscall(SYS_sched_getaffinity, 0, sizeof(mask), &mask);
	self->observed_mask = mask;
	self->observed_cpu = sched_getcpu();
	self->observed_policy = get_policy(0);

	self->ready = 1;
	while (!self->stop) {
		self->laps++;
		if ((self->laps & 0xfffff) == 0) {
			self->observed_cpu = sched_getcpu();
			self->observed_policy = get_policy(0);
		}
	}
	return NULL;
}

// Run two spinners against each other on one CPU for `ms` milliseconds and
// report what each of them got through.
static int race(struct spinner *first, struct spinner *second, int ms) {
	pthread_t first_thread, second_thread;

	first->laps = second->laps = 0;
	first->ready = second->ready = 0;
	first->stop = second->stop = 0;
	first->setup_error = second->setup_error = 0;

	if (pthread_create(&first_thread, NULL, spin, first) != 0
			|| pthread_create(&second_thread, NULL, spin, second) != 0) {
		fail("pthread_create: %s", strerror(errno));
		return -1;
	}

	// Both threads have to be on the CPU and carrying their policies before the
	// clock starts, or the first one up is credited with the other's share.
	uint64_t deadline = monotonic_ns() + 2000000000u;
	while ((!first->ready || !second->ready) && monotonic_ns() < deadline) {
		usleep(1000);
	}

	usleep((useconds_t)ms * 1000);
	first->stop = second->stop = 1;
	pthread_join(first_thread, NULL);
	pthread_join(second_thread, NULL);

	if (first->setup_error != 0 || second->setup_error != 0) {
		fail("spinner setup failed: %s / %s", strerror(first->setup_error),
				strerror(second->setup_error));
		return -1;
	}
	return 0;
}

// ── what the syscalls say ───────────────────────────────────────────────────

static void check_policy_interface(void) {
	int before = failures;
	pid_t self = thread_id();

	if (sched_get_priority_min(SCHED_FIFO) != 1
			|| sched_get_priority_max(SCHED_FIFO) != 99) {
		fail("SCHED_FIFO priority range is %d..%d, wanted 1..99",
				sched_get_priority_min(SCHED_FIFO), sched_get_priority_max(SCHED_FIFO));
	}
	if (sched_get_priority_min(SCHED_RR) != 1 || sched_get_priority_max(SCHED_RR) != 99) {
		fail("SCHED_RR priority range is %d..%d, wanted 1..99",
				sched_get_priority_min(SCHED_RR), sched_get_priority_max(SCHED_RR));
	}
	if (sched_get_priority_min(SCHED_OTHER) != 0
			|| sched_get_priority_max(SCHED_OTHER) != 0) {
		fail("SCHED_OTHER has a priority range");
	}
	if (sched_get_priority_max(0x7fff) != -1 || errno != EINVAL) {
		fail("an unknown policy was given a priority range");
	}

	if (get_policy(self) != SCHED_OTHER) {
		fail("a fresh thread starts as policy %d, not SCHED_OTHER", get_policy(self));
	}

	// A real-time priority that does not exist is refused, and refusing it does
	// not change anything.
	if (set_policy(self, SCHED_FIFO, 0) == 0 || errno != EINVAL) {
		fail("SCHED_FIFO accepted priority 0");
	}
	if (set_policy(self, SCHED_FIFO, 100) == 0 || errno != EINVAL) {
		fail("SCHED_FIFO accepted priority 100");
	}
	if (set_policy(self, SCHED_OTHER, 1) == 0 || errno != EINVAL) {
		fail("SCHED_OTHER accepted a non-zero priority");
	}
	if (get_policy(self) != SCHED_OTHER) {
		fail("a refused request changed the policy anyway");
	}

	if (set_policy(self, SCHED_RR, 42) != 0) {
		fail("sched_setscheduler(SCHED_RR, 42): %s", strerror(errno));
	}
	if (get_policy(self) != SCHED_RR || get_priority(self) != 42) {
		fail("after SCHED_RR 42 the thread reports policy %d priority %d",
				get_policy(self), get_priority(self));
	}

	// Only SCHED_RR has a quantum to report.
	struct timespec interval = {.tv_sec = -1, .tv_nsec = -1};
	if (sched_rr_get_interval(0, &interval) != 0) {
		fail("sched_rr_get_interval: %s", strerror(errno));
	} else if (interval.tv_sec != 0 || interval.tv_nsec <= 0) {
		fail("SCHED_RR reports a %ld.%09ld second quantum", (long)interval.tv_sec,
				(long)interval.tv_nsec);
	} else {
		note("SCHED_RR quantum is %ld us", (long)interval.tv_nsec / 1000);
	}

	// sched_setparam moves the priority and leaves the policy alone.
	struct sched_param param = {.sched_priority = 7};
	if (syscall(SYS_sched_setparam, 0, &param) != 0) {
		fail("sched_setparam(7): %s", strerror(errno));
	}
	if (get_policy(self) != SCHED_RR || get_priority(self) != 7) {
		fail("sched_setparam changed the policy or missed the priority");
	}

	if (set_policy(self, SCHED_OTHER, 0) != 0) {
		fail("could not go back to SCHED_OTHER: %s", strerror(errno));
	}
	if (sched_rr_get_interval(0, &interval) != 0 || interval.tv_nsec != 0) {
		fail("SCHED_OTHER reports a round-robin quantum");
	}
	if (get_policy(self) != SCHED_OTHER || get_priority(self) != 0) {
		fail("SCHED_OTHER left priority %d behind", get_priority(self));
	}

	// A thread that is not there is ESRCH, not a policy. An id no thread could
	// hold is EINVAL, which is a different answer and one callers act on.
	if (get_policy(0x7ffe) != -1 || errno != ESRCH) {
		fail("sched_getscheduler answered for a thread that does not exist");
	}
	if (get_policy(-1) != -1 || errno != EINVAL) {
		fail("sched_getscheduler(-1) reported %s, wanted EINVAL", strerror(errno));
	}

	if (failures == before) {
		pass("policies and priorities are carried by the syscalls");
	}
}

static void check_reset_on_fork(void) {
	int before = failures;
	pid_t self = thread_id();

	if (set_policy(self, SCHED_FIFO | SCHED_RESET_ON_FORK, 30) != 0) {
		fail("SCHED_RESET_ON_FORK was refused: %s", strerror(errno));
		return;
	}
	if (get_policy(self) != (SCHED_FIFO | SCHED_RESET_ON_FORK)) {
		fail("SCHED_RESET_ON_FORK is not reported back, policy is %d", get_policy(self));
	}

	pid_t child = fork();
	if (child == 0) {
		int policy = get_policy(0);
		int priority = get_priority(0);
		_exit(policy == SCHED_OTHER && priority == 0 ? 0 : 1);
	}
	if (child < 0) {
		fail("fork: %s", strerror(errno));
	} else {
		int status = 0;
		waitpid(child, &status, 0);
		if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) {
			fail("a SCHED_RESET_ON_FORK child kept its parent's real-time policy");
		}
	}

	set_policy(self, SCHED_OTHER, 0);

	if (failures == before) {
		pass("SCHED_RESET_ON_FORK hands children an ordinary policy");
	}
}

// ── what the scheduler does with them ───────────────────────────────────────

static void check_realtime_wins_the_cpu(void) {
	int before = failures;
	struct spinner realtime = {.policy = SCHED_FIFO, .priority = 10};
	struct spinner ordinary = {.policy = SCHED_OTHER};

	if (race(&realtime, &ordinary, 1000) != 0) {
		return;
	}
	note("one CPU, SCHED_FIFO 10 vs SCHED_OTHER: %llu vs %llu laps",
			(unsigned long long)realtime.laps, (unsigned long long)ordinary.laps);
	// Where each of them actually was. A surprising split is nearly always one
	// of the two not being where it was sent, or not carrying what it was
	// given, and neither is visible from the lap counts alone.
	note("  real-time: cpu %d mask 0x%lx policy %d; ordinary: cpu %d mask 0x%lx policy %d",
			realtime.observed_cpu, realtime.observed_mask, realtime.observed_policy,
			ordinary.observed_cpu, ordinary.observed_mask, ordinary.observed_policy);

	if (ordinary.laps == 0) {
		fail("the ordinary thread never ran at all");
	} else if (realtime.laps < ordinary.laps * 4) {
		fail("SCHED_FIFO took %llu laps against SCHED_OTHER's %llu, which is not priority",
				(unsigned long long)realtime.laps, (unsigned long long)ordinary.laps);
	}

	if (failures == before) {
		pass("a real-time thread is picked ahead of an ordinary one");
	}
}

static void check_priority_orders_the_band(void) {
	int before = failures;
	struct spinner high = {.policy = SCHED_FIFO, .priority = 60};
	struct spinner low = {.policy = SCHED_FIFO, .priority = 20};

	if (race(&high, &low, 1000) != 0) {
		return;
	}
	note("one CPU, SCHED_FIFO 60 vs SCHED_FIFO 20: %llu vs %llu laps",
			(unsigned long long)high.laps, (unsigned long long)low.laps);

	if (high.laps < low.laps * 4) {
		fail("priority 60 took %llu laps against priority 20's %llu",
				(unsigned long long)high.laps, (unsigned long long)low.laps);
	}

	if (failures == before) {
		pass("priority orders the real-time band");
	}
}

static void check_idle_policy_yields(void) {
	int before = failures;
	struct spinner ordinary = {.policy = SCHED_OTHER};
	struct spinner idle = {.policy = SCHED_IDLE};

	if (race(&ordinary, &idle, 1000) != 0) {
		return;
	}
	note("one CPU, SCHED_OTHER vs SCHED_IDLE: %llu vs %llu laps",
			(unsigned long long)ordinary.laps, (unsigned long long)idle.laps);

	if (ordinary.laps < idle.laps * 4) {
		fail("SCHED_IDLE took %llu laps against SCHED_OTHER's %llu",
				(unsigned long long)idle.laps, (unsigned long long)ordinary.laps);
	}

	if (failures == before) {
		pass("SCHED_IDLE runs behind ordinary threads");
	}
}

// A runaway real-time thread is the failure mode that makes real-time support
// dangerous on a machine with no way to interrupt it. The bandwidth cap is what
// keeps the rest of the machine alive, and this is the check that it is there:
// the ordinary thread sharing that CPU has to get *some* of it.
static void check_runaway_is_throttled(void) {
	int before = failures;
	struct spinner runaway = {.policy = SCHED_FIFO, .priority = 99};
	struct spinner ordinary = {.policy = SCHED_OTHER};

	if (race(&runaway, &ordinary, 3000) != 0) {
		return;
	}
	note("one CPU, SCHED_FIFO 99 for three seconds: %llu vs %llu laps",
			(unsigned long long)runaway.laps, (unsigned long long)ordinary.laps);

	if (ordinary.laps == 0) {
		fail("a SCHED_FIFO 99 loop starved its CPU completely");
	}

	if (failures == before) {
		pass("a runaway real-time thread is held to its bandwidth");
	}
}

static void check_deadline_is_a_budget(void) {
	int before = failures;

	// Two milliseconds in every ten. The ordinary thread sharing the CPU should
	// come out ahead, which no priority-based policy would allow.
	struct spinner deadline = {
		.policy = SCHED_DEADLINE,
		.dl_runtime_ns = 2000000,
		.dl_period_ns = 10000000,
	};
	struct spinner ordinary = {.policy = SCHED_OTHER};

	if (race(&deadline, &ordinary, 2000) != 0) {
		return;
	}
	note("one CPU, SCHED_DEADLINE 2ms/10ms vs SCHED_OTHER: %llu vs %llu laps",
			(unsigned long long)deadline.laps, (unsigned long long)ordinary.laps);

	if (deadline.laps == 0) {
		fail("the deadline thread never ran");
	} else if (deadline.laps > ordinary.laps) {
		fail("a 20%% deadline thread took %llu laps against the ordinary thread's %llu",
				(unsigned long long)deadline.laps, (unsigned long long)ordinary.laps);
	}

	if (failures == before) {
		pass("SCHED_DEADLINE keeps a thread inside its budget");
	}
}

static void check_deadline_admission(void) {
	int before = failures;

	struct sched_attr_t attr = {
		.size = sizeof(attr),
		.sched_policy = SCHED_DEADLINE,
		.sched_runtime = 2000000,
		.sched_deadline = 1000000,
		.sched_period = 10000000,
	};
	// A runtime that does not fit inside its own deadline is not a deadline.
	if (syscall(SYS_sched_setattr, 0, &attr, 0u) == 0 || errno != EINVAL) {
		fail("sched_setattr accepted a runtime longer than its deadline");
	}

	// More of a CPU than there is.
	attr.sched_runtime = 990000000;
	attr.sched_deadline = 1000000000;
	attr.sched_period = 1000000000;
	if (syscall(SYS_sched_setattr, 0, &attr, 0u) == 0 || errno != EBUSY) {
		fail("sched_setattr admitted 99%% of a CPU, errno %d", errno);
	}

	// One that does fit is admitted, reported back, and can be given up again.
	attr.sched_runtime = 1000000;
	attr.sched_deadline = 10000000;
	attr.sched_period = 10000000;
	if (syscall(SYS_sched_setattr, 0, &attr, 0u) != 0) {
		fail("sched_setattr refused 10%% of a CPU: %s", strerror(errno));
	} else {
		struct sched_attr_t read_back = {0};
		if (syscall(SYS_sched_getattr, 0, &read_back, (unsigned)sizeof(read_back), 0u)
				!= 0) {
			fail("sched_getattr: %s", strerror(errno));
		} else if (read_back.sched_policy != SCHED_DEADLINE
				|| read_back.sched_runtime != 1000000
				|| read_back.sched_period != 10000000) {
			fail("sched_getattr reported policy %u runtime %llu period %llu",
					read_back.sched_policy, (unsigned long long)read_back.sched_runtime,
					(unsigned long long)read_back.sched_period);
		}
		if (set_policy(thread_id(), SCHED_OTHER, 0) != 0) {
			fail("a deadline thread could not go back to SCHED_OTHER: %s",
					strerror(errno));
		}
	}

	if (failures == before) {
		pass("SCHED_DEADLINE admits only what the machine can keep");
	}
}

// ── how long a real-time thread waits ───────────────────────────────────────

struct load {
	volatile int stop;
};

static void *load_thread(void *argument) {
	struct load *self = argument;
	volatile uint64_t sink = 0;
	while (!self->stop) {
		sink++;
	}
	(void)sink;
	return NULL;
}

// cyclictest, in miniature: sleep to an absolute time over and over and measure
// how late the thread is when it gets the CPU back. This is the number the
// "bounded worst-case latency" question is really asking about, and running it
// against a busy machine is what makes the answer worth having.
static void check_wakeup_latency(void) {
	int before = failures;
	const int cycles = 500;
	const uint64_t interval_ns = 1000000;

	// One ordinary spinner per CPU, so that every wake-up has to take a CPU off
	// something rather than find one already idle.
	long cpus = sysconf(_SC_NPROCESSORS_ONLN);
	if (cpus < 1) {
		cpus = 1;
	}
	struct load load = {0};
	pthread_t loaders[8];
	int loader_count = cpus > 8 ? 8 : (int)cpus;
	for (int i = 0; i < loader_count; i++) {
		if (pthread_create(&loaders[i], NULL, load_thread, &load) != 0) {
			loader_count = i;
			break;
		}
	}

	if (set_policy(thread_id(), SCHED_FIFO, 80) != 0) {
		fail("could not become SCHED_FIFO 80: %s", strerror(errno));
		load.stop = 1;
		for (int i = 0; i < loader_count; i++) {
			pthread_join(loaders[i], NULL);
		}
		return;
	}

	uint64_t worst = 0;
	uint64_t total = 0;
	uint64_t best = UINT64_MAX;
	struct timespec when;
	clock_gettime(CLOCK_MONOTONIC, &when);

	for (int i = 0; i < cycles; i++) {
		uint64_t target = (uint64_t)when.tv_sec * 1000000000u + (uint64_t)when.tv_nsec
				+ interval_ns;
		when.tv_sec = (time_t)(target / 1000000000u);
		when.tv_nsec = (long)(target % 1000000000u);

		if (clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME, &when, NULL) != 0) {
			fail("clock_nanosleep: %s", strerror(errno));
			break;
		}

		uint64_t woke = monotonic_ns();
		uint64_t late = woke > target ? woke - target : 0;
		total += late;
		if (late > worst) {
			worst = late;
		}
		if (late < best) {
			best = late;
		}
	}

	set_policy(thread_id(), SCHED_OTHER, 0);
	load.stop = 1;
	for (int i = 0; i < loader_count; i++) {
		pthread_join(loaders[i], NULL);
	}

	uint64_t average = total / (uint64_t)cycles;
	note("wake-up latency over %d cycles against %d busy threads: min %llu us, "
			"avg %llu us, max %llu us",
			cycles, loader_count, (unsigned long long)(best / 1000),
			(unsigned long long)(average / 1000), (unsigned long long)(worst / 1000));

	// The numbers themselves are the point of this check; the thresholds only
	// have to catch a real-time thread that is queueing behind the ordinary
	// ones. The average is asserted rather than the worst case because the
	// worst case belongs mostly to whatever is underneath this machine -- a
	// hypervisor on a loaded laptop moves it by milliseconds between runs, and
	// a threshold tight enough to be interesting there would fail on a Tuesday.
	if (average > 5000000u) {
		fail("a SCHED_FIFO 80 thread woke %llu ms late on average",
				(unsigned long long)(average / 1000000));
	}
	if (worst > 100000000u) {
		fail("a SCHED_FIFO 80 thread woke %llu ms late at worst",
				(unsigned long long)(worst / 1000000));
	}

	if (failures == before) {
		pass("a real-time thread wakes on time on a busy machine");
	}
}

static void check_proc_reports_the_policy(void) {
	int before = failures;

	if (set_policy(thread_id(), SCHED_FIFO, 55) != 0) {
		fail("sched_setscheduler(SCHED_FIFO, 55): %s", strerror(errno));
		return;
	}

	char buffer[512];
	int fd = open("/proc/self/stat", O_RDONLY);
	if (fd < 0) {
		fail("open /proc/self/stat: %s", strerror(errno));
		set_policy(thread_id(), SCHED_OTHER, 0);
		return;
	}
	ssize_t got = read(fd, buffer, sizeof(buffer) - 1);
	close(fd);
	if (got <= 0) {
		fail("read /proc/self/stat: %s", strerror(errno));
		set_policy(thread_id(), SCHED_OTHER, 0);
		return;
	}
	buffer[got] = '\0';

	// Fields 40 and 41 are rt_priority and policy. Walk past the command name
	// first, since it is the one field that can contain spaces.
	char *cursor = strrchr(buffer, ')');
	int rt_priority = -1;
	int policy = -1;
	if (cursor != NULL) {
		int field = 2;
		for (char *token = strtok(cursor + 1, " \n"); token != NULL;
				token = strtok(NULL, " \n")) {
			field++;
			if (field == 40) {
				rt_priority = atoi(token);
			} else if (field == 41) {
				policy = atoi(token);
			}
		}
	}
	if (policy != SCHED_FIFO || rt_priority != 55) {
		fail("/proc/self/stat reports policy %d rt_priority %d", policy, rt_priority);
	}

	set_policy(thread_id(), SCHED_OTHER, 0);

	if (failures == before) {
		pass("/proc reports the policy a thread is running under");
	}
}

int main(void) {
	printf("QEMU RT: start\n");
	fflush(stdout);

	check_policy_interface();
	check_reset_on_fork();
	check_proc_reports_the_policy();
	check_realtime_wins_the_cpu();
	check_priority_orders_the_band();
	check_idle_policy_yields();
	check_deadline_admission();
	check_deadline_is_a_budget();
	check_runaway_is_throttled();
	check_wakeup_latency();

	if (failures == 0) {
		printf("VINIX QEMU RT: PASS\n");
	} else {
		printf("VINIX QEMU RT: FAIL (%d)\n", failures);
	}
	fflush(stdout);

	// PID 1 must not return; the runner stops the machine once it has read the
	// verdict above.
	for (;;) {
		pause();
	}
	return 0;
}

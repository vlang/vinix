// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The guest half of tests/cpu-power: run as /sbin/init, it loads the CPUs in
// the ways that would show a lost wake-up, reads the idle and frequency files
// back out of /sys, and powers the machine off. Every line it prints starts
// with CPUTEST; a line with FAIL in it is a failure, and the run is only good
// if it ends with "CPUTEST DONE failures=0". See README.md.
#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/reboot.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#ifndef CONSOLE
#define CONSOLE "/dev/console"
#endif

#define MAX_CPUS 64
#define MAX_STATES 10
#define CPU_DIR "/sys/devices/system/cpu"

static int out = 1;
static int failures;

static void sayf(const char *fmt, ...) {
    char b[1024];
    va_list ap;
    va_start(ap, fmt);
    int n = vsnprintf(b, sizeof b, fmt, ap);
    va_end(ap);
    if (n > (int)sizeof b) n = sizeof b;
    if (n > 0) write(out, b, n);
}

static void fail(const char *fmt, ...) {
    char b[512];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(b, sizeof b, fmt, ap);
    va_end(ap);
    failures++;
    sayf("CPUTEST FAIL %s\n", b);
}

static int readfile(const char *p, char *buf, int cap) {
    int fd = open(p, O_RDONLY);
    if (fd < 0) return -errno;
    int n = read(fd, buf, cap - 1);
    int e = errno;
    close(fd);
    if (n < 0) return -e;
    buf[n] = 0;
    while (n > 0 && (buf[n - 1] == '\n' || buf[n - 1] == ' ')) buf[--n] = 0;
    return n;
}

// The bytes written, or -errno: of the open, or of the write.
static int writefile(const char *p, const char *text) {
    int fd = open(p, O_WRONLY);
    if (fd < 0) return -errno;
    int n = write(fd, text, strlen(text));
    int e = errno;
    close(fd);
    return n < 0 ? -e : n;
}

static long long readnum(const char *p) {
    char b[64];
    if (readfile(p, b, sizeof b) < 0) return -1;
    return atoll(b);
}

static uint64_t now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000000ull + ts.tv_nsec;
}

static void sleep_ms(int ms) {
    struct timespec ts = {ms / 1000, (ms % 1000) * 1000000L};
    while (nanosleep(&ts, &ts) != 0 && errno == EINTR) {}
}

// ── The workload ────────────────────────────────────────────────────────────

// Spinners: a fixed amount of arithmetic whose answer is known. A thread that
// was resumed with the wrong registers, or not resumed, gets it wrong or
// never finishes.
static uint64_t spin_rounds;

static uint64_t spin_job(uint64_t rounds) {
    uint64_t x = 0x9e3779b97f4a7c15ull, sum = 0;
    for (uint64_t i = 0; i < rounds; i++) {
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        sum += x ^ i;
    }
    return sum;
}

static void *spinner(void *arg) {
    *(uint64_t *)arg = spin_job(spin_rounds);
    return NULL;
}

// Sleepers: short timed sleeps, each ended by this CPU's idle timer.
struct sleeper {
    int count, each_us;
    int done;
    uint64_t worst_late_ns;
    int early;
};

static void *sleeper(void *arg) {
    struct sleeper *s = arg;
    for (int i = 0; i < s->count; i++) {
        struct timespec ts = {0, s->each_us * 1000L};
        uint64_t t0 = now_ns();
        while (nanosleep(&ts, &ts) != 0 && errno == EINTR) {}
        uint64_t took = now_ns() - t0;
        if (took < (uint64_t)s->each_us * 1000) s->early++;
        else if (took - (uint64_t)s->each_us * 1000 > s->worst_late_ns)
            s->worst_late_ns = took - (uint64_t)s->each_us * 1000;
        s->done++;
    }
    return NULL;
}

// Ping-pong: two threads that block in read() and are woken by each other's
// write(), for as long as the test runs. Every wake-up is one CPU handing
// work to another that may be idle; one that is lost stops the pair for good.
struct pair {
    int to_b[2], to_a[2];
    uint64_t until_ns;
    uint32_t trips;
    int bad;
};

static void *ping(void *arg) {
    struct pair *p = arg;
    uint32_t seq = 1;
    for (;;) {
        int last = now_ns() >= p->until_ns;
        uint32_t send = last ? 0 : seq;
        if (write(p->to_b[1], &send, 4) != 4) { p->bad++; break; }
        if (last) break;
        uint32_t back = 0;
        if (read(p->to_a[0], &back, 4) != 4 || back != seq + 1) { p->bad++; break; }
        seq += 2;
        p->trips++;
    }
    return NULL;
}

static void *pong(void *arg) {
    struct pair *p = arg;
    for (;;) {
        uint32_t got = 0;
        if (read(p->to_b[0], &got, 4) != 4) { p->bad++; break; }
        if (got == 0) break;
        got++;
        if (write(p->to_a[1], &got, 4) != 4) { p->bad++; break; }
    }
    return NULL;
}

#define SPINNERS 2
#define SLEEPERS 2
#define PAIRS 2

// One pass: `spinners` threads of arithmetic beside the sleepers and the pipe
// pairs, for about `ms`. With no spinners the CPUs are idle between wake-ups,
// which is the case the idle states are entered and left in; with them every
// CPU is busy and a wake-up has to preempt.
static void workload(const char *name, int spinners, int ms) {
    pthread_t spin_t[SPINNERS], sleep_t[SLEEPERS], ping_t[PAIRS], pong_t[PAIRS];
    uint64_t spin_result[SPINNERS];
    struct sleeper sl[SLEEPERS];
    struct pair pr[PAIRS];
    memset(sl, 0, sizeof sl);
    memset(pr, 0, sizeof pr);

    uint64_t start = now_ns();
    for (int i = 0; i < PAIRS; i++) {
        if (pipe(pr[i].to_a) != 0 || pipe(pr[i].to_b) != 0) { fail("pipe: errno %d", errno); return; }
        pr[i].until_ns = start + (uint64_t)ms * 1000000;
        pthread_create(&pong_t[i], NULL, pong, &pr[i]);
        pthread_create(&ping_t[i], NULL, ping, &pr[i]);
    }
    for (int i = 0; i < SLEEPERS; i++) {
        // 3 ms and 7 ms: between the idle ticks, and across them.
        sl[i].each_us = i == 0 ? 3000 : 7000;
        sl[i].count = ms * 1000 / sl[i].each_us;
        pthread_create(&sleep_t[i], NULL, sleeper, &sl[i]);
    }
    uint64_t expected = 0;
    if (spinners) {
        for (int i = 0; i < spinners; i++) pthread_create(&spin_t[i], NULL, spinner, &spin_result[i]);
        // The same job here, so the answer the others must give is known,
        // and so that a 2-CPU machine has more to run than it has CPUs.
        expected = spin_job(spin_rounds);
        for (int i = 0; i < spinners; i++) pthread_join(spin_t[i], NULL);
    }
    for (int i = 0; i < SLEEPERS; i++) pthread_join(sleep_t[i], NULL);
    for (int i = 0; i < PAIRS; i++) {
        pthread_join(ping_t[i], NULL);
        pthread_join(pong_t[i], NULL);
        close(pr[i].to_a[0]); close(pr[i].to_a[1]); close(pr[i].to_b[0]); close(pr[i].to_b[1]);
    }
    uint64_t took_ms = (now_ns() - start) / 1000000;

    for (int i = 0; i < spinners; i++)
        if (spin_result[i] != expected) fail("%s: spinner %d: %llx, expected %llx", name, i, (unsigned long long)spin_result[i], (unsigned long long)expected);
    uint32_t trips = 0;
    uint64_t late = 0;
    int slept = 0;
    for (int i = 0; i < SLEEPERS; i++) {
        if (sl[i].done != sl[i].count) fail("%s: sleeper %d: %d of %d sleeps", name, i, sl[i].done, sl[i].count);
        if (sl[i].early) fail("%s: sleeper %d: %d sleeps returned early", name, i, sl[i].early);
        if (sl[i].worst_late_ns > late) late = sl[i].worst_late_ns;
        slept += sl[i].done;
    }
    for (int i = 0; i < PAIRS; i++) {
        if (pr[i].bad) fail("%s: pipe pair %d: %d bad transfers", name, i, pr[i].bad);
        if (pr[i].trips == 0) fail("%s: pipe pair %d: no round trips", name, i);
        trips += pr[i].trips;
    }
    sayf("CPUTEST workload %s: %llu ms; %d spinners result %llx; %d timed sleeps, worst %llu us late; %u pipe round trips\n", name,
         (unsigned long long)took_ms, spinners ? spinners + 1 : 0, (unsigned long long)expected, slept,
         (unsigned long long)(late / 1000), trips);
}

static void workloads(void) {
    if (spin_rounds == 0) {
        // About 300 ms of arithmetic per spinner, as measured here over
        // long enough that the clock's own step does not matter.
        uint64_t rounds = 1000000, took = 0;
        for (;;) {
            uint64_t t0 = now_ns();
            volatile uint64_t sink = spin_job(rounds);
            (void)sink;
            took = now_ns() - t0;
            if (took >= 50000000 || rounds >= 1000000000) break;
            rounds *= 4;
        }
        spin_rounds = took ? rounds * 300000000ull / took : rounds;
        sayf("CPUTEST calibration: %llu rounds in %llu us; %llu rounds per spinner\n", (unsigned long long)rounds,
             (unsigned long long)(took / 1000), (unsigned long long)spin_rounds);
    }
    workload("idle", 0, 1500);
    workload("busy", SPINNERS, 1500);
}

// ── Idle states ─────────────────────────────────────────────────────────────

static int ncpus, nstates;

struct idle_sample {
    long long usage[MAX_CPUS][MAX_STATES];
    long long time_us[MAX_CPUS][MAX_STATES];
    long long idle_ticks[MAX_CPUS]; // /proc/stat, in 10 ms
    uint64_t at_ns;
};

static void state_path(char *p, int cap, int cpu, int state, const char *file) {
    snprintf(p, cap, CPU_DIR "/cpu%d/cpuidle/state%d/%s", cpu, state, file);
}

static void take(struct idle_sample *s) {
    char p[160];
    memset(s, 0, sizeof *s);
    s->at_ns = now_ns();
    for (int c = 0; c < ncpus; c++)
        for (int st = 0; st < nstates; st++) {
            state_path(p, sizeof p, c, st, "usage");
            s->usage[c][st] = readnum(p);
            state_path(p, sizeof p, c, st, "time");
            s->time_us[c][st] = readnum(p);
        }
    static char stat[8192];
    if (readfile("/proc/stat", stat, sizeof stat) > 0) {
        for (char *line = stat; line; line = strchr(line, '\n') ? strchr(line, '\n') + 1 : NULL) {
            int c;
            long long user, nice, sys, idle;
            if (sscanf(line, "cpu%d %lld %lld %lld %lld", &c, &user, &nice, &sys, &idle) == 5 && c >= 0 && c < MAX_CPUS)
                s->idle_ticks[c] = idle;
        }
    }
}

static int count_dirs(const char *dir, const char *prefix) {
    DIR *d = opendir(dir);
    if (!d) return 0;
    int n = 0;
    struct dirent *e;
    while ((e = readdir(d)))
        if (strncmp(e->d_name, prefix, strlen(prefix)) == 0 && e->d_name[strlen(prefix)] >= '0' && e->d_name[strlen(prefix)] <= '9') n++;
    closedir(d);
    return n;
}

static void show(const char *p) {
    char b[512];
    int n = readfile(p, b, sizeof b);
    if (n < 0) sayf("CPUTEST   %s: errno %d\n", p, -n);
    else sayf("CPUTEST   %s: %s\n", p, b);
}

static void idle_states(void) {
    char p[160], driver[64] = "?", b[128];
    ncpus = count_dirs(CPU_DIR, "cpu");
    if (ncpus > MAX_CPUS) ncpus = MAX_CPUS;
    if (readfile(CPU_DIR "/cpuidle/current_driver", driver, sizeof driver) < 0) fail("no cpuidle/current_driver");
    show(CPU_DIR "/cpuidle/current_driver");
    show(CPU_DIR "/cpuidle/current_governor");
    nstates = count_dirs(CPU_DIR "/cpu0/cpuidle", "state");
    if (nstates > MAX_STATES) nstates = MAX_STATES;
    sayf("CPUTEST idle: driver=%s cpus=%d states=%d\n", driver, ncpus, nstates);
    if (strcmp(driver, "none") == 0) {
        if (nstates != 0) fail("driver none with %d states", nstates);
        return;
    }
    if (nstates == 0) { fail("driver %s has no states", driver); return; }
    for (int st = 0; st < nstates; st++) {
        char name[64] = "", desc[64] = "";
        state_path(p, sizeof p, 0, st, "name"); readfile(p, name, sizeof name);
        state_path(p, sizeof p, 0, st, "desc"); readfile(p, desc, sizeof desc);
        state_path(p, sizeof p, 0, st, "latency"); long long lat = readnum(p);
        state_path(p, sizeof p, 0, st, "residency"); long long res = readnum(p);
        sayf("CPUTEST   state%d: name=%s desc=\"%s\" latency=%lld residency=%lld\n", st, name, desc, lat, res);
        if (!name[0] || lat < 0 || res < 0) fail("state%d is missing a file", st);
        static const char *files[] = {"usage", "time", "above", "below", "rejected", "disable"};
        for (unsigned f = 0; f < sizeof files / sizeof files[0]; f++) {
            state_path(p, sizeof p, ncpus - 1, st, files[f]);
            if (readfile(p, b, sizeof b) < 0) fail("%s cannot be read", p);
        }
    }

    // Across two quiet seconds every CPU must have idled, and the time in
    // its states must be about the time /proc/stat says it was idle.
    static struct idle_sample a, z;
    sleep_ms(200);
    take(&a);
    sleep_ms(2000);
    take(&z);
    long long window_us = (z.at_ns - a.at_ns) / 1000;
    for (int c = 0; c < ncpus; c++) {
        long long usage = 0, time_us = 0;
        for (int st = 0; st < nstates; st++) {
            usage += z.usage[c][st] - a.usage[c][st];
            time_us += z.time_us[c][st] - a.time_us[c][st];
        }
        long long idle_us = (z.idle_ticks[c] - a.idle_ticks[c]) * 10000;
        long long pct = idle_us > 0 ? time_us * 100 / idle_us : -1;
        sayf("CPUTEST   cpu%d: window=%lld us usage+%lld state_time+%lld us procstat_idle+%lld us (%lld%%)\n", c, window_us, usage,
             time_us, idle_us, pct);
        if (usage <= 0) fail("cpu%d: usage did not grow while idle", c);
        if (time_us <= 0) fail("cpu%d: time did not grow while idle", c);
        if (time_us > window_us * 105 / 100) fail("cpu%d: %lld us in idle states within %lld us", c, time_us, window_us);
        if (pct < 80 || pct > 120) fail("cpu%d: state time is %lld%% of idle time", c, pct);
    }

    // disable: the deepest state stops being used, on the CPUs it is written for.
    int deepest = nstates - 1;
    for (int c = 0; c < ncpus; c++) {
        state_path(p, sizeof p, c, deepest, "disable");
        int r = writefile(p, "1\n");
        if (r < 0) fail("%s: write 1: errno %d", p, -r);
        if (readnum(p) != 1) fail("%s: reads %lld after writing 1", p, readnum(p));
    }
    sleep_ms(300); // an idle already under way finishes and is counted
    take(&a);
    sleep_ms(1000);
    take(&z);
    for (int c = 0; c < ncpus; c++) {
        long long grew = z.usage[c][deepest] - a.usage[c][deepest];
        long long other = 0;
        for (int st = 0; st < deepest; st++) other += z.usage[c][st] - a.usage[c][st];
        sayf("CPUTEST   cpu%d: state%d disabled: usage+%lld, shallower states usage+%lld\n", c, deepest, grew, other);
        if (grew != 0) fail("cpu%d: disabled state%d was entered %lld times", c, deepest, grew);
        if (deepest > 0 && other <= 0) fail("cpu%d: no shallower state took over", c);
    }
    state_path(p, sizeof p, 0, deepest, "disable");
    int r = writefile(p, "2\n");
    sayf("CPUTEST   write 2 to disable: %d (EINVAL is %d)\n", r, -EINVAL);
    if (r != -EINVAL) fail("disable took 2");
    r = writefile(p, "on\n");
    if (r != -EINVAL) fail("disable took \"on\"");
    for (int c = 0; c < ncpus; c++) {
        state_path(p, sizeof p, c, deepest, "disable");
        r = writefile(p, "0\n");
        if (r < 0) fail("%s: write 0: errno %d", p, -r);
    }
    take(&a);
    sleep_ms(500);
    take(&z);
    for (int c = 0; c < ncpus; c++) {
        long long grew = z.usage[c][deepest] - a.usage[c][deepest];
        sayf("CPUTEST   cpu%d: state%d enabled again: usage+%lld\n", c, deepest, grew);
        if (grew <= 0) fail("cpu%d: state%d not used after enabling", c, deepest);
    }
    state_path(p, sizeof p, 0, 0, "usage");
    r = writefile(p, "0\n");
    sayf("CPUTEST   write to usage: %d\n", r);
    if (r >= 0) fail("usage is writable");
}

// ── /proc/cpuinfo ───────────────────────────────────────────────────────────

static void cpuinfo(void) {
    static char text[65536];
    int n = readfile("/proc/cpuinfo", text, sizeof text);
    if (n <= 0) { sayf("CPUTEST cpuinfo: unreadable (%d)\n", n); return; }
    char *flags = strstr(text, "flags\t");
    if (!flags) flags = strstr(text, "Features");
    int monitor = 0;
    if (flags) {
        char *end = strchr(flags, '\n');
        if (end) *end = 0;
        monitor = strstr(flags, " monitor") != NULL;
    }
    char *model = strstr(text, "model name");
    if (model) { char *end = strchr(model, '\n'); if (end && end < (flags ? flags : text + n)) *end = 0; }
    sayf("CPUTEST cpuinfo: monitor flag %s\n", monitor ? "present" : "absent");
}

int main(void) {
    int fd = open(CONSOLE, O_WRONLY);
    if (fd >= 0) out = fd;
    sayf("CPUTEST START\n");
    cpuinfo();
    workloads();
    idle_states();
#ifdef CPUFREQ_TEST
    cpufreq();
#endif
    // Once more after the files were written to: the idle path still wakes.
    workloads();
    sayf("CPUTEST DONE failures=%d\n", failures);
    sync();
    reboot(RB_POWER_OFF);
    for (;;) pause();
}

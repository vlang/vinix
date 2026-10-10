// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Guest side of the thermal test: run as /sbin/init, it reads what the kernel
// publishes under /sys/class/thermal, /sys/class/hwmon and /sys/class/powercap
// and, on a kernel built with -d thermal_selftest, walks the virtual zone
// through heating, cooling, a hot trip, a critical trip, a failing sensor and
// its removal, watching the limit on CPU performance the whole way.
//
// Every line it prints starts with THERMAL. A check prints `THERMAL ok ...` or
// `THERMAL FAIL ...`; the last line but one is `THERMAL RESULT pass=N fail=M`,
// and `THERMAL DONE` means the program ran to its end.
//
// Kept in C so that it can be dropped into an initramfs with nothing else;
// the V test suite in this directory is to take it over.
#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdarg.h>
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

#define CLASS "/sys/class/thermal"
#define LIMIT CLASS "/thermal_limit"
#define STATE CLASS "/cooling_device0/cur_state"
#define POLLS CLASS "/poll_count"
#define CRITICAL CLASS "/critical_count"
#define NONE LONG_MIN

static int out = 1;
static int passed, failed;
static char zone[128];
static char hwmon[128];

static void sayf(const char *fmt, ...) {
    char b[1024];
    va_list ap;
    va_start(ap, fmt);
    int n = vsnprintf(b, sizeof b, fmt, ap);
    va_end(ap);
    if (n > (int)sizeof b - 1) n = sizeof b - 1;
    if (n > 0) write(out, b, n);
}

static void check(int ok, const char *fmt, ...) {
    char b[512];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(b, sizeof b, fmt, ap);
    va_end(ap);
    if (ok) passed++; else failed++;
    sayf("THERMAL %s %s\n", ok ? "ok" : "FAIL", b);
}

static void nap(int ms) {
    struct timespec t = { ms / 1000, (long)(ms % 1000) * 1000000 };
    nanosleep(&t, 0);
}

static int readfile(const char *p, char *buf, int cap) {
    int fd = open(p, O_RDONLY);
    if (fd < 0) return -errno;
    int n = read(fd, buf, cap - 1);
    int e = errno;
    close(fd);
    if (n < 0) return -e;
    buf[n] = 0;
    return n;
}

static int writefile(const char *p, const char *text) {
    int fd = open(p, O_WRONLY);
    if (fd < 0) return -errno;
    int n = write(fd, text, strlen(text));
    int e = errno;
    close(fd);
    return n < 0 ? -e : n;
}

// The number a file holds, or NONE when it cannot be read or holds none: a
// temperature that could not be read is an empty file.
static long number(const char *p) {
    char b[64];
    int n = readfile(p, b, sizeof b);
    if (n <= 0) return NONE;
    char *end;
    long v = strtol(b, &end, 10);
    return end == b ? NONE : v;
}

static long in_dir(const char *dir, const char *name) {
    char p[256];
    snprintf(p, sizeof p, "%s/%s", dir, name);
    return number(p);
}

static const char *word(const char *dir, const char *name) {
    static char b[128];
    char p[256];
    snprintf(p, sizeof p, "%s/%s", dir, name);
    int n = readfile(p, b, sizeof b);
    if (n < 0) return "<unreadable>";
    while (n > 0 && (b[n - 1] == '\n' || b[n - 1] == ' ')) b[--n] = 0;
    return b;
}

static int put(const char *dir, const char *name, const char *text) {
    char p[256];
    snprintf(p, sizeof p, "%s/%s", dir, name);
    return writefile(p, text);
}

static int exists(const char *p) {
    struct stat st;
    return lstat(p, &st) == 0;
}

static void walk(const char *path, int depth) {
    DIR *d = opendir(path);
    if (!d) {
        sayf("THERMAL   %s: cannot open, errno %d\n", path, errno);
        return;
    }
    struct dirent *e;
    while ((e = readdir(d))) {
        if (e->d_name[0] == '.') continue;
        char p[512];
        snprintf(p, sizeof p, "%s/%s", path, e->d_name);
        struct stat st;
        if (lstat(p, &st) != 0) {
            sayf("THERMAL   %s: stat errno %d\n", p, errno);
            continue;
        }
        if (S_ISLNK(st.st_mode)) {
            char t[256];
            int n = readlink(p, t, sizeof t - 1);
            t[n < 0 ? 0 : n] = 0;
            sayf("THERMAL   %s -> %s%s\n", p, t, stat(p, &st) == 0 ? "" : " DANGLING");
        } else if (S_ISDIR(st.st_mode)) {
            sayf("THERMAL   %s/\n", p);
            if (depth < 6) walk(p, depth + 1);
        } else {
            char b[400];
            int n = (st.st_mode & 0444) ? readfile(p, b, sizeof b) : 0;
            if (n > 0 && b[n - 1] == '\n') b[n - 1] = 0;
            for (char *c = b; n > 0 && *c; c++) if (*c == '\n') *c = '|';
            sayf("THERMAL   %s %o [%s]\n", p, st.st_mode & 0777, n < 0 ? "ERR" : n == 0 ? "" : b);
        }
    }
    closedir(d);
}

// The directory of the first zone of type `type`, and its hwmon directory.
static int find_zone(const char *type) {
    for (int i = 0; i < 16; i++) {
        char dir[128];
        snprintf(dir, sizeof dir, CLASS "/thermal_zone%d", i);
        if (!exists(dir)) continue;
        if (strcmp(word(dir, "type"), type) == 0) {
            strcpy(zone, dir);
            snprintf(hwmon, sizeof hwmon, "/sys/class/hwmon/hwmon%d", i);
            return 1;
        }
    }
    return 0;
}

static int count_zones(void) {
    int n = 0;
    for (int i = 0; i < 16; i++) {
        char dir[128];
        snprintf(dir, sizeof dir, CLASS "/thermal_zone%d", i);
        if (exists(dir)) n++;
    }
    return n;
}

// Wait for `n` more passes of the polling thread, at most `ms` milliseconds.
// Two passes after a write are sure to include one that began after it.
static int passes(int n, int ms) {
    long start = number(POLLS);
    for (int waited = 0; waited < ms; waited += 10) {
        if (number(POLLS) - start >= n) return 1;
        nap(10);
    }
    return 0;
}

static void heat(long millicelsius) {
    char b[32];
    snprintf(b, sizeof b, "%ld\n", millicelsius);
    int n = put(zone, "emul_temp", b);
    if (n < 0) check(0, "write %ld to emul_temp: errno %d", millicelsius, -n);
    passes(2, 5000);
}

// Record the limit after each pass until it reads `target` or `max` passes
// have gone by. The sequence is every value the limit took, in order.
static int follow(long target, int max, long *seq, int cap) {
    int n = 0;
    long last = number(LIMIT);
    for (int i = 0; i < max && last != target; i++) {
        passes(1, 3000);
        long now = number(LIMIT);
        if (now != last && n < cap) seq[n++] = now;
        last = now;
    }
    return n;
}

static void print_seq(const char *what, long from, const long *seq, int n) {
    char b[256];
    int at = snprintf(b, sizeof b, "%ld", from);
    for (int i = 0; i < n && at < (int)sizeof b - 16; i++) at += snprintf(b + at, sizeof b - at, " %ld", seq[i]);
    sayf("THERMAL %s: limit %s\n", what, b);
}

static int steps_of_ten(long from, const long *seq, int n, int up) {
    long last = from;
    for (int i = 0; i < n; i++) {
        if (seq[i] - last != (up ? 10 : -10)) return 0;
        last = seq[i];
    }
    return 1;
}

static void selftest(void) {
    long seq[32];
    int n;

    sayf("THERMAL selftest zone %s, hwmon %s\n", zone, hwmon);
    check(strcmp(word(zone, "policy"), "step_wise") == 0, "policy is step_wise");
    check(strcmp(word(zone, "mode"), "enabled") == 0, "mode is enabled");
    check(strcmp(word(zone, "trip_point_0_type"), "passive") == 0 && in_dir(zone, "trip_point_0_temp") == 80000,
          "trip 0 is passive at 80000");
    check(strcmp(word(zone, "trip_point_1_type"), "hot") == 0 && in_dir(zone, "trip_point_1_temp") == 95000,
          "trip 1 is hot at 95000");
    check(strcmp(word(zone, "trip_point_2_type"), "critical") == 0 && in_dir(zone, "trip_point_2_temp") == 105000,
          "trip 2 is critical at 105000");
    check(in_dir(zone, "trip_point_0_hyst") == 5000, "passive hysteresis is 5000");
    check(number(CLASS "/cooling_device0/max_state") == 9, "cooling_device0/max_state is 9");

    // Heating: one step for each reading that is higher than the last.
    heat(40000);
    check(in_dir(zone, "temp") == 40000, "temp reads back 40000");
    check(number(LIMIT) == 100 && number(STATE) == 0, "cool: limit 100, cur_state 0");
    static const long rising[] = { 70000, 80000, 82000, 84000, 86000, 88000 };
    static const long expect[] = { 100, 90, 80, 70, 60, 50 };
    char line[256];
    int at = 0, good = 1;
    for (int i = 0; i < 6; i++) {
        heat(rising[i]);
        long limit = number(LIMIT), state = number(STATE);
        at += snprintf(line + at, sizeof line - at, " %ld:%ld/%ld", rising[i] / 1000, limit, state);
        if (limit != expect[i] || state != (100 - expect[i]) / 10) good = 0;
    }
    sayf("THERMAL heating (C:limit/cur_state):%s\n", line);
    check(good, "heating past 80 C lowers the limit a step per rising reading");

    // Steady or falling above the trip, and inside the hysteresis: hold.
    heat(88000);
    passes(2, 3000);
    check(number(LIMIT) == 50, "steady at 88 C holds the limit at 50");
    heat(85000);
    check(number(LIMIT) == 50, "falling to 85 C, still above the trip, holds 50");
    heat(78000);
    check(number(LIMIT) == 50, "78 C, inside the hysteresis, holds 50");

    // Below the hysteresis: back up a step each pass.
    put(zone, "emul_temp", "70000\n");
    n = follow(100, 20, seq, 32);
    print_seq("cooling to 70 C", 50, seq, n);
    check(n == 5 && steps_of_ten(50, seq, n, 1) && number(LIMIT) == 100 && number(STATE) == 0,
          "cooling below the hysteresis restores the limit to 100 a step at a time");

    // Hot: the lowest limit at once.
    put(zone, "emul_temp", "96000\n");
    n = follow(10, 6, seq, 32);
    print_seq("hot at 96 C", 100, seq, n);
    check(n == 1 && seq[0] == 10 && number(STATE) == 9, "95 C and over drops the limit to 10 at once");
    put(zone, "emul_temp", "60000\n");
    n = follow(100, 20, seq, 32);
    print_seq("cooling to 60 C", 10, seq, n);
    check(n == 9 && steps_of_ten(10, seq, n, 1), "and cooling gives it back a step at a time");

    // Critical: the handler, once for as long as it stays there.
    long before = number(CRITICAL);
    heat(106000);
    long once = number(CRITICAL);
    passes(4, 5000);
    long still = number(CRITICAL);
    sayf("THERMAL critical at 106 C: critical_count %ld -> %ld, after 4 more passes %ld, limit %ld\n", before, once,
         still, number(LIMIT));
    check(once == before + 1 && still == once, "105 C and over calls the critical handler exactly once");
    check(number(LIMIT) == 10, "and holds the limit at 10");
    check(in_dir(hwmon, "temp1_crit_alarm") == 1, "temp1_crit_alarm is 1");
    put(zone, "emul_temp", "60000\n");
    n = follow(100, 20, seq, 32);
    check(number(LIMIT) == 100, "cooling from critical restores the limit");
    heat(106000);
    check(number(CRITICAL) == before + 2, "a second excursion calls the handler a second time");
    put(zone, "emul_temp", "60000\n");
    follow(100, 20, seq, 32);

    // A sensor that fails: not a temperature. The limit stays, the zone goes.
    heat(82000);
    long held = number(LIMIT);
    long failures = in_dir(zone, "read_failures");
    long polls = number(POLLS);
    put(zone, "emul_temp", "error\n");
    int disabled = 0;
    for (int i = 0; i < 40 && !disabled; i++) {
        passes(1, 3000);
        disabled = strcmp(word(zone, "mode"), "disabled") == 0;
    }
    long took = number(POLLS) - polls;
    long counted = in_dir(zone, "read_failures") - failures;
    sayf("THERMAL failing sensor: limit %ld before; disabled after %ld passes, %ld failed readings; limit %ld, temp [%s]\n",
         held, took, counted, number(LIMIT), word(zone, "temp"));
    check(held == 90, "one step taken before the sensor fails");
    check(disabled && counted == 5, "five failed readings in a row disable the zone");
    check(number(LIMIT) == held && number(STATE) == 1, "and leave the limit where it was");
    check(in_dir(zone, "temp") == NONE, "temp reads as nothing while the sensor fails");
    passes(3, 5000);
    check(in_dir(zone, "read_failures") - failures == 5 && number(LIMIT) == held,
          "a disabled zone is not read again");
    put(zone, "emul_temp", "-300000\n");
    check(in_dir(zone, "temp") == NONE, "a value below absolute zero means the same");
    put(zone, "emul_temp", "60000\n");
    check(strcmp(word(zone, "mode"), "disabled") == 0, "a working sensor does not enable the zone by itself");
    check(put(zone, "mode", "enabled\n") > 0 && strcmp(word(zone, "mode"), "enabled") == 0,
          "writing enabled to mode brings it back");
    follow(100, 20, seq, 32);
    check(number(LIMIT) == 100, "and the limit is given back");

    // Switched off by hand.
    check(put(zone, "mode", "disabled\n") > 0, "mode accepts disabled");
    heat(90000);
    check(number(LIMIT) == 100, "a disabled zone at 90 C changes nothing");
    check(put(zone, "mode", "bogus\n") == -EINVAL, "mode refuses anything else");
    put(zone, "mode", "enabled\n");
    passes(2, 3000);
    check(number(LIMIT) == 90, "enabled again, it takes its first step");
    put(zone, "emul_temp", "40000\n");
    follow(100, 20, seq, 32);

    // The hwmon view.
    heat(45000);
    check(strcmp(word(hwmon, "name"), "vinix_selftest") == 0, "hwmon name");
    check(in_dir(hwmon, "temp1_input") == 45000 && in_dir(hwmon, "temp2_input") == 40000,
          "temp1_input and temp2_input");
    check(strcmp(word(hwmon, "temp1_label"), "Selftest") == 0, "temp1_label");
    check(in_dir(hwmon, "temp1_max") == 80000 && in_dir(hwmon, "temp1_crit") == 105000, "temp1_max and temp1_crit");
    check(in_dir(hwmon, "temp1_crit_alarm") == 0, "temp1_crit_alarm is 0");
    check(put(hwmon, "pwm1", "128\n") > 0 && in_dir(hwmon, "fan1_input") == 1500 && in_dir(hwmon, "pwm1") == 128,
          "pwm1 sets the fan: fan1_input 1500");
    check(put(hwmon, "pwm1", "300\n") == -EINVAL, "pwm1 refuses 300");

    // Taking the zone away gives back what it held and, with no zone left,
    // stops the polling.
    int others = count_zones() - 1;
    heat(82000);
    check(number(LIMIT) == 90, "holding a step before removal");
    check(writefile(CLASS "/selftest_zone", "0\n") > 0, "unregister through selftest_zone");
    check(!exists(zone) && !exists(hwmon), "the zone's directories are gone");
    check(number(LIMIT) == 100 && number(STATE) == 0, "and its step with it");
    if (others == 0) {
        nap(1300);
        long idle = number(POLLS);
        nap(2500);
        check(number(POLLS) == idle, "no zones: the polling thread does not run");
    }
    check(writefile(CLASS "/selftest_zone", "1\n") > 0 && find_zone("vinix_selftest"), "registered again");
    check(passes(2, 5000), "and polled again");
    for (int i = 0; i < 20; i++) {
        writefile(CLASS "/selftest_zone", "0\n");
        writefile(CLASS "/selftest_zone", "1\n");
    }
    check(find_zone("vinix_selftest") && in_dir(zone, "temp") == 82000, "twenty more removals and registrations");
    put(zone, "emul_temp", "40000\n");
    follow(100, 20, seq, 32);
    check(number(LIMIT) == 100, "limit 100 at the end");
}

int main(void) {
    int fd = open(CONSOLE, O_WRONLY);
    if (fd >= 0) out = fd;
    sayf("THERMAL START\n");
    walk("/sys/class/thermal", 0);
    walk("/sys/class/hwmon", 0);
    if (exists("/sys/class/powercap")) walk("/sys/class/powercap", 0);
    else sayf("THERMAL   /sys/class/powercap: absent\n");

    int have = find_zone("vinix_selftest");
    int zones = count_zones();
    sayf("THERMAL zones=%d real=%d selftest=%d\n", zones, zones - have, have);
    check(exists(CLASS "/cooling_device0/cur_state") && number(LIMIT) == 100, "cooling device there, limit 100");
    if (have) {
        selftest();
    } else {
        long before = number(POLLS);
        nap(2500);
        long after = number(POLLS);
        sayf("THERMAL no selftest zone; poll_count %ld then %ld\n", before, after);
        if (zones == 0) check(before == 0 && after == 0, "no zones: the polling thread never ran");
    }
    sayf("THERMAL RESULT pass=%d fail=%d\n", passed, failed);
    sayf("THERMAL DONE\n");
    sync();
    reboot(RB_POWER_OFF);
    for (;;) pause();
}

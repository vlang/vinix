// SPDX-License-Identifier: GPL-2.0-or-later
#define _GNU_SOURCE
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <time.h>
#include <unistd.h>

static int metrics_failures;

static void metrics_check(int okay, const char *name) {
    printf("ACTIVITY-CHECK %s %s\n", okay ? "PASS" : "FAIL", name);
    if (!okay) metrics_failures++;
}

static int read_text(const char *path, char *text, size_t size) {
    int fd = open(path, O_RDONLY);
    if (fd < 0) return -1;
    ssize_t count = read(fd, text, size - 1);
    close(fd);
    if (count < 0) return -1;
    text[count] = 0;
    return (int)count;
}

static uint64_t field(const char *text, const char *key) {
    size_t length = strlen(key);
    for (const char *line = text; line && *line; ) {
        if (!strncmp(line, key, length) && line[length] == ':') {
            unsigned long long value = 0;
            return sscanf(line + length + 1, "%llu", &value) == 1 ? (uint64_t)value : 0;
        }
        const char *next = strchr(line, '\n');
        line = next ? next + 1 : NULL;
    }
    return 0;
}

static uint64_t nanoseconds(void) {
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return (uint64_t)now.tv_sec * 1000000000ULL + (uint64_t)now.tv_nsec;
}

static uint64_t busy_ticks(const char *text) {
    unsigned long long user = 0, nice = 0, system = 0;
    if (sscanf(text, "cpu %llu %llu %llu", &user, &nice, &system) != 3) return 0;
    return (uint64_t)(user + nice + system);
}

static uint64_t core_busy_ticks(const char *text) {
    uint64_t total = 0;
    for (const char *line = strstr(text, "\ncpu"); line; line = strstr(line + 1, "\ncpu")) {
        const char *fields = strchr(line + 1, ' ');
        unsigned long long user = 0, nice = 0, system = 0;
        if (fields && sscanf(fields, "%llu %llu %llu", &user, &nice, &system) == 3)
            total += (uint64_t)(user + nice + system);
    }
    return total;
}

static void cpu_metrics(void) {
    char before[24576], after[24576];
    int first = read_text("/proc/stat", before, sizeof before);
    metrics_check(first > 0 && strstr(before, "\ncpu0 "), "per-core CPU counters available");
    uint64_t end = nanoseconds() + 300000000ULL;
    volatile uint64_t work = 1;
    while (nanoseconds() < end) {
        for (int i = 0; i < 100000; ++i) work = work * 6364136223846793005ULL + 1;
    }
    int second = read_text("/proc/stat", after, sizeof after);
    metrics_check(first > 0 && second > 0 && busy_ticks(after) > busy_ticks(before),
                  "machine CPU counters advance under computation");
    metrics_check(first > 0 && second > 0 && core_busy_ticks(after) > core_busy_ticks(before),
                  "per-core CPU counters advance under computation");
    (void)work;
}

static void file_metrics(void) {
    char before[1024], after[1024], data[4096], copied[4096];
    memset(data, 0x5a, sizeof data);
    int first = read_text("/proc/self/io", before, sizeof before);
    metrics_check(first > 0 && strstr(before, "rchar:") && strstr(before, "read_bytes:") &&
                  strstr(before, "net_recv_bytes:"), "process I/O counters available");
    int fd = open("/tmp/activity-io-test", O_CREAT | O_TRUNC | O_RDWR, 0600);
    metrics_check(fd >= 0, "create I/O accounting fixture");
    if (fd < 0) return;
    metrics_check(write(fd, data, sizeof data) == sizeof data &&
                  pwrite(fd, data, sizeof data, 4096) == sizeof data,
                  "regular and positioned writes complete");
    metrics_check(lseek(fd, 0, SEEK_SET) == 0 && read(fd, copied, sizeof copied) == sizeof copied &&
                  pread(fd, copied, sizeof copied, 4096) == sizeof copied &&
                  !memcmp(data, copied, sizeof data), "regular and positioned reads complete");
    close(fd);
    unlink("/tmp/activity-io-test");
    int second = read_text("/proc/self/io", after, sizeof after);
    metrics_check(first > 0 && second > 0 && field(after, "rchar") >= field(before, "rchar") + 8192 &&
                  field(after, "wchar") >= field(before, "wchar") + 8192,
                  "process logical read and write bytes are charged");
    char global[1024];
    metrics_check(read_text("/proc/activity_io", global, sizeof global) > 0 &&
                  strstr(global, "disk_read_bytes:") && strstr(global, "disk_write_bytes:"),
                  "completed physical disk counters available");
}

static void network_metrics(void) {
    char before[1024], after[1024], data[512], copied[512];
    memset(data, 0x27, sizeof data);
    int first = read_text("/proc/self/io", before, sizeof before);
    int receiver = socket(AF_INET, SOCK_DGRAM, 0);
    int sender = socket(AF_INET, SOCK_DGRAM, 0);
    metrics_check(receiver >= 0 && sender >= 0, "create INET payload accounting sockets");
    if (receiver < 0 || sender < 0) {
        if (receiver >= 0) close(receiver);
        if (sender >= 0) close(sender);
        return;
    }
    struct timeval timeout = { .tv_sec = 1 };
    setsockopt(receiver, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof timeout);
    struct sockaddr_in address = { .sin_family = AF_INET, .sin_addr.s_addr = htonl(INADDR_LOOPBACK) };
    socklen_t length = sizeof address;
    int bound = bind(receiver, (struct sockaddr *)&address, sizeof address) == 0 &&
                getsockname(receiver, (struct sockaddr *)&address, &length) == 0;
    metrics_check(bound, "bind loopback payload receiver");
    ssize_t sent = bound ? sendto(sender, data, sizeof data, 0, (struct sockaddr *)&address, length) : -1;
    ssize_t received = sent == sizeof data ? recvfrom(receiver, copied, sizeof copied, 0, NULL, NULL) : -1;
    metrics_check(sent == sizeof data && received == sizeof copied && !memcmp(data, copied, sizeof data),
                  "INET loopback payload transfer completes");
    close(sender);
    close(receiver);
    int second = read_text("/proc/self/io", after, sizeof after);
    metrics_check(first > 0 && second > 0 && field(after, "net_send_bytes") >= field(before, "net_send_bytes") + 512 &&
                  field(after, "net_recv_bytes") >= field(before, "net_recv_bytes") + 512,
                  "process network payload bytes are charged");
    char global[1024];
    int present = read_text("/proc/activity_io", global, sizeof global) > 0;
    metrics_check(present && second > 0 && field(global, "net_send_bytes") >= field(after, "net_send_bytes") &&
                  field(global, "net_recv_bytes") >= field(after, "net_recv_bytes"),
                  "machine network totals include process payload bytes");
}

struct slab_count { uint64_t size, live; };

static int slab_counts(struct slab_count counts[32]) {
    char text[4096];
    if (read_text("/proc/slabinfo", text, sizeof text) <= 0) return 0;
    int count = 0;
    for (const char *line = text; line && *line && count < 32; ) {
        unsigned long long size = 0, live = 0;
        if (sscanf(line, "size-%*u %llu %llu", &size, &live) == 2)
            counts[count++] = (struct slab_count){ (uint64_t)size, (uint64_t)live };
        const char *next = strchr(line, '\n');
        line = next ? next + 1 : NULL;
    }
    return count;
}

static void repeated_metric_reads(void) {
    static const char *machine_paths[] = {
        "/proc/stat", "/proc/activity_io", "/proc/activity_gpu", "/proc/meminfo"
    };
    static const char *process_files[] = { "io", "cmdline", "status", "stat", "statm", "maps" };
    char paths[16][64];
    for (unsigned i = 0; i < 4; ++i)
        snprintf(paths[i], sizeof paths[i], "%s", machine_paths[i]);
    for (unsigned i = 0; i < 6; ++i) {
        // The monitor uses numeric PID paths. Also exercise the self symlink,
        // used by accounting clients, so its transient builder cannot leak.
        snprintf(paths[4 + i], sizeof paths[4 + i], "/proc/%ld/%s", (long)getpid(), process_files[i]);
        snprintf(paths[10 + i], sizeof paths[10 + i], "/proc/self/%s", process_files[i]);
    }
    char text[24576];
    int completed = 1;
    // Instantiate procfs nodes and settle the grace queue before measurement.
    for (int warm = 0; warm < 8; ++warm)
        for (unsigned path = 0; path < sizeof paths / sizeof paths[0]; ++path)
            completed &= read_text(paths[path], text, sizeof text) >= 0;
    usleep(20000);
    int flat = 1;
    for (unsigned path = 0; path < sizeof paths / sizeof paths[0]; ++path) {
        struct slab_count before[32], after[32];
        int first = slab_counts(before);
        for (int iteration = 0; iteration < 500; ++iteration)
            completed &= read_text(paths[path], text, sizeof text) >= 0;
        usleep(20000);
        int second = slab_counts(after);
        flat &= first > 0 && first == second;
        int64_t total = 0;
        for (int i = 0; i < first && i < second; ++i) {
            int64_t objects = (int64_t)after[i].live - (int64_t)before[i].live;
            total += objects;
            if (objects)
                printf("ACTIVITY-SLAB path=%s size=%llu delta_objects=%lld reads=500\n",
                       paths[path], (unsigned long long)after[i].size, (long long)objects);
            // Bounded worker/diagnostic noise is possible, but one retained
            // object per repeated read must fail. Deltas remain in the log.
            if (before[i].size != after[i].size || objects >= 250) flat = 0;
        }
        printf("ACTIVITY-SLAB path=%s retained_objects=%lld reads=500\n", paths[path], (long long)total);
    }
    metrics_check(completed, "repeat every Activity Monitor procfs reader 500 times");
    metrics_check(flat, "repeated Activity Monitor reads do not retain per-read slab objects");
}

int activity_metrics_checks(void) {
    metrics_failures = 0;
    cpu_metrics();
    file_metrics();
    network_metrics();
    repeated_metric_reads();
    return metrics_failures;
}

#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <unistd.h>

#define CHECK(x) do { if (!(x)) { printf("PROCFS ALLOCS FAIL line=%d errno=%d\n", __LINE__, errno); for (;;) pause(); } } while (0)
static int baseline;
struct heap { long size[32], objects[32], large; int n; };

static void heap_snapshot(struct heap *h)
{
    memset(h, 0, sizeof(*h));
    FILE *f = fopen("/proc/slabinfo", "r"); CHECK(f != NULL);
    char line[256]; long index, size, objects, pages;
    while (fgets(line, sizeof line, f)) {
        if (sscanf(line, "size-%ld %ld %ld %ld", &index, &size, &objects, &pages) == 4 && h->n < 32) {
            h->size[h->n] = size; h->objects[h->n++] = objects;
        } else if (sscanf(line, "large - - %ld", &pages) == 1) h->large = pages;
    }
    CHECK(fclose(f) == 0 && h->n > 0);
}

static void sites(const char *path, const char *label)
{
    FILE *file = fopen(path, "r"); CHECK(file != NULL);
    char line[512];
    while (fgets(line, sizeof line, file)) {
        if (label) printf("PERF-SITE variant=focus scenario=ops round=1 op=%s dir=/tmp %s", label, line);
    }
    CHECK(!ferror(file) && fclose(file) == 0);
}

static void read_proc(void)
{
    static const char *paths[] = {"/proc/self/stat", "/proc/self/status", "/proc/meminfo",
        "/proc/uptime", "/proc/self/maps", "/proc/stat"};
    static const char *tokens[] = {" (", "Name:", "MemTotal:", ".", "r", "cpu "};
    char buffer[4096];
    for (size_t i = 0; i < sizeof paths / sizeof paths[0]; i++) {
        int fd = open(paths[i], O_RDONLY); CHECK(fd >= 0);
        ssize_t n = read(fd, buffer, sizeof buffer - 1); CHECK(n > 0);
        buffer[n] = 0; CHECK(strstr(buffer, tokens[i]) != NULL);
        while ((n = read(fd, buffer, sizeof buffer)) > 0) {}
        CHECK(n == 0 && close(fd) == 0);
    }
}

static int list(const char *path)
{
    DIR *dir = opendir(path); CHECK(dir != NULL);
    struct dirent *entry; int count = 0;
    errno = 0;
    while ((entry = readdir(dir)) != NULL) { CHECK(entry->d_name[0] != 0); count++; }
    CHECK(errno == 0 && closedir(dir) == 0);
    return count;
}

static void list_many(void) { CHECK(list("/many") == 1403); }
static void list_proc(void) { CHECK(list("/proc") >= 10); }

static void measure(const char *label, void (*operation)(void), int count)
{
    for (int i = 0; i < 20; i++) operation();
    struct heap before, after;
    heap_snapshot(&before); sites("/proc/allocstart", NULL);
    for (int i = 0; i < count; i++) operation();
    heap_snapshot(&after); sites("/proc/allocsites", label);
    CHECK(before.n == after.n);
    long kept = (after.large - before.large) * sysconf(_SC_PAGESIZE);
    for (int i = 0; i < before.n; i++) {
        long delta = after.objects[i] - before.objects[i];
        printf("PROCFS ALLOCS HEAP op=%s size=%ld delta=%ld\n", label, before.size[i], delta);
        kept += delta * before.size[i];
        if (!baseline) CHECK(delta < 32);
    }
    printf("PROCFS ALLOCS MEASURE op=%s count=%d retained=%ld large=%ld\n", label, count, kept, after.large - before.large);
    if (!baseline) CHECK(kept < 16384 && after.large - before.large < 2);
}

static void records(void)
{
    unsigned char buffer[320];
    int fd = open("/many", O_RDONLY | O_DIRECTORY); CHECK(fd >= 0);
    /* A failed copy must be a checked syscall failure, not a kernel fault. */
    CHECK(syscall(SYS_getdents64, fd, (void *)1, sizeof buffer) == -1 && errno == EFAULT);
    CHECK(close(fd) == 0);
    fd = open("/many", O_RDONLY | O_DIRECTORY); CHECK(fd >= 0);
    if (!baseline) CHECK(syscall(SYS_getdents64, fd, buffer, 1) == -1 && errno == EINVAL);
    int seen[1400] = {0}, long_seen = 0, total = 0, dots = 0;
    ssize_t n;
    while ((n = syscall(SYS_getdents64, fd, buffer, sizeof buffer)) > 0) {
        for (ssize_t offset = 0; offset < n;) {
            uint16_t length; memcpy(&length, buffer + offset + 16, 2);
            CHECK(length >= 24 && length % 8 == 0 && offset + length <= n);
            const char *name = (const char *)buffer + offset + 19;
            const char *end = memchr(name, 0, length - 19); CHECK(end != NULL);
            for (const unsigned char *pad = (const unsigned char *)end + 1; pad < buffer + offset + length; pad++) CHECK(*pad == 0);
            if (!strcmp(name, ".") || !strcmp(name, "..")) {
                CHECK(buffer[offset + 18] == DT_DIR); dots++; offset += length; continue;
            }
            CHECK(buffer[offset + 18] == DT_REG);
            if (!strncmp(name, "long-", 5)) { CHECK(strlen(name) == 255 && !long_seen++); }
            else { int value = -1; CHECK(sscanf(name, "f%d", &value) == 1 && value >= 0 && value < 1400 && !seen[value]++); }
            total++; offset += length;
        }
    }
    printf("PROCFS ALLOCS RECORDS n=%ld total=%d long=%d\n", (long)n, total, long_seen);
    CHECK(n == 0 && total == 1401 && long_seen == 1 && dots == 2 && close(fd) == 0);
    int file = open("/many/f0000", O_RDONLY); CHECK(file >= 0);
    CHECK(syscall(SYS_getdents64, file, buffer, sizeof buffer) == -1 && errno == ENOTDIR);
    CHECK(close(file) == 0);
#ifdef __x86_64__
    fd = open("/many", O_RDONLY | O_DIRECTORY); CHECK(fd >= 0);
    total = 0;
    while ((n = syscall(SYS_getdents, fd, buffer, sizeof buffer)) > 0) {
        for (ssize_t offset = 0; offset < n;) {
            uint16_t length; memcpy(&length, buffer + offset + 16, 2);
            CHECK(length >= 24 && length % 8 == 0 && offset + length <= n);
            const char *name = (const char *)buffer + offset + 18;
            CHECK(memchr(name, 0, length - 19) != NULL);
            unsigned char type = buffer[offset + length - 1];
            CHECK(type == ((!strcmp(name, ".") || !strcmp(name, "..")) ? DT_DIR : DT_REG));
            total++; offset += length;
        }
    }
    CHECK(n == 0 && total == 1403 && close(fd) == 0);
#endif
}

static void name_bounds(void)
{
    CHECK(mkdir("/huge", 0700) == 0);
    char path[1040] = "/huge/";
    memset(path + 6, 'x', 1024); path[1030] = 0;
    int file = open(path, O_CREAT | O_WRONLY, 0600); CHECK(file >= 0 && close(file) == 0);
    int fd = open("/huge", O_RDONLY | O_DIRECTORY); CHECK(fd >= 0);
    unsigned char buffer[1056];
    for (int i = 0; i < 40; i++)
        CHECK(syscall(SYS_getdents64, fd, buffer, sizeof buffer) == -1 && errno == ENAMETOOLONG);
    CHECK(unlink(path) == 0);
    /* The failed, invalid snapshot is rebuilt by the same handle after repair. */
    CHECK(syscall(SYS_getdents64, fd, buffer, sizeof buffer) == 48);
    CHECK(syscall(SYS_getdents64, fd, buffer, sizeof buffer) == 0 && close(fd) == 0);
    path[1029] = 0;
    file = open(path, O_CREAT | O_WRONLY, 0600); CHECK(file >= 0 && close(file) == 0);
    fd = open("/huge", O_RDONLY | O_DIRECTORY); CHECK(fd >= 0);
    int found = 0; ssize_t n;
    while ((n = syscall(SYS_getdents64, fd, buffer, sizeof buffer)) > 0) {
        for (ssize_t offset = 0; offset < n;) {
            uint16_t length; memcpy(&length, buffer + offset + 16, 2);
            CHECK(length >= 24 && length % 8 == 0 && offset + length <= n);
            const char *name = (const char *)buffer + offset + 19;
            const char *end = memchr(name, 0, length - 19); CHECK(end != NULL);
            if (name[0] == 'x') CHECK(strlen(name) == 1023 && length == 1048 && !found++);
            offset += length;
        }
    }
    CHECK(n == 0 && found == 1 && close(fd) == 0 && unlink(path) == 0);
    CHECK(rmdir("/huge") == 0);
}

int main(void)
{
    setbuf(stdout, NULL);
#ifdef __x86_64__
    int console = open("/dev/com1", O_WRONLY);
    CHECK(console >= 0 && dup2(console, 1) == 1 && dup2(console, 2) == 2 && close(console) == 0);
#endif
    baseline = access("/proc-leaks-baseline", F_OK) == 0;
    char long_name[300] = "/many/long-";
    memset(long_name + 11, 'x', 250); long_name[261] = 0;
    int long_fd = open(long_name, O_CREAT | O_WRONLY, 0600); CHECK(long_fd >= 0 && close(long_fd) == 0);
    read_proc(); puts("PROCFS ALLOCS PASS: contents");
    records();
    if (!baseline) name_bounds();
    puts("PROCFS ALLOCS PASS: records");
    measure("proc_read", read_proc, 200);
    measure("proc_list", list_proc, 200);
    measure("many", list_many, 40);
    puts("PROCFS ALLOCS PASS: growth");
    puts("PROCFS ALLOCS GUEST: PASS");
    for (;;) pause();
}

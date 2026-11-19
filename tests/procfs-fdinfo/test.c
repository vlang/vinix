// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/reboot.h>
#include <sys/stat.h>
#include <unistd.h>

static int failures;

static void check(int ok, const char *message) {
    if (!ok) {
        printf("FAIL: procfs fdinfo: %s (errno=%d)\n", message, errno);
        fflush(stdout);
        ++failures;
    }
}

// The whole of /proc/self/fdinfo/<fd>, or -1.
static int read_fdinfo(int fd, char *text, size_t size) {
    char path[64];
    snprintf(path, sizeof(path), "/proc/self/fdinfo/%d", fd);
    int info = open(path, O_RDONLY | O_CLOEXEC);
    if (info < 0) return -1;
    size_t used = 0;
    for (;;) {
        ssize_t got = read(info, text + used, size - 1 - used);
        if (got < 0) { close(info); return -1; }
        if (got == 0) break;
        used += (size_t)got;
        if (used == size - 1) break;
    }
    text[used] = 0;
    close(info);
    return (int)used;
}

// The value of a "key:\t<value>" line, read in `base`.
static int field(const char *text, const char *key, unsigned long long *value, int base) {
    char pattern[64];
    snprintf(pattern, sizeof(pattern), "%s:\t", key);
    const char *line = text;
    while (line && *line) {
        if (strncmp(line, pattern, strlen(pattern)) == 0) {
            char *end = NULL;
            errno = 0;
            *value = strtoull(line + strlen(pattern), &end, base);
            return errno == 0 && end && *end == '\n';
        }
        line = strchr(line, '\n');
        if (line) line++;
    }
    return 0;
}

static void regular_file(void) {
    char text[512];
    unsigned long long value = 0;
    int fd = open("/tmp/fdinfo-file", O_RDWR | O_CREAT | O_TRUNC | O_CLOEXEC, 0600);
    check(fd >= 0, "create a file");
    check(write(fd, "0123456789abcdef", 16) == 16 && lseek(fd, 5, SEEK_SET) == 5, "write and seek");
    struct stat st;
    check(fstat(fd, &st) == 0, "stat the file");
    check(read_fdinfo(fd, text, sizeof(text)) > 0, "read fdinfo of a file");
    check(strncmp(text, "pos:\t5\nflags:\t0", 15) == 0, "pos and flags come first, flags in octal");
    check(field(text, "pos", &value, 10) && value == 5, "pos is the file offset");
    check(field(text, "flags", &value, 8) && value == (unsigned long long)(O_RDWR | O_CLOEXEC | O_LARGEFILE),
          "flags are the access mode, O_CLOEXEC and O_LARGEFILE, without O_CREAT or O_TRUNC");
    check(field(text, "mnt_id", &value, 10), "mnt_id is a number");
    check(field(text, "ino", &value, 10) && value == (unsigned long long)st.st_ino, "ino is the file's inode");
    check(strstr(text, "drm-") == NULL, "an ordinary file has no DRM lines");

    int plain = dup(fd);
    check(plain >= 0 && read_fdinfo(plain, text, sizeof(text)) > 0, "read fdinfo of a duplicate");
    check(field(text, "flags", &value, 8) && (value & O_CLOEXEC) == 0, "a dup is not close-on-exec");
    check(field(text, "pos", &value, 10) && value == 5, "a dup shares the offset");
    check(fcntl(plain, F_SETFD, FD_CLOEXEC) == 0 && read_fdinfo(plain, text, sizeof(text)) > 0
          && field(text, "flags", &value, 8) && (value & O_CLOEXEC) != 0, "F_SETFD shows in flags");

    int found = 0;
    DIR *dir = opendir("/proc/self/fdinfo");
    check(dir != NULL, "list /proc/self/fdinfo");
    if (dir) {
        struct dirent *entry;
        while ((entry = readdir(dir)) != NULL) {
            if (atoi(entry->d_name) == plain && entry->d_name[0] != '.') found = 1;
        }
        closedir(dir);
    }
    check(found, "the listing names an open descriptor");
    char path[64];
    snprintf(path, sizeof(path), "/proc/%d/fdinfo/%d", getpid(), plain);
    int by_pid = open(path, O_RDONLY | O_CLOEXEC);
    check(by_pid >= 0, "open fdinfo through the process id");
    // One open file reads one snapshot, a byte at a time as at once.
    char whole[512], bytes[512];
    int whole_length = read_fdinfo(plain, whole, sizeof(whole));
    size_t used = 0;
    if (by_pid >= 0) {
        while (used < sizeof(bytes) - 1 && read(by_pid, bytes + used, 1) == 1) used++;
    }
    bytes[used] = 0;
    check(whole_length > 0 && strcmp(whole, bytes) == 0, "a byte-at-a-time read matches a whole read");
    if (by_pid >= 0) close(by_pid);
    int early = open(path, O_RDONLY | O_CLOEXEC);
    check(early >= 0, "open fdinfo before the descriptor closes");
    check(close(plain) == 0 && read_fdinfo(plain, text, sizeof(text)) < 0 && errno == ENOENT,
          "a closed descriptor has no fdinfo");
    char after[64];
    check(early >= 0 && read(early, after, sizeof(after)) < 0 && errno == ENOENT,
          "an entry opened before the close reads as gone");
    if (early >= 0) close(early);
    close(fd);
    unlink("/tmp/fdinfo-file");
    puts("PASS: fdinfo of files: offset, flags, mount, inode, listing and closed descriptors");
}

static unsigned long long client_of(int fd, char *driver, size_t driver_size) {
    char text[1024];
    unsigned long long client = 0;
    check(read_fdinfo(fd, text, sizeof(text)) > 0, "read fdinfo of a DRM file");
    const char *name = strstr(text, "\ndrm-driver:\t");
    check(name != NULL, "a DRM file names its driver");
    if (name && driver) {
        name += strlen("\ndrm-driver:\t");
        size_t length = strcspn(name, "\n");
        if (length >= driver_size) length = driver_size - 1;
        memcpy(driver, name, length);
        driver[length] = 0;
    }
    check(field(text, "drm-client-id", &client, 10) && client != 0, "a DRM file has a client id");
    const char *driver_line = strstr(text, "drm-driver:");
    const char *ino_line = strstr(text, "\nino:\t");
    check(driver_line && ino_line && driver_line > ino_line, "DRM lines follow the generic ones");
    return client;
}

static void drm_files(void) {
    int first = open("/dev/dri/card0", O_RDWR | O_CLOEXEC);
    if (first < 0) {
        puts("SKIP: no /dev/dri/card0");
        return;
    }
    char driver[64] = "";
    unsigned long long a = client_of(first, driver, sizeof(driver));
    char sample[1024];
    if (read_fdinfo(first, sample, sizeof(sample)) > 0) printf("fdinfo of /dev/dri/card0:\n%s", sample);
    check(client_of(first, NULL, 0) == a, "a description keeps its client id");
    int second = open("/dev/dri/card0", O_RDWR | O_CLOEXEC);
    check(second >= 0, "open the DRM node again");
    unsigned long long b = client_of(second, NULL, 0);
    check(b != a, "another open is another client");
    int shared = dup(first);
    check(shared >= 0 && client_of(shared, NULL, 0) == a, "a duplicate is the same client");
    close(shared);
    close(second);
    int third = open("/dev/dri/card0", O_RDWR | O_CLOEXEC);
    unsigned long long c = third >= 0 ? client_of(third, NULL, 0) : 0;
    check(c != a && c != b, "a client id is not reused");
    close(third);
    int path = open("/dev/dri/card0", O_PATH | O_CLOEXEC);
    char text[512];
    check(path >= 0 && read_fdinfo(path, text, sizeof(text)) > 0 && strstr(text, "drm-") == NULL,
          "an O_PATH descriptor has no DRM lines");
    if (path >= 0) close(path);
    close(first);
    printf("PASS: fdinfo of DRM files: driver %s, stable distinct client ids\n", driver);
}

#define MAX_CLASSES 64

struct heap {
    int count;
    long size[MAX_CLASSES];
    long objects[MAX_CLASSES];
    long large_pages;
};

static int read_heap(struct heap *h) {
    FILE *f = fopen("/proc/slabinfo", "r");
    if (!f) return -1;
    char line[256];
    h->count = 0;
    h->large_pages = 0;
    while (fgets(line, sizeof line, f)) {
        long size, objects, pages;
        if (sscanf(line, "size-%*d %ld %ld %ld", &size, &objects, &pages) == 3 && h->count < MAX_CLASSES) {
            h->size[h->count] = size;
            h->objects[h->count] = objects;
            h->count++;
        } else if (sscanf(line, "large - - %ld", &pages) == 1) {
            h->large_pages = pages;
        }
    }
    fclose(f);
    return 0;
}

static const char *phase_names[] = {"file fdinfo reads", "fdinfo listings", "DRM opens alone",
                                    "DRM opens with fdinfo reads", "entries made and pruned"};

static void churn_cycle(int phase, int fd) {
    char text[1024];
    if (phase == 0) {
        read_fdinfo(fd, text, sizeof(text));
    } else if (phase == 1) {
        DIR *dir = opendir("/proc/self/fdinfo");
        if (dir) {
            while (readdir(dir) != NULL) {}
            closedir(dir);
        }
    } else if (phase == 4) {
        // A descriptor opened, shown and closed before the next listing:
        // its entry is made, then pruned, every cycle.
        int brief = open("/tmp/fdinfo-churn", O_RDONLY | O_CLOEXEC);
        if (brief >= 0) {
            read_fdinfo(brief, text, sizeof(text));
            close(brief);
        }
        DIR *dir = opendir("/proc/self/fdinfo");
        if (dir) {
            while (readdir(dir) != NULL) {}
            closedir(dir);
        }
    } else {
        int card = open("/dev/dri/card0", O_RDWR | O_CLOEXEC);
        if (card >= 0) {
            if (phase == 3) read_fdinfo(card, text, sizeof(text));
            close(card);
        }
    }
}

// Per-class object growth over 200 cycles of one phase, after a warm-up and
// `settle` seconds for anything freed after a grace period.
static void phase_growth(int phase, int fd, struct heap *growth, unsigned settle) {
    // A phase that waits for the grace period warms up as long as it measures,
    // so queues sized by the backlog reach their high-water mark first.
    int warmup = settle ? 200 : 20;
    for (int i = 0; i < warmup; i++) churn_cycle(phase, fd);
    if (settle) sleep(settle);
    struct heap before, after;
    check(read_heap(&before) == 0, "read /proc/slabinfo");
    for (int i = 0; i < 200; i++) churn_cycle(phase, fd);
    if (settle) sleep(settle);
    check(read_heap(&after) == 0 && after.count == before.count, "read /proc/slabinfo again");
    growth->count = before.count;
    for (int i = 0; i < before.count && i < after.count; i++) {
        growth->size[i] = before.size[i];
        growth->objects[i] = after.objects[i] - before.objects[i];
        if (growth->objects[i] > 8)
            printf("%s: size-%ld grew by %ld objects over 200 cycles\n", phase_names[phase], before.size[i],
                   growth->objects[i]);
    }
    growth->large_pages = after.large_pages - before.large_pages;
    if (growth->large_pages > 1)
        printf("%s: large pages grew by %ld\n", phase_names[phase], growth->large_pages);
}

// What fdinfo reads, listings and DRM client numbers keep allocated: every
// heap size class must stay flat over 200 cycles, where a leak would grow one
// class by about 200 objects. Opening a DRM file is measured on its own, so
// that only what reading its fdinfo adds is charged here.
static void flat_memory(void) {
    int fd = open("/tmp/fdinfo-churn", O_RDWR | O_CREAT | O_TRUNC | O_CLOEXEC, 0600);
    check(fd >= 0, "create the churn file");
    int phases = access("/dev/dri/card0", F_OK) == 0 ? 4 : 2;
    struct heap growth[5];
    for (int phase = 0; phase < phases; phase++) phase_growth(phase, fd, &growth[phase], 0);
    // Pruned entries are freed after the removed-node grace period of five
    // seconds, reaped once a second.
    phase_growth(4, fd, &growth[4], 8);
    long largest = 0;
    for (int phase = 0; phase < 5; phase++) {
        if (phase == 2 || (phase == 3 && phases < 4)) continue;
        for (int i = 0; i < growth[phase].count; i++) {
            long added = growth[phase].objects[i];
            if (phase == 3 && i < growth[2].count) added -= growth[2].objects[i];
            if (added > largest) largest = added;
            if (added > 8) {
                printf("FAIL: procfs fdinfo: %s add %ld size-%ld objects\n", phase_names[phase], added,
                       growth[phase].size[i]);
                ++failures;
            }
        }
        long pages = growth[phase].large_pages - (phase == 3 ? growth[2].large_pages : 0);
        check(pages <= 1, "large pages stay flat");
    }
    close(fd);
    unlink("/tmp/fdinfo-churn");
    printf("PASS: 200 cycles each of fdinfo reads, listings, DRM fdinfo reads and pruned entries keep every heap class flat "
           "(largest growth %ld)\n", largest);
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    alarm(120);
    regular_file();
    drm_files();
    flat_memory();
    if (failures) printf("FAIL: procfs fdinfo (%d checks)\n", failures);
    else puts("VINIX PROCFS FDINFO: PASS");
    fflush(stdout);
    sync();
    reboot(RB_POWER_OFF);
    for (;;) pause();
}

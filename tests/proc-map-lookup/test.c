// SPDX-License-Identifier: GPL-2.0-or-later
#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/reboot.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

enum { children_per_round = 12, rounds = 4, inspectors = 3 };
static pthread_mutex_t state_lock = PTHREAD_MUTEX_INITIALIZER;
static pid_t children[children_per_round], owner;
static unsigned observed, listed, epoch;
static int active, stopped, failures;
static unsigned long lookups, listings;

static void fail(const char *what) {
    printf("FAIL: proc map lookup: %s errno=%d\n", what, errno);
    __atomic_add_fetch(&failures, 1, __ATOMIC_RELAXED);
}

static int failed(void) { return __atomic_load_n(&failures, __ATOMIC_RELAXED); }

static int read_process(pid_t pid, int required) {
    const char *names[] = { "stat", "status", "comm" };
    char path[96], text[2048];
    for (unsigned i = 0; i < sizeof(names) / sizeof(names[0]); ++i) {
        snprintf(path, sizeof(path), "/proc/%d/%s", pid, names[i]);
        int fd = open(path, O_RDONLY);
        if (fd < 0) {
            if (required || (errno != ENOENT && errno != ESRCH)) fail("open process entry");
            return 0;
        }
        ssize_t count = read(fd, text, sizeof(text) - 1);
        int error = errno;
        if (close(fd)) fail("close process entry");
        if (count <= 0) {
            errno = error;
            if (required) fail("read stable process entry");
            return 0;
        }
        text[count] = 0;
        if (!strcmp(names[i], "status") && !strstr(text, "State:\t"))
            fail("status keeps its state field");
    }
    __atomic_add_fetch(&lookups, 1, __ATOMIC_RELAXED);
    return 1;
}

static int listing(pid_t pid, const char *suffix, int required, int process_dir) {
    char path[96];
    if (pid) snprintf(path, sizeof(path), "/proc/%d%s", pid, suffix);
    else snprintf(path, sizeof(path), "/proc%s", suffix);
    DIR *directory = opendir(path);
    if (!directory) {
        if (required || (errno != ENOENT && errno != ESRCH)) fail("open directory snapshot");
        return 0;
    }
    int dot = 0, dotdot = 0, status = 0, stat = 0;
    struct dirent *entry;
    errno = 0;
    while ((entry = readdir(directory))) {
        if (!memchr(entry->d_name, 0, sizeof(entry->d_name))) fail("terminated directory name");
        dot |= !strcmp(entry->d_name, ".");
        dotdot |= !strcmp(entry->d_name, "..");
        status |= !strcmp(entry->d_name, "status");
        stat |= !strcmp(entry->d_name, "stat");
    }
    int error = errno;
    if (closedir(directory)) fail("close directory snapshot");
    if (error) { errno = error; fail("read directory snapshot"); }
    if (!dot || !dotdot || (process_dir && (!status || !stat))) fail("snapshot contains required entries");
    __atomic_add_fetch(&listings, 1, __ATOMIC_RELAXED);
    return !error;
}

static int stable_operation(void) {
    if (!read_process(owner, 1) || !listing(0, "", 1, 0)
        || !listing(owner, "", 1, 1) || !listing(owner, "/task", 1, 0)
        || !listing(owner, "/fd", 1, 0)) return 0;
    const char *links[] = { "exe", "cwd", "root" };
    char path[96], target[256];
    for (unsigned i = 0; i < sizeof(links) / sizeof(links[0]); ++i) {
        snprintf(path, sizeof(path), "/proc/%d/%s", owner, links[i]);
        if (readlink(path, target, sizeof(target)) <= 0) fail("refresh process magic link");
    }
    return !failed();
}

static void *inspector(void *argument) {
    uintptr_t kind = (uintptr_t)argument;
    unsigned slot = 0;
    while (!__atomic_load_n(&stopped, __ATOMIC_ACQUIRE) && !failed()) {
        if (kind == 2) {
            listing(0, "", 1, 0);
            listing(owner, "", 1, 1);
            listing(owner, "/task", 1, 0);
            listing(owner, "/fd", 1, 0);
        } else read_process(owner, 1);
        pthread_mutex_lock(&state_lock);
        unsigned saved_epoch = epoch;
        pid_t child = active ? children[slot % active] : 0;
        unsigned saved_slot = active ? slot % active : 0;
        pthread_mutex_unlock(&state_lock);
        if (child) {
            int saw = kind == 2 ? listing(child, "", 0, 1) : read_process(child, 0);
            if (saw) {
                pthread_mutex_lock(&state_lock);
                if (epoch == saved_epoch && saved_slot < (unsigned)active && children[saved_slot] == child) {
                    if (kind == 2) listed |= 1u << saved_slot;
                    else observed |= 1u << saved_slot;
                }
                pthread_mutex_unlock(&state_lock);
            }
        }
        ++slot;
        const struct timespec pause = { .tv_nsec = 1000000 };
        nanosleep(&pause, NULL);
    }
    return NULL;
}

struct heap { long size[32], live[32], pages[32], large, uaf; int count; };
static int snapshot(struct heap *heap) {
    memset(heap, 0, sizeof(*heap));
    FILE *file = fopen("/proc/slabinfo", "r");
    if (!file) { fail("open allocation snapshot"); return 0; }
    char line[256]; int large = 0, uaf = 0;
    while (fgets(line, sizeof(line), file)) {
        long label, size, live, pages;
        if (sscanf(line, "size-%ld %ld %ld %ld", &label, &size, &live, &pages) == 4 && label == size) {
            if (heap->count == 32) { fail("allocation class capacity"); break; }
            int i = heap->count++;
            heap->size[i] = size; heap->live[i] = live; heap->pages[i] = pages;
        } else if (sscanf(line, "large - - %ld", &pages) == 1) { heap->large = pages; large = 1; }
        else if (sscanf(line, "# written after free %ld", &live) == 1) { heap->uaf = live; uaf = 1; }
    }
    if (fclose(file)) fail("close allocation snapshot");
#ifdef __aarch64__
    if (heap->count != 18 || !large || !uaf) fail("complete ARM allocation snapshot");
#else
    if (heap->count != 14 || !large || !uaf) fail("complete x86 allocation snapshot");
#endif
    return !failed();
}

int main(void) {
    setbuf(stdout, NULL);
    alarm(600);
    owner = getpid();
    pthread_t threads[inspectors]; int started = 0;
    for (; started < inspectors; ++started) {
        int error = pthread_create(&threads[started], NULL, inspector, (void *)(uintptr_t)started);
        if (error) { errno = error; fail("start concurrent inspector"); break; }
    }
    for (int round = 0; round < rounds && !failed(); ++round) {
        int gate[2];
        if (pipe(gate)) { fail("create child lifetime gate"); break; }
        pid_t cohort[children_per_round]; int count = 0;
        for (; count < children_per_round; ++count) {
            pid_t pid = fork();
            if (!pid) { close(gate[1]); char byte; ssize_t got = read(gate[0], &byte, 1); _exit(got == 1 ? 0 : 1); }
            if (pid < 0) { fail("fork map-growth child"); break; }
            cohort[count] = pid;
        }
        close(gate[0]);
        pthread_mutex_lock(&state_lock);
        ++epoch; observed = listed = 0; active = count;
        memcpy(children, cohort, count * sizeof(*cohort));
        pthread_mutex_unlock(&state_lock);
        unsigned all = (1u << count) - 1;
        while (!failed()) {
            pthread_mutex_lock(&state_lock);
            int complete = observed == all && listed == all;
            pthread_mutex_unlock(&state_lock);
            if (complete) break;
            const struct timespec pause = { .tv_nsec = 1000000 }; nanosleep(&pause, NULL);
        }
        pthread_mutex_lock(&state_lock); active = 0; ++epoch; pthread_mutex_unlock(&state_lock);
        char release[children_per_round]; memset(release, 'X', sizeof(release));
        if (write(gate[1], release, count) != count) fail("release map-growth children");
        close(gate[1]);
        for (int i = 0; i < count; ++i) {
            int status;
            if (waitpid(cohort[i], &status, 0) != cohort[i] || !WIFEXITED(status) || WEXITSTATUS(status))
                fail("reap map-growth child");
        }
        printf("proc map lookup: completed growth cohort %d children=%d\n", round + 1, count);
    }
    __atomic_store_n(&stopped, 1, __ATOMIC_RELEASE);
    for (int i = 0; i < started; ++i) if (pthread_join(threads[i], NULL)) fail("join inspector");
    if (lookups < 100 || listings < 100) fail("concurrent lookup and snapshot progress");
    // The dynamic tree intentionally retains pruned nodes. Measure repeated
    // snapshot/lookup buffers only after all growth and inspection have ended.
    for (int i = 0; i < 20 && !failed(); ++i) stable_operation();
    const struct timespec grace = { .tv_sec = 7 }; nanosleep(&grace, NULL);
    struct heap before, after;
    if (!failed() && snapshot(&before)) {
        for (int i = 0; i < 200 && !failed(); ++i) stable_operation();
        if (snapshot(&after)) {
            if (before.count != after.count) fail("allocation class count remains stable");
            for (int i = 0; i < before.count && i < after.count; ++i) {
                printf("PROC-MAP-RETENTION class=%ld live=%ld pages=%ld\n", before.size[i], after.live[i] - before.live[i], after.pages[i] - before.pages[i]);
                if (before.size[i] != after.size[i] || before.live[i] != after.live[i] || before.pages[i] != after.pages[i])
                    fail("snapshot and lookup buffers remain flat");
            }
            printf("PROC-MAP-RETENTION large=%ld uaf=%ld\n", after.large - before.large, after.uaf - before.uaf);
            if (before.large != after.large || before.uaf != after.uaf) fail("large allocations and UAF remain flat");
        }
    }
    printf("proc map lookup: %lu lookups, %lu directory snapshots\n", lookups, listings);
    if (!failed()) puts("VINIX PROC MAP LOOKUP: PASS");
    if (owner != 1) return failed() ? 1 : 0;
    sync(); reboot(RB_POWER_OFF); for (;;) pause();
}

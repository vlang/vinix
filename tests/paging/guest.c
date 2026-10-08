#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/swap.h>
#include <sys/sysinfo.h>
#include <sys/wait.h>
#include <unistd.h>

#ifndef MADV_PAGEOUT
#define MADV_PAGEOUT 21
#endif
static size_t page;
#define CHECK(condition) do { if (!(condition)) { printf("PAGING FAIL line=%d errno=%d\n", __LINE__, errno); fflush(stdout); _exit(1); } } while (0)

static unsigned char *mapping(size_t pages, int shared) {
    unsigned char *p = mmap(NULL, pages * page, PROT_READ | PROT_WRITE,
                           MAP_ANONYMOUS | (shared ? MAP_SHARED : MAP_PRIVATE), -1, 0);
    CHECK(p != MAP_FAILED);
    return p;
}
static void out(void *p, size_t pages) { CHECK(madvise(p, pages * page, MADV_PAGEOUT) == 0); }
static void pattern(unsigned char *p, size_t pages, int random) {
    uint32_t x = 97;
    for (size_t i = 0; i < pages * page; ++i) {
        x ^= x << 13; x ^= x >> 17; x ^= x << 5;
        p[i] = random ? (unsigned char)x : (unsigned char)(i / page + 37);
    }
}
static void verify(const unsigned char *p, size_t pages, int random) {
    uint32_t x = 97;
    for (size_t i = 0; i < pages * page; ++i) {
        x ^= x << 13; x ^= x >> 17; x ^= x << 5;
        CHECK(p[i] == (random ? (unsigned char)x : (unsigned char)(i / page + 37)));
    }
}
static void wait_ok(pid_t pid) { int status; CHECK(waitpid(pid, &status, 0) == pid); CHECK(WIFEXITED(status) && WEXITSTATUS(status) == 0); }

static void private_pages(void) {
    unsigned char *p = mapping(8, 0);
    pattern(p, 8, 0); out(p, 8);
    unsigned char resident[8];
    CHECK(mincore(p, page * 8, resident) == 0);
    for (int i = 0; i < 8; ++i) CHECK(!(resident[i] & 1));
    pid_t pid = fork(); CHECK(pid >= 0);
    if (!pid) { verify(p, 8, 0); p[0] = 201; out(p, 8); CHECK(p[0] == 201); _exit(0); }
    wait_ok(pid); verify(p, 8, 0);
    out(p, 8);
    CHECK(mprotect(p, page * 8, PROT_NONE) == 0);
    CHECK(mprotect(p, page * 8, PROT_READ | PROT_WRITE) == 0); verify(p, 8, 0);
    out(p, 8);
    p = mremap(p, page * 8, page * 12, MREMAP_MAYMOVE); CHECK(p != MAP_FAILED);
    verify(p, 8, 0);
    for (size_t i = page * 8; i < page * 12; ++i) CHECK(p[i] == 0);
    out(p, 12);
    CHECK(madvise(p + page, page, MADV_DONTNEED) == 0);
    for (size_t i = 0; i < page; ++i) CHECK(p[page + i] == 0);
    CHECK(p[0] == 37 && p[page * 2] == 39);
    CHECK(mlock(p, page) == 0); out(p, 1);
    CHECK(mincore(p, page, resident) == 0 && (resident[0] & 1));
    CHECK(munlock(p, page) == 0); CHECK(munmap(p, page * 12) == 0);
    printf("PAGING private PASS\n"); fflush(stdout);
}

static void shared_pages(void) {
    unsigned char *p = mapping(4, 1); pattern(p, 4, 0);
    int to_child[2], to_parent[2]; CHECK(pipe(to_child) == 0 && pipe(to_parent) == 0);
    pid_t pid = fork(); CHECK(pid >= 0);
    if (!pid) {
        char byte;
        CHECK(read(to_child[0], &byte, 1) == 1); verify(p, 4, 0);
        p[page + 11] = 191; out(p, 4);
        CHECK(write(to_parent[1], "x", 1) == 1);
        CHECK(read(to_child[0], &byte, 1) == 1); CHECK(p[0] == 211);
        CHECK(munmap(p, page * 4) == 0); _exit(0);
    }
    out(p, 4);
    unsigned char *moved = mremap(p, page * 4, page * 6, MREMAP_MAYMOVE); CHECK(moved != MAP_FAILED);
    CHECK(write(to_child[1], "x", 1) == 1);
    char byte; CHECK(read(to_parent[0], &byte, 1) == 1); CHECK(moved[page + 11] == 191);
    moved[0] = 211; out(moved, 6);
    CHECK(write(to_child[1], "x", 1) == 1); wait_ok(pid);
    CHECK(moved[0] == 211 && moved[page + 11] == 191);
    CHECK(munmap(moved, page * 6) == 0);
    for (int i = 0; i < 2; ++i) { close(to_child[i]); close(to_parent[i]); }
    printf("PAGING shared-remap PASS\n"); fflush(stdout);
}

static unsigned char *race_pages;
static void signal_handler(int sig) { (void)sig; }
static void *evict_worker(void *unused) {
    (void)unused;
    for (int i = 0; i < 100; ++i) { out(race_pages, 16); CHECK(kill(getpid(), SIGUSR1) == 0); }
    return NULL;
}
static void concurrent_refault(void) {
    struct sigaction action = {.sa_handler = signal_handler}; CHECK(sigaction(SIGUSR1, &action, NULL) == 0);
    race_pages = mapping(16, 0); pattern(race_pages, 16, 0);
    pthread_t worker; CHECK(pthread_create(&worker, NULL, evict_worker, NULL) == 0);
    for (int i = 0; i < 100; ++i) verify(race_pages, 16, 0);
    CHECK(pthread_join(worker, NULL) == 0); verify(race_pages, 16, 0);
    CHECK(munmap(race_pages, 16 * page) == 0);
    printf("PAGING concurrent-signal-refault PASS\n"); fflush(stdout);
}

static unsigned long meminfo_value(const char *key) {
    FILE *f = fopen("/proc/meminfo", "r"); CHECK(f != NULL);
    char line[256]; unsigned long value = 0; int found = 0;
    while (fgets(line, sizeof line, f))
        if (strncmp(line, key, strlen(key)) == 0) { CHECK(sscanf(line + strlen(key), "%lu", &value) == 1); found = 1; break; }
    CHECK(fclose(f) == 0 && found); return value;
}

static void pressure_pages(void) {
    if (access("/paging-pressure", F_OK) != 0) return;
    struct sysinfo info; CHECK(sysinfo(&info) == 0);
    size_t pages = (size_t)((uint64_t)info.totalram * info.mem_unit / page);
    unsigned long before = meminfo_value("VinixPageouts:");
    unsigned char *p = mapping(pages, 0);
    for (size_t i = 0; i < pages; ++i) p[i * page] = (unsigned char)(i * 37 + 11);
    CHECK(meminfo_value("VinixPageouts:") > before);
    for (size_t i = 0; i < pages; ++i) CHECK(p[i * page] == (unsigned char)(i * 37 + 11));
    CHECK(munmap(p, pages * page) == 0);
    printf("PAGING automatic-pressure-reclaim PASS pages=%zu\n", pages); fflush(stdout);
}

static void disk_pages(void) {
    const char *devices[] = {"/dev/vda", "/dev/sd0", "/dev/ata0", "/dev/nvme0n1"};
    const char *device = NULL;
    for (size_t i = 0; i < sizeof(devices) / sizeof(devices[0]); ++i)
        if (access(devices[i], F_OK) == 0) { device = devices[i]; break; }
    if (!device) { printf("PAGING disk SKIP (no swap device)\n"); return; }
    for (int i = 0; swapon(device, 0) != 0; ++i) { CHECK(errno == EAGAIN && i < 40); sleep(1); }
    struct sysinfo info; CHECK(sysinfo(&info) == 0 && info.totalswap > 0);
    unsigned char *p = mapping(64, 0); pattern(p, 64, 1); out(p, 64);
    CHECK(sysinfo(&info) == 0 && info.freeswap < info.totalswap);
    int fd = open(device, O_WRONLY); CHECK(fd == -1 && errno == EBUSY);
    pid_t pid = fork(); CHECK(pid >= 0);
    if (!pid) { verify(p, 64, 1); unsigned char original = p[0]; p[0] ^= 0x55; out(p, 64); CHECK(p[0] == (unsigned char)(original ^ 0x55)); _exit(0); }
    wait_ok(pid); verify(p, 64, 1); out(p, 64);
    unsigned char *shared = mapping(4, 1); pattern(shared, 4, 1); out(shared, 4);
    pid = fork(); CHECK(pid >= 0);
    if (!pid) { verify(shared, 4, 1); shared[19] = 203; out(shared, 4); _exit(0); }
    wait_ok(pid); CHECK(shared[19] == 203); out(shared, 4);
    pressure_pages();
    CHECK(swapoff(device) == 0); CHECK(sysinfo(&info) == 0 && info.totalswap == 0);
    verify(p, 64, 1); CHECK(munmap(p, page * 64) == 0);
    CHECK(shared[19] == 203); CHECK(munmap(shared, page * 4) == 0);
    printf("PAGING encrypted-disk-swapoff PASS\n"); fflush(stdout);
}

static void slab_snapshot(long objects[64], long sizes[64], int *count) {
    FILE *f = fopen("/proc/slabinfo", "r"); CHECK(f != NULL);
    char line[256]; *count = 0;
    while (fgets(line, sizeof line, f)) {
        long size, live, pages;
        if (sscanf(line, "size-%*d %ld %ld %ld", &size, &live, &pages) == 3) {
            CHECK(*count < 64); sizes[*count] = size; objects[(*count)++] = live;
        }
    }
    CHECK(fclose(f) == 0);
}

static void churn(int rounds) {
    for (int i = 0; i < rounds; ++i) {
        unsigned char *p = mapping(4, 0); pattern(p, 4, 0); out(p, 4);
        CHECK(munmap(p, page * 4) == 0);
    }
}

static void measured_churn(void) {
    churn(20);
    unsigned long stored = meminfo_value("Zswapped:");
    long before[64], after[64], sizes[64], after_sizes[64]; int count, after_count;
    slab_snapshot(before, sizes, &count); churn(200); slab_snapshot(after, after_sizes, &after_count);
    CHECK(count == after_count);
    for (int i = 0; i < count; ++i) {
        CHECK(sizes[i] == after_sizes[i]);
        printf("PAGING SLAB size=%ld before=%ld after=%ld delta=%ld rounds=200\n", sizes[i], before[i], after[i], after[i] - before[i]);
    }
    CHECK(meminfo_value("Zswapped:") <= stored);
}

int main(void) {
    page = (size_t)sysconf(_SC_PAGESIZE); CHECK(page == 4096 || page == 16384);
    printf("PAGING START page=%zu\n", page); fflush(stdout);
    private_pages(); shared_pages(); concurrent_refault(); disk_pages();
    measured_churn();
    printf("PAGING PASS\n"); fflush(stdout);
    for (;;) pause();
}

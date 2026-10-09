#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/statfs.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

#ifndef VINIX_TEST_MEMORY_MIB
#define VINIX_TEST_MEMORY_MIB 1024
#endif
#define SIZE 65536
#define CHECK(x) do { if (!(x)) { printf("MAPPED WRITEBACK FAIL line=%d errno=%d FAIL END\n", __LINE__, errno); for (;;) pause(); } } while (0)
static atomic_int stopping;
static int private_churn;

static void *sync_worker(void *unused)
{
    (void)unused;
    while (!atomic_load(&stopping)) { sync(); usleep(2000); }
    return NULL;
}

struct heap { long size[16], count[16]; int n; long large; };
static void heap_snapshot(struct heap *h)
{
    FILE *f = fopen("/proc/slabinfo", "r");
    CHECK(f != NULL);
    char line[256];
    memset(h, 0, sizeof(*h));
    while (fgets(line, sizeof(line), f)) {
        long index, size, objects, pages;
        if (sscanf(line, "size-%ld %ld %ld %ld", &index, &size, &objects, &pages) == 4 && h->n < 16) {
            h->size[h->n] = size; h->count[h->n++] = objects;
        } else if (sscanf(line, "large - - %ld", &pages) == 1) { h->large = pages; }
    }
    fclose(f);
    CHECK(h->n > 0);
}

static void churn_one(void)
{
    int fd = open("/root/mapped-churn", O_CREAT | O_TRUNC | O_RDWR, 0600);
    CHECK(fd >= 0 && ftruncate(fd, 16384) == 0);
    volatile unsigned char *p = mmap(NULL, 16384, PROT_READ | PROT_WRITE,
                                    private_churn ? MAP_PRIVATE : MAP_SHARED, fd, 0);
    CHECK(p != MAP_FAILED);
    CHECK(unlink("/root/mapped-churn") == 0);
    CHECK(close(fd) == 0);
    p[17] = 0x71;
    p[16383] = 0x92;
    if (private_churn) {
        unsigned char *moved = mremap((void *)p, 16384, 32768, MREMAP_MAYMOVE);
        CHECK(moved != MAP_FAILED && moved[17] == 0x71 && moved[16383] == 0x92);
        CHECK(munmap(moved, 32768) == 0);
    } else {
        CHECK(munmap((void *)p, 16384) == 0);
    }
}

static void sites(const char *path, int print)
{
    FILE *f = fopen(path, "r");
    if (!f) return;
    char line[1024];
    while (fgets(line, sizeof(line), f)) if (print) printf("PERF-SITE mapped-churn %s", line);
    fclose(f);
}

static void churn(void)
{
    for (int i = 0; i < 32; i++) churn_one();
    sleep(6);
    struct heap before, after;
    churn_one();
    heap_snapshot(&before);
    sites("/proc/allocstart", 0);
    pthread_t worker;
    CHECK(pthread_create(&worker, NULL, sync_worker, NULL) == 0);
    for (int i = 0; i < 500; i++) churn_one();
    atomic_store(&stopping, 1);
    CHECK(pthread_join(worker, NULL) == 0);
    sleep(6);
    churn_one();
    heap_snapshot(&after);
    sites("/proc/allocsites", 1);
    CHECK(before.n == after.n);
    long kept = 0;
    int growing_class = 0;
    for (int i = 0; i < before.n; i++) {
        CHECK(before.size[i] == after.size[i]);
        long delta = after.count[i] - before.count[i];
        printf("MAPPED CHURN size=%ld before=%ld after=%ld kept=%ld\n", before.size[i], before.count[i], after.count[i], delta);
        if (delta > 0) kept += delta * before.size[i];
        if (delta >= 64) growing_class = 1;
    }
    printf("MAPPED CHURN total=%ld large_before=%ld large_after=%ld\n", kept, before.large, after.large);
    CHECK(!growing_class && kept < 65536 && after.large - before.large < 16);
}

#define PRIVATE_SIZE (8 * 1024 * 1024)
static volatile unsigned char *thread_page, *clean_page;
static size_t thread_stride;
static atomic_int writing_done;

static void *private_writer(void *unused)
{
    (void)unused;
    for (size_t i = 0; i < 512 && i * thread_stride < PRIVATE_SIZE; i++)
        atomic_store((_Atomic unsigned char *)&thread_page[i * thread_stride + 17], 0xd4);
    atomic_store(&writing_done, 1);
    return NULL;
}

static void *private_reader(void *unused)
{
    (void)unused;
    do {
        for (size_t i = 0; i < 512 && i * thread_stride < PRIVATE_SIZE; i++) {
            unsigned char before = i ? (unsigned char)((i * thread_stride + 17) * 37 + 11) : 0x82;
            unsigned char value = atomic_load((_Atomic unsigned char *)&thread_page[i * thread_stride + 17]);
            CHECK(value == before || value == 0xd4);
            CHECK(clean_page[i * thread_stride + 17] == before);
        }
    } while (!atomic_load(&writing_done));
    return NULL;
}

static long meminfo_kib(const char *name)
{
    FILE *f = fopen("/proc/meminfo", "r");
    CHECK(f != NULL);
    char line[256]; long value = -1;
    while (fgets(line, sizeof(line), f)) {
        if (!strncmp(line, name, strlen(name)) && sscanf(line + strlen(name), "%ld", &value) == 1) break;
    }
    fclose(f);
    CHECK(value >= 0);
    return value;
}

static long free_kib(void) { return meminfo_kib("MemFree:"); }

static void private_mapping(void)
{
    int fd = open("/root/mapped-private", O_CREAT | O_TRUNC | O_RDWR, 0600);
    CHECK(fd >= 0);
    unsigned char data[SIZE];
    for (size_t i = 0; i < SIZE; i++) data[i] = (unsigned char)(i * 37 + 11);
    for (int i = 0; i < PRIVATE_SIZE / SIZE; i++) CHECK(write(fd, data, SIZE) == SIZE);
    CHECK(fsync(fd) == 0);
    volatile unsigned char *p[8];
    long first = 0;
    for (int map = 0; map < 8; map++) {
        p[map] = mmap(NULL, PRIVATE_SIZE, PROT_READ, MAP_PRIVATE, fd, 0);
        CHECK(p[map] != MAP_FAILED);
        for (size_t i = 0; i < PRIVATE_SIZE; i += 4096) CHECK(p[map][i + 17] == data[17]);
        if (!map) first = free_kib();
    }
    long aliases = free_kib();
    printf("PRIVATE SHARING aliases=7 extent=%d extra_kib=%ld\n", PRIVATE_SIZE, first - aliases);
    CHECK(first - aliases < 2048);
    CHECK(mprotect((void *)p[1], PRIVATE_SIZE, PROT_READ | PROT_WRITE) == 0);
    CHECK(aliases - free_kib() < 1024);
    p[1][17] = 0x74;
    CHECK(p[0][17] == data[17] && p[2][17] == data[17]);
    CHECK(mprotect((void *)p[2], PRIVATE_SIZE, PROT_READ | PROT_WRITE) == 0);
    p[2][17] = 0xa8;
    CHECK(mprotect((void *)p[3], PRIVATE_SIZE, PROT_READ | PROT_WRITE) == 0);
    CHECK(pread(fd, (void *)&p[3][17], 1, 33) == 1);
    CHECK(p[3][17] == data[33] && p[0][17] == data[17]);
    volatile unsigned char *shared = mmap(NULL, SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    CHECK(shared != MAP_FAILED);
    shared[17] = 0x82;
    CHECK(p[0][17] == 0x82 && p[7][17] == 0x82);
    CHECK(p[1][17] == 0x74 && p[2][17] == 0xa8 && p[3][17] == data[33]);
    unsigned char changed = 0x93;
    CHECK(pwrite(fd, &changed, 1, SIZE - 9) == 1);
    CHECK(p[0][SIZE - 9] == 0x93 && p[1][SIZE - 9] == 0x93);

    int pipefd[2];
    CHECK(pipe(pipefd) == 0);
    pid_t child = fork(); CHECK(child >= 0);
    if (!child) {
        close(pipefd[0]);
        p[1][17] = 0xcc;
        CHECK(p[0][17] == 0x82 && p[2][17] == 0xa8);
        CHECK(write(pipefd[1], "k", 1) == 1);
        _exit(0);
    }
    close(pipefd[1]);
    char reply; int status;
    CHECK(read(pipefd[0], &reply, 1) == 1 && reply == 'k');
    CHECK(waitpid(child, &status, 0) == child && WIFEXITED(status) && !WEXITSTATUS(status));
    close(pipefd[0]);
    CHECK(p[1][17] == 0x74 && p[0][17] == 0x82);
    CHECK(madvise((void *)p[1], PRIVATE_SIZE, MADV_DONTNEED) == 0 && p[1][17] == 0x82);

    CHECK(mprotect((void *)p[4], PRIVATE_SIZE, PROT_READ | PROT_WRITE) == 0);
    thread_page = p[4]; clean_page = p[0]; thread_stride = (size_t)sysconf(_SC_PAGESIZE);
    pthread_t reader, writer;
    CHECK(pthread_create(&reader, NULL, private_reader, NULL) == 0);
    CHECK(pthread_create(&writer, NULL, private_writer, NULL) == 0);
    CHECK(pthread_join(writer, NULL) == 0 && pthread_join(reader, NULL) == 0);
    CHECK(p[4][17] == 0xd4 && p[0][17] == 0x82);
    size_t page = (size_t)sysconf(_SC_PAGESIZE);
    volatile unsigned char *locked = mmap(NULL, page, PROT_READ | PROT_WRITE, MAP_PRIVATE, fd, 0);
    CHECK(locked != MAP_FAILED);
    locked[17] = 0x6e;
    CHECK(mlock((void *)locked, page) == 0);
    unsigned char *moved = mremap((void *)locked, page, 2 * page, MREMAP_MAYMOVE);
    CHECK(moved != MAP_FAILED && moved[17] == 0x6e && p[0][17] == 0x82 && shared[17] == 0x82);
    CHECK(madvise(moved, 2 * page, MADV_DONTNEED) == -1 && errno == EINVAL);
    CHECK(munlock(moved, 2 * page) == 0);
    CHECK(madvise(moved, 2 * page, MADV_DONTNEED) == 0 && moved[17] == 0x82);
    CHECK(munmap(moved, 2 * page) == 0);
    puts("PRIVATE REMAP: dirty locked pages preserved, cache isolated, unlock permits reload");
    CHECK(fsync(fd) == 0);
    for (int i = 0; i < 8; i++) CHECK(munmap((void *)p[i], PRIVATE_SIZE) == 0);
    CHECK(munmap((void *)shared, SIZE) == 0 && close(fd) == 0);
    private_churn = 1;
    churn();
}

static void residency(volatile unsigned char *p, size_t length, int expected)
{
    unsigned char vec[64] = {0};
    size_t page = (size_t)sysconf(_SC_PAGESIZE);
    CHECK(length / page <= sizeof(vec));
    CHECK(mincore((void *)p, length, vec) == 0);
    for (size_t i = 0; i < length / page; i++) CHECK((vec[i] & 1) == expected);
}

static void file_pageout(void)
{
    const size_t page = (size_t)sysconf(_SC_PAGESIZE);
    int fd = open("/root/mapped-pageout", O_CREAT | O_TRUNC | O_RDWR, 0600);
    unsigned char expected[SIZE];
    for (size_t i = 0; i < SIZE; i++) expected[i] = (unsigned char)(i * 37 + 11);
    CHECK(fd >= 0 && write(fd, expected, SIZE) == SIZE && fsync(fd) == 0);
    volatile unsigned char *p = mmap(NULL, SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    volatile unsigned char *alias = mmap(NULL, SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    volatile unsigned char *clean = mmap(NULL, SIZE, PROT_READ, MAP_PRIVATE, fd, 0);
    volatile unsigned char *copy = mmap(NULL, SIZE, PROT_READ | PROT_WRITE, MAP_PRIVATE, fd, 0);
    CHECK(p != MAP_FAILED && alias != MAP_FAILED && clean != MAP_FAILED && copy != MAP_FAILED);
    volatile unsigned char *lazy = mmap(NULL, SIZE, PROT_NONE, MAP_SHARED, fd, 0);
    CHECK(lazy != MAP_FAILED);
    for (size_t i = 0; i < SIZE; i += page) {
        CHECK(p[i] == expected[i] && alias[i] == expected[i] && clean[i] == expected[i]);
        copy[i + 31] = 0xce;
    }
    p[17] = 0x71;
    CHECK(msync((void *)p, SIZE, MS_SYNC) == 0);
    CHECK(mprotect((void *)alias, SIZE, PROT_READ) == 0);
    CHECK(mprotect((void *)alias, SIZE, PROT_READ | PROT_WRITE) == 0);
    alias[17] = 0x82;
    // A usercopy write through the physical direct map must dirty the PTE.
    unsigned char value = 0x93;
    int input = open("/root/pageout-input", O_CREAT | O_TRUNC | O_RDWR, 0600);
    CHECK(input >= 0 && write(input, &value, 1) == 1);
    CHECK(pread(input, (void *)&p[SIZE - 9], 1, 0) == 1 && close(input) == 0);
    CHECK(msync((void *)alias, SIZE, MS_SYNC) == 0);
    CHECK(mlock((void *)clean, page) == 0);
    CHECK(madvise((void *)p, SIZE, MADV_PAGEOUT) == 0);
    residency(p, page, 1); // Any locked alias pins the underlying file frame.
    CHECK(munlock((void *)clean, page) == 0);
    CHECK(madvise((void *)p, SIZE, MADV_PAGEOUT) == 0);
    residency(p, SIZE, 0);
    residency(alias, SIZE, 0);
    residency(clean, SIZE, 0);
    for (size_t i = 0; i < SIZE; i += page) CHECK(copy[i + 31] == 0xce);
    CHECK(madvise((void *)copy, SIZE, MADV_PAGEOUT) == 0);
    residency(copy, SIZE, 0);
    for (size_t i = 0; i < SIZE; i += page) CHECK(copy[i + 31] == 0xce);
    CHECK(madvise((void *)copy, SIZE, MADV_PAGEOUT) == 0);
    CHECK(madvise((void *)copy, SIZE, MADV_DONTNEED) == 0);
    CHECK(copy[31] == expected[31]);
    CHECK(p[17] == 0x82 && alias[17] == 0x82 && clean[17] == 0x82);
    CHECK(p[SIZE - 9] == 0x93 && copy[SIZE - 9] == 0x93);
    CHECK(msync((void *)p, SIZE, MS_SYNC) == 0 && fsync(fd) == 0);
    puts("FILE PAGEOUT: shared aliases revoked, locked page pinned, private COW paged and discarded, refault coherent");

    struct heap pageout_before, pageout_after;
    for (int round = 0; round < 232; round++) {
        p[17] = 0x82;
        CHECK(madvise((void *)p, SIZE, MADV_PAGEOUT) == 0 && p[17] == 0x82);
        if (round == 31) heap_snapshot(&pageout_before);
    }
    heap_snapshot(&pageout_after);
    CHECK(pageout_before.n == pageout_after.n);
    long kept = 0;
    for (int i = 0; i < pageout_before.n; i++) {
        long delta = pageout_after.count[i] - pageout_before.count[i];
        printf("FILE PAGEOUT CHURN size=%ld before=%ld after=%ld kept=%ld\n",
               pageout_before.size[i], pageout_before.count[i], pageout_after.count[i], delta);
        CHECK(delta < 32);
        if (delta > 0) kept += delta * pageout_before.size[i];
    }
    CHECK(kept < 8192 && pageout_after.large - pageout_before.large < 4);
    puts("FILE PAGEOUT: 200 refault/write/pageout operations retain bounded heap");

    // Final unmap must retain writes even after unlink and close. Truncation
    // zeroes cached bytes so pageout cannot put stale tail data back on disk.
    int temporary = open("/root/pageout-truncate", O_CREAT | O_TRUNC | O_RDWR, 0600);
    CHECK(temporary >= 0 && ftruncate(temporary, 2 * page) == 0);
    volatile unsigned char *tail = mmap(NULL, 2 * page, PROT_READ | PROT_WRITE, MAP_SHARED, temporary, 0);
    CHECK(tail != MAP_FAILED);
    tail[page + 17] = 0xa5;
    CHECK(ftruncate(temporary, page + 1) == 0);
    CHECK(ftruncate(temporary, 2 * page) == 0 && tail[page + 17] == 0);
    tail[17] = 0x62;
    CHECK(madvise((void *)tail, 2 * page, MADV_PAGEOUT) == 0 && tail[17] == 0x62);
    CHECK(unlink("/root/pageout-truncate") == 0 && close(temporary) == 0);
    tail[17] = 0x73;
    CHECK(munmap((void *)tail, 2 * page) == 0);
    for (int i = 0; i < 4; i++) {
        volatile unsigned char *map = i == 0 ? p : i == 1 ? alias : i == 2 ? clean : copy;
        CHECK(munmap((void *)map, SIZE) == 0);
    }
    CHECK(munmap((void *)lazy, SIZE) == 0 && close(fd) == 0);
    puts("FILE PAGEOUT: truncate/regrow and unlinked final unmap preserved");
}

static void file_pressure(void)
{
    const size_t length = 8 * 1024 * 1024;
    const size_t page = (size_t)sysconf(_SC_PAGESIZE);
    int fd = open("/root/mapped-pressure", O_CREAT | O_TRUNC | O_RDWR, 0600);
    unsigned char expected[SIZE];
    for (size_t i = 0; i < SIZE; i++) expected[i] = (unsigned char)(i * 37 + 11);
    CHECK(fd >= 0);
    for (size_t i = 0; i < length; i += SIZE) CHECK(write(fd, expected, SIZE) == SIZE);
    CHECK(fsync(fd) == 0);
    puts("FILE PRESSURE: seeded 8 MiB file");
    volatile unsigned char *p = mmap(NULL, length, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    CHECK(p != MAP_FAILED);
    for (size_t i = 0; i < length; i += page) CHECK(p[i + 17] == expected[17]);
    puts("FILE PRESSURE: populated file pages");
    p[17] = 0x82;
    p[SIZE - 9] = 0x93;
    // Exceed free RAM and reclaimable block-cache space, while remaining
    // within the bounded compression pool without requiring a swap disk.
    size_t extent = ((size_t)free_kib() + (size_t)meminfo_kib("Cached:")) * 1024 + 24 * 1024 * 1024;
    extent = extent / page * page;
    printf("FILE PRESSURE allocation=%zu MiB ram=%d MiB\n", extent / (1024 * 1024), VINIX_TEST_MEMORY_MIB);
    volatile unsigned char *anonymous = mmap(NULL, extent, PROT_READ | PROT_WRITE,
                                           MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    CHECK(anonymous != MAP_FAILED);
    puts("FILE PRESSURE: anonymous mapping created");
    for (size_t i = 0; i < extent; i += page) {
        anonymous[i] = 0x46;
        anonymous[i + page - 1] = 0x57;
        if ((i + page) % (32 * 1024 * 1024) == 0) printf("FILE PRESSURE touched=%zu MiB\n", (i + page) / (1024 * 1024));
    }
    unsigned char *vec = calloc(length / page, 1);
    CHECK(vec != NULL && mincore((void *)p, length, vec) == 0);
    size_t missing = 0;
    for (size_t i = 0; i < length / page; i++) missing += !(vec[i] & 1);
    printf("FILE PRESSURE missing=%zu total=%zu\n", missing, length / page);
    CHECK(missing > 0);
    CHECK(p[17] == 0x82 && p[SIZE - 9] == 0x93);
    for (size_t i = 0; i < length; i += page) CHECK(p[i + 31] == expected[31]);
    for (size_t i = 0; i < extent; i += page) CHECK(anonymous[i] == 0x46 && anonymous[i + page - 1] == 0x57);
    CHECK(msync((void *)p, length, MS_SYNC) == 0 && fsync(fd) == 0);
    CHECK(munmap((void *)anonymous, extent) == 0);
    free(vec);
    puts("FILE PRESSURE: automatic file eviction and dirty refault passed beside pressure-sized anonymous memory");
}

int main(void)
{
    setbuf(stdout, NULL);
#ifdef __x86_64__
    int console = open("/dev/com1", O_WRONLY);
    CHECK(console >= 0 && dup2(console, 1) == 1 && dup2(console, 2) == 2);
    close(console);
#endif
    struct statfs fs;
    CHECK(statfs("/root", &fs) == 0 && fs.f_type == 0xef53);
    struct stat st;
    CHECK(stat("/root/many/f1199", &st) == 0 && st.st_size == 0);
    char step[32] = {0};
    int config = open("/no-sync-step", O_RDONLY);
    CHECK(config >= 0 && read(config, step, sizeof(step) - 1) > 0);
    close(config);
    step[strcspn(step, "\n")] = 0;
    printf("MAPPED WRITEBACK START %s\n", step);
    if (!strcmp(step, "churn")) {
        churn();
    } else if (!strcmp(step, "private")) {
        private_mapping();
    } else if (!strcmp(step, "pageout")) {
        file_pageout();
    } else if (!strcmp(step, "pressure")) {
        file_pressure();
    } else {
        char path[96];
        snprintf(path, sizeof(path), "/root/mapped-%s", step);
        int fd = open(path, O_CREAT | O_TRUNC | O_RDWR, 0600);
        CHECK(fd >= 0);
        unsigned char expected[SIZE];
        for (size_t i = 0; i < SIZE; i++) expected[i] = (unsigned char)(i * 37 + 11);
        CHECK(write(fd, expected, SIZE) == SIZE && fsync(fd) == 0);
        volatile unsigned char *p = mmap(NULL, SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
        CHECK(p != MAP_FAILED);
        CHECK(p[17] == expected[17]);
        p[17] = 0x71;
        if (!strcmp(step, "background")) {
            sleep(6);
            // A later write must be collected by the next background pass.
            p[17] = 0x82;
            p[SIZE - 9] = 0x93;
            sleep(6);
        } else if (!strcmp(step, "sync") || !strcmp(step, "syncfs")) {
            CHECK(syscall(!strcmp(step, "sync") ? SYS_sync : SYS_syncfs, fd) == 0);
            p[17] = 0x82;
            p[SIZE - 9] = 0x93;
            CHECK(syscall(!strcmp(step, "sync") ? SYS_sync : SYS_syncfs, fd) == 0);
        } else { CHECK(0); }
        // Both the fd and live mapping stay open. No close, msync or unmap
        // may hide a broken global/background writeback before the power cut.
        CHECK(p[17] == 0x82 && p[SIZE - 9] == 0x93);
    }
    printf("MAPPED WRITEBACK DONE %s ino=0\n", step);
    for (;;) pause();
}

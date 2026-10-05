// SPDX-License-Identifier: GPL-2.0-or-later
// Run with the actual private Android musl loader and compatibility library.
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <malloc.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

#include "musl-statistics.h"
// A weak declaration lets the host cross-compiler link the fixture against
// its stock headers. The private loader must resolve the real definition.
extern int __vinix_malloc_stats(struct vinix_malloc_stats *, size_t) __attribute__((weak));
// An extra native source fixture links the private donate.o directly to
// exercise this hidden loader hook; the production DSO keeps it hidden.
extern void __malloc_donate(char *, char *) __attribute__((weak));

struct android_mallinfo {
    size_t arena, ordblks, smblks, hblks, hblkhd;
    size_t usmblks, fsmblks, uordblks, fordblks, keepcost;
};
static struct android_mallinfo (*android_mallinfo)(void);
static int (*trim_heap)(size_t);
static pthread_barrier_t wave;
static _Atomic int churn_done;
static char donation_area[65536] __attribute__((aligned(65536)));
#define THREADS 6
#define BLOCKS 12
#define LARGE (3UL * 1024 * 1024)

static void require(int condition, const char *reason)
{
    if (!condition) {
        fprintf(stderr, "ANDROID-MALLINFO-FAIL %s errno=%d\n", reason, errno);
        exit(1);
    }
}

static struct vinix_malloc_stats snapshot(void)
{
    struct vinix_malloc_stats stats;
    require(__vinix_malloc_stats != NULL, "private allocator statistics export");
    errno = EDOM;
    require(__vinix_malloc_stats(&stats, sizeof(stats)) == 0 && errno == EDOM,
            "snapshot preserves errno");
    require(stats.peak_mapped_bytes >= stats.mapped_bytes
            && stats.peak_live_bytes >= stats.live_bytes
            && stats.live_bytes <= stats.mapped_bytes
            && stats.free_bytes <= stats.mapped_bytes - stats.live_bytes,
            "snapshot footprint and high-water invariants");
    require((stats.mapped_bytes == 0) == (stats.mapped_blocks == 0)
            && (stats.free_bytes == 0) == (stats.free_blocks == 0), "snapshot block counts");
    return stats;
}

static void require_payload(struct vinix_malloc_stats before, size_t bytes, size_t blocks)
{
    struct vinix_malloc_stats after = snapshot();
    require(after.live_bytes == before.live_bytes + bytes
            && after.live_blocks == before.live_blocks + blocks, "exact live payload accounting");
}

static void check_startup_groups(void)
{
    // These payloads select exactly the classes used by ELF-gap donation.
    // Check them before dlopen/stdio creates ordinary groups that could hide
    // an unaccounted donated slot inside a larger aggregate free counter.
    const size_t sizes[] = {60, 124, 236, 492, 1004, 2028, 4076, 8172, 16364, 32748, 65516};
    for (unsigned index = 0; index < sizeof(sizes)/sizeof(sizes[0]); ++index) {
        struct vinix_malloc_stats before = snapshot();
        void *p = malloc(sizes[index]);
        require(p != NULL, "initial donor-class allocation");
        require_payload(before, sizes[index], 1);
        free(p);
        require_payload(before, 0, 0);
    }
    if (__malloc_donate != NULL) {
        memset(donation_area, 0x67, sizeof(donation_area));
        struct vinix_malloc_stats before = snapshot();
        __malloc_donate(donation_area, donation_area + sizeof(donation_area));
        struct vinix_malloc_stats after = snapshot();
        require(memcmp(&before, &after, sizeof(before)) == 0,
                "private allocator declines borrowed ELF backing");
        for (size_t index = 0; index < sizeof(donation_area); ++index)
            require(donation_area[index] == 0x67, "declined donation preserves image bytes");
    }
    FILE *maps = fopen("/proc/self/maps", "r");
    require(maps != NULL, "open startup mappings");
    char *line = NULL;
    size_t capacity = 0;
    require(getline(&line, &capacity, maps) > 0, "read startup mappings");
    free(line);
    require(fclose(maps) == 0, "close startup mappings");
    snapshot();
}

static size_t wave_size(unsigned thread, unsigned block)
{
    return (thread + 1) * (block + 1) * 103;
}

static void barrier(void)
{
    int result = pthread_barrier_wait(&wave);
    require(result == 0 || result == PTHREAD_BARRIER_SERIAL_THREAD, "thread barrier");
}

static void *worker(void *argument)
{
    unsigned thread = (unsigned)(uintptr_t)argument;
    void *blocks[BLOCKS];
    barrier();
    barrier();
    for (unsigned block = 0; block < BLOCKS; ++block) {
        size_t size = wave_size(thread, block);
        blocks[block] = malloc(size);
        require(blocks[block] != NULL, "thread wave allocation");
        memset(blocks[block], (int)thread, size);
    }
    barrier();
    barrier();
    for (unsigned block = 0; block < BLOCKS; ++block) free(blocks[block]);
    barrier();
    barrier();
    for (unsigned iteration = 0; iteration < 400; ++iteration) {
        size_t size = 1 + (iteration * 997 + thread * 331) % 300000;
        unsigned char *p = malloc(size);
        require(p != NULL, "concurrent allocation");
        memset(p, (int)thread, size);
        p = realloc(p, size + 71);
        require(p != NULL && p[0] == thread && p[size-1] == thread, "concurrent realloc data");
        free(p);
    }
    atomic_fetch_add(&churn_done, 1);
    return NULL;
}

static void check_threads_and_fork(void)
{
    require(pthread_barrier_init(&wave, NULL, THREADS + 1) == 0, "initialize barrier");
    pthread_t threads[THREADS];
    for (unsigned thread = 0; thread < THREADS; ++thread) {
        require(pthread_create(&threads[thread], NULL, worker, (void *)(uintptr_t)thread) == 0,
                "create allocation thread");
    }
    barrier();
    struct vinix_malloc_stats baseline = snapshot();
    barrier();
    barrier();
    size_t payload = 0;
    for (unsigned thread = 0; thread < THREADS; ++thread)
        for (unsigned block = 0; block < BLOCKS; ++block) payload += wave_size(thread, block);
    require_payload(baseline, payload, THREADS * BLOCKS);
    barrier();
    barrier();
    require_payload(baseline, 0, 0);
    barrier();

    // Fork while the other threads allocate, resize and free. musl's own
    // allocator atfork lock must leave the child's copied counters usable.
    pid_t child = fork();
    require(child >= 0, "fork during allocations");
    if (child == 0) {
        alarm(5);
        struct vinix_malloc_stats before = snapshot();
        void *p = malloc(17001);
        require(p != NULL, "child allocation");
        require_payload(before, 17001, 1);
        free(p);
        require_payload(before, 0, 0);
        _exit(0);
    }
    while (atomic_load(&churn_done) < THREADS) snapshot();
    int status;
    require(waitpid(child, &status, 0) == child && WIFEXITED(status) && WEXITSTATUS(status) == 0,
            "child statistics after concurrent fork");
    for (unsigned thread = 0; thread < THREADS; ++thread)
        require(pthread_join(threads[thread], NULL) == 0, "join allocation thread");
    require(pthread_barrier_destroy(&wave) == 0, "destroy barrier");
    snapshot();
}

int main(int argc, char **argv)
{
    alarm(60);
    // Exercise the first large allocation before dlsym, dlopen or stdio.
    void *first = malloc(LARGE);
    require(first != NULL, "initial direct mapping");
    struct vinix_malloc_stats initial = snapshot();
    require(initial.live_bytes >= LARGE && initial.mapped_bytes >= LARGE,
            "first allocation records real footprint");
    free(first);
    snapshot();
    check_startup_groups();
    require(argc <= 2, "usage: mallinfo-test [compat.so]");
    if (argc == 2) require(dlopen(argv[1], RTLD_NOW | RTLD_GLOBAL) != NULL, "load Bionic facade");
    android_mallinfo = dlsym(RTLD_DEFAULT, "bionic_mallinfo");
    trim_heap = dlsym(RTLD_DEFAULT, "malloc_trim");
    require(android_mallinfo != NULL && trim_heap != NULL, "Bionic statistics and trim exports");

    struct vinix_malloc_stats invalid;
    errno = 0;
    require(__vinix_malloc_stats(NULL, sizeof(invalid)) == -1 && errno == EINVAL, "reject null snapshot");
    errno = 0;
    require(__vinix_malloc_stats(&invalid, sizeof(invalid)-1) == -1 && errno == EINVAL,
            "reject incompatible snapshot size");
    struct vinix_malloc_stats baseline = snapshot();
    unsigned char *p = malloc(4000);
    require(p != NULL, "small allocation");
    memset(p, 0x59, 4000);
    require_payload(baseline, 4000, 1);
    unsigned char *resized = realloc(p, 3999);
    require(resized == p && resized[3998] == 0x59, "in-place realloc");
    require_payload(baseline, 3999, 1);
    volatile size_t impossible = SIZE_MAX;
    void *(*volatile resize_checked)(void *, size_t) = realloc;
    struct vinix_malloc_stats before_failure = snapshot();
    errno = 0;
    require(resize_checked(resized, impossible) == NULL && errno == ENOMEM && resized[3998] == 0x59,
            "failed realloc preserves allocation");
    require_payload(baseline, 3999, 1);
    struct vinix_malloc_stats after_failure = snapshot();
    require(memcmp(&before_failure, &after_failure, sizeof(before_failure)) == 0,
            "failed realloc leaves every counter unchanged");
    free(resized);
    require_payload(baseline, 0, 0);

    baseline = snapshot();
    p = malloc(LARGE);
    require(p != NULL, "large allocation");
    p[0] = 0x62;
    p[LARGE-1] = 0x63;
    require_payload(baseline, LARGE, 1);
    struct vinix_malloc_stats large = snapshot();
    size_t page_size = (size_t)getpagesize();
    size_t expected_mapping = (LARGE + 20 + page_size - 1) & -page_size;
    require(large.mapped_blocks == baseline.mapped_blocks + 1
            && large.mapped_bytes == baseline.mapped_bytes + expected_mapping, "large mapping accounting");
    p = realloc(p, LARGE * 2);
    require(p != NULL && p[0] == 0x62 && p[LARGE-1] == 0x63, "large mremap data");
    require_payload(baseline, LARGE * 2, 1);
    struct vinix_malloc_stats grown = snapshot();
    require(grown.mapped_blocks == large.mapped_blocks
            && grown.mapped_bytes >= large.mapped_bytes + LARGE, "large mapping growth");
    p = realloc(p, LARGE);
    require(p != NULL && p[0] == 0x62 && p[LARGE-1] == 0x63, "large mremap shrink");
    require_payload(baseline, LARGE, 1);
    require(snapshot().peak_mapped_bytes >= grown.peak_mapped_bytes, "mapping peak survives shrink");
    free(p);
    require_payload(baseline, 0, 0);
    require(snapshot().mapped_bytes == baseline.mapped_bytes, "uncached mapping released");

    baseline = snapshot();
    p = calloc(17, 31);
    require(p != NULL, "calloc");
    for (unsigned index = 0; index < 17*31; ++index) require(p[index] == 0, "calloc zero bytes");
    require_payload(baseline, 17*31, 1);
    free(p);
    before_failure = snapshot();
    errno = 0;
    require(calloc(impossible, 2) == NULL && errno == ENOMEM, "calloc multiplication overflow");
    after_failure = snapshot();
    require(memcmp(&before_failure, &after_failure, sizeof(before_failure)) == 0,
            "calloc overflow leaves every counter unchanged");
    require_payload(baseline, 0, 0);
    const size_t alignments[] = { 16, 64, 4096, 65536, 2097152 };
    for (unsigned index = 0; index < sizeof(alignments)/sizeof(alignments[0]); ++index) {
        void *aligned = NULL;
        require(posix_memalign(&aligned, alignments[index], 129) == 0
                && (uintptr_t)aligned % alignments[index] == 0, "aligned allocation");
        memset(aligned, 0x71, 129);
        require_payload(baseline, 129, 1);
        free(aligned);
        require_payload(baseline, 0, 0);
    }
    errno = 0;
    require(memalign(3, 128) == NULL && errno == EINVAL, "invalid alignment");
    require_payload(baseline, 0, 0);

    trim_heap(0);
    baseline = snapshot();
    p = malloc(200000);
    require(p != NULL, "cache allocation");
    struct vinix_malloc_stats occupied = snapshot();
    free(p);
    struct vinix_malloc_stats cached = snapshot();
    require_payload(baseline, 0, 0);
    require(cached.mapped_bytes == occupied.mapped_bytes
            && cached.free_bytes > occupied.free_bytes && cached.free_blocks > occupied.free_blocks,
            "cached mapping is genuinely reusable");
    p = malloc(180000);
    require(p != NULL, "reuse cached mapping");
    struct vinix_malloc_stats reused = snapshot();
    require(reused.mapped_bytes == cached.mapped_bytes && reused.free_bytes < cached.free_bytes,
            "cache reuse updates free statistics");
    free(p);
    p = malloc(240000);
    require(p != NULL, "replace cached mapping");
    free(p);
    struct vinix_malloc_stats replaced = snapshot();
    require(replaced.mapped_blocks == baseline.mapped_blocks + 1, "cache eviction mapping count");
    trim_heap(0);
    struct vinix_malloc_stats trimmed = snapshot();
    require(trimmed.mapped_bytes < replaced.mapped_bytes && trimmed.free_bytes < replaced.free_bytes
            && trimmed.peak_mapped_bytes >= replaced.peak_mapped_bytes, "trim preserves peak and releases cache");
    require_payload(baseline, 0, 0);

    check_threads_and_fork();
    baseline = snapshot();
    for (unsigned iteration = 0; iteration < 400; ++iteration) {
        size_t size = 1 + iteration * 743 % 500000;
        p = malloc(size);
        require(p != NULL, "churn allocation");
        memset(p, 0x45, size);
        p = realloc(p, size + 1);
        require(p != NULL && p[0] == 0x45, "churn resize");
        free(p);
    }
    require_payload(baseline, 0, 0);
    struct vinix_malloc_stats real = snapshot();
    errno = ENOTTY;
    struct android_mallinfo android = android_mallinfo();
    require(errno == ENOTTY && sizeof(android) == 80, "Bionic return ABI and errno");
    require(android.hblkhd == real.mapped_bytes && android.usmblks == real.peak_mapped_bytes
            && android.uordblks == real.live_bytes && android.fordblks == real.free_bytes
            && android.ordblks == real.free_blocks && android.hblks == real.mapped_blocks,
            "Bionic fields use real allocator counters");
    require(android.arena == 0 && android.smblks == 0 && android.fsmblks == 0 && android.keepcost == 0,
            "Bionic unused and separate-metadata fields");
    puts("ANDROID-MALLINFO-PASS payload=exact mappings=verified aligned=verified threads=verified fork=verified churn=verified bionic=verified");
    return 0;
}

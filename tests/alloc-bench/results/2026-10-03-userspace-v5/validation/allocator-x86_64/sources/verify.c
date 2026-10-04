#define _GNU_SOURCE
#include <errno.h>
#include <inttypes.h>
#include <malloc.h>
#include <pthread.h>
#include <signal.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>
#include <sys/wait.h>
#include <unistd.h>

extern int malloc_trim(size_t);

/* Compile against the staged Vinix libc. Nothing interposes malloc here. */
static const size_t sizes[] = {0, 1, 15, 16, 17, 31, 32, 48, 64, 96, 128,
    256, 512, 1024, 2048, 4096, 8192, 16384, 32768, 65536, 131051, 131052,
    131053, 200000, 262144, 400000, 800000, 1600000, 2097152, 2200000};
static unsigned checks;
static atomic_int worker_failed;
static atomic_int worker_stop;

#define REQUIRE(condition) do { ++checks; if (!(condition)) { \
    fprintf(stderr, "UALLOC-FAIL line=%d check=%s errno=%d\n", \
            __LINE__, #condition, errno); return 1; } } while (0)

static int has_byte(const unsigned char *p, size_t n, unsigned char value)
{
    for (size_t i = 0; i < n; ++i) if (p[i] != value) return 0;
    return 1;
}

static uint64_t mapped_bytes(void)
{
    FILE *stream = fopen("/proc/self/maps", "r");
    if (!stream) return 0;
    char line[1024];
    uint64_t sum = 0;
    unsigned long begin, end;
    while (fgets(line, sizeof line, stream))
        if (sscanf(line, "%lx-%lx", &begin, &end) == 2 && end >= begin)
            sum += end - begin;
    fclose(stream);
    return sum;
}

static int sizes_and_resize(void)
{
    for (unsigned round = 0; round < 3; ++round) {
        for (size_t i = 0; i < sizeof sizes / sizeof sizes[0]; ++i) {
            size_t n = sizes[i];
            unsigned char *p = malloc(n);
            REQUIRE(p && !((uintptr_t)p & 15));
            memset(p, 0x35 + round, n);
            REQUIRE(has_byte(p, n, (unsigned char)(0x35 + round)));
            errno = EDOM;
            free(p);
            REQUIRE(errno == EDOM);
            p = calloc(1, n);
            REQUIRE(p && has_byte(p, n, 0));
            memset(p, 0xa7, n);
            size_t larger = n + n / 2 + 97;
            unsigned char *q = realloc(p, larger);
            REQUIRE(q && has_byte(q, n, 0xa7));
            memset(q, 0x51, larger);
            size_t smaller = n / 3 + 1;
            p = realloc(q, smaller);
            REQUIRE(p && has_byte(p, smaller, 0x51));
            free(p);
        }
    }
    volatile size_t enormous = SIZE_MAX;
    errno = 0;
    REQUIRE(!calloc(enormous, 2) && errno == ENOMEM);
    unsigned char *p = malloc(31);
    REQUIRE(p);
    memset(p, 0x82, 31);
    REQUIRE(!realloc(p, enormous) && has_byte(p, 31, 0x82));
    free(p);
    p = realloc(NULL, 73);
    REQUIRE(p);
    free(p);
    free(NULL);
    return 0;
}

static int growing_cache_bucket(void)
{
    (void)malloc_trim(0);
    unsigned char *small = malloc(270000);  /* Both fit the 512 KiB bucket. */
    unsigned char *large = malloc(490000);
    REQUIRE(small && large);
    memset(small, 0x8e, 270000);
    memset(large, 0x63, 490000);
    free(small);
    free(large);  /* The larger free map must replace the smaller one. */
    for (unsigned i = 0; i < 30; ++i) {
        size_t n = 280000 + (i * 7919U) % 200000;
        unsigned char *p = calloc(1, n);
        REQUIRE(p && has_byte(p, n, 0));
        memset(p, 0x91, n);
        unsigned char *q = realloc(p, n + 31);
        REQUIRE(q && has_byte(q, n, 0x91));
        free(q);
    }
    (void)malloc_trim(0);
    return 0;
}

static int aligned_sizes(void)
{
    for (size_t alignment = 16; alignment <= 2097152; alignment <<= 1) {
        for (unsigned round = 0; round < 3; ++round) {
            size_t n = alignment + 119;
            void *p = NULL;
            REQUIRE(!posix_memalign(&p, alignment, n));
            REQUIRE(p && !((uintptr_t)p & (alignment - 1)));
            memset(p, 0xd3, n);
            void *q = realloc(p, n + 713);
            REQUIRE(q && has_byte(q, n, 0xd3));
            free(q);
            p = aligned_alloc(alignment, alignment);
            REQUIRE(p && !((uintptr_t)p & (alignment - 1)));
            memset(p, 0x37, alignment);
            free(p);
        }
    }
    return 0;
}

static int batches_and_trim(void)
{
    unsigned char *live[96];
    for (size_t i = 0; i < 96; ++i) {
        live[i] = malloc(sizes[i % 30]);
        REQUIRE(live[i]);
        memset(live[i], (int)i, sizes[i % 30]);
    }
    for (size_t i = 0; i < 96; ++i) {
        size_t j = (i * 37) % 96;
        if (j & 1) { free(live[j]); live[j] = NULL; }
    }
    errno = EOVERFLOW;
    (void)malloc_trim(0);
    REQUIRE(errno == EOVERFLOW);
    for (size_t i = 0; i < 96; ++i) if (live[i]) {
        REQUIRE(has_byte(live[i], sizes[i % 30], (unsigned char)i));
        free(live[i]);
    }
    (void)mapped_bytes();  /* Warm stdio allocations before the footprint check. */
    (void)malloc_trim(0);
    uint64_t before = mapped_bytes();
    for (unsigned round = 0; round < 30; ++round) {
        for (size_t i = 0; i < 30; ++i) {
            unsigned char *p = malloc(sizes[i]);
            REQUIRE(p);
            memset(p, 0x95, sizes[i]);
            free(p);
        }
    }
    uint64_t retained = mapped_bytes();
    REQUIRE(!before || !retained || retained <= before + 12U*1024U*1024U);
    errno = ERANGE;
    (void)malloc_trim(0);
    REQUIRE(errno == ERANGE);
    uint64_t trimmed = mapped_bytes();
    REQUIRE(!before || !trimmed || trimmed <= before + 128U*1024U);
    printf("UALLOC-FOOTPRINT before=%" PRIu64 " retained=%" PRIu64
           " trimmed=%" PRIu64 "\n", before, retained, trimmed);
    return 0;
}

static void *worker(void *argument)
{
    uintptr_t id = (uintptr_t)argument;
    for (unsigned round = 0; round < 100 || !atomic_load(&worker_stop); ++round) {
        size_t n = sizes[(round + id * 7) % 30];
        unsigned char *p = malloc(n);
        if (!p) { atomic_store(&worker_failed, 1); return NULL; }
        memset(p, (int)(id + 13), n);
        if (!has_byte(p, n, (unsigned char)(id + 13))) atomic_store(&worker_failed, 1);
        free(p);
        if ((round & 15) == 0) (void)malloc_trim(0);
    }
    size_t transfer_size = 79 + id * 64;
    unsigned char *transfer = malloc(transfer_size);
    if (!transfer) atomic_store(&worker_failed, 1);
    else memset(transfer, (int)(id + 27), transfer_size);
    return transfer;
}

static int threaded_fork(void)
{
    pthread_t threads[4];
    for (uintptr_t i = 0; i < 4; ++i) REQUIRE(!pthread_create(&threads[i], NULL, worker, (void *)i));
    for (unsigned trial = 0; trial < 8; ++trial) {
        pid_t child = fork();
        REQUIRE(child >= 0);
        if (!child) {
            alarm(20);
            for (unsigned i = 0; i < 30; ++i) {
                unsigned char *p = calloc(1, sizes[i]);
                if (!p || !has_byte(p, sizes[i], 0)) _exit(1);
                memset(p, 0xc7, sizes[i]);
                free(p);
            }
            (void)malloc_trim(0);
            _exit(0);
        }
        int status;
        REQUIRE(waitpid(child, &status, 0) == child && WIFEXITED(status) && !WEXITSTATUS(status));
    }
    atomic_store(&worker_stop, 1);
    for (unsigned i = 0; i < 4; ++i) {
        void *transfer = NULL;
        REQUIRE(!pthread_join(threads[i], &transfer));
        REQUIRE(transfer && has_byte(transfer, 79 + i * 64, (unsigned char)(i + 27)));
        free(transfer);  /* Explicit cross-thread ownership transfer. */
    }
    REQUIRE(!atomic_load(&worker_failed));
    return 0;
}

static int rejects_corruption(void)
{
    for (unsigned test = 0; test < 4; ++test) {
        pid_t child = fork();
        REQUIRE(child >= 0);
        if (!child) {
            struct rlimit limit = {0, 0};
            (void)setrlimit(RLIMIT_CORE, &limit);
            size_t n = test & 1 ? 262144 : 64;
            unsigned char *p = malloc(n);
            if (!p) _exit(2);
            void (*volatile release)(void *) = free;
            if (test < 2) { release(p); release(p); }
            else { ((volatile unsigned char *)p)[n] = 0x81; release(p); }
            _exit(3);
        }
        int status;
        REQUIRE(waitpid(child, &status, 0) == child);
        printf("UALLOC-CORRUPTION test=%u status=%d signal=%d exit=%d\n", test, status,
            WIFSIGNALED(status) ? WTERMSIG(status) : 0,
            WIFEXITED(status) ? WEXITSTATUS(status) : -1);
        /* Vinix reports AArch64 BRK as SIGTRAP; x86 UD2 reports SIGILL. */
        REQUIRE(WIFSIGNALED(status) && (WTERMSIG(status) == SIGSEGV ||
            WTERMSIG(status) == SIGILL || WTERMSIG(status) == SIGABRT
#if defined(__aarch64__)
            || WTERMSIG(status) == SIGTRAP
#endif
        ));
    }
    return 0;
}

int main(void)
{
    alarm(180);
    if (sizes_and_resize() || growing_cache_bucket() || aligned_sizes() || batches_and_trim() || threaded_fork() || rejects_corruption()) return 1;
    (void)malloc_trim(0);
    printf("UALLOC-DONE checks=%u\n", checks);
    return 0;
}

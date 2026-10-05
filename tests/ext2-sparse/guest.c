#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/statfs.h>
#include <time.h>
#include <unistd.h>

#define CHECK(x) do { if (!(x)) { printf("EXT2 SPARSE FAIL line=%d errno=%d FAIL END\n", __LINE__, errno); for (;;) pause(); } } while (0)
static uint64_t block_size, capacity, positions[9];
static const unsigned char bytes[3] = {0x71, 0x92, 0x53};
static const unsigned char crossing[16] = {1, 3, 5, 7, 9, 11, 13, 15, 2, 4, 6, 8, 10, 12, 14, 16};

static uint64_t free_blocks(void)
{
    struct statfs fs;
    CHECK(statfs("/root", &fs) == 0 && fs.f_type == 0xef53);
    return fs.f_bfree;
}

static void check_file(int fd, uint64_t size)
{
    struct stat st;
    CHECK(fstat(fd, &st) == 0 && (uint64_t)st.st_size == size && st.st_blocks < 64 * (int64_t)(block_size / 512));
    unsigned char observed[64];
    for (size_t i = 0; i < sizeof positions / sizeof positions[0]; i++) {
        uint64_t offset = positions[i] * block_size + 17;
        if (offset + 3 > size) continue;
        CHECK(pread(fd, observed, 20, (off_t)(offset - 17)) == 20);
        for (int j = 0; j < 17; j++) CHECK(observed[j] == 0);
        CHECK(!memcmp(observed + 17, bytes, 3));
    }
    CHECK(pread(fd, observed, sizeof observed, (off_t)(3 * block_size)) == sizeof observed);
    for (size_t i = 0; i < sizeof observed; i++) CHECK(observed[i] == 0);
    if (size > (UINT64_C(1) << 32)) {
        CHECK(pread(fd, observed, sizeof crossing, (off_t)((UINT64_C(1) << 32) - 8)) == sizeof crossing);
        CHECK(!memcmp(observed, crossing, sizeof crossing));
    }
    printf("EXT2 SPARSE size=%llu sectors=%lld block=%llu\n", (unsigned long long)size,
           (long long)st.st_blocks, (unsigned long long)block_size);
}

static void shrink_tail(void)
{
    int fd = open("/root/sparse-tail", O_CREAT | O_TRUNC | O_RDWR, 0600);
    CHECK(fd >= 0);
    unsigned char data[64]; memset(data, 0xcc, sizeof data);
    CHECK(write(fd, data, sizeof data) == sizeof data);
    size_t page = (size_t)sysconf(_SC_PAGESIZE);
    volatile unsigned char *shared = mmap(NULL, page, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    volatile unsigned char *private = mmap(NULL, page, PROT_READ | PROT_WRITE, MAP_PRIVATE, fd, 0);
    CHECK(shared != MAP_FAILED && private != MAP_FAILED);
    private[18] = 0xee;
    CHECK(ftruncate(fd, 17) == 0);
    shared[18] = 0x77;
    CHECK(ftruncate(fd, 64) == 0);
    CHECK(pread(fd, data, sizeof data, 0) == sizeof data);
    for (int i = 0; i < 64; i++) CHECK(data[i] == (i < 17 ? 0xcc : 0));
    CHECK(shared[18] == 0 && private[18] == 0xee);
    CHECK(munmap((void *)shared, page) == 0 && munmap((void *)private, page) == 0);
    CHECK(unlink("/root/sparse-tail") == 0 && close(fd) == 0);
}

struct heap { long size[16], count[16], large; int n; };
static void snapshot(struct heap *h)
{
    memset(h, 0, sizeof(*h));
    FILE *f = fopen("/proc/slabinfo", "r"); CHECK(f != NULL);
    char line[256];
    while (fgets(line, sizeof line, f)) {
        long index, size, objects, pages;
        if (sscanf(line, "size-%ld %ld %ld %ld", &index, &size, &objects, &pages) == 4 && h->n < 16) {
            h->size[h->n] = size; h->count[h->n++] = objects;
        } else if (sscanf(line, "large - - %ld", &pages) == 1) h->large = pages;
    }
    fclose(f); CHECK(h->n > 0);
}

static void cycle(int fd)
{
    CHECK(ftruncate(fd, (off_t)capacity) == 0);
    CHECK(pwrite(fd, bytes, sizeof bytes, (off_t)(capacity - block_size + 17)) == sizeof bytes);
    CHECK(ftruncate(fd, 0) == 0);
}

static void churn(void)
{
    int fd = open("/root/sparse-churn", O_CREAT | O_TRUNC | O_RDWR, 0600);
    CHECK(fd >= 0);
    uint64_t available = free_blocks();
    for (int i = 0; i < 32; i++) cycle(fd);
    sleep(6);
    struct heap before, after;
    snapshot(&before);
    struct timespec start, end;
    CHECK(clock_gettime(CLOCK_MONOTONIC, &start) == 0);
    for (int i = 0; i < 500; i++) cycle(fd);
    CHECK(clock_gettime(CLOCK_MONOTONIC, &end) == 0);
    sleep(6);
    snapshot(&after);
    CHECK(before.n == after.n && after.large - before.large < 16);
    long kept = 0;
    for (int i = 0; i < before.n; i++) {
        long delta = after.count[i] - before.count[i];
        printf("EXT2 SPARSE CHURN size=%ld delta=%ld\n", before.size[i], delta);
        CHECK(delta < 64);
        if (delta > 0) kept += delta * before.size[i];
    }
    CHECK(kept < 65536 && free_blocks() == available);
    long long elapsed_ms = (end.tv_sec - start.tv_sec) * 1000LL + (end.tv_nsec - start.tv_nsec) / 1000000LL;
    printf("EXT2 SPARSE CHURN runs=500 retained=%ld elapsed_ms=%lld\n", kept, elapsed_ms);
    CHECK(elapsed_ms < 60000);
    CHECK(unlink("/root/sparse-churn") == 0 && close(fd) == 0);
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
    block_size = fs.f_bsize;
    CHECK(block_size == 1024 || block_size == 4096);
    uint64_t p = block_size / 4;
    capacity = (12 + p + p*p + p*p*p) * block_size;
    uint64_t logical[] = {11, 12, 12+p-1, 12+p, 12+p+p*p-1, 12+p+p*p,
                          12+p+p*p+p*p+2*p+3, (UINT64_C(1)<<32)/block_size-2,
                          capacity/block_size-1};
    memcpy(positions, logical, sizeof logical);
    uint64_t state[2] = {0};
    int stage = open("/root/sparse-stage", O_CREAT | O_RDWR, 0600);
    CHECK(stage >= 0);
    ssize_t got = pread(stage, state, sizeof state, 0);
    CHECK(got == 0 || got == sizeof state);
    const char *step = state[0] == 0 ? "create" : state[0] == 1 ? "shrink" : "cleanup";
    printf("EXT2 SPARSE START %s\n", step);
    int fd = open("/root/sparse-persist", O_CREAT | O_RDWR, 0600);
    CHECK(fd >= 0);
    uint64_t small = (12 + p + 1) * block_size + 20;
    if (!state[0]) {
        CHECK(pwrite(stage, state, sizeof state, 0) == sizeof state);
        state[1] = free_blocks();
        shrink_tail();
        churn();
        CHECK(ftruncate(fd, (off_t)capacity) == 0);
        struct stat st;
        CHECK(fstat(fd, &st) == 0 && (uint64_t)st.st_size == capacity && st.st_blocks == 0);
        errno = 0; CHECK(ftruncate(fd, (off_t)(capacity + 1)) == -1 && errno == EFBIG);
        for (size_t i = 0; i < sizeof positions / sizeof positions[0]; i++)
            CHECK(pwrite(fd, bytes, sizeof bytes, (off_t)(positions[i]*block_size+17)) == sizeof bytes);
        CHECK(pwrite(fd, crossing, sizeof crossing, (off_t)((UINT64_C(1)<<32)-8)) == sizeof crossing);
        CHECK(pwrite(fd, bytes, 0, (off_t)capacity) == 0);
        check_file(fd, capacity);
        state[0] = 1;
    } else if (state[0] == 1) {
        check_file(fd, capacity);
        CHECK(ftruncate(fd, (off_t)small) == 0);
        check_file(fd, small);
        state[0] = 2;
    } else {
        CHECK(state[0] == 2);
        check_file(fd, small);
        CHECK(ftruncate(fd, 0) == 0);
        struct stat st;
        CHECK(fstat(fd, &st) == 0 && st.st_size == 0 && st.st_blocks == 0);
        CHECK(free_blocks() == state[1]);
        CHECK(unlink("/root/sparse-persist") == 0);
        CHECK(close(fd) == 0);
        fd = -1;
        state[0] = 3;
    }
    CHECK(pwrite(stage, state, sizeof state, 0) == sizeof state);
    CHECK((fd < 0 || fsync(fd) == 0) && fsync(stage) == 0);
    sync();
    printf("EXT2 SPARSE DONE %s ino=0\n", step);
    for (;;) pause();
}

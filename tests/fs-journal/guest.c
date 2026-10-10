#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/statfs.h>
#include <sys/syscall.h>
#include <sys/xattr.h>
#include <unistd.h>

#define CHECK(x) do { if (!(x)) { printf("JOURNAL FAIL line=%d errno=%d FAIL END\n", __LINE__, errno); for (;;) pause(); } } while (0)
#define ARM_CUT 0x564a0001UL
#define MODE 0x564a0002UL
#define SITES 0x564a0003UL
static void done(int mode) { printf("JOURNAL DONE %d ino=0\n", mode); for (;;) pause(); }
static int open_file(const char *name) { int fd = open(name, O_CREAT | O_RDWR, 0600); CHECK(fd >= 0); return fd; }
static char byte_at(const char *name) { int fd = open(name, O_RDONLY); char b; CHECK(fd >= 0 && read(fd, &b, 1) == 1 && close(fd) == 0); return b; }

static void sparse(int fd)
{
    for (int i = 0; i < 600; i++) {
        char b = (char)(i % 127 + 1);
        CHECK(pwrite(fd, &b, 1, (off_t)i * 4 * 1024 * 1024) == 1);
    }
}

static void full(void)
{
    CHECK(mkdir("/root/left", 0700) == 0 && mkdir("/root/right", 0700) == 0);
    int fd = open_file("/root/left/file");
    unsigned char data[16384]; memset(data, 0x41, sizeof(data));
    CHECK(write(fd, data, sizeof(data)) == sizeof(data));
    CHECK(fsetxattr(fd, "user.journal", "durable", 7, 0) == 0);
    CHECK(link("/root/left/file", "/root/alias") == 0);
    CHECK(rename("/root/left/file", "/root/right/file") == 0);
    CHECK(chmod("/root/alias", 0640) == 0 && unlink("/root/alias") == 0);
    volatile unsigned char *shared = mmap(NULL, sizeof(data), PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    volatile unsigned char *private = mmap(NULL, sizeof(data), PROT_READ | PROT_WRITE, MAP_PRIVATE, fd, 0);
    CHECK(shared != MAP_FAILED && private != MAP_FAILED);
    private[17] = 0x99; shared[29] = 0x82; shared[sizeof(data) - 3] = 0x93;
    CHECK(msync((void *)shared, sizeof(data), MS_SYNC) == 0 && fsync(fd) == 0);
    CHECK(ftruncate(fd, 9000) == 0 && ftruncate(fd, sizeof(data)) == 0);
    CHECK(shared[9000] == 0 && shared[sizeof(data) - 3] == 0 && private[17] == 0x99);
    CHECK(munmap((void *)shared, sizeof(data)) == 0 && munmap((void *)private, sizeof(data)) == 0);
    CHECK(close(fd) == 0);
    CHECK(mkdir("/root/left/dir", 0700) == 0 && mkdir("/root/right/dir", 0700) == 0);
    CHECK(rename("/root/left/dir", "/root/right/dir") == 0);
    CHECK(syscall(SYS_renameat2, AT_FDCWD, "/root/source", AT_FDCWD, "/root/target", 2) == 0);
    CHECK(byte_at("/root/source") == 'B' && byte_at("/root/target") == 'A');
    fd = open_file("/root/large"); sparse(fd);
    CHECK(ftruncate(fd, 0) == 0);
    struct stat st; CHECK(fstat(fd, &st) == 0 && st.st_size == 0 && st.st_blocks == 0);
    sparse(fd); CHECK(unlink("/root/large") == 0 && close(fd) == 0);
    sync();
}

static void verify_full(void)
{
    int fd = open("/root/right/file", O_RDONLY); CHECK(fd >= 0);
    struct stat st; CHECK(fstat(fd, &st) == 0 && st.st_size == 16384 && st.st_nlink == 1 && (st.st_mode & 0777) == 0640);
    char attribute[16]; CHECK(fgetxattr(fd, "user.journal", attribute, sizeof(attribute)) == 7 && memcmp(attribute, "durable", 7) == 0);
    unsigned char data[16384]; CHECK(read(fd, data, sizeof(data)) == sizeof(data));
    for (int i = 0; i < 16384; i++) CHECK(data[i] == (i >= 9000 ? 0 : i == 29 ? 0x82 : 0x41));
    CHECK(close(fd) == 0 && access("/root/large", F_OK) != 0 && access("/root/alias", F_OK) != 0);
    CHECK(byte_at("/root/source") == 'B' && byte_at("/root/target") == 'A');
}

struct heap { long size[32], live[32], large; int n; };
static void snapshot(struct heap *h)
{
    memset(h, 0, sizeof(*h));
    FILE *f = fopen("/proc/slabinfo", "r"); CHECK(f != NULL);
    char line[256];
    while (fgets(line, sizeof(line), f)) {
        long index, size, live, pages;
        if (sscanf(line, "size-%ld %ld %ld %ld", &index, &size, &live, &pages) == 4) {
            CHECK(h->n < 32);
            h->size[h->n] = size; h->live[h->n++] = live;
        } else if (sscanf(line, "large - - %ld", &pages) == 1) h->large = pages;
    }
    CHECK(fclose(f) == 0 && h->n > 0);
}
static void churn_one(void)
{
    int fd = open_file("/root/churn");
    CHECK(ftruncate(fd, 16384) == 0);
    unsigned char *p = mmap(NULL, 16384, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    CHECK(p != MAP_FAILED); p[17] = 0x82;
    CHECK(msync(p, 16384, MS_SYNC) == 0);
    CHECK(link("/root/churn", "/root/churn-link") == 0);
    CHECK(rename("/root/churn", "/root/churn-renamed") == 0);
    CHECK(unlink("/root/churn-link") == 0 && unlink("/root/churn-renamed") == 0);
    CHECK(close(fd) == 0 && munmap(p, 16384) == 0);
}
static void settled_snapshot(struct heap *h)
{
    // Retired namespace nodes can require a second five-second grace pass.
    // Take per-class minima across timer phases to exclude short-lived
    // maintenance allocations; persistent retained objects cannot disappear.
    sleep(12); snapshot(h);
    for (int sample = 0; sample < 10; sample++) {
        usleep(200000); struct heap current; snapshot(&current);
        CHECK(current.n == h->n);
        for (int i = 0; i < h->n; i++) {
            CHECK(current.size[i] == h->size[i]);
            if (current.live[i] < h->live[i]) h->live[i] = current.live[i];
        }
        if (current.large < h->large) h->large = current.large;
    }
}
static void allocation_sites(const char *path, int print)
{
    FILE *f = fopen(path, "r"); if (!f) return;
    char line[1024];
    while (fgets(line, sizeof(line), f)) if (print) printf("JOURNAL SITE %s", line);
    fclose(f);
}
static void churn(int control)
{
    // Warm device-cache keys before comparing persistent allocation counts.
    int warm = open_file("/root/warm-cache"); unsigned char data[4096];
    memset(data, 0x71, sizeof(data));
    for (int i = 0; i < 160; i++) CHECK(write(warm, data, sizeof(data)) == sizeof(data));
    CHECK(lseek(warm, 0, SEEK_SET) == 0);
    for (int i = 0; i < 160; i++) CHECK(read(warm, data, sizeof(data)) == sizeof(data));
    CHECK(close(warm) == 0 && unlink("/root/warm-cache") == 0);
    // Warm the same peak workload as the measured batches, including the
    // bounded block cache and retirement queue capacities.
    for (int round = 0; round < 2; round++) {
        for (int i = 0; i < 200; i++) churn_one();
        sleep(12);
    }
    struct heap before, after;
    // Warm the observer too: the first procfs open may populate its vnode.
    for (int i = 0; i < 3; i++) snapshot(&before);
    // AMD64 executes this fixture from disk. Fault in the reporting code
    // before the baseline; printing the first batch otherwise adds a mapped
    // executable page and its clean block-cache page to the second batch.
    for (int i = 0; i < before.n; i++)
        printf("JOURNAL RETENTION batch=%d size=%ld objects=%ld\n", -1, before.size[i], 0L);
    printf("JOURNAL RETENTION batch=%d large=%ld\n", -1, 0L);
    allocation_sites("/proc/allocstart", 0);
    settled_snapshot(&before);
    for (int batch = 0; batch < 2; batch++) {
        for (int i = 0; i < 200; i++) churn_one();
        settled_snapshot(&after); CHECK(after.n == before.n);
        int flat = 1;
        for (int i = 0; i < after.n; i++) {
            long delta = after.live[i] - before.live[i];
            printf("JOURNAL RETENTION batch=%d size=%ld objects=%ld\n", batch, after.size[i], delta);
            if (after.size[i] != before.size[i] || delta > 0) flat = 0;
        }
        printf("JOURNAL RETENTION batch=%d large=%ld\n", batch, after.large - before.large);
        if (!flat || after.large > before.large) CHECK(ioctl(control, SITES, 0) == 0);
        CHECK(flat && after.large <= before.large);
    }
}

int main(void)
{
    setbuf(stdout, NULL);
#ifdef __x86_64__
    int console = open("/dev/com1", O_WRONLY);
    CHECK(console >= 0 && dup2(console, 1) == 1 && dup2(console, 2) == 2);
    CHECK(close(console) == 0);
#endif
    puts("JOURNAL START");
    int control = open("/root/control", O_RDONLY); CHECK(control >= 0);
#ifdef VINIX_JOURNAL_PRODUCTION
    int mode = access("/root/right/file", F_OK) == 0 ? 2 : 1;
#else
    int mode = ioctl(control, MODE, 0); CHECK(mode > 0);
#endif
    struct statfs fs; CHECK(fstatfs(control, &fs) == 0 && fs.f_type == 0x4a56);
    if (mode == 1) full();
    else if (mode == 2) verify_full();
    else if (mode >= 101 && mode <= 105) {
        CHECK(ioctl(control, ARM_CUT, (unsigned long)(mode - 100)) == 0);
        CHECK(rename("/root/source", "/root/target") == 0); CHECK(0);
    } else if (mode >= 201 && mode <= 205) {
        if (mode == 201) CHECK(byte_at("/root/source") == 'A' && byte_at("/root/target") == 'B');
        else CHECK(access("/root/source", F_OK) != 0 && byte_at("/root/target") == 'A');
    } else if (mode == 3 || mode == 5) {
        int fd = open_file("/root/large"); sparse(fd);
        if (mode == 3) CHECK(unlink("/root/large") == 0); // keep its FD alive across the power cut
        else { CHECK(ioctl(control, ARM_CUT, 2UL) == 0); CHECK(ftruncate(fd, 0) == 0); CHECK(0); }
    } else if (mode == 4) CHECK(access("/root/large", F_OK) != 0);
    else if (mode == 6) { struct stat st; CHECK(stat("/root/large", &st) == 0 && st.st_size == 0 && st.st_blocks == 0); }
    else if (mode == 8) churn(control);
    else CHECK(0);
    done(mode);
}

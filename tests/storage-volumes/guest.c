/* SPDX-License-Identifier: GPL-2.0-or-later */
#define _GNU_SOURCE
#include "../../tools/volumes/volumecli/volume.h"
#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <sys/mman.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/swap.h>
#include <sys/wait.h>
#define CREATE 0x56560001UL
#define GROW 0x56560002UL
#define REMOVE 0x56560003UL
#define STATUS 0x56560004UL
#define DISCARD 0x1277UL
#define CHECK(x) do { if (!(x)) { printf("VOLUME FAIL line=%d errno=%d FAIL END\n", __LINE__, errno); for (;;) pause(); } } while (0)
#define BAD(x, e) do { errno = 0; long result = (x); int actual = errno; if (result != -1 || actual != (e)) printf("VOLUME BAD %s result=%ld errno=%d expected=%d\n", #x, result, actual, (e)); CHECK(result == -1 && actual == (e)); } while (0)
static const char *node = "/dev/mapper/vinix0";
static unsigned char data[131072], got[131072];
static int disk;
static struct vinix_block_status status(int fd) {
    struct vinix_block_status s = {0}; CHECK(ioctl(fd, STATUS, &s) == 0 && s.version == 1 && s.reserved == 0); return s;
}
static void create(unsigned slot, uint64_t offset, uint64_t length, unsigned flags) {
    struct vinix_volume_request r = {1, slot, offset, length, flags}; CHECK(ioctl(disk, CREATE, &r) == 0);
}
static void remove_volume(int fd) { CHECK(ioctl(fd, REMOVE, 0) == 0); }
static int open_volume(int flags) { int fd = open(node, flags); CHECK(fd >= 0); return fd; }
static void tool_exit(int expected, const char *command, const char *device, const char *a, const char *b, const char *c) {
    pid_t p = fork(); CHECK(p >= 0);
    if (!p) { execl("/usr/sbin/vinix-volume", "vinix-volume", command, device, a, b, c, (char *)0); _exit(127); }
    int code; CHECK(waitpid(p, &code, 0) == p && WIFEXITED(code) && WEXITSTATUS(code) == expected);
}
struct heap { long size[32], live[32], large; int count; };
static void snapshot(struct heap *h) {
    memset(h, 0, sizeof(*h)); FILE *f = fopen("/proc/slabinfo", "r"); CHECK(f != NULL);
    char line[256];
    while (fgets(line, sizeof(line), f)) {
        long index, size, live, pages;
        if (sscanf(line, "size-%ld %ld %ld %ld", &index, &size, &live, &pages) == 4) {
            CHECK(h->count < 32); h->size[h->count] = size; h->live[h->count++] = live;
        } else if (sscanf(line, "large - - %ld", &pages) == 1) h->large = pages;
    }
    CHECK(fclose(f) == 0 && h->count > 0);
}
static void cycles(unsigned first, unsigned count) {
    for (unsigned i = first; i < first + count; i++) {
        create(0, 2 * 1024 * 1024 + (uint64_t)i * 4096, 512, 0);
        int fd = open_volume(O_RDWR);
        CHECK(pwrite(fd, data, 512, 0) == 512);
        uint64_t trim[2] = {0, 512}; CHECK(ioctl(fd, DISCARD, trim) == 0);
        struct vinix_volume_request r = {1, 0, 0, 1024, 0}; CHECK(ioctl(fd, GROW, &r) == 0);
        remove_volume(fd); CHECK(close(fd) == 0);
    }
    sleep(7); /* Namespace/object grace and writeback worker reaping. */
}
static void *opener(void *unused) {
    (void)unused;
    for (int i = 0; i < 400; i++) {
        int fd = open(node, O_RDONLY);
        if (fd >= 0) {
            unsigned char bytes[512]; ssize_t n = pread(fd, bytes, sizeof(bytes), 0);
            CHECK(n == 512 || (n == -1 && errno == ENODEV)); CHECK(close(fd) == 0);
        } else CHECK(errno == ENOENT || errno == ENODEV);
    }
    return NULL;
}
int main(void) {
    setbuf(stdout, NULL);
#ifdef __x86_64__
    int console = open("/dev/com1", O_WRONLY); CHECK(console >= 0 && dup2(console, 1) == 1 && dup2(console, 2) == 2); close(console);
    const char *parent = "/dev/sd0", *partition = "/dev/sd0-0";
#else
    const char *parent = "/dev/vda";
#endif
    puts("VOLUME START");
    disk = open(parent, O_RDWR); CHECK(disk >= 0);
    struct vinix_block_status physical = status(disk); CHECK(physical.bytes == 16 * 1024 * 1024 && physical.sector == 512 && (physical.flags & 4) && (physical.flags & 32));
    uint64_t geometry = 0; int sector = 0, ro = -1;
    CHECK(ioctl(disk, 0x80081272UL, &geometry) == 0 && geometry == physical.bytes);
    CHECK(ioctl(disk, 0x1268, &sector) == 0 && sector == 512 && ioctl(disk, 0x125e, &ro) == 0 && ro == 0);
    struct vinix_volume_request r = {1, 0, 1024 * 1024, sizeof(data), 0};
    BAD(ioctl(disk, CREATE, NULL), EFAULT);
    void *inaccessible = mmap(NULL, 4096, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0); CHECK(inaccessible != MAP_FAILED);
    BAD(ioctl(disk, CREATE, inaccessible), EFAULT); BAD(ioctl(disk, STATUS, inaccessible), EFAULT);
    r.offset = UINT64_MAX; BAD(ioctl(disk, CREATE, &r), EINVAL); r.offset = 1; BAD(ioctl(disk, CREATE, &r), EINVAL);
    r.offset = physical.bytes; BAD(ioctl(disk, CREATE, &r), EINVAL); r.offset = 1024 * 1024;
    r.slot = 64; BAD(ioctl(disk, CREATE, &r), EINVAL); r.slot = 0;
    r.flags = 2; BAD(ioctl(disk, CREATE, &r), EINVAL); r.flags = 0;
    CHECK(mkdir("/dev/mapper", 0700) == 0 || errno == EEXIST);
    int occupied = open(node, O_CREAT | O_RDWR, 0600); CHECK(occupied >= 0); close(occupied);
    BAD(ioctl(disk, CREATE, &r), EEXIST); CHECK(unlink(node) == 0);
    CHECK(ioctl(disk, CREATE, &r) == 0); int fd = open_volume(O_RDWR);
    struct vinix_block_status before = status(fd); CHECK(before.bytes == sizeof(data) && before.start == r.offset && before.slot == 0 && before.disk_id == physical.disk_id && (before.flags & 8));
    BAD(ioctl(disk, CREATE, &r), EEXIST); r.slot = 1; BAD(ioctl(disk, CREATE, &r), EBUSY); r.slot = 0;
    int bindtarget = open("/tmp/volume-bind", O_CREAT | O_RDWR, 0600); CHECK(bindtarget >= 0); close(bindtarget);
    BAD(mount(node, "/tmp/volume-bind", NULL, MS_BIND, NULL), EBUSY);
    CHECK(mkdir("/tmp/mapper-bind", 0700) == 0); BAD(mount("/dev/mapper", "/tmp/mapper-bind", NULL, MS_BIND, NULL), EBUSY);
    BAD(mount("tmpfs", "/dev/mapper", "tmpfs", 0, NULL), EBUSY);
    BAD(rename(node, "/dev/volume-moved"), EBUSY); BAD(link(node, "/dev/volume-link"), EBUSY);
    BAD(rename("/dev/mapper", "/dev/mapper-moved"), EBUSY); BAD(unlink(node), EBUSY);
    memset(data, 0x73, sizeof(data)); CHECK(pwrite(fd, data, sizeof(data), 0) == sizeof(data));
    CHECK(pread(fd, got, sizeof(got), 0) == sizeof(got) && memcmp(data, got, sizeof(data)) == 0);
    CHECK(pread(disk, got, sizeof(got), 1024 * 1024) == sizeof(got) && memcmp(data, got, sizeof(data)) == 0);
    BAD(pread(fd, got, 512, sizeof(data)), EINVAL); BAD(pwrite(fd, data, 511, 0), EINVAL);
    BAD(pread(fd, inaccessible, 512, 0), EFAULT); BAD(pwrite(fd, inaccessible, 512, 0), EFAULT);
    r.offset = 0; r.length = sizeof(data) / 2; BAD(ioctl(fd, GROW, &r), EINVAL);
    r.length = sizeof(data) * 2; CHECK(ioctl(fd, GROW, &r) == 0);
    CHECK(status(fd).bytes == sizeof(data) * 2 && pwrite(fd, data, 512, sizeof(data)) == 512 && fsync(fd) == 0);
    struct vinix_block_status after = status(fd); CHECK(after.reads >= 2 && after.writes >= 3 && after.flushes >= 1 && after.errors == 0);
    CHECK(status(disk).writes > physical.writes && status(disk).flushes > physical.flushes);
    /* A retained mknod alias opens the actual managed resource and sees growth. */
    struct stat st; CHECK(fstat(fd, &st) == 0 && mknod("/dev/volume-alias", S_IFBLK | 0600, st.st_rdev) == 0);
    BAD(mount("/dev/volume-alias", "/tmp/volume-bind", NULL, MS_BIND, NULL), EBUSY);
    int alias = open("/dev/volume-alias", O_RDWR); CHECK(alias >= 0 && status(alias).bytes == after.bytes);
    create(1, 1536 * 1024, 4096, 1);
    BAD(open("/dev/mapper/vinix1", O_RDWR), EROFS);
    int readonly = open("/dev/mapper/vinix1", O_RDONLY); CHECK(readonly >= 0 && (status(readonly).flags & 1));
    remove_volume(readonly); CHECK(close(readonly) == 0);
    pid_t child = fork(); CHECK(child >= 0);
    if (child == 0) { CHECK(setuid(1000) == 0); errno = 0; _exit(ioctl(fd, REMOVE, 0) == -1 && errno == EPERM ? 0 : 1); }
    int code; CHECK(waitpid(child, &code, 0) == child && WIFEXITED(code) && WEXITSTATUS(code) == 0);
    remove_volume(fd); CHECK(status(fd).flags & 2);
    BAD(pread(fd, got, 512, 0), ENODEV); BAD(pwrite(alias, data, 512, 0), ENODEV);
    BAD(ioctl(fd, REMOVE, 0), ENODEV); BAD(open(node, O_RDONLY), ENOENT);
    create(0, 1024 * 1024, 4096, 0); int replacement = open_volume(O_RDWR);
    CHECK(status(replacement).generation > before.generation); BAD(ioctl(fd, REMOVE, 0), ENODEV);
    remove_volume(replacement); CHECK(close(replacement) == 0 && close(fd) == 0 && close(alias) == 0 && unlink("/dev/volume-alias") == 0);
    tool_exit(2, "create", parent, "64", "0", "512"); tool_exit(2, "create", parent, "0", "18446744073709551616", "512");
    tool_exit(0, "create", parent, "0", "1048576", "4096"); tool_exit(0, "grow", node, "8192", NULL, NULL); tool_exit(0, "status", node, NULL, NULL, NULL); tool_exit(0, "remove", node, NULL, NULL, NULL);
    create(3, 4 * 1024 * 1024, 12288, 0);
    int trimfd = open("/dev/mapper/vinix3", O_RDWR); CHECK(trimfd >= 0);
    memset(data, 0x95, 12288); CHECK(pwrite(trimfd, data, 12288, 0) == 12288);
    uint64_t trim[2] = {4096, 4096};
    CHECK(ioctl(trimfd, DISCARD, trim) == 0 && fsync(trimfd) == 0);
    CHECK(pread(trimfd, got, 4096, 0) == 4096 && memcmp(got, data, 4096) == 0);
    CHECK(pread(trimfd, got, 4096, 8192) == 4096 && memcmp(got, data, 4096) == 0);
    trim[0] = UINT64_MAX; BAD(ioctl(trimfd, DISCARD, trim), EINVAL);
    trim[0] = 1; BAD(ioctl(trimfd, DISCARD, trim), EINVAL); trim[0] = 4096;
    trim[1] = 0; BAD(ioctl(trimfd, DISCARD, trim), EINVAL); trim[1] = 4096;
    BAD(ioctl(trimfd, DISCARD, inaccessible), EFAULT);
    int trimro = open("/dev/mapper/vinix3", O_RDONLY); CHECK(trimro >= 0); BAD(ioctl(trimro, DISCARD, trim), EBADF); close(trimro);
    tool_exit(2, "discard", "/dev/mapper/vinix3", "-1", "4096", NULL);
    tool_exit(0, "discard", "/dev/mapper/vinix3", "4096", "4096", NULL);
    CHECK(fstat(disk, &st) == 0 && mknod("/dev/disk-alias", S_IFBLK | 0600, st.st_rdev) == 0);
    int diskalias = open("/dev/disk-alias", O_RDWR); CHECK(diskalias >= 0 && (status(diskalias).flags & 32));
    trim[0] = 4 * 1024 * 1024 + 4096; CHECK(ioctl(diskalias, DISCARD, trim) == 0); close(diskalias);
    CHECK(unlink("/dev/disk-alias") == 0); trim[0] = 4096;
    remove_volume(trimfd); BAD(ioctl(trimfd, DISCARD, trim), ENODEV); close(trimfd);
#ifdef __x86_64__
    int partfd = open(partition, O_RDWR); CHECK(partfd >= 0);
    CHECK(status(partfd).start == 12 * 1024 * 1024 && (status(partfd).flags & 32));
    CHECK(pwrite(partfd, data, 12288, 0) == 12288 && ioctl(partfd, DISCARD, trim) == 0 && fsync(partfd) == 0);
    CHECK(pread(disk, got, 4096, 12 * 1024 * 1024) == 4096 && memcmp(got, data, 4096) == 0);
    CHECK(pread(disk, got, 4096, 12 * 1024 * 1024 + 8192) == 4096 && memcmp(got, data, 4096) == 0);
    trim[0] = 1024 * 1024; BAD(ioctl(partfd, DISCARD, trim), EINVAL); close(partfd);
#endif
    create(2, 8 * 1024 * 1024, 4 * 1024 * 1024, 0);
    int swapfd = open("/dev/mapper/vinix2", O_RDWR); CHECK(swapfd >= 0);
    unsigned char header[4096] = {0}; uint32_t one = 1, last = 1023;
    memcpy(header + 1024, &one, 4); memcpy(header + 1028, &last, 4); memcpy(header + 4086, "SWAPSPACE2", 10);
    CHECK(pwrite(swapfd, header, sizeof(header), 0) == sizeof(header));
    for (int i = 0; swapon("/dev/mapper/vinix2", 0) != 0; i++) { CHECK(errno == EAGAIN && i < 40); sleep(1); }
    CHECK(close(swapfd) == 0); swapfd = open("/dev/mapper/vinix2", O_RDONLY); CHECK(swapfd >= 0);
    r.length = 5 * 1024 * 1024; BAD(ioctl(swapfd, GROW, &r), EBUSY); BAD(ioctl(swapfd, REMOVE, 0), EBUSY);
    BAD(pwrite(disk, data, 512, 8 * 1024 * 1024), EBUSY);
    trim[0] = 8 * 1024 * 1024; trim[1] = 4096; BAD(ioctl(disk, DISCARD, trim), EBUSY);
    CHECK(swapoff("/dev/mapper/vinix2") == 0); remove_volume(swapfd); CHECK(close(swapfd) == 0);
    memset(data, 0x73, sizeof(data));
    pthread_t worker; CHECK(pthread_create(&worker, NULL, opener, NULL) == 0); cycles(0, 100); CHECK(pthread_join(worker, NULL) == 0);
    /* Warm the policy/retirement arrays, then measure distinct extents. */
    cycles(100, 200); struct heap warm, final; snapshot(&warm); cycles(300, 200); snapshot(&final);
    CHECK(warm.count == final.count && final.large <= warm.large);
    for (int i = 0; i < warm.count; i++) { printf("VOLUME RETAIN size=%ld delta=%ld\n", warm.size[i], final.live[i] - warm.live[i]); CHECK(final.size[i] == warm.size[i] && final.live[i] <= warm.live[i]); }
    CHECK(munmap(inaccessible, 4096) == 0 && close(disk) == 0);
    puts("VOLUME DONE full ino=0"); for (;;) pause();
}

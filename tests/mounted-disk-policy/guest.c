#define _GNU_SOURCE
#include <errno.h>
#include <dirent.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/statfs.h>
#include <sys/uio.h>
#include <unistd.h>

#define CHECK(x) do { if (!(x)) { printf("SECUREDISK FAIL line=%d errno=%d: %s FAIL END\n", __LINE__, errno, #x); for (;;) pause(); } } while (0)
static unsigned char data[512], observed[512];

static void level(int value)
{
    char text[8]; int length = snprintf(text, sizeof text, "%d\n", value);
    int fd = open("/proc/sys/kernel/securelevel", O_WRONLY); CHECK(fd >= 0);
    CHECK(write(fd, text, (size_t)length) == length && close(fd) == 0);
}

static long slab(void)
{
    FILE *file = fopen("/proc/meminfo", "r"); CHECK(file != NULL);
    char line[256], key[64]; long value, found = -1;
    while (fgets(line, sizeof line, file))
        if (sscanf(line, "%63s %ld", key, &value) == 2 && !strcmp(key, "Slab:")) found = value;
    CHECK(fclose(file) == 0 && found >= 0); return found;
}

static void denied_open(const char *path)
{
    errno = 0; CHECK(open(path, O_WRONLY) == -1 && errno == EPERM);
    int fd = open(path, O_RDONLY); CHECK(fd >= 0 && close(fd) == 0);
    fd = open(path, O_PATH); CHECK(fd >= 0 && close(fd) == 0);
}

static void denied_write(int fd)
{
    errno = 0; CHECK(write(fd, data, sizeof data) == -1 && errno == EPERM);
    errno = 0; CHECK(pwrite(fd, data, sizeof data, 0) == -1 && errno == EPERM);
    struct iovec vector = {data, sizeof data};
    errno = 0; CHECK(writev(fd, &vector, 1) == -1 && errno == EPERM);
}

static void denied_transfer(int fd, int input)
{
    int pipes[2]; CHECK(pipe2(pipes, O_NONBLOCK | O_CLOEXEC) == 0);
    CHECK(write(pipes[1], data, sizeof data) == sizeof data);
    off_t destination = 0;
    errno = 0; CHECK(splice(pipes[0], NULL, fd, &destination, sizeof data, 0) == -1 && errno == EPERM);
    CHECK(destination == 0);
    CHECK(read(pipes[0], observed, sizeof observed) == sizeof observed && !memcmp(data, observed, sizeof data));
    CHECK(close(pipes[0]) == 0 && close(pipes[1]) == 0);
    CHECK(lseek(input, 0, SEEK_SET) == 0);
    off_t source = 0;
    errno = 0; CHECK(copy_file_range(input, &source, fd, &destination, sizeof data, 0) == -1 && errno == EPERM);
    CHECK(source == 0 && destination == 0 && lseek(input, 0, SEEK_CUR) == 0);
}

int main(void)
{
#ifdef __x86_64__
    int serial = open("/dev/com1", O_WRONLY | O_NOCTTY);
    if (serial >= 0) { dup2(serial, 1); dup2(serial, 2); close(serial); }
    const char *mounted = "/dev/sd0", *spare = "/dev/sd1";
#else
    const char *mounted = "/dev/vda", *spare = "/dev/vdb";
#endif
    setbuf(stdout, NULL); puts("SECUREDISK START"); level(0);
    DIR *devices = opendir("/dev"); CHECK(devices != NULL);
    struct dirent *entry;
    while ((entry = readdir(devices)) != NULL) {
        char path[256]; snprintf(path, sizeof path, "/dev/%.240s", entry->d_name);
        struct stat device;
        if (stat(path, &device) == 0 && S_ISBLK(device.st_mode))
            printf("SECUREDISK DEVICE: %s rdev=%llu bytes=%lld\n", path, (unsigned long long)device.st_rdev, (long long)device.st_size);
    }
    CHECK(closedir(devices) == 0);
    struct stat original, extra;
    CHECK(stat(mounted, &original) == 0 && S_ISBLK(original.st_mode));
    CHECK(stat(spare, &extra) == 0 && S_ISBLK(extra.st_mode));
    struct statfs filesystem;
    CHECK(statfs("/root", &filesystem) == 0 && filesystem.f_type == 0xef53);
    CHECK(mknod("/policy-mounted", S_IFBLK | 0600, original.st_rdev) == 0);
    CHECK(mknod("/policy-spare", S_IFBLK | 0600, extra.st_rdev) == 0);
    CHECK(mknod("/policy-unknown", S_IFBLK | 0600, (dev_t)-1) == 0);
    CHECK(symlink(mounted, "/policy-symlink") == 0);
    CHECK(mkdir("/policy-aliases", 0700) == 0);
    char misleading[64]; snprintf(misleading, sizeof misleading, "/policy-aliases/%s", strrchr(mounted, '/') + 1);
    CHECK(mknod(misleading, S_IFCHR | 0600, 0) == 0); /* Basename selects the real block backing. */
    int held = open(mounted, O_RDWR), alias = open("/policy-mounted", O_RDWR);
    int disguised = open(misleading, O_RDWR | O_NOCTTY), unmounted = open(spare, O_RDWR);
    CHECK(held >= 0 && alias >= 0 && disguised >= 0 && unmounted >= 0);
    CHECK(pread(held, observed, sizeof observed, 0) == sizeof observed);
    unsigned char before[512]; memcpy(before, observed, sizeof before);
    memset(data, 0xa7, sizeof data);
    int input = open("/root/policy-input", O_CREAT | O_RDWR, 0600); CHECK(input >= 0);
    CHECK(write(input, data, sizeof data) == sizeof data && lseek(input, 0, SEEK_SET) == 0);
    CHECK(pwrite(unmounted, data, sizeof data, 4096) == sizeof data);
    CHECK(pread(unmounted, observed, sizeof observed, 4096) == sizeof observed && !memcmp(data, observed, sizeof data));

    level(1);
    denied_open(mounted); denied_open("/policy-mounted"); denied_open("/policy-symlink"); denied_open(misleading);
    denied_open("/policy-unknown");
    denied_write(held); denied_write(alias);
    denied_transfer(held, input); denied_transfer(alias, input); denied_transfer(disguised, input);
    errno = 0; CHECK(write(disguised, data, sizeof data) == -1 && errno == EPERM);
    CHECK(pread(held, observed, sizeof observed, 0) == sizeof observed && !memcmp(before, observed, sizeof before));
    puts("SECUREDISK PASS: mounted capability and aliases cannot write at level 1");

    int spare_alias = open("/policy-spare", O_RDWR); CHECK(spare_alias >= 0);
    memset(data, 0x59, sizeof data);
    CHECK(pwrite(unmounted, data, sizeof data, 4096) == sizeof data);
    CHECK(pwrite(spare_alias, data, sizeof data, 8192) == sizeof data);
    CHECK(pread(unmounted, observed, sizeof observed, 8192) == sizeof observed && !memcmp(data, observed, sizeof data));
#ifdef __x86_64__
    /* The root's MBR entry is a whole-extent alias with start LBA 0.
     * Its own rdev differs, but its physical identity overlaps the root. */
    denied_open("/dev/sd0-0");
    int partition = open("/dev/sd1-0", O_RDWR); CHECK(partition >= 0);
    CHECK(pwrite(partition, data, sizeof data, 4096) == sizeof data && close(partition) == 0);
#else
    /* qemu-persist is an existing template for mounted, regardless of the
     * source string: this must protect mounted, without marking spare. */
    CHECK(mkdir("/policy-second", 0700) == 0);
    int file = open("/root/policy-template", O_CREAT | O_WRONLY, 0600); CHECK(file >= 0);
    CHECK(write(file, data, sizeof data) == sizeof data && fsync(file) == 0 && close(file) == 0);
    CHECK(mount(spare, "/policy-second", "qemu-persist", 0, "") == 0);
    file = open("/policy-second/policy-template", O_RDONLY); CHECK(file >= 0);
    CHECK(read(file, observed, sizeof observed) == sizeof observed && !memcmp(data, observed, sizeof data) && close(file) == 0);
    CHECK(umount("/policy-second") == 0);
    denied_open(mounted);
    CHECK(pwrite(unmounted, data, sizeof data, 4096) == sizeof data);
#endif
    puts("SECUREDISK PASS: unrelated raw disk remains writable and actual backing wins");

    int output = open("/root/policy-writeback", O_CREAT | O_TRUNC | O_WRONLY, 0600); CHECK(output >= 0);
    for (int i = 0; i < 128; ++i) CHECK(write(output, data, sizeof data) == sizeof data);
    CHECK(fsync(output) == 0 && close(output) == 0);
    puts("SECUREDISK PASS: mounted filesystem writeback remains available");

    struct iovec vector = {data, sizeof data};
    int transfers[2]; CHECK(pipe2(transfers, O_NONBLOCK | O_CLOEXEC) == 0);
    CHECK(write(transfers[1], data, sizeof data) == sizeof data);
    for (int i = 0; i < 50; ++i) {
        errno = 0; CHECK(open("/policy-mounted", O_WRONLY) == -1 && errno == EPERM);
        denied_write(held);
        off_t source = 0, destination = 0;
        errno = 0; CHECK(splice(transfers[0], NULL, held, &destination, sizeof data, 0) == -1 && errno == EPERM);
        errno = 0; CHECK(copy_file_range(input, &source, held, &destination, sizeof data, 0) == -1 && errno == EPERM);
    }
    long old = slab();
    for (int i = 0; i < 1000; ++i) {
        errno = 0; CHECK(open("/policy-mounted", O_WRONLY) == -1 && errno == EPERM);
        errno = 0; CHECK(pwrite(held, data, sizeof data, 0) == -1 && errno == EPERM);
        errno = 0; CHECK(write(held, data, sizeof data) == -1 && errno == EPERM);
        errno = 0; CHECK(writev(alias, &vector, 1) == -1 && errno == EPERM);
        off_t source = 0, destination = 0;
        errno = 0; CHECK(splice(transfers[0], NULL, held, &destination, sizeof data, 0) == -1 && errno == EPERM);
        errno = 0; CHECK(copy_file_range(input, &source, held, &destination, sizeof data, 0) == -1 && errno == EPERM);
        CHECK(source == 0 && destination == 0);
    }
    long after = slab();
    printf("SECUREDISK RETAINED: 6000 denials slab_kb=%ld -> %ld\n", old, after); CHECK(after <= old + 16);
    CHECK(read(transfers[0], observed, sizeof observed) == sizeof observed && !memcmp(data, observed, sizeof data));
    CHECK(close(transfers[0]) == 0 && close(transfers[1]) == 0);
    level(2); denied_open(spare); denied_open("/policy-spare"); denied_write(unmounted); denied_write(spare_alias);
    denied_transfer(unmounted, input); denied_transfer(spare_alias, input);
    errno = 0; CHECK(write(disguised, data, sizeof data) == -1 && errno == EPERM);
    CHECK(close(held) == 0 && close(alias) == 0 && close(disguised) == 0 && close(unmounted) == 0 && close(spare_alias) == 0 && close(input) == 0);
    level(0); sync();
    puts("SECUREDISK DONE pass ino=0"); for (;;) pause();
}

/* SPDX-License-Identifier: GPL-2.0-or-later */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <sched.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/mount.h>
#include <sys/reboot.h>
#include <sys/resource.h>
#include <signal.h>
#include <sys/stat.h>
#include <sys/statfs.h>
#include <sys/syscall.h>
#include <sys/uio.h>
#include <sys/sendfile.h>
#include <sys/wait.h>
#include <unistd.h>

#ifndef TEST_DIR
#define TEST_DIR "/tmp"
#endif

#define FLAGS_GET 0x80086601UL
#define FLAGS_SET 0x40086602UL
#define IMMUTABLE 0x10
#define APPEND 0x20
#define CHECK(x) do { if (!(x)) { printf("SECURELEVEL FAIL: line %d: %s errno=%d\n", __LINE__, #x, errno); return 1; } } while (0)
static const char *level_path = "/proc/sys/kernel/securelevel";
static int secure_fd;

static int level(void)
{
    char text[16];
    int fd = open(level_path, O_RDONLY);
    if (fd < 0) return -99;
    ssize_t n = read(fd, text, sizeof text - 1);
    close(fd);
    if (n < 1) return -99;
    text[n] = 0;
    return atoi(text);
}
static int set_level(const char *value)
{
    size_t size = strlen(value);
    errno = 0;
    ssize_t result = pwrite(secure_fd, value, size, 0);
    return result == (ssize_t)size ? 0 : (result < 0 ? errno : EIO);
}
static int reap(pid_t child)
{
    int status;
    pid_t result;
    do result = waitpid(child, &status, 0); while (result < 0 && errno == EINTR);
    return result == child && WIFEXITED(status) ? WEXITSTATUS(status) : 255;
}
static void *raising(void *unused)
{
    (void)unused;
    for (unsigned i = 0; i < 200; ++i) {
        int result = set_level("2");
        if (result || level() != 2) return (void *)1;
    }
    return NULL;
}
static void *lowering(void *unused)
{
    (void)unused;
    for (unsigned i = 0; i < 200; ++i) {
        int result = set_level("1");
        /* Before the first raise a no-op succeeds. Once the atomic raise is
         * published, every later attempt must be refused for non-init. */
        if ((result != 0 && result != EPERM) || level() < 1) return (void *)1;
    }
    return NULL;
}
static int concurrent_transitions(void)
{
    pid_t child = fork();
    CHECK(child >= 0);
    if (!child) {
        pthread_t raise_thread, lower_thread;
        void *raised = (void *)1, *lowered = (void *)1;
        if (pthread_create(&raise_thread, NULL, raising, NULL)
            || pthread_create(&lower_thread, NULL, lowering, NULL)) _exit(1);
        if (pthread_join(raise_thread, &raised) || pthread_join(lower_thread, &lowered)) _exit(2);
        _exit(!raised && !lowered && level() == 2 && set_level("1") == EPERM ? 0 : 3);
    }
    CHECK(reap(child) == 0);
    CHECK(level() == 2);
    puts("SECURELEVEL PASS: concurrent non-init raises and lowers are serialized");
    return 0;
}
static int authority(int immutable_fd)
{
    pid_t child = fork();
    CHECK(child >= 0);
    if (!child) {
        if (unshare(CLONE_NEWUSER)) _exit(1);
        int flags = IMMUTABLE | APPEND;
        int bad = set_level("2") != EPERM
            || ioctl(immutable_fd, FLAGS_SET, &flags) != -1 || errno != EPERM;
        errno = 0;
        bad |= mount("tmpfs", TEST_DIR "/host-mount", "tmpfs", 0, "") != -1 || errno != EPERM;
        errno = 0;
        bad |= sethostname("changed-host", 12) != -1 || errno != EPERM;
        errno = 0;
        bad |= reboot(RB_AUTOBOOT) != -1 || errno != EPERM;
        /* Namespaced controls remain useful to container roots. */
        bad |= unshare(CLONE_NEWNS | CLONE_NEWUTS) != 0;
        bad |= sethostname("private-host", 12) != 0;
        bad |= mount("tmpfs", TEST_DIR "/host-mount", "tmpfs", 0, "") != 0;
        _exit(bad ? 2 : 0);
    }
    CHECK(reap(child) == 0);
    CHECK(level() >= 1);
    child = fork();
    CHECK(child >= 0);
    if (!child) {
        struct { uint32_t version; int pid; } header = { 0x20080522, 0 };
        struct { uint32_t effective, permitted, inheritable; } data[2];
        memset(data, 0, sizeof data);
        data[0].effective = data[0].permitted = UINT32_MAX & ~(1u << 21);
        data[1].effective = data[1].permitted = 0x1ff;
        _exit(syscall(SYS_capset, &header, data) == 0 && set_level("2") == EPERM ? 0 : 3);
    }
    CHECK(reap(child) == 0);
    puts("SECURELEVEL PASS: host controls require initial namespace capabilities; private controls work");
    return 0;
}
static int shared_aliases(void)
{
    long page = sysconf(_SC_PAGESIZE);
    CHECK(page > 0);
    int fd = open(TEST_DIR "/mapped-seal", O_CREAT | O_RDWR, 0600);
    CHECK(fd >= 0 && ftruncate(fd, 3 * page) == 0);
    int flags = IMMUTABLE;
    void *readonly = mmap(NULL, 3 * page, PROT_READ, MAP_SHARED, fd, 0);
    CHECK(readonly != MAP_FAILED);
    CHECK(ioctl(fd, FLAGS_SET, &flags) == -1 && errno == EBUSY);
    CHECK(munmap(readonly, 3 * page) == 0);
    void *mapping = mmap(NULL, 3 * page, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    CHECK(mapping != MAP_FAILED);
    /* Admission happens before faults, and failure must unwind its count. */
    CHECK(ioctl(fd, FLAGS_SET, &flags) == -1 && errno == EBUSY);
    CHECK(mmap(mapping, page, PROT_READ, MAP_SHARED | MAP_FIXED_NOREPLACE, fd, 0)
        == MAP_FAILED && errno == EEXIST);
    CHECK(munmap(mapping, page) == 0);
    CHECK(ioctl(fd, FLAGS_SET, &flags) == -1 && errno == EBUSY);
    int release[2], acknowledge[2];
    CHECK(pipe(release) == 0 && pipe(acknowledge) == 0);
    pid_t child = fork();
    CHECK(child >= 0);
    if (!child) {
        char byte;
        if (read(release[0], &byte, 1) != 1 || munmap((char *)mapping + page, 2 * page)) _exit(1);
        _exit(write(acknowledge[1], "x", 1) == 1 ? 0 : 2);
    }
    CHECK(munmap((char *)mapping + page, 2 * page) == 0);
    CHECK(ioctl(fd, FLAGS_SET, &flags) == -1 && errno == EBUSY);
    CHECK(write(release[1], "x", 1) == 1);
    char byte;
    CHECK(read(acknowledge[0], &byte, 1) == 1 && reap(child) == 0);
    for (unsigned i = 0; i < 2; ++i) { CHECK(close(release[i]) == 0); CHECK(close(acknowledge[i]) == 0); }
    mapping = mmap(NULL, 3 * page, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    CHECK(mapping != MAP_FAILED);
    void *destination = mmap(NULL, 3 * page, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    CHECK(destination != MAP_FAILED && munmap(destination, 3 * page) == 0);
    void *moved = mremap(mapping, 3 * page, 3 * page, MREMAP_MAYMOVE | MREMAP_FIXED, destination);
    CHECK(moved == destination);
    CHECK(ioctl(fd, FLAGS_SET, &flags) == -1 && errno == EBUSY);
    CHECK(munmap(moved, 3 * page) == 0);
    CHECK(ioctl(fd, FLAGS_SET, &flags) == 0);
    CHECK(mmap(NULL, page, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0) == MAP_FAILED && errno == EPERM);
    CHECK(mmap(NULL, page, PROT_READ, MAP_SHARED, fd, 0) == MAP_FAILED && errno == EPERM);
    void *copy = mmap(NULL, page, PROT_READ | PROT_WRITE, MAP_PRIVATE, fd, 0);
    CHECK(copy != MAP_FAILED);
    *(volatile char *)copy = 'x';
    CHECK(pread(fd, &byte, 1, 0) == 1 && byte == 0);
    CHECK(munmap(copy, page) == 0 && close(fd) == 0);
    puts("SECURELEVEL PASS: shared aliases block sealing through admission, failure, fork, split, and mremap");
    return 0;
}
struct append_job { int fd; int tag; int error; };
static void *append_worker(void *argument)
{
    struct append_job *job = argument;
    for (int i = 0; i < 200; ++i) {
        int record[2] = {job->tag, i}, got[2];
        if (write(job->fd, record, sizeof record) != sizeof record) { job->error = 1; break; }
        off_t end = lseek(job->fd, 0, SEEK_CUR);
        if (end < (off_t)sizeof record || pread(job->fd, got, sizeof got, end - sizeof got) != sizeof got
            || memcmp(record, got, sizeof got)) { job->error = 2; break; }
    }
    return NULL;
}
static int concurrent_append(void)
{
    int first = open(TEST_DIR "/concurrent-append", O_CREAT | O_RDWR | O_APPEND, 0600);
    int second = open(TEST_DIR "/concurrent-append", O_RDWR | O_APPEND);
    CHECK(first >= 0 && second >= 0);
    struct append_job jobs[2] = {{first, 17, 0}, {second, 23, 0}};
    pthread_t threads[2];
    CHECK(pthread_create(&threads[0], NULL, append_worker, &jobs[0]) == 0);
    CHECK(pthread_create(&threads[1], NULL, append_worker, &jobs[1]) == 0);
    CHECK(pthread_join(threads[0], NULL) == 0 && pthread_join(threads[1], NULL) == 0);
    struct stat info;
    CHECK(!jobs[0].error && !jobs[1].error && fstat(first, &info) == 0 && info.st_size == 3200);
    CHECK(close(first) == 0 && close(second) == 0);
    pid_t child = fork();
    CHECK(child >= 0);
    if (!child) {
        signal(SIGXFSZ, SIG_IGN);
        int fd = open(TEST_DIR "/append-limit", O_CREAT | O_RDWR | O_APPEND, 0600);
        struct rlimit limit = {12, 12};
        if (fd < 0 || setrlimit(RLIMIT_FSIZE, &limit)) _exit(1);
        if (write(fd, "12345678", 8) != 8 || write(fd, "abcdefgh", 8) != 4 || lseek(fd, 0, SEEK_CUR) != 12) _exit(2);
        _exit(write(fd, "x", 1) == -1 && errno == EFBIG ? 0 : 3);
    }
    CHECK(reap(child) == 0);
    puts("SECURELEVEL PASS: concurrent appenders return actual end positions and enforce file-size limits");
    return 0;
}
struct heap_class { long size, live; };
struct heap_state { struct heap_class classes[32]; size_t count; long large; };
static int heap_snapshot(int fd, struct heap_state *state)
{
    char text[8192];
    memset(state, 0, sizeof *state);
    ssize_t length = pread(fd, text, sizeof text - 1, 0);
    CHECK(length > 0);
    text[length] = 0;
    char *line = text;
    int saw_large = 0;
    while (line && *line) {
        long class_size, size, live, pages;
        if (sscanf(line, "size-%ld %ld %ld %ld", &class_size, &size, &live, &pages) == 4 && class_size == size) {
            CHECK(state->count < 32);
            state->classes[state->count++] = (struct heap_class){size, live};
        } else if (sscanf(line, "large - - %ld", &pages) == 1) {
            state->large = pages;
            saw_large = 1;
        }
        line = strchr(line, '\n');
        if (line) ++line;
    }
#ifdef __aarch64__
    CHECK(state->count == 18 && saw_large);
#else
    CHECK(state->count == 14 && saw_large);
#endif
    return 0;
}
static int measure_writes(int boot)
{
    int fd = open("/proc/slabinfo", O_RDONLY);
    int append_fd = open(TEST_DIR "/concurrent-append", O_WRONLY | O_APPEND);
    CHECK(fd >= 0 && append_fd >= 0);
    struct heap_state warm, before, control, after, appended;
    CHECK(heap_snapshot(fd, &warm) == 0);
    CHECK(heap_snapshot(fd, &before) == 0);
    CHECK(heap_snapshot(fd, &control) == 0);
    for (unsigned i = 0; i < 2000; ++i)
        CHECK(set_level(boot == 2 ? " 2\n" : " 1\n") == 0);
    CHECK(heap_snapshot(fd, &after) == 0);
    for (unsigned i = 0; i < 2000; ++i) CHECK(write(append_fd, "", 0) == 0);
    CHECK(heap_snapshot(fd, &appended) == 0);
    CHECK(before.count == control.count && control.count == after.count && after.count == appended.count);
    for (size_t i = 0; i < after.count; ++i) {
        CHECK(before.classes[i].size == after.classes[i].size);
        long observed = after.classes[i].live - control.classes[i].live;
        long reader = control.classes[i].live - before.classes[i].live;
        printf("SECURELEVEL HEAP class=%ld control=%ld writes=%ld objects\n", after.classes[i].size, reader, observed);
        CHECK(reader == 0 && observed == 0);
        long append_objects = appended.classes[i].live - after.classes[i].live;
        printf("SECURELEVEL HEAP class=%ld append=%ld objects\n", after.classes[i].size, append_objects);
        CHECK(append_objects == 0);
    }
    CHECK(control.large == before.large && after.large == control.large);
    CHECK(appended.large == after.large);
    CHECK(close(append_fd) == 0 && close(fd) == 0);
    puts("SECURELEVEL PASS: 2000 policy writes and zero-length appends retain no excess objects");
    return 0;
}
int main(void)
{
    setvbuf(stdout, NULL, _IONBF, 0);
    puts("SECURELEVEL BOOT TEST ENTERED");
    CHECK(getpid() == 1);
#ifdef SECURELEVEL_EXT2
    struct statfs filesystem;
    CHECK(statfs(TEST_DIR, &filesystem) == 0 && filesystem.f_type == 0xef53);
    puts("SECURELEVEL PASS: file enforcement is running on ext2");
#endif
    secure_fd = open(level_path, O_WRONLY);
    CHECK(secure_fd >= 0);
    int boot = level();
    CHECK(boot >= -1 && boot <= 2);
    CHECK(set_level("garbage") == EINVAL && level() == boot);
    CHECK(set_level("1x") == EINVAL && level() == boot);
    CHECK(set_level("1 2") == EINVAL && level() == boot);
    CHECK(set_level("2147483648") == EINVAL && level() == boot);
    CHECK(set_level("\n\t  ") == EINVAL && level() == boot);
    char oversized[80]; memset(oversized, ' ', sizeof oversized); oversized[79] = 0;
    CHECK(set_level(oversized) == EINVAL && level() == boot);
    int result = set_level("-1");
    if (boot > 0) {
        CHECK(result == EPERM && level() == boot);
        CHECK(set_level("0") == EPERM && level() == boot);
    } else if (result == 0) {
        CHECK(level() == -1 && set_level("0") == 0);
        puts("SECURELEVEL PASS: absent boot option preserves PID 1 default compatibility");
    } else {
        CHECK(result == EPERM && level() == 0);
        puts("SECURELEVEL PASS: explicit zero floor rejects permanently-insecure mode");
    }
    CHECK(mkdir(TEST_DIR "/host-mount", 0755) == 0);
    int fd = open(TEST_DIR "/sealed", O_CREAT | O_RDWR, 0600);
    CHECK(fd >= 0 && write(fd, "approved", 8) == 8);
    int flags = IMMUTABLE;
    CHECK(ioctl(fd, FLAGS_SET, &flags) == 0);
    if (boot <= 0) CHECK(set_level("1") == 0);
    flags = 0;
    CHECK(ioctl(fd, FLAGS_SET, &flags) == -1 && errno == EPERM);
    CHECK(write(fd, "x", 1) == -1 && errno == EPERM);
    struct iovec vector = { .iov_base = "x", .iov_len = 1 };
    CHECK(writev(fd, &vector, 1) == -1 && errno == EPERM);
    CHECK(pwrite(fd, "x", 1, 0) == -1 && errno == EPERM);
    int source = open(TEST_DIR "/write-source", O_CREAT | O_RDWR, 0600);
    CHECK(source >= 0 && write(source, "x", 1) == 1);
    off_t offset = 0;
    CHECK(sendfile(fd, source, &offset, 1) == -1 && errno == EPERM);
    CHECK(close(source) == 0);
    int append_fd = open(TEST_DIR "/append", O_CREAT | O_RDWR, 0600);
    int append_writer = open(TEST_DIR "/append", O_WRONLY | O_APPEND);
    CHECK(append_fd >= 0 && append_writer >= 0);
    flags = APPEND;
    CHECK(ioctl(append_fd, FLAGS_SET, &flags) == 0);
    CHECK(write(append_fd, "x", 1) == -1 && errno == EPERM);
    CHECK(write(append_writer, "first", 5) == 5);
    CHECK(lseek(append_writer, 0, SEEK_SET) == 0 && write(append_writer, "second", 6) == 6);
    CHECK(lseek(append_fd, 0, SEEK_SET) == 0);
    char appended[12] = {0};
    CHECK(read(append_fd, appended, 11) == 11 && strcmp(appended, "firstsecond") == 0);
    CHECK(close(append_fd) == 0 && close(append_writer) == 0);
    CHECK(truncate(TEST_DIR "/sealed", 0) == -1 && errno == EPERM);
    CHECK(chmod(TEST_DIR "/sealed", 0777) == -1 && errno == EPERM);
    CHECK(unlink(TEST_DIR "/sealed") == -1 && errno == EPERM);
    CHECK(authority(fd) == 0);
    CHECK(shared_aliases() == 0);
    CHECK(concurrent_append() == 0);
    CHECK(concurrent_transitions() == 0);
    if (boot <= 1) {
        CHECK(set_level("1") == 0); /* init can lower runtime raises to the floor */
        CHECK(level() == 1);
    } else CHECK(set_level("1") == EPERM && level() == 2);
    CHECK(measure_writes(boot) == 0);
    CHECK(close(fd) == 0 && close(secure_fd) == 0);
    printf("SECURELEVEL PASS: boot floor %d enforced for PID 1, file flags, and strict tunable writes\n", boot);
    sync();
    puts("SECURELEVEL ALL PASS");
    for (;;) pause();
}

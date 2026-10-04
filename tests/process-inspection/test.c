// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <pthread.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/prctl.h>
#include <sys/reboot.h>
#include <sys/syscall.h>
#include <sys/uio.h>
#include <sys/wait.h>
#include <unistd.h>

static unsigned char cow_byte = 0xA5;
static int failures;

static void check(int ok, const char *message) {
    if (!ok) {
        printf("FAIL: process inspection: %s (errno=%d)\n", message, errno);
        fflush(stdout);
        ++failures;
    }
}

static int exact_write(int fd, const void *data, size_t count) {
    return write(fd, data, count) == (ssize_t)count;
}

static int exact_read(int fd, void *data, size_t count) {
    return read(fd, data, count) == (ssize_t)count;
}

static ssize_t vm_copy(int write_remote, pid_t pid, const struct iovec *local,
                       size_t local_count, const struct iovec *remote,
                       size_t remote_count, unsigned long flags) {
    return syscall(write_remote ? SYS_process_vm_writev : SYS_process_vm_readv,
                   pid, local, local_count, remote, remote_count, flags);
}

static int child_exit(pid_t pid) {
    int status = 0;
    if (waitpid(pid, &status, 0) != pid || !WIFEXITED(status)) return -1;
    return WEXITSTATUS(status);
}

static void dumpability(void) {
    check(prctl(PR_GET_DUMPABLE) == 1, "new executable is dumpable");
    check(prctl(PR_SET_DUMPABLE, 0) == 0 && prctl(PR_GET_DUMPABLE) == 0,
          "dumpability setting is retained");
    check(prctl(PR_SET_DUMPABLE, 2) == -1 && errno == EINVAL &&
          prctl(PR_GET_DUMPABLE) == 0, "invalid dumpability preserves state");
    pid_t child = fork();
    if (child == 0) {
        if (prctl(PR_GET_DUMPABLE) != 0) _exit(1);
        execl("/sbin/init", "init", "--dumpability-exec", (char *)NULL);
        _exit(2);
    }
    check(child > 0 && child_exit(child) == 0, "fork inherits and exec resets dumpability");
    check(prctl(PR_SET_DUMPABLE, 1) == 0, "dumpability can be restored");
    child = fork();
    if (child == 0) {
        if (setgid(1000) || prctl(PR_GET_DUMPABLE) != 0) _exit(1);
        if (prctl(PR_SET_DUMPABLE, 1) || setuid(1000) || prctl(PR_GET_DUMPABLE) != 0)
            _exit(2);
        _exit(0);
    }
    check(child > 0 && child_exit(child) == 0, "effective uid and gid changes revoke dumpability");
    puts("PASS: dumpability state and credential lifecycle");
}

struct remote_info {
    uintptr_t cow;
    uintptr_t lazy;
    uintptr_t readonly;
    uintptr_t inaccessible;
    uintptr_t boundary;
};

static void memory_vectors(void) {
    size_t cow_size = (size_t)sysconf(_SC_PAGESIZE);
    unsigned char *cow_page = mmap(NULL, cow_size, PROT_READ | PROT_WRITE,
                                   MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    check(cow_page != MAP_FAILED, "allocate isolated fork shared page");
    if (cow_page == MAP_FAILED) return;
    cow_page[0] = 0xA5;
    int commands[2], replies[2];
    check(pipe(commands) == 0 && pipe(replies) == 0, "create memory test pipes");
    pid_t child = fork();
    if (child == 0) {
        close(commands[1]); close(replies[0]);
        size_t page = (size_t)sysconf(_SC_PAGESIZE);
        unsigned char *lazy = mmap(NULL, 80 * 1024 * 1024, PROT_READ | PROT_WRITE,
                                   MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        void *ro = mmap(NULL, page, PROT_READ, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        void *none = mmap(NULL, page, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        unsigned char *boundary = mmap(NULL, 2 * page, PROT_READ | PROT_WRITE,
                                      MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        if (lazy == MAP_FAILED || ro == MAP_FAILED || none == MAP_FAILED ||
            boundary == MAP_FAILED) _exit(1);
        lazy[64 * 1024 * 1024] = 0;
        memset(boundary, 0x31, page);
        if (mprotect(boundary + page, page, PROT_NONE)) _exit(2);
        struct remote_info info = {
            .cow = (uintptr_t)cow_page, .lazy = (uintptr_t)(lazy + 64 * 1024 * 1024),
            .readonly = (uintptr_t)ro, .inaccessible = (uintptr_t)none,
            .boundary = (uintptr_t)(boundary + page - 4),
        };
        if (!exact_write(replies[1], &info, sizeof(info))) _exit(3);
        char cmd;
        if (!exact_read(commands[0], &cmd, 1)) _exit(4);
        unsigned char *at = lazy + 64 * 1024 * 1024;
        _exit(cow_page[0] == 0xA5 && at[0] == 1 && at[1] == 2 && at[2] == 3 && at[3] == 4
              ? 0 : 5);
    }
    close(commands[0]); close(replies[1]);
    struct remote_info info = {0};
    check(child > 0 && exact_read(replies[0], &info, sizeof(info)), "receive child mappings");
    unsigned char result[8] = {0};
    struct iovec local[3] = {{result, 0}, {result, 2}, {result + 2, 2}};
    struct iovec remote[3] = {{(void *)info.lazy, 1}, {(void *)(info.lazy + 1), 0},
                             {(void *)(info.lazy + 1), 3}};
    check(vm_copy(0, child, local, 3, remote, 3, 0) == 4 &&
          memcmp(result, "\0\0\0\0", 4) == 0, "remote reads copy resident pages");
    unsigned char replacement[4] = {1, 2, 3, 4};
    local[1].iov_base = replacement;
    local[2].iov_base = replacement + 2;
    check(vm_copy(1, child, local, 3, remote, 3, 0) == 4,
          "scatter gather writes reach remote resident pages");
    struct iovec absent_remote = {(void *)(info.lazy + (uintptr_t)sysconf(_SC_PAGESIZE)), 1};
    struct iovec absent_local = {replacement, 1};
    check(vm_copy(0, child, &absent_local, 1, &absent_remote, 1, 0) == -1 && errno == EFAULT,
          "remote absent pages return an explicit fault");
    check(vm_copy(1, child, &absent_local, 1, &absent_remote, 1, 0) == -1 && errno == EFAULT,
          "remote absent pages cannot be allocated by writes");
    unsigned char *self_lazy = mmap(NULL, 80 * 1024 * 1024, PROT_READ | PROT_WRITE,
                                   MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    check(self_lazy != MAP_FAILED, "allocate self demand mapping");
    if (self_lazy != MAP_FAILED) {
        absent_remote.iov_base = self_lazy + 64 * 1024 * 1024;
        replacement[0] = 0x42;
        check(vm_copy(1, getpid(), &absent_local, 1, &absent_remote, 1, 0) == 1,
              "self inspection supports normal demand fault charging");
        check(self_lazy[64 * 1024 * 1024] == 0x42, "self demand write is visible");
        check(munmap(self_lazy, 80 * 1024 * 1024) == 0, "release self demand mapping");
    }
    unsigned char value = 0x5A;
    struct iovec one_local = {&value, 1}, one_remote = {(void *)info.cow, 1};
    check(vm_copy(1, child, &one_local, 1, &one_remote, 1, 0) == -1 && errno == EFAULT && cow_page[0] == 0xA5,
          "remote COW writes are rejected without changing parent");
    one_remote.iov_base = (void *)info.readonly;
    check(vm_copy(1, child, &one_local, 1, &one_remote, 1, 0) == -1 && errno == EFAULT,
          "remote writes cannot bypass readonly protection");
    one_remote.iov_base = (void *)info.inaccessible;
    check(vm_copy(0, child, &one_local, 1, &one_remote, 1, 0) == -1 && errno == EFAULT,
          "remote reads cannot bypass PROT_NONE");
    struct iovec bad_remote[2] = {{(void *)info.boundary, 4}, {(void *)info.inaccessible, 4}};
    struct iovec big_local = {result, 8};
    check(vm_copy(0, child, &big_local, 1, bad_remote, 2, 0) == 4 &&
          result[0] == 0x31 && result[3] == 0x31,
          "partial transfer reports bytes before a failing remote vector");
    struct iovec boundary = {(void *)info.boundary, 8};
    check(vm_copy(0, child, &big_local, 1, &boundary, 1, 0) == 4,
          "page boundary faults retain a successful prefix");
    check(vm_copy(0, child, &big_local, 1, &boundary, 1, 1) == -1 && errno == EINVAL,
          "unknown flags rejected");
    check(vm_copy(0, child, &big_local, 1025, &boundary, 1, 0) == -1 && errno == EINVAL,
          "vector count bounded");
    struct iovec overflow = {result, (size_t)SSIZE_MAX + 1};
    check(vm_copy(0, child, &overflow, 1, &boundary, 1, 0) == -1 && errno == EINVAL,
          "length overflow rejected");
    check(vm_copy(0, child, (void *)1, 1, &boundary, 1, 0) == -1 && errno == EFAULT,
          "invalid vector array is checked");
    struct iovec zero = {NULL, 0};
    check(vm_copy(0, INT_MAX, &zero, 1, (void *)1, 1, 0) == 0,
          "empty transfer does not inspect a target");
    check(vm_copy(0, INT_MAX, &big_local, 1, &boundary, 1, 0) == -1 && errno == ESRCH,
          "unknown process rejected");
    char cmd = 'V';
    check(exact_write(commands[1], &cmd, 1) && child_exit(child) == 0,
          "child observes written bytes");
    close(commands[1]); close(replies[0]);
    check(munmap(cow_page, cow_size) == 0, "release isolated fork shared page");
    puts("PASS: process VM copies, faults, COW, vectors and failures");
}

static void permission_worker(void) {
    if (setgid(1000) || setuid(1000) || prctl(PR_SET_DUMPABLE, 1)) _exit(1);
    int commands[2], replies[2];
    if (pipe(commands) || pipe(replies)) _exit(2);
    pid_t child = fork();
    if (child == 0) {
        close(commands[1]); close(replies[0]);
        unsigned char byte = 0x62;
        uintptr_t ptr = (uintptr_t)&byte;
        if (!exact_write(replies[1], &ptr, sizeof(ptr))) _exit(3);
        char cmd;
        if (!exact_read(commands[0], &cmd, 1)) _exit(4);
        if (prctl(PR_SET_DUMPABLE, 0)) _exit(5);
        if (!exact_write(replies[1], &cmd, 1) || !exact_read(commands[0], &cmd, 1)) _exit(6);
        _exit(0);
    }
    close(commands[0]); close(replies[1]);
    uintptr_t ptr = 0;
    if (child < 0 || !exact_read(replies[0], &ptr, sizeof(ptr))) _exit(7);
    unsigned char byte = 0;
    struct iovec local = {&byte, 1}, remote = {(void *)ptr, 1};
    if (vm_copy(0, child, &local, 1, &remote, 1, 0) != 1 || byte != 0x62) _exit(8);
    char cmd = 'D';
    if (!exact_write(commands[1], &cmd, 1) || !exact_read(replies[0], &cmd, 1)) _exit(9);
    if (vm_copy(0, child, &local, 1, &remote, 1, 0) != -1 || errno != EPERM) _exit(10);
    if (vm_copy(1, child, &local, 1, &remote, 1, 0) != -1 || errno != EPERM) _exit(11);
    char path[80];
    snprintf(path, sizeof(path), "/proc/%d/maps", child);
    int fd = open(path, O_RDONLY);
    if (fd >= 0) {
        char text[32];
        ssize_t got = read(fd, text, sizeof(text));
        close(fd);
        if (got != -1 || errno != EACCES) _exit(12);
    } else if (errno != EACCES) _exit(13);
    snprintf(path, sizeof(path), "/proc/%d/exe", child);
    char link[80];
    if (readlink(path, link, sizeof(link)) != -1 || errno != EACCES) _exit(17);
    // A process always remains able to copy its own memory after disabling dumps.
    if (prctl(PR_SET_DUMPABLE, 0)) _exit(14);
    remote.iov_base = &cow_byte;
    if (vm_copy(0, getpid(), &local, 1, &remote, 1, 0) != 1 || byte != 0xA5) _exit(15);
    if (!exact_write(commands[1], &cmd, 1) || child_exit(child) != 0) _exit(16);
    _exit(0);
}

static void permissions(void) {
    pid_t child = fork();
    if (child == 0) permission_worker();
    int status = child > 0 ? child_exit(child) : -1;
    if (status != 0) printf("permission worker status: %d\n", status);
    check(status == 0, "same credentials and dumpability govern remote memory and proc maps");
    puts("PASS: inspection authorization and dumpability revocation");
}

struct copy_job {
    pid_t pid;
    void *local;
    void *remote;
    size_t size;
    volatile int started;
    ssize_t result;
    int error;
};

static void *remote_reader(void *argument) {
    struct copy_job *job = argument;
    struct iovec local = {job->local, job->size}, remote = {job->remote, job->size};
    __atomic_store_n(&job->started, 1, __ATOMIC_RELEASE);
    job->result = vm_copy(0, job->pid, &local, 1, &remote, 1, 0);
    job->error = errno;
    return NULL;
}

static void teardown_races(void) {
    const size_t size = 16 * 1024 * 1024;
    unsigned char *local = mmap(NULL, size, PROT_READ | PROT_WRITE,
                                MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    check(local != MAP_FAILED, "allocate race destination");
    if (local == MAP_FAILED) return;
    for (int iteration = 0; iteration < 6; ++iteration) {
        int commands[2], replies[2];
        check(pipe(commands) == 0 && pipe(replies) == 0, "create teardown pipes");
        pid_t child = fork();
        if (child == 0) {
            close(commands[1]); close(replies[0]);
            unsigned char *space = mmap(NULL, 80 * 1024 * 1024, PROT_READ | PROT_WRITE,
                                        MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
            if (space == MAP_FAILED) _exit(1);
            memset(space + 32 * 1024 * 1024, 0, size);
            uintptr_t ptr = (uintptr_t)(space + 32 * 1024 * 1024);
            if (!exact_write(replies[1], &ptr, sizeof(ptr))) _exit(2);
            char cmd;
            if (!exact_read(commands[0], &cmd, 1)) _exit(3);
            if (iteration & 1) _exit(0);
            execl("/sbin/init", "init", "--inspection-exec-child", (char *)NULL);
            _exit(4);
        }
        close(commands[0]); close(replies[1]);
        uintptr_t ptr = 0;
        check(child > 0 && exact_read(replies[0], &ptr, sizeof(ptr)), "receive teardown mapping");
        struct copy_job job = {.pid = child, .local = local, .remote = (void *)ptr, .size = size};
        pthread_t reader;
        check(pthread_create(&reader, NULL, remote_reader, &job) == 0, "start concurrent inspector");
        while (!__atomic_load_n(&job.started, __ATOMIC_ACQUIRE)) sched_yield();
        usleep(1000);
        char cmd = 'X';
        check(exact_write(commands[1], &cmd, 1), "start child exec or exit");
        check(pthread_join(reader, NULL) == 0, "finish concurrent inspection");
        check(job.result > 0 || (job.result == -1 &&
              (job.error == ESRCH || job.error == EFAULT)), "teardown race has a valid copy result");
        check(child_exit(child) == 0, "child exec and exit complete after inspection");
        close(commands[1]); close(replies[0]);
    }
    check(munmap(local, size) == 0, "release race destination");
    puts("PASS: process VM inspection races with exec and exit");
}

static void remap_races(void) {
    int commands[2], replies[2];
    check(pipe(commands) == 0 && pipe(replies) == 0, "create remap test pipes");
    pid_t child = fork();
    if (child == 0) {
        close(commands[1]); close(replies[0]);
        size_t page = (size_t)sysconf(_SC_PAGESIZE);
        unsigned char *space = mmap(NULL, page, PROT_READ | PROT_WRITE,
                                    MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        if (space == MAP_FAILED) _exit(1);
        space[0] = 0x77;
        uintptr_t ptr = (uintptr_t)space;
        if (!exact_write(replies[1], &ptr, sizeof(ptr))) _exit(2);
        char cmd;
        if (!exact_read(commands[0], &cmd, 1)) _exit(3);
        for (int i = 0; i < 300; ++i) {
            if (munmap(space, page)) _exit(4);
            if (mmap(space, page, PROT_READ | PROT_WRITE,
                     MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED, -1, 0) != space) _exit(5);
            space[0] = 0x77;
            usleep(100);
        }
        _exit(0);
    }
    close(commands[0]); close(replies[1]);
    uintptr_t ptr = 0;
    check(child > 0 && exact_read(replies[0], &ptr, sizeof(ptr)), "receive remap target");
    unsigned char byte = 0;
    struct iovec local = {&byte, 1}, remote = {(void *)ptr, 1};
    check(vm_copy(0, child, &local, 1, &remote, 1, 0) == 1 && byte == 0x77,
          "read remap target before concurrent changes");
    char cmd = 'R';
    check(exact_write(commands[1], &cmd, 1), "start concurrent munmap and remap");
    for (int i = 0; i < 1500; ++i) {
        ssize_t got = vm_copy(0, child, &local, 1, &remote, 1, 0);
        check(got == 1 || (got == -1 && (errno == EFAULT || errno == ESRCH)),
              "concurrent remap has a checked read result");
        byte = 0x22;
        got = vm_copy(1, child, &local, 1, &remote, 1, 0);
        check(got == 1 || (got == -1 && (errno == EFAULT || errno == ESRCH)),
              "concurrent remap has a checked write result");
    }
    check(child_exit(child) == 0, "remapping target exits cleanly");
    close(commands[1]); close(replies[0]);
    puts("PASS: process VM inspection races with munmap and remap");
}

static int control_write(const char *path, const char *value) {
    int fd = open(path, O_WRONLY);
    if (fd < 0) return -1;
    int ok = exact_write(fd, value, strlen(value));
    close(fd);
    return ok ? 0 : -1;
}

static unsigned long long memory_current(void) {
    int fd = open("/tmp/inspection-cgroup/target/memory.current", O_RDONLY);
    if (fd < 0) return ULLONG_MAX;
    char text[64] = {0};
    ssize_t count = read(fd, text, sizeof(text) - 1);
    close(fd);
    return count > 0 ? strtoull(text, NULL, 10) : ULLONG_MAX;
}

static void cgroup_fault_policy(void) {
    check(mkdir("/tmp/inspection-cgroup", 0755) == 0, "create cgroup mountpoint");
    check(mount("none", "/tmp/inspection-cgroup", "cgroup2", 0, NULL) == 0,
          "mount cgroup2 inspection hierarchy");
    check(mkdir("/tmp/inspection-cgroup/target", 0755) == 0, "create target cgroup");
    check(control_write("/tmp/inspection-cgroup/target/memory.max", "33554432\n") == 0,
          "set remote target memory limit");
    size_t cow_size = (size_t)sysconf(_SC_PAGESIZE);
    unsigned char *cow_page = mmap(NULL, cow_size, PROT_READ | PROT_WRITE,
                                   MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    check(cow_page != MAP_FAILED, "allocate accounted fork shared page");
    if (cow_page == MAP_FAILED) return;
    cow_page[0] = 0xA5;
    int commands[2], replies[2];
    check(pipe(commands) == 0 && pipe(replies) == 0, "create cgroup test pipes");
    pid_t child = fork();
    if (child == 0) {
        close(commands[1]); close(replies[0]);
        char cmd;
        if (!exact_read(commands[0], &cmd, 1)) _exit(1);
        unsigned char *space = mmap(NULL, 80 * 1024 * 1024, PROT_READ | PROT_WRITE,
                                    MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        if (space == MAP_FAILED) _exit(2);
        space[0] = 0x63;
        uintptr_t ptr[2] = {(uintptr_t)space, (uintptr_t)cow_page};
        if (!exact_write(replies[1], ptr, sizeof(ptr)) || !exact_read(commands[0], &cmd, 1))
            _exit(3);
        _exit(space[0] == 0x64 && cow_page[0] == 0xA5 ? 0 : 4);
    }
    close(commands[0]); close(replies[1]);
    char pid_text[64];
    snprintf(pid_text, sizeof(pid_text), "%d\n", child);
    check(child > 0 && control_write("/tmp/inspection-cgroup/target/cgroup.procs", pid_text) == 0,
          "put remote target in accounted cgroup");
    char cmd = 'A';
    check(exact_write(commands[1], &cmd, 1), "start accounted target mapping");
    uintptr_t ptr[2] = {0};
    check(exact_read(replies[0], ptr, sizeof(ptr)), "receive accounted target mapping");
    unsigned long long before = memory_current();
    unsigned char byte = 0;
    struct iovec local = {&byte, 1}, remote = {(void *)ptr[0], 1};
    check(vm_copy(0, child, &local, 1, &remote, 1, 0) == 1 && byte == 0x63,
          "accounted resident pages remain inspectable");
    byte = 0x64;
    check(vm_copy(1, child, &local, 1, &remote, 1, 0) == 1,
          "accounted resident pages remain writable");
    remote.iov_base = (void *)(ptr[0] + 64 * 1024 * 1024);
    check(vm_copy(0, child, &local, 1, &remote, 1, 0) == -1 && errno == EFAULT,
          "remote read cannot fault uncharged pages into a limited target");
    check(vm_copy(1, child, &local, 1, &remote, 1, 0) == -1 && errno == EFAULT,
          "remote write cannot fault uncharged pages into a limited target");
    remote.iov_base = (void *)ptr[1];
    check(vm_copy(1, child, &local, 1, &remote, 1, 0) == -1 && errno == EFAULT,
          "remote COW cannot allocate uncharged pages in a limited target");
    check(cow_page[0] == 0xA5, "rejected accounted COW write preserves parent page");
    unsigned long long after = memory_current();
    check(before != ULLONG_MAX && before == after && after <= 33554432,
          "remote missing-page copies do not increase accounted resident memory");
    check(exact_write(commands[1], &cmd, 1) && child_exit(child) == 0,
          "limited target survives rejected remote faults");
    close(commands[1]); close(replies[0]);
    check(munmap(cow_page, cow_size) == 0, "release accounted fork shared page");
    check(rmdir("/tmp/inspection-cgroup/target") == 0, "remove target cgroup");
    check(umount("/tmp/inspection-cgroup") == 0, "unmount inspection hierarchy");
    puts("PASS: remote inspection preserves cgroup memory limits");
}

int main(int argc, char **argv) {
    if (argc == 2 && strcmp(argv[1], "--dumpability-exec") == 0)
        return prctl(PR_GET_DUMPABLE) == 1 ? 0 : 1;
    if (argc == 2 && strcmp(argv[1], "--inspection-exec-child") == 0) return 0;
    setvbuf(stdout, NULL, _IONBF, 0);
    alarm(120);
    dumpability();
    memory_vectors();
    permissions();
    teardown_races();
    remap_races();
    cgroup_fault_policy();
    if (failures) printf("FAIL: process inspection (%d checks)\n", failures);
    else puts("VINIX PROCESS INSPECTION: PASS");
    fflush(stdout);
    sync();
    reboot(RB_POWER_OFF);
    for (;;) pause();
}

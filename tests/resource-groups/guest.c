#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <pthread.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/epoll.h>
#include <sys/mman.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/swap.h>
#include <sys/sysmacros.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#define CHECK(x) do { if (!(x)) { printf("CGROUP FAIL line=%d errno=%d\n", __LINE__, errno); fflush(stdout); _exit(1); } } while (0)
#define ROOT "/tmp/groups"
static size_t page;
static char disk[64];

static uint64_t now(void) {
    struct timespec ts; CHECK(clock_gettime(CLOCK_MONOTONIC, &ts) == 0);
    return (uint64_t)ts.tv_sec * 1000000000 + ts.tv_nsec;
}
static int put(const char *path, const char *text) {
    int fd = open(path, O_WRONLY); if (fd < 0) return -1;
    ssize_t n = write(fd, text, strlen(text)); int saved = errno; close(fd); errno = saved;
    return n == (ssize_t)strlen(text) ? 0 : -1;
}
static int move(const char *group, pid_t pid) {
    char path[256], text[32]; snprintf(path, sizeof path, "%s/cgroup.procs", group);
    snprintf(text, sizeof text, "%d", pid); return put(path, text);
}
static int get(const char *path, char *text, size_t size) {
    int fd = open(path, O_RDONLY); CHECK(fd >= 0);
    ssize_t n = read(fd, text, size - 1); CHECK(n >= 0); text[n] = 0; close(fd); return (int)n;
}
static uint64_t number(const char *path) { char text[128]; get(path, text, sizeof text); return strtoull(text, NULL, 10); }
static uint64_t field(const char *path, const char *label) {
    char text[8192]; get(path, text, sizeof text); char *p = strstr(text, label); CHECK(p != NULL);
    return strtoull(p + strlen(label), NULL, 10);
}
static void wait_ok(pid_t pid) { int status; CHECK(waitpid(pid, &status, 0) == pid); CHECK(WIFEXITED(status) && WEXITSTATUS(status) == 0); }
static pid_t idle(const char *group) {
    pid_t pid = fork(); CHECK(pid >= 0);
    if (!pid) { CHECK(move(group, 0) == 0); for (;;) pause(); }
    for (int n = 0; n < 200; ++n) {
        char path[256], text[256], pid_text[32]; snprintf(path, sizeof path, "%s/cgroup.procs", group);
        get(path, text, sizeof text); snprintf(pid_text, sizeof pid_text, "%d\n", pid);
        if (strstr(text, pid_text)) return pid;
        usleep(10000);
    }
    CHECK(0); return -1;
}
static void stop(pid_t pid) { int status; CHECK(kill(pid, SIGKILL) == 0); CHECK(waitpid(pid, &status, 0) == pid); CHECK(WIFSIGNALED(status)); }
static void pass(const char *name) { printf("CGROUP %s PASS\n", name); fflush(stdout); }

static void migration(void) {
    CHECK(mkdir(ROOT "/parent", 0700) == 0); CHECK(mkdir(ROOT "/parent/a", 0700) == 0); CHECK(mkdir(ROOT "/parent/b", 0700) == 0);
    CHECK(put(ROOT "/parent/pids.max", "2") == 0); CHECK(put(ROOT "/parent/a/pids.max", "1") == 0); CHECK(put(ROOT "/parent/b/pids.max", "1") == 0);
    pid_t a = idle(ROOT "/parent/a"), b = idle(ROOT "/parent/b");
    CHECK(number(ROOT "/parent/pids.current") == 2);
    CHECK(move(ROOT "/parent/b", a) != 0 && errno == EAGAIN);
    CHECK(number(ROOT "/parent/a/pids.current") == 1 && number(ROOT "/parent/b/pids.current") == 1);
    CHECK(put(ROOT "/parent/b/pids.max", "2") == 0); CHECK(move(ROOT "/parent/b", a) == 0);
    CHECK(number(ROOT "/parent/pids.current") == 2 && number(ROOT "/parent/a/pids.current") == 0);
    CHECK(move(ROOT, a) == 0); stop(a); stop(b);
    CHECK(number(ROOT "/parent/pids.current") == 0);
    pass("migration-rollback-common-ancestor");
}

static pthread_barrier_t create_barrier;
static volatile int release_inner;
static void *inner(void *unused) { (void)unused; while (!__atomic_load_n(&release_inner, __ATOMIC_ACQUIRE)) usleep(1000); return NULL; }
static void *creator(void *unused) {
    (void)unused; pthread_t ids[8]; int n = 0; pthread_barrier_wait(&create_barrier);
    for (; n < 8; ++n) { int rc = pthread_create(&ids[n], NULL, inner, NULL); if (rc) { CHECK(rc == EAGAIN || rc == ENOMEM); break; } }
    while (!__atomic_load_n(&release_inner, __ATOMIC_ACQUIRE)) usleep(1000);
    for (int i = 0; i < n; ++i) CHECK(pthread_join(ids[i], NULL) == 0);
    return NULL;
}
static void pid_quota(void) {
    CHECK(mkdir(ROOT "/tasks", 0700) == 0); CHECK(put(ROOT "/tasks/pids.max", "9") == 0);
    pid_t pid = fork(); CHECK(pid >= 0);
    if (!pid) {
        CHECK(move(ROOT "/tasks", 0) == 0); CHECK(pthread_barrier_init(&create_barrier, NULL, 5) == 0);
        pthread_t creators[4]; for (int i = 0; i < 4; ++i) CHECK(pthread_create(&creators[i], NULL, creator, NULL) == 0);
        pthread_barrier_wait(&create_barrier); usleep(300000);
        CHECK(number(ROOT "/tasks/pids.current") == 9); CHECK(number(ROOT "/tasks/pids.peak") == 9);
        CHECK(fork() < 0 && errno == EAGAIN);
        __atomic_store_n(&release_inner, 1, __ATOMIC_RELEASE);
        for (int i = 0; i < 4; ++i) CHECK(pthread_join(creators[i], NULL) == 0);
        CHECK(number(ROOT "/tasks/pids.current") == 1);
        pthread_t recovered; CHECK(pthread_create(&recovered, NULL, inner, NULL) == 0); CHECK(pthread_join(recovered, NULL) == 0);
        CHECK(field(ROOT "/tasks/pids.events", "max ") > 0); _exit(0);
    }
    wait_ok(pid); CHECK(number(ROOT "/tasks/pids.current") == 0);
    pass("concurrent-pid-quota-recovery");
}

static void *exec_worker(void *unused) {
    (void)unused; char *args[] = {"/sbin/init", "--exec-ok", NULL}; execv(args[0], args); CHECK(0); return NULL;
}
static void exec_quota(void) {
    CHECK(mkdir(ROOT "/exec", 0700) == 0);
    for (int threaded = 0; threaded < 2; ++threaded) {
        printf("CGROUP exec-start threaded=%d\n", threaded); fflush(stdout);
        pid_t pid = fork(); CHECK(pid >= 0);
        if (!pid) {
            CHECK(move(ROOT "/exec", 0) == 0);
            CHECK(put(ROOT "/exec/pids.max", threaded ? "2" : "1") == 0);
            if (threaded) { pthread_t id; CHECK(pthread_create(&id, NULL, exec_worker, NULL) == 0); for (;;) pause(); }
            exec_worker(NULL); CHECK(0);
        }
        wait_ok(pid); CHECK(number(ROOT "/exec/pids.current") == 0);
    }
    pass("leader-and-worker-exec-at-limit");
}

static void kernel_quota(void) {
    CHECK(mkdir(ROOT "/kernel", 0700) == 0);
    pid_t pid = fork(); CHECK(pid >= 0);
    if (!pid) {
        CHECK(move(ROOT "/kernel", 0) == 0);
        int view = open(ROOT "/kernel/memory.current", O_RDONLY), limit = open(ROOT "/kernel/memory.max", O_WRONLY); CHECK(view >= 0 && limit >= 0);
        char text[128]; ssize_t bytes = pread(view, text, sizeof text - 1, 0); CHECK(bytes > 0); text[bytes] = 0;
        uint64_t base = strtoull(text, NULL, 10); snprintf(text, sizeof text, "%llu", (unsigned long long)(base + 512 * 1024));
        CHECK(write(limit, text, strlen(text)) == (ssize_t)strlen(text));
        int pipes[512][2], n = 0;
        for (; n < 512; ++n) { if (pipe(pipes[n]) != 0) { CHECK(errno == ENOMEM); break; } }
        CHECK(n > 4 && n < 512);
        for (int i = 0; i < n; ++i) { CHECK(close(pipes[i][0]) == 0); CHECK(close(pipes[i][1]) == 0); }
        CHECK(pipe(pipes[0]) == 0); close(pipes[0][0]); close(pipes[0][1]);
        CHECK(field(ROOT "/kernel/memory.events", "max ") > 0); close(view); close(limit); _exit(0);
    }
    wait_ok(pid); pass("kernel-memory-quota-recovery");
}

static void committed_memory(void) {
    CHECK(mkdir(ROOT "/memory", 0700) == 0);
    pid_t pid = fork(); CHECK(pid >= 0);
    if (!pid) {
        CHECK(move(ROOT "/memory", 0) == 0);
        const size_t pages = 64, length = pages * page;
        uint64_t before = number(ROOT "/memory/memory.current");
        unsigned char *p = mmap(NULL, length, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0); CHECK(p != MAP_FAILED);
        for (size_t i = 0; i < pages; ++i) p[i * page] = (unsigned char)(i + 19);
        uint64_t resident = number(ROOT "/memory/memory.current"); CHECK(resident >= before + length);
        uint64_t anon = field(ROOT "/memory/memory.stat", "anon ");
        CHECK(madvise(p, length, 21) == 0);
        uint64_t paged = number(ROOT "/memory/memory.current"); CHECK(field(ROOT "/memory/memory.stat", "anon ") + page >= anon);
        CHECK(number(ROOT "/memory/memory.swap.current") >= length);
        CHECK(mprotect(p, length, PROT_NONE) == 0); CHECK(field(ROOT "/memory/memory.stat", "anon ") + page >= anon);
        CHECK(mprotect(p, length, PROT_READ | PROT_WRITE) == 0);
        for (size_t i = 0; i < pages; ++i) CHECK(p[i * page] == (unsigned char)(i + 19));
        CHECK(number(ROOT "/memory/memory.swap.current") == 0);
        CHECK(munmap(p, length) == 0); CHECK(number(ROOT "/memory/memory.current") + length <= paged + 65536);
        _exit(0);
    }
    wait_ok(pid); pass("committed-pageout-protection-refault-unmap");
}

static void memory_recovery(void) {
    CHECK(mkdir(ROOT "/high", 0700) == 0);
    pid_t pid = fork(); CHECK(pid >= 0);
    if (!pid) {
        CHECK(move(ROOT "/high", 0) == 0); char text[64];
        snprintf(text, sizeof text, "%llu", (unsigned long long)(number(ROOT "/high/memory.current") + 8 * page));
        CHECK(put(ROOT "/high/memory.high", text) == 0);
        unsigned char *p = mmap(NULL, 64 * page, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0); CHECK(p != MAP_FAILED);
        uint64_t start = now(); for (size_t i = 0; i < 64; ++i) p[i * page] = 42;
        CHECK(now() - start >= 20000000); CHECK(field(ROOT "/high/memory.events", "high ") > 0);
        CHECK(munmap(p, 64 * page) == 0); _exit(0);
    }
    wait_ok(pid);
    CHECK(mkdir(ROOT "/oom", 0700) == 0);
    pid = fork(); CHECK(pid >= 0);
    if (!pid) {
        CHECK(move(ROOT "/oom", 0) == 0); char text[64];
        snprintf(text, sizeof text, "%llu", (unsigned long long)(number(ROOT "/oom/memory.current") + 512 * 1024));
        CHECK(put(ROOT "/oom/memory.max", text) == 0);
        unsigned char *p = mmap(NULL, 32 * 1024 * 1024, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0); CHECK(p != MAP_FAILED);
        for (size_t i = 0; i < 32 * 1024 * 1024 / page; ++i) p[i * page] = 43;
        _exit(77);
    }
    int status = -1; pid_t reaped = waitpid(pid, &status, 0);
    printf("CGROUP oom-victim pid=%d reaped=%d status=%#x\n", pid, reaped, status); fflush(stdout);
    CHECK(reaped == pid); CHECK(WIFSIGNALED(status) && WTERMSIG(status) == SIGKILL);
    CHECK(field(ROOT "/oom/memory.events", "oom_kill ") > 0);
    sleep(2);
    pid = fork(); CHECK(pid >= 0);
    if (!pid) {
        CHECK(move(ROOT "/oom", 0) == 0);
        unsigned char *p = mmap(NULL, 4 * page, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0); CHECK(p != MAP_FAILED);
        for (size_t i = 0; i < 4; ++i) p[i * page] = 44;
        CHECK(munmap(p, 4 * page) == 0); _exit(0);
    }
    wait_ok(pid); pass("memory-high-oom-and-quota-recovery");
}

static void memory_migration(void) {
    CHECK(mkdir(ROOT "/migrate-memory", 0700) == 0); CHECK(put(ROOT "/migrate-memory/memory.max", "262144") == 0);
    pid_t pid = fork(); CHECK(pid >= 0);
    if (!pid) {
        unsigned char *p = mmap(NULL, 2 * 1024 * 1024, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0); CHECK(p != MAP_FAILED);
        for (size_t i = 0; i < 2 * 1024 * 1024 / page; ++i) p[i * page] = 7;
        CHECK(move(ROOT "/migrate-memory", 0) < 0 && errno == EAGAIN);
        CHECK(number(ROOT "/migrate-memory/pids.current") == 0);
        CHECK(put(ROOT "/migrate-memory/memory.max", "max") == 0); CHECK(move(ROOT "/migrate-memory", 0) == 0);
        CHECK(field(ROOT "/migrate-memory/memory.stat", "anon ") >= 2 * 1024 * 1024);
        CHECK(munmap(p, 2 * 1024 * 1024) == 0); _exit(0);
    }
    wait_ok(pid); pass("memory-migration-admission-rollback");
}

static void oom_exit_race(void) {
    // Fast faulting victims can reach exit_group before the next timer IRQ.
    // Use a fresh controller each time so its previous-victim grace cannot
    // defer enforcement for a different process.
    for (int round = 0; round < 40; ++round) {
        char group[128], path[160]; snprintf(group, sizeof group, ROOT "/oom-race-%d", round);
        CHECK(mkdir(group, 0700) == 0);
        pid_t pid = fork(); CHECK(pid >= 0);
        if (!pid) {
            CHECK(move(group, 0) == 0); char text[64];
            snprintf(path, sizeof path, "%s/memory.current", group);
            // Allow initial mapping metadata, then exceed the anonymous quota.
            snprintf(text, sizeof text, "%llu", (unsigned long long)(number(path) + 128 * 1024));
            snprintf(path, sizeof path, "%s/memory.max", group); CHECK(put(path, text) == 0);
            unsigned char *p = mmap(NULL, 32 * 1024 * 1024, PROT_READ | PROT_WRITE,
                                    MAP_PRIVATE | MAP_ANONYMOUS, -1, 0); CHECK(p != MAP_FAILED);
            for (size_t i = 0; i < 64; ++i) p[i * page] = 45;
            _exit(77);
        }
        int status = -1; pid_t reaped = waitpid(pid, &status, 0);
        if (reaped != pid || status != SIGKILL) {
            printf("CGROUP oom-race round=%d pid=%d reaped=%d status=%#x\n", round, pid, reaped, status); fflush(stdout);
        }
        CHECK(reaped == pid); CHECK(WIFSIGNALED(status) && WTERMSIG(status) == SIGKILL);
        snprintf(path, sizeof path, "%s/memory.events", group); CHECK(field(path, "oom_kill ") > 0);
        CHECK(rmdir(group) == 0);
    }
    pass("oom-signal-wins-fast-fault-exit-race");
}

static void shared_child(void) {
    CHECK(move(ROOT "/shared", 0) == 0);
    uint64_t baseline = field(ROOT "/shared/memory.stat", "anon ");
    size_t length = 32 * page;
    unsigned char *shared = mmap(NULL, length, PROT_READ | PROT_WRITE, MAP_SHARED | MAP_ANONYMOUS, -1, 0);
    unsigned char *private = mmap(NULL, length, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    CHECK(shared != MAP_FAILED && private != MAP_FAILED);
    for (size_t i = 0; i < 32; ++i) { shared[i * page] = 11; private[i * page] = 22; }
    CHECK(madvise(private, length, 21) == 0);
    uint64_t swap = number(ROOT "/shared/memory.swap.current"); CHECK(swap >= length);
    int ready[2], release[2]; CHECK(pipe(ready) == 0 && pipe(release) == 0);
    pid_t other = fork(); CHECK(other >= 0);
    if (!other) {
        shared[0] = 99; CHECK(private[0] == 22); private[0] = 77;
        CHECK(write(ready[1], "r", 1) == 1); char c; CHECK(read(release[0], &c, 1) == 1); _exit(0);
    }
    char c; CHECK(read(ready[0], &c, 1) == 1); CHECK(shared[0] == 99 && private[0] == 22);
    uint64_t anon = field(ROOT "/shared/memory.stat", "anon ");
    printf("CGROUP shared anon=%llu baseline=%llu mapped=%zu\n", (unsigned long long)anon, (unsigned long long)baseline, 2 * length); fflush(stdout);
    CHECK(anon >= baseline + 2 * length && anon < baseline + 2 * length + 256 * 1024);
    CHECK(number(ROOT "/shared/memory.swap.current") <= swap);
    CHECK(write(release[1], "x", 1) == 1); wait_ok(other);
    close(ready[0]); close(ready[1]); close(release[0]); close(release[1]);
    CHECK(munmap(shared, length) == 0 && munmap(private, length) == 0); CHECK(number(ROOT "/shared/memory.swap.current") == 0);
    CHECK(put(ROOT "/shared/memory.swap.max", "0") == 0);
    private = mmap(NULL, length, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0); CHECK(private != MAP_FAILED);
    for (size_t i = 0; i < 32; ++i) private[i * page] = 55;
    CHECK(madvise(private, length, 21) == 0); CHECK(number(ROOT "/shared/memory.swap.current") == 0);
    for (size_t i = 0; i < 32; ++i) CHECK(private[i * page] == 55);
    CHECK(munmap(private, length) == 0); _exit(0);
}

static void shared_memory(void) {
    CHECK(mkdir(ROOT "/shared", 0700) == 0);
    pid_t pid = fork(); CHECK(pid >= 0);
    if (!pid) {
        char *args[] = {"/sbin/init", "--shared-check", NULL}; execv(args[0], args); CHECK(0);
    }
    wait_ok(pid); pass("shared-private-fork-and-swap-quota");
}

static void hierarchy_limits(void) {
    CHECK(mkdir(ROOT "/tree", 0700) == 0); CHECK(put(ROOT "/tree/cgroup.max.depth", "1") == 0);
    CHECK(put(ROOT "/tree/cgroup.max.descendants", "1") == 0); CHECK(mkdir(ROOT "/tree/a", 0700) == 0);
    CHECK(mkdir(ROOT "/tree/b", 0700) < 0 && errno == ENOSPC); CHECK(mkdir(ROOT "/tree/a/b", 0700) < 0 && errno == ENOSPC);
    CHECK(field(ROOT "/tree/cgroup.stat", "nr_descendants ") == 1); CHECK(rmdir(ROOT "/tree/a") == 0);
    CHECK(field(ROOT "/tree/cgroup.stat", "nr_descendants ") == 0); CHECK(mkdir(ROOT "/tree/b", 0700) == 0);
    pass("hierarchy-admission-and-removal-recovery");
}

static void cpu_quota(void) {
    CHECK(mkdir(ROOT "/cpu", 0700) == 0); CHECK(put(ROOT "/cpu/cpu.max", "1000 100000") == 0);
    pid_t pid = fork(); CHECK(pid >= 0);
    if (!pid) {
        CHECK(move(ROOT "/cpu", 0) == 0); uint64_t end = now() + 550000000; volatile uint64_t value = 1;
        while (now() < end) for (int i = 0; i < 1000; ++i) value = value * 6364136223846793005ULL + 1;
        _exit(value == 0 ? 1 : 0);
    }
    wait_ok(pid); CHECK(field(ROOT "/cpu/cpu.stat", "nr_throttled ") > 0);
    uint64_t usage = field(ROOT "/cpu/cpu.stat", "usage_usec "), user = field(ROOT "/cpu/cpu.stat", "user_usec "), system = field(ROOT "/cpu/cpu.stat", "system_usec ");
    printf("CGROUP cpu usage=%llu user=%llu system=%llu\n", (unsigned long long)usage, (unsigned long long)user, (unsigned long long)system); fflush(stdout);
    CHECK(usage > 0 && user > 0 && usage >= user + system && usage <= user + system + 1);
    CHECK(put(ROOT "/cpu/cpu.max", "max") == 0); pass("cpu-quota-and-workload-accounting");
}

static void io_quota(void) {
    CHECK(mkdir(ROOT "/io", 0700) == 0); CHECK(mkdir(ROOT "/io/child", 0700) == 0);
    struct stat st; CHECK(stat(disk, &st) == 0); char limit[160];
    snprintf(limit, sizeof limit, "%u:%u rbps=131072", major(st.st_rdev), minor(st.st_rdev)); CHECK(put(ROOT "/io/io.max", limit) == 0);
    snprintf(limit, sizeof limit, "%u:%u rbps=262144", major(st.st_rdev), minor(st.st_rdev)); CHECK(put(ROOT "/io/child/io.max", limit) == 0);
    pid_t pid = fork(); CHECK(pid >= 0);
    if (!pid) {
        int fd = open(disk, O_RDONLY); CHECK(fd >= 0); unsigned char buffer[65536];
        CHECK(move(ROOT "/io/child", 0) == 0); uint64_t start = now();
        CHECK(pread(fd, buffer, sizeof buffer, 16 * 1024 * 1024) == sizeof buffer);
        uint64_t elapsed = now() - start; printf("CGROUP io-duration=%llu\n", (unsigned long long)elapsed); fflush(stdout); CHECK(elapsed >= 450000000);
        close(fd); _exit(0);
    }
    wait_ok(pid); CHECK(field(ROOT "/io/io.stat", "rbytes=") >= 65536); CHECK(field(ROOT "/io/child/io.stat", "rios=") > 0);
    snprintf(limit, sizeof limit, "%u:%u rbps=max", major(st.st_rdev), minor(st.st_rdev)); CHECK(put(ROOT "/io/io.max", limit) == 0); CHECK(put(ROOT "/io/child/io.max", limit) == 0);
    snprintf(limit, sizeof limit, "%u:%u rbps=1", major(st.st_rdev), minor(st.st_rdev)); CHECK(put(ROOT "/io/io.max", limit) == 0);
    uint64_t before = field(ROOT "/io/io.stat", "rbytes=");
    pid = fork(); CHECK(pid >= 0);
    if (!pid) {
        int fd = open(disk, O_RDONLY); CHECK(fd >= 0); unsigned char buffer[4096]; CHECK(move(ROOT "/io/child", 0) == 0);
        CHECK(pread(fd, buffer, sizeof buffer, 17 * 1024 * 1024) == sizeof buffer); close(fd); _exit(0);
    }
    for (int i = 0; field(ROOT "/io/io.stat", "rbytes=") == before; ++i) { CHECK(i < 200); usleep(10000); }
    snprintf(limit, sizeof limit, "%u:%u rbps=max", major(st.st_rdev), minor(st.st_rdev)); CHECK(put(ROOT "/io/io.max", limit) == 0);
    wait_ok(pid); pass("io-hierarchy-accounting-limit-release");
}

static void pressure(void) {
    int a = open(ROOT "/tasks/resource.pressure", O_RDONLY), b = open(ROOT "/tasks/resource.pressure", O_RDONLY); CHECK(a >= 0 && b >= 0);
    int duplicate = dup(a); CHECK(duplicate >= 0); char text[768]; CHECK(pread(a, text, sizeof text, 0) > 0);
    struct pollfd pollfds[2] = {{duplicate, POLLIN | POLLPRI, 0}, {b, POLLIN | POLLPRI, 0}};
    CHECK(poll(pollfds, 2, 0) == 1 && pollfds[0].revents == 0 && pollfds[1].revents != 0);
    CHECK(pread(b, text, sizeof text, 0) > 0); int ep = epoll_create1(0); CHECK(ep >= 0);
    struct epoll_event wanted = {.events = EPOLLIN | EPOLLPRI, .data.fd = a}, ready;
    CHECK(epoll_ctl(ep, EPOLL_CTL_ADD, a, &wanted) == 0); CHECK(epoll_wait(ep, &ready, 1, 0) == 0);
    CHECK(put(ROOT "/tasks/pids.max", "0") == 0); CHECK(epoll_wait(ep, &ready, 1, 2500) == 1);
    CHECK(pread(duplicate, text, sizeof text - 1, 0) > 0); text[sizeof text - 1] = 0; CHECK(strstr(text, "pids_max 0\n"));
    CHECK(epoll_wait(ep, &ready, 1, 0) == 0);
    CHECK(put(ROOT "/tasks/cpu.max", "max 100000") == 0); CHECK(epoll_wait(ep, &ready, 1, 2500) == 1);
    CHECK(pread(a, text, sizeof text, 0) > 0); CHECK(epoll_wait(ep, &ready, 1, 0) == 0);
    CHECK(put(ROOT "/tasks/pids.max", "max") == 0);
    close(ep); close(duplicate); close(a); close(b);
    int descriptions[128]; for (int i = 0; i < 128; ++i) { descriptions[i] = open(ROOT "/tasks/resource.pressure", O_RDONLY); CHECK(descriptions[i] >= 0); }
    CHECK(open(ROOT "/tasks/resource.pressure", O_RDONLY) < 0 && errno == ENOSPC);
    for (int i = 0; i < 128; ++i) close(descriptions[i]);
    a = open(ROOT "/tasks/resource.pressure", O_RDONLY); CHECK(a >= 0); close(a);
    pass("independent-poll-epoll-pressure-recovery");
}

static void invalid_limits(void) {
    CHECK(put(ROOT "/tasks/pids.max", "18446744073709551615") < 0 && errno == EINVAL);
    CHECK(put(ROOT "/kernel/memory.max", "18446744073709551616") < 0 && errno == EINVAL);
    CHECK(put(ROOT "/kernel/memory.max", "18446744073709551615T") < 0 && errno == EINVAL);
    CHECK(put(ROOT "/cpu/cpu.max", "18446744073709551615 100000") < 0 && errno == EINVAL);
    CHECK(put(ROOT "/io/io.max", "0:1 rbps=2 rbps=3") < 0 && errno == EINVAL);
    CHECK(put(ROOT "/io/io.max", "4096:1 rbps=2") < 0 && errno == EINVAL);
    CHECK(put(ROOT "/io/io.max", "0:1 rbps=18446744073709551616") < 0 && errno == EINVAL);
    CHECK(put(ROOT "/io/io.max", "0:1 rubbish=2") < 0 && errno == EINVAL);
    CHECK(put(ROOT "/tasks/cgroup.procs", "1garbage") < 0 && errno == EINVAL);
    pass("invalid-overflow-limits");
}

static void controller_operations(void) {
    CHECK(put(ROOT "/tasks/pids.max", "9") == 0); CHECK(put(ROOT "/tasks/pids.max", "10") == 0);
    (void)number(ROOT "/tasks/pids.current"); (void)number(ROOT "/memory/memory.current");
    (void)field(ROOT "/memory/memory.stat", "anon "); (void)field(ROOT "/cpu/cpu.stat", "usage_usec ");
    char text[8192]; get(ROOT "/io/io.stat", text, sizeof text);
    int fd = open(ROOT "/tasks/resource.pressure", O_RDONLY); CHECK(fd >= 0); CHECK(read(fd, text, sizeof text) > 0); close(fd);
}

struct slab { unsigned long size[32], live[32]; int count; };
static struct slab slab_snapshot(void) {
    char text[8192]; get("/proc/slabinfo", text, sizeof text); struct slab result = {0};
    for (char *p = text; p && *p;) {
        unsigned long size, live, pages;
        if (sscanf(p, "size-%*u %lu %lu %lu", &size, &live, &pages) == 3) {
            CHECK(result.count < 32); result.size[result.count] = size; result.live[result.count++] = live;
        }
        p = strchr(p, '\n'); if (p) ++p;
    }
    CHECK(result.count > 0); return result;
}
static void allocation_recovery(void) {
    for (int i = 0; i < 300; ++i) controller_operations();
    sleep(7); struct slab before = slab_snapshot();
    for (int i = 0; i < 200; ++i) controller_operations();
    sleep(7); struct slab after = slab_snapshot(); CHECK(before.count == after.count);
    for (int i = 0; i < before.count; ++i) {
        CHECK(before.size[i] == after.size[i]);
        printf("CGROUP SLAB size=%lu delta=%ld\n", before.size[i], (long)after.live[i] - (long)before.live[i]);
        CHECK(after.live[i] <= before.live[i] + 8);
    }
    pass("controller-operation-allocation-recovery");
}

int main(int argc, char **argv) {
    if (argc > 1 && !strcmp(argv[1], "--exec-ok")) _exit(0);
    if (argc > 1 && !strcmp(argv[1], "--shared-check")) { page = (size_t)sysconf(_SC_PAGESIZE); shared_child(); _exit(0); }
    page = (size_t)sysconf(_SC_PAGESIZE); printf("CGROUP START page=%zu\n", page); fflush(stdout);
    CHECK(mkdir(ROOT, 0700) == 0); CHECK(mount("none", ROOT, "cgroup2", 0, NULL) == 0);
    const char *devices[] = {"/dev/vda", "/dev/sd0", "/dev/ata0", "/dev/nvme0n1"};
    for (size_t i = 0; i < sizeof devices / sizeof devices[0]; ++i) if (access(devices[i], F_OK) == 0) { strcpy(disk, devices[i]); break; }
    CHECK(disk[0]); for (int i = 0; swapon(disk, 0) != 0; ++i) { CHECK(errno == EAGAIN && i < 40); sleep(1); }
    migration(); pid_quota(); exec_quota(); kernel_quota(); committed_memory(); memory_recovery(); oom_exit_race(); memory_migration(); shared_memory();
    cpu_quota(); io_quota(); pressure(); hierarchy_limits(); invalid_limits(); allocation_recovery();
    CHECK(field(ROOT "/memory.stat", "anon ") > 0 && field(ROOT "/memory.stat", "kernel ") > 0);
    CHECK(swapoff(disk) == 0); printf("CGROUP PASS\n"); fflush(stdout); for (;;) pause();
}

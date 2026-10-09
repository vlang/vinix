#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <poll.h>
#include <sched.h>
#include <signal.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/epoll.h>
#include <sys/reboot.h>
#include <sys/signalfd.h>
#include <sys/syscall.h>
#include <sys/time.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#define CHECK(x) do { if (!(x)) { printf("PROCESS-SMP FAIL line=%d errno=%d: %s\n", __LINE__, errno, #x); _exit(1); } } while (0)
#define FUTEX_WAIT_PRIVATE 128
#define FUTEX_WAKE_PRIVATE 129
#ifndef PROCESS_TIMER_ONLY
#define PROCESS_TIMER_ONLY 0
#endif
static size_t page;
static uint64_t now(void) {
    struct timespec ts; CHECK(clock_gettime(CLOCK_MONOTONIC, &ts) == 0);
    return (uint64_t)ts.tv_sec * 1000000000 + ts.tv_nsec;
}
static void sleep_ms(int ms) {
    struct timespec ts = {ms / 1000, (ms % 1000) * 1000000};
    while (nanosleep(&ts, &ts) < 0) CHECK(errno == EINTR);
}
static void wait_ok(pid_t pid) {
    int status; CHECK(waitpid(pid, &status, 0) == pid);
    if (status) printf("PROCESS-SMP child=%d status=%x\n", pid, status);
    CHECK(WIFEXITED(status) && WEXITSTATUS(status) == 0);
}
static void pass(const char *name) { printf("PROCESS-SMP %s PASS\n", name); }
static void start_thread(pthread_t *thread, void *(*fn)(void *), void *arg) {
    uint64_t end = now() + 8000000000ULL;
    for (;;) {
        int rc = pthread_create(thread, NULL, fn, arg);
        if (!rc) return;
        printf("PROCESS-SMP thread-admission rc=%d\n", rc);
        CHECK((rc == EAGAIN || rc == ENOMEM) && now() < end);
        sleep_ms(10);
    }
}

struct clone_state { _Atomic int value, ready, release; uintptr_t heap; void *created, *removed; int exec; };
static int vm_child(void *argument) {
    struct clone_state *s = argument;
    s->heap = syscall(SYS_brk, 0);
    CHECK(syscall(SYS_brk, s->heap + page) == (long)(s->heap + page));
    s->created = mmap(NULL, page, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    CHECK(s->created != MAP_FAILED); memset(s->created, 0x5a, page);
    CHECK(munmap(s->removed, page) == 0);
    atomic_store(&s->value, 42);
    atomic_store(&s->ready, 1);
    if (s->exec) {
        char *argv[] = {"/sbin/init", "--exec-ok", NULL};
        execv(argv[0], argv); _exit(94);
    }
    while (!atomic_load(&s->release)) {
        int rc = syscall(SYS_futex, &s->release, FUTEX_WAIT_PRIVATE, 0, NULL, NULL, 0);
        CHECK(rc == 0 || (rc == -1 && (errno == EAGAIN || errno == EINTR)));
    }
    return 0;
}
static int empty_child(void *unused) { (void)unused; return 0; }
static void clone_vm(void) {
    char *stack = mmap(NULL, 1024 * 1024, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    struct clone_state *s = mmap(NULL, page, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    CHECK(stack != MAP_FAILED && s != MAP_FAILED);
    errno = 0;
    CHECK(clone(empty_child, stack + 1024 * 1024, CLONE_SIGHAND | SIGCHLD, NULL) == -1 && errno == EINVAL);
    errno = 0;
    CHECK(clone(empty_child, stack + 1024 * 1024, CLONE_THREAD | CLONE_VM, NULL) == -1 && errno == EINVAL);
    CHECK(clone(empty_child, stack + 1024 * 1024, CLONE_FILES | SIGCHLD, NULL) == -1 && errno == ENOTSUP);
    CHECK(clone(empty_child, stack + 1024 * 1024, CLONE_VM | CLONE_SIGHAND | SIGCHLD, NULL) == -1 && errno == ENOTSUP);
    for (int exec = 0; exec < 2; ++exec) {
        memset(s, 0, page); s->exec = exec;
        s->removed = mmap(NULL, page, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        CHECK(s->removed != MAP_FAILED);
        uintptr_t heap = syscall(SYS_brk, 0);
        pid_t child = clone(vm_child, stack + 1024 * 1024, CLONE_VM | SIGCHLD, s);
        CHECK(child > 0);
        if (!exec) {
            uint64_t end = now() + 3000000000ULL;
            while (!atomic_load(&s->ready) && now() < end) sched_yield();
            CHECK(atomic_load(&s->ready) == 1 && atomic_load(&s->value) == 42);
            CHECK(s->heap == heap && syscall(SYS_brk, 0) == (long)(heap + page));
            atomic_store(&s->release, 1);
            CHECK(syscall(SYS_futex, &s->release, FUTEX_WAKE_PRIVATE, 1, NULL, NULL, 0) >= 0);
        }
        wait_ok(child);
        CHECK(atomic_load(&s->value) == 42);
        CHECK(*(unsigned char *)s->created == 0x5a);
        unsigned char resident; CHECK(mincore(s->removed, page, &resident) == -1 && errno == ENOMEM);
        CHECK(munmap(s->created, page) == 0);
        CHECK(syscall(SYS_brk, heap) == (long)heap);
    }
    CHECK(munmap(s, page) == 0 && munmap(stack, 1024 * 1024) == 0);
    pass("clone-vm-shared-break-exec-exit");
}

static int vfork_child(void *argument) {
    _Atomic int *value = argument;
    sleep_ms(60); atomic_store(value, 123); return 0;
}
static int vfork_exec_child(void *argument) {
    _Atomic int *value = argument;
    atomic_store(value, 124);
    char *argv[] = {"/sbin/init", "--exec-ok", NULL};
    execv(argv[0], argv); return 95;
}
static void vfork_semantics(void) {
    char *stack = mmap(NULL, 1024 * 1024, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    _Atomic int *value = mmap(NULL, page, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    CHECK(stack != MAP_FAILED && value != MAP_FAILED);
    for (int i = 0; i < 40; ++i) {
        atomic_store(value, 0); uint64_t start = now();
        pid_t child = clone(vfork_child, stack + 1024 * 1024, CLONE_VM | CLONE_VFORK | SIGCHLD, value);
        CHECK(child > 0 && atomic_load(value) == 123 && now() - start >= 50000000ULL);
        wait_ok(child);
        atomic_store(value, 0);
        child = clone(vfork_exec_child, stack + 1024 * 1024, CLONE_VM | CLONE_VFORK | SIGCHLD, value);
        CHECK(child > 0 && atomic_load(value) == 124); wait_ok(child);
    }
    // libc's vfork wrapper uses the caller's stack and the dedicated x86 syscall.
    // Keep the child to async-signal-safe exit; do not alter its parent's frame.
    pid_t child = vfork(); CHECK(child >= 0); if (!child) _exit(0); wait_ok(child);
    munmap(value, page); munmap(stack, 1024 * 1024);
    pass("vfork-parent-suspension-and-release");
}

static int survivor(void *argument) {
    _Atomic int *value = argument;
    atomic_store(value, getpid());
    sleep_ms(200);
    // The creator has already died and released its ownership of this map.
    atomic_store(value + 1, 765); return 0;
}
static void vfork_parent_death(void) {
    _Atomic int *value = mmap(NULL, page, PROT_READ | PROT_WRITE, MAP_SHARED | MAP_ANONYMOUS, -1, 0);
    CHECK(value != MAP_FAILED);
    for (int i = 0; i < 30; ++i) {
        atomic_store(value, 0); atomic_store(value + 1, 0);
        pid_t parent = fork(); CHECK(parent >= 0);
        if (!parent) {
            char *stack = mmap(NULL, 1024 * 1024, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
            CHECK(stack != MAP_FAILED);
            CHECK(clone(survivor, stack + 1024 * 1024, CLONE_VM | CLONE_VFORK | SIGCHLD, value) > 0);
            _exit(97); // The parent must still be suspended when killed below.
        }
        uint64_t end = now() + 3000000000ULL;
        while (!atomic_load(value) && now() < end) sched_yield();
        CHECK(atomic_load(value) > 0);
        CHECK(kill(parent, SIGKILL) == 0);
        int status; CHECK(waitpid(parent, &status, 0) == parent);
        CHECK(WIFSIGNALED(status) && WTERMSIG(status) == SIGKILL);
        wait_ok(atomic_load(value)); CHECK(atomic_load(value + 1) == 765);
    }
    CHECK(munmap(value, page) == 0); pass("vfork-killed-parent-shared-map-survives");
}

static int pipes[2];
static pthread_mutex_t cancel_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t cancel_cond = PTHREAD_COND_INITIALIZER;
static _Atomic int entered, cleaned;
static void cancel_cleanup(void *arg) {
    if (arg) CHECK(pthread_mutex_unlock(&cancel_lock) == 0);
    atomic_fetch_add(&cleaned, 1);
}
static void *cancel_worker(void *argument) {
    int mode = (int)(intptr_t)argument;
    if (mode == 2) CHECK(pthread_mutex_lock(&cancel_lock) == 0);
    pthread_cleanup_push(cancel_cleanup, mode == 2 ? &cancel_lock : NULL);
    atomic_store(&entered, 1);
    if (mode == 0) { char c; CHECK(read(pipes[0], &c, 1) == 1); }
    else if (mode == 1) sleep_ms(30000);
    else CHECK(pthread_cond_wait(&cancel_cond, &cancel_lock) == 0);
    pthread_cleanup_pop(1);
    return NULL;
}
static void cancellation(void) {
    CHECK(pipe(pipes) == 0); atomic_store(&cleaned, 0);
    for (int i = 0; i < 60; ++i) {
        atomic_store(&entered, 0); pthread_t t;
        CHECK(pthread_create(&t, NULL, cancel_worker, (void *)(intptr_t)(i % 3)) == 0);
        while (!atomic_load(&entered)) sched_yield();
        sleep_ms(2); CHECK(pthread_cancel(t) == 0);
        void *result; CHECK(pthread_join(t, &result) == 0 && result == PTHREAD_CANCELED);
    }
    CHECK(atomic_load(&cleaned) == 60);
    CHECK(pthread_mutex_trylock(&cancel_lock) == 0); pthread_mutex_unlock(&cancel_lock);
    close(pipes[0]); close(pipes[1]); pass("cancellation-read-sleep-condvar-cleanup");
}

static pthread_mutex_t robust;
static void *robust_owner(void *unused) { (void)unused; CHECK(pthread_mutex_lock(&robust) == 0); return NULL; }
static void robust_futex(void) {
    pthread_mutexattr_t attr; CHECK(pthread_mutexattr_init(&attr) == 0);
    CHECK(pthread_mutexattr_setrobust(&attr, PTHREAD_MUTEX_ROBUST) == 0);
    CHECK(pthread_mutex_init(&robust, &attr) == 0); pthread_mutexattr_destroy(&attr);
    for (int i = 0; i < 60; ++i) {
        pthread_t t; CHECK(pthread_create(&t, NULL, robust_owner, NULL) == 0); CHECK(pthread_join(t, NULL) == 0);
        CHECK(pthread_mutex_lock(&robust) == EOWNERDEAD);
        CHECK(pthread_mutex_consistent(&robust) == 0); CHECK(pthread_mutex_unlock(&robust) == 0);
    }
    CHECK(pthread_mutex_destroy(&robust) == 0); pass("robust-owner-death-and-cleartid-join");
}

static _Atomic int futex_word, futex_ready;
static void *futex_waiter(void *unused) {
    (void)unused; atomic_fetch_add(&futex_ready, 1);
    while (!atomic_load(&futex_word)) {
        int rc = syscall(SYS_futex, &futex_word, FUTEX_WAIT_PRIVATE, 0, NULL, NULL, 0);
        CHECK(rc == 0 || (rc == -1 && (errno == EAGAIN || errno == EINTR)));
    }
    return NULL;
}
static void futex_cow(void) {
    for (int batch = 0; batch < 20; ++batch) {
        atomic_store(&futex_ready, 0); atomic_store(&futex_word, 0); pthread_t threads[8];
        for (int i = 0; i < 8; ++i) start_thread(&threads[i], futex_waiter, NULL);
        while (atomic_load(&futex_ready) < 8) sched_yield();
        // The parent's next write breaks COW while its waiters retain their keys.
        pid_t child = fork(); CHECK(child >= 0); if (!child) _exit(0); wait_ok(child);
        atomic_store(&futex_word, 1);
        CHECK(syscall(SYS_futex, &futex_word, FUTEX_WAKE_PRIVATE, 8, NULL, NULL, 0) >= 0);
        for (int i = 0; i < 8; ++i) CHECK(pthread_join(threads[i], NULL) == 0);
    }
    struct timespec timeout = {0, 1000000}; atomic_store(&futex_word, 0);
    CHECK(syscall(SYS_futex, &futex_word, FUTEX_WAIT_PRIVATE, 0, &timeout, NULL, 0) == -1 && errno == ETIMEDOUT);
    pass("futex-cow-wake-timeout");
}

static sigset_t usr1;
static void *signal_waiter(void *unused) {
    (void)unused; atomic_store(&entered, 1);
    struct timespec timeout = {3, 0}; siginfo_t info;
    CHECK(sigtimedwait(&usr1, &info, &timeout) == SIGUSR1 && info.si_signo == SIGUSR1);
    return NULL;
}
static void signals(void) {
    sigemptyset(&usr1); sigaddset(&usr1, SIGUSR1); CHECK(pthread_sigmask(SIG_BLOCK, &usr1, NULL) == 0);
    for (int i = 0; i < 60; ++i) {
        atomic_store(&entered, 0); pthread_t t; CHECK(pthread_create(&t, NULL, signal_waiter, NULL) == 0);
        while (!atomic_load(&entered)) sched_yield();
        CHECK((i % 2 ? pthread_kill(t, SIGUSR1) : kill(getpid(), SIGUSR1)) == 0);
        CHECK(pthread_join(t, NULL) == 0);
    }
    CHECK(pthread_sigmask(SIG_UNBLOCK, &usr1, NULL) == 0); pass("thread-and-process-directed-signal-waits");
}

static int signal_fd;
static void *signal_fd_sender(void *unused) {
    (void)unused; sleep_ms(20); CHECK(kill(getpid(), SIGUSR1) == 0); return NULL;
}
static int signal_exec_child(void *unused) {
    (void)unused; char *argv[] = {"/sbin/init", "--signal-worker-exec", NULL};
    execv(argv[0], argv); return 99;
}
static void *pending_signal_worker(void *argument) {
    int mode = (int)(intptr_t)argument;
    struct timespec zero = {0, 0}; siginfo_t info;
    if (mode == 0) {
        CHECK(sigtimedwait(&usr1, &info, &zero) == SIGUSR1 && info.si_signo == SIGUSR1);
        CHECK(sigtimedwait(&usr1, &info, &zero) == -1 && errno == EAGAIN);
    } else if (mode == 1) {
        // Neither sigwait nor signalfd may steal the creator's private signal.
        CHECK(sigtimedwait(&usr1, &info, &zero) == -1 && errno == EAGAIN);
        struct pollfd fd = {signal_fd, POLLIN, 0}; CHECK(poll(&fd, 1, 0) == 0);
        int ep = epoll_create1(EPOLL_CLOEXEC); CHECK(ep >= 0);
        struct epoll_event watched = {.events = EPOLLIN}, ready;
        CHECK(epoll_ctl(ep, EPOLL_CTL_ADD, signal_fd, &watched) == 0);
        CHECK(epoll_wait(ep, &ready, 1, 0) == 0); close(ep);
        struct signalfd_siginfo fdinfo;
        CHECK(read(signal_fd, &fdinfo, sizeof fdinfo) == -1 && errno == EAGAIN);
    } else if (mode == 2) {
        CHECK(syscall(SYS_rt_sigtimedwait, &usr1, UINTPTR_MAX, &zero, 8) == -1 && errno == EFAULT);
    } else {
        struct signalfd_siginfo fdinfo;
        struct pollfd fd = {signal_fd, POLLIN, 0}; CHECK(poll(&fd, 1, 0) == 1 && fd.revents == POLLIN);
        CHECK(read(signal_fd, &fdinfo, sizeof fdinfo) == sizeof fdinfo && fdinfo.ssi_signo == SIGUSR1);
    }
    return NULL;
}
static void pending_signal_ownership(void) {
    sigemptyset(&usr1); sigaddset(&usr1, SIGUSR1);
    CHECK(pthread_sigmask(SIG_BLOCK, &usr1, NULL) == 0);
    signal_fd = signalfd(-1, &usr1, SFD_NONBLOCK | SFD_CLOEXEC); CHECK(signal_fd >= 0);
    struct timespec zero = {0, 0}; siginfo_t info; pthread_t t;
    // Queue before a waiter exists, then create a sibling to consume it.
    for (int i = 0; i < 40; ++i) {
        CHECK(kill(getpid(), SIGUSR1) == 0);
        start_thread(&t, pending_signal_worker, NULL); CHECK(pthread_join(t, NULL) == 0);
    }
    CHECK(pthread_kill(pthread_self(), SIGUSR1) == 0);
    start_thread(&t, pending_signal_worker, (void *)1); CHECK(pthread_join(t, NULL) == 0);
    struct pollfd fd = {signal_fd, POLLIN, 0}; CHECK(poll(&fd, 1, 0) == 1 && fd.revents == POLLIN);
    CHECK(kill(getpid(), SIGUSR1) == 0);
    start_thread(&t, pending_signal_worker, NULL); CHECK(pthread_join(t, NULL) == 0);
    CHECK(sigtimedwait(&usr1, &info, &zero) == SIGUSR1);
    CHECK(kill(getpid(), SIGUSR1) == 0);
    start_thread(&t, pending_signal_worker, (void *)2); CHECK(pthread_join(t, NULL) == 0);
    start_thread(&t, pending_signal_worker, NULL); CHECK(pthread_join(t, NULL) == 0);
    CHECK(kill(getpid(), SIGUSR1) == 0);
    start_thread(&t, pending_signal_worker, (void *)3); CHECK(pthread_join(t, NULL) == 0);
    CHECK(kill(getpid(), SIGUSR1) == 0);
    pid_t child = fork(); CHECK(child >= 0);
    if (!child) { CHECK(sigtimedwait(&usr1, &info, &zero) == -1 && errno == EAGAIN); _exit(0); }
    wait_ok(child); CHECK(sigtimedwait(&usr1, &info, &zero) == SIGUSR1);
    child = fork(); CHECK(child >= 0);
    if (!child) {
        CHECK(fcntl(signal_fd, F_SETFL, 0) == 0);
        start_thread(&t, signal_fd_sender, NULL);
        struct signalfd_siginfo fdinfo;
        CHECK(read(signal_fd, &fdinfo, sizeof fdinfo) == sizeof fdinfo && fdinfo.ssi_signo == SIGUSR1);
        CHECK(pthread_join(t, NULL) == 0); _exit(0);
    }
    wait_ok(child);
    child = fork(); CHECK(child >= 0);
    if (!child) {
        CHECK(kill(getpid(), SIGUSR1) == 0);
        char *argv[] = {"/sbin/init", "--signal-exec", NULL}; execv(argv[0], argv); _exit(99);
    }
    wait_ok(child); close(signal_fd);
    char *stack = mmap(NULL, 1024 * 1024, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    CHECK(stack != MAP_FAILED);
    for (int i = 0; i < 20; ++i) {
        child = clone(signal_exec_child, stack + 1024 * 1024, CLONE_VM | CLONE_VFORK | SIGCHLD, NULL);
        CHECK(child > 0 && kill(child, SIGUSR1) == 0); wait_ok(child);
    }
    CHECK(munmap(stack, 1024 * 1024) == 0);
    CHECK(pthread_sigmask(SIG_UNBLOCK, &usr1, NULL) == 0);
    pass("pending-process-signals-private-siblings-efault-fork-exec");
}

static void *arm_real_timer(void *unused) {
    (void)unused; struct itimerval timer = {{0, 0}, {2, 0}};
    CHECK(setitimer(ITIMER_REAL, &timer, NULL) == 0); return NULL;
}
static void timer_ownership(void) {
    pid_t child = fork(); CHECK(child >= 0);
    if (!child) {
        sigset_t mask; sigemptyset(&mask); sigaddset(&mask, SIGALRM);
        CHECK(pthread_sigmask(SIG_BLOCK, &mask, NULL) == 0);
        pthread_t t; start_thread(&t, arm_real_timer, NULL); CHECK(pthread_join(t, NULL) == 0);
        struct itimerval timer; CHECK(getitimer(ITIMER_REAL, &timer) == 0);
        CHECK(timer.it_value.tv_sec || timer.it_value.tv_usec);
        pid_t copy = fork(); CHECK(copy >= 0);
        if (!copy) { CHECK(getitimer(ITIMER_REAL, &timer) == 0); CHECK(!timer.it_value.tv_sec && !timer.it_value.tv_usec); _exit(0); }
        wait_ok(copy);
        char *argv[] = {"/sbin/init", "--timer-exec", NULL}; execv(argv[0], argv); _exit(98);
    }
    wait_ok(child);
    // All 40 processes must retain independent timers; no silent 32-slot cap.
    int ready[2], release[2]; CHECK(pipe(ready) == 0 && pipe(release) == 0); pid_t children[40];
    for (int i = 0; i < 40; ++i) {
        children[i] = fork(); CHECK(children[i] >= 0);
        if (!children[i]) {
            close(ready[0]); close(release[1]);
            struct itimerval timer = {{0, 0}, {30, 0}};
            CHECK(setitimer(ITIMER_REAL, &timer, NULL) == 0);
            CHECK(getitimer(ITIMER_REAL, &timer) == 0 && timer.it_value.tv_sec > 0);
            CHECK(write(ready[1], "r", 1) == 1); char c; CHECK(read(release[0], &c, 1) == 1); _exit(0);
        }
    }
    close(ready[1]); close(release[0]);
    for (int i = 0; i < 40; ++i) { char c; CHECK(read(ready[0], &c, 1) == 1); }
    char done[40]; memset(done, 'x', sizeof done); CHECK(write(release[1], done, sizeof done) == sizeof done);
    close(ready[0]); close(release[1]); for (int i = 0; i < 40; ++i) wait_ok(children[i]);
    struct itimerval disarmed = {{0, 30000}, {0, 0}}, value;
    CHECK(setitimer(ITIMER_REAL, &disarmed, NULL) == 0 && getitimer(ITIMER_REAL, &value) == 0);
    CHECK(!value.it_value.tv_sec && !value.it_value.tv_usec && value.it_interval.tv_usec == 30000);
    pass("real-timer-thread-exit-exec-fork-and-capacity");
}

static _Atomic int yielding;
static volatile sig_atomic_t alarms;
static void count_alarm(int signo) { (void)signo; ++alarms; }
static void *yield_worker(void *unused) { (void)unused; while (atomic_load(&yielding)) sched_yield(); return NULL; }
static void timer_phase(void) {
    pthread_t workers[4]; atomic_store(&yielding, 1);
    for (int i = 0; i < 4; ++i) start_thread(&workers[i], yield_worker, NULL);
    struct sigaction action = {.sa_handler = count_alarm}, old; sigemptyset(&action.sa_mask);
    CHECK(sigaction(SIGALRM, &action, &old) == 0); alarms = 0;
    uint64_t start = now(); alarm(1);
    while (!alarms && now() - start < 3000000000ULL) sleep_ms(10);
    uint64_t elapsed = now() - start;
    CHECK(alarms == 1 && elapsed >= 900000000ULL && elapsed <= 2000000000ULL);
    alarms = 0; struct itimerval timer = {{0, 50000}, {0, 50000}}, off = {{0, 0}, {0, 0}};
    start = now(); CHECK(setitimer(ITIMER_REAL, &timer, NULL) == 0);
    while (now() - start < 1000000000ULL) sleep_ms(10);
    CHECK(setitimer(ITIMER_REAL, &off, NULL) == 0);
    int count = alarms; printf("PROCESS-SMP interval-expirations=%d\n", count);
    CHECK(count >= 10 && count <= 25); CHECK(sigaction(SIGALRM, &old, NULL) == 0);
    atomic_store(&yielding, 0); for (int i = 0; i < 4; ++i) CHECK(pthread_join(workers[i], NULL) == 0);
    pass("real-timer-smp-deadlines-and-periodic-phase");
}

struct slab { unsigned long bytes, objects; };
static unsigned long free_kib(void) {
    FILE *f = fopen("/proc/meminfo", "r"); CHECK(f != NULL);
    char line[256]; unsigned long free = 0;
    while (fgets(line, sizeof line, f)) if (sscanf(line, "MemFree: %lu kB", &free) == 1) break;
    fclose(f); CHECK(free > 0); return free;
}
static void track_allocations(int dump) {
    FILE *f = fopen(dump ? "/proc/allocsites" : "/proc/allocstart", "r");
    if (!f) return;
    char line[1024]; while (fgets(line, sizeof line, f)) if (dump) printf("PERF-SITE process-smp %s", line);
    fclose(f);
}
static int slabs(struct slab *out) {
    FILE *f = fopen("/proc/slabinfo", "r"); CHECK(f != NULL);
    char line[256]; int n = 0;
    while (fgets(line, sizeof line, f)) {
        unsigned long size, total, used;
        if (sscanf(line, "size-%lu %*u %lu %lu", &size, &used, &total) == 3) {
            CHECK(n < 32); out[n++] = (struct slab){size, used};
        }
    }
    fclose(f); return n;
}
static void empty_poll_churn(void) {
    struct slab before[32], after[32]; int n = slabs(before); CHECK(n > 0);
    for (int batch = 0; batch < 2; ++batch) {
        for (int i = 0; i < 200; ++i) CHECK(poll(NULL, 0, 1) == 0);
        CHECK(slabs(after) == n);
        for (int i = 0; i < n; ++i) {
            long delta = (long)after[i].objects - (long)before[i].objects;
            printf("PROCESS-SMP POLL batch=%d class=%lu delta=%ld\n", batch + 1, after[i].bytes, delta);
            CHECK(delta <= 2);
        }
        memcpy(before, after, sizeof before);
    }
    pass("empty-poll-wait-events-return-all-slab-classes");
}
static void signal_fd_churn(void) {
    sigset_t mask; sigemptyset(&mask); sigaddset(&mask, SIGUSR1);
    CHECK(pthread_sigmask(SIG_BLOCK, &mask, NULL) == 0);
    int fd = signalfd(-1, &mask, SFD_NONBLOCK | SFD_CLOEXEC); CHECK(fd >= 0);
    struct slab before[32], after[32]; int n = slabs(before); CHECK(n > 0);
    for (int batch = 0; batch < 2; ++batch) {
        for (int i = 0; i < 200; ++i) {
            CHECK(kill(getpid(), SIGUSR1) == 0);
            struct pollfd watched = {fd, POLLIN, 0}; CHECK(poll(&watched, 1, 0) == 1 && watched.revents == POLLIN);
            struct signalfd_siginfo info;
            CHECK(read(fd, &info, sizeof info) == sizeof info && info.ssi_signo == SIGUSR1);
        }
        CHECK(slabs(after) == n);
        for (int i = 0; i < n; ++i) {
            long delta = (long)after[i].objects - (long)before[i].objects;
            printf("PROCESS-SMP SIGNALFD batch=%d class=%lu delta=%ld\n", batch + 1, after[i].bytes, delta);
            CHECK(delta <= 2);
        }
        memcpy(before, after, sizeof before);
    }
    close(fd); CHECK(pthread_sigmask(SIG_UNBLOCK, &mask, NULL) == 0);
    pass("signalfd-process-send-poll-read-return-all-slab-classes");
}
static void cohort(int count) {
    for (int i = 0; i < count; ++i) {
        pid_t child = fork(); CHECK(child >= 0);
        if (!child) { char *argv[] = {"/sbin/init", "--exec-ok", NULL}; execv(argv[0], argv); _exit(96); }
        wait_ok(child);
    }
}
static void churn(void) {
    struct slab before[32], after[32];
    cohort(100); sleep_ms(6500); track_allocations(0);
    int n = slabs(before); CHECK(n > 0); CHECK(slabs(after) == n);
    long control[32]; for (int i = 0; i < n; ++i) control[i] = (long)after[i].objects - (long)before[i].objects;
    memcpy(before, after, sizeof before);
    unsigned long physical_before = free_kib();
    for (int batch = 0; batch < 3; ++batch) {
        cohort(100); sleep_ms(6500); CHECK(slabs(after) == n);
        unsigned long physical_after = free_kib();
        printf("PROCESS-SMP MEMORY cohort=%d free-kib-delta=%ld\n", batch + 1, (long)physical_after - (long)physical_before);
        CHECK(physical_after + 1024 >= physical_before); physical_before = physical_after;
        for (int i = 0; i < n; ++i) {
            long delta = (long)after[i].objects - (long)before[i].objects;
            printf("PROCESS-SMP SLAB cohort=%d class=%lu delta=%ld control=%ld\n", batch + 1, after[i].bytes, delta, control[i]);
            CHECK(delta <= (control[i] > 0 ? control[i] : 0) + 2);
        }
        memcpy(before, after, sizeof before);
    }
    track_allocations(1);
    pass("fork-exec-exit-churn-all-slab-classes");
}

int main(int argc, char **argv) {
    setvbuf(stdout, NULL, _IONBF, 0); setvbuf(stderr, NULL, _IONBF, 0);
    if (argc > 1 && !strcmp(argv[1], "--exec-ok")) return 0;
    if (argc > 1 && !strcmp(argv[1], "--signal-exec")) {
        sigset_t mask; sigemptyset(&mask); sigaddset(&mask, SIGUSR1);
        struct timespec zero = {0, 0}; CHECK(sigtimedwait(&mask, NULL, &zero) == SIGUSR1); return 0;
    }
    if (argc > 1 && !strcmp(argv[1], "--signal-worker-exec")) {
        sigemptyset(&usr1); sigaddset(&usr1, SIGUSR1);
        pthread_t t; start_thread(&t, signal_waiter, NULL); CHECK(pthread_join(t, NULL) == 0); return 0;
    }
    if (argc > 1 && !strcmp(argv[1], "--timer-exec")) {
        struct itimerval timer; CHECK(getitimer(ITIMER_REAL, &timer) == 0);
        CHECK(timer.it_value.tv_sec || timer.it_value.tv_usec);
        sigset_t mask; sigemptyset(&mask); sigaddset(&mask, SIGALRM);
        struct timespec timeout = {4, 0}; CHECK(sigtimedwait(&mask, NULL, &timeout) == SIGALRM); return 0;
    }
    page = sysconf(_SC_PAGESIZE);
    printf("PROCESS-SMP START cpus=%ld page=%zu\n", sysconf(_SC_NPROCESSORS_ONLN), page);
    CHECK(sysconf(_SC_NPROCESSORS_ONLN) >= 2);
    if (!PROCESS_TIMER_ONLY) {
        clone_vm(); vfork_semantics(); vfork_parent_death(); cancellation(); robust_futex(); futex_cow(); signals();
        pending_signal_ownership();
    }
    timer_ownership(); timer_phase(); if (!PROCESS_TIMER_ONLY) { empty_poll_churn(); signal_fd_churn(); churn(); }
    puts("PROCESS-SMP PASS"); sync(); reboot(RB_POWER_OFF); return 0;
}

#define _GNU_SOURCE
#include <errno.h>
#include <pthread.h>
#include <signal.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/reboot.h>
#include <sys/resource.h>
#include <sys/syscall.h>
#include <sys/time.h>
#include <sys/times.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

static volatile sig_atomic_t virtual_count, prof_count, xcpu_count;
static atomic_int stop_worker;
static volatile unsigned long computation;
static int failures;

static void signal_seen(int signal) {
    if (signal == SIGVTALRM) virtual_count++;
    if (signal == SIGPROF) {
        prof_count++;
        // An asynchronously delivered handler must restore even caller-saved
        // SIMD registers used by the interrupted instruction stream.
#if defined(__aarch64__)
        __asm__ volatile("movi v31.16b, #0" ::: "v31");
#elif defined(__x86_64__)
        __asm__ volatile("pxor %%xmm15, %%xmm15" ::: "xmm15");
#endif
    }
    if (signal == SIGXCPU) xcpu_count++;
}

static void check(int passed, const char *name) {
    printf("CPU-CHECK %s %s\n", passed ? "PASS" : "FAIL", name);
    if (!passed) failures++;
}

static uint64_t cpu_ns(void) {
    struct timespec t;
    if (clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &t)) return 0;
    return (uint64_t)t.tv_sec * 1000000000 + t.tv_nsec;
}

static void compute(uint64_t duration) {
    uint64_t started = cpu_ns();
    do {
        for (unsigned i = 0; i < 100000; i++) computation += i;
    } while (cpu_ns() - started < duration);
}

static void *worker(void *unused) {
    (void)unused;
    volatile unsigned long work = 0;
    while (!stop_worker) {
        for (unsigned i = 0; i < 100000; i++) work += i;
    }
    return NULL;
}

#if defined(__aarch64__)
static void native_unexpected_entry(void) {
    _exit(5);
}

static void native_guard(void) {
    pid_t child = fork();
    if (!child) {
        struct itimerval timer = {.it_value = {0, 20000}};
        sig_atomic_t previous = virtual_count;
        if (setitimer(ITIMER_VIRTUAL, &timer, NULL) ||
            syscall(246, (uintptr_t)native_unexpected_entry)) _exit(2);
        for (unsigned i = 0; i < 20000000; i++) computation += i;
        int deferred = virtual_count == previous;
        // Changing back to the Linux frame ABI at a syscall boundary allows
        // its pending handler to run with the complete SIMD frame.
        if (syscall(246, 0)) _exit(3);
        _exit(deferred && virtual_count == previous + 1 ? 0 : 4);
    }
    int status = 0;
    check(child > 0 && waitpid(child, &status, 0) == child && WIFEXITED(status) &&
          WEXITSTATUS(status) == 0, "native custom handlers defer to syscall boundary");

    child = fork();
    if (!child) {
        struct rlimit limit = {.rlim_cur = 1, .rlim_max = 1};
        if (setrlimit(RLIMIT_CPU, &limit) ||
            syscall(246, (uintptr_t)native_unexpected_entry)) _exit(2);
        for (;;) computation++;
    }
    check(child > 0 && waitpid(child, &status, 0) == child && WIFSIGNALED(status) &&
          WTERMSIG(status) == SIGKILL, "native fatal limit uses owned kernel stack");
}
#endif

static void timers(void) {
    struct itimerval timer = {.it_interval = {0, 20000}, .it_value = {0, 20000}};
    struct itimerval seen, off = {0};
    check(setitimer(ITIMER_VIRTUAL, &timer, NULL) == 0, "virtual arm");
    check(getitimer(ITIMER_VIRTUAL, &seen) == 0 && seen.it_interval.tv_usec == 20000 &&
          (seen.it_value.tv_sec || seen.it_value.tv_usec), "virtual remaining interval");
    usleep(100000);
    check(virtual_count == 0, "virtual excludes sleep");
    // No syscalls occur in this loop; scheduler ticks must deliver the timer.
    while (virtual_count < 3) {
        for (unsigned i = 0; i < 100000; i++) computation += i;
    }
    check(virtual_count >= 3, "periodic virtual interrupts pure userspace");
    check(setitimer(ITIMER_VIRTUAL, &off, &seen) == 0 &&
          seen.it_interval.tv_usec == 20000, "virtual disarm returns previous interval");
    check(getitimer(ITIMER_VIRTUAL, &seen) == 0 && !seen.it_value.tv_sec &&
          !seen.it_value.tv_usec, "virtual disarmed");

    check(setitimer(ITIMER_PROF, &timer, NULL) == 0, "prof arm");
    compute(100000000);
    check(prof_count >= 3, "periodic prof delivers");
    check(setitimer(ITIMER_PROF, &off, NULL) == 0, "prof disarm");

    uint64_t expected[2] = {UINT64_C(0x1122334455667788), UINT64_C(0x99aabbccddeeff00)};
    uint64_t restored[2] = {0};
    sig_atomic_t previous_prof = prof_count;
    timer.it_interval.tv_usec = 0;
    timer.it_value.tv_usec = 30000;
    pthread_t simd_thread;
    stop_worker = 0;
    check(pthread_create(&simd_thread, NULL, worker, NULL) == 0 &&
          setitimer(ITIMER_PROF, &timer, NULL) == 0, "competing SIMD timer arm");
#if defined(__aarch64__)
    __asm__ volatile("ld1 {v31.2d}, [%0]" :: "r"(expected) : "v31", "memory");
#elif defined(__x86_64__)
    __asm__ volatile("movdqu (%0), %%xmm15" :: "r"(expected) : "xmm15", "memory");
#endif
    while (prof_count == previous_prof) computation++;
#if defined(__aarch64__)
    __asm__ volatile("st1 {v31.2d}, [%0]" :: "r"(restored) : "memory");
#elif defined(__x86_64__)
    __asm__ volatile("movdqu %%xmm15, (%0)" :: "r"(restored) : "memory");
#endif
    stop_worker = 1;
    pthread_join(simd_thread, NULL);
    check(restored[0] == expected[0] && restored[1] == expected[1],
          "async signal restores SIMD across competing threads");

    // A process timer is shared by every thread, including when its setter
    // sleeps and another thread consumes the budget without making syscalls.
    virtual_count = 0;
    timer.it_value.tv_usec = 60000;
    timer.it_interval.tv_usec = 0;
    pthread_t thread;
    stop_worker = 0;
    check(setitimer(ITIMER_VIRTUAL, &timer, NULL) == 0 &&
          pthread_create(&thread, NULL, worker, NULL) == 0, "threaded virtual arm");
    for (int i = 0; i < 200 && !virtual_count; i++) usleep(10000);
    stop_worker = 1;
    pthread_join(thread, NULL);
    check(virtual_count == 1, "worker CPU expires process timer while setter sleeps");

    timer.it_value.tv_usec = 500000;
    check(setitimer(ITIMER_VIRTUAL, &timer, NULL) == 0, "fork timer arm");
    pid_t child = fork();
    if (!child) {
        int valid = getitimer(ITIMER_VIRTUAL, &seen) == 0 &&
                    !seen.it_value.tv_sec && !seen.it_value.tv_usec;
        _exit(valid ? 0 : 1);
    }
    int status = 0;
    check(child > 0 && waitpid(child, &status, 0) == child && WIFEXITED(status) &&
          WEXITSTATUS(status) == 0, "fork does not inherit CPU timers");
    setitimer(ITIMER_VIRTUAL, &off, NULL);

    errno = 0;
    check(getitimer(99, &seen) == -1 && errno == EINVAL, "getitimer invalid selector");
    errno = 0;
    check(setitimer(-1, &off, NULL) == -1 && errno == EINVAL, "setitimer invalid selector");
    timer.it_value.tv_usec = 1000000;
    errno = 0;
    check(setitimer(ITIMER_PROF, &timer, NULL) == -1 && errno == EINVAL,
          "reject invalid timeval microseconds");
    timer.it_value.tv_sec = -1;
    timer.it_value.tv_usec = 0;
    errno = 0;
    check(setitimer(ITIMER_VIRTUAL, &timer, NULL) == -1 && errno == EINVAL,
          "reject negative timeval");
    errno = 0;
    check(syscall(SYS_getitimer, ITIMER_PROF, 0) == -1 && errno == EFAULT,
          "getitimer null output");
    errno = 0;
    check(syscall(SYS_setitimer, ITIMER_VIRTUAL, (void *)UINTPTR_MAX, 0) == -1 &&
          errno == EFAULT, "setitimer checked input pointer");
}

static void accounting(void) {
    struct rusage before, after;
    getrusage(RUSAGE_SELF, &before);
    for (int i = 0; i < 250000; i++) syscall(SYS_getpid);
    getrusage(RUSAGE_SELF, &after);
    long system = (after.ru_stime.tv_sec - before.ru_stime.tv_sec) * 1000000L +
                  after.ru_stime.tv_usec - before.ru_stime.tv_usec;
    check(system > 0, "getrusage accounts syscall kernel time");
    getrusage(RUSAGE_SELF, &before);
    compute(100000000);
    getrusage(RUSAGE_SELF, &after);
    long user = (after.ru_utime.tv_sec - before.ru_utime.tv_sec) * 1000000L +
                after.ru_utime.tv_usec - before.ru_utime.tv_usec;
    check(user > 10000, "getrusage accounts user time");
    struct tms usage;
    check(times(&usage) != (clock_t)-1 && usage.tms_stime > 0 && usage.tms_utime > 0,
          "times exposes both user and kernel ticks");
}

static void limits(void) {
    pid_t inheritor = fork();
    if (!inheritor) {
        struct rlimit inherited = {.rlim_cur = 1, .rlim_max = 1};
        if (setrlimit(RLIMIT_CPU, &inherited)) _exit(2);
        pid_t grandchild = fork();
        if (!grandchild) for (;;) computation++;
        int inherited_status = 0;
        int valid = grandchild > 0 && waitpid(grandchild, &inherited_status, 0) == grandchild &&
                    WIFSIGNALED(inherited_status) && WTERMSIG(inherited_status) == SIGKILL;
        _exit(valid ? 0 : 3);
    }
    int inherited_status = 0;
    check(inheritor > 0 && waitpid(inheritor, &inherited_status, 0) == inheritor &&
          WIFEXITED(inherited_status) && WEXITSTATUS(inherited_status) == 0,
          "fork inherits enforced CPU limits with a fresh budget");

    int channel[2];
    check(pipe(channel) == 0, "limit pipe");
    pid_t child = fork();
    if (!child) {
        close(channel[0]);
        struct rlimit limit = {.rlim_cur = 1, .rlim_max = 3};
        if (setrlimit(RLIMIT_CPU, &limit)) _exit(2);
        pthread_t thread;
        stop_worker = 0;
        if (pthread_create(&thread, NULL, worker, NULL)) _exit(3);
        while (xcpu_count < 2) {
            for (unsigned i = 0; i < 100000; i++) computation += i;
        }
        // Do not require a handler to call write(), which is not async safe
        // under every Vinix libc path. Mark repeat-soft delivery from here.
        char ok = 'S';
        if (write(channel[1], &ok, 1) != 1) _exit(4);
        for (;;) {
            for (unsigned i = 0; i < 100000; i++) computation += i;
        }
    }
    close(channel[1]);
    char marker = 0;
    ssize_t count = read(channel[0], &marker, 1);
    close(channel[0]);
    int status = 0;
    check(count == 1 && marker == 'S', "CPU soft limit repeats SIGXCPU in multithreaded process");
    struct rusage child_usage;
    check(child > 0 && wait4(child, &status, 0, &child_usage) == child &&
          WIFSIGNALED(status) && WTERMSIG(status) == SIGKILL,
          "CPU hard limit kills whole process without syscalls");
    long total = child_usage.ru_utime.tv_sec * 1000000L + child_usage.ru_utime.tv_usec +
                 child_usage.ru_stime.tv_sec * 1000000L + child_usage.ru_stime.tv_usec;
    printf("CPU-CHECK child charged_us=%ld\n", total);
    check(total >= 2900000 && total < 4500000, "hard limit uses summed CPU time");
    struct rusage children;
    check(getrusage(RUSAGE_CHILDREN, &children) == 0 && children.ru_utime.tv_sec >= 2,
          "reaped CPU time reaches RUSAGE_CHILDREN");
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    puts("CPU-CHECK START");
    struct sigaction action = {.sa_handler = signal_seen};
    sigemptyset(&action.sa_mask);
    sigaction(SIGVTALRM, &action, NULL);
    sigaction(SIGPROF, &action, NULL);
    sigaction(SIGXCPU, &action, NULL);
    alarm(60);
    timers();
#if defined(__aarch64__)
    native_guard();
#endif
    accounting();
    limits();
    alarm(0);
    printf("CPU-CHECK DONE failures=%d\n", failures);
    if (getpid() == 1) {
        reboot(RB_POWER_OFF);
        for (;;) pause();
    }
    return failures ? 1 : 0;
}

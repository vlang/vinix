#define _GNU_SOURCE
#include <errno.h>
#include <pthread.h>
#include <sched.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/syscall.h>
#include <time.h>
#include <unistd.h>

enum { ROUNDS = 64, FUTEX_WAIT_PRIVATE = 128, FUTEX_WAKE_PRIVATE = 129 };
static atomic_int kick, done, ready, stop, setup_failed;
static atomic_ullong heartbeat;
static uint64_t sent[ROUNDS], latency[ROUNDS], counter_hz;

static uint64_t counter(void) {
#if defined(__aarch64__)
    uint64_t result;
    __asm__ volatile("mrs %0, cntvct_el0" : "=r"(result));
    return result;
#else
    unsigned low, high;
    __asm__ volatile("lfence; rdtsc" : "=a"(low), "=d"(high) :: "memory");
    return ((uint64_t)high << 32) | low;
#endif
}

static uint64_t ns(uint64_t ticks) {
    return ticks / counter_hz * UINT64_C(1000000000) +
           ticks % counter_hz * UINT64_C(1000000000) / counter_hz;
}

static int configure(int cpu, int priority) {
    cpu_set_t mask;
    CPU_ZERO(&mask);
    CPU_SET(cpu, &mask);
    struct sched_param param = {.sched_priority = priority};
    if (sched_setaffinity(0, sizeof mask, &mask)) {
        printf("SCHED-PREEMPT configure affinity cpu=%d errno=%d\n", cpu, errno);
        return 1;
    }
    // This cross-musl's POSIX wrapper is an ENOSYS stub; exercise the ABI.
    if (syscall(SYS_sched_setscheduler, 0, SCHED_FIFO, &param)) {
        printf("SCHED-PREEMPT configure priority=%d errno=%d\n", priority, errno);
        return 1;
    }
    return 0;
}

static void *urgent(void *unused) {
    (void)unused;
    if (configure(1, 50)) setup_failed = 1;
    ready++;
    for (int i = 0; i < ROUNDS; i++) {
        while (atomic_load_explicit(&kick, memory_order_acquire) <= i) {
            if (syscall(SYS_futex, &kick, FUTEX_WAIT_PRIVATE, i, NULL, NULL, 0) < 0 &&
                errno != EAGAIN && errno != EINTR) setup_failed = 1;
        }
        latency[i] = ns(counter() - sent[i]);
        atomic_store_explicit(&done, i + 1, memory_order_release);
    }
    return NULL;
}

static void *busy(void *unused) {
    (void)unused;
    if (configure(1, 1)) setup_failed = 1;
    ready++;
    uint64_t count = 0;
    // No syscalls: only the target's scheduler IRQ can give urgent its CPU.
    while (!atomic_load_explicit(&stop, memory_order_relaxed)) {
        atomic_store_explicit(&heartbeat, ++count, memory_order_relaxed);
    }
    return NULL;
}

static int compare(const void *left, const void *right) {
    uint64_t a = *(const uint64_t *)left, b = *(const uint64_t *)right;
    return (a > b) - (a < b);
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    puts("SCHED-PREEMPT START");
    cpu_set_t coordinator_mask;
    CPU_ZERO(&coordinator_mask);
    CPU_SET(0, &coordinator_mask);
    if (sched_setaffinity(0, sizeof coordinator_mask, &coordinator_mask)) goto fail;
#if defined(__aarch64__)
    __asm__ volatile("mrs %0, cntfrq_el0" : "=r"(counter_hz));
#else
    struct timespec before, after;
    clock_gettime(CLOCK_MONOTONIC, &before);
    uint64_t start = counter();
    usleep(100000);
    clock_gettime(CLOCK_MONOTONIC, &after);
    uint64_t elapsed = (after.tv_sec - before.tv_sec) * UINT64_C(1000000000) +
                       after.tv_nsec - before.tv_nsec;
    if (!elapsed) goto fail;
    counter_hz = (counter() - start) * UINT64_C(1000000000) / elapsed;
#endif
    if (!counter_hz) goto fail;
    printf("SCHED-PREEMPT counter_hz=%llu\n", (unsigned long long)counter_hz);
    pthread_t high, low;
    if (pthread_create(&high, NULL, urgent, NULL) ||
        pthread_create(&low, NULL, busy, NULL)) goto fail;
    uint64_t ready_start = counter();
    while (ready < 2) {
        if (ns(counter() - ready_start) > UINT64_C(10000000000)) goto fail;
        usleep(1000);
    }
    puts("SCHED-PREEMPT workers ready");
    usleep(10000);
    if (setup_failed || !heartbeat) goto fail;
    unsigned sleeping_wakes = 0;
    for (int i = 0; i < ROUNDS; i++) {
        // Give urgent time to enter its futex, while busy retains CPU 1.
        usleep(500);
        sent[i] = counter();
        atomic_store_explicit(&kick, i + 1, memory_order_release);
        long woken = syscall(SYS_futex, &kick, FUTEX_WAKE_PRIVATE, 1, NULL, NULL, 0);
        if (woken < 0) goto fail;
        sleeping_wakes += woken > 0;
        uint64_t timeout = counter();
        while (atomic_load_explicit(&done, memory_order_acquire) < i + 1) {
            if (ns(counter() - timeout) > UINT64_C(1000000000)) goto fail;
        }
    }
    stop = 1;
    pthread_join(high, NULL);
    pthread_join(low, NULL);
    qsort(latency, ROUNDS, sizeof latency[0], compare);
    printf("SCHED-PREEMPT wake_ns min=%llu p50=%llu p95=%llu max=%llu sleeping=%u\n",
           (unsigned long long)latency[0], (unsigned long long)latency[ROUNDS / 2],
           (unsigned long long)latency[ROUNDS * 95 / 100],
           (unsigned long long)latency[ROUNDS - 1], sleeping_wakes);
    // Median distinguishes dispatch by enqueue from FIFO's 5 ms tick while
    // tolerating a host pause affecting individual samples. Report all tails.
    if (setup_failed || sleeping_wakes < ROUNDS / 2 || latency[ROUNDS / 2] >= 3000000)
        goto fail;
    puts("SCHED-PREEMPT PASS");
    for (;;) pause();
fail:
    printf("SCHED-PREEMPT FAIL errno=%d setup=%d ready=%d done=%d\n", errno, setup_failed, ready, done);
    for (;;) pause();
}

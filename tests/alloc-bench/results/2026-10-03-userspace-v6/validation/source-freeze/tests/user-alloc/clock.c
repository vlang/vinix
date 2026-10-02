#define _GNU_SOURCE
#include <errno.h>
#include <inttypes.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <sys/syscall.h>
#include <sys/timerfd.h>
#include <time.h>
#include <unistd.h>

#define CHECK(condition) do { if (!(condition)) { \
    printf("CLOCK-FAIL line=%d check=%s errno=%d\n", __LINE__, #condition, errno); \
    return 1; \
} } while (0)

static uint64_t as_ns(struct timespec value)
{
    return (uint64_t)value.tv_sec * 1000000000 + (uint64_t)value.tv_nsec;
}

static struct timespec from_ns(uint64_t value)
{
    return (struct timespec){(time_t)(value / 1000000000), (long)(value % 1000000000)};
}

static uint64_t counter(void)
{
#if defined(__x86_64__)
    unsigned int low, high;
    __asm__ volatile("lfence; rdtsc" : "=a"(low), "=d"(high) : : "memory");
    return ((uint64_t)high << 32) | low;
#elif defined(__aarch64__)
    uint64_t value;
    __asm__ volatile("isb; mrs %0, cntvct_el0" : "=r"(value) : : "memory");
    return value;
#else
    return 0;
#endif
}

static int interval_ok(uint64_t before, uint64_t after, uint64_t minimum)
{
    return after >= before && after - before >= minimum && after - before < 2000000000;
}

int main(void)
{
    setbuf(stdout, NULL);
    alarm(30);
    struct timespec resolution, coarse, before, after;
    CHECK(!clock_getres(CLOCK_MONOTONIC, &resolution));
    CHECK(!resolution.tv_sec && resolution.tv_nsec >= 1 && resolution.tv_nsec <= 1000);
    CHECK(!clock_getres(CLOCK_MONOTONIC_COARSE, &resolution));
    CHECK(!resolution.tv_sec && resolution.tv_nsec == 1000000);
    CHECK(!clock_gettime(CLOCK_MONOTONIC, &before));
    CHECK(!clock_gettime(CLOCK_MONOTONIC_COARSE, &coarse));
    CHECK(!clock_gettime(CLOCK_MONOTONIC, &after));
    CHECK(as_ns(after) >= as_ns(before));
    CHECK(as_ns(coarse) <= as_ns(after));
    CHECK(as_ns(after) - as_ns(coarse) < 100000000);

    /* Sleep calibrates only the counter ratio, not its frequency. Syscalls
     * can merge PIT IRQs, so the busy interval must keep the same ratio. */
    uint64_t sleep_start = counter();
    CHECK(!clock_gettime(CLOCK_MONOTONIC, &before));
    CHECK(!nanosleep(&(struct timespec){.tv_nsec = 50000000}, NULL));
    CHECK(!clock_gettime(CLOCK_MONOTONIC, &after));
    uint64_t sleep_ticks = counter() - sleep_start;
    uint64_t sleep_ns = as_ns(after) - as_ns(before);
    CHECK(interval_ok(as_ns(before), as_ns(after), 50000000));

    CHECK(!clock_gettime(CLOCK_MONOTONIC, &before));
    printf("CLOCK-REFERENCE-BEGIN ns=%" PRIu64 "\n", as_ns(before));
    uint64_t busy_start = counter();
    for (unsigned i = 0; i < 50000; ++i)
        (void)getpid();
    uint64_t busy_ticks = counter() - busy_start;
    CHECK(!clock_gettime(CLOCK_MONOTONIC, &after));
    uint64_t busy_ns = as_ns(after) - as_ns(before);
    printf("CLOCK-REFERENCE-END ns=%" PRIu64 " elapsed=%" PRIu64 "\n", as_ns(after), busy_ns);
    CHECK(sleep_ticks && busy_ticks && busy_ns);
    double ratio = ((double)busy_ns / busy_ticks) / ((double)sleep_ns / sleep_ticks);
    printf("CLOCK-COUNTER sleep_ns=%" PRIu64 " sleep_ticks=%" PRIu64
        " busy_ns=%" PRIu64 " busy_ticks=%" PRIu64 " ratio=%.6f\n",
        sleep_ns, sleep_ticks, busy_ns, busy_ticks, ratio);
    CHECK(ratio > 0.5 && ratio < 1.5);

    for (unsigned realtime = 0; realtime < 2; ++realtime) {
        clockid_t clock = realtime ? CLOCK_REALTIME : CLOCK_MONOTONIC;
        int fd = timerfd_create(clock, TFD_CLOEXEC);
        CHECK(fd >= 0);
        CHECK(!clock_gettime(clock, &before));
        struct itimerspec timer = {.it_value = from_ns(as_ns(before) + 20000000)};
        CHECK(!timerfd_settime(fd, TFD_TIMER_ABSTIME, &timer, NULL));
        struct pollfd event = {fd, POLLIN, 0};
        CHECK(poll(&event, 1, 1000) == 1 && (event.revents & POLLIN));
        uint64_t expirations = 0;
        CHECK(read(fd, &expirations, sizeof expirations) == sizeof expirations && expirations == 1);
        CHECK(!clock_gettime(clock, &after));
        CHECK(interval_ok(as_ns(before), as_ns(after), 20000000));
        CHECK(!close(fd));
    }

    CHECK(!clock_gettime(CLOCK_MONOTONIC, &before));
    struct timespec deadline = from_ns(as_ns(before) + 20000000);
    CHECK(!clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME, &deadline, NULL));
    CHECK(!clock_gettime(CLOCK_MONOTONIC, &after));
    CHECK(interval_ok(as_ns(before), as_ns(after), 20000000));

    int word = 0;
    CHECK(!clock_gettime(CLOCK_MONOTONIC, &before));
    deadline = from_ns(as_ns(before) + 20000000);
    errno = 0;
    /* FUTEX_WAIT_BITSET | FUTEX_PRIVATE_FLAG, FUTEX_BITSET_MATCH_ANY. */
    CHECK(syscall(SYS_futex, &word, 9 | 128, 0, &deadline, NULL, ~0u) == -1 && errno == ETIMEDOUT);
    CHECK(!clock_gettime(CLOCK_MONOTONIC, &after));
    CHECK(interval_ok(as_ns(before), as_ns(after), 20000000));
    puts("CLOCK-DONE precise counter, coarse snapshots, absolute sleeps, timerfd and futex");
    return 0;
}

#define _GNU_SOURCE
#include <errno.h>
#include <linux/futex.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/syscall.h>
#include <sys/time.h>
#include <time.h>
#include <unistd.h>

static uint64_t ns(struct timespec t)
{
    return (uint64_t)t.tv_sec * 1000000000 + t.tv_nsec;
}

static uint64_t counter(void)
{
    uint64_t value;
    __asm__ volatile("isb; mrs %0, cntvct_el0" : "=r"(value) : : "memory");
    return value;
}

static struct timespec deadline(void)
{
    struct timespec value;
    if (clock_gettime(CLOCK_MONOTONIC, &value) != 0)
        return (struct timespec){0};
    value.tv_nsec += 20000000;
    if (value.tv_nsec >= 1000000000) {
        value.tv_sec++;
        value.tv_nsec -= 1000000000;
    }
    return value;
}

int main(int argc, char **argv)
{
    uint64_t frequency;
    __asm__ volatile("mrs %0, cntfrq_el0" : "=r"(frequency));
    const clockid_t ids[] = {CLOCK_MONOTONIC, CLOCK_REALTIME,
                             CLOCK_MONOTONIC_RAW, CLOCK_BOOTTIME};
    const char *names[] = {"monotonic", "realtime", "raw", "boottime"};
    int failed = 0;
    for (unsigned c = 0; c < sizeof(ids) / sizeof(ids[0]); c++) {
        unsigned zero = 0, backwards = 0;
        uint64_t hardware = 0, elapsed = 0;
        struct timespec resolution;
        if (clock_getres(ids[c], &resolution) != 0)
            return 1;
        for (int i = 0; i < 100; i++) {
            struct timespec before, after;
            uint64_t begin = counter();
            if (clock_gettime(ids[c], &before) != 0)
                return 1;
            for (int pause = 0; pause < 5000; pause++)
                __asm__ volatile("yield" : : : "memory");
            if (clock_gettime(ids[c], &after) != 0)
                return 1;
            uint64_t end = counter();
            zero += ns(after) == ns(before);
            backwards += ns(after) < ns(before);
            elapsed += ns(after) - ns(before);
            hardware += (end - begin) * 1000000000 / frequency;
            if (after.tv_nsec < 0 || after.tv_nsec >= 1000000000)
                return 1;
        }
        printf("DHEWM3-CLOCK clock=%s zero=%u/100 backwards=%u hardware_ns=%llu clock_ns=%llu resolution_ns=%llu\n",
               names[c], zero, backwards, (unsigned long long)hardware,
               (unsigned long long)elapsed, (unsigned long long)ns(resolution));
        failed |= zero != 0 || backwards != 0;
    }
    unsigned zero = 0;
    for (int i = 0; i < 100; i++) {
        struct timeval before, after;
        if (gettimeofday(&before, NULL) != 0)
            return 1;
        for (int pause = 0; pause < 20000; pause++)
            __asm__ volatile("yield" : : : "memory");
        if (gettimeofday(&after, NULL) != 0)
            return 1;
        zero += before.tv_sec == after.tv_sec && before.tv_usec == after.tv_usec;
    }
    printf("DHEWM3-CLOCK clock=gettimeofday zero=%u/100\n", zero);
    failed |= zero != 0;

    // Absolute waits consume these clocks too. Check them against the raw
    // counter so moving the syscall clock cannot silently shift deadlines.
    for (int futex = 0; futex < 2; futex++) {
        struct timespec until = deadline();
        uint64_t begin = counter();
        int result;
        if (futex) {
            int word = 0;
            result = syscall(SYS_futex, &word, FUTEX_WAIT_BITSET | FUTEX_PRIVATE_FLAG,
                             0, &until, NULL, FUTEX_BITSET_MATCH_ANY);
            result = result == -1 && errno == ETIMEDOUT ? 0 : 1;
        } else {
            result = clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME, &until, NULL);
        }
        uint64_t elapsed = (counter() - begin) * 1000000000 / frequency;
        struct timespec after;
        if (clock_gettime(CLOCK_MONOTONIC, &after) != 0)
            return 1;
        int valid = result == 0 && elapsed >= 19000000 && elapsed < 1000000000 && ns(after) >= ns(until);
        printf("DHEWM3-DEADLINE wait=%s hardware_ns=%llu passed=%d\n",
               futex ? "futex" : "clock_nanosleep", (unsigned long long)elapsed, valid);
        failed |= !valid;
    }
    return argc > 1 && strcmp(argv[1], "--check") == 0 ? failed : 0;
}

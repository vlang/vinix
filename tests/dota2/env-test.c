/* SPDX-License-Identifier: LGPL-2.1-or-later
 * Adapted from GNU libc stdlib/tst-getenv-thread.c (glibc-2.41),
 * Copyright (C) 2024-2025 Free Software Foundation, Inc.
 * https://github.com/bminor/glibc/blob/glibc-2.41/stdlib/tst-getenv-thread.c
 *
 * Concurrent readers check an unchanged constant and a missing variable while
 * one writer adds 1000 distinct names, as in the upstream regression. Arrays
 * are reset only after all readers joined. Reusing the same names and values
 * across finite rounds bounds libc's retained environment strings. No host
 * environment entries or values are read into output.
 *
 * Link to the staged x86-64 glibc directly, like tests/dota2/steam-smoke.c.
 * Manual prototypes avoid host/musl headers and CRT. pthread_t is unsigned
 * long and timespec is two longs in the Linux x86-64 glibc ABI.
 */
extern char *getenv(const char *);
extern int setenv(const char *, const char *, int);
extern int clearenv(void);
extern int strcmp(const char *, const char *);
extern int snprintf(char *, unsigned long, const char *, ...);
extern int printf(const char *, ...);
extern int puts(const char *);
extern int fflush(void *);
extern long write(int, const void *, unsigned long);
extern void _exit(int);
extern unsigned int alarm(unsigned int);
extern int sched_yield(void);
extern int pthread_create(unsigned long *, const void *, void *(*)(void *), void *);
extern int pthread_join(unsigned long, void **);
extern const char *gnu_get_libc_version(void);
typedef void (*signal_handler)(int);
extern signal_handler signal(int, signal_handler);
struct timestamp { long seconds, nanoseconds; };
extern int clock_gettime(int, struct timestamp *);

__asm__(".text\n.global _start\n_start:\n"
        "xor %ebp,%ebp\nmov %rdx,%r9\npop %rsi\nmov %rsp,%rdx\n"
        "and $-16,%rsp\npush %rax\npush %rsp\nxor %r8d,%r8d\nxor %ecx,%ecx\n"
        "lea main(%rip),%rdi\ncall *__libc_start_main@GOTPCREL(%rip)\nhlt\n");

enum { reader_count = 2, variable_count = 1000, rounds = 32, timeout_seconds = 90 };
static int ready, running, stop, failed, writing;
static unsigned long checks[reader_count], concurrent_checks[reader_count];
static unsigned long writer_calls;
static char names[variable_count][32];
static struct timestamp deadline;

static void timed_out(int number)
{
    (void)number;
    static const char message[] = "VINIX-DOTA2-ENV-FAIL: timeout\n";
    write(2, message, sizeof message - 1);
    _exit(124);
}

static int past_deadline(void)
{
    struct timestamp current;
    if (clock_gettime(1, &current)) return 1; /* CLOCK_MONOTONIC */
    return current.seconds > deadline.seconds ||
        (current.seconds == deadline.seconds && current.nanoseconds >= deadline.nanoseconds);
}

static void *reader(void *argument)
{
    unsigned long index = (unsigned long)argument;
    __atomic_add_fetch(&ready, 1, __ATOMIC_RELEASE);
    while (!__atomic_load_n(&running, __ATOMIC_ACQUIRE)) {
        if (__atomic_load_n(&stop, __ATOMIC_ACQUIRE)) return (void *)0;
        sched_yield();
    }
    unsigned long count = 0, overlap = 0;
    while (!__atomic_load_n(&stop, __ATOMIC_ACQUIRE)) {
        int during_write = __atomic_load_n(&writing, __ATOMIC_ACQUIRE);
        char *constant = getenv("VINIX_ENV_TEST_CONSTANT");
        if (!constant || strcmp(constant, "constant-test-value") ||
            getenv("VINIX_ENV_TEST_MISSING") != (void *)0) {
            __atomic_store_n(&failed, 1, __ATOMIC_RELEASE);
            break;
        }
        ++count;
        if (during_write && __atomic_load_n(&writing, __ATOMIC_ACQUIRE)) ++overlap;
        /* Keep a core available for the single writer on translated guests. */
        if (!(count & 63)) sched_yield();
    }
    checks[index] = count;
    concurrent_checks[index] = overlap;
    return (void *)0;
}

int main(void)
{
    puts("VINIX-DOTA2-ENV-START");
    printf("VINIX-DOTA2-ENV-LIBC: %s\n", gnu_get_libc_version());
    fflush((void *)0);
    if (signal(14, timed_out) == (signal_handler)-1 || clock_gettime(1, &deadline)) {
        puts("VINIX-DOTA2-ENV-FAIL: watchdog initialization");
        return 2;
    }
    deadline.seconds += timeout_seconds;
    alarm(timeout_seconds);
    for (unsigned long index = 0; index < variable_count; ++index)
        if (snprintf(names[index], sizeof names[index], "VINIX_ENV_TEST_V%lu", index) <= 0) {
            puts("VINIX-DOTA2-ENV-FAIL: fixed test name initialization");
            return 2;
        }
    unsigned long total_checks = 0, total_overlap = 0;
    for (unsigned long round = 0; round < rounds; ++round) {
        /* No concurrent reader exists while the test environment is reset. */
        if (clearenv() || setenv("VINIX_ENV_TEST_CONSTANT", "constant-test-value", 1)) {
            puts("VINIX-DOTA2-ENV-FAIL: test environment initialization");
            return 2;
        }
        ready = running = stop = failed = writing = 0;
        unsigned long threads[reader_count], started = 0;
        for (; started < reader_count; ++started) {
            checks[started] = concurrent_checks[started] = 0;
            if (pthread_create(&threads[started], (void *)0, reader, (void *)started)) break;
        }
        if (started != reader_count) {
            __atomic_store_n(&stop, 1, __ATOMIC_RELEASE);
            for (unsigned long index = 0; index < started; ++index)
                pthread_join(threads[index], (void *)0);
            puts("VINIX-DOTA2-ENV-FAIL: reader thread creation");
            return 2;
        }
        while (__atomic_load_n(&ready, __ATOMIC_ACQUIRE) != reader_count) {
            if (past_deadline()) timed_out(0);
            sched_yield();
        }
        __atomic_store_n(&writing, 1, __ATOMIC_RELEASE);
        __atomic_store_n(&running, 1, __ATOMIC_RELEASE);
        for (unsigned long index = 0; index < variable_count; ++index) {
            if (setenv(names[index], "fixed-test-value", 1)) {
                __atomic_store_n(&failed, 1, __ATOMIC_RELEASE);
                break;
            }
            ++writer_calls;
            if (!(index & 31)) {
                if (past_deadline()) timed_out(0);
                sched_yield();
            }
            if (__atomic_load_n(&failed, __ATOMIC_ACQUIRE)) break;
        }
        __atomic_store_n(&writing, 0, __ATOMIC_RELEASE);
        __atomic_store_n(&stop, 1, __ATOMIC_RELEASE);
        for (unsigned long index = 0; index < reader_count; ++index)
            if (pthread_join(threads[index], (void *)0)) {
                puts("VINIX-DOTA2-ENV-FAIL: reader thread join");
                return 2;
            }
        unsigned long round_checks = checks[0] + checks[1];
        unsigned long round_overlap = concurrent_checks[0] + concurrent_checks[1];
        total_checks += round_checks;
        total_overlap += round_overlap;
        printf("VINIX-DOTA2-ENV-ROUND: round=%lu writes=%lu checks=%lu overlap=%lu\n",
               round + 1, writer_calls, round_checks, round_overlap);
        fflush((void *)0);
        if (__atomic_load_n(&failed, __ATOMIC_ACQUIRE) || !checks[0] || !checks[1] ||
            !concurrent_checks[0] || !concurrent_checks[1]) {
            puts("VINIX-DOTA2-ENV-FAIL: lookup invariant or missing reader overlap");
            fflush((void *)0);
            return 1;
        }
    }
    alarm(0);
    printf("VINIX-DOTA2-ENV-PASS: rounds=%u writes=%lu checks=%lu overlap=%lu\n",
           rounds, writer_calls, total_checks, total_overlap);
    fflush((void *)0);
    return 0;
}

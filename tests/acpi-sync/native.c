#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <pthread.h>

extern void *vinix_acpi_sync_create(bool);
extern bool vinix_acpi_sync_destroy(void *);
extern int vinix_acpi_sync_wait(void *, uint16_t);
extern bool vinix_acpi_sync_signal(void *);
extern void vinix_acpi_sync_reset(void *);
extern void vinix_acpi_sync_sleep(uint64_t);
extern uint64_t vinix_acpi_sync_clock_ns(void);
extern uint64_t vinix_acpi_sync_thread_id(void);
extern void vinix_acpi_sync_heap_snapshot(uint64_t *);
extern void kprintf(const char *, ...);

static void test_log(const char *message)
{
    kprintf("%s", message);
#ifndef __AARCH64__
    /* x86's normal production kprint deliberately omits COM1. Keep these
     * optional test verdicts visible without changing production logging. */
    extern void serial__out(char);
    for (const char *p = message; *p; ++p) serial__out(*p);
#endif
}

#define CHECK(condition) do { if (!(condition)) { \
    kprintf("FAIL: ACPI sync at line %u\n", (unsigned)__LINE__); \
    test_log("FAIL: ACPI sync native self-test\n"); return -1; \
} } while (0)

static int counter_and_timeouts(void)
{
    void *event = vinix_acpi_sync_create(false);
    void *mutex = vinix_acpi_sync_create(true);
    CHECK(event && mutex && vinix_acpi_sync_thread_id());
    CHECK(vinix_acpi_sync_wait(NULL, 0) == 7);
    CHECK(vinix_acpi_sync_wait(event, 0) == 18);
    CHECK(vinix_acpi_sync_wait(mutex, 0) == 0);
    CHECK(vinix_acpi_sync_wait(mutex, 0) == 18);
    CHECK(!vinix_acpi_sync_destroy(mutex));
    CHECK(vinix_acpi_sync_signal(mutex));
    CHECK(!vinix_acpi_sync_signal(mutex));
    CHECK(vinix_acpi_sync_signal(event));
    CHECK(vinix_acpi_sync_signal(event));
    CHECK(vinix_acpi_sync_wait(event, 0) == 0);
    CHECK(vinix_acpi_sync_wait(event, 0) == 0);
    CHECK(vinix_acpi_sync_wait(event, 0) == 18);
    CHECK(vinix_acpi_sync_signal(event));
    vinix_acpi_sync_reset(event);
    CHECK(vinix_acpi_sync_wait(event, 0) == 18);
    uint64_t before = vinix_acpi_sync_clock_ns();
    CHECK(vinix_acpi_sync_wait(event, 3) == 18);
    CHECK(vinix_acpi_sync_clock_ns() - before >= 3000000);
    before = vinix_acpi_sync_clock_ns();
    vinix_acpi_sync_sleep(2);
    CHECK(vinix_acpi_sync_clock_ns() - before >= 2000000);
    CHECK(vinix_acpi_sync_destroy(event));
    CHECK(vinix_acpi_sync_destroy(mutex));
    return 0;
}

int vinix_acpi_sync_boot_test(void)
{
    CHECK(counter_and_timeouts() == 0);
    test_log("ACPI-SYNC: bootstrap polling PASS\n");
    return 0;
}

struct workers {
    void *mutex, *event;
    uint64_t identities[4];
    unsigned ready, successes, failures, counter, in_section;
};
struct worker {
    struct workers *shared;
    unsigned index;
};

static void *mutex_worker(void *argument)
{
    struct worker *worker = argument;
    struct workers *shared = worker->shared;
    shared->identities[worker->index] = vinix_acpi_sync_thread_id();
    __atomic_add_fetch(&shared->ready, 1, __ATOMIC_RELEASE);
    if (vinix_acpi_sync_wait(shared->event, UINT16_MAX)) {
        __atomic_add_fetch(&shared->failures, 1, __ATOMIC_RELAXED);
        pthread_exit(NULL);
    }
    for (unsigned i = 0; i < 1000; ++i) {
        if (vinix_acpi_sync_wait(shared->mutex, UINT16_MAX)) {
            __atomic_add_fetch(&shared->failures, 1, __ATOMIC_RELAXED);
            break;
        }
        if (__atomic_add_fetch(&shared->in_section, 1, __ATOMIC_RELAXED) != 1)
            __atomic_add_fetch(&shared->failures, 1, __ATOMIC_RELAXED);
        shared->counter++;
        __atomic_sub_fetch(&shared->in_section, 1, __ATOMIC_RELAXED);
        if (!vinix_acpi_sync_signal(shared->mutex))
            __atomic_add_fetch(&shared->failures, 1, __ATOMIC_RELAXED);
    }
    pthread_exit(NULL);
    return NULL;
}

static void *event_worker(void *argument)
{
    struct worker *worker = argument;
    struct workers *shared = worker->shared;
    __atomic_add_fetch(&shared->ready, 1, __ATOMIC_RELEASE);
    int result = vinix_acpi_sync_wait(shared->event, 200);
    if (result == 0)
        __atomic_add_fetch(&shared->successes, 1, __ATOMIC_RELAXED);
    else if (result != 18)
        __atomic_add_fetch(&shared->failures, 1, __ATOMIC_RELAXED);
    pthread_exit(NULL);
    return NULL;
}

static void *wrong_owner(void *argument)
{
    struct workers *shared = argument;
    if (vinix_acpi_sync_signal(shared->mutex))
        __atomic_add_fetch(&shared->failures, 1, __ATOMIC_RELAXED);
    pthread_exit(NULL);
    return NULL;
}

static void *delayed_signal(void *argument)
{
    vinix_acpi_sync_sleep(5);
    vinix_acpi_sync_signal(argument);
    pthread_exit(NULL);
    return NULL;
}

int vinix_acpi_sync_native_test(void)
{
    CHECK(counter_and_timeouts() == 0);
    struct workers shared = {0};
    struct worker workers[4] = {0};
    pthread_t threads[4];
    shared.mutex = vinix_acpi_sync_create(true);
    shared.event = vinix_acpi_sync_create(false);
    CHECK(shared.mutex && shared.event);
    CHECK(vinix_acpi_sync_wait(shared.mutex, 0) == 0);
    CHECK(pthread_create(&threads[0], NULL, wrong_owner, &shared) == 0);
    CHECK(pthread_join(threads[0], NULL) == 0);
    CHECK(!shared.failures);
    CHECK(vinix_acpi_sync_wait(shared.mutex, 0) == 18);
    CHECK(vinix_acpi_sync_signal(shared.mutex));
    for (unsigned i = 0; i < 4; ++i) {
        workers[i].shared = &shared;
        workers[i].index = i;
        CHECK(pthread_create(&threads[i], NULL, mutex_worker, &workers[i]) == 0);
    }
    while (__atomic_load_n(&shared.ready, __ATOMIC_ACQUIRE) != 4)
        vinix_acpi_sync_sleep(1);
    for (unsigned i = 0; i < 4; ++i) CHECK(vinix_acpi_sync_signal(shared.event));
    for (unsigned i = 0; i < 4; ++i) CHECK(pthread_join(threads[i], NULL) == 0);
    CHECK(shared.counter == 4000 && !shared.failures && !shared.in_section);
    for (unsigned i = 0; i < 4; ++i) {
        CHECK(shared.identities[i] && shared.identities[i] != vinix_acpi_sync_thread_id());
        for (unsigned j = 0; j < i; ++j) CHECK(shared.identities[i] != shared.identities[j]);
    }
    test_log("ACPI-SYNC: mutex exclusion and thread identity PASS\n");

    shared.ready = 0;
    for (unsigned i = 0; i < 4; ++i)
        CHECK(pthread_create(&threads[i], NULL, event_worker, &workers[i]) == 0);
    while (__atomic_load_n(&shared.ready, __ATOMIC_ACQUIRE) != 4)
        vinix_acpi_sync_sleep(1);
    vinix_acpi_sync_sleep(5);
    CHECK(!vinix_acpi_sync_destroy(shared.event));
    CHECK(vinix_acpi_sync_signal(shared.event));
    for (unsigned i = 0; i < 4; ++i) CHECK(pthread_join(threads[i], NULL) == 0);
    CHECK(shared.successes == 1 && !shared.failures);
    CHECK(pthread_create(&threads[0], NULL, delayed_signal, shared.event) == 0);
    CHECK(vinix_acpi_sync_wait(shared.event, 100) == 0);
    CHECK(pthread_join(threads[0], NULL) == 0);
    CHECK(pthread_create(&threads[0], NULL, delayed_signal, shared.event) == 0);
    CHECK(vinix_acpi_sync_wait(shared.event, UINT16_MAX) == 0);
    CHECK(pthread_join(threads[0], NULL) == 0);
    CHECK(vinix_acpi_sync_wait(shared.event, 0) == 18);
    CHECK(vinix_acpi_sync_destroy(shared.event));
    CHECK(vinix_acpi_sync_destroy(shared.mutex));
    test_log("ACPI-SYNC: one permit, reset, finite and infinite waits PASS\n");

    /* Warm the timer-array and allocator capacities before comparing every
     * live slab class. Observer snapshots use no heap allocation. */
    for (unsigned i = 0; i < 8; ++i) CHECK(counter_and_timeouts() == 0);
    uint64_t before[18], after[18];
    vinix_acpi_sync_heap_snapshot(before);
    for (unsigned i = 0; i < 200; ++i) CHECK(counter_and_timeouts() == 0);
    vinix_acpi_sync_heap_snapshot(after);
    for (unsigned i = 0; i < 18; ++i) {
        if (before[i] != after[i])
            kprintf("ACPI-SYNC: slab class %u before=%llu after=%llu\n", i,
                    (unsigned long long)before[i], (unsigned long long)after[i]);
        CHECK(before[i] == after[i]);
    }
    test_log("ACPI-SYNC: 200 repeated gate/timer lifetimes, every slab class flat PASS\n");
    test_log("ACPI-SYNC: ALL PASS\n");
    return 0;
}

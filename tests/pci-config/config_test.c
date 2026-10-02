/* SPDX-License-Identifier: GPL-2.0-only */
/* The real portable core uses a deterministic test transport, not PCI devices. */
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <sched.h>
#include "../../kernel/c/pci_config.h"

struct test_device { uint32_t bus, slot, function; unsigned char bytes[4096]; };
static struct test_device devices[] = {
    { .bus = 0, .slot = 1 }, { .bus = 0, .slot = 2 },
    { .bus = 7, .slot = 31, .function = 7 },
    { .bus = 255, .slot = 31, .function = 7 },
};
static pthread_mutex_t transport = PTHREAD_MUTEX_INITIALIZER;
static __thread bool interrupts = true, locked, saved_interrupts;
static __thread unsigned int pins, saved_pins;
static unsigned int attempts, locks, unlocks, limits, reads, writes, allocations;
static uint32_t cf8;
static bool oversized_reads;
static unsigned int gate_armed, gate_entered, gate_release;
static uint32_t gate_slot, gate_offset;
static uint32_t last_read_width, last_write_width, last_write_offset, last_write_value;

/* Compiled into the core object only. Test backing pthread/libc allocation is
 * outside this check; any allocation newly introduced into the core fails. */
void *vinix_pci_test_malloc(size_t bytes) { (void)bytes; __atomic_add_fetch(&allocations, 1, __ATOMIC_RELAXED); return NULL; }
void *vinix_pci_test_calloc(size_t count, size_t bytes) { (void)count; return vinix_pci_test_malloc(bytes); }
void *vinix_pci_test_realloc(void *old, size_t bytes) { (void)old; return vinix_pci_test_malloc(bytes); }
void vinix_pci_test_free(void *pointer) { (void)pointer; __atomic_add_fetch(&allocations, 1, __ATOMIC_RELAXED); }

static void wait_flag(unsigned int *flag, unsigned int wanted)
{
    for (unsigned int spin = 0; spin < 10000000; spin++) {
        if (__atomic_load_n(flag, __ATOMIC_ACQUIRE) >= wanted) return;
        sched_yield();
    }
    assert(!"test actor/gate failed to progress");
}
static struct test_device *find_device(uint32_t bus, uint32_t slot, uint32_t function)
{
    for (size_t i = 0; i < sizeof(devices) / sizeof(devices[0]); i++)
        if (devices[i].bus == bus && devices[i].slot == slot && devices[i].function == function)
            return &devices[i];
    return NULL;
}
static void check_locked(void) { assert(locked && !interrupts && pins == saved_pins + 1); }
void vinix_pci_config_lock(void)
{
    assert(!locked);
    __atomic_add_fetch(&attempts, 1, __ATOMIC_RELEASE);
    assert(!pthread_mutex_lock(&transport));
    saved_interrupts = interrupts; saved_pins = pins;
    interrupts = false; pins++;
    locked = true;
    __atomic_add_fetch(&locks, 1, __ATOMIC_RELAXED);
}
void vinix_pci_config_unlock(void)
{
    check_locked();
    __atomic_add_fetch(&unlocks, 1, __ATOMIC_RELAXED);
    locked = false;
    assert(!pthread_mutex_unlock(&transport));
    pins = saved_pins; interrupts = saved_interrupts;
}
uint32_t vinix_pci_config_limit(uint32_t bus)
{
    check_locked(); __atomic_add_fetch(&limits, 1, __ATOMIC_RELAXED);
    if (bus == 0 || bus == 255) return 256;
    if (bus == 7) return 4096;
    return 0;
}
static struct test_device *select_address(uint32_t bus, uint32_t slot,
        uint32_t function, uint32_t offset, uint32_t *actual_offset)
{
    check_locked();
    if (bus == 7) { *actual_offset = offset; return find_device(bus, slot, function); }
    uint32_t address = UINT32_C(0x80000000) | (bus << 16) | (slot << 11) |
                       (function << 8) | (offset & 0xfc);
    __atomic_store_n(&cf8, address, __ATOMIC_RELEASE);
    /* Host scheduling instrumentation only: real raw callbacks never wait.
     * Delaying after address publication exposes a missing shared lock. */
    if (bus == 0 && slot == gate_slot && offset == gate_offset &&
        __atomic_exchange_n(&gate_armed, 0, __ATOMIC_ACQ_REL)) {
        __atomic_store_n(&gate_entered, 1, __ATOMIC_RELEASE);
        wait_flag(&gate_release, 1);
    }
    address = __atomic_load_n(&cf8, __ATOMIC_ACQUIRE);
    *actual_offset = (address & 0xfc) + (offset & 3);
    return find_device((address >> 16) & 255, (address >> 11) & 31, (address >> 8) & 7);
}
uint32_t vinix_pci_config_read_raw(uint32_t bus, uint32_t slot, uint32_t function,
        uint32_t offset, uint32_t width)
{
    uint32_t actual_offset;
    struct test_device *device = select_address(bus, slot, function, offset, &actual_offset);
    assert(width == 1 || width == 2 || width == 4);
    last_read_width = width;
    __atomic_add_fetch(&reads, 1, __ATOMIC_RELAXED);
    if (!device) return UINT32_MAX;
    uint32_t value = 0;
    for (uint32_t i = 0; i < width; i++) value |= (uint32_t)device->bytes[actual_offset + i] << (8 * i);
    if (oversized_reads && width < 4) value |= width == 1 ? UINT32_C(0xa5a5a500) : UINT32_C(0xa5a50000);
    return value;
}
void vinix_pci_config_write_raw(uint32_t bus, uint32_t slot, uint32_t function,
        uint32_t offset, uint32_t width, uint32_t value)
{
    uint32_t actual_offset;
    struct test_device *device = select_address(bus, slot, function, offset, &actual_offset);
    assert(width == 1 || width == 2 || width == 4);
    assert(width == 4 || !(value >> (8 * width)));
    last_write_width = width; last_write_offset = offset; last_write_value = value;
    __atomic_add_fetch(&writes, 1, __ATOMIC_RELAXED);
    if (!device) return;
    for (uint32_t i = 0; i < width; i++) {
        unsigned char byte = (unsigned char)(value >> (8 * i));
        /* STATUS shares COMMAND's dword. Writing a one clears that bit. */
        if (actual_offset + i == 6 || actual_offset + i == 7)
            device->bytes[actual_offset + i] &= (unsigned char)~byte;
        else device->bytes[actual_offset + i] = byte;
    }
}

struct observed { unsigned int attempts, locks, unlocks, limits, reads, writes, allocations, pins; bool interrupts; };
static struct observed observe(void)
{
    return (struct observed){
        .attempts = __atomic_load_n(&attempts, __ATOMIC_ACQUIRE),
        .locks = __atomic_load_n(&locks, __ATOMIC_RELAXED),
        .unlocks = __atomic_load_n(&unlocks, __ATOMIC_RELAXED),
        .limits = __atomic_load_n(&limits, __ATOMIC_RELAXED),
        .reads = __atomic_load_n(&reads, __ATOMIC_RELAXED),
        .writes = __atomic_load_n(&writes, __ATOMIC_RELAXED),
        .allocations = __atomic_load_n(&allocations, __ATOMIC_RELAXED),
        .pins = pins, .interrupts = interrupts,
    };
}
static void preserved(struct observed before)
{
    assert(!locked && interrupts == before.interrupts && pins == before.pins);
    assert(__atomic_load_n(&allocations, __ATOMIC_RELAXED) == before.allocations);
}
static void check_bad(uint32_t domain, uint32_t bus, uint32_t slot, uint32_t function,
        uint64_t offset, uint32_t width, int expected, bool result, bool takes_lock)
{
    struct observed before = observe();
    uint32_t value = UINT32_C(0x12345678);
    assert(vinix_pci_config_read(domain, bus, slot, function, offset, width, result ? &value : NULL) == expected);
    assert(value == UINT32_C(0x12345678));
    preserved(before);
    struct observed after = observe();
    assert(after.reads == before.reads && after.writes == before.writes);
    assert(after.attempts - before.attempts == (takes_lock ? 1U : 0U));
    assert(after.locks - before.locks == (takes_lock ? 1U : 0U));
    assert(after.unlocks - before.unlocks == (takes_lock ? 1U : 0U));
    assert(after.limits - before.limits == (takes_lock ? 1U : 0U));
    if (!result) return; /* Write has no result argument to invalidate. */
    before = observe();
    assert(vinix_pci_config_write(domain, bus, slot, function, offset, width, UINT32_MAX) == expected);
    preserved(before); after = observe();
    assert(after.reads == before.reads && after.writes == before.writes);
    assert(after.attempts - before.attempts == (takes_lock ? 1U : 0U));
    assert(after.locks - before.locks == (takes_lock ? 1U : 0U));
    assert(after.unlocks - before.unlocks == (takes_lock ? 1U : 0U));
    assert(after.limits - before.limits == (takes_lock ? 1U : 0U));
}
static void validation_tests(void)
{
    for (unsigned int state = 0; state < 2; state++) {
        interrupts = !state; pins = state ? 2 : 0;
        check_bad(0, 0, 1, 0, 0, 4, VINIX_PCI_CONFIG_BAD_REGISTER, false, false);
        check_bad(1, 0, 1, 0, 0, 4, VINIX_PCI_CONFIG_BAD_REGISTER, false, false);
        check_bad(0, 256, 1, 0, 0, 4, VINIX_PCI_CONFIG_BAD_REGISTER, true, false);
        check_bad(0, UINT32_MAX, 1, 0, 0, 4, VINIX_PCI_CONFIG_BAD_REGISTER, true, false);
        check_bad(0, 0, 32, 0, 0, 4, VINIX_PCI_CONFIG_BAD_REGISTER, true, false);
        check_bad(0, 0, 1, 8, 0, 4, VINIX_PCI_CONFIG_BAD_REGISTER, true, false);
        static const uint32_t invalid_widths[] = { 0, 3, 8, UINT32_MAX };
        for (size_t i = 0; i < sizeof(invalid_widths) / sizeof(invalid_widths[0]); i++)
            check_bad(0, 0, 1, 0, 0, invalid_widths[i], VINIX_PCI_CONFIG_BAD_REGISTER, true, false);
        check_bad(0, 0, 1, 0, 1, 2, VINIX_PCI_CONFIG_BAD_REGISTER, true, false);
        check_bad(0, 0, 1, 0, 2, 4, VINIX_PCI_CONFIG_BAD_REGISTER, true, false);
        check_bad(1, 0, 1, 0, 0, 4, VINIX_PCI_CONFIG_UNAVAILABLE, true, false);
        check_bad(UINT32_MAX, 0, 1, 0, UINT64_MAX, 1, VINIX_PCI_CONFIG_UNAVAILABLE, true, false);
        check_bad(1, 256, 1, 0, 0, 4, VINIX_PCI_CONFIG_BAD_REGISTER, true, false);
        check_bad(0, 3, 1, 0, 0, 4, VINIX_PCI_CONFIG_UNAVAILABLE, true, true);
        check_bad(0, 0, 1, 0, 256, 1, VINIX_PCI_CONFIG_BAD_REGISTER, true, true);
        check_bad(0, 7, 31, 7, 4096, 4, VINIX_PCI_CONFIG_BAD_REGISTER, true, true);
        check_bad(0, 0, 1, 0, UINT64_C(0x100000000), 4, VINIX_PCI_CONFIG_BAD_REGISTER, true, true);
        check_bad(0, 0, 1, 0, UINT64_MAX, 1, VINIX_PCI_CONFIG_BAD_REGISTER, true, true);
        check_bad(0, 0, 1, 0, UINT64_MAX - 1, 2, VINIX_PCI_CONFIG_BAD_REGISTER, true, true);
        check_bad(0, 7, 31, 7, UINT64_MAX - 3, 4, VINIX_PCI_CONFIG_BAD_REGISTER, true, true);
    }
    interrupts = true; pins = 0;
}
static uint32_t word(const unsigned char *bytes, uint32_t width)
{
    uint32_t value = 0;
    for (uint32_t i = 0; i < width; i++) value |= (uint32_t)bytes[i] << (8 * i);
    return value;
}
static void width_tests(void)
{
    static const uint32_t widths[] = { 1, 2, 4 };
    for (size_t device_index = 0; device_index < sizeof(devices) / sizeof(devices[0]); device_index++) {
        struct test_device *device = &devices[device_index];
        uint32_t limit = device->bus == 7 ? 4096 : 256;
        for (uint32_t byte = 0; byte < 4096; byte++) device->bytes[byte] = (unsigned char)(byte * 37 + device_index);
        for (size_t w = 0; w < 3; w++) {
            uint32_t width = widths[w];
            for (uint32_t offset = 0; offset < limit; offset += width) {
                struct observed before = observe();
                uint32_t value = 0;
                assert(!vinix_pci_config_read(0, device->bus, device->slot, device->function, offset, width, &value));
                assert(value == word(device->bytes + offset, width));
                preserved(before);
                if (width > 1) check_bad(0, device->bus, device->slot, device->function,
                        offset + 1, width, VINIX_PCI_CONFIG_BAD_REGISTER, true, false);
            }
            unsigned char expected[4096];
            memcpy(expected, device->bytes, sizeof(expected));
            uint32_t offset = limit - width;
            for (uint32_t i = 0; i < width; i++) expected[offset + i] = (unsigned char)(UINT32_C(0xa1b2c3d4) >> (8 * i));
            struct observed before = observe();
            assert(!vinix_pci_config_write(0, device->bus, device->slot, device->function, offset, width, UINT32_C(0xa1b2c3d4)));
            assert(!memcmp(expected, device->bytes, sizeof(expected)));
            assert(last_write_width == width && last_write_offset == offset);
            preserved(before);
        }
        /* Fixed interior byte lanes exercise CFC+1 and CFC+2 as well as
         * dword addressing. Only the selected bytes may change. */
        static const struct { uint32_t offset, width, value, result; } interior[] = {
            { 33, 1, UINT32_C(0xdeadbe76), UINT32_C(0x76) },
            { 34, 2, UINT32_C(0xbeef4321), UINT32_C(0x4321) },
            { 36, 4, UINT32_C(0x98765432), UINT32_C(0x98765432) },
        };
        for (size_t i = 0; i < sizeof(interior) / sizeof(interior[0]); i++) {
            unsigned char expected[4096];
            memcpy(expected, device->bytes, sizeof(expected));
            for (uint32_t byte = 0; byte < interior[i].width; byte++)
                expected[interior[i].offset + byte] = (unsigned char)(interior[i].result >> (8 * byte));
            struct observed before = observe();
            assert(!vinix_pci_config_write(0, device->bus, device->slot, device->function,
                    interior[i].offset, interior[i].width, interior[i].value));
            assert(!memcmp(expected, device->bytes, sizeof(expected)));
            assert(last_write_width == interior[i].width && last_write_offset == interior[i].offset &&
                   last_write_value == interior[i].result);
            uint32_t result = 0;
            assert(!vinix_pci_config_read(0, device->bus, device->slot, device->function,
                    interior[i].offset, interior[i].width, &result));
            assert(result == interior[i].result);
            preserved(before);
        }
    }
    oversized_reads = true;
    for (size_t w = 0; w < 3; w++) {
        uint32_t value = 0;
        assert(!vinix_pci_config_read(0, 0, 1, 0, 16, widths[w], &value));
        assert(value == word(devices[0].bytes + 16, widths[w]));
        assert(!vinix_pci_config_read(0, 7, 30, 6, 0, widths[w], &value));
        assert(value == (widths[w] == 1 ? UINT32_C(0xff) : widths[w] == 2 ? UINT32_C(0xffff) : UINT32_MAX));
        unsigned char before[4096]; memcpy(before, devices[2].bytes, sizeof(before));
        assert(!vinix_pci_config_write(0, 7, 30, 6, 0, widths[w], UINT32_MAX));
        assert(!memcmp(before, devices[2].bytes, sizeof(before)));
    }
    oversized_reads = false;
}
static void command_tests(void)
{
    static const struct { uint16_t initial, clear, set, expected; bool changed; } cases[] = {
        { 0x1234, 0x000f, 0x0003, 0x1233, true },
        { 0xffff, 0xffff, 0x5a3c, 0x5a3c, true },
        { 0x1234, 0, 0, 0x1234, false },
        { 0x1234, 0x0004, 0x0004, 0x1234, false },
    };
    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        struct test_device *device = &devices[0];
        device->bytes[4] = (unsigned char)cases[i].initial; device->bytes[5] = (unsigned char)(cases[i].initial >> 8);
        device->bytes[6] = 0xa5; device->bytes[7] = 0x5a;
        struct observed before = observe();
        assert(!vinix_pci_config_update_command(0, 0, 1, 0, cases[i].clear, cases[i].set));
        assert(word(device->bytes + 4, 2) == cases[i].expected);
        assert(device->bytes[6] == 0xa5 && device->bytes[7] == 0x5a);
        struct observed after = observe();
        assert(after.locks == before.locks + 1 && after.unlocks == before.unlocks + 1);
        assert(after.reads == before.reads + 1 && after.writes == before.writes + cases[i].changed);
        assert(last_read_width == 2);
        if (cases[i].changed) assert(last_write_width == 2 && last_write_offset == 4 && last_write_value == cases[i].expected);
        preserved(before);
    }
    /* Real width mutations, including intentional direct RW1C STATUS writes. */
    devices[0].bytes[6] = 0xff; devices[0].bytes[7] = 0xff;
    assert(!vinix_pci_config_write(0, 0, 1, 0, 6, 1, 0x0f));
    assert(devices[0].bytes[6] == 0xf0 && devices[0].bytes[7] == 0xff);
    assert(!vinix_pci_config_write(0, 0, 1, 0, 6, 2, 0xf00f));
    assert(devices[0].bytes[6] == 0xf0 && devices[0].bytes[7] == 0x0f);
    struct observed before = observe();
    assert(vinix_pci_config_update_command(1, 0, 1, 0, 0, 1) == VINIX_PCI_CONFIG_UNAVAILABLE);
    assert(vinix_pci_config_update_command(0, 256, 1, 0, 0, 1) == VINIX_PCI_CONFIG_BAD_REGISTER);
    assert(vinix_pci_config_update_command(0, 0, 32, 0, 0, 1) == VINIX_PCI_CONFIG_BAD_REGISTER);
    assert(vinix_pci_config_update_command(0, 0, 1, 8, 0, 1) == VINIX_PCI_CONFIG_BAD_REGISTER);
    assert(observe().locks == before.locks && observe().reads == before.reads && observe().writes == before.writes);
    assert(vinix_pci_config_update_command(0, 3, 1, 0, 0, 1) == VINIX_PCI_CONFIG_UNAVAILABLE);
    assert(!vinix_pci_config_update_command(0, 0, 30, 0, 1, 0)); /* Absent hardware ignores writes. */
    preserved(before);
}

struct actor { uint32_t slot, value; uint16_t set; unsigned int done; bool command; };
static void *actor_run(void *argument)
{
    struct actor *actor = argument;
    interrupts = false; pins = 2;
    struct observed before = observe();
    if (actor->command) assert(!vinix_pci_config_update_command(0, 0, actor->slot, 0, 0, actor->set));
    else assert(!vinix_pci_config_read(0, 0, actor->slot, 0, 0x40, 4, &actor->value));
    preserved(before);
    __atomic_store_n(&actor->done, 1, __ATOMIC_RELEASE);
    return NULL;
}
static void concurrent_tests(void)
{
    for (unsigned int command = 0; command < 2; command++) {
        devices[0].bytes[4] = devices[0].bytes[5] = 0;
        devices[0].bytes[6] = 0xa5; devices[0].bytes[7] = 0x5a;
        devices[0].bytes[0x40] = 0x11; devices[1].bytes[0x40] = 0x22;
        devices[0].bytes[0x41] = devices[0].bytes[0x42] = devices[0].bytes[0x43] = 0;
        devices[1].bytes[0x41] = devices[1].bytes[0x42] = devices[1].bytes[0x43] = 0;
        struct actor a = { .slot = 1, .set = 1, .command = !!command };
        struct actor b = { .slot = command ? 1 : 2, .set = 2, .command = !!command };
        pthread_t first, second;
        gate_slot = 1; gate_offset = command ? 4 : 0x40;
        __atomic_store_n(&gate_entered, 0, __ATOMIC_RELEASE);
        __atomic_store_n(&gate_release, 0, __ATOMIC_RELEASE);
        __atomic_store_n(&gate_armed, 1, __ATOMIC_RELEASE);
        unsigned int start_attempts = observe().attempts;
        assert(!pthread_create(&first, NULL, actor_run, &a));
        wait_flag(&gate_entered, 1);
        uint32_t captured = __atomic_load_n(&cf8, __ATOMIC_ACQUIRE);
        assert(!pthread_create(&second, NULL, actor_run, &b));
        wait_flag(&attempts, start_attempts + 2);
        assert(!__atomic_load_n(&a.done, __ATOMIC_ACQUIRE) && !__atomic_load_n(&b.done, __ATOMIC_ACQUIRE));
        assert(__atomic_load_n(&cf8, __ATOMIC_ACQUIRE) == captured);
        __atomic_store_n(&gate_release, 1, __ATOMIC_RELEASE);
        assert(!pthread_join(first, NULL) && !pthread_join(second, NULL));
        assert(a.done && b.done);
        if (command) {
            assert(word(devices[0].bytes + 4, 2) == 3);
            assert(devices[0].bytes[6] == 0xa5 && devices[0].bytes[7] == 0x5a);
        } else assert(a.value == 0x11 && b.value == 0x22);
    }
}
int main(void)
{
    validation_tests(); width_tests(); command_tests(); concurrent_tests();
    assert(!locked && interrupts && !pins && !allocations);
    assert(observe().locks == observe().unlocks);
    assert(!pthread_mutex_destroy(&transport));
    puts("PCI config: PASS (actual core, widths/bounds, CF8 serialization, RW1C-safe COMMAND, no core allocations; host model only)");
    return 0;
}

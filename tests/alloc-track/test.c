/* Independent live-count, call-chain and bounded-output instrumentation fixture. */
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

void vinix_alloc_track_enter(void *, uint64_t, uint64_t *);
void alloc_untrack(void *);
void alloc_track_start(void);
uint64_t alloc_track_dump(char *, uint64_t, uint64_t);

static uint64_t frames[20];
static char output[30000];
static void record(unsigned index, unsigned size) {
    vinix_alloc_track_enter((void *)(uintptr_t)(0x10000 + 16 * index), size, frames);
}
static void check(unsigned expected, unsigned count16, unsigned count32) {
    uint64_t n = alloc_track_dump(output, sizeof(output) - 1, 1);
    assert(n < sizeof(output));
    output[n] = 0;
    unsigned live, dropped;
    assert(sscanf(output, "live %u dropped %u", &live, &dropped) == 2);
    assert(live == expected && dropped == 0);
    unsigned seen16 = 0, seen32 = 0;
    for (char *p = strchr(output, '\n') + 1; *p; p = strchr(p, '\n') + 1) {
        unsigned count, size;
        unsigned long long pcs[10];
        assert(sscanf(p, "%u %u %llx %llx %llx %llx %llx %llx %llx %llx %llx %llx",
                      &count, &size, &pcs[0], &pcs[1], &pcs[2], &pcs[3], &pcs[4],
                      &pcs[5], &pcs[6], &pcs[7], &pcs[8], &pcs[9]) == 12);
        for (unsigned j = 0; j < 10; j++) assert(pcs[j] == 0x1000 + j);
        if (size == 16) seen16 += count;
        else { assert(size == 32); seen32 += count; }
    }
    assert(seen16 == count16 && seen32 == count32);
}
int main(void) {
    for (unsigned i = 0; i < 10; i++) {
        frames[i * 2] = i < 9 ? (uintptr_t)&frames[(i + 1) * 2] : 0;
        frames[i * 2 + 1] = 0x1000 + i;
    }
    record(1, 16);
    check(0, 0, 0);
    alloc_track_start();
    for (unsigned i = 1; i <= 8192; i++) record(i, i & 1 ? 16 : 32);
    check(8192, 4096, 4096);
    /* Updating a pointer replaces its record, without adding another live slot. */
    record(1, 32);
    check(8192, 4095, 4097);
    for (unsigned i = 1; i <= 8192; i += 2) alloc_untrack((void *)(uintptr_t)(0x10000 + 16 * i));
    check(4096, 0, 4096);
    for (unsigned i = 2; i <= 8192; i += 2) alloc_untrack((void *)(uintptr_t)(0x10000 + 16 * i));
    check(0, 0, 0);
    for (unsigned i = 1; i <= 1024; i++) record(i, 16);
    check(1024, 1024, 0);
    char golden[sizeof(output)];
    uint64_t full = alloc_track_dump(golden, sizeof(golden), 1);
    for (unsigned cap = 0; cap <= full + 2; cap++) {
        memset(output, 0xa5, sizeof(output));
        uint64_t count = alloc_track_dump(output, cap, 1);
        assert(count == (cap < full ? cap : full));
        assert(!memcmp(output, golden, count));
        assert((unsigned char)output[cap] == 0xa5);
    }
    alloc_track_start();
    check(0, 0, 0);
    alloc_untrack(NULL);
    record(1, 16);
    alloc_untrack((void *)(uintptr_t)0x1234);
    check(1, 1, 0);
    return 0;
}

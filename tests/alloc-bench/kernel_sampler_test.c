/* Independent C ABI/ownership fixture for the production V sampler. */
#include <assert.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int alloc_kernel_bench(void);
int kmod_alloc_start(void *, void *);
int kmod_alloc_stop(void *, void *);
static size_t attempts, frees, live, fail_at = SIZE_MAX, poison_at = SIZE_MAX;
static uint64_t tick;
static int constant_clock;
static char output[16384];
static size_t output_size;
void *vkb_test_alloc(size_t size) {
    size_t attempt = attempts++;
    if (attempt == fail_at) return NULL;
    unsigned char *pointer = calloc(1, size);
    assert(pointer);
    live++;
    if (attempt == poison_at) pointer[size - 1] = 0x7e;
    return pointer;
}
void vkb_test_free(void *pointer) { assert(pointer && live); live--; frees++; free(pointer); }
uint64_t vkb_test_ticks(void) { if (!constant_clock) tick += 1000; return tick; }
int vkb_test_log(const char *format, ...) {
    va_list args;
    va_start(args, format);
    int length = vsnprintf(output + output_size, sizeof(output) - output_size, format, args);
    va_end(args);
    assert(length > 0 && (size_t)length < sizeof(output) - output_size);
    output_size += (size_t)length;
    return length;
}
static void reset(void) {
    assert(!live);
    attempts = frees = 0;
    fail_at = poison_at = SIZE_MAX;
    tick = 0;
    constant_clock = 0;
    output_size = 0;
    output[0] = 0;
}
int main(void) {
    reset();
    assert(alloc_kernel_bench() == 0 && !live);
    assert(attempts == 674496 && frees == attempts);
    assert(strstr(output, "KALLOC-DONE platform=vinix phases=3 checksum=27358432\n"));
    assert(strstr(output, "phase=hot64 pairs=100000 samples=5 warmup_pairs=100000 median_ticks=1000 min_ticks=1000 max_ticks=1000 median_ticks_per_pair=0 checksum=25486688\n"));
    assert(strstr(output, "phase=mixed256 pairs=12288 samples=5 warmup_pairs=12288 median_ticks=1000 min_ticks=1000 max_ticks=1000 median_ticks_per_pair=0 checksum=1855488\n"));
    assert(strstr(output, "phase=big262144 pairs=128 samples=5 warmup_pairs=128 median_ticks=1000 min_ticks=1000 max_ticks=1000 median_ticks_per_pair=7 checksum=16256\n"));
    size_t failures[] = {0, 600019, 673745};
    for (size_t i = 0; i < sizeof(failures)/sizeof(failures[0]); i++) {
        reset(); fail_at = failures[i];
        assert(alloc_kernel_bench() == 1 && !live && frees + 1 == attempts);
        assert(strstr(output, "reason=allocation_failed"));
        assert(!strstr(output, "KALLOC-DONE"));
    }
    size_t poison[] = {7, 600019, 673745};
    for (size_t i = 0; i < sizeof(poison)/sizeof(poison[0]); i++) {
        reset(); poison_at = poison[i];
        assert(alloc_kernel_bench() == 1 && !live && frees == attempts);
        assert(strstr(output, "reason=nonzero_allocation"));
        assert(strstr(output, "value=126\n"));
    }
    reset(); constant_clock = 1;
    assert(alloc_kernel_bench() == 1 && !live && frees == attempts);
    assert(strstr(output, "reason=nonmonotonic_tsc"));
    reset(); fail_at = 0;
    assert(kmod_alloc_start(NULL, NULL) == 5 && !live);
    assert(kmod_alloc_stop(NULL, NULL) == 0);
    puts("Shared kernel allocator sampler: success, three-phase OOM/zeroing rollback, TSC failure and kext ABI passed");
    return 0;
}

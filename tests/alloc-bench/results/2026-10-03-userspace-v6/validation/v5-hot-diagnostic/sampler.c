#define _GNU_SOURCE
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <dlfcn.h>
#define hidden __attribute__((__visibility__("hidden")))
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wsign-compare"
#pragma GCC diagnostic ignored "-Wunused-parameter"
#include "headers/src/malloc/mallocng/meta.h"
#pragma GCC diagnostic pop
#undef malloc
#undef free
#undef realloc
#undef mmap
#undef madvise
#undef mremap
#undef ctx
#undef size_classes
#undef brk
#define main original_benchmark_main
#include "bench.c"
#undef main

static struct malloc_context *diag_context;
static struct __libc *diag_libc;
static volatile int *diag_lock;
static const uint16_t *diag_classes;

static int setup(void)
{
#ifdef STATIC_CONTEXT
    diag_context = &__malloc_context;
    diag_libc = &__libc;
    diag_lock = __malloc_lock;
    diag_classes = __malloc_size_classes;
#else
    Dl_info info;
    /* Non-PIE GCC takes malloc's address through the executable PLT.
     * Resolve its definition in the next DSO before asking for its base. */
    void *actual_malloc = dlsym(RTLD_NEXT, "malloc");
    if (!actual_malloc || !dladdr(actual_malloc, &info) || !info.dli_fbase ||
        (!strstr(info.dli_fname, "ld-musl-x86_64.so.1") &&
         !strstr(info.dli_fname, "libc.musl-x86_64.so.1")))
        return 1;
    uintptr_t base = (uintptr_t)info.dli_fbase;
    diag_context = (void *)(base + 0xa6b00);
    diag_libc = (void *)(base + 0xa68c0);
    diag_lock = (void *)(base + 0xa9038);
    diag_classes = (void *)(base + 0x9a340);
#endif
    return 0;
}

/* Inspect only a currently live allocation supplied by the unchanged libc. */
static struct meta *group_of(unsigned char *p, unsigned *index)
{
    unsigned offset = *(uint16_t *)(p - 2);
    *index = p[-3] & 31;
    if (p[-4]) offset = *(uint32_t *)(p - 8);
    struct group *group = (void *)(p - UNIT * offset - UNIT);
    struct meta *meta = group->meta;
    if (meta->mem != group || *index > meta->last_idx)
        __builtin_trap();
    return meta;
}

static void state(const char *phase)
{
    struct meta *g = diag_context->active[4];
    if (!g) {
        printf("DIAG-STATE phase=%s group=none need_locks=%d lock=%d\n",
            phase, (int)diag_libc->need_locks, *diag_lock);
        return;
    }
    unsigned groups = 1;
    for (struct meta *m = g->next; m && m != g && groups < 64; m = m->next)
        ++groups;
    size_t stride = !g->last_idx && g->maplen ?
        g->maplen * 4096UL - UNIT : UNIT * diag_classes[g->sizeclass];
    printf("DIAG-STATE phase=%s class=%u slots=%u maplen=%zu nested=%u"
        " sole=%u group_count=%u active_idx=%u avail=%u freed=%u"
        " stride=%zu full_stride=%u usage=%zu need_locks=%d lock=%d"
        " mem_page_offset=%zu meta_cacheline_offset=%zu\n",
        phase, (unsigned)g->sizeclass, (unsigned)g->last_idx + 1,
        (size_t)g->maplen, !g->maplen, g->next == g, groups,
        (unsigned)g->mem->active_idx, (unsigned)g->avail_mask,
        (unsigned)g->freed_mask, stride,
        stride >= UNIT * diag_classes[g->sizeclass],
        diag_context->usage_by_class[g->sizeclass],
        (int)diag_libc->need_locks, *diag_lock,
        (size_t)((uintptr_t)g->mem & 4095),
        (size_t)((uintptr_t)g & 63));
}

static int probe(const char *phase)
{
    unsigned slots[32] = {0}, class_count[48] = {0};
    unsigned sole = 0, nested = 0, full = 0, eligible = 0;
    unsigned lock_zero = 0, need_zero = 0, need_negative = 0;
    unsigned group_changes = 0, reserved_min = 32, reserved_max = 0;
    unsigned offset_min = UINT_MAX, offset_max = 0;
    struct meta *prior = NULL;
    for (unsigned i = 0; i < 32; ++i) {
        unsigned char *p = malloc(64);
        if (!p) return 1;
        unsigned idx;
        struct meta *g = group_of(p, &idx);
        if (g->sizeclass >= 48) return 1;
        size_t stride = !g->last_idx && g->maplen ?
            g->maplen * 4096UL - UNIT : UNIT * diag_classes[g->sizeclass];
        size_t footprint = g->maplen ? g->maplen * 4096UL :
            UNIT + stride * (g->last_idx + 1);
        sole += g->next == g;
        nested += !g->maplen;
        full += stride >= UNIT * diag_classes[g->sizeclass];
        eligible += !diag_libc->need_locks && g->next == g &&
            stride >= UNIT * diag_classes[g->sizeclass] &&
            footprint <= RETAIN_GROUP_MAX_BYTES;
        need_zero += diag_libc->need_locks == 0;
        need_negative += diag_libc->need_locks < 0;
        lock_zero += *diag_lock == 0;
        group_changes += prior && prior != g;
        prior = g;
        ++slots[idx];
        ++class_count[g->sizeclass];
        unsigned reserved = p[-3] >> 5;
        if (reserved < reserved_min) reserved_min = reserved;
        if (reserved > reserved_max) reserved_max = reserved;
        unsigned offset = *(uint16_t *)(p - 2);
        if (offset < offset_min) offset_min = offset;
        if (offset > offset_max) offset_max = offset;
        free(p);
    }
    printf("DIAG-PROBE phase=%s pairs=32 class4=%u sole=%u nested=%u"
        " full_stride=%u eligible=%u lock_zero=%u need_zero=%u"
        " need_negative=%u group_changes=%u reserved_min=%u reserved_max=%u"
        " offset_min=%u offset_max=%u slots=",
        phase, class_count[4], sole, nested, full, eligible, lock_zero,
        need_zero, need_negative, group_changes, reserved_min, reserved_max,
        offset_min, offset_max);
    for (unsigned i = 0; i < 32; ++i)
        if (slots[i]) printf("%u:%u,", i, slots[i]);
    putchar('\n');
    return 0;
}

static int hot_samples(const char *phase)
{
    struct outcome out = {0};
    if (malloc_hot(200000, &out) || out.checksum != out.expected) return 1;
    state(phase);
    if (probe(phase)) return 1;
    for (unsigned sample = 0; sample < 7; ++sample) {
        uint64_t start, end, cpu_start, cpu_end;
        struct timespec cpu_time;
        struct outcome sample_out = {0};
        if (clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &cpu_time)) return 1;
        cpu_start = (uint64_t)cpu_time.tv_sec * UINT64_C(1000000000) + cpu_time.tv_nsec;
        if (now_ns(&start) || malloc_hot(200000, &sample_out) ||
            now_ns(&end) || sample_out.checksum != sample_out.expected)
            return 1;
        if (clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &cpu_time)) return 1;
        cpu_end = (uint64_t)cpu_time.tv_sec * UINT64_C(1000000000) + cpu_time.tv_nsec;
        printf("DIAG-HOT phase=%s sample=%u pairs=200000 elapsed_ns=%" PRIu64
            " ns_per_pair=%.3f cpu_ns=%" PRIu64 " checksum=%" PRIu64 "\n", phase, sample + 1,
            end - start, (double)(end - start) / 200000.0, cpu_end - cpu_start, sample_out.checksum);
    }
    state("after-samples");
    return probe("after-samples");
}

int main(void)
{
    if (setup()) return 1;
    struct options options = {200000, 7, "private_state_sampler"};
    /* Same metadata path as the canonical benchmark precedes its first hot
     * warmup. Diagnostic probes are outside the unchanged payload loops. */
    if (print_metadata(&options)) return 1;
    state("after-metadata");
    if (hot_samples("fresh-hot")) return 1;
    struct outcome mixed = {0};
    if (malloc_mixed(200000, &mixed) || mixed.checksum != mixed.expected)
        return 1;
    state("after-mixed");
    if (hot_samples("post-mixed-hot")) return 1;
    puts("DIAG-SAMPLER-DONE");
    return 0;
}

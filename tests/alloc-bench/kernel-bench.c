/* Standalone kext ABI: link the generated V sampler object separately. */
#include "../../kernel/c/heap_benchmark_v.h"
int alloc_kernel_bench(void);
int kmod_alloc_start(void *, void *);
int kmod_alloc_stop(void *, void *);

// Private ABI between Vinix's source-built Android musl and its Bionic facade.
#ifndef VINIX_ANDROID_MUSL_STATISTICS_H
#define VINIX_ANDROID_MUSL_STATISTICS_H
#include <stddef.h>

struct vinix_malloc_stats {
    size_t mapped_bytes;
    size_t live_bytes;
    size_t free_bytes;
    size_t peak_mapped_bytes;
    size_t peak_live_bytes;
    size_t live_blocks;
    size_t free_blocks;
    size_t mapped_blocks;
};

int __vinix_malloc_stats(struct vinix_malloc_stats *, size_t);
#endif

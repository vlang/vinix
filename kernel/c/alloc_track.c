// Native capture keeps the first recorded frame at the original C ABI entry.
#ifdef VINIX_ALLOC_TRACK
#include "alloc_track_v.h"
void alloc_track(void *pointer, uint64_t size) {
    vinix_alloc_track_enter(pointer, size, __builtin_frame_address(0));
    /* The captured frame must remain alive throughout the synchronous walk. */
    __asm__ volatile("" ::: "memory");
}
#endif

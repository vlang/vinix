#ifndef VINIX_ALLOC_TRACK_V_H
#define VINIX_ALLOC_TRACK_V_H
#include <stdint.h>
void vinix_alloc_track_enter(void *, uint64_t, uint64_t *);
void alloc_untrack(void *);
void alloc_track_start(void);
uint64_t alloc_track_dump(char *, uint64_t, uint64_t);
#endif

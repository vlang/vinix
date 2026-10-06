#ifndef VINIX_ALLOC_TRACK_FIXTURE_ABI_H
#define VINIX_ALLOC_TRACK_FIXTURE_ABI_H
#include <assert.h>
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
typedef unsigned long long vtrack_ull;
_Static_assert(sizeof(vtrack_ull) == sizeof(uint64_t), "original scanf storage width");
void vinix_alloc_track_enter(void *, uint64_t, uint64_t *);
void alloc_untrack(void *);
void alloc_track_start(void);
uint64_t alloc_track_dump(char *, uint64_t, uint64_t);
#endif

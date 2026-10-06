#ifndef VINIX_ALLOC_TRACK_GUEST_NATIVE_ABI_H
#define VINIX_ALLOC_TRACK_GUEST_NATIVE_ABI_H
#ifndef _GNU_SOURCE
#define _GNU_SOURCE 1
#endif
#include <stdint.h>
#include <stdio.h>
#include <fcntl.h>
#include <string.h>
#include <unistd.h>
typedef unsigned long long vtrack_guest_ull;
_Static_assert(sizeof(vtrack_guest_ull) == sizeof(uint64_t), "original native scan width");
#endif

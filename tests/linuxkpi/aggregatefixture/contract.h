/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Foreign type and compiler metadata only. All executable fixture code is V. */
#ifndef VINIX_AGGREGATE_EXCHANGE_FIXTURE_H
#define VINIX_AGGREGATE_EXCHANGE_FIXTURE_H
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#define u64 vag_linux_u64
#define timezone vag_linux_timezone
#define ffs vag_linux_ffs
#define fls vag_linux_fls
#include <linux/atomic.h>
#include <asm/pgtable_types.h>
#undef u64
#undef timezone
#undef ffs
#undef fls
typedef struct { uint8_t bits; } vag_record1;
typedef struct { uint16_t bits; } vag_record2;
typedef struct { uint32_t bits; } vag_record4;
typedef struct { uint64_t bits; } vag_record8;
typedef union { uint8_t bits; } vag_union1;
typedef union { uint16_t bits; } vag_union2;
typedef union { uint32_t bits; } vag_union4;
typedef union { uint64_t bits; } vag_union8;
typedef volatile vag_record8 vag_volatile_record8;
typedef pthread_t vag_thread;
typedef struct { uint32_t ordinal; } vag_actor;
#define VAG_LAYOUT(type, width) _Static_assert(sizeof(type) == (width) && __alignof__(type) == (width), "natural atomic aggregate layout")
VAG_LAYOUT(vag_record1, 1);
VAG_LAYOUT(vag_record2, 2);
VAG_LAYOUT(vag_record4, 4);
VAG_LAYOUT(vag_record8, 8);
VAG_LAYOUT(vag_union1, 1);
VAG_LAYOUT(vag_union2, 2);
VAG_LAYOUT(vag_union4, 4);
VAG_LAYOUT(vag_union8, 8);
VAG_LAYOUT(pte_t, 8);
VAG_LAYOUT(pmd_t, 8);
/* Qualifiers and widths below exercise rejected compiler boundaries. */
typedef const vag_record8 vag_const_record8;
typedef float vag_float;
typedef double vag_double;
typedef uint64_t vag_array8[1];
typedef struct { uint8_t bytes[3]; } vag_record3;
typedef struct __attribute__((packed)) { uint64_t bits; } vag_packed8;
typedef struct __attribute__((aligned(16))) { uint64_t low, high; } vag_record16;
typedef unsigned __int128 vag_integer16;
_Static_assert(sizeof(vag_packed8) == 8 && __alignof__(vag_packed8) == 1, "packed negative control");
_Static_assert(sizeof(vag_record16) == 16 && __alignof__(vag_record16) == 16 && sizeof(vag_integer16) == 16, "aggregate width cap is independent of alignment and prior scalar wide dispatch");
#endif

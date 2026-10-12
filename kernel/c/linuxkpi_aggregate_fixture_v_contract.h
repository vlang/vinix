/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Native fixture metadata only; all checks and operations are implemented in V. */
#ifndef VINIX_LINUXKPI_AGGREGATE_FIXTURE_V_CONTRACT_H
#define VINIX_LINUXKPI_AGGREGATE_FIXTURE_V_CONTRACT_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#include <string.h>

/* Keep original Linux aliases separate from the native V blob's LP64 names. */
#define u64 vaf_linux_u64
#define timezone vaf_linux_timezone
#define ffs vaf_linux_ffs
#define fls vaf_linux_fls
#include <linux/atomic.h>
#include <asm/pgtable_types.h>
#undef u64
#undef timezone
#undef ffs
#undef fls

typedef struct { uint8_t bits; } vaf_record1;
typedef struct { uint16_t bits; } vaf_record2;
typedef struct { uint32_t bits; } vaf_record4;
typedef struct { uint64_t bits; } vaf_record8;
typedef union { uint8_t bits; } vaf_union1;
typedef union { uint16_t bits; } vaf_union2;
typedef union { uint32_t bits; } vaf_union4;
typedef union { uint64_t bits; } vaf_union8;

#define VAF_LAYOUT(type, width) \
    _Static_assert(sizeof(type) == (width) && __alignof__(type) == (width), \
        "Native aggregate fixture requires exact naturally aligned words")
VAF_LAYOUT(vaf_record1, 1);
VAF_LAYOUT(vaf_record2, 2);
VAF_LAYOUT(vaf_record4, 4);
VAF_LAYOUT(vaf_record8, 8);
VAF_LAYOUT(vaf_union1, 1);
VAF_LAYOUT(vaf_union2, 2);
VAF_LAYOUT(vaf_union4, 4);
VAF_LAYOUT(vaf_union8, 8);
VAF_LAYOUT(pte_t, 8);
VAF_LAYOUT(pmd_t, 8);
#undef VAF_LAYOUT

int vinix_linuxkpi_aggregate_fixture_queries(void);

#endif

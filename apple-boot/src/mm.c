// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Physical allocation and the page tables the kernel is entered with: 4 KiB
 * granule, four levels, 48-bit virtual addresses, as Limine builds them. */
#include "lib.h"
#include "loader.h"

uint64_t alloc_pages(struct allocator *allocator, uint64_t bytes, uint64_t alignment)
{
    if (alignment < PAGE_SIZE)
        alignment = PAGE_SIZE;
    uint64_t start = align_up(allocator->next, alignment);
    uint64_t length = align_up(bytes, PAGE_SIZE);
    if (start < allocator->next || start > allocator->end || allocator->end - start < length)
        loader_fail(0x0a01, bytes);
    allocator->next = start + length;
    return start;
}

uint64_t alloc_zeroed(struct allocator *allocator, uint64_t bytes, uint64_t alignment)
{
    uint64_t start = alloc_pages(allocator, bytes, alignment);
    memset((void *)(uintptr_t)start, 0, align_up(bytes, PAGE_SIZE));
    return start;
}

#define PTE_VALID (1ull << 0)
#define PTE_TABLE (1ull << 1) /* table at levels 0-2, page at level 3 */
#define PTE_ATTR(index) ((uint64_t)(index) << 2)
#define PTE_READ_ONLY (1ull << 7)
#define PTE_INNER_SHAREABLE (3ull << 8)
#define PTE_ACCESS (1ull << 10)
#define PTE_PXN (1ull << 53)
#define PTE_UXN (1ull << 54)
#define PTE_ADDRESS 0x0000fffffffff000ull

#define TABLE_BYTES 0x1000ull

static uint64_t new_table(struct pagemap *map)
{
    /* Tables are 4 KiB but the allocator hands out Apple pages; pack them. */
    static uint64_t chunk, chunk_used = PAGE_SIZE;

    if (chunk_used + TABLE_BYTES > PAGE_SIZE) {
        chunk = alloc_zeroed(map->allocator, PAGE_SIZE, PAGE_SIZE);
        chunk_used = 0;
    }
    uint64_t table = chunk + chunk_used;
    chunk_used += TABLE_BYTES;
    return table;
}

void pagemap_init(struct pagemap *map, struct allocator *allocator)
{
    map->allocator = allocator;
    map->root = new_table(map);
}

static uint64_t leaf_bits(unsigned attribute, unsigned flags)
{
    uint64_t bits = PTE_VALID | PTE_ATTR(attribute) | PTE_ACCESS | PTE_UXN;

    if (attribute != PTE_ATTR_DEVICE)
        bits |= PTE_INNER_SHAREABLE;
    if (!(flags & MAP_WRITE))
        bits |= PTE_READ_ONLY;
    if (!(flags & MAP_EXEC))
        bits |= PTE_PXN;
    return bits;
}

static uint64_t *next_level(struct pagemap *map, uint64_t *entry)
{
    if (!(*entry & PTE_VALID)) {
        *entry = new_table(map) | PTE_VALID | PTE_TABLE;
    } else if (!(*entry & PTE_TABLE)) {
        /* A block already covers this range; refuse to split it. */
        loader_fail(0x0b01, *entry);
    }
    return (uint64_t *)(uintptr_t)(*entry & PTE_ADDRESS);
}

void map_range(struct pagemap *map, uint64_t virt, uint64_t phys, uint64_t bytes,
               unsigned attribute, unsigned flags)
{
    uint64_t end = virt + align_up(bytes, 0x1000);
    uint64_t bits = leaf_bits(attribute, flags);

    if ((virt | phys) & 0xfff)
        loader_fail(0x0b02, virt | phys);
    while (virt < end) {
        uint64_t *level0 = (uint64_t *)(uintptr_t)map->root;
        uint64_t *level1 = next_level(map, &level0[(virt >> 39) & 511]);
        uint64_t *slot1 = &level1[(virt >> 30) & 511];
        if (!((virt | phys) & 0x3fffffff) && end - virt >= 0x40000000 && !(*slot1 & PTE_VALID)) {
            *slot1 = phys | bits; /* 1 GiB block */
            virt += 0x40000000;
            phys += 0x40000000;
            continue;
        }
        uint64_t *level2 = next_level(map, slot1);
        uint64_t *slot2 = &level2[(virt >> 21) & 511];
        if (!((virt | phys) & 0x1fffff) && end - virt >= 0x200000 && !(*slot2 & PTE_VALID)) {
            *slot2 = phys | bits; /* 2 MiB block */
            virt += 0x200000;
            phys += 0x200000;
            continue;
        }
        uint64_t *level3 = next_level(map, slot2);
        level3[(virt >> 12) & 511] = phys | bits | PTE_TABLE;
        virt += 0x1000;
        phys += 0x1000;
    }
}

// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

/* SPDX-License-Identifier: GPL-2.0-or-later */
/* The memory map handed to the kernel.
 *
 * iBoot's usable range is [phys_base, phys_base + mem_size). Coprocessor
 * firmware it has already loaded -- the "segment-ranges" of the ASC nodes
 * (SIO, DCP, ANS, ISP, ...) -- is live and must never be handed out, and
 * m1n1 reserves the same segments for Linux. The rest of the carveouts in
 * /chosen/carveout-memory-map lie outside the usable range (one of them is
 * the usable range itself), so they need nothing. */
#include "lib.h"
#include "loader.h"

#define SEGMENT_RANGE_BYTES 32 /* u64 phys, iova, remap; u32 size, flags */

static void add_reserved(struct reserved_set *set, uint64_t base, uint64_t end,
                         uint64_t ram_base, uint64_t ram_end)
{
    base &= ~(PAGE_SIZE - 1);
    end = align_up(end, PAGE_SIZE);
    if (base < ram_base)
        base = ram_base;
    if (end > ram_end)
        end = ram_end;
    if (end <= base)
        return;
    if (set->count == RESERVED_MAX_RANGES)
        loader_fail(0x0503, base);
    /* Kept sorted and merged, so the map built from it stays ordered. */
    unsigned index = set->count;
    while (index > 0 && set->ranges[index - 1].base > base) {
        set->ranges[index] = set->ranges[index - 1];
        index--;
    }
    set->ranges[index].base = base;
    set->ranges[index].end = end;
    set->count++;
    unsigned out = 0;
    for (unsigned in = 0; in < set->count; in++) {
        if (out > 0 && set->ranges[in].base <= set->ranges[out - 1].end) {
            if (set->ranges[in].end > set->ranges[out - 1].end)
                set->ranges[out - 1].end = set->ranges[in].end;
            continue;
        }
        set->ranges[out++] = set->ranges[in];
    }
    set->count = out;
}

static void collect_node(const struct adt *adt, size_t node, unsigned depth,
                         struct reserved_set *set, uint64_t ram_base, uint64_t ram_end)
{
    struct adt_property segments;

    if (!adt_get(adt, node, "segment-ranges", &segments)) {
        for (uint32_t at = 0; at + SEGMENT_RANGE_BYTES <= segments.length;
             at += SEGMENT_RANGE_BYTES) {
            uint64_t phys = load_le64(segments.value + at);
            uint64_t size = load_le32(segments.value + at + 24);
            if (size)
                add_reserved(set, phys, phys + size, ram_base, ram_end);
        }
    }
    if (depth == ADT_MAX_DEPTH)
        return;
    size_t child = adt_first_child(adt, node);
    for (uint32_t index = 0; index < adt_child_count(adt, node); index++) {
        collect_node(adt, child, depth + 1, set, ram_base, ram_end);
        child = adt_next_sibling(adt, child);
    }
}

void reserved_collect(const struct adt *adt, uint64_t ram_base, uint64_t ram_end,
                      struct reserved_set *set)
{
    set->count = 0;
    collect_node(adt, 0, 0, set, ram_base, ram_end);
}

uint64_t reserved_window(const struct reserved_set *set, uint64_t from, uint64_t end,
                         uint64_t bytes, uint64_t alignment)
{
    uint64_t base = align_up(from, alignment);

    for (unsigned index = 0; index < set->count; index++) {
        if (set->ranges[index].end <= base)
            continue;
        if (base + bytes <= set->ranges[index].base)
            break;
        base = align_up(set->ranges[index].end, alignment);
    }
    if (base + bytes > end || base + bytes < base)
        loader_fail(0x0504, bytes);
    return base;
}

static void insert(struct memmap *map, uint64_t base, uint64_t end, uint64_t type)
{
    if (end <= base)
        return;
    if (map->count == MEMMAP_MAX_ENTRIES)
        loader_fail(0x0501, base);
    /* Sorted by base, as Limine's map is. */
    unsigned index = map->count;
    while (index > 0 && map->entries[index - 1].base > base) {
        map->entries[index] = map->entries[index - 1];
        index--;
    }
    map->entries[index].base = base;
    map->entries[index].length = end - base;
    map->entries[index].type = type;
    map->count++;
}

void memmap_add(struct memmap *map, uint64_t base, uint64_t end, uint64_t type,
                const struct reserved_set *reserved)
{
    for (unsigned index = 0; index < reserved->count && base < end; index++) {
        const struct reserved_range *range = &reserved->ranges[index];
        if (range->end <= base)
            continue;
        if (range->base >= end)
            break;
        insert(map, base, range->base, type);
        base = range->end;
    }
    if (base < end)
        insert(map, base, end, type);
}

void memmap_add_reserved(struct memmap *map, const struct reserved_set *reserved)
{
    for (unsigned index = 0; index < reserved->count; index++)
        insert(map, reserved->ranges[index].base, reserved->ranges[index].end, MEMMAP_RESERVED);
}

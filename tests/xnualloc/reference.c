/*
 * Copyright (c) 2000-2020 Apple Inc. All rights reserved.
 *
 * @APPLE_OSREFERENCE_LICENSE_HEADER_START@
 *
 * This file contains Original Code and/or Modifications of Original Code
 * as defined in and that are subject to the Apple Public Source License
 * Version 2.0 (the 'License'). You may not use this file except in
 * compliance with the License. The rights granted to you under the License
 * may not be used to create, or enable the creation or redistribution of,
 * unlawful or unlicensed copies of an Apple operating system, or to
 * circumvent, violate, or enable the circumvention or violation of, any
 * terms of an Apple operating system software license agreement.
 *
 * Please obtain a copy of the License at
 * http://www.opensource.apple.com/apsl/ and read it before using this file.
 *
 * The Original Code and all software distributed under the License are
 * distributed on an 'AS IS' basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE, QUIET ENJOYMENT OR NON-INFRINGEMENT.
 * Please see the License for the specific language governing rights and
 * limitations under the License.
 *
 * @APPLE_OSREFERENCE_LICENSE_HEADER_END@
 */
/*
 * @OSF_COPYRIGHT@
 */
/*
 * Mach Operating System
 * Copyright (c) 1991,1990,1989,1988,1987 Carnegie Mellon University
 * All Rights Reserved.
 *
 * Permission to use, copy, modify and distribute this software and its
 * documentation is hereby granted, provided that both the copyright
 * notice and this permission notice appear in all copies of the
 * software, derivative works or modified versions, and any portions
 * thereof, and that both notices appear in supporting documentation.
 *
 * CARNEGIE MELLON ALLOWS FREE USE OF THIS SOFTWARE IN ITS "AS IS"
 * CONDITION.  CARNEGIE MELLON DISCLAIMS ANY LIABILITY OF ANY KIND FOR
 * ANY DAMAGES WHATSOEVER RESULTING FROM THE USE OF THIS SOFTWARE.
 *
 * Carnegie Mellon requests users of this software to return to
 *
 *  Software Distribution Coordinator  or  Software.Distribution@CS.CMU.EDU
 *  School of Computer Science
 *  Carnegie Mellon University
 *  Pittsburgh PA 15213-3890
 *
 * any improvements or extensions that they make and grant Carnegie Mellon
 * the rights to redistribute these changes.
 */
// Modified 2026-09-11: C-to-V translation and explicitly documented adaptations.
// Upstream: apple-oss-distributions/xnu f6217f891ac0bb64f3d375211650a4c1ff8ca1ea,
// osfmk/kern/zalloc.c. See docs/xnualloc/PORT_STATUS.md and
// kernel/modules/xnualloc/APPLE_LICENSE.
// These translations retain APSL 2.0; they are NOT relicensed as GPL.

/* C reference extracted from zalloc.c. Harness adaptations: prebacked arenas,
 * explicit pointer/count arguments for scans, and checked-exhaustion wrappers.
 * The split/coalesce/list formulas and bitmap scan/merge/free logic are kept.
 * This reference is NOT the translated V implementation.
 */
#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
#ifndef PAGE_MAX_SHIFT
#define PAGE_MAX_SHIFT 12
#endif
#define ZBA_CHUNK_SIZE (1u << PAGE_MAX_SHIFT)
#define ZBA_GRANULE sizeof(uint64_t)
#define ZBA_MAX_ORDER (PAGE_MAX_SHIFT - 4)
#define ZBA_SLOTS (ZBA_CHUNK_SIZE / ZBA_GRANULE)
#define ZBA_HEADS_COUNT (ZBA_MAX_ORDER + 1)
struct zone_bits_chain { uint32_t zbc_next, zbc_prev; };
struct zone_bits_head { uint32_t zbh_next, zbh_unused; };
struct zone_bits_allocator_meta {
    uint32_t zbam_left, zbam_right;
    struct zone_bits_head zbam_lists[ZBA_HEADS_COUNT];
    struct zone_bits_head zbam_lists_with_extra[ZBA_HEADS_COUNT];
};
struct zone_bits_allocator_header { uint64_t zbah_bits[ZBA_SLOTS / 64]; };
static uint8_t *arena;
static size_t arena_bytes;
static struct zone_bits_allocator_header *zba_base_header(void) { return (void *)arena; }
static struct zone_bits_allocator_meta *zba_meta(void) { return (void *)&zba_base_header()[1]; }
static uint64_t *zba_slot_base(void) { return (void *)arena; }
static struct zone_bits_head *zba_head(uint32_t order, bool with_extra) {
    return with_extra ? &zba_meta()->zbam_lists_with_extra[order] : &zba_meta()->zbam_lists[order];
}
static uint32_t zba_head_index(struct zone_bits_head *hd) { return (uint32_t)((uint64_t *)hd - zba_slot_base()); }
static struct zone_bits_chain *zba_chain_for_index(uint32_t index) { return (void *)(zba_slot_base() + index); }
static uint32_t zba_chain_to_index(const struct zone_bits_chain *zbc) { return (uint32_t)((const uint64_t *)zbc - zba_slot_base()); }
static void zba_push_block(struct zone_bits_chain *zbc, uint32_t order, bool with_extra) {
    struct zone_bits_head *hd = zba_head(order, with_extra);
    uint32_t hd_index = zba_head_index(hd), index = zba_chain_to_index(zbc);
    struct zone_bits_chain *next;
    if (hd->zbh_next) {
        next = zba_chain_for_index(hd->zbh_next);
        assert(next->zbc_prev == hd_index);
        next->zbc_prev = index;
    }
    zbc->zbc_next = hd->zbh_next;
    zbc->zbc_prev = hd_index;
    hd->zbh_next = index;
}
static void zba_remove_block(struct zone_bits_chain *zbc) {
    struct zone_bits_chain *prev = zba_chain_for_index(zbc->zbc_prev);
    uint32_t index = zba_chain_to_index(zbc);
    assert(prev->zbc_next == index);
    if ((prev->zbc_next = zbc->zbc_next)) {
        struct zone_bits_chain *next = zba_chain_for_index(zbc->zbc_next);
        assert(next->zbc_prev == index);
        next->zbc_prev = zbc->zbc_prev;
    }
}
static uintptr_t zba_try_pop_block(uint32_t order, bool with_extra) {
    struct zone_bits_head *hd = zba_head(order, with_extra);
    if (hd->zbh_next == 0) return 0;
    struct zone_bits_chain *zbc = zba_chain_for_index(hd->zbh_next);
    zba_remove_block(zbc);
    return (uintptr_t)zbc;
}
static struct zone_bits_allocator_header *zba_header(uintptr_t addr) { return (void *)(addr & -(uintptr_t)ZBA_CHUNK_SIZE); }
static size_t zba_node_parent(size_t node) { return (node - 1) / 2; }
static size_t zba_node_left_child(size_t node) { return node * 2 + 1; }
static size_t zba_node_buddy(size_t node) { return ((node - 1) ^ 1) + 1; }
static size_t zba_node(uintptr_t addr, uint32_t order) {
    uintptr_t offs = (addr % ZBA_CHUNK_SIZE) / ZBA_GRANULE;
    return (offs >> order) + (1u << (ZBA_MAX_ORDER - order + 1)) - 1;
}
static struct zone_bits_chain *zba_chain_for_node(struct zone_bits_allocator_header *zbah, size_t node, uint32_t order) {
    uintptr_t offs = (node - (1u << (ZBA_MAX_ORDER - order + 1)) + 1) << order;
    return (void *)((uintptr_t)zbah + offs * ZBA_GRANULE);
}
static void zba_node_flip_split(struct zone_bits_allocator_header *zbah, size_t node) { zbah->zbah_bits[node / 64] ^= 1ull << (node % 64); }
static bool zba_node_is_split(struct zone_bits_allocator_header *zbah, size_t node) { return zbah->zbah_bits[node / 64] & (1ull << (node % 64)); }
static void zba_free(uintptr_t addr, uint32_t order, bool with_extra) {
    struct zone_bits_allocator_header *zbah = zba_header(addr);
    size_t node = zba_node(addr, order);
    while (node) {
        size_t parent = zba_node_parent(node);
        zba_node_flip_split(zbah, parent);
        if (zba_node_is_split(zbah, parent)) break;
        struct zone_bits_chain *zbc = zba_chain_for_node(zbah, zba_node_buddy(node), order);
        zba_remove_block(zbc);
        order++;
        node = parent;
    }
    zba_push_block(zba_chain_for_node(zbah, node, order), order, with_extra);
}
static size_t zba_chunk_header_size(uint32_t n) {
    return sizeof(struct zone_bits_allocator_header) + (n == 0 ? sizeof(struct zone_bits_allocator_meta) : 0);
}
static void zba_init_chunk(uint32_t n, bool with_extra) {
    size_t hdr_size = zba_chunk_header_size(n), size = ZBA_CHUNK_SIZE;
    uintptr_t page = (uintptr_t)zba_base_header() + n * ZBA_CHUNK_SIZE;
    struct zone_bits_allocator_header *zbah = zba_header(page);
    for (uint32_t o = ZBA_MAX_ORDER + 1; o-- > 0;) {
        if (size < hdr_size + (ZBA_GRANULE << o)) continue;
        size -= ZBA_GRANULE << o;
        size_t node = zba_node(page + size, o);
        zba_node_flip_split(zbah, zba_node_parent(node));
        zba_push_block(zba_chain_for_node(zbah, node, o), o, with_extra);
    }
}
static void zba_grow(bool with_extra) {
    struct zone_bits_allocator_meta *meta = zba_meta();
    assert(meta->zbam_left < meta->zbam_right);
    uint32_t chunk = with_extra ? meta->zbam_right - 1 : meta->zbam_left;
    memset(arena + chunk * ZBA_CHUNK_SIZE, 0, ZBA_CHUNK_SIZE);
    if (with_extra) meta->zbam_right--; else meta->zbam_left++;
    zba_init_chunk(chunk, with_extra);
}
static uintptr_t zba_alloc(uint32_t order, bool with_extra) {
    uint32_t cur = order;
    uintptr_t addr;
    while ((addr = zba_try_pop_block(cur, with_extra)) == 0) {
        if (cur++ >= ZBA_MAX_ORDER) { zba_grow(with_extra); cur = order; }
    }
    struct zone_bits_allocator_header *zbah = zba_header(addr);
    size_t node = zba_node(addr, cur);
    zba_node_flip_split(zbah, zba_node_parent(node));
    while (cur > order) {
        cur--;
        zba_node_flip_split(zbah, node);
        node = zba_node_left_child(node);
        zba_push_block(zba_chain_for_node(zbah, node + 1, cur), cur, with_extra);
    }
    return addr;
}
int ref_buddy_init(uint32_t chunks) {
    free(arena); arena = NULL;
    arena_bytes = (size_t)chunks * ZBA_CHUNK_SIZE;
    if (!chunks || posix_memalign((void **)&arena, ZBA_CHUNK_SIZE, arena_bytes)) return -1;
    memset(arena, 0, arena_bytes);
    zba_meta()->zbam_left = 1; zba_meta()->zbam_right = chunks;
    zba_init_chunk(0, false);
    return 0;
}
uint64_t ref_buddy_alloc(uint32_t order, bool extra) {
    if (order > ZBA_MAX_ORDER) return 0;
    bool available = zba_meta()->zbam_left < zba_meta()->zbam_right;
    for (uint32_t o = order; o <= ZBA_MAX_ORDER; o++) available |= zba_head(o, extra)->zbh_next != 0;
    if (!available) return 0;
    return (uint64_t)(zba_alloc(order, extra) - (uintptr_t)arena);
}
void ref_buddy_free(uint64_t offset, uint32_t order, bool extra) { zba_free((uintptr_t)arena + offset, order, extra); }
void ref_buddy_snapshot(void *out) { memcpy(out, arena, arena_bytes); }
void ref_buddy_destroy(void) { free(arena); arena = NULL; }
uint64_t ref_scan64(uint64_t *bits, uint32_t words, uint64_t eidx) {
    size_t i = eidx / 64;
    uint64_t map;
    if (eidx % 64) {
        map = bits[i] & (-(1ull << (eidx % 64)));
        if (map) { eidx = __builtin_ctzll(map); bits[i] ^= 1ull << eidx; return i * 64 + eidx; }
        i++;
    }
    for (uint32_t j = 0; j < words; i++, j++) {
        if (i >= words) i = 0;
        if ((map = bits[i])) { bits[i] &= map - 1; return i * 64 + __builtin_ctzll(map); }
    }
    return UINT64_MAX;
}
void ref_merge64(uint64_t *bits, uint32_t start, uint32_t end) {
    while (start < end) {
        size_t s_i = start / 64, s_e = end / 64;
        if (s_i == s_e) { bits[s_i] |= ((1ull << (end % 64)) - 1) & (-(1ull << (start % 64))); break; }
        bits[s_i] |= -(1ull << (start % 64));
        start += 64 - start % 64;
    }
}
bool ref_mark_free64(uint64_t *bits, uint64_t eidx) {
    uint64_t bit = 1ull << (eidx % 64);
    if (bits[eidx / 64] & bit) return false;
    bits[eidx / 64] ^= bit;
    return true;
}

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
// osfmk/kern/zalloc.c. See docs/xnualloc/PORT_STATUS.md and APPLE_LICENSE.
// These translations retain APSL 2.0; they are NOT relicensed as GPL.


// Original tests for the translation, made available under APSL 2.0.
// See kernel/modules/xnualloc/APPLE_LICENSE. Modified 2026-09-11.
// Run from the repository root:
// v -gc none -path "@vlib|@vmodules|$(pwd)/kernel/modules" test tests/xnualloc
module main

import xnualloc

#include <stdlib.h>
fn C.posix_memalign(&voidptr, usize, usize) int
fn C.free(voidptr)

fn arena_alloc(bytes u64, alignment u64) voidptr {
	mut ptr := voidptr(0)
	assert C.posix_memalign(&ptr, usize(alignment), usize(bytes)) == 0
	return ptr
}

fn test_metadata_layout_and_masks() {
	assert sizeof(xnualloc.PageMetadata) == 16
	meta := xnualloc.PageMetadata{bits: u16((7 << 12) | (1 << 11) | 25)}
	assert meta.chunk_len() == 7
	assert meta.is_inline()
}

fn test_ref_bitmap_boundaries_and_wrap() {
	counts := [u32(0), 1, 31, 32, 33, 63, 64, 65, 127, 128, 129,
		255, 256, 511, 512, 8191, 8192]
	for count in counts {
		mut bits := [128]u64{}
		mut seen := [8192]bool{}
		xnualloc.zone_bits_init_ref(unsafe { &bits[0] }, 128, count)
		mut cursor := u64(8192) // exact end must wrap without reading past the map
		for _ in 0 .. int(count) {
			index := xnualloc.zba_scan_bitmap_ref(unsafe { &bits[0] }, 128, cursor)
			assert index < count && !seen[int(index)]
			seen[int(index)] = true
			cursor = index + 1
		}
		assert xnualloc.zba_scan_bitmap_ref(unsafe { &bits[0] }, 128, cursor) == xnualloc.no_element
		for i in 0 .. int(count) {
			assert seen[i]
		}
	}
}

fn test_ref_rotation_and_double_free() {
	mut bits := [4]u64{}
	for i in [u64(0), 3, 64, 129] {
		assert xnualloc.zone_bits_mark_free_ref(unsafe { &bits[0] }, 4, i)
		assert !xnualloc.zone_bits_mark_free_ref(unsafe { &bits[0] }, 4, i)
	}
	starts := [u64(2), 4, 65, 130]
	expected := [u64(3), 64, 129, 0]
	for i in 0 .. starts.len {
		assert xnualloc.zba_scan_bitmap_ref(unsafe { &bits[0] }, 4, starts[i]) == expected[i]
	}
	assert xnualloc.zba_scan_bitmap_ref(unsafe { &bits[0] }, 4, 0) == xnualloc.no_element
}

fn test_merge_ranges() {
	for first in [u32(0), 1, 31, 32, 63, 64, 65, 127, 128, 255, 256] {
		for end in [u32(0), 1, 31, 32, 63, 64, 65, 127, 128, 255, 256] {
			if first > end {
				continue
			}
			mut bits := [4]u64{}
			mut meta := [8]xnualloc.PageMetadata{}
			xnualloc.zone_bits_merge_ref(unsafe { &bits[0] }, 4, first, end)
			xnualloc.zone_bits_merge_inline(unsafe { &meta[0] }, 8, first, end)
			for i := u32(0); i < 256; i++ {
				expected := i >= first && i < end
				assert xnualloc.zone_bits_is_free_ref(unsafe { &bits[0] }, 4, i) == expected
				assert (meta[int(i / 32)].bitmap & (u32(1) << (i % 32)) != 0) == expected
			}
		}
	}
}

fn test_inline_bitmap_and_metadata_stride() {
	for count := u32(0); count <= 256; count++ {
		mut meta := [8]xnualloc.PageMetadata{}
		for mut m in meta {
			m.page_next = 0x5aa5
		}
		xnualloc.zone_meta_bits_init_inline(unsafe { &meta[0] }, count, 8)
		mut cursor := u64(256)
		for _ in 0 .. int(count) {
			index := xnualloc.zba_scan_bitmap_inline(unsafe { &meta[0] }, 8, cursor)
			assert index < count
			cursor = index + 1
		}
		assert xnualloc.zba_scan_bitmap_inline(unsafe { &meta[0] }, 8, cursor) == xnualloc.no_element
		for m in meta {
			assert m.page_next == 0x5aa5
		}
	}
}

fn test_buddy_exhaustion_reuse_both_geometries() {
	for shift in [u32(12), 14] {
		page := u64(1) << shift
		ptr := arena_alloc(4 * page, page)
		mut b := xnualloc.buddy_init(ptr, 4 * page, shift) or { panic('buddy_init') }
		mut refs := []u32{}
		for {
			reference := b.zone_meta_bits_alloc_init(129, 256, false)
			if reference == 0 {
				break
			}
			assert reference >> xnualloc.zba_order_shift == 2
			addr := u64(b.zba_bits_ref_ptr(reference))
			assert addr % 32 == 0 && addr >= u64(ptr) && addr + 32 <= u64(ptr) + 4 * page
			for old in refs {
				assert reference != old
			}
			refs << reference
		}
		assert refs.len > 100
		first_count := refs.len
		for i := refs.len - 1; i >= 0; i-- {
			b.zone_bits_free(refs[i])
		}
		refs.clear()
		for {
			reference := b.zone_meta_bits_alloc_init(129, 256, false)
			if reference == 0 { break }
			refs << reference
		}
		assert refs.len == first_count
		for reference in refs {
			b.zone_bits_free(reference)
		}
		unsafe { C.free(ptr) }
	}
}

struct LiveBlock {
	address u64
	order u32
	stamp u64
}

fn rng_step(state &u64) u64 {
	unsafe {
		mut x := *state
		x ^= x << 13
		x ^= x >> 7
		x ^= x << 17
		*state = x
		return x
	}
}

fn test_buddy_mixed_orders_and_live_payloads() {
	ptr := arena_alloc(65536, 4096)
	defer { unsafe { C.free(ptr) } }
	mut b := xnualloc.buddy_init(ptr, 65536, 12) or { panic('buddy_init') }
	mut live := []LiveBlock{}
	mut state := u64(0x584e555f504f5254)
	for step in 0 .. 20000 {
		r := rng_step(&state)
		if live.len == 0 || (live.len < 256 && r & 3 != 0) {
			order := u32((r >> 8) % 9)
			addr := b.zba_alloc(order, false)
			if addr == 0 { continue }
			size := u64(8) << order
			for block in live {
				assert addr + size <= block.address || block.address + (u64(8) << block.order) <= addr
			}
			stamp := u64(step + 1)
			unsafe {
				mut data := &u64(addr)
				for i := u64(0); i < size / 8; i++ { data[i] = stamp }
			}
			live << LiveBlock{address: addr, order: order, stamp: stamp}
		} else {
			i := int((r >> 16) % u64(live.len))
			block := live[i]
			unsafe {
				data := &u64(block.address)
				for j := u64(0); j < (u64(1) << block.order); j++ { assert data[j] == block.stamp }
			}
			b.zba_free(block.address, block.order, false)
			live[i] = live[live.len - 1]
			live.delete_last()
		}
	}
	for block in live {
		b.zba_free(block.address, block.order, false)
	}
	// All chunks coalesce back to their original free-block decomposition.
	mut large := []u64{}
	for { a := b.zba_alloc(8, false); if a == 0 { break }; large << a }
	assert large.len == 16
	for a in large { b.zba_free(a, 8, false) }
}

fn test_packed_ref_metadata_and_extra_shadow() {
	ptr := arena_alloc(16384, 4096)
	extra := arena_alloc(16384 * 16, 4096)
	defer { unsafe { C.free(ptr); C.free(extra) } }
	mut b := xnualloc.buddy_init(ptr, 16384, 12) or { panic('buddy_init') }
	assert b.zone_meta_bits_alloc_init(64, 64, true) == 0
	assert b.configure_extra(extra, 16384 * 16, 1)
	reference := b.zone_meta_bits_alloc_init(65, 128, true)
	assert reference != 0 && reference & xnualloc.zba_has_extra_bit != 0
	mut meta := xnualloc.PageMetadata{bitmap: reference}
	mut last := u16(0)
	assert xnualloc.zone_meta_find_and_clear_bit(&meta, &b, 1, &last) == 1
	assert !xnualloc.zone_meta_is_free(&meta, &b, 1, 1)
	assert xnualloc.zone_meta_mark_free(&meta, &b, 1, 1)
	assert !xnualloc.zone_meta_mark_free(&meta, &b, 1, 1)
	xnualloc.zone_meta_bits_merge(&meta, &b, 1, 65, 128)
	assert xnualloc.zone_meta_is_free(&meta, &b, 1, 127)
	tag := b.zba_extra_ref_ptr(reference, 64)
	assert u64(tag) >= u64(extra) && u64(tag) + 2 <= u64(extra) + 16384 * 16
	unsafe { assert *(&u16(tag)) == 0; *(&u16(tag)) = 0x1234 }
	b.zone_bits_free(reference)
}

fn test_depot_full_empty_partition_and_minima() {
	mut mags := [10]xnualloc.Magazine{}
	mut a := xnualloc.Depot{}
	mut b := xnualloc.Depot{}
	a.zone_depot_init()
	b.zone_depot_init()
	for i in 0 .. 4 {
		mags[i].seq = u64(i + 1)
		a.zone_depot_insert_tail_full(mut mags[i])
	}
	a.zone_depot_insert_head_empty(mut mags[4])
	a.zone_depot_insert_head_empty(mut mags[5])
	mut minimum := xnualloc.RecircMinimum{full: 4, empty: 2}
	assert b.zone_depot_move_full(mut a, 2, &minimum, false) == 2
	assert minimum.full == 2 && a.full == 2 && b.full == 2
	b.zone_depot_move_empty(mut a, 1, &minimum)
	assert minimum.empty == 1 && b.empty == 1
	assert u64(b.zone_depot_pop_head_full(unsafe { nil })) == u64(&mags[0])
	assert u64(b.zone_depot_pop_head_full(unsafe { nil })) == u64(&mags[1])
	assert b.full == 0 && u64(unsafe { *b.tail }) == u64(&mags[5])
	assert u64(b.zone_depot_pop_head_empty(unsafe { nil })) == u64(&mags[5])
	b.zone_depot_insert_tail_full(mut mags[6])
	b.zone_depot_move_full(mut a, 2, &minimum, true)
	assert u64(b.zone_depot_pop_head_full(unsafe { nil })) == u64(&mags[2])
	assert u64(b.zone_depot_pop_head_full(unsafe { nil })) == u64(&mags[3])
	assert u64(b.zone_depot_pop_head_full(unsafe { nil })) == u64(&mags[6])
	assert u64(a.zone_depot_pop_head_empty(unsafe { nil })) == u64(&mags[4])
	assert a.head == unsafe { nil } && b.head == unsafe { nil }
}

fn denied(_ u64) bool { return false }
fn permitted(seq u64) bool { return seq == 7 }

fn test_smr_poll_is_not_a_success_stub() {
	mut d := xnualloc.Depot{}
	mut mag := xnualloc.Magazine{seq: 7}
	d.zone_depot_init()
	assert !d.zone_depot_poll(false, denied)
	d.zone_depot_insert_tail_full(mut mag)
	assert d.zone_depot_poll(false, denied)
	assert !d.zone_depot_poll(true, denied)
	assert d.zone_depot_poll(true, permitted)
}

fn test_magazine_swap_replace_and_non_smr_fast_paths() {
	mut a := xnualloc.Magazine{}
	mut f := xnualloc.Magazine{}
	mut full := xnualloc.Magazine{}
	mut c := xnualloc.Cache{alloc_mag: &a, free_mag: &f}
	for i := u64(1); i <= 33; i++ { assert c.try_free(i) }
	assert c.alloc_cur == 32 && c.free_cur == 1
	for i := u64(32); i > 0; i-- { assert c.try_alloc() == i }
	assert c.try_alloc() == 33
	assert c.try_alloc() == 0
	for i in 0 .. 32 { full.elems[i] = u64(i + 100) }
	old := c.zone_magazine_replace(mut full, false)
	assert u64(old) != u64(&full) && c.try_alloc() == 131
}

fn test_free_swap_with_partial_alloc_magazine() {
	mut a := xnualloc.Magazine{}
	mut f := xnualloc.Magazine{}
	a.elems[0] = 1000
	for i in 0 .. 32 { f.elems[i] = u64(i + 1) }
	mut c := xnualloc.Cache{alloc_mag: &a, free_mag: &f, alloc_cur: 1, free_cur: 32}
	assert c.try_free(1001)
	assert c.alloc_cur == 32 && c.free_cur == 2
	assert c.free_mag.elems[0] == 1000 && c.free_mag.elems[1] == 1001
	assert c.try_alloc() == 32
}

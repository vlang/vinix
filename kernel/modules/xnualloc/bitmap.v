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


@[manualfree]
module xnualloc

pub const no_element = u64(-1)
pub const zba_ptr_mask = u32(0x0fffffff)
pub const zba_order_shift = u32(29)
pub const zba_has_extra_bit = u32(0x10000000)

// C's packed bitfield/union representation, expressed explicitly in V.
// Supported targets are the little-endian 64-bit architectures used by Vinix.
// bits: zone index [0:9], guarded [10], inline [11], chunk length [12:15].
// alloc_size doubles as secondary-page index/subchunk length.
@[packed]
pub struct PageMetadata {
pub mut:
	bits       u16
	alloc_size u16
	bitmap     u32
	page_next  u32
	page_prev  u32
}

@[inline]
pub fn (meta &PageMetadata) is_inline() bool {
	return meta.bits & u16(1 << 11) != 0
}

@[inline]
pub fn (meta &PageMetadata) chunk_len() u32 {
	return u32(meta.bits >> 12)
}

// Equivalent to __builtin_ctzll on a nonzero operand; no FP or runtime call.
@[inline]
fn trailing_zeros(input u64) u64 {
	mut value := input
	assert value != 0
	mut index := u64(0)
	if value & u64(0xffffffff) == 0 {
		index += 32
		value >>= 32
	}
	if value & u64(0xffff) == 0 {
		index += 16
		value >>= 16
	}
	if value & u64(0xff) == 0 {
		index += 8
		value >>= 8
	}
	if value & u64(0xf) == 0 {
		index += 4
		value >>= 4
	}
	if value & u64(3) == 0 {
		index += 2
		value >>= 2
	}
	if value & u64(1) == 0 {
		index++
	}
	return index
}

@[inline]
fn mask_ge64(index u64) u64 {
	return u64(-1) << (index % 64)
}

@[inline]
fn mask_lt64(index u64) u64 {
	return (u64(1) << (index % 64)) - 1
}

// Direct translation of zba_scan_bitmap_ref, with explicit storage/word-count
// parameters instead of XNU's global zone_info lookup. 1 = free, 0 = occupied.
// eidx may equal words * 64 (the wrap boundary), but may not exceed it.
// Unlike upstream's accounting panic, exhaustion returns no_element; the
// Vinix bridge turns this into a kernel panic when its page claims free slots.
// The caller holds the owning zone lock. This routine is NOT atomic.
pub fn zba_scan_bitmap_ref(bits &u64, words u32, eidx u64) u64 {
	assert bits != unsafe { nil } && words > 0 && words <= 128
	assert words & (words - 1) == 0 && eidx <= u64(words) * 64
	mut i := eidx / 64
	unsafe {
		if eidx % 64 != 0 {
			map := bits[i] & mask_ge64(eidx)
			if map != 0 {
				bit := trailing_zeros(map)
				bits[i] ^= u64(1) << bit
				return i * 64 + bit
			}
			i++
		}
		for j := u32(0); j < words; j++ {
			if i >= words {
				i = 0
			}
			map := bits[i]
			if map != 0 {
				bits[i] &= map - 1
				return i * 64 + trailing_zeros(map)
			}
			i++
		}
	}
	return no_element
}

// Direct translation of zba_scan_bitmap_inline. chunk_len is supplied by the
// caller: ordinary chunks use meta.chunk_len(); Z_PCPU uses CPU count instead.
pub fn zba_scan_bitmap_inline(meta &PageMetadata, chunk_len u32, eidx u64) u64 {
	assert meta != unsafe { nil } && chunk_len > 0
	assert eidx <= u64(chunk_len) * 32
	mut i := eidx / 32
	unsafe {
		if eidx % 32 != 0 {
			map := meta[i].bitmap & (u32(-1) << (eidx % 32))
			if map != 0 {
				bit := trailing_zeros(u64(map))
				meta[i].bitmap ^= u32(1) << bit
				return i * 32 + bit
			}
			i++
		}
		for j := u32(0); j < chunk_len; j++ {
			if i >= chunk_len {
				i = 0
			}
			map := meta[i].bitmap
			if map != 0 {
				meta[i].bitmap &= map - 1
				return i * 32 + trailing_zeros(u64(map))
			}
			i++
		}
	}
	return no_element
}

// Upstream requires zero-initialized metadata before this call.
pub fn zone_meta_bits_init_inline(meta &PageMetadata, count u32, chunks u32) {
	assert meta != unsafe { nil } && u64(count) <= u64(chunks) * 32
	unsafe {
		for i := u32(0); i < count / 32; i++ {
			meta[i].bitmap = u32(-1)
		}
		if count % 32 != 0 {
			meta[count / 32].bitmap = (u32(1) << (count % 32)) - 1
		}
	}
}

// The initialization loop in zone_meta_bits_alloc_init, also exposed for
// caller-owned bitmaps such as Vinix's one-page slab geometry.
pub fn zone_bits_init_ref(bits &u64, words u32, count u32) {
	assert bits != unsafe { nil } && words > 0 && words <= 128
	assert u64(count) <= u64(words) * 64
	mut i := u32(0)
	unsafe {
		for i < count / 64 {
			bits[i] = u64(-1)
			i++
		}
		if count % 64 != 0 {
			bits[i] = mask_lt64(count)
			i++
		}
		for i < words {
			bits[i] = 0
			i++
		}
	}
}

pub fn zone_bits_merge_ref(bits &u64, words u32, first u32, end u32) {
	assert bits != unsafe { nil } && first <= end && u64(end) <= u64(words) * 64
	mut start := first
	unsafe {
		for start < end {
			i := start / 64
			if i == end / 64 {
				bits[i] |= mask_lt64(end) & mask_ge64(start)
				break
			}
			bits[i] |= mask_ge64(start)
			start += 64 - start % 64
		}
	}
}

pub fn zone_bits_merge_inline(meta &PageMetadata, chunks u32, first u32, end u32) {
	assert meta != unsafe { nil } && first <= end && u64(end) <= u64(chunks) * 32
	mut start := first
	unsafe {
		for start < end {
			i := start / 32
			if i == end / 32 {
				meta[i].bitmap |= ((u32(1) << (end % 32)) - 1) &
					(u32(-1) << (start % 32))
				break
			}
			meta[i].bitmap |= u32(-1) << (start % 32)
			start += 32 - start % 32
		}
	}
}

pub fn zone_bits_is_free_ref(bits &u64, words u32, index u64) bool {
	assert bits != unsafe { nil } && index < u64(words) * 64
	return unsafe { bits[index / 64] & (u64(1) << (index % 64)) != 0 }
}

pub fn zone_bits_mark_free_ref(bits &u64, words u32, index u64) bool {
	assert bits != unsafe { nil } && index < u64(words) * 64
	bit := u64(1) << (index % 64)
	unsafe {
		if bits[index / 64] & bit != 0 {
			return false
		}
		bits[index / 64] ^= bit
	}
	return true
}

pub fn zone_meta_is_free(meta &PageMetadata, arena &Buddy, chunks u32, index u64) bool {
	if meta.is_inline() {
		assert index < u64(chunks) * 32
		return unsafe { meta[index / 32].bitmap & (u32(1) << (index % 32)) != 0 }
	}
	return zone_bits_is_free_ref(arena.zba_bits_ref_ptr(meta.bitmap),
		u32(1) << (meta.bitmap >> zba_order_shift), index)
}

pub fn zone_meta_mark_free(meta &PageMetadata, arena &Buddy, chunks u32, index u64) bool {
	if meta.is_inline() {
		assert index < u64(chunks) * 32
		bit := u32(1) << (index % 32)
		unsafe {
			if meta[index / 32].bitmap & bit != 0 {
				return false
			}
			meta[index / 32].bitmap ^= bit
		}
		return true
	}
	return zone_bits_mark_free_ref(arena.zba_bits_ref_ptr(meta.bitmap),
		u32(1) << (meta.bitmap >> zba_order_shift), index)
}

pub fn zone_meta_bits_merge(meta &PageMetadata, arena &Buddy, chunks u32, start u32, end u32) {
	if meta.is_inline() {
		zone_bits_merge_inline(meta, chunks, start, end)
	} else {
		zone_bits_merge_ref(arena.zba_bits_ref_ptr(meta.bitmap),
			u32(1) << (meta.bitmap >> zba_order_shift), start, end)
	}
}

// Caller supplies its per-CPU cursor. A Vinix shared-lock adapter may instead
// keep one cursor per slab class, which is a documented behavioral difference.
pub fn zone_meta_find_and_clear_bit(meta &PageMetadata, arena &Buddy, chunks u32,
	last &u16) u64 {
	start := u64(unsafe { *last }) + 1
	mut index := no_element
	if meta.is_inline() {
		index = zba_scan_bitmap_inline(meta, chunks, start)
	} else {
		index = zba_scan_bitmap_ref(arena.zba_bits_ref_ptr(meta.bitmap),
			u32(1) << (meta.bitmap >> zba_order_shift), start)
	}
	if index != no_element {
		unsafe { *last = u16(index) }
	}
	return index
}

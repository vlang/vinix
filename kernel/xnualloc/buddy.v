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

// Translation of XNU's zba_* buddy allocator, including both free-list banks,
// split-bit coalescing, relative indices and packed bitmap references.
//
// BACKING ADAPTATION: the caller supplies an already mapped, page-aligned arena.
// zba_grow initializes another chunk of that arena; it cannot populate VM or
// wait for VM_PAGE_WAIT. Exhaustion returns 0 rather than sleeping/panicking.
// This object is not internally synchronized. Hold one external arena lock.
// Do not reinitialize, move the backing arena, or use stale/double-freed refs.
pub struct Buddy {
mut:
	base        u64
	bytes       u64
	chunk_size  u64
	max_order   u32
	head_count  u32
	extra_base  u64
	extra_bytes u64
	extra_shift u32
}

@[packed]
struct BitsChain {
mut:
	next u32
	prev u32
}

// The first two u32 words are zbam_left / zbam_right. The list heads follow.
// Computing their offsets permits the exact 4 KiB and 16 KiB XNU geometries
// without making a fixed-size V array change the upstream header size.
fn (b &Buddy) header_bytes() u64 {
	return b.chunk_size / 64
}

fn (b &Buddy) meta_words() &u32 {
	return unsafe { &u32(b.base + b.header_bytes()) }
}

fn (b &Buddy) left() u32 {
	return unsafe { b.meta_words()[0] }
}

fn (b &Buddy) right() u32 {
	return unsafe { b.meta_words()[1] }
}

fn zero_words(base u64, bytes u64) {
	assert bytes % 8 == 0
	unsafe {
		mut p := &u64(base)
		for i := u64(0); i < bytes / 8; i++ {
			p[i] = 0
		}
	}
}

// page_shift must be 12 or 14. The arena must outlive every bitmap reference.
// Only the first chunk is initialized now; others are initialized on growth.
pub fn buddy_init(arena voidptr, bytes u64, page_shift u32) ?Buddy {
	base := u64(arena)
	if (page_shift != 12 && page_shift != 14) || base == 0 {
		return none
	}
	chunk := u64(1) << page_shift
	if base % chunk != 0 || bytes < chunk || bytes % chunk != 0
		|| bytes > (u64(zba_ptr_mask) + 1) * 8 || base > u64(-1) - bytes {
		return none
	}
	mut b := Buddy{
		base: base
		bytes: bytes
		chunk_size: chunk
		max_order: page_shift - 4
		head_count: page_shift - 3
	}
	zero_words(base, chunk)
	unsafe {
		mut meta := b.meta_words()
		meta[0] = 1
		meta[1] = u32(bytes / chunk)
	}
	b.zba_init_chunk(0, false)
	return b
}

// Optional prebacked VM-tracking shadow. Requests with_extra fail unless this
// is configured; they never pretend that the shadow exists. No VM mapping or
// Apple tagging machinery is implemented by this library.
pub fn (mut b Buddy) configure_extra(arena voidptr, bytes u64, shift u32) bool {
	if b.base == 0 || b.extra_base != 0 || u64(arena) == 0 || shift > 8 {
		return false
	}
	scale := u64(8) << shift
	if b.bytes > u64(-1) / scale || bytes < b.bytes * scale
		|| u64(arena) % 8 != 0 || u64(arena) > u64(-1) - bytes {
		return false
	}
	// Separate storage is required; otherwise population would overwrite the
	// allocator itself. The caller must likewise avoid overlap with other users.
	if u64(arena) < b.base + b.bytes && b.base < u64(arena) + bytes {
		return false
	}
	b.extra_base = u64(arena)
	b.extra_bytes = bytes
	b.extra_shift = shift
	return true
}

fn (b &Buddy) zba_head(order u32, with_extra bool) &BitsChain {
	assert order <= b.max_order
	bank := if with_extra { b.head_count } else { u32(0) }
	return unsafe { &BitsChain(b.base + b.header_bytes() + 8 + u64(bank + order) * 8) }
}

fn (b &Buddy) zba_chain_for_index(index u32) &BitsChain {
	assert index != 0 && u64(index) * 8 + 8 <= b.bytes
	return unsafe { &BitsChain(b.base + u64(index) * 8) }
}

fn (b &Buddy) zba_chain_to_index(chain &BitsChain) u32 {
	addr := u64(chain)
	assert addr >= b.base && addr < b.base + b.bytes && (addr - b.base) % 8 == 0
	return u32((addr - b.base) / 8)
}

fn (mut b Buddy) zba_push_block(chain &BitsChain, order u32, with_extra bool) {
	unsafe {
		mut hd := b.zba_head(order, with_extra)
		hd_index := b.zba_chain_to_index(hd)
		index := b.zba_chain_to_index(chain)
		if hd.next != 0 {
			mut next := b.zba_chain_for_index(hd.next)
			if next.prev != hd_index {
				panic('xnualloc: zone bits allocator head is corrupt')
			}
			next.prev = index
		}
		mut node := chain
		node.next = hd.next
		node.prev = hd_index
		hd.next = index
	}
}

fn (mut b Buddy) zba_remove_block(chain &BitsChain) {
	unsafe {
		mut prev := b.zba_chain_for_index(chain.prev)
		index := b.zba_chain_to_index(chain)
		if prev.next != index {
			panic('xnualloc: zone bits allocator previous link is corrupt')
		}
		prev.next = chain.next
		if chain.next != 0 {
			mut next := b.zba_chain_for_index(chain.next)
			if next.prev != index {
				panic('xnualloc: zone bits allocator next link is corrupt')
			}
			next.prev = chain.prev
		}
	}
}

fn (mut b Buddy) zba_try_pop_block(order u32, with_extra bool) u64 {
	hd := b.zba_head(order, with_extra)
	if hd.next == 0 {
		return 0
	}
	chain := b.zba_chain_for_index(hd.next)
	b.zba_remove_block(chain)
	return u64(chain)
}

@[inline]
fn zba_node_parent(node u64) u64 {
	assert node != 0
	return (node - 1) / 2
}

@[inline]
fn zba_node_left_child(node u64) u64 {
	return node * 2 + 1
}

@[inline]
fn zba_node_buddy(node u64) u64 {
	assert node != 0
	return ((node - 1) ^ 1) + 1
}

fn (b &Buddy) zba_node(addr u64, order u32) u64 {
	offs := (addr % b.chunk_size) / 8
	return (offs >> order) + (u64(1) << (b.max_order - order + 1)) - 1
}

fn (b &Buddy) zba_chain_for_node(header u64, node u64, order u32) &BitsChain {
	offs := (node - (u64(1) << (b.max_order - order + 1)) + 1) << order
	return unsafe { &BitsChain(header + offs * 8) }
}

fn zba_node_flip_split(header u64, node u64) {
	unsafe {
		mut bits := &u64(header)
		bits[node / 64] ^= u64(1) << (node % 64)
	}
}

fn zba_node_is_split(header u64, node u64) bool {
	return unsafe { (&u64(header))[node / 64] & (u64(1) << (node % 64)) != 0 }
}

fn (b &Buddy) zba_chunk_header_size(index u32) u64 {
	return b.header_bytes() + if index == 0 { u64(8) + u64(b.head_count) * 16 } else { u64(0) }
}

fn (mut b Buddy) zba_init_chunk(index u32, with_extra bool) {
	hdr_size := b.zba_chunk_header_size(index)
	page := b.base + u64(index) * b.chunk_size
	mut size := b.chunk_size
	for o := int(b.max_order); o >= 0; o-- {
		block := u64(8) << u32(o)
		if size < hdr_size + block {
			continue
		}
		size -= block
		node := b.zba_node(page + size, u32(o))
		zba_node_flip_split(page, zba_node_parent(node))
		b.zba_push_block(b.zba_chain_for_node(page, node, u32(o)), u32(o), with_extra)
	}
}

// This is the sole backing-policy adaptation to the C zba_grow path: mapped
// storage is already owned. We return failure at the arena limit, never wait.
fn (mut b Buddy) zba_grow(with_extra bool) bool {
	if b.left() >= b.right() || (with_extra && b.extra_base == 0) {
		return false
	}
	index := if with_extra { b.right() - 1 } else { b.left() }
	zero_words(b.base + u64(index) * b.chunk_size, b.chunk_size)
	if with_extra {
		xsize := b.chunk_size * 8 << b.extra_shift
		zero_words(b.extra_base + u64(index) * xsize, xsize)
	}
	unsafe {
		mut meta := b.meta_words()
		if with_extra {
			meta[1]--
		} else {
			meta[0]++
		}
	}
	b.zba_init_chunk(index, with_extra)
	return true
}

pub fn (mut b Buddy) zba_alloc(order u32, with_extra bool) u64 {
	if b.base == 0 || order > b.max_order || (with_extra && b.extra_base == 0) {
		return 0
	}
	mut current := order
	mut addr := b.zba_try_pop_block(current, with_extra)
	for addr == 0 {
		if current >= b.max_order {
			if !b.zba_grow(with_extra) {
				return 0
			}
			current = order
		} else {
			current++
		}
		addr = b.zba_try_pop_block(current, with_extra)
	}
	header := addr & ~(b.chunk_size - 1)
	mut node := b.zba_node(addr, current)
	zba_node_flip_split(header, zba_node_parent(node))
	for current > order {
		current--
		zba_node_flip_split(header, node)
		node = zba_node_left_child(node)
		b.zba_push_block(b.zba_chain_for_node(header, node + 1, current), current, with_extra)
	}
	return addr
}

pub fn (mut b Buddy) zba_free(addr u64, initial_order u32, with_extra bool) {
	assert b.base != 0 && initial_order <= b.max_order
	assert addr >= b.base && addr < b.base + b.bytes
	assert addr % (u64(8) << initial_order) == 0
	index := u32((addr - b.base) / b.chunk_size)
	assert (with_extra && b.extra_base != 0 && index >= b.right())
		|| (!with_extra && index < b.left())
	assert addr % b.chunk_size >= b.zba_chunk_header_size(index)
	assert addr % b.chunk_size + (u64(8) << initial_order) <= b.chunk_size
	header := addr & ~(b.chunk_size - 1)
	mut order := initial_order
	mut node := b.zba_node(addr, order)
	for node != 0 {
		parent := zba_node_parent(node)
		zba_node_flip_split(header, parent)
		if zba_node_is_split(header, parent) {
			break
		}
		chain := b.zba_chain_for_node(header, zba_node_buddy(node), order)
		b.zba_remove_block(chain)
		order++
		node = parent
	}
	assert order <= b.max_order
	b.zba_push_block(b.zba_chain_for_node(header, node, order), order, with_extra)
}

pub fn (b &Buddy) zba_bits_ref_ptr(reference u32) &u64 {
	order := reference >> zba_order_shift
	index := reference & zba_ptr_mask
	assert b.base != 0 && index != 0 && order <= 7
	assert u64(index) * 8 + (u64(8) << order) <= b.bytes
	return unsafe { &u64(b.base + u64(index) * 8) }
}

pub fn (b &Buddy) zba_extra_ref_ptr(reference u32, index u64) voidptr {
	assert b.extra_base != 0 && reference & zba_has_extra_bit != 0
	assert index < (u64(64) << (reference >> zba_order_shift))
	offs := u64(reference & zba_ptr_mask) * 64
	assert ((offs + index + 1) << b.extra_shift) <= b.extra_bytes
	return voidptr(b.extra_base + ((offs + index) << b.extra_shift))
}

pub fn (mut b Buddy) zone_meta_bits_alloc_init(count u32, nbits u32, with_extra bool) u32 {
	if nbits == 0 || nbits > 8192 || count > nbits {
		return 0
	}
	mut scale := (nbits - 1) / 64
	mut order := u32(0)
	for scale != 0 {
		order++
		scale >>= 1
	}
	addr := b.zba_alloc(order, with_extra)
	if addr == 0 {
		return 0
	}
	zone_bits_init_ref(unsafe { &u64(addr) }, u32(1) << order, count)
	return u32((addr - b.base) / 8) | (order << zba_order_shift) |
		if with_extra { zba_has_extra_bit } else { u32(0) }
}

pub fn (mut b Buddy) zone_bits_free(reference u32) {
	addr := u64(b.zba_bits_ref_ptr(reference))
	b.zba_free(addr, reference >> zba_order_shift, reference & zba_has_extra_bit != 0)
}

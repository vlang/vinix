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

// Adapted translations of the ordinary, non-SMR zone paths in zalloc.c.
// Every entry below requires ONE external lock covering the Zone, its chunks,
// all CPU caches and both depot layers. This deliberately does not claim XNU's
// lock-free CPU fast path. No function allocates from a language/runtime heap.
// Storage providers own mapping, CPU pinning, allocation failure and page free.
// Addresses and identities are compared numerically (not V struct equality).

pub enum ChunkQueue {
	detached
	empty
	partial
	full
}

pub struct ZoneChunk {
pub mut:
	owner    u64
	base     u64
	bytes    u64
	offset   u64
	pages    u32
	capacity u32
	reserved u32 // includes cached objects, not only client-live objects
	words    u32
	bits     &u64 = unsafe { nil } // 1 = available to zone import
	live     &u64 = unsafe { nil } // port addition: 1 = handed to a client
	prev     &ZoneChunk = unsafe { nil }
	next     &ZoneChunk = unsafe { nil }
	queue    ChunkQueue
}

pub struct Zone {
pub mut:
	elem_size    u64
	empty        &ZoneChunk = unsafe { nil }
	partial      &ZoneChunk = unsafe { nil }
	full         &ZoneChunk = unsafe { nil }
	elems_avail  u64
	elems_free   u64
	live_count   u64
	wired        u64
	wired_empty  u64
	free_min     u64
	alloc_rr     u16
	recirc       Depot
	minimum      RecircMinimum
	// Non-SMR depot cap, in magazines. 0 means direct recirculation.
	depot_max    u32
	lifo         bool
	// Optional O(1) metadata lookup. Must return stable, owned metadata for
	// valid objects. Arbitrary/unmapped pointers are not a supported input.
	resolve      fn (u64) &ZoneChunk = unsafe { nil }
}

pub struct CpuCache {
pub mut:
	cache        Cache
	depot        Depot
	alloc_rr     u16
	ready        bool
	// Two active magazines plus four spare containers. All have stable
	// addresses for the lifetime of the Zone, even when owned by recirc.
	storage      [6]Magazine
}

pub fn (mut z Zone) zone_init(size u64, depot_max u32) bool {
	if z.elem_size != 0 || size == 0 || size > 32768 || depot_max > 4 {
		return false
	}
	z.elem_size = size
	z.depot_max = depot_max
	z.recirc.zone_depot_init()
	return true
}

pub fn (mut c CpuCache) cache_init() bool {
	if c.ready {
		return false
	}
	c.depot.zone_depot_init()
	unsafe {
		c.cache.alloc_mag = &c.storage[0]
		c.cache.free_mag = &c.storage[1]
	}
	for i := 2; i < 6; i++ {
		c.depot.zone_depot_insert_head_empty(mut c.storage[i])
	}
	c.ready = true
	return true
}

fn (mut z Zone) queue_head(q ChunkQueue) &ZoneChunk {
	return match q {
		.empty { z.empty }
		.partial { z.partial }
		.full { z.full }
		else { unsafe { nil } }
	}
}

fn (mut z Zone) queue_set_head(q ChunkQueue, p &ZoneChunk) {
	match q {
		.empty { unsafe { z.empty = p } }
		.partial { unsafe { z.partial = p } }
		.full { unsafe { z.full = p } }
		else { assert false }
	}
}

// zone_meta_queue_push/remqueue/requeue with explicit pointers rather than
// XNU's packed zone-page virtual-address indices.
fn (mut z Zone) zone_meta_remqueue(mut p ZoneChunk) {
	assert p.owner == u64(&z) && p.queue != .detached
	if p.prev == unsafe { nil } {
		assert u64(z.queue_head(p.queue)) == u64(&p)
		z.queue_set_head(p.queue, p.next)
	} else {
		assert u64(p.prev.next) == u64(&p)
		p.prev.next = p.next
	}
	if p.next != unsafe { nil } {
		assert u64(p.next.prev) == u64(&p)
		p.next.prev = p.prev
	}
	p.prev = unsafe { nil }
	p.next = unsafe { nil }
	p.queue = .detached
}

fn (mut z Zone) zone_meta_queue_push(mut p ZoneChunk, q ChunkQueue) {
	assert p.queue == .detached && q != .detached
	p.next = z.queue_head(q)
	p.prev = unsafe { nil }
	if p.next != unsafe { nil } {
		unsafe { p.next.prev = &p }
	}
	z.queue_set_head(q, &p)
	p.queue = q
}

fn (mut z Zone) zone_meta_requeue(mut p ZoneChunk, q ChunkQueue) {
	if p.queue == q {
		return
	}
	z.zone_meta_remqueue(mut p)
	z.zone_meta_queue_push(mut p, q)
}

// Fully backed chunk installation: the completed-population portion of zcram.
// Partial Mach VM population/secondary-page metadata are not synthesized.
// The bitmap word count must be a power of two, at most 128, as in zba.
pub fn (mut z Zone) zcram(mut p ZoneChunk) bool {
	if z.elem_size == 0 || p.owner != 0 || p.queue != .detached || p.base == 0
		|| p.bytes == 0 || p.base > u64(-1) - p.bytes || p.offset >= p.bytes
		|| p.pages == 0 || p.words == 0 || p.words > 128
		|| p.words & (p.words - 1) != 0 || p.bits == unsafe { nil }
		|| p.live == unsafe { nil } || u64(p.bits) == u64(p.live) {
		return false
	}
	capacity := (p.bytes - p.offset) / z.elem_size
	if capacity == 0 || capacity > u64(p.words) * 64
		|| z.elems_avail > u64(-1) - capacity || z.wired > u64(-1) - p.pages {
		return false
	}
	p.owner = u64(&z)
	p.capacity = u32(capacity)
	p.reserved = 0
	zone_bits_init_ref(p.bits, p.words, p.capacity)
	unsafe {
		for i := u32(0); i < p.words; i++ {
			p.live[i] = 0
		}
	}
	z.zone_meta_queue_push(mut p, .empty)
	z.elems_avail += capacity
	z.elems_free += capacity
	z.wired += p.pages
	z.wired_empty += p.pages
	return true
}

pub fn (mut z Zone) zone_element_resolve(addr u64) &ZoneChunk {
	if z.resolve != unsafe { nil } {
		p := z.resolve(addr)
		if p != unsafe { nil } && p.owner == u64(&z) && z.slot(p, addr) != no_element {
			return p
		}
		return unsafe { nil }
	}
	// Portable/test fallback. A Vinix resolver avoids this list traversal.
	heads := [z.full, z.partial, z.empty]!
	for head in heads {
		mut p := head
		for p != unsafe { nil } {
			if z.slot(p, addr) != no_element {
				return p
			}
			p = p.next
		}
	}
	return unsafe { nil }
}

fn (z &Zone) slot(p &ZoneChunk, addr u64) u64 {
	if p.owner != u64(z) || p.queue == .detached || addr < p.base + p.offset {
		return no_element
	}
	offs := addr - p.base - p.offset
	if offs % z.elem_size != 0 || offs / z.elem_size >= p.capacity {
		return no_element
	}
	return offs / z.elem_size
}

// Translation of zalloc_import's bitmap reservation and queue transitions.
// Reserve n elements; none is client-live until zone_mark_valid. n==0 is a
// port-defined no-op. No mutation occurs for an unavailable batch.
pub fn (mut z Zone) zalloc_import(out &u64, n u32, rr &u16) bool {
	if n == 0 {
		return true
	}
	if out == unsafe { nil } || rr == unsafe { nil } || u64(n) > z.elems_free {
		return false
	}
	mut done := u32(0)
	for done < n {
		mut p := z.partial
		if p == unsafe { nil } {
			p = z.empty
		}
		assert p != unsafe { nil }
		old := p.reserved
		if old == 0 {
			z.wired_empty -= p.pages
		}
		for done < n && p.reserved < p.capacity {
			// Normalize across chunks with different bitmap capacities.
			start := (u64(unsafe { *rr }) + 1) % (u64(p.words) * 64)
			index := zba_scan_bitmap_ref(p.bits, p.words, start)
			assert index < p.capacity
			unsafe { *rr = u16(index) }
			unsafe { out[done] = p.base + p.offset + index * z.elem_size }
			p.reserved++
			done++
		}
		if p.reserved == p.capacity {
			z.zone_meta_requeue(mut p, .full)
		} else if old == 0 {
			z.zone_meta_requeue(mut p, .partial)
		}
	}
	z.elems_free -= n
	if z.free_min > z.elems_free {
		z.free_min = z.elems_free
	}
	return true
}

// Extra client-live bitmap prevents accepting a second free into a cache.
// It does not detect stale pointers after the slot is reallocated.
pub fn (mut z Zone) zone_mark_valid(addr u64) bool {
	mut p := z.zone_element_resolve(addr)
	if p == unsafe { nil } {
		return false
	}
	i := z.slot(p, addr)
	bit := u64(1) << (i % 64)
	unsafe {
		if p.bits[i / 64] & bit != 0 || p.live[i / 64] & bit != 0 {
			return false
		}
		p.live[i / 64] |= bit
	}
	z.live_count++
	return true
}

pub fn (mut z Zone) zone_mark_invalid(addr u64) bool {
	mut p := z.zone_element_resolve(addr)
	if p == unsafe { nil } {
		return false
	}
	i := z.slot(p, addr)
	bit := u64(1) << (i % 64)
	unsafe {
		if p.bits[i / 64] & bit != 0 || p.live[i / 64] & bit == 0 {
			return false
		}
		p.live[i / 64] &= ~bit
	}
	assert z.live_count != 0
	z.live_count--
	return true
}

// Translation of zfree_drop. Caller has already invalidated the client
// object or is returning a never-exposed reserved object during cache drain.
pub fn (mut z Zone) zfree_drop(addr u64) bool {
	mut p := z.zone_element_resolve(addr)
	if p == unsafe { nil } || p.reserved == 0 {
		return false
	}
	i := z.slot(p, addr)
	unsafe {
		if p.live[i / 64] & (u64(1) << (i % 64)) != 0 {
			return false
		}
	}
	if !zone_bits_mark_free_ref(p.bits, p.words, i) {
		return false
	}
	old := p.reserved
	p.reserved--
	z.elems_free++
	if p.reserved == 0 {
		z.zone_meta_requeue(mut p, .empty)
		z.wired_empty += p.pages
	} else if old == p.capacity {
		z.zone_meta_requeue(mut p, .partial)
	}
	return true
}

// Adapted zone_reclaim_chunk: detach metadata and account under the lock;
// the adapter MUST release backing after unlocking and never touch it again.
pub fn (mut z Zone) zone_reclaim_chunk() &ZoneChunk {
	mut p := z.empty
	if p == unsafe { nil } {
		return unsafe { nil }
	}
	assert p.reserved == 0
	z.zone_meta_remqueue(mut p)
	z.elems_avail -= p.capacity
	z.elems_free -= p.capacity
	z.wired -= p.pages
	z.wired_empty -= p.pages
	if z.free_min > z.elems_free {
		z.free_min = z.elems_free
	}
	p.owner = 0
	return p
}

pub fn (mut z Zone) zone_reclaim_elements(elems &u64, n u16) {
	assert n <= magazine_capacity
	unsafe {
		for i := u16(0); i < n; i++ {
			addr := elems[i]
			elems[i] = 0
			ok := z.zfree_drop(addr)
			assert ok
		}
	}
}

// Non-SMR translations of zalloc_cached_depot_recirculate and prime.
fn (mut z Zone) zalloc_cached_depot_recirculate(mut c CpuCache) {
	max := z.depot_max
	assert max != 0
	if c.depot.empty >= max {
		z.recirc.zone_depot_move_empty(mut c.depot, c.depot.empty - max / 2,
			unsafe { nil })
	}
	mut n := max - c.depot.empty
	if n > z.recirc.full {
		n = z.recirc.full
	}
	if n != 0 {
		c.depot.zone_depot_move_full(mut z.recirc, n, &z.minimum, z.lifo)
	}
}

fn (mut z Zone) zalloc_cached_prime(mut c CpuCache) {
	if z.depot_max != 0 {
		if c.depot.full == 0 {
			z.zalloc_cached_depot_recirculate(mut c)
		}
		if c.depot.full != 0 {
			mut mag := c.depot.zone_depot_pop_head_full(unsafe { nil })
			mut old := c.cache.zone_magazine_replace(mut mag, false)
			c.depot.zone_depot_insert_head_empty(mut old)
		}
	} else if z.recirc.full != 0 {
		mut mag := z.recirc.zone_depot_pop_head_full(&z.minimum)
		mut old := c.cache.zone_magazine_replace(mut mag, false)
		z.recirc.zone_depot_insert_head_empty(mut old)
	}
	if c.cache.alloc_cur == 0 && z.elems_free != 0 {
		mut n := u32(magazine_capacity)
		if z.elems_free < n {
			n = u32(z.elems_free)
		}
		ok := z.zalloc_import(unsafe { &c.cache.alloc_mag.elems[0] }, n, &c.alloc_rr)
		assert ok
		c.cache.alloc_cur = u16(n)
	}
}

// Return 0 on exhaustion. The adapter can expand outside this state machine
// and retry. No WAITOK/NOFAIL promises or fake page waits are exposed here.
pub fn (mut z Zone) zalloc_ext(cache &CpuCache) u64 {
	mut addr := u64(0)
	if cache != unsafe { nil } {
		mut c := unsafe { cache }
		assert c.ready
		addr = c.cache.try_alloc()
		if addr == 0 {
			z.zalloc_cached_prime(mut c)
			addr = c.cache.try_alloc()
		}
	} else if z.elems_free != 0 {
		ok := z.zalloc_import(&addr, 1, &z.alloc_rr)
		assert ok
	}
	if addr != 0 {
		ok := z.zone_mark_valid(addr)
		assert ok
	}
	return addr
}

fn (mut z Zone) zfree_cached_depot_recirculate(mut c CpuCache) {
	max := z.depot_max
	assert max != 0
	if c.depot.full >= max {
		z.recirc.zone_depot_move_full(mut c.depot, c.depot.full - max / 2,
			unsafe { nil }, z.lifo)
	}
	mut n := max - c.depot.full
	if n > z.recirc.empty {
		n = z.recirc.empty
	}
	if n != 0 {
		c.depot.zone_depot_move_empty(mut z.recirc, n, &z.minimum)
	}
}

fn (mut z Zone) zfree_cached_trim(mut c CpuCache) bool {
	if z.depot_max != 0 {
		if c.depot.empty == 0 {
			z.zfree_cached_depot_recirculate(mut c)
		}
		if c.depot.empty != 0 {
			mut mag := c.depot.zone_depot_pop_head_empty(unsafe { nil })
			mut old := c.cache.zone_magazine_replace(mut mag, true)
			c.depot.zone_depot_insert_tail_full(mut old)
			return true
		}
	} else {
		// Fixed container pool adaptation: take a local empty container before
		// central empties, instead of recursively allocating magazine objects.
		mut mag := unsafe { &Magazine(nil) }
		if z.recirc.empty != 0 {
			mag = z.recirc.zone_depot_pop_head_empty(&z.minimum)
		} else if c.depot.empty != 0 {
			mag = c.depot.zone_depot_pop_head_empty(unsafe { nil })
		}
		if mag != unsafe { nil } {
			mut old := c.cache.zone_magazine_replace(mut mag, true)
			if z.lifo {
				z.recirc.zone_depot_insert_head_full(mut old)
			} else {
				z.recirc.zone_depot_insert_tail_full(mut old)
			}
			return true
		}
	}
	return false
}

// Call after zone_mark_invalid AND any poison/zero operation. The split
// interface ensures no object is published before the adapter sanitizes it.
pub fn (mut z Zone) zfree_ext(addr u64, cache &CpuCache) bool {
	p := z.zone_element_resolve(addr)
	if p == unsafe { nil } {
		return false
	}
	i := z.slot(p, addr)
	unsafe {
		bit := u64(1) << (i % 64)
		if p.bits[i / 64] & bit != 0 || p.live[i / 64] & bit != 0 {
			return false
		}
	}
	if cache != unsafe { nil } {
		mut c := unsafe { cache }
		assert c.ready
		if c.cache.try_free(addr) {
			return true
		}
		if z.zfree_cached_trim(mut c) {
			ok := c.cache.try_free(addr)
			assert ok
			return true
		}
	}
	return z.zfree_drop(addr)
}

// Drain active magazines AND the local depot. This is serialized with every
// alloc/free by the external lock; the adapter need not interrupt other CPUs.
pub fn (mut z Zone) zone_drain_cache(mut c CpuCache) {
	assert c.ready
	z.zone_reclaim_elements(unsafe { &c.cache.alloc_mag.elems[0] }, c.cache.alloc_cur)
	z.zone_reclaim_elements(unsafe { &c.cache.free_mag.elems[0] }, c.cache.free_cur)
	c.cache.alloc_cur = 0
	c.cache.free_cur = 0
	for c.depot.full != 0 {
		mut mag := c.depot.zone_depot_pop_head_full(unsafe { nil })
		z.zone_reclaim_elements(unsafe { &mag.elems[0] }, magazine_capacity)
		c.depot.zone_depot_insert_head_empty(mut mag)
	}
}

pub fn (mut z Zone) zone_drain_recirc() {
	for z.recirc.full != 0 {
		mut mag := z.recirc.zone_depot_pop_head_full(&z.minimum)
		z.zone_reclaim_elements(unsafe { &mag.elems[0] }, magazine_capacity)
		z.recirc.zone_depot_insert_head_empty(mut mag)
	}
}

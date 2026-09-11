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


@[has_globals; manualfree]
module memory

import xnualloc
import klock
import katomic
import lib

// Opt-in bridge for the ordinary XNU zone state machine. The class lock covers
// ALL CPU caches and depots as well as the core. This is deliberately a
// correctness-first serialization policy, not XNU's scalable locking scheme.
// Metadata remains in the same writable backing page. Large allocations still
// use Vinix's page-aligned malloc interface and contiguous physical allocation.
const xnu_heap_magic = u64(0x584e555a4f4e4531)
const xnu_heap_max_cpus = 64

struct XnuHeapClass {
mut:
	@lock  klock.Lock
	zone   xnualloc.Zone
	caches [64]&xnualloc.CpuCache
}

struct XnuHeapHeader {
mut:
	magic      u64
	class      u64
	chunk      xnualloc.ZoneChunk
	free_bits  [4]u64
	live_bits  [4]u64
}

__global (
	xnu_heap_classes [14]XnuHeapClass
	xnu_heap_cpus    = u64(0)
)

fn xnu_heap_init() {
	for i := 0; i < 14; i++ {
		mut h := &xnu_heap_classes[i]
		ok := h.zone.zone_init(slabs[i].ent_size, 2)
		if !ok {
			lib.kpanic(unsafe { nil }, c'XNU zone initialization failed')
			return
		}
		h.zone.resolve = xnu_heap_resolve
		for cpu := 0; cpu < xnu_heap_max_cpus; cpu++ {
			h.caches[cpu] = unsafe { nil }
		}
	}
}

// Called once by SMP bootstrap only AFTER every CPU has its kernel GS/TPIDR
// number installed and the online acquire/release handshake has completed.
// Readers load-acquire before inspecting CPU number. Early boot never reads it.
pub fn heap_enable_cpu_caches(count u64) {
	$if xnu_zone ? {
		if count == 0 {
			return
		}
		katomic.store(mut &xnu_heap_cpus, count)
	}
}

fn xnu_heap_resolve(addr u64) &xnualloc.ZoneChunk {
	if addr == 0 {
		return unsafe { nil }
	}
	mut hdr := unsafe { &XnuHeapHeader(addr & ~(page_size - 1)) }
	if hdr.magic != xnu_heap_magic || hdr.class >= 14 {
		return unsafe { nil }
	}
	return unsafe { &hdr.chunk }
}

fn (mut h XnuHeapClass) cache_locked(allow_create bool) &xnualloc.CpuCache {
	count := katomic.load(&xnu_heap_cpus)
	if count == 0 {
		return unsafe { nil }
	}
	// h.lock disables interrupts: CPU identity cannot migrate during this call.
	index := xnu_heap_cpu_number()
	if index >= count || index >= xnu_heap_max_cpus {
		return unsafe { nil }
	}
	mut c := h.caches[int(index)]
	// Do not spend the last backing page on an empty cache before a payload
	// exists. Failure to create a cache must leave this allocation satisfiable.
	if c == unsafe { nil } && allow_create && h.zone.elems_free != 0 {
		// No runtime allocation or recursive use of this heap for its caches.
		pages := lib.div_roundup(u64(sizeof(xnualloc.CpuCache)), page_size)
		phys := pmm_alloc_fallible(pages)
		if phys == unsafe { nil } {
			return unsafe { nil }
		}
		c = unsafe { &xnualloc.CpuCache(u64(phys) + higher_half) }
		ok := c.cache_init()
		if !ok {
			lib.kpanic(unsafe { nil }, c'XNU cache initialization failed')
			return unsafe { nil }
		}
		h.caches[int(index)] = c
	}
	return c
}

fn (mut h XnuHeapClass) grow_locked(index int) bool {
	phys := pmm_alloc_fallible(1)
	if phys == unsafe { nil } {
		return false
	}
	base := u64(phys) + higher_half
	mut hdr := unsafe { &XnuHeapHeader(base) }
	hdr.magic = xnu_heap_magic
	hdr.class = u64(index)
	hdr.chunk.base = base
	hdr.chunk.bytes = page_size
	hdr.chunk.offset = lib.align_up(u64(sizeof(XnuHeapHeader)), 16)
	hdr.chunk.pages = 1
	hdr.chunk.words = 4
	hdr.chunk.bits = unsafe { &hdr.free_bits[0] }
	hdr.chunk.live = unsafe { &hdr.live_bits[0] }
	if !h.zone.zcram(mut hdr.chunk) {
		hdr.magic = 0
		pmm_free(phys, 1)
		return false
	}
	return true
}

fn (mut h XnuHeapClass) drain_locked() {
	for i := 0; i < xnu_heap_max_cpus; i++ {
		mut c := h.caches[i]
		if c != unsafe { nil } {
			h.zone.zone_drain_cache(mut c)
		}
	}
	h.zone.zone_drain_recirc()
}

fn xnu_heap_alloc(size u64) voidptr {
	mut index := 0
	for index < 14 && xnu_heap_classes[index].zone.elem_size < size {
		index++
	}
	if index == 14 {
		return big_alloc(size)
	}
	mut h := &xnu_heap_classes[index]
	h.@lock.acquire()
	c := h.cache_locked(true)
	mut addr := h.zone.zalloc_ext(c)
	if addr == 0 {
		// Recover elements stranded in other CPU caches before requesting RAM.
		h.drain_locked()
		addr = h.zone.zalloc_ext(c)
	}
	if addr == 0 && h.grow_locked(index) {
		addr = h.zone.zalloc_ext(c)
	}
	capacity := h.zone.elem_size
	h.@lock.release()
	if addr == 0 {
		// Preserve Vinix's existing infallible small malloc OOM behavior.
		lib.kpanic(unsafe { nil }, c'XNU zone heap exhausted')
		return unsafe { nil }
	}
	// The client-live slot pins its page after unlock.
	unsafe { C.memset(voidptr(addr), 0, capacity) }
	return voidptr(addr)
}

fn xnu_heap_free(ptr voidptr) {
	mut hdr := unsafe { &XnuHeapHeader(u64(ptr) & ~(page_size - 1)) }
	if hdr.magic != xnu_heap_magic || hdr.class >= 14 {
		lib.kpanic(unsafe { nil }, c'XNU zone invalid free header')
		return
	}
	mut h := &xnu_heap_classes[int(hdr.class)]
	h.@lock.acquire()
	if !h.zone.zone_mark_invalid(u64(ptr)) {
		h.@lock.release()
		lib.kpanic(unsafe { nil }, c'XNU zone double or misaligned free')
		return
	}
	// Invalidate then poison before publishing to any cache or zone bitmap.
	unsafe { C.memset(ptr, 0xaa, h.zone.elem_size) }
	c := h.cache_locked(false)
	if !h.zone.zfree_ext(u64(ptr), c) {
		h.@lock.release()
		lib.kpanic(unsafe { nil }, c'XNU zone corrupt free state')
		return
	}
	// Keep one fully empty spare; cached objects intentionally pin pages.
	mut dead := u64(0)
	if h.zone.wired_empty > 1 {
		p := h.zone.zone_reclaim_chunk()
		dead = p.base
		mut old := unsafe { &XnuHeapHeader(dead) }
		old.magic = 0
	}
	h.@lock.release()
	if dead != 0 {
		pmm_free(voidptr(dead - higher_half), 1)
	}
}

fn xnu_heap_realloc(ptr voidptr, size u64) voidptr {
	mut hdr := unsafe { &XnuHeapHeader(u64(ptr) & ~(page_size - 1)) }
	if hdr.magic != xnu_heap_magic || hdr.class >= 14 {
		lib.kpanic(unsafe { nil }, c'XNU zone invalid realloc')
		return unsafe { nil }
	}
	old_size := xnu_heap_classes[int(hdr.class)].zone.elem_size
	if size <= old_size {
		return ptr
	}
	new_ptr := malloc(size)
	if new_ptr == unsafe { nil } {
		return unsafe { nil }
	}
	unsafe { C.memcpy(new_ptr, ptr, old_size) }
	xnu_heap_free(ptr)
	return new_ptr
}

fn xnu_heap_trim() u64 {
	mut bytes := u64(0)
	for i := 0; i < 14; i++ {
		mut h := &xnu_heap_classes[i]
		h.@lock.acquire()
		h.drain_locked()
		// Detach a private list under the lock, then release outside it.
		mut head := u64(0)
		for h.zone.empty != unsafe { nil } {
			mut p := h.zone.zone_reclaim_chunk()
			mut hdr := unsafe { &XnuHeapHeader(p.base) }
			hdr.magic = 0
			p.next = unsafe { &xnualloc.ZoneChunk(head) }
			head = u64(p)
		}
		h.@lock.release()
		for head != 0 {
			p := unsafe { &xnualloc.ZoneChunk(head) }
			next := u64(p.next)
			base := p.base
			// Capture everything needed before PMM poisons the backing page.
			pmm_free(voidptr(base - higher_half), 1)
			bytes += page_size
			head = next
		}
	}
	return bytes
}

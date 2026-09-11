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

// Data-structure translations used by zone.v and its opt-in Vinix adapter.
// Callers supply CPU pinning, locks, ownership transitions, refill, accounting
// and safe reclamation. No SMR grace-period implementation is hidden behind
// a successful stub. Depot polling requires an explicit poll callback when
// SMR is requested; the zone.v backend is strictly non-SMR.
//
// Storage adaptation: the flexible C array has a fixed 32-element capacity.
pub const magazine_capacity = u16(32)

pub struct Magazine {
pub mut:
	next  &Magazine = unsafe { nil }
	seq   u64
	elems [32]u64
}

pub struct Cache {
pub mut:
	alloc_cur u16
	free_cur  u16
	alloc_mag &Magazine = unsafe { nil }
	free_mag  &Magazine = unsafe { nil }
}

// One chain, as in XNU: full magazines precede empty magazines, and tail is
// the address of the link separating the two portions. A Depot MUST NOT MOVE
// after init(), because tail may point to its own head field.
pub struct Depot {
pub mut:
	head  &Magazine = unsafe { nil }
	tail  &&Magazine = unsafe { nil }
	full  u32
	empty u32
}

// The zone's recirculation minima are explicit parameters in this port.
pub struct RecircMinimum {
pub mut:
	full  u32
	empty u32
}

pub fn (mut d Depot) zone_depot_init() {
	d.head = unsafe { nil }
	d.full = 0
	d.empty = 0
	unsafe { d.tail = &d.head }
}

pub fn (mut d Depot) zone_depot_insert_head_full(mut mag Magazine) {
	assert d.tail != unsafe { nil }
	if d.full == 0 {
		unsafe { d.tail = &mag.next }
	}
	d.full++
	mag.next = d.head
	unsafe { d.head = mag }
}

pub fn (mut d Depot) zone_depot_insert_tail_full(mut mag Magazine) {
	assert d.tail != unsafe { nil }
	d.full++
	unsafe {
		mag.next = *d.tail
		*d.tail = mag
		d.tail = &mag.next
	}
}

pub fn (mut d Depot) zone_depot_insert_head_empty(mut mag Magazine) {
	assert d.tail != unsafe { nil }
	d.empty++
	unsafe {
		mag.next = *d.tail
		*d.tail = mag
	}
}

pub fn (mut d Depot) zone_depot_pop_head_full(minimum &RecircMinimum) &Magazine {
	assert d.full != 0
	mut mag := d.head
	d.full--
	unsafe {
		if minimum != nil && minimum.full > d.full {
			mut m := minimum
			m.full = d.full
		}
		d.head = mag.next
		if d.full == 0 {
			d.tail = &d.head
		}
		mag.next = nil
	}
	return mag
}

pub fn (mut d Depot) zone_depot_pop_head_empty(minimum &RecircMinimum) &Magazine {
	assert d.empty != 0
	unsafe {
		mut mag := *d.tail
		d.empty--
		if minimum != nil && minimum.empty > d.empty {
			mut m := minimum
			m.empty = d.empty
		}
		*d.tail = mag.next
		mag.next = nil
		return mag
	}
}

// lifo is the supplied equivalent of zone_security_array[zid].z_lifo.
// Source and destination must be distinct, initialized, externally locked.
pub fn (mut dst Depot) zone_depot_move_full(mut src Depot, n u32,
	minimum &RecircMinimum, lifo bool) u64 {
	assert n > 0 && src.full >= n && u64(&dst) != u64(&src)
	src.full -= n
	unsafe {
		if minimum != nil && minimum.full > src.full {
			mut m := minimum
			m.full = src.full
		}
		head := src.head
		mut last := head
		for i := u32(1); i < n; i++ {
			last = last.next
		}
		src.head = last.next
		if src.full == 0 {
			src.tail = &src.head
		}
		if lifo {
			if dst.full == 0 {
				dst.tail = &last.next
			}
			last.next = dst.head
			dst.head = head
		} else {
			last.next = *dst.tail
			*dst.tail = head
			dst.tail = &last.next
		}
		dst.full += n
		return last.seq
	}
}

pub fn (mut dst Depot) zone_depot_move_empty(mut src Depot, n u32,
	minimum &RecircMinimum) {
	assert n > 0 && src.empty >= n && u64(&dst) != u64(&src)
	src.empty -= n
	unsafe {
		if minimum != nil && minimum.empty > src.empty {
			mut m := minimum
			m.empty = src.empty
		}
		head := *src.tail
		mut last := head
		for i := u32(1); i < n; i++ {
			last = last.next
		}
		*src.tail = last.next
		dst.empty += n
		last.next = *dst.tail
		*dst.tail = head
	}
}

pub fn (d &Depot) zone_depot_poll(use_smr bool, poll fn (u64) bool) bool {
	if d.full == 0 {
		return false
	}
	if !use_smr {
		return true
	}
	// Explicit failure is essential: treating every SMR sequence as ready
	// would permit use-after-free of still-observed objects.
	if poll == unsafe { nil } {
		return false
	}
	return poll(d.head.seq)
}

pub fn (mut c Cache) zone_cache_swap_magazines() {
	assert c.alloc_cur <= magazine_capacity && c.free_cur <= magazine_capacity
	count_a := c.alloc_cur
	count_f := c.free_cur
	elems_a := c.alloc_mag
	elems_f := c.free_mag
	c.alloc_cur = count_f
	c.free_cur = count_a
	c.alloc_mag = elems_f
	c.free_mag = elems_a
}

pub fn (mut c Cache) zone_magazine_replace(mut mag Magazine, empty bool) &Magazine {
	mag.seq = 0 // SMR_SEQ_INVALID
	mut old := unsafe { &Magazine(nil) }
	if empty {
		old = c.free_mag
		c.free_cur = 0
		unsafe { c.free_mag = mag }
	} else {
		old = c.alloc_mag
		c.alloc_cur = magazine_capacity
		unsafe { c.alloc_mag = mag }
	}
	return old
}

// Non-SMR fast-path operations from zalloc/zfree's cache paths, exposed for
// differential testing. 0/false asks the caller to refill/trim; it is not OOM.
pub fn (mut c Cache) try_alloc() u64 {
	assert c.alloc_mag != unsafe { nil } && c.free_mag != unsafe { nil }
	if c.alloc_cur == 0 && c.free_cur != 0 {
		c.zone_cache_swap_magazines()
	}
	if c.alloc_cur == 0 {
		return 0
	}
	c.alloc_cur--
	value := c.alloc_mag.elems[int(c.alloc_cur)]
	c.alloc_mag.elems[int(c.alloc_cur)] = 0
	return value
}

pub fn (mut c Cache) try_free(value u64) bool {
	assert value != 0 && c.alloc_mag != unsafe { nil } && c.free_mag != unsafe { nil }
	if c.free_cur == magazine_capacity && c.alloc_cur < magazine_capacity {
		c.zone_cache_swap_magazines()
	}
	if c.free_cur == magazine_capacity {
		return false
	}
	c.free_mag.elems[int(c.free_cur)] = value
	c.free_cur++
	return true
}

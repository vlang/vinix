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


// Ordinary zone and cache state-machine tests. These execute V when run by vtest.
module main

import xnualloc

fn zn_install(mut z xnualloc.Zone, mut p xnualloc.ZoneChunk, bits &u64,
	live &u64, base u64, offset u64) {
	p.base = base
	p.bytes = 4096
	p.offset = offset
	p.pages = 1
	p.words = 4
	unsafe {
		p.bits = bits
		p.live = live
	}
	assert z.zcram(mut p)
}

fn zn_bitcount(value u64) u64 {
	mut v := value
	mut n := u64(0)
	for v != 0 {
		v &= v - 1
		n++
	}
	return n
}

fn zn_check(z &xnualloc.Zone, chunks &xnualloc.ZoneChunk, count int) {
	mut capacity := u64(0)
	mut available_total := u64(0)
	mut live := u64(0)
	mut pages := u64(0)
	mut empty := u64(0)
	unsafe {
		for j := 0; j < count; j++ {
			p := &chunks[j]
			if p.owner == 0 {
				assert p.queue == .detached
				continue
			}
			assert p.owner == u64(z)
			mut available := u64(0)
			mut active := u64(0)
			for i := u32(0); i < p.words; i++ {
				assert p.bits[i] & p.live[i] == 0
				available += zn_bitcount(p.bits[i])
				active += zn_bitcount(p.live[i])
			}
			assert available + p.reserved == p.capacity
			assert active <= p.reserved
			expected := if p.reserved == 0 { xnualloc.ChunkQueue.empty }
				else if p.reserved == p.capacity { xnualloc.ChunkQueue.full }
				else { xnualloc.ChunkQueue.partial }
			assert p.queue == expected
			capacity += p.capacity
			available_total += available
			live += active
			pages += p.pages
			if p.reserved == 0 { empty += p.pages }
		}
	}
	assert z.elems_avail == capacity && z.elems_free == available_total
	assert z.live_count == live && z.wired == pages && z.wired_empty == empty
	mut seen := map[u64]bool{}
	unsafe {
		mut heads := [z.empty, z.partial, z.full]!
		for index in 0 .. heads.len {
			mut p := heads[index]
			mut prev := u64(0)
			for p != nil {
				assert !seen[u64(p)]
				seen[u64(p)] = true
				assert u64(p.prev) == prev
				prev = u64(p)
				p = p.next
			}
		}
	}
	assert u64(seen.len) == pages
}

fn test_zone_queue_transitions_and_batch_atomicity() {
	mut z := xnualloc.Zone{}
	assert z.zone_init(64, 2)
	mut p := [2]xnualloc.ZoneChunk{}
	mut bits := [2][4]u64{}
	mut live := [2][4]u64{}
	for i := 0; i < 2; i++ {
		zn_install(mut z, mut p[i], unsafe { &bits[i][0] }, unsafe { &live[i][0] },
			u64(i + 1) * 4096, 0)
	}
	mut out := [128]u64{}
	mut rr := u16(0)
	assert !z.zalloc_import(unsafe { &out[0] }, 129, &rr)
	assert z.elems_free == 128 && out[0] == 0
	assert z.zalloc_import(unsafe { &out[0] }, 65, &rr)
	assert p[1].queue == .full && p[0].queue == .partial
	assert p[1].reserved == 64 && p[0].reserved == 1
	zn_check(&z, unsafe { &p[0] }, 2)
	for i := 0; i < 65; i++ { assert z.zfree_drop(out[i]) }
	zn_check(&z, unsafe { &p[0] }, 2)
	assert z.wired_empty == 2
	for _ in 0 .. 2 { assert z.zone_reclaim_chunk() != unsafe { nil } }
	assert z.zone_reclaim_chunk() == unsafe { nil }
	zn_check(&z, unsafe { &p[0] }, 2)
}

fn test_zone_rejects_misaligned_and_cached_double_free() {
	mut z := xnualloc.Zone{}
	assert z.zone_init(48, 2)
	mut p := xnualloc.ZoneChunk{}
	mut bits := [4]u64{}
	mut live := [4]u64{}
	zn_install(mut z, mut p, unsafe { &bits[0] }, unsafe { &live[0] }, 4096, 16)
	mut c := xnualloc.CpuCache{}
	assert c.cache_init()
	addr := z.zalloc_ext(&c)
	assert addr != 0 && z.live_count == 1
	assert !z.zone_mark_invalid(addr + 1)
	assert !z.zfree_drop(addr)
	assert z.zone_mark_invalid(addr)
	assert z.zfree_ext(addr, &c)
	assert !z.zone_mark_invalid(addr)
	assert z.live_count == 0 && p.reserved > 0
	assert z.zone_reclaim_chunk() == unsafe { nil }
	z.zone_drain_cache(mut c)
	z.zone_drain_recirc()
	assert p.reserved == 0 && z.elems_free == p.capacity
	assert z.zone_reclaim_chunk() != unsafe { nil }
}

fn test_zone_reclaim_does_not_drop_live_survivor() {
	mut z := xnualloc.Zone{}
	assert z.zone_init(16, 2)
	mut p := xnualloc.ZoneChunk{}
	mut bits := [4]u64{}
	mut live := [4]u64{}
	zn_install(mut z, mut p, unsafe { &bits[0] }, unsafe { &live[0] }, 4096, 0)
	mut c := xnualloc.CpuCache{}
	assert c.cache_init()
	addr := z.zalloc_ext(&c)
	z.zone_drain_cache(mut c)
	z.zone_drain_recirc()
	assert p.reserved == 1 && z.live_count == 1
	assert z.zone_reclaim_chunk() == unsafe { nil }
	assert z.zone_mark_invalid(addr)
	assert z.zfree_ext(addr, unsafe { nil })
	assert z.zone_reclaim_chunk() != unsafe { nil }
}

fn zn_random(state &u64) u64 {
	unsafe {
		mut v := *state
		v ^= v << 13
		v ^= v >> 7
		v ^= v << 17
		*state = v
		return v
	}
}

fn test_zone_multi_cpu_migration_and_drain_sequences() {
	for depot_max in [u32(0), 1, 2, 4] {
		mut z := xnualloc.Zone{}
		assert z.zone_init(16, depot_max)
		mut p := [4]xnualloc.ZoneChunk{}
		mut bits := [4][4]u64{}
		mut live_bits := [4][4]u64{}
		mut cpus := [4]xnualloc.CpuCache{}
		for i := 0; i < 4; i++ {
			zn_install(mut z, mut p[i], unsafe { &bits[i][0] }, unsafe { &live_bits[i][0] },
				u64(i + 1) * 4096, 0)
			assert cpus[i].cache_init()
		}
		mut live := []u64{}
		mut state := u64(0x1234567812345678) + depot_max
		for step in 0 .. 20000 {
			r := zn_random(&state)
			cpu := int((r >> 12) & 3)
			if live.len == 0 || (live.len < 800 && r & 1 == 0) {
				addr := z.zalloc_ext(unsafe { &cpus[cpu] })
				if addr != 0 {
					assert addr !in live
					live << addr
				}
			} else {
				i := int((r >> 20) % u64(live.len))
				addr := live[i]
				assert z.zone_mark_invalid(addr)
				assert z.zfree_ext(addr, unsafe { &cpus[cpu] })
				live.delete(i)
			}
			if step % 71 == 0 {
				z.zone_drain_cache(mut cpus[cpu])
				z.zone_drain_recirc()
			}
			zn_check(&z, unsafe { &p[0] }, 4)
			assert z.live_count == u64(live.len)
		}
		for addr in live {
			assert z.zone_mark_invalid(addr)
			assert z.zfree_ext(addr, unsafe { &cpus[0] })
		}
		for i := 0; i < 4; i++ { z.zone_drain_cache(mut cpus[i]) }
		z.zone_drain_recirc()
		zn_check(&z, unsafe { &p[0] }, 4)
		assert z.elems_free == 1024 && z.live_count == 0
		for _ in 0 .. 4 { assert z.zone_reclaim_chunk() != unsafe { nil } }
		zn_check(&z, unsafe { &p[0] }, 4)
	}
}

fn test_zone_geometry_rejection_and_no_backing_failure() {
	mut z := xnualloc.Zone{}
	assert !z.zone_init(0, 2)
	assert !z.zone_init(16, 5)
	assert z.zone_init(16, 2)
	assert !z.zone_init(16, 2)
	assert z.zalloc_ext(unsafe { nil }) == 0
	mut p := xnualloc.ZoneChunk{base: u64(-1) - 1024, bytes: 4096}
	assert !z.zcram(mut p)
	assert p.owner == 0 && z.elems_avail == 0
}

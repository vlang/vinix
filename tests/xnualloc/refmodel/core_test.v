// Copyright (c) 2000-2020 Apple Inc. All rights reserved.
//
// @APPLE_OSREFERENCE_LICENSE_HEADER_START@
//
// This file contains Original Code and/or Modifications of Original Code
// as defined in and that are subject to the Apple Public Source License
// Version 2.0 (the 'License'). You may not use this file except in
// compliance with the License. The rights granted to you under the License
// may not be used to create, or enable the creation or redistribution of,
// unlawful or unlicensed copies of an Apple operating system, or to
// circumvent, violate, or enable the circumvention or violation of, any
// terms of an Apple operating system software license agreement.
//
// Please obtain a copy of the License at
// http://www.opensource.apple.com/apsl/ and read it before using this file.
//
// The Original Code and all software distributed under the License are
// distributed on an 'AS IS' basis, WITHOUT WARRANTY OF ANY KIND, EITHER
// EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
// INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE, QUIET ENJOYMENT OR NON-INFRINGEMENT.
// Please see the License for the specific language governing rights and
// limitations under the License.
//
// @APPLE_OSREFERENCE_LICENSE_HEADER_END@
// @OSF_COPYRIGHT@
// Mach Operating System
// Copyright (c) 1991,1990,1989,1988,1987 Carnegie Mellon University
// All Rights Reserved.
//
// Permission to use, copy, modify and distribute this software and its
// documentation is hereby granted, provided that both the copyright
// notice and this permission notice appear in all copies of the
// software, derivative works or modified versions, and any portions
// thereof, and that both notices appear in supporting documentation.
//
// CARNEGIE MELLON ALLOWS FREE USE OF THIS SOFTWARE IN ITS "AS IS"
// CONDITION.  CARNEGIE MELLON DISCLAIMS ANY LIABILITY OF ANY KIND FOR
// ANY DAMAGES WHATSOEVER RESULTING FROM THE USE OF THIS SOFTWARE.
//
// Carnegie Mellon requests users of this software to return to
//
// Software Distribution Coordinator  or  Software.Distribution@CS.CMU.EDU
// School of Computer Science
// Carnegie Mellon University
// Pittsburgh PA 15213-3890
//
// any improvements or extensions that they make and grant Carnegie Mellon
// the rights to redistribute these changes.
// Modified 2026-09-11: Python differential harness and translated buddy model.
// Upstream: apple-oss-distributions/xnu f6217f891ac0bb64f3d375211650a4c1ff8ca1ea,
// osfmk/kern/zalloc.c. See docs/xnualloc/PORT_STATUS.md and
// kernel/xnualloc/APPLE_LICENSE.
// These translations retain APSL 2.0; they are NOT relicensed as GPL.
//
//
// Independent C fixture versus V byte oracle; no kernel allocator is imported.
module refmodel

import heapmodel
import os

fn source_root() string { return os.dir(os.dir(os.dir(os.dir(@FILE)))) }

struct MergeRange {
 first int
 end int
}

fn test_rotating_scan_against_bit_by_bit_oracle() {
	destination := temporary()!
	defer { os.rmdir_all(destination) or { panic(err) } }
	reference := load(12, destination, source_root())!
	defer { reference.close() }
	mut rng := heapmodel.random(0x584e55)
	for n in 0 .. 12000 {
		words := 1 << rng.below(8)
		mut values := []u64{len: words}
		for i in 0 .. words { if n % 3 == 0 { values[i] = rng.bits(64) } }
		if n % 3 == 1 {
			slot := rng.below(words * 64)
			values[slot / 64] = u64(1) << (slot % 64)
		}
		start := rng.below(words * 64 + 1)
		mut wanted := u64(0xffffffffffffffff)
		for step in 0 .. words * 64 {
			i := (start + step) % (words * 64)
			if values[i / 64] & (u64(1) << (i % 64)) != 0 { wanted = u64(i); break }
		}
		mut actual := values.clone()
		assert reference.scan(actual.data, u32(words), u64(start)) == wanted
		if wanted != u64(0xffffffffffffffff) { values[int(wanted / 64)] &= ~(u64(1) << (wanted % 64)) }
		assert actual == values
	}
}

fn test_merge_and_duplicate_free() {
	destination := temporary()!
	defer { os.rmdir_all(destination) or { panic(err) } }
	reference := load(12, destination, source_root())!
	defer { reference.close() }
	mut rng := heapmodel.random(7)
	boundaries := [0, 1, 31, 32, 33, 63, 64, 65, 127, 128, 129, 255, 256]
	mut pairs := []MergeRange{}
	for first in boundaries { for end in boundaries { if first <= end { pairs << MergeRange{first, end} } } }
	for _ in 0 .. 3000 {
		a := rng.below(257)
		b := rng.below(257)
		pairs << if a < b { MergeRange{a, b} } else { MergeRange{b, a} }
	}
	for pair in pairs {
		first, end := pair.first, pair.end
		mut actual := [4]u64{}
		reference.merge(&actual[0], u32(first), u32(end))
		mut expected := [4]u64{}
		for slot in first .. end { expected[slot / 64] |= u64(1) << (slot % 64) }
		assert actual == expected
		slot := rng.below(256)
		was_free := expected[slot / 64] & (u64(1) << (slot % 64)) != 0
		assert reference.mark_free(&actual[0], u64(slot)) == !was_free
		assert !reference.mark_free(&actual[0], u64(slot))
	}
}

struct Live {
	address int
	order   int
	extra   bool
}

fn test_buddy_mixed_orders_banks_and_exact_arena_state() {
	destination := temporary()!
	defer { os.rmdir_all(destination) or { panic(err) } }
	for shift in [12, 14] {
		reference := load(shift, destination, source_root())!
		assert reference.initialize(16) == 0
		mut model := buddy(shift, 16)
		mut snapshot := []u8{len: model.data.len}
		mut rng := heapmodel.random(u64(shift))
		mut live := []Live{}
		for step in 0 .. 20000 {
			if live.len == 0 || (live.len < 512 && rng.below(4) != 0) {
				order := rng.below(model.order + 1)
				extra := rng.below(2) != 0
				actual := reference.allocate(u32(order), extra)
				assert actual == u64(model.allocate(order, extra))
				if actual != 0 {
					size := 8 << order
					for old in live { assert int(actual) + size <= old.address || old.address + (8 << old.order) <= int(actual) }
					live << Live{int(actual), order, extra}
				}
			} else {
				index := rng.below(live.len)
				item := live[index]
				live.delete(index)
				reference.release(u64(item.address), u32(item.order), item.extra)
				model.release(item.address, item.order, item.extra)
			}
			if step % 37 == 0 {
				reference.snapshot(snapshot.data)
				assert snapshot == model.data
				model.check_lists()
			}
		}
		for item in live {
			reference.release(u64(item.address), u32(item.order), item.extra)
			model.release(item.address, item.order, item.extra)
		}
		reference.snapshot(snapshot.data)
		assert snapshot == model.data
		model.check_lists()
		mut total := 0
		for extra in [false, true] {
			for {
				address := reference.allocate(u32(model.order), extra)
				if address == 0 { break }
				assert address == u64(model.allocate(model.order, extra))
				total++
			}
		}
		assert total == 16
		reference.close()
	}
}

fn test_single_chunk_exhaustion_and_reuse() {
	destination := temporary()!
	defer { os.rmdir_all(destination) or { panic(err) } }
	for shift in [12, 14] {
		reference := load(shift, destination, source_root())!
		assert reference.initialize(1) == 0
		mut model := buddy(shift, 1)
		mut values := []u64{}
		for {
			address := reference.allocate(0, false)
			if address == 0 { break }
			assert address == u64(model.allocate(0, false))
			values << address
		}
		assert model.allocate(0, false) == 0
		expected := ((1 << shift) - model.hdr - 8 - model.heads * 16) / 8
		assert values.len == expected
		for index := values.len - 1; index >= 0; index-- {
			reference.release(values[index], 0, false)
			model.release(int(values[index]), 0, false)
		}
		mut second := []u64{}
		for {
			address := reference.allocate(0, false)
			if address == 0 { break }
			assert address == u64(model.allocate(0, false))
			second << address
		}
		assert second.len == values.len
		reference.close()
	}
}

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
// The byte-oriented buddy oracle remains independent of kernel V.
module refmodel

import encoding.binary

pub struct BuddyModel {
pub:
	page  int
	order int
	heads int
	hdr   int
pub mut:
	data []u8
}

pub fn buddy(shift int, chunks int) BuddyModel {
	page := 1 << shift
	mut result := BuddyModel{page: page, order: shift - 4, heads: shift - 3, hdr: page / 64, data: []u8{len: page * chunks}}
	result.w32(result.hdr, 1)
	result.w32(result.hdr + 4, u32(chunks))
	result.init_chunk(0, false)
	return result
}

pub fn (model BuddyModel) r32(offset int) u32 { return binary.little_endian_u32(model.data[offset..offset + 4]) }

fn (mut model BuddyModel) w32(offset int, value u32) { binary.little_endian_put_u32(mut model.data[offset..offset + 4], value) }

fn (model BuddyModel) head(order int, extra bool) int {
	return (model.hdr + 8 + ((if extra { model.heads } else { 0 }) + order) * 8) / 8
}

fn (mut model BuddyModel) push(index int, order int, extra bool) {
	head := model.head(order, extra)
	next := model.r32(head * 8)
	if next != 0 {
		assert model.r32(int(next) * 8 + 4) == u32(head)
		model.w32(int(next) * 8 + 4, u32(index))
	}
	model.w32(index * 8, next)
	model.w32(index * 8 + 4, u32(head))
	model.w32(head * 8, u32(index))
}

fn (mut model BuddyModel) remove(index int) {
	next := model.r32(index * 8)
	previous := model.r32(index * 8 + 4)
	assert model.r32(int(previous) * 8) == u32(index)
	model.w32(int(previous) * 8, next)
	if next != 0 {
		assert model.r32(int(next) * 8 + 4) == u32(index)
		model.w32(int(next) * 8 + 4, previous)
	}
}

fn (mut model BuddyModel) pop(order int, extra bool) int {
	index := int(model.r32(model.head(order, extra) * 8))
	if index != 0 { model.remove(index) }
	return index * 8
}

fn (model BuddyModel) node(address int, order int) int {
	return ((address % model.page / 8) >> order) + (1 << (model.order - order + 1)) - 1
}

fn (model BuddyModel) address(page int, node int, order int) int {
	return page + ((node - (1 << (model.order - order + 1)) + 1) << order) * 8
}

fn (mut model BuddyModel) flip(page int, node int) {
	position := page + (node / 64) * 8
	word := binary.little_endian_u64(model.data[position..position + 8])
	binary.little_endian_put_u64(mut model.data[position..position + 8], word ^ (u64(1) << (node % 64)))
}

fn (model BuddyModel) split(page int, node int) bool {
	position := page + (node / 64) * 8
	word := binary.little_endian_u64(model.data[position..position + 8])
	return word & (u64(1) << (node % 64)) != 0
}

fn (mut model BuddyModel) init_chunk(index int, extra bool) {
	header := model.hdr + if index == 0 { 8 + model.heads * 16 } else { 0 }
	page := index * model.page
	mut size := model.page
	for order := model.order; order >= 0; order-- {
		block := 8 << order
		if size < header + block { continue }
		size -= block
		node := model.node(page + size, order)
		model.flip(page, (node - 1) / 2)
		model.push(model.address(page, node, order) / 8, order, extra)
	}
}

fn (mut model BuddyModel) grow(extra bool) bool {
	left := int(model.r32(model.hdr))
	right := int(model.r32(model.hdr + 4))
	if left >= right { return false }
	index := if extra { right - 1 } else { left }
	for i in index * model.page .. (index + 1) * model.page { model.data[i] = 0 }
	model.w32(model.hdr + if extra { 4 } else { 0 }, u32(if extra { right - 1 } else { left + 1 }))
	model.init_chunk(index, extra)
	return true
}

pub fn (mut model BuddyModel) allocate(order int, extra bool) int {
	mut current := order
	mut address := model.pop(current, extra)
	for address == 0 {
		if current >= model.order {
			if !model.grow(extra) { return 0 }
			current = order
		} else { current++ }
		address = model.pop(current, extra)
	}
	page := address & -model.page
	mut node := model.node(address, current)
	model.flip(page, (node - 1) / 2)
	for current > order {
		current--
		model.flip(page, node)
		node = node * 2 + 1
		model.push(model.address(page, node + 1, current) / 8, current, extra)
	}
	return address
}

pub fn (mut model BuddyModel) release(address int, requested_order int, extra bool) {
	page := address & -model.page
	mut node := model.node(address, requested_order)
	mut order := requested_order
	for node != 0 {
		parent := (node - 1) / 2
		model.flip(page, parent)
		if model.split(page, parent) { break }
		model.remove(model.address(page, ((node - 1) ^ 1) + 1, order) / 8)
		order++
		node = parent
	}
	assert order <= model.order
	model.push(model.address(page, node, order) / 8, order, extra)
}

pub fn (model BuddyModel) check_lists() {
	mut visited := map[int]bool{}
	for extra in [false, true] {
		for order in 0 .. model.heads {
			mut previous := model.head(order, extra)
			mut index := int(model.r32(previous * 8))
			for index != 0 {
				assert index !in visited
				visited[index] = true
				assert model.r32(index * 8 + 4) == u32(previous)
				assert (index * 8) % (8 << order) == 0
				assert index * 8 + (8 << order) <= model.data.len
				previous, index = index, int(model.r32(index * 8))
			}
		}
	}
}

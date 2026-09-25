// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module mmap

import memory

// One mapping of an address space, as /proc/<pid>/maps and smaps describe it.
pub struct MappingInfo {
pub mut:
	base   u64
	end    u64
	prot   int
	shared bool
	// Where in its file the mapping starts, and the file's device and inode;
	// zero for anonymous memory.
	offset u64
	dev    u64
	ino    u64
	file   bool
	// Part of the arena the program break grows in.
	brk bool
	// The open file the mapping was made from, held until release_mappings(),
	// so that its name can still be looked up once the address space is let
	// go of.
	handle       voidptr
	handle_unref fn (voidptr) = unsafe { nil }
	// Bytes resident, how many of them another process shares, and the
	// mapping's share of them; counted only when asked for.
	resident        u64
	shared_resident u64
	share           u64
}

// The mappings of `pagemap` in address order, or none when another CPU holds
// its lock for longer than a reader should wait. The caller keeps the page map
// alive meanwhile.
pub fn mappings(_pagemap &memory.Pagemap, count_pages bool) ?[]MappingInfo {
	mut pagemap := unsafe { _pagemap }
	if pagemap == unsafe { nil } {
		return []MappingInfo{}
	}
	mut acquired := false
	for _ in 0 .. 100000 {
		if pagemap.l.test_and_acquire() {
			acquired = true
			break
		}
	}
	if !acquired {
		return none
	}
	defer {
		pagemap.l.release()
	}

	mut list := []MappingInfo{cap: pagemap.mmap_ranges.len}
	for ptr in pagemap.mmap_ranges {
		local_range := unsafe { &MmapRangeLocal(ptr) }
		if unsafe { local_range == nil } {
			continue
		}
		global_range := local_range.global
		mut info := MappingInfo{
			base:   local_range.base
			end:    local_range.base + local_range.length
			prot:   local_range.prot
			shared: local_range.flags & map_shared != 0
			brk:    local_range.flags & map_brk_reservation != 0
		}
		if global_range != unsafe { nil } && global_range.resource != unsafe { nil }
			&& local_range.flags & map_anonymous == 0 {
			info.file = true
			info.offset = u64(local_range.offset)
			info.dev = global_range.resource.stat.dev
			info.ino = global_range.resource.stat.ino
			if global_range.handle != unsafe { nil } && global_range.handle_ref != unsafe { nil }
				&& global_range.handle_unref != unsafe { nil } {
				global_range.handle_ref(global_range.handle)
				info.handle = global_range.handle
				info.handle_unref = global_range.handle_unref
			}
		}
		if count_pages && local_range.prot != prot_none {
			counted := pagemap.residency(info.base, info.end)
			info.resident = counted.resident
			info.shared_resident = counted.shared
			info.share = counted.share
			// A shared mapping's pages are the same memory wherever the range
			// is mapped, and are not counted per mapping.
			if info.shared && global_range != unsafe { nil } {
				range_locals_lock.acquire()
				sharers := u64(global_range.locals.len)
				range_locals_lock.release()
				if sharers > 1 {
					info.shared_resident = info.resident
					info.share = info.resident / sharers
				}
			}
		}
		// Kept in address order, as the ranges need not be.
		mut at := list.len
		for at > 0 && list[at - 1].base > info.base {
			at--
		}
		list.insert(at, info)
	}
	return list
}

// Let go of the files mappings() held.
pub fn release_mappings(mut list []MappingInfo) {
	for info in list {
		if info.handle != unsafe { nil } {
			info.handle_unref(info.handle)
		}
	}
	unsafe { list.free() }
}

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

	// The caller frees it with release_mappings().
	mut list := []MappingInfo{cap: pagemap.mmap_ranges.len} @[freed]
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
		// Pushed and moved into place rather than inserted: insert() takes the
		// value's address, and V copied `info` to the heap for it every time.
		list << info
		// Kept in address order, as the ranges need not be.
		for at := list.len - 1; at > 0 && list[at - 1].base > list[at].base; at-- {
			list[at - 1], list[at] = list[at], list[at - 1]
		}
	}
	return list
}

// ProcessMemory is what an address space holds. `mapped` is the length of its
// accessible mappings: address space, much of which a program never touches.
// Every program's first thread alone reserves a 256 MiB stack, so this is
// never below that. `resident` is the memory actually present, each page
// counted as its share when other processes map it too, so the figures of a
// group of processes add up to the memory they use between them. Device
// memory, such as a mapped framebuffer, is in neither: it is not RAM the
// program uses.
pub struct ProcessMemory {
pub:
	mapped   u64
	resident u64
}

// process_memory counts an address space without waiting for its lock, so a
// caller may hold the process table: a process in the middle of an mmap holds
// its pagemap while it goes on to take locks that come after the table, and
// waiting here is how a monitor deadlocks the machine it is monitoring. None
// when the lock is busy, which the caller reports as nothing for one sample.
pub fn process_memory(_pagemap &memory.Pagemap) ?ProcessMemory {
	mut pagemap := unsafe { _pagemap }
	if pagemap == unsafe { nil } {
		return ProcessMemory{}
	}
	if !pagemap.l.test_and_acquire() {
		return none
	}
	defer {
		pagemap.l.release()
	}
	mut mapped := u64(0)
	mut resident := u64(0)
	for i := 0; i < pagemap.mmap_ranges.len; i++ {
		range := unsafe { &MmapRangeLocal(pagemap.mmap_ranges[i]) }
		// A PROT_NONE range only reserves addresses: allocators keep metadata
		// arenas that way, and the program break's arena is one.
		if unsafe { range == nil } || range.prot == prot_none {
			continue
		}
		if range.global != unsafe { nil }
			&& range.global.pte_extra & (memory.pte_uncached | memory.pte_device) != 0 {
			continue
		}
		mapped += range.length
		resident += pagemap.resident_share(range.base, range.base + range.length)
	}
	return ProcessMemory{
		mapped:   mapped
		resident: resident
	}
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

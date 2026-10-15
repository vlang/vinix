// SPDX-License-Identifier: GPL-2.0-or-later
module fs

import file
import memory.mmap
import proc

// The caller holds the process table lock, which protects the page-map pointer
// across exec/exit. Its try-lock protects the range list and the locals that
// keep their globals/handles alive. Do not wait or call mapping callbacks here.
fn unmount_mappings_in_use(owner &proc.Process, entry &Mount) bool {
	mut pagemap := owner.pagemap
	if pagemap == unsafe { nil } { return false }
	if !pagemap.l.test_and_acquire() { return true }
	defer { pagemap.l.release() }
	for pointer in pagemap.mmap_ranges {
		local := unsafe { &mmap.MmapRangeLocal(pointer) }
		if local == unsafe { nil } || local.flags & mmap.map_anonymous != 0 { continue }
		if file.mmap_mount(local.global) == voidptr(entry) { return true }
	}
	return false
}

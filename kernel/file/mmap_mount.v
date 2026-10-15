// SPDX-License-Identifier: GPL-2.0-or-later
module file

import lib
import memory.mmap

// Borrow only a mapping that retains a file.Handle with this module's exact
// callbacks. Other mmap callers may use a different opaque handle type. The
// caller holds the owning page-map lock and keeps its process/map alive.
pub fn mmap_mount(range &mmap.MmapRangeGlobal) voidptr {
	if range == unsafe { nil } || range.handle == unsafe { nil }
		|| voidptr(range.handle_ref) != voidptr(retain_mmap_handle)
		|| voidptr(range.handle_unref) != voidptr(release_mmap_handle) {
		return unsafe { nil }
	}
	handle := unsafe { &Handle(range.handle) }
	return lib.mount_context_top(&handle.mount)
}

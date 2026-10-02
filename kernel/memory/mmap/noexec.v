// SPDX-License-Identifier: GPL-2.0-or-later
module mmap

import memory

// A mapping made through noexec may not gain execute permission later, even
// after a split, fork or mremap. Validate the entire request before changing it.
fn no_exec_overlap_unlocked(pagemap &memory.Pagemap, base u64, length u64) bool {
	if length == 0 || base > u64(-1) - length { return false }
	end := base + length
	mut local := range_floor(pagemap, base)
	if local == unsafe { nil } { local = range_lower_bound(pagemap, base) }
	for local != unsafe { nil } {
		if local.base >= end { break }
		if local.global.no_exec && base < local.base + local.length { return true }
		if local.base == u64(-1) { break }
		local = range_lower_bound(pagemap, local.base + 1)
	}
	return false
}

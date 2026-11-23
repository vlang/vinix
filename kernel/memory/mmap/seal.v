// SPDX-License-Identifier: GPL-2.0-or-later
module mmap

import errno
import lib
import memory
import proc

// Cut off the upper portion without acquiring another backing-object
// reference. The existing split helper publishes both pieces under its
// range-list lock.
fn split_seal_boundary_unlocked(mut pagemap memory.Pagemap, boundary u64) ? {
	local, _, _ := addr2range(pagemap, boundary) or { return }
	if local.base == boundary || local.sealed { return }
	split_upper_range_unlocked(mut pagemap, local, boundary)?
}

fn seal_unlocked(mut pagemap memory.Pagemap, base u64, end u64) u64 {
	// Validate the entire request before touching metadata, including the
	// portions of Vinix's brk arena that Linux would leave unmapped.
	mut cursor := base
	for cursor < end {
		local, _, _ := addr2range(pagemap, cursor) or { return errno.enomem }
		next := min_u64(end, local.base + local.length)
		if local.flags & map_brk_reservation != 0 && (cursor < pagemap.brk_base
			|| next > lib.align_up(pagemap.brk_current, page_size)) {
			return errno.enomem
		}
		cursor = next
	}

	// Only the outer boundaries can need metadata. Publish the seals after
	// both splits have succeeded so allocation failure leaves no new seals.
	split_seal_boundary_unlocked(mut pagemap, end) or { return errno.get() }
	split_seal_boundary_unlocked(mut pagemap, base) or { return errno.get() }
	cursor = base
	for cursor < end {
		mut local, _, _ := addr2range(pagemap, cursor) or { return errno.enomem }
		local.sealed = true
		cursor = local.base + local.length
	}
	return 0
}

pub fn syscall_mseal(_ voidptr, address u64, size u64, flags u64) (u64, u64) {
	mut base := address
	$if arm64 {
		base &= u64(0x00ffffffffffffff)
	}
	if flags != 0 || base % page_size != 0 { return errno.err, errno.einval }
	length := lib.align_up(size, page_size)
	if length < size || base > u64(-1) - length { return errno.err, errno.einval }
	if length == 0 { return 0, 0 }
	end := base + length
	if end > memory.user_address_limit() { return errno.err, errno.enomem }

	mut pagemap := proc.current_thread().process.pagemap
	begin_mapping_update(mut pagemap) or { return errno.err, errno.get() }
	defer { end_mapping_update(mut pagemap) }
	pagemap.l.acquire()
	error := seal_unlocked(mut pagemap, base, end)
	pagemap.l.release()
	if error != 0 { return errno.err, error }
	return 0, 0
}

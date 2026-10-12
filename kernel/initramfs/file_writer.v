// SPDX-License-Identifier: GPL-2.0-or-later
module initramfs

import resource

// A regular resource may complete only part of a write. VJFS bounds each
// transaction to 1 MiB, so installation must advance both the archive buffer
// and the destination offset until every byte has been stored.
fn write_archive_file(mut destination resource.Resource, buffer voidptr, size u64) bool {
	mut done := u64(0)
	for done < size {
		remaining := size - done
		written := destination.write(unsafe { nil }, voidptr(u64(buffer) + done), done,
			remaining) or { return false }
		// No progress must fail rather than spin forever. An impossible count
		// must not advance past the end of the archive entry.
		if written <= 0 || u64(written) > remaining {
			return false
		}
		done += u64(written)
	}
	return true
}

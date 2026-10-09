// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

module mmap

import errno
import lib
import memory
import proc

// OpenBSD's mimmutable(2) makes mapping metadata one-way: once a mapped span is
// immutable its protection or mapping cannot be changed. Unmapped holes are
// deliberately ignored and do not acquire any latent state.
fn immutable_overlap_unlocked(pagemap &memory.Pagemap, base u64, length u64) bool {
	if length == 0 || base > u64(-1) - length {
		return false
	}
	end := base + length
	mut range_local := range_floor(pagemap, base)
	if range_local == unsafe { nil } {
		range_local = range_lower_bound(pagemap, base)
	}
	for range_local != unsafe { nil } {
		if range_local.base >= end {
			break
		}
		range_end := range_local.base + range_local.length
		if range_local.immutable && base < range_end && end > range_local.base {
			return true
		}
		if range_local.base == u64(-1) {
			break
		}
		range_local = range_lower_bound(pagemap, range_local.base + 1)
	}
	return false
}

fn next_mapped_base_unlocked(pagemap &memory.Pagemap, address u64, end u64) u64 {
	if address == u64(-1) {
		return end
	}
	next := range_lower_bound(pagemap, address + 1)
	if next != unsafe { nil } && next.base < end {
		return next.base
	}
	return end
}

pub fn mimmutable(mut pagemap memory.Pagemap, address u64, _length u64) ? {
	if _length == 0 {
		return
	}
	base := lib.align_down(address, page_size)
	prefix := address - base
	if _length > u64(-1) - prefix {
		errno.set(errno.einval)
		return none
	}
	requested := _length + prefix
	length := lib.align_up(requested, page_size)
	if length < requested || base >= memory.user_address_limit()
		|| length > memory.user_address_limit() - base {
		errno.set(errno.einval)
		return none
	}

	pagemap.l.acquire()
	defer { pagemap.l.release() }
	mimmutable_unlocked(mut pagemap, base, length)?
}

fn mimmutable_unlocked(mut pagemap memory.Pagemap, base u64, length u64) ? {
	end := base + length
	mut current := base
	for current < end {
		mut local_range, _, _ := addr2range(pagemap, current) or {
			// Holes do not become sticky, but a sparse request may cover terabytes.
			// Jump to the next mapping instead of walking each absent page.
			current = next_mapped_base_unlocked(pagemap, current, end)
			continue
		}
		local_end := local_range.base + local_range.length
		snip_begin := current
		snip_end := if local_end < end { local_end } else { end }
		if local_range.immutable {
			current = snip_end
			continue
		}

		snip_size := snip_end - snip_begin

		if snip_begin > local_range.base && snip_end < local_end {
			mut postsplit_range := new_local_range(MmapRangeLocal{
				pagemap: local_range.pagemap
				base: snip_end
				length: local_end - snip_end
				offset: local_range.offset + i64(snip_end - local_range.base)
				prot: local_range.prot
				flags: local_range.flags
				cow: local_range.cow
				immutable: local_range.immutable
				dont_fork: local_range.dont_fork
				wipe_on_fork: local_range.wipe_on_fork
				global: local_range.global
			})?
			split_off_unlocked(mut pagemap, local_range, postsplit_range)
		}

		if snip_size == local_range.length {
			local_range.immutable = true
		} else {
			mut immutable_range := new_local_range(MmapRangeLocal{
				pagemap: local_range.pagemap
				base: snip_begin
				length: snip_size
				offset: local_range.offset + i64(snip_begin - local_range.base)
				prot: local_range.prot
				flags: local_range.flags
				cow: local_range.cow
				immutable: true
				dont_fork: local_range.dont_fork
				wipe_on_fork: local_range.wipe_on_fork
				global: local_range.global
			})?
			split_off_unlocked(mut pagemap, local_range, immutable_range)
		}
		current = snip_end
	}
}

// For ELF's already validated, page-aligned LOAD spans, after the last
// fallible loader operation. mmap_file_segment leaves each final mapping
// piece within an original LOAD span; it does not coalesce adjacent ranges.
// Freeze whole final RX ranges only: writable replacements on overlapping
// segment pages remain mutable. This never allocates, splits, or fails.
pub fn mimmutable_executable(mut pagemap memory.Pagemap, base u64, length u64) {
	pagemap.l.acquire()
	defer { pagemap.l.release() }
	end := base + length
	mut local := range_lower_bound(pagemap, base)
	for local != unsafe { nil } && local.base < end {
		if local.length <= end - local.base && local.prot & prot_exec != 0
			&& local.prot & prot_write == 0 {
			local.immutable = true
		}
		local = range_lower_bound(pagemap, local.base + 1)
	}
}

pub fn syscall_mimmutable(_ voidptr, addr voidptr, length u64) (u64, u64) {
	mut process := proc.current_thread().process
	mimmutable(mut process.pagemap, u64(addr), length) or {
		return errno.err, errno.get()
	}
	return 0, 0
}

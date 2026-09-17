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
	for ptr in pagemap.mmap_ranges {
		range_local := unsafe { &MmapRangeLocal(ptr) }
		if !range_local.immutable {
			continue
		}
		range_end := range_local.base + range_local.length
		if base < range_end && end > range_local.base {
			return true
		}
	}
	return false
}

fn next_mapped_base_unlocked(pagemap &memory.Pagemap, address u64, end u64) u64 {
	mut next := end
	for ptr in pagemap.mmap_ranges {
		range_local := unsafe { &MmapRangeLocal(ptr) }
		if range_local.base > address && range_local.base < next {
			next = range_local.base
		}
	}
	return next
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

		mut global_range := local_range.global
		snip_size := snip_end - snip_begin

		if snip_begin > local_range.base && snip_end < local_end {
			mut postsplit_range := &MmapRangeLocal{
				pagemap: local_range.pagemap
				base: snip_end
				length: local_end - snip_end
				offset: local_range.offset + i64(snip_end - local_range.base)
				prot: local_range.prot
				flags: local_range.flags
				cow: local_range.cow
				immutable: local_range.immutable
				global: local_range.global
			}
			global_range.locals << postsplit_range
			pagemap.mmap_ranges << postsplit_range
			local_range.length -= postsplit_range.length
		}

		if snip_size == local_range.length {
			local_range.immutable = true
		} else {
			new_offset := local_range.offset + i64(snip_begin - local_range.base)
			if snip_begin == local_range.base {
				local_range.offset += i64(snip_size)
				local_range.base = snip_end
			}
			local_range.length -= snip_size

			mut immutable_range := &MmapRangeLocal{
				pagemap: local_range.pagemap
				base: snip_begin
				length: snip_size
				offset: new_offset
				prot: local_range.prot
				flags: local_range.flags
				cow: local_range.cow
				immutable: true
				global: local_range.global
			}
			global_range.locals << immutable_range
			pagemap.mmap_ranges << immutable_range
		}
		current = snip_end
	}
}

pub fn syscall_mimmutable(_ voidptr, addr voidptr, length u64) (u64, u64) {
	mut process := proc.current_thread().process
	mimmutable(mut process.pagemap, u64(addr), length) or {
		return errno.err, errno.get()
	}
	return 0, 0
}

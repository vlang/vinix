// SPDX-License-Identifier: GPL-2.0-or-later
@[manualfree]
module memory

import errno
import lib

// V's aligned copies use the POSIX allocation ABI. Keep the ordinary heap
// ownership so its generated free calls can release these allocations too.
@[export: 'posix_memalign']
pub fn posix_memalign(result &voidptr, alignment u64, size u64) int {
	if alignment < sizeof(voidptr) || alignment & (alignment - 1) != 0 {
		return errno.einval
	}
	length := if size == 0 { u64(1) } else { size }
	mut ptr := unsafe { nil }
	if alignment <= slab_alignment {
		ptr = malloc_packed_fallible(length)
	} else if alignment <= page_size {
		ptr = big_alloc_inner(length, false)
	} else {
		if length > big_allocation_max_size() || higher_half & (alignment - 1) != 0 {
			return errno.enomem
		}
		pages := lib.div_roundup(length, page_size)
		alignment_pages := alignment / page_size
		if pages > u64(-1) - alignment_pages {
			return errno.enomem
		}
		// Leave one metadata page immediately before the aligned payload, as
		// big_free expects. Return the unused prefix before publishing it.
		raw := pmm_alloc_aligned_fallible(pages + alignment_pages, alignment_pages)
		if raw == unsafe { nil } {
			return errno.enomem
		}
		metadata_address := u64(raw) + alignment - page_size + higher_half
		pmm_free(raw, alignment_pages - 1)
		mut metadata := unsafe { &MallocMetadata(metadata_address) }
		update_big_metadata(mut metadata, pages, length)
		adjust_big_alloc_pages(i64(pages + 1))
		ptr = voidptr(metadata_address + page_size)
	}
	if ptr == unsafe { nil } {
		return errno.enomem
	}
	unsafe { *result = ptr }
	return 0
}

// SPDX-License-Identifier: GPL-2.0-or-later
module mmap

import errno
import lib
import memory
import pagecache
import resource
import stat

const madv_willneed = 3
const madv_cold = 20
const madv_collapse = 25
const cold_page_batch = 128

pub fn is_process_advice(advice int) bool {
	return advice in [madv_willneed, madv_cold, madv_pageout, madv_collapse]!
}

// The caller holds an inspection reference. As on Linux, holes are skipped
// so that the remaining mapped spans can still be advised before ENOMEM.
pub fn process_advise_range(mut pagemap memory.Pagemap, base u64, length u64, advice int) ? {
	if base % page_size != 0 || length > u64(-1) - (page_size - 1) {
		errno.set(errno.einval)
		return none
	}
	span := lib.align_up(length, page_size)
	if span > u64(-1) - base || (advice == madv_collapse && span != 0) {
		errno.set(errno.einval)
		return none
	}
	end := base + span
	mut cursor := base
	mut hole := false
	for cursor < end {
		pagemap.l.acquire()
		local, _, _ := addr2range(pagemap, cursor) or {
			hole = true
			cursor = next_mapped_start(pagemap, cursor, end)
			pagemap.l.release()
			continue
		}
		stop := min_u64(end, local.base + local.length)
		if advice != madv_willneed {
			if local.immutable {
				pagemap.l.release()
				errno.set(errno.eperm)
				return none
			}
			res := local.global.resource
			if local.flags & map_locked != 0 || (local.flags & map_anonymous == 0
				&& (res == unsafe { nil } || !stat.isreg(res.stat.mode))) {
				pagemap.l.release()
				errno.set(errno.einval)
				return none
			}
		}
		match advice {
			madv_cold {
				for _ in 0 .. cold_page_batch {
					page := pagemap.next_present(cursor, stop)
					if page == stop {
						cursor = stop
						break
					}
					pagemap.age_page_unlocked(page)
					cursor = page + page_size
				}
				pagemap.l.release()
			}
			madv_pageout {
				pagemap.l.release()
				// Skip resident aliases and frames still owned by a fork shadow.
				pageout_pager(pagemap, cursor, stop - cursor, true)
				cursor = stop
			}
			else {
				if local.flags & map_anonymous == 0 {
					offset := u64(local.offset) + cursor - local.base
					source := range_page_source(local, cursor)
					pagemap.l.release()
					prefetch_file_source(source, offset, stop - cursor)
				} else {
					pagemap.l.release()
				}
				prefetch_pager_span(mut pagemap, cursor, stop)
				cursor = stop
			}
		}
	}
	if hole {
		errno.set(errno.enomem)
		return none
	}
}

fn prefetch_file_source(source RangePageSource, offset u64, length u64) {
	defer { source.close() }
	if source.direct { return }
	mut res := source.resource
	resource.advise_resource(mut res, source.handle, offset, length, pagecache.willneed) or {}
}

// Prefetch stored pages only. An untouched anonymous reservation should
// stay sparse even when the whole span is marked WILLNEED.
fn prefetch_pager_span(mut pagemap memory.Pagemap, start u64, end u64) {
	mut cursor := start
	for cursor < end {
		pagemap.l.acquire()
		local, _, _ := addr2range(pagemap, cursor) or {
			cursor = next_mapped_start(pagemap, cursor, end)
			pagemap.l.release()
			continue
		}
		stop := min_u64(end, local.base + local.length)
		key := shadow_address(local, cursor)
		mut global := local.global
		global.shadow_pagemap.l.acquire()
		stored := paged_lower(global.paged_pages, key)
		page := if stored != unsafe { nil } && stored.page - key < stop - cursor {
			cursor + (stored.page - key)
		} else {
			stop
		}
		global.shadow_pagemap.l.release()
		if page == stop {
			pagemap.l.release()
			cursor = stop
			continue
		}
		source := range_page_source(local, page)
		pagemap.l.release()
		if source.backing != unsafe { nil } {
			fill_range_page(mut pagemap, source, page, source.file_page) or {}
		} else {
			source.close()
		}
		cursor = page + page_size
	}
}

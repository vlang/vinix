// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The allocator's map, frame by frame.
//
// Everything else that asks the allocator for memory takes whichever pages it
// gives. Hibernation is the exception in both directions. To save the machine
// it has to know of every page of usable memory whether somebody holds it;
// and to bring a saved machine back it has to put each page into the very
// frame it came from, so it asks for frames by number.
@[manualfree]
module memory

import lib

// Whether the allocator has handed out frame `page`, or never had it: a frame
// past the end of usable memory counts as taken. No lock is held; exact only
// for a caller that has stopped everything else that allocates.
pub fn pmm_frame_taken(page u64) bool {
	return page >= pmm_avl_page_count || lib.bittest(pmm_bitmap, page)
}

// Take frame `page` out of the free pages. False when it is not free. What
// is in it is left as it is.
pub fn pmm_claim_frame(page u64) bool {
	if page == 0 || page >= pmm_avl_page_count {
		return false
	}
	pmm_lock.acquire()
	defer {
		pmm_lock.release()
	}
	if lib.bittest(pmm_bitmap, page) {
		return false
	}
	lib.bitset(pmm_bitmap, page)
	unsafe {
		(&u32(pmm_refcounts))[page] = 1
	}
	charge_node_pages(page, 1)
	free_pages--
	return true
}

// Usable frames handed out, and free.
pub fn pmm_frames_used() u64 {
	pmm_lock.acquire()
	defer {
		pmm_lock.release()
	}
	return pmm_total_pages - free_pages
}

pub fn pmm_frames_free() u64 {
	pmm_lock.acquire()
	defer {
		pmm_lock.release()
	}
	return free_pages
}

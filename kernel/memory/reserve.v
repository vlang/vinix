@[has_globals]
module memory

import katomic

// Running out of memory has to cost whoever is using it, not the machine.
// The kernel's own allocations -- page tables, slab pages, kernel stacks --
// cannot fail, so two amounts of free memory are kept back from everything
// that can. Both are pressure watermarks, so /proc/vmpressure and these agree:
//
//  - A file's data leaves the high watermark. tmpfs, which keeps its files in
//    memory, answers ENOSPC to a write that would go below it, and a full
//    RAM-backed root still has room to run programs in, the ones that make
//    room on it included.
//  - A process' own pages leave the critical watermark. A process that needs
//    a page it cannot have gets one killed for it, the largest; see
//    userland/oom.v.
//
// Before there was either, writing a large file to the RAM root took free
// memory down to nothing, and whatever the kernel allocated next -- starting
// a program was enough -- stopped the machine with "Out of memory after
// reclaim".

// How many pages are given back at a time, beyond the ones asked for, when an
// allocation finds the reserve short: one reclaim then serves the next few
// hundred allocations rather than one.
const reserve_reclaim_batch = u64(256)

__global (
	// How many allocations for a process found no memory; see exhaustions().
	user_exhaustions   = u64(0)
	exhaustion_handler fn (bool) bool
	reserve_pass       fn (u64) bool
	reclaimable_hint   fn () u64
)

pub fn user_reserve_pages() u64 {
	return pressure_watermarks(total_bytes()).critical / page_size
}

pub fn file_reserve_pages() u64 {
	return pressure_watermarks(total_bytes()).high / page_size
}

// Whether `count` pages can be handed out with `reserve` left free, once what
// can be regenerated has been given back. Read without the allocator's lock:
// several CPUs may each take a page past the line, which a reserve can bear.
//
// What a cache holds clean counts as free even when it could not be had this
// instant. A reclaimer another CPU is in the middle of gives this one nothing,
// and a cache whose lock is taken, as it is across a read from the disk, is
// passed over: on a system whose root is a disk, where the cache fills
// whatever memory is left, that would have files refused room and processes
// killed with most of memory there for the taking.
fn room_above(reserve u64, count u64) bool {
	wanted := reserve + count
	free := free_pages
	if free >= wanted {
		return true
	}
	reclaim_pages(wanted - free + reserve_reclaim_batch)
	if free_pages >= wanted {
		return true
	}
	return free_pages + reclaimable_pages() >= wanted
}

// Registered by the page cache: how many pages it could give back.
pub fn register_reclaimable(hint fn () u64) {
	reclaimable_hint = hint
}

fn reclaimable_pages() u64 {
	if reclaimable_hint == unsafe { nil } {
		return 0
	}
	return reclaimable_hint()
}

// Whether a file may take `count` more pages for its data.
pub fn file_room(count u64) bool {
	return room_above(file_reserve_pages(), count)
}

// Whether a process may take `count` more pages of its own. One the kernel
// itself is waiting on may take them from the reserve; see
// register_reserve_pass().
pub fn user_room(count u64) bool {
	if room_above(user_reserve_pages(), count) {
		return true
	}
	if reserve_pass != unsafe { nil } && reserve_pass(count) {
		return true
	}
	note_exhaustion()
	return false
}

// Whether a process asking for a page now would be given one, after giving
// back what can be regenerated. Unlike user_room() a refusal here is not
// counted: it is what recovery asks while it waits.
pub fn user_memory_available() bool {
	return room_above(user_reserve_pages(), 1)
}

// The bytes a file can still grow by, for statfs(2).
pub fn file_room_bytes() u64 {
	reserve := file_reserve_pages()
	free := free_pages
	return if free > reserve { (free - reserve) * page_size } else { u64(0) }
}

pub fn note_exhaustion() {
	katomic.inc(mut &user_exhaustions)
}

// A count that moves each time memory for a process cannot be had. A fault
// handler samples it before resolving a fault: a fault that fails with the
// count moved failed for lack of memory, not for a bad address.
pub fn exhaustions() u64 {
	return katomic.load(&user_exhaustions)
}

// Zeroed pages for a file's data, or nil when they would cut into what
// programs need to run.
pub fn pmm_alloc_file(count u64) voidptr {
	if !file_room(count) {
		return unsafe { nil }
	}
	return pmm_alloc_fallible(count)
}

// Pages for a process' own memory, or nil when only the kernel's reserve is
// left; the caller's fault or syscall then goes through
// recover_from_exhaustion().
pub fn pmm_alloc_user_nozero(count u64) voidptr {
	if !user_room(count) {
		return unsafe { nil }
	}
	ret := pmm_alloc_nozero_fallible(count)
	if ret == unsafe { nil } {
		note_exhaustion()
	}
	return ret
}

pub fn pmm_alloc_user(count u64) voidptr {
	if !user_room(count) {
		return unsafe { nil }
	}
	ret := pmm_alloc_fallible(count)
	if ret == unsafe { nil } {
		note_exhaustion()
	}
	return ret
}

// Registered by userland, which can tell which process to kill and can wait
// for it to go: this module cannot import it.
pub fn register_exhaustion_handler(handler fn (bool) bool) {
	exhaustion_handler = handler
}

// Registered by userland too: whether the calling thread has been let into
// the reserve for this many pages, which uses that much of its pass up. A
// fault the kernel takes on a process' page, copying to or from it with a
// lock held or for a process that is being killed, can neither wait for
// memory nor fail: before there was a reserve it took the page, and it still
// does.
pub fn register_reserve_pass(pass fn (u64) bool) {
	reserve_pass = pass
}

// Whether there is a page to be had at all, the reserve included.
pub fn any_free() bool {
	return free_pages != 0
}

// Whether the upper half of the reserve is still there. That half is what a
// syscall that cannot wait for memory may take its pages from; the lower one
// is the kernel's alone.
pub fn reserve_half_left() bool {
	return free_pages > user_reserve_pages() / 2
}

// A page for the calling thread's process could not be had. Has a process
// killed for the memory and waits for it; true when the caller should try
// again, false when it is the one being killed or nothing is left to kill.
// `sleepable` is for a caller that knows it holds no lock and may sleep; one
// that cannot tell says false, and is not made to wait unless that is plain.
pub fn recover_from_exhaustion(sleepable bool) bool {
	if exhaustion_handler == unsafe { nil } {
		return false
	}
	return exhaustion_handler(sleepable)
}

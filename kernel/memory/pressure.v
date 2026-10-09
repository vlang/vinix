@[has_globals]
module memory

import katomic
import klock
import event
import event.eventstruct

pub struct PressureSnapshot {
pub:
	level               int
	generation          u64
	free_bytes          u64
	total_bytes         u64
	watermarks          PressureWatermarks
	reclaim_runs        u64
	reclaimed_pages     u64
	allocation_failures u64
}

__global (
	pressure_lock                klock.Lock
	pressure_level               = int(0)
	pressure_generation          = u64(0)
	pressure_reclaim_runs         = u64(0)
	pressure_reclaimed_pages      = u64(0)
	pressure_allocation_failures  = u64(0)
	pressure_observer            fn (u64) = unsafe { nil }
	anonymous_pageout            fn (u64, bool) u64 = unsafe { nil }
	file_pageout                 fn (u64, bool) u64 = unsafe { nil }
	anonymous_pageout_inflight   u32
	anonymous_pageout_completed eventstruct.Event
)

pub fn register_anonymous_pageout(handler fn (u64, bool) u64) {
	pressure_lock.acquire()
	anonymous_pageout = handler
	pressure_lock.release()
}

pub fn register_file_pageout(handler fn (u64, bool) u64) {
	pressure_lock.acquire()
	file_pageout = handler
	pressure_lock.release()
}

// Disk I/O belongs only in a sleepable context, never in the PMM's generic
// reclaim callbacks (which can be entered under arbitrary kernel locks).
// This entry point coordinates mapped-file and anonymous pageout together.
pub fn pageout_anonymous(wanted u64) u64 {
	return pageout_anonymous_inner(wanted, false)
}

// Foreground allocation recovery can wait for an already-running reclaimer.
// A busy worker is not evidence that user memory cannot be reclaimed.
pub fn pageout_anonymous_wait(wanted u64) u64 {
	return pageout_anonymous_inner(wanted, true)
}

fn pageout_anonymous_inner(wanted u64, wait bool) u64 {
	pressure_lock.acquire()
	handler := anonymous_pageout
	file_handler := file_pageout
	pressure_lock.release()
	if handler == unsafe { nil } && file_handler == unsafe { nil } { return 0 }
	for {
		generation := event.generation(mut anonymous_pageout_completed)
		if katomic.cas(mut &anonymous_pageout_inflight, u32(0), u32(1)) { break }
		if !wait || !event.may_wait() { return 0 }
		event.await_one_from_generation_masked(mut anonymous_pageout_completed, generation) or { return 0 }
		if user_memory_available() { return 0 }
	}
	defer {
		katomic.store(mut &anonymous_pageout_inflight, u32(0))
		event.trigger(mut anonymous_pageout_completed, true)
	}
	mut reclaimed := u64(0)
	if file_handler != unsafe { nil } { reclaimed = file_handler(wanted, wait) }
	if reclaimed < wanted && handler != unsafe { nil } { reclaimed += handler(wanted - reclaimed, wait) }
	mut previous := katomic.load(&pressure_reclaimed_pages)
	for !katomic.cas(mut &pressure_reclaimed_pages, previous, previous + reclaimed) {
		previous = katomic.load(&pressure_reclaimed_pages)
	}
	return reclaimed
}

// The notification bridge is registered at procfs construction, before the
// maintenance worker starts. Callbacks only run from that worker, never while
// a physical allocator or filesystem lock is held.
pub fn register_pressure_observer(observer fn (u64)) {
	pressure_lock.acquire()
	pressure_observer = observer
	pressure_lock.release()
}

pub fn pressure_snapshot() PressureSnapshot {
	free := free_bytes()
	total := total_bytes()
	pressure_lock.acquire()
	level := pressure_level
	generation := pressure_generation
	pressure_lock.release()
	return PressureSnapshot{
		level: level
		generation: generation
		free_bytes: free
		total_bytes: total
		watermarks: pressure_watermarks(total)
		reclaim_runs: katomic.load(&pressure_reclaim_runs)
		reclaimed_pages: katomic.load(&pressure_reclaimed_pages)
		allocation_failures: katomic.load(&pressure_allocation_failures)
	}
}

// Called once a second from a sleepable kernel worker. Bound each pass to
// 4 MiB so one tick cannot discard an entire useful cache or monopolise a
// cache lock. Existing clean-LRU reclaimers skip dirty/writeback pages; the
// regular five-second writeback pass makes successfully written pages eligible
// for subsequent passes. Remaining pressure evicts unlocked anonymous pages.
pub fn pressure_maintenance() {
	free := free_bytes()
	marks := pressure_watermarks(total_bytes())
	pressure_lock.acquire()
	level := pressure_next_level(pressure_level, free, marks)
	observer := pressure_observer
	mut changed := false
	if level != pressure_level {
		pressure_level = level
		pressure_generation++
		changed = true
	}
	generation := pressure_generation
	pressure_lock.release()
	if changed && observer != unsafe { nil } { observer(generation) }
	if level == 0 || free >= marks.high { return }
	mut wanted := (marks.high - free + page_size - 1) / page_size
	budget := u64(4 * 1024 * 1024) / page_size
	if wanted > budget { wanted = budget }
	reclaimed := reclaim_pages(wanted)
	if reclaimed < wanted { pageout_anonymous(wanted - reclaimed) }
}

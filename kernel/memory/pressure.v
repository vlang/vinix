@[has_globals]
module memory

import katomic
import klock

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
)

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
// for subsequent passes. Anonymous and live file mappings are not evicted.
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
	reclaim_pages(wanted)
}

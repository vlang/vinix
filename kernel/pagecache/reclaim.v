@[has_globals]
module pagecache

import klock
import katomic
import memory

const max_registered_caches = 16

__global (
	registered_caches      [max_registered_caches]&Cache
	registered_caches_len  = int(0)
	registered_caches_lock klock.Lock
	reclaimer_registered   = bool(false)
)

// Filesystems register long-lived shared caches once their backing store has
// been validated. Cache objects are mount-lifetime allocations in Vinix, so a
// registry entry cannot outlive its target.
//
// The writeback callback and its context are recorded here as well. Without
// them a registered cache could only be reclaimed, never flushed: sync(2) and
// reboot(2) have no descriptor to recover them from, and dirty pages reached
// the device only when the LRU happened to evict them.
pub fn register_cache(cache &Cache, context voidptr, store IO) bool {
	if context == unsafe { nil } {
		return false
	}
	registered_caches_lock.acquire()
	defer { registered_caches_lock.release() }
	for i := 0; i < registered_caches_len; i++ {
		if voidptr(registered_caches[i]) == voidptr(cache) {
			return true
		}
	}
	if registered_caches_len == max_registered_caches {
		return false
	}
	if !reclaimer_registered {
		if !memory.register_reclaimer(reclaim_caches) {
			return false
		}
		reclaimer_registered = true
	}
	mut target := unsafe { cache }
	target.writeback_context = context
	target.writeback = store
	registered_caches[registered_caches_len] = target
	katomic.store(mut &registered_caches_len, registered_caches_len + 1)
	return true
}

// resident_bytes is the file data every registered cache holds, for meminfo's
// Cached line.
pub fn resident_bytes() u64 {
	registered_caches_lock.acquire()
	count := katomic.load(&registered_caches_len)
	registered_caches_lock.release()
	mut total := u64(0)
	for i := 0; i < count; i++ {
		mut cache := registered_caches[i]
		cache.l.acquire()
		total += u64(cache.resident) * page_bytes
		cache.l.release()
	}
	return total
}

// Write every registered cache's dirty pages back to its backing store. This
// is what sync(2), syncfs(2) and the shutdown path need: a filesystem whose
// pages are only flushed on eviction otherwise loses every small write when
// the machine restarts. Flushing continues past a failing cache so one broken
// device cannot strand the others, and the failure is still reported.
pub fn sync_all() bool {
	registered_caches_lock.acquire()
	count := katomic.load(&registered_caches_len)
	registered_caches_lock.release()

	mut ok := true
	for i := 0; i < count; i++ {
		mut cache := registered_caches[i]
		if cache.writeback_context == unsafe { nil } {
			continue
		}
		cache.sync(cache.writeback_context, cache.writeback) or { ok = false }
	}
	return ok
}

fn reclaim_caches(wanted u64) u64 {
	mut reclaimed := u64(0)
	// PMM budgets are physical pages; cache pages are always 4 KiB. Four
	// cached pages share a 16 KiB backing frame on arm64, so reclaiming only
	// `wanted` cache entries there under-reclaims by a factor of four.
	ratio := page_size / page_bytes
	cache_budget := if wanted > u64(-1) / ratio { u64(-1) } else { wanted * ratio }
	count := katomic.load(&registered_caches_len)
	for i := 0; i < count && reclaimed < cache_budget; i++ {
		mut cache := registered_caches[i]
		reclaimed += cache.reclaim_clean(cache_budget - reclaimed)
	}
	return reclaimed / (page_size / page_bytes)
}

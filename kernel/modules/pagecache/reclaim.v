@[has_globals]
module pagecache

import klock
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
pub fn register_cache(cache &Cache) bool {
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
	registered_caches[registered_caches_len] = unsafe { cache }
	registered_caches_len++
	return true
}

fn reclaim_caches(wanted u64) u64 {
	mut reclaimed := u64(0)
	count := registered_caches_len
	for i := 0; i < count && reclaimed < wanted; i++ {
		mut cache := registered_caches[i]
		reclaimed += cache.reclaim_clean(wanted - reclaimed)
	}
	return reclaimed
}

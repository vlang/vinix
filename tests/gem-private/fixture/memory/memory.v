@[has_globals]
module memory

pub const pte_uncached = u64(1) << 4

const fixture_page = u64(16384)
const pool_slots = u64(512)

struct Allocation {
	address u64
	raw voidptr = unsafe { nil }
}

__global allocations = [16]Allocation{}
__global count = 0
__global reject = false
// Nonzero: contiguous requests longer than this many pages fail, as on a
// fragmented PMM.
__global contiguous_limit = u64(0)
// Single pages come from a pool that skips every third slot, so consecutive
// allocations form physically adjacent pairs with a gap between them.
__global pool_raw = unsafe { nil }
__global pool_base = u64(0)
__global pool_next = u64(0)
__global pool_live = 0
// Nonnegative: that many more single-page allocations succeed, then they fail.
__global single_successes = -1
__global uncached_pages = u64(0)

pub fn live() int { return count + pool_live }
pub fn fail(failed bool) { reject = failed }
pub fn limit_contiguous(pages u64) { contiguous_limit = pages }
pub fn fail_single_pages_after(successes int) { single_successes = successes }
pub fn uncached() u64 { return uncached_pages }
pub fn pool_page(index u64) u64 { return pool_base + (index + index / 2) * fixture_page }
pub fn user_room(_pages u64) bool { return !reject }

pub fn malloc_packed_fallible(size u64) voidptr { return unsafe { C.malloc(size) } }
pub fn free(storage voidptr) { unsafe { C.free(storage) } }

pub fn set_ram_direct_map_uncached(_phys u64, size u64, uncached bool) bool {
	pages := size / fixture_page
	if uncached {
		uncached_pages += pages
	} else {
		assert uncached_pages >= pages, 'restored more uncached pages than were set'
		uncached_pages -= pages
	}
	return true
}

pub fn pmm_alloc_aligned_fallible(pages u64, alignment u64) voidptr {
	if reject || (contiguous_limit != 0 && pages > contiguous_limit) { return unsafe { nil } }
	boundary := alignment * fixture_page
	raw := unsafe { C.malloc(pages * fixture_page + boundary) }
	if raw == unsafe { nil } { return raw }
	address := (u64(raw) + boundary - 1) & ~(boundary - 1)
	for index in 0 .. 16 {
		if allocations[index].address == 0 {
			allocations[index] = Allocation{ address: address, raw: raw }
			count++
			return voidptr(address)
		}
	}
	panic('fixture allocation table exhausted')
}

pub fn pmm_alloc_fallible(pages u64) voidptr {
	assert pages == 1, 'scattered GEM backing takes single pages'
	if reject || single_successes == 0 { return unsafe { nil } }
	if single_successes > 0 { single_successes-- }
	if pool_raw == unsafe { nil } {
		pool_raw = unsafe { C.malloc((pool_slots + 1) * fixture_page) }
		assert pool_raw != unsafe { nil }
		pool_base = (u64(pool_raw) + fixture_page - 1) & ~(fixture_page - 1)
	}
	address := pool_page(pool_next)
	assert address + fixture_page <= pool_base + pool_slots * fixture_page, 'fixture page pool exhausted'
	pool_next++
	pool_live++
	unsafe { C.memset(voidptr(address), 0, fixture_page) }
	return voidptr(address)
}

pub fn pmm_free(address voidptr, pages u64) {
	if pool_raw != unsafe { nil } && u64(address) >= pool_base
		&& u64(address) < pool_base + pool_slots * fixture_page {
		assert pages == 1
		pool_live--
		return
	}
	for index in 0 .. 16 {
		if allocations[index].address == u64(address) {
			unsafe { C.free(allocations[index].raw) }
			allocations[index] = Allocation{}
			count--
			return
		}
	}
	panic('unknown backing allocation')
}

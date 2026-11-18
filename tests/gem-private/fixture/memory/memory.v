@[has_globals]
module memory

pub const pte_uncached = u64(1) << 4

struct Allocation {
	address u64
	raw voidptr = unsafe { nil }
}

__global allocations = [16]Allocation{}
__global count = 0
__global reject = false

pub fn live() int { return count }
pub fn fail(failed bool) { reject = failed }
pub fn user_room(_pages u64) bool { return !reject }

pub fn malloc_packed_fallible(size u64) voidptr { return unsafe { C.malloc(size) } }
pub fn free(storage voidptr) { unsafe { C.free(storage) } }

pub fn set_ram_direct_map_uncached(_phys u64, _size u64, _uncached bool) bool {
	panic('private GEM fixture uses cacheable backing')
}

pub fn pmm_alloc_aligned_fallible(pages u64, alignment u64) voidptr {
	if reject { return unsafe { nil } }
	boundary := alignment * 16384
	raw := unsafe { C.malloc(pages * 16384 + boundary) }
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

pub fn pmm_free(address voidptr, _pages u64) {
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

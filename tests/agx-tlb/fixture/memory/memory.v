@[has_globals]
module memory

struct Allocation {
	aligned u64
	raw     voidptr
}

__global allocations = []Allocation{}
__global remaining = int(-1)

pub fn fail_after(count int) { remaining = count }

pub fn pmm_alloc_aligned(pages u64, alignment u64) &u64 {
	if remaining == 0 { return unsafe { nil } }
	if remaining > 0 { remaining-- }
	boundary := alignment * 16384
	raw := unsafe { malloc(int(pages * 16384 + boundary)) }
	aligned := (u64(raw) + boundary - 1) & ~(boundary - 1)
	unsafe { C.memset(voidptr(aligned), 0, pages * 16384) }
	allocations << Allocation{ aligned: aligned, raw: raw }
	return unsafe { &u64(aligned) }
}

pub fn pmm_free(pointer voidptr, pages u64) {
	for index, allocation in allocations {
		if allocation.aligned == u64(pointer) {
			unsafe { free(allocation.raw) }
			allocations.delete(index)
			return
		}
	}
	assert false, 'free of unknown table page'
}

pub fn live_pages() int { return allocations.len }

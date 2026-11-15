@[has_globals]
module memory

pub const page_size = u64(4096)

struct Allocation {
	address u64
	raw voidptr = unsafe { nil }
	pages u64
}

__global backing = [32]Allocation{}
__global live = 0
__global attempts = 0
__global reject_next = false

pub fn active() int { return live }
pub fn calls() int { return attempts }
pub fn fail_next() { reject_next = true }

pub fn pmm_alloc_aligned_fallible(pages u64, alignment u64) voidptr {
	attempts++
	if reject_next { reject_next = false; return unsafe { nil } }
	assert pages > 0 && pages < 1024 && alignment == 4
	bytes := pages * page_size
	raw := unsafe { malloc(int(bytes + alignment * page_size)) }
	address := (u64(raw) + alignment * page_size - 1) & ~(alignment * page_size - 1)
	unsafe { C.memset(voidptr(address), 0, bytes) }
	for index in 0 .. 32 {
		if backing[index].address == 0 {
			backing[index] = Allocation{ address: address, raw: raw, pages: pages }
			live++
			return voidptr(address)
		}
	}
	panic('fixture backing table exhausted')
}

pub fn pmm_free(pointer voidptr, pages u64) {
	for index in 0 .. 32 {
		if backing[index].address == u64(pointer) && pointer != unsafe { nil } {
			assert backing[index].pages == pages
			unsafe { free(backing[index].raw) }
			backing[index] = Allocation{}
			live--
			return
		}
	}
	assert false, 'free of unknown physical backing'
}

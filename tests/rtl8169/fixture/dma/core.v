@[has_globals]
module dma

import devcore

pub struct Buffer {
pub:
	virt  u64
	bus   u64
	bytes u64
}

__global (
	pub live      int
	pub allocated int
	pub fail_at   int = -1
)

pub fn alloc_buffer(mut d devcore.Device, bytes u64) ?Buffer {
	assert d.pci.command & 4 == 0
	if allocated == fail_at { return none }
	allocated++
	addr := unsafe { malloc(int(bytes)) }
	live++
	return Buffer{u64(addr), u64(addr) + 0x100000, bytes}
}

pub fn free_buffer(mut d devcore.Device, b Buffer) {
	if b.virt != 0 {
		assert d.pci.command & 4 == 0
		unsafe { free(voidptr(b.virt)) }
		live--
	}
}

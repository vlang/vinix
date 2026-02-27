@[has_globals]
module memory

import lib
import limine
import klock

fn C.text_start()
fn C.text_end()
fn C.rodata_start()
fn C.rodata_end()
fn C.data_start()
fn C.data_end()

// Portable PTE flags. Callers use these consistently; arch-specific
// map_page implementations translate them into the real PTE format.
pub const pte_present = u64(1) << 0
pub const pte_writable = u64(1) << 1
pub const pte_user = u64(1) << 2
pub const pte_device = u64(1) << 3 // ARM64: use Device-nGnRnE memory type for MMIO
pub const pte_uncached = u64(1) << 4 // ARM64: use Normal Non-Cacheable for framebuffers
pub const pte_noexec = u64(1) << 63

__global (
	page_size       = u64(0x1000)
	kernel_pagemap  Pagemap
	vmm_initialised = bool(false)
)

pub struct Pagemap {
pub mut:
	l           klock.Lock
	top_level   &u64 = unsafe { nil }
	mmap_ranges []voidptr
}

fn C.get_kernel_end_addr() u64

@[_linker_section: '.requests']
@[cinit]
__global (
	volatile kaddr_req  = limine.LimineKernelAddressRequest{
		response: unsafe { nil }
	}
	volatile memmap_req = limine.LimineMemmapRequest{
		response: unsafe { nil }
	}
)

fn map_kernel_span(virt u64, phys u64, len u64, flags u64) {
	aligned_len := lib.align_up(len, page_size)

	print('vmm: Kernel: Mapping 0x${phys:x} to 0x${virt:x}, length: 0x${aligned_len:x}\n')

	for i := u64(0); i < aligned_len; i += page_size {
		kernel_pagemap.map_page(virt + i, phys + i, flags) or { panic('vmm init failure') }
	}
}

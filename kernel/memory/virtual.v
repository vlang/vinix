@[has_globals]
module memory

import lib
import limine
import klock
import event.eventstruct

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
pub const kernel_page_size = u64(0x1000)

// What of a range of an address space is resident, in bytes: all of it, the
// part fork left shared with another process until one of them writes it,
// and every page counted as its share, as resident_share() counts it.
pub struct Residency {
pub mut:
	resident u64
	shared   u64
	share    u64
}

pub __global (
	page_size        = u64(0x1000)
	kernel_pagemap   Pagemap
	vmm_initialised  = bool(false)
	cow_resolver     fn (&Pagemap, u64) bool
	page_in_resolver fn (&Pagemap, u64) bool
)

pub fn register_cow_resolver(resolver fn (&Pagemap, u64) bool) {
	cow_resolver = resolver
}

pub fn resolve_cow(pagemap &Pagemap, address u64) bool {
	if cow_resolver == unsafe { nil } {
		return false
	}
	return cow_resolver(pagemap, address)
}

// Registered by mmap, which knows what a mapping is backed by, as the COW
// resolver above is: this module cannot import it.
pub fn register_page_in_resolver(resolver fn (&Pagemap, u64) bool) {
	page_in_resolver = resolver
}

// Page in the page of a user mapping that holds `address`, as a fault on it
// would. True once the page is present, whoever put it there.
pub fn resolve_missing_page(pagemap &Pagemap, address u64) bool {
	if page_in_resolver == unsafe { nil } {
		return false
	}
	return page_in_resolver(pagemap, address)
}

pub struct Pagemap {
pub mut:
	l           klock.Lock
	top_level   &u64 = unsafe { nil }
	mmap_ranges []voidptr
	// Search tree for mmap ranges; its nodes are owned by mmap_ranges.
	mmap_root   voidptr
	// Being torn down: no CPU runs it any more, so pages come out of it with
	// no TLB maintenance each, and one flush follows (flush_tlb_everywhere).
	dying bool
	// Address-space inspection survives exec/exit detaching this map from
	// its process. The counter and final wake are protected by l.
	inspection_refs int
	inspection_drained eventstruct.Event
}

fn C.get_kernel_end_addr() u64

@[_linker_section: '.requests']
@[cinit]
__global (
	volatile kaddr_req = limine.LimineKernelAddressRequest{
		response: unsafe { nil }
	}
	volatile memmap_req = limine.LimineMemmapRequest{
		response: unsafe { nil }
	}
)

// The direct map covers every physical page, the kernel's own among them, and
// mapped them all writable: the kernel's text and read-only data were W^X at
// their own addresses and writable through their alias, so anything able to
// write kernel memory at a chosen address could patch the kernel's code. As
// OpenBSD and Linux keep them, the alias of both is read-only here, and not
// executable. `phys` and `len` cover text through rodata, which the linker
// scripts align to pages.
fn protect_kernel_image_alias(phys u64, len u64) {
	for i := u64(0); i < lib.align_up(len, kernel_page_size); i += kernel_page_size {
		kernel_pagemap.map_page(phys + i + higher_half, phys + i, pte_present | pte_noexec) or {
			panic('vmm init failure: kernel image alias')
		}
	}
	C.kprintf(c'vmm: kernel text and rodata read-only in the direct map (0x%llx +0x%llx)\n',
		phys, len)
}

fn map_kernel_span(virt u64, phys u64, len u64, flags u64) {
	aligned_len := lib.align_up(len, kernel_page_size)

	C.kprintf(c'vmm: Kernel: Mapping 0x%llx to 0x%llx, length: 0x%llx\n', u64(phys), u64(virt),
		u64(aligned_len))

	for i := u64(0); i < aligned_len; i += kernel_page_size {
		kernel_pagemap.map_page(virt + i, phys + i, flags) or { panic('vmm init failure') }
	}
}

@[has_globals]
module memory

import kbudget
import lib
import limine
import klock
import event.eventstruct
import katomic

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
pub const pte_execute_only = u64(1) << 5 // ARM64: EL0 instruction fetch without data access
pub const pte_file_tracked = u64(1) << 9
pub const pte_file_dirty = u64(1) << 10
pub const pte_noexec = u64(1) << 63
pub const kernel_page_size = u64(0x1000)

pub struct PageActivity {
pub mut:
	referenced bool
	dirty bool
}

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
	locked_bytes_resolver fn (&Pagemap) u64
	fault_resolution_guard u64
	native_fault_context_guard u64
)

type FaultResolutionGuard = fn () bool

// The architecture publishes this after every boot CPU has installed its
// native context, before runnable tasks/interrupts start. The callback is
// permanent and never called before the acknowledged setup of kernel GS.
pub fn register_native_fault_context_guard(guard fn () bool) {
	bits := u64(voidptr(guard))
	if bits == 0 || !katomic.cas(mut &native_fault_context_guard, u64(0), bits) {
		panic('native fault-context guard already installed or invalid')
	}
}

// The compatibility runtime installs this once during boot, before publishing
// its workers. This module cannot import its task/scheduler implementation.
pub fn register_fault_resolution_guard(guard fn () bool) {
	bits := u64(voidptr(guard))
	if bits == 0 || !katomic.cas(mut &fault_resolution_guard, u64(0), bits) {
		panic('fault-resolution guard already installed or invalid')
	}
}

pub fn fault_resolution_disabled() bool {
	native_bits := katomic.load(&native_fault_context_guard)
	if native_bits != 0 {
		native_guard := unsafe { FaultResolutionGuard(voidptr(native_bits)) }
		if native_guard() { return true }
	}
	bits := katomic.load(&fault_resolution_guard)
	if bits == 0 { return false }
	guard := unsafe { FaultResolutionGuard(voidptr(bits)) }
	return guard()
}

pub fn register_cow_resolver(resolver fn (&Pagemap, u64) bool) {
	cow_resolver = resolver
}

pub fn resolve_cow(pagemap &Pagemap, address u64) bool {
	if fault_resolution_disabled() || cow_resolver == unsafe { nil } {
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
	if fault_resolution_disabled() || page_in_resolver == unsafe { nil } {
		return false
	}
	return page_in_resolver(pagemap, address)
}

pub fn register_locked_bytes_resolver(resolver fn (&Pagemap) u64) {
	locked_bytes_resolver = resolver
}

pub fn locked_bytes(pagemap &Pagemap) u64 {
	if pagemap == unsafe { nil } || locked_bytes_resolver == unsafe { nil } { return 0 }
	return locked_bytes_resolver(pagemap)
}

pub struct Pagemap {
pub mut:
	kernel_owner kbudget.Owner
	kernel_charge kbudget.Charge
	l           klock.Lock
	// Process owners, including non-thread CLONE_VM children. Inspection pins
	// are separate: only the final process release may destroy this map.
	owners      u64 = 1
	// The program break belongs to the address space, not a process sharing it.
	brk_busy    bool
	brk_changed eventstruct.Event
	brk_base    u64
	brk_current u64
	// MCL_FUTURE belongs to the address space shared by CLONE_VM threads.
	lock_future bool
	// Resident user-address leaf mappings only; writers hold l, observers use atomics.
	track_residency bool
	resident_bytes u64
	peak_resident_bytes u64
	top_level   &u64 = unsafe { nil }
	mmap_ranges []voidptr
	// Search tree for mmap ranges; its nodes are owned by mmap_ranges.
	mmap_root   voidptr
	// Being torn down: no CPU runs it any more, retained translations were
	// invalidated before its pages/tables are returned to the allocator.
	dying bool
	// Address-space inspection survives exec/exit detaching this map from
	// its process. The counter and final wake are protected by l.
	inspection_refs int
	pageout_cursor u64
	inspection_drained eventstruct.Event
	// Exclusive ARM ASID or x86 PCID ownership until destruction. Zero uses
	// conservative flush-on-switch behavior when unavailable or exhausted.
	tlb_tag u16
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

// Called under pagemap.l, or while constructing an unpublished fork map,
// after a successful leaf descriptor update. Shadow
// backing maps do not track residency; kernel addresses are excluded. A
// PROT_NONE page still consumes resident memory until actually unmapped.
pub fn (mut pagemap Pagemap) account_resident(virt u64, was_present bool, is_present bool) {
	if !pagemap.track_residency || virt >= user_address_limit() || was_present == is_present { return }
	old := pagemap.resident_bytes
	if is_present {
		next := old + page_size
		katomic.store(mut &pagemap.resident_bytes, next)
		if next > pagemap.peak_resident_bytes {
			katomic.store(mut &pagemap.peak_resident_bytes, next)
		}
	} else if old >= page_size {
		katomic.store(mut &pagemap.resident_bytes, old - page_size)
	}
}

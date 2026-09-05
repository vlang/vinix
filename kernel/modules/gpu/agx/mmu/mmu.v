@[has_globals]
module mmu

// Apple GPU UAT (Unified Address Translation) context management.
//
// The GPU firmware owns the hardware context switch. The application
// processor supplies two TTBRs per context in a reserved 64-entry table and
// coordinates changes through the reserved uPPL handoff structure. UAT page
// tables use a 16 KiB granule and are implemented in pgtable.v.

import gpu.agx.pgtable
import gpu.agx.alloc as gpu_alloc
import klock
import katomic
import aarch64.cpu
import memory

pub const uat_num_contexts = 64
pub const uat_kernel_flush_slot = 64
pub const uat_user_va_start = u64(0x4000)
pub const uat_user_va_end = u64(1) << 39
pub const uat_unknown_page = uat_user_va_end - 2 * pgtable.uat_pgsz
pub const uat_kernel_va_start = u64(0xffffffa000000000)
pub const uat_kernel_va_end = u64(0xffffffb000000000)

const ttbr_valid = u64(1)
const ttbr_asid_shift = u32(48)
const ppl_magic = u64(0x4b1d000000000002)
const handoff_size = u64(0x648)

pub enum UatHandoffAbi {
	v12_3
	g17_26_5
}

@[packed]
pub struct UatFlushInfo {
pub mut:
	state u64
	addr  u64
	size  u64
}

// Byte-exact firmware ABI. In particular, the two lock flags are bytes, the
// flush array has an extra kernel slot (index 64), and unk3 is at 0x640.
@[packed]
pub struct UatHandoff {
pub mut:
	magic_ap u64
	magic_fw u64
	lock_ap  u8
	lock_fw  u8
	pad_12   [2]u8
	turn     u32
	cur_slot u32
	pad_1c   u32
	flush    [uat_num_contexts + 1]UatFlushInfo
	unk2     u8
	pad_639  [7]u8
	unk3     u64
}

@[packed]
struct SlotTtbs {
mut:
	ttb0 u64
	ttb1 u64
}

pub struct UatContext {
pub mut:
	id             u32
	pgtable        &pgtable.UatPgtable = unsafe { nil }
	active         bool
	lock           klock.Lock
	vm_id          u32
	dummy_phys     u64
	kernel_start   u64
	kernel_end     u64
	driver_gpu     gpu_alloc.HeapAllocator
	driver_private gpu_alloc.HeapAllocator
mut:
	driver_buffers []&UatBuffer
}

// Driver-owned backing mapped into a user UAT context. These objects occupy
// Mesa's reserved kernel VA window, so userspace GEM_BIND requests cannot
// alias them. The queue/job owner must retain the object until firmware has
// retired every command that references it.
pub struct UatBuffer {
pub:
	va      u64
	phys    u64
	size    u64
	private bool
mut:
	released bool
}

pub struct UatManager {
pub mut:
	contexts             [uat_num_contexts]&UatContext
	kernel_lower_pgtable &pgtable.UatPgtable = unsafe { nil }
	kernel_pgtable       &pgtable.UatPgtable = unsafe { nil }
	handoff              &UatHandoff = unsafe { nil }
	ttbs                 &SlotTtbs = unsafe { nil }
	ttbs_base            u64
	handoff_base         u64
	pagetables_base      u64
	ias                  u32
	oas                  u32
	map_kernel_to_user   bool
	handoff_abi          UatHandoffAbi
	handoff_initialized  bool
	lock                 klock.Lock
}

__global (
	uat_mgr = unsafe { &UatManager(nil) }
)

// Attach to bootloader-reserved UAT structures. Nothing is written here;
// handoff initialization must happen only after the GPU RTKit firmware is up.
pub fn new_manager(ttbs_base u64, handoff_base u64, pagetables_base u64, ias u32, oas u32,
	map_kernel_to_user bool, handoff_abi UatHandoffAbi) ?&UatManager {
	if ttbs_base & pgtable.uat_pg_mask != 0 || handoff_base & pgtable.uat_pg_mask != 0
		|| pagetables_base & pgtable.uat_pg_mask != 0 {
		C.printf(c'uat mmu: reserved regions are not 16 KiB aligned\n')
		return none
	}
	if sizeof(UatHandoff) != handoff_size || sizeof(SlotTtbs) != 16 {
		C.printf(c'uat mmu: firmware structure layout mismatch\n')
		return none
	}

	lower := pgtable.new_pgtable(ias, oas) or {
		C.printf(c'uat mmu: failed to allocate lower kernel page table\n')
		return none
	}
	upper := pgtable.new_pgtable_with_root(pagetables_base, ias, oas) or {
		pgtable.destroy(lower)
		C.printf(c'uat mmu: invalid reserved TTBR1 page table\n')
		return none
	}

	mgr := &UatManager{
		kernel_lower_pgtable: lower
		kernel_pgtable: upper
		handoff: unsafe { &UatHandoff(handoff_base + higher_half) }
		ttbs: unsafe { &SlotTtbs(ttbs_base + higher_half) }
		ttbs_base: ttbs_base
		handoff_base: handoff_base
		pagetables_base: pagetables_base
		ias: ias
		oas: oas
		map_kernel_to_user: map_kernel_to_user
		handoff_abi: handoff_abi
	}
	uat_mgr = mgr

	C.printf(c'uat mmu: attached IAS=%u OAS=%u TTBs=0x%llx handoff=0x%llx TTBR1=0x%llx\n', ias, oas, ttbs_base, handoff_base, pagetables_base)
	return mgr
}

// Initialize the uPPL handoff exactly as the G17 host driver does. Unlike the
// v12.3 protocol this does not wait for firmware to mirror the magic. Offset
// 0x638 instead records whether the pre-existing firmware word differed.
fn (mut mgr UatManager) initialize_g17_handoff() {
	unsafe {
		mut h := mgr.handoff
		h.magic_ap = ppl_magic
		h.lock_ap = 0
		h.lock_fw = 0
		h.turn = 0
		h.cur_slot = u32(-1)
		h.unk3 = 0
		if h.magic_fw != ppl_magic {
			h.unk2 = 1
		}
		for i := 0; i <= uat_num_contexts; i++ {
			h.flush[i].state = 0
			h.flush[i].addr = 0
			h.flush[i].size = 0
		}
	}
	cpu.dsb_sy()
}

fn shared_store8(mut target &u8, value u8) {
	unsafe {
		*target = value
	}
	cpu.dmb_sy()
}

fn shared_load8(target &u8) u8 {
	cpu.dmb_sy()
	return unsafe { *target }
}

// Dekker lock shared with the GPU firmware. Barriers around byte accesses are
// required: widening either flag to u32 would overwrite the peer's byte.
pub fn handoff_lock(h &UatHandoff) {
	if h == unsafe { nil } {
		return
	}
	unsafe {
		mut hp := h
		shared_store8(mut &hp.lock_ap, 1)
	}
	for shared_load8(&h.lock_fw) != 0 {
		if katomic.load(&h.turn) != 0 {
			unsafe {
				mut hp := h
				shared_store8(mut &hp.lock_ap, 0)
			}
			for katomic.load(&h.turn) != 0 {
				cpu.isb()
			}
			unsafe {
				mut hp := h
				shared_store8(mut &hp.lock_ap, 1)
			}
		}
	}
	cpu.dmb_sy()
}

pub fn handoff_unlock(h &UatHandoff) {
	if h == unsafe { nil } {
		return
	}
	unsafe {
		mut hp := h
		katomic.store(mut &hp.turn, u32(1))
		shared_store8(mut &hp.lock_ap, 0)
	}
	cpu.sev()
}

// Complete the uPPL magic exchange and publish the initial context roots.
// The firmware must already be running when this is called.
pub fn (mut mgr UatManager) initialize_handoff() bool {
	if mgr.handoff_initialized {
		return true
	}
	if mgr.handoff == unsafe { nil } || mgr.ttbs == unsafe { nil } {
		return false
	}
	if mgr.handoff_abi == .g17_26_5 {
		mgr.initialize_g17_handoff()
		mgr.publish_initial_context_roots()
		mgr.handoff_initialized = true
		return true
	}
	unsafe {
		mut h := mgr.handoff
		katomic.store(mut &h.magic_ap, ppl_magic)
		katomic.store(mut &h.cur_slot, u32(0))
		katomic.store(mut &h.unk3, u64(0))
	}
	cpu.dsb_sy()

	// Drop the lock periodically so firmware can finish its side of init.
	mut ready := false
	for _ in 0 .. 1000 {
		handoff_lock(mgr.handoff)
		ready = katomic.load(&mgr.handoff.magic_fw) == ppl_magic
		handoff_unlock(mgr.handoff)
		if ready {
			break
		}
		for _ in 0 .. 10000 {
			cpu.isb()
		}
	}
	if !ready {
		C.printf(c'uat mmu: firmware handoff magic timed out\n')
		return false
	}

	for i := 0; i <= uat_num_contexts; i++ {
		unsafe {
			mut h := mgr.handoff
			katomic.store(mut &h.flush[i].state, u64(0))
			katomic.store(mut &h.flush[i].addr, u64(0))
			katomic.store(mut &h.flush[i].size, u64(0))
		}
	}
	cpu.dsb_sy()

	mgr.publish_initial_context_roots()
	mgr.handoff_initialized = true
	return true
}

fn (mut mgr UatManager) publish_initial_context_roots() {
	handoff_lock(mgr.handoff)
	unsafe {
		mut slots := mgr.ttbs
		slots[0].ttb0 = mgr.kernel_lower_pgtable.l1_phys | ttbr_valid
		slots[0].ttb1 = mgr.kernel_pgtable.l1_phys | ttbr_valid
		for i := 1; i < uat_num_contexts; i++ {
			slots[i].ttb0 = 0
			slots[i].ttb1 = 0
		}
	}
	cpu.dsb_sy()
	handoff_unlock(mgr.handoff)
}

pub fn (mut mgr UatManager) create_context(kernel_start u64, kernel_end u64) ?&UatContext {
	if kernel_start < uat_user_va_start || kernel_start >= kernel_end
		|| kernel_end > uat_unknown_page || kernel_start & pgtable.uat_pg_mask != 0
		|| kernel_end & pgtable.uat_pg_mask != 0 {
		return none
	}
	mgr.lock.acquire()
	defer {
		mgr.lock.release()
	}
	for i := u32(1); i < uat_num_contexts; i++ {
		if mgr.contexts[i] == unsafe { nil } {
			kernel_half_size := ((kernel_end - kernel_start) >> 1) & ~pgtable.uat_pg_mask
			kernel_midpoint := kernel_start + kernel_half_size
			if kernel_half_size == 0 || kernel_midpoint >= kernel_end {
				return none
			}
			mut pt := pgtable.new_pgtable(mgr.ias, mgr.oas) or { return none }
			dummy_phys := u64(memory.pmm_alloc_aligned_fallible(4, 4))
			if dummy_phys == 0 {
				pgtable.destroy(pt)
				return none
			}
			if !pt.map(uat_unknown_page, dummy_phys, pgtable.uat_pgsz, pgtable.gpu_prot_gpu_shared_rw) {
				memory.pmm_free(voidptr(dummy_phys), 4)
				pgtable.destroy(pt)
				return none
			}
			ctx := &UatContext{
				id: i
				pgtable: pt
				active: true
				vm_id: i
				dummy_phys: dummy_phys
				kernel_start: kernel_start
				kernel_end: kernel_end
				driver_gpu: gpu_alloc.new_heap('uat-user-gpu', kernel_start, kernel_midpoint)
				driver_private: gpu_alloc.new_heap('uat-user-private', kernel_midpoint, kernel_end)
			}
			mgr.contexts[i] = ctx
			return ctx
		}
	}
	return none
}

pub fn (mut mgr UatManager) destroy_context(ctx &UatContext) {
	if ctx == unsafe { nil } || ctx.id == 0 || ctx.id >= uat_num_contexts {
		return
	}
	mgr.lock.acquire()
	defer {
		mgr.lock.release()
	}
	mgr.unbind_context(ctx)
	mut owned := unsafe { ctx }
	owned.release_all_driver_buffers()
	owned.active = false
	if owned.pgtable != unsafe { nil } {
		pgtable.destroy(owned.pgtable)
	}
	if owned.dummy_phys != 0 {
		memory.pmm_free(voidptr(owned.dummy_phys), 4)
		owned.dummy_phys = 0
	}
	mgr.contexts[ctx.id] = unsafe { nil }
}

// Allocate physically contiguous, CPU-visible memory in the half of Mesa's
// reserved VM window matching the requested coherency domain. GPU-shared
// buffers are coherent and GPU-only; private buffers are cached and visible
// to both the GPU and firmware. Publishing a new mapping to running firmware
// still requires the caller to issue a UAT flush before queue submission.
pub fn (mut ctx UatContext) alloc_driver_buffer(size u64, private bool) ?&UatBuffer {
	if size == 0 || size > u64(-1) - pgtable.uat_pg_mask || ctx.pgtable == unsafe { nil } {
		return none
	}
	aligned_size := (size + pgtable.uat_pg_mask) & ~pgtable.uat_pg_mask
	pages := aligned_size / u64(4096)

	ctx.lock.acquire()
	defer {
		ctx.lock.release()
	}
	if !ctx.active {
		return none
	}

	phys := u64(memory.pmm_alloc_aligned_fallible(pages, 4))
	if phys == 0 {
		return none
	}
	unsafe {
		C.memset(voidptr(phys + higher_half), 0, aligned_size)
	}

	va := if private {
		ctx.driver_private.alloc(aligned_size, pgtable.uat_pgsz) or {
			memory.pmm_free(voidptr(phys), pages)
			return none
		}
	} else {
		ctx.driver_gpu.alloc(aligned_size, pgtable.uat_pgsz) or {
			memory.pmm_free(voidptr(phys), pages)
			return none
		}
	}
	protection := if private {
		pgtable.gpu_prot_fw_gpu_cached_rw
	} else {
		pgtable.gpu_prot_gpu_shared_rw
	}
	mut pt := unsafe { ctx.pgtable }
	if !pt.map(va, phys, aligned_size, protection) {
		if private {
			ctx.driver_private.release(va)
			ctx.driver_private.gc()
		} else {
			ctx.driver_gpu.release(va)
			ctx.driver_gpu.gc()
		}
		memory.pmm_free(voidptr(phys), pages)
		return none
	}

	buffer := &UatBuffer{
		va: va
		phys: phys
		size: aligned_size
		private: private
	}
	ctx.driver_buffers << buffer
	return buffer
}

fn (mut ctx UatContext) release_driver_buffer_locked(buffer &UatBuffer) {
	if buffer == unsafe { nil } {
		return
	}
	mut owned := unsafe { buffer }
	if owned.released {
		return
	}
	owned.released = true
	if ctx.pgtable != unsafe { nil } && owned.va != 0 && owned.size != 0 {
		mut pt := unsafe { ctx.pgtable }
		pt.unmap(owned.va, owned.size)
	}
	if owned.phys != 0 && owned.size != 0 {
		memory.pmm_free(voidptr(owned.phys), owned.size / u64(4096))
	}
	if owned.private {
		ctx.driver_private.release(owned.va)
	} else {
		ctx.driver_gpu.release(owned.va)
	}
}

pub fn (mut ctx UatContext) release_driver_buffer(buffer &UatBuffer) {
	ctx.lock.acquire()
	for index, candidate in ctx.driver_buffers {
		if voidptr(candidate) == voidptr(buffer) {
			ctx.release_driver_buffer_locked(candidate)
			ctx.driver_buffers.delete(index)
			break
		}
	}
	ctx.driver_gpu.gc()
	ctx.driver_private.gc()
	ctx.lock.release()
}

fn (mut ctx UatContext) release_all_driver_buffers() {
	ctx.lock.acquire()
	for index := ctx.driver_buffers.len - 1; index >= 0; index-- {
		ctx.release_driver_buffer_locked(ctx.driver_buffers[index])
	}
	ctx.driver_buffers.clear()
	ctx.driver_gpu.gc()
	ctx.driver_private.gc()
	ctx.lock.release()
}

pub fn (buffer &UatBuffer) cpu_address() voidptr {
	if buffer == unsafe { nil } || buffer.released || buffer.phys == 0 {
		return unsafe { nil }
	}
	return voidptr(buffer.phys + higher_half)
}

pub fn (mgr &UatManager) bind_context(ctx &UatContext) {
	if !mgr.handoff_initialized || ctx == unsafe { nil } || ctx.pgtable == unsafe { nil }
		|| ctx.id >= uat_num_contexts {
		return
	}
	asid := u64(ctx.id) << ttbr_asid_shift
	handoff_lock(mgr.handoff)
	unsafe {
		mut slots := mgr.ttbs
		slots[ctx.id].ttb0 = ctx.pgtable.l1_phys | asid | ttbr_valid
		slots[ctx.id].ttb1 = if mgr.map_kernel_to_user {
			mgr.kernel_pgtable.l1_phys | asid | ttbr_valid
		} else {
			u64(0)
		}
	}
	cpu.dsb_sy()
	handoff_unlock(mgr.handoff)
}

pub fn (mgr &UatManager) unbind_context(ctx &UatContext) {
	if !mgr.handoff_initialized || ctx == unsafe { nil } || ctx.id >= uat_num_contexts {
		return
	}
	handoff_lock(mgr.handoff)
	unsafe {
		mut slots := mgr.ttbs
		slots[ctx.id].ttb0 = 0
		slots[ctx.id].ttb1 = 0
	}
	cpu.dsb_sy()
	handoff_unlock(mgr.handoff)
}

// Map a driver-owned allocation into context zero. Lower addresses use TTBR0;
// canonical high addresses use the reserved firmware-compatible TTBR1 root.
pub fn (mgr &UatManager) map_kernel(iova u64, phys u64, size u64, prot u64) bool {
	if iova < (u64(1) << mgr.ias) {
		mut pt := unsafe { mgr.kernel_lower_pgtable }
		return pt.map(iova, phys, size, prot)
	}
	mut pt := unsafe { mgr.kernel_pgtable }
	return pt.map(iova, phys, size, prot)
}

// Remove a driver-owned context-zero mapping. This is primarily used to
// unwind a partially constructed firmware MMIO aperture before MSG_INIT.
pub fn (mgr &UatManager) unmap_kernel(iova u64, size u64) {
	if iova < (u64(1) << mgr.ias) {
		mut pt := unsafe { mgr.kernel_lower_pgtable }
		pt.unmap(iova, size)
		return
	}
	mut pt := unsafe { mgr.kernel_pgtable }
	pt.unmap(iova, size)
}

// Prepare one firmware cache-flush slot. The caller must enqueue the matching
// 0x14-byte FwCtl message and ring endpoint 0x21 before completing it.
pub fn (mgr &UatManager) begin_flush(slot u32, addr u64, size u64) bool {
	if !mgr.handoff_initialized || slot > uat_kernel_flush_slot || size == 0 {
		return false
	}
	info := &mgr.handoff.flush[slot]
	if katomic.load(&info.state) != 0 {
		return false
	}
	unsafe {
		mut entry := info
		katomic.store(mut &entry.addr, addr)
		katomic.store(mut &entry.size, size)
		katomic.store(mut &entry.state, u64(1))
	}
	cpu.dsb_sy()
	return true
}

pub fn (mgr &UatManager) complete_flush(slot u32) bool {
	if !mgr.handoff_initialized || slot > uat_kernel_flush_slot {
		return false
	}
	info := &mgr.handoff.flush[slot]
	if katomic.load(&info.state) != 2 {
		return false
	}
	unsafe {
		mut entry := info
		katomic.store(mut &entry.state, u64(0))
	}
	return true
}

// Cancel a flush reservation only before its command has been published to
// firmware. Once the FWCTL ring owns the request, timing out is fatal and the
// slot must not be reused underneath a late firmware completion.
pub fn (mgr &UatManager) abort_unpublished_flush(slot u32) {
	if !mgr.handoff_initialized || slot > uat_kernel_flush_slot {
		return
	}
	info := &mgr.handoff.flush[slot]
	if katomic.load(&info.state) != 1 {
		return
	}
	unsafe {
		mut entry := info
		katomic.store(mut &entry.addr, u64(0))
		katomic.store(mut &entry.size, u64(0))
		katomic.store(mut &entry.state, u64(0))
	}
}

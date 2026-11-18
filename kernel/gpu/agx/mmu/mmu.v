@[has_globals]
module mmu

// Apple GPU UAT (Unified Address Translation) context management.
//
// The GPU firmware owns the hardware context switch. The application
// processor supplies two TTBRs per context in a reserved 64-entry table and
// coordinates changes through the reserved uPPL handoff structure. UAT page
// tables use a 16 KiB granule and are implemented in pgtable.v.

import gpu.agx.pgtable
import gpu.agx.admission
import gpu.agx.alloc as gpu_alloc
import gpu.agx.vm as agxvm
import klock
import katomic
import aarch64.cpu
import memory
import aarch64.timer
import event
import event.eventstruct

pub const uat_num_contexts = 64
pub const uat_kernel_flush_slot = 64
pub const uat_user_va_start = agxvm.user_start
pub const uat_user_va_end = agxvm.address_space_end
pub const uat_unknown_page = agxvm.user_end
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
pub:
	identity       u64 // non-reused VM-private BO reservation domain
pub mut:
	id             u32 // internal identity within the owning DRM file
	pgtable        &pgtable.UatPgtable = unsafe { nil }
	active         bool
	lock           klock.Lock
	vm_id          u32 // userspace name assigned by the owning DRM file
	detached       bool // protected by the owning file's lock
	inflight       u64 // atomic callback and aggregate submission pins
	binding_epoch  u64 // changes whenever this VM's firmware root is installed
	binding_gate   admission.Gate // serializes G13 submission binds across slot waits
	dummy_phys     u64
	kernel_start   u64
	kernel_end     u64
	driver_gpu     gpu_alloc.HeapAllocator
	driver_private gpu_alloc.HeapAllocator
mut:
	driver_buffers []&UatBuffer
}

__global context_identity_lock klock.Lock
__global context_identities = agxvm.IdentityPool{}

fn allocate_context_identity() ?u64 {
	context_identity_lock.acquire()
	defer { context_identity_lock.release() }
	return context_identities.allocate()
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
pub mut:
	// The mmu module makes a mapping uncached; the GPU driver does too.
	protection u64
mut:
	mapped              bool
	released            bool
	cache_flush_pending bool
}

pub struct UatManager {
pub mut:
	contexts             [uat_num_contexts]&UatContext // published user roots
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
mut:
	slot_users        [uat_num_contexts]u64
	slot_release      [uat_num_contexts]u64
	slot_release_clock u64
	slot_released      eventstruct.Event
}

__global (
	uat_mgr = unsafe { &UatManager(nil) }
)

// Attach to bootloader-reserved UAT structures. Handoff initialization must
// happen only after the GPU ASC CPU is running.
pub fn new_manager(ttbs_base u64, handoff_base u64, pagetables_base u64, ias u32, oas u32,
	map_kernel_to_user bool, handoff_abi UatHandoffAbi) ?&UatManager {
	if ttbs_base & pgtable.uat_pg_mask != 0 || handoff_base & pgtable.uat_pg_mask != 0
		|| pagetables_base & pgtable.uat_pg_mask != 0 {
		println('uat mmu: reserved regions are not 16 KiB aligned')
		return none
	}
	if sizeof(UatHandoff) != handoff_size || sizeof(SlotTtbs) != 16 {
		println('uat mmu: firmware structure layout mismatch')
		return none
	}

	lower := pgtable.new_pgtable(ias, oas) or {
		println('uat mmu: failed to allocate lower kernel page table')
		return none
	}
	mut upper := pgtable.new_pgtable_with_root(pagetables_base, ias, oas) or {
		pgtable.destroy(lower)
		println('uat mmu: invalid reserved TTBR1 page table')
		return none
	}
	if handoff_abi == .v12_3 {
		// G13 has a 39-bit TTBR1 root. Slot 2 spans the driver's canonical
		// kernel window and must point to a fresh 36-bit table, exactly as the
		// reference driver replaces kpt0()[2]. Other reserved entries belong
		// to firmware and are left untouched.
		if ias != 39 || !upper.clear_external_root_entry(2) {
			pgtable.destroy(lower)
			pgtable.destroy(upper)
			println('uat mmu: invalid G13 reserved TTBR1 geometry')
			return none
		}
		cpu.dsb_sy()
	}

	handoff_virt := memory.map_uncached(handoff_base, sizeof(UatHandoff))
	ttbs_virt := memory.map_uncached(ttbs_base, u64(uat_num_contexts) * sizeof(SlotTtbs))

	mgr := &UatManager{
		kernel_lower_pgtable: lower
		kernel_pgtable: upper
		handoff: unsafe { &UatHandoff(handoff_virt) }
		ttbs: unsafe { &SlotTtbs(ttbs_virt) }
		ttbs_base: ttbs_base
		handoff_base: handoff_base
		pagetables_base: pagetables_base
		ias: ias
		oas: oas
		map_kernel_to_user: map_kernel_to_user
		handoff_abi: handoff_abi
	}
	uat_mgr = mgr

	C.kprintf(c'uat mmu: attached IAS=%llu OAS=%llu TTBs=0x%llx handoff=0x%llx TTBR1=0x%llx\n',
		u64(ias), u64(oas), u64(ttbs_base), u64(handoff_base), u64(pagetables_base))
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
	// Match the reference driver's one-second deadline and 10 ms cadence.
	mut is_ready := false
	for _ in 0 .. 100 {
		handoff_lock(mgr.handoff)
		is_ready = katomic.load(&mgr.handoff.magic_fw) == ppl_magic
		handoff_unlock(mgr.handoff)
		if is_ready {
			break
		}
		timer.busywait_us(10000)
	}
	if !is_ready {
		println('uat mmu: firmware handoff magic timed out')
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
	// The global TTBR1 invalidation also removes stale bootloader entries
	// from every cleared user slot before the new graph is published.
	mgr.kernel_lower_pgtable.bind_tlb(0)
	mgr.kernel_pgtable.bind_tlb(0)
}

pub fn (mut mgr UatManager) create_context(kernel_start u64, kernel_end u64) ?&UatContext {
	window := agxvm.driver_window(kernel_start, kernel_end) or { return none }
	mgr.lock.acquire()
	defer {
		mgr.lock.release()
	}
	identity := allocate_context_identity() or { return none }
	mut pt := pgtable.new_pgtable(mgr.ias, mgr.oas) or { return none }
	dummy_pages := pgtable.uat_pgsz / memory.page_size
	dummy_phys := u64(memory.pmm_alloc_aligned_fallible(dummy_pages, dummy_pages))
	if dummy_phys == 0 {
		pgtable.destroy(pt)
		return none
	}
	if !pt.map(uat_unknown_page, dummy_phys, pgtable.uat_pgsz, pgtable.gpu_prot_gpu_shared_rw) {
		memory.pmm_free(voidptr(dummy_phys), dummy_pages)
		pgtable.destroy(pt)
		return none
	}
	mut ctx := &UatContext{
		identity: identity
		pgtable: pt
		active: true
		dummy_phys: dummy_phys
		kernel_start: window.start
		kernel_end: window.end
		driver_gpu: gpu_alloc.new_heap('uat-user-gpu', window.start, window.midpoint)
		driver_private: gpu_alloc.new_heap('uat-user-private', window.midpoint, window.end)
	} @[freed]
	// Nothing slices the list, so growing it can free the old buffer.
	ctx.driver_buffers.flags |= .noslices
	return ctx
}

// Caller holds the final file owner after mappings, queue backing and job
// captures have retired. The context pointer is consumed by this call.
pub fn (mut mgr UatManager) destroy_context(ctx &UatContext) {
	if ctx == unsafe { nil } {
		return
	}
	mgr.lock.acquire()
	defer {
		mgr.lock.release()
	}
	mgr.unbind_context(ctx)
	mut owned := unsafe { ctx }
	owned.release_all_driver_buffers()
	pgtable.destroy(owned.pgtable)
	if owned.dummy_phys != 0 {
		memory.pmm_free(voidptr(owned.dummy_phys), pgtable.uat_pgsz / memory.page_size)
	}
	unsafe { free(owned) }
}

// Allocate physically contiguous, CPU-visible memory in the half of Mesa's
// reserved VM window matching the requested coherency domain. GPU-shared
// buffers are coherent and GPU-only; private buffers are cached and visible
// to both the GPU and firmware. Publishing a new mapping to running firmware
// still requires the caller to issue a UAT flush before queue submission.
pub fn (mut ctx UatContext) alloc_driver_buffer(size u64, private bool) ?&UatBuffer {
	return ctx.alloc_driver_buffer_aligned(size, private, pgtable.uat_pgsz)
}

// Allocate a driver buffer at a stricter GPU-VA alignment. The G13 tiled
// buffer manager encodes addresses in 32 KiB units even though UAT pages are
// 16 KiB, so its per-VM allocator must preserve that larger alignment.
pub fn (mut ctx UatContext) alloc_driver_buffer_aligned(size u64, private bool,
	alignment u64) ?&UatBuffer {
	if size == 0 || size > u64(-1) - pgtable.uat_pg_mask || ctx.pgtable == unsafe { nil } {
		return none
	}
	if alignment < pgtable.uat_pgsz || alignment & (alignment - 1) != 0
		|| alignment & pgtable.uat_pg_mask != 0 {
		return none
	}
	// The per-VM allocators in Asahi have a 32 KiB minimum alignment, even
	// when the requested object and UAT page alignment are smaller.
	actual_alignment := if alignment < agxvm.driver_page_size { agxvm.driver_page_size } else { alignment }
	if size > ~u64(0) - (actual_alignment - 1) { return none }
	aligned_size := (size + actual_alignment - 1) & ~(actual_alignment - 1)
	pages := aligned_size / memory.page_size

	ctx.lock.acquire()
	defer {
		ctx.lock.release()
	}
	if !ctx.active {
		return none
	}

	phys := u64(memory.pmm_alloc_aligned_fallible(pages, pgtable.uat_pgsz / memory.page_size))
	if phys == 0 {
		return none
	}
	unsafe {
		C.memset(voidptr(phys + higher_half), 0, aligned_size)
	}

	va := if private {
		ctx.driver_private.alloc(aligned_size, actual_alignment) or {
			memory.pmm_free(voidptr(phys), pages)
			return none
		}
	} else {
		ctx.driver_gpu.alloc(aligned_size, actual_alignment) or {
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
	if !pt.map_new(va, phys, aligned_size, protection) {
		if private {
			ctx.driver_private.cancel_unpublished(va)
		} else {
			ctx.driver_gpu.cancel_unpublished(va)
		}
		memory.pmm_free(voidptr(phys), pages)
		return none
	}

	buffer := &UatBuffer{
		va: va
		phys: phys
		size: aligned_size
		private: private
		protection: protection
		mapped: true
		cache_flush_pending: pgtable.is_cached_noncoherent(protection)
	}
	ctx.driver_buffers << buffer
	return buffer
}

// Convert a cached driver allocation to the corresponding uncached mapping
// while its PTEs and physical backing are still valid. Reprotect completes
// the GPU TLBI before the caller checks whether an ASC cache flush is needed.
pub fn (mut ctx UatContext) reprotect_driver_buffer_uncached(buffer &UatBuffer) bool {
	if buffer == unsafe { nil } {
		return false
	}
	ctx.lock.acquire()
	defer {
		ctx.lock.release()
	}
	for candidate in ctx.driver_buffers {
		if voidptr(candidate) != voidptr(buffer) {
			continue
		}
		mut owned := unsafe { candidate }
		if owned.released {
			return false
		}
		if !owned.mapped || !pgtable.is_cached_noncoherent(owned.protection) {
			return true
		}
		if ctx.pgtable == unsafe { nil } || owned.va == 0 || owned.size == 0 {
			return false
		}
		protection := pgtable.as_uncached(owned.protection)
		mut pt := unsafe { ctx.pgtable }
		if !pt.reprotect(owned.va, owned.size, protection) {
			return false
		}
		owned.protection = protection
		return true
	}
	return false
}

// Keep the cache-flush obligation separate from the current PTE attributes.
// A failed, unpublished firmware request leaves an uncached PTE behind, but
// teardown must retry the flush before it is allowed to remove that PTE.
pub fn (buffer &UatBuffer) needs_cache_flush() bool {
	return buffer != unsafe { nil } && buffer.cache_flush_pending
}

pub fn (mut ctx UatContext) complete_driver_buffer_cache_flush(buffer &UatBuffer) bool {
	if buffer == unsafe { nil } {
		return false
	}
	ctx.lock.acquire()
	defer {
		ctx.lock.release()
	}
	for candidate in ctx.driver_buffers {
		if voidptr(candidate) != voidptr(buffer) {
			continue
		}
		mut owned := unsafe { candidate }
		if owned.released || !owned.mapped
			|| pgtable.is_cached_noncoherent(owned.protection) {
			return false
		}
		owned.cache_flush_pending = false
		return true
	}
	return false
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
	if owned.mapped && ctx.pgtable != unsafe { nil } && owned.va != 0 && owned.size != 0 {
		mut pt := unsafe { ctx.pgtable }
		pt.unmap(owned.va, owned.size)
		owned.mapped = false
	}
	if owned.phys != 0 && owned.size != 0 {
		memory.pmm_free(voidptr(owned.phys), owned.size / memory.page_size)
	}
	if owned.private {
		ctx.driver_private.release(owned.va)
	} else {
		ctx.driver_gpu.release(owned.va)
	}
}

// Remove the translation and complete the GPU TLBI before backing can be
// freed. The caller has already resolved any outstanding ASC cache flush.
pub fn (mut ctx UatContext) unmap_driver_buffer(buffer &UatBuffer) bool {
	if buffer == unsafe { nil } {
		return false
	}
	ctx.lock.acquire()
	defer {
		ctx.lock.release()
	}
	for candidate in ctx.driver_buffers {
		if voidptr(candidate) != voidptr(buffer) {
			continue
		}
		mut owned := unsafe { candidate }
		if owned.released {
			return false
		}
		if !owned.mapped {
			return true
		}
		if ctx.pgtable == unsafe { nil } || owned.va == 0 || owned.size == 0 {
			return false
		}
		mut pt := unsafe { ctx.pgtable }
		pt.unmap(owned.va, owned.size)
		owned.mapped = false
		return true
	}
	return false
}

pub fn (mut ctx UatContext) release_driver_buffer(buffer &UatBuffer) {
	ctx.lock.acquire()
	for index, candidate in ctx.driver_buffers {
		if voidptr(candidate) == voidptr(buffer) {
			ctx.release_driver_buffer_locked(candidate)
			ctx.driver_buffers.delete(index)
			// Jobs and render buffers relinquish each record here.
			unsafe { free(candidate) }
			break
		}
	}
	ctx.driver_gpu.gc()
	ctx.driver_private.gc()
	ctx.lock.release()
}

fn (mut ctx UatContext) release_all_driver_buffers() {
	ctx.lock.acquire()
	for buffer in ctx.driver_buffers {
		ctx.release_driver_buffer_locked(buffer)
		unsafe { free(buffer) }
	}
	ctx.driver_gpu.gc()
	ctx.driver_private.gc()
	unsafe {
		ctx.driver_buffers.free()
		ctx.driver_gpu.allocations.free()
		ctx.driver_private.allocations.free()
	}
	ctx.lock.release()
}

pub fn (buffer &UatBuffer) cpu_address() voidptr {
	if buffer == unsafe { nil } || buffer.released || buffer.phys == 0 {
		return unsafe { nil }
	}
	return voidptr(buffer.phys + higher_half)
}

// G13 callers serialize slot reads with publication and eviction.
pub fn (ctx &UatContext) is_bound() bool {
	return ctx.pgtable != unsafe { nil } && ctx.pgtable.tlb_bound
}

// Zero denotes a VM without a resident user root.
pub fn (ctx &UatContext) bound_slot() u32 {
	return if ctx.is_bound() { u32(ctx.pgtable.tlb_asid) } else { u32(0) }
}

// The GPU manager lock keeps the caller's VM resident across this snapshot
// and any ensuing FwCtl transaction. The handoff lock makes the ASC slot
// and published root one observation, like Asahi's cached-mapping teardown.
pub fn (mut mgr UatManager) g13_cache_flush_required(ctx &UatContext, slot u32) ?bool {
	mgr.lock.acquire()
	defer { mgr.lock.release() }
	if !mgr.handoff_initialized || mgr.handoff_abi != .v12_3 || mgr.handoff == unsafe { nil }
		|| mgr.ttbs == unsafe { nil } || slot == 0 || slot >= uat_num_contexts
		|| ctx == unsafe { nil } || ctx.bound_slot() != slot || voidptr(mgr.contexts[slot]) != voidptr(ctx) {
		return none
	}
	expected := ctx.pgtable.l1_phys | (u64(slot) << ttbr_asid_shift) | ttbr_valid
	handoff_lock(mgr.handoff)
	current := katomic.load(&mgr.handoff.cur_slot)
	published := unsafe { katomic.load(&mgr.ttbs[slot].ttb0) }
	handoff_unlock(mgr.handoff)
	return current == slot && published == expected
}

// Caller holds both MMU and handoff locks. The ASC flushes its translations
// and cache on a context switch. Keep its selected root until it switches
// away, and leave any incomplete firmware invalidation with its old owner.
fn (mgr &UatManager) select_context_slot_locked(leased bool) u32 {
	current := if leased { katomic.load(&mgr.handoff.cur_slot) } else { u32(0) }
	mut oldest := u32(0)
	mut oldest_age := u64(0)
	for slot := u32(1); slot < uat_num_contexts; slot++ {
		if !leased {
			if mgr.contexts[slot] == unsafe { nil } { return slot }
			continue
		}
		if slot == current || katomic.load(&mgr.handoff.flush[slot].state) != 0
			|| mgr.slot_users[slot] != 0 { continue }
		// Root removal preserves the allocator's release age. Only slots
		// that have never been used carry the initial release time.
		age := mgr.slot_release_clock - mgr.slot_release[slot]
		if oldest == 0 || age > oldest_age {
			oldest = slot
			oldest_age = age
		}
	}
	return oldest
}

// G13 acquires a user of the slot for each prepared job. G17 keeps an eager
// binding for the VM's lifetime. A zero return acquires no binding.
pub fn (mgr &UatManager) bind_context(ctx &UatContext) u32 {
	// The firmware handoff lock excludes the ASC. The manager lock also
	// excludes other AP threads, including a different VM's root removal.
	mut owner := unsafe { mgr }
	owner.lock.acquire()
	defer { owner.lock.release() }
	if !mgr.handoff_initialized || ctx == unsafe { nil } || !ctx.active || ctx.pgtable == unsafe { nil } {
		return 0
	}
	leased := mgr.handoff_abi == .v12_3
	bound := ctx.bound_slot()
	if bound != 0 {
		if leased {
			if mgr.slot_users[bound] == ~u64(0) { return 0 }
			owner.slot_users[bound]++
		}
		return bound
	}
	handoff_lock(mgr.handoff)
	slot := mgr.select_context_slot_locked(leased)
	if slot == 0 {
		handoff_unlock(mgr.handoff)
		return 0
	}
	replaced := mgr.contexts[slot]
	asid := u64(slot) << ttbr_asid_shift
	unsafe {
		mut slots := mgr.ttbs
		slots[slot].ttb0 = ctx.pgtable.l1_phys | asid | ttbr_valid
		slots[slot].ttb1 = if mgr.map_kernel_to_user {
			mgr.kernel_pgtable.l1_phys | asid | ttbr_valid
		} else {
			u64(0)
		}
	}
	cpu.dsb_sy()
	handoff_unlock(mgr.handoff)
	mut pt := unsafe { ctx.pgtable }
	if replaced != unsafe { nil } {
		mut previous := unsafe { replaced.pgtable }
		pt.replace_tlb(mut previous, u8(slot))
	} else {
		pt.bind_tlb(u8(slot))
	}
	mut installed := unsafe { ctx }
	installed.binding_epoch++
	owner.contexts[slot] = installed
	owner.slot_users[slot] = if leased { u64(1) } else { u64(0) }
	return slot
}

// A job retains its slot through command and buffer cleanup, including
// quarantine. The last release leaves the resident root available for reuse.
pub fn (mut mgr UatManager) release_g13_slot(ctx &UatContext, slot u32) {
	mgr.lock.acquire()
	defer { mgr.lock.release() }
	assert slot != 0 && slot < uat_num_contexts
	assert voidptr(mgr.contexts[slot]) == voidptr(ctx) && mgr.slot_users[slot] != 0
	mgr.slot_users[slot]--
	if mgr.slot_users[slot] == 0 {
		mgr.slot_release_clock++
		mgr.slot_release[slot] = mgr.slot_release_clock
		event.trigger_n(mut mgr.slot_released, 1)
	}
}

// Caller holds mgr.lock.
pub fn (mut mgr UatManager) unbind_context(ctx &UatContext) {
	if !mgr.handoff_initialized || ctx == unsafe { nil } { return }
	slot := ctx.bound_slot()
	if slot == 0 || slot >= uat_num_contexts {
		return
	}
	assert voidptr(mgr.contexts[slot]) == voidptr(ctx) && mgr.slot_users[slot] == 0
	handoff_lock(mgr.handoff)
	unsafe {
		mut slots := mgr.ttbs
		slots[slot].ttb0 = 0
		slots[slot].ttb1 = 0
	}
	cpu.dsb_sy()
	handoff_unlock(mgr.handoff)
	mut pt := unsafe { ctx.pgtable }
	pt.unbind_tlb()
	mgr.contexts[slot] = unsafe { nil }
	if mgr.handoff_abi == .v12_3 {
		event.trigger_n(mut mgr.slot_released, 1)
	}
}

// Map a driver-owned allocation into context zero. Lower addresses use TTBR0;
// canonical high addresses use the reserved firmware-compatible TTBR1 root.
pub fn (mgr &UatManager) map_kernel(iova u64, phys u64, size u64, prot u64) bool {
	return mgr.map_kernel_status(iova, phys, size, prot) == 0
}

pub fn (mgr &UatManager) map_kernel_status(iova u64, phys u64, size u64, prot u64) int {
	mut pt := unsafe {
		if iova < (u64(1) << mgr.ias) { mgr.kernel_lower_pgtable } else { mgr.kernel_pgtable }
	}
	if mgr.handoff_abi == .v12_3 {
		return pt.map_new_status(iova, phys, size, prot)
	}
	return if pt.map(iova, phys, size, prot) { 0 } else { -12 }
}

// Reprotect an existing context-zero mapping without changing its physical
// backing. This is the first phase of cache-safe teardown for private firmware
// allocations.
pub fn (mgr &UatManager) reprotect_kernel(iova u64, size u64, prot u64) bool {
	if iova < (u64(1) << mgr.ias) {
		mut pt := unsafe { mgr.kernel_lower_pgtable }
		return pt.reprotect(iova, size, prot)
	}
	mut pt := unsafe { mgr.kernel_pgtable }
	return pt.reprotect(iova, size, prot)
}

// Remove a driver-owned context-zero mapping. A published root completes
// its GPU TLBI before returning; an unpublished root has no translations.
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

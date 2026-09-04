@[has_globals]
module mmu

// Apple GPU UAT (Unified Address Translation) context management.
//
// The GPU firmware owns the hardware context switch. The application
// processor supplies two TTBRs per context in a reserved 64-entry table and
// coordinates changes through the reserved uPPL handoff structure. UAT page
// tables use a 16 KiB granule and are implemented in pgtable.v.

import gpu.agx.pgtable
import klock
import katomic
import aarch64.cpu

pub const uat_num_contexts = 64
pub const uat_kernel_flush_slot = 64
pub const uat_user_va_start = u64(0x4000)
pub const uat_user_va_end = u64(1) << 39
pub const uat_kernel_va_start = u64(0xffffffa000000000)
pub const uat_kernel_va_end = u64(0xffffffb000000000)

const ttbr_valid = u64(1)
const ttbr_asid_shift = u32(48)
const ppl_magic = u64(0x4b1d000000000002)
const handoff_size = u64(0x648)

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
	id      u32
	pgtable &pgtable.UatPgtable = unsafe { nil }
	active  bool
	lock    klock.Lock
	vm_id   u32
}

pub struct UatManager {
pub mut:
	contexts            [uat_num_contexts]&UatContext
	kernel_lower_pgtable &pgtable.UatPgtable = unsafe { nil }
	kernel_pgtable       &pgtable.UatPgtable = unsafe { nil }
	handoff              &UatHandoff         = unsafe { nil }
	ttbs                 &SlotTtbs           = unsafe { nil }
	ttbs_base            u64
	handoff_base         u64
	pagetables_base      u64
	ias                  u32
	oas                  u32
	map_kernel_to_user   bool
	handoff_initialized  bool
	lock                 klock.Lock
}

__global (
	uat_mgr = unsafe { &UatManager(nil) }
)

// Attach to bootloader-reserved UAT structures. Nothing is written here;
// handoff initialization must happen only after the GPU RTKit firmware is up.
pub fn new_manager(ttbs_base u64, handoff_base u64, pagetables_base u64, ias u32, oas u32,
	map_kernel_to_user bool) ?&UatManager {
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
		kernel_pgtable:       upper
		handoff:              unsafe { &UatHandoff(handoff_base + higher_half) }
		ttbs:                 unsafe { &SlotTtbs(ttbs_base + higher_half) }
		ttbs_base:            ttbs_base
		handoff_base:         handoff_base
		pagetables_base:      pagetables_base
		ias:                  ias
		oas:                  oas
		map_kernel_to_user:   map_kernel_to_user
	}
	uat_mgr = mgr

	C.printf(c'uat mmu: attached IAS=%u OAS=%u TTBs=0x%llx handoff=0x%llx TTBR1=0x%llx\n',
		ias, oas, ttbs_base, handoff_base, pagetables_base)
	return mgr
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
	mgr.handoff_initialized = true
	return true
}

pub fn (mut mgr UatManager) create_context() ?&UatContext {
	mgr.lock.acquire()
	defer {
		mgr.lock.release()
	}
	for i := u32(1); i < uat_num_contexts; i++ {
		if mgr.contexts[i] == unsafe { nil } {
			pt := pgtable.new_pgtable(mgr.ias, mgr.oas) or { return none }
			ctx := &UatContext{
				id:      i
				pgtable: pt
				active:  true
				vm_id:   i
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
	if ctx.pgtable != unsafe { nil } {
		pgtable.destroy(ctx.pgtable)
	}
	mgr.contexts[ctx.id] = unsafe { nil }
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

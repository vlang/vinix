@[has_globals]
module mmu

// Apple GPU UAT (Unified Address Translation) context management
// Manages 64 hardware VM contexts via the TTBAT (Translation Table Base
// Address Table). Each context has its own UatPgtable for GPU-side address
// translation. A shared kernel page table is mapped into every context.
//
// Firmware coordination uses a Peterson-style mutual-exclusion handoff
// region in shared memory. The AP (application processor) and FW each
// have a flag; the `turn` variable breaks ties.
//
// Translated from the Asahi Linux mmu.rs driver code.

import gpu.agx.pgtable
import memory
import klock
import katomic
import lib
import aarch64.cpu

// --- VA range constants ---

// User (per-context) VA range: pages start at 0x4000, up to 2^39
pub const uat_num_contexts = 64
pub const uat_user_va_start = u64(0x4000)
pub const uat_user_va_end = u64(1) << 39

// Kernel (shared / firmware) VA range
pub const uat_kernel_va_start = u64(0xffffffa000000000)
pub const uat_kernel_va_end = u64(0xffffffb000000000)

// TTBAT entry layout: each slot is 16 bytes (phys[63:0] + cfg[63:0])
const ttbat_slot_size = u64(16)

// Handoff flush state values
const handoff_flush_idle = u32(0)
const handoff_flush_pending = u32(1)
const handoff_flush_processing = u32(2)
const handoff_flush_done = u32(3)

// --- Handoff region (shared memory with GPU firmware) ---

// Peterson-style mutual exclusion between AP and firmware.
// Both sides set their flag and yield turn to the other; the one
// whose turn it is *not* gets to proceed.
@[packed]
pub struct UatHandoff {
pub mut:
	lock_ap     u32 // AP interest flag
	lock_fw     u32 // FW interest flag
	turn        u32 // Whose turn to wait (0 = AP waits, 1 = FW waits)
	cur_slot    u32 // Current slot being flushed
	flush_state u32 // Flush state machine
	pad         [3]u32
}

// --- VM context ---

pub struct UatContext {
pub mut:
	id      u32
	pgtable &pgtable.UatPgtable = unsafe { nil }
	active  bool
	lock    klock.Lock
	vm_id   u32 // Firmware-visible VM identifier
}

// --- UAT manager ---

pub struct UatManager {
pub mut:
	contexts       [uat_num_contexts]&UatContext
	kernel_pgtable &pgtable.UatPgtable = unsafe { nil }
	handoff        &UatHandoff         = unsafe { nil }
	ttbat_base     u64 // Physical / MMIO base of the TTBAT
	lock           klock.Lock
}

__global (
	uat_mgr = unsafe { &UatManager(nil) }
)

// Create and initialise the global UAT manager.
// `ttbat_base` is the physical address of the hardware TTBAT register block.
pub fn new_manager(ttbat_base u64) ?&UatManager {
	// Allocate the kernel (shared) page table
	kpt := pgtable.new_pgtable() or {
		C.printf(c'uat mmu: failed to allocate kernel page table\n')
		return none
	}

	// Allocate the handoff region (must be GPU-accessible shared memory)
	// One 4KB page is sufficient for the handoff structure.
	handoff_phys := memory.pmm_alloc(1)
	if handoff_phys == 0 {
		C.printf(c'uat mmu: failed to allocate handoff region\n')
		return none
	}
	handoff_ptr := unsafe { &UatHandoff(u64(handoff_phys) + higher_half) }

	// Zero-initialise handoff (pmm_alloc already zeroes, but be explicit)
	unsafe {
		C.memset(voidptr(handoff_ptr), 0, sizeof(UatHandoff))
	}

	mgr := &UatManager{
		kernel_pgtable: kpt
		handoff:        handoff_ptr
		ttbat_base:     ttbat_base
	}

	uat_mgr = mgr

	C.printf(c'uat mmu: initialised, %d VM contexts, ttbat @ 0x%llx\n', uat_num_contexts,
		ttbat_base)

	return mgr
}

// Allocate a free VM context. Returns a new UatContext with its own page table.
// Context 0 is reserved for the kernel.
pub fn (mut mgr UatManager) create_context() ?&UatContext {
	mgr.lock.acquire()
	defer {
		mgr.lock.release()
	}

	// Scan for a free slot (skip slot 0, reserved for kernel)
	for i := u32(1); i < uat_num_contexts; i++ {
		if mgr.contexts[i] == unsafe { nil } {
			pt := pgtable.new_pgtable() or { return none }

			ctx := &UatContext{
				id:      i
				pgtable: pt
				active:  true
				vm_id:   i
			}
			mgr.contexts[i] = ctx

			C.printf(c'uat mmu: created context %d\n', i)
			return ctx
		}
	}

	C.printf(c'uat mmu: no free VM contexts\n')
	return none
}

// Destroy a VM context: unbind from TTBAT, free page tables, release slot.
pub fn (mut mgr UatManager) destroy_context(ctx &UatContext) {
	if ctx == unsafe { nil } {
		return
	}

	id := ctx.id
	if id == 0 || id >= uat_num_contexts {
		return
	}

	mgr.lock.acquire()
	defer {
		mgr.lock.release()
	}

	// Unbind from hardware
	mgr.unbind_context(ctx)

	// Free page tables
	if ctx.pgtable != unsafe { nil } {
		pgtable.destroy(ctx.pgtable)
	}

	mgr.contexts[id] = unsafe { nil }

	C.printf(c'uat mmu: destroyed context %d\n', id)
}

// Write the page table root into the hardware TTBAT slot for this context.
// This makes the GPU firmware aware of the context's address space.
pub fn (mgr &UatManager) bind_context(ctx &UatContext) {
	if ctx == unsafe { nil } || ctx.pgtable == unsafe { nil } {
		return
	}

	slot := ctx.id
	if slot >= uat_num_contexts {
		return
	}

	root_phys := ctx.pgtable.l1_phys

	// Each TTBAT slot: [63:0] = TTBR value (physical address | attributes)
	slot_addr := mgr.ttbat_base + u64(slot) * ttbat_slot_size
	slot_virt := slot_addr + higher_half

	unsafe {
		// Write TTBR0 for this slot (physical base with valid indicator)
		mut ttbr_ptr := &u64(slot_virt)
		*ttbr_ptr = root_phys | 1 // Valid bit

		// Write TTBR1 / config word (kernel page table for shared mappings)
		mut cfg_ptr := &u64(slot_virt + 8)
		*cfg_ptr = mgr.kernel_pgtable.l1_phys | 1
	}

	// Ensure the write is visible before firmware reads it
	cpu.dsb_sy()

	C.printf(c'uat mmu: bound context %d, root=0x%llx\n', slot, root_phys)
}

// Clear the TTBAT entry, detaching this context from the hardware.
pub fn (mgr &UatManager) unbind_context(ctx &UatContext) {
	if ctx == unsafe { nil } {
		return
	}

	slot := ctx.id
	if slot >= uat_num_contexts {
		return
	}

	slot_addr := mgr.ttbat_base + u64(slot) * ttbat_slot_size
	slot_virt := slot_addr + higher_half

	unsafe {
		mut ttbr_ptr := &u64(slot_virt)
		*ttbr_ptr = 0
		mut cfg_ptr := &u64(slot_virt + 8)
		*cfg_ptr = 0
	}

	cpu.dsb_sy()
}

// Request a TLB flush for a given context through the firmware handoff.
pub fn (mgr &UatManager) flush(ctx &UatContext) {
	if ctx == unsafe { nil } || mgr.handoff == unsafe { nil } {
		return
	}

	handoff_lock(mgr.handoff)
	defer {
		handoff_unlock(mgr.handoff)
	}

	handoff_flush(mgr.handoff, ctx.id)
}

// Map a region into the kernel (shared) page table.
// All VM contexts see the kernel page table via TTBR1 in their TTBAT slot.
pub fn (mgr &UatManager) map_kernel(iova u64, phys u64, size u64, prot u64) bool {
	if mgr.kernel_pgtable == unsafe { nil } {
		return false
	}

	mut pt := unsafe { mgr.kernel_pgtable }
	return pt.map(iova, phys, size, prot)
}

// --- Peterson-style handoff lock (AP side) ---
//
// The AP and firmware each have a flag (lock_ap, lock_fw).
// The `turn` variable decides who yields when both want to enter.
// AP sets its flag, sets turn = 1 (yield to FW), then spins while
// FW flag is set AND turn is still 1.

pub fn handoff_lock(h &UatHandoff) {
	if h == unsafe { nil } {
		return
	}

	// Express interest
	unsafe {
		mut hp := h
		katomic.store(mut &hp.lock_ap, u32(1))
	}

	// Yield priority to firmware
	unsafe {
		mut hp := h
		katomic.store(mut &hp.turn, u32(1))
	}

	// Full memory barrier so firmware sees our writes
	cpu.dmb_sy()

	// Spin while firmware holds the lock and it is our turn to wait
	for {
		fw := katomic.load(&h.lock_fw)
		turn := katomic.load(&h.turn)
		if fw == 0 || turn != 1 {
			break
		}
		// Power-efficient spin
		cpu.wfe()
	}
}

pub fn handoff_unlock(h &UatHandoff) {
	if h == unsafe { nil } {
		return
	}

	// Release our interest
	unsafe {
		mut hp := h
		katomic.store(mut &hp.lock_ap, u32(0))
	}

	cpu.dmb_sy()

	// Wake firmware if it was spinning
	cpu.sev()
}

// Request a TLB invalidation for `ctx_id` via the handoff flush protocol.
// Caller must hold the handoff lock.
fn handoff_flush(h &UatHandoff, ctx_id u32) {
	if h == unsafe { nil } {
		return
	}

	// Set the slot to flush
	unsafe {
		mut hp := h
		katomic.store(mut &hp.cur_slot, ctx_id)
	}

	// Signal flush pending
	unsafe {
		mut hp := h
		katomic.store(mut &hp.flush_state, handoff_flush_pending)
	}

	cpu.dmb_sy()

	// Wait for firmware to acknowledge and complete the flush
	timeout := 100000
	for i := 0; i < timeout; i++ {
		state := katomic.load(&h.flush_state)
		if state == handoff_flush_done || state == handoff_flush_idle {
			break
		}
		cpu.wfe()
	}

	// Reset flush state to idle
	unsafe {
		mut hp := h
		katomic.store(mut &hp.flush_state, handoff_flush_idle)
	}

	cpu.dmb_sy()
}

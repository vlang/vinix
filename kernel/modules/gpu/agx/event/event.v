@[has_globals]
module event

// GPU event manager and completion stamp tracking
// Manages a shared-memory stamp array that the GPU firmware writes to
// signal completion. Each stamp slot can be associated with a DMA fence
// that is signaled when the stamp value is observed. Translates event.rs
// from the Asahi Linux GPU driver.

import drm.syncobj
import klock
import katomic

// The v12.3 firmware exposes exactly 128 event slots. Driver-visible and
// firmware-private stamps are separate arrays of four-byte counters.
pub const max_stamps = u32(128)
pub const stamp_size = u32(4)

pub struct StampState {
pub mut:
	value  u32
	fence  &syncobj.DmaFence = unsafe { nil }
	in_use bool
}

pub struct EventManager {
pub mut:
	stamp_base u64 // GPU VA of stamp array
	stamp_phys u64 // physical address
	fw_stamp_base u64
	fw_stamp_phys u64
	stamps     [max_stamps]StampState
	initialized bool
	lock       klock.Lock
}

__global (
	gpu_event_mgr EventManager
)

pub fn configure_event_manager(stamp_va u64, stamp_phys u64, fw_stamp_va u64,
	fw_stamp_phys u64) bool {
	if stamp_va == 0 || stamp_phys == 0 || fw_stamp_va == 0 || fw_stamp_phys == 0 {
		return false
	}
	unsafe {
		C.memset(voidptr(stamp_phys + higher_half), 0, u64(max_stamps) * stamp_size)
		C.memset(voidptr(fw_stamp_phys + higher_half), 0, u64(max_stamps) * stamp_size)
	}
	gpu_event_mgr = EventManager{
		stamp_base: stamp_va
		stamp_phys: stamp_phys
		fw_stamp_base: fw_stamp_va
		fw_stamp_phys: fw_stamp_phys
		initialized: true
	}
	return true
}

pub fn reset_event_manager() {
	// Serialize with the worker before its physical backing is unmapped/freed.
	gpu_event_mgr.lock.acquire()
	gpu_event_mgr.initialized = false
	gpu_event_mgr.stamp_base = 0
	gpu_event_mgr.stamp_phys = 0
	gpu_event_mgr.fw_stamp_base = 0
	gpu_event_mgr.fw_stamp_phys = 0
	for i := u32(0); i < max_stamps; i++ {
		gpu_event_mgr.stamps[i] = StampState{}
	}
	gpu_event_mgr.lock.release()
}

pub fn event_manager_ready() bool {
	return gpu_event_mgr.initialized
}

// Allocate a stamp slot. Returns the slot index, or none if all slots
// are in use.
pub fn (mut em EventManager) alloc_stamp() ?u32 {
	if !em.initialized {
		return none
	}
	em.lock.acquire()
	defer {
		em.lock.release()
	}

	for i := u32(0); i < max_stamps; i++ {
		if !em.stamps[i].in_use {
			em.stamps[i].in_use = true
			em.stamps[i].value = 0
			em.stamps[i].fence = unsafe { nil }
			unsafe {
				mut stamp := &u32(em.stamp_phys + u64(i) * stamp_size + higher_half)
				mut fw_stamp := &u32(em.fw_stamp_phys + u64(i) * stamp_size + higher_half)
				katomic.store(mut stamp, u32(0))
				katomic.store(mut fw_stamp, u32(0))
			}
			return i
		}
	}

	return none
}

// Free a previously allocated stamp slot.
pub fn (mut em EventManager) free_stamp(index u32) {
	if index >= max_stamps {
		return
	}

	em.lock.acquire()
	defer {
		em.lock.release()
	}

	em.stamps[index].in_use = false
	em.stamps[index].fence = unsafe { nil }
	em.stamps[index].value = 0
}

// Return the GPU virtual address of a stamp slot.
pub fn (em &EventManager) get_stamp_addr(index u32) u64 {
	if !em.initialized || index >= max_stamps {
		return 0
	}
	return em.stamp_base + u64(index) * u64(stamp_size)
}

pub fn (em &EventManager) get_fw_stamp_addr(index u32) u64 {
	if !em.initialized || index >= max_stamps {
		return 0
	}
	return em.fw_stamp_base + u64(index) * u64(stamp_size)
}

// Associate a DMA fence with a stamp slot. The fence will be signaled
// when the stamp value is observed during completion scanning.
pub fn (mut em EventManager) set_fence(index u32, fence &syncobj.DmaFence) {
	if index >= max_stamps {
		return
	}

	em.lock.acquire()
	defer {
		em.lock.release()
	}

	em.stamps[index].fence = unsafe { fence }
}

// Set the expected completion value for a stamp slot.
pub fn (mut em EventManager) set_expected(index u32, value u32) {
	if index >= max_stamps {
		return
	}

	em.lock.acquire()
	defer {
		em.lock.release()
	}

	em.stamps[index].value = value
}

// Check whether a stamp slot has been completed by the GPU.
// Reads the stamp value from shared memory and signals the associated
// fence if the written value matches or exceeds the expected value.
// Returns true if the stamp has completed.
pub fn (mut em EventManager) check_completion(index u32) bool {
	if !em.initialized || index >= max_stamps {
		return false
	}
	em.lock.acquire()
	defer {
		em.lock.release()
	}
	if !em.stamps[index].in_use {
		return false
	}

	// Read the stamp value from shared memory
	stamp_phys_addr := em.stamp_phys + u64(index) * u64(stamp_size)
	current_value := unsafe { katomic.load(&u32(stamp_phys_addr + higher_half)) }

	expected := em.stamps[index].value
	if expected == 0 {
		return false
	}

	if i32(current_value - expected) >= 0 {
		// Stamp completed -- signal the fence
		if em.stamps[index].fence != unsafe { nil } {
			syncobj.signal(em.stamps[index].fence)
		}
		return true
	}

	return false
}

// Advance one event in the firmware's 0x100-unit sequence space.
pub fn (mut em EventManager) next_stamp_value(index u32) ?u32 {
	if !em.initialized || index >= max_stamps {
		return none
	}
	em.lock.acquire()
	defer {
		em.lock.release()
	}

	value := em.stamps[index].value + u32(0x100)
	em.stamps[index].value = value
	return value
}

// Scan all active stamp slots for completion. This is called from the
// event processing path (e.g., after receiving a firmware event channel
// notification) to batch-check and signal fences.
pub fn (mut em EventManager) scan_completions() {
	if !em.initialized {
		return
	}
	em.lock.acquire()
	defer {
		em.lock.release()
	}

	for i := u32(0); i < max_stamps; i++ {
		if !em.stamps[i].in_use {
			continue
		}

		if em.stamps[i].value == 0 {
			continue
		}

		// Read stamp from shared memory
		stamp_phys_addr := em.stamp_phys + u64(i) * u64(stamp_size)
		current_value := unsafe { katomic.load(&u32(stamp_phys_addr + higher_half)) }

		if i32(current_value - em.stamps[i].value) >= 0 {
			// Signal the fence
			if em.stamps[i].fence != unsafe { nil } {
				syncobj.signal(em.stamps[i].fence)
			}
			// Mark slot as no longer in use
			em.stamps[i].in_use = false
			em.stamps[i].fence = unsafe { nil }
		}
	}
}

// Firmware event handlers use this entry point so the global manager remains
// encapsulated in this module.
pub fn scan_all_completions() {
	gpu_event_mgr.scan_completions()
}

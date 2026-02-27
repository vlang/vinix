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
import memory

pub const max_stamps = u32(1024)
pub const stamp_size = u32(16) // each stamp is 16 bytes in shared memory

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
	stamps     [max_stamps]StampState
	next_value u32
	lock       klock.Lock
}

__global (
	gpu_event_mgr EventManager
)

// Create a new event manager backed by the given stamp memory region.
pub fn new_event_manager(stamp_va u64, stamp_phys u64) EventManager {
	// Zero-initialise the stamp memory region
	if stamp_phys != 0 {
		unsafe {
			C.memset(voidptr(stamp_phys + higher_half), 0,
				u64(max_stamps) * u64(stamp_size))
		}
	}

	return EventManager{
		stamp_base: stamp_va
		stamp_phys: stamp_phys
		next_value: 1
	}
}

// Allocate a stamp slot. Returns the slot index, or none if all slots
// are in use.
pub fn (mut em EventManager) alloc_stamp() ?u32 {
	em.lock.acquire()
	defer {
		em.lock.release()
	}

	for i := u32(0); i < max_stamps; i++ {
		if !em.stamps[i].in_use {
			em.stamps[i].in_use = true
			em.stamps[i].value = 0
			em.stamps[i].fence = unsafe { nil }
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
	if index >= max_stamps {
		return 0
	}
	return em.stamp_base + u64(index) * u64(stamp_size)
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
	if index >= max_stamps {
		return false
	}

	if !em.stamps[index].in_use {
		return false
	}

	// Read the stamp value from shared memory
	stamp_phys_addr := em.stamp_phys + u64(index) * u64(stamp_size)
	current_value := unsafe { *&u32(stamp_phys_addr + higher_half) }

	expected := em.stamps[index].value
	if expected == 0 {
		return false
	}

	if current_value >= expected {
		// Stamp completed -- signal the fence
		if em.stamps[index].fence != unsafe { nil } {
			syncobj.signal(em.stamps[index].fence)
		}
		return true
	}

	return false
}

// Atomically get the next unique stamp value. Each stamp value is
// monotonically increasing so the GPU can write it to signal progress.
pub fn (mut em EventManager) next_stamp_value() u32 {
	em.lock.acquire()
	defer {
		em.lock.release()
	}

	val := em.next_value
	em.next_value++

	// Wrap around but skip zero (zero means "not complete")
	if em.next_value == 0 {
		em.next_value = 1
	}

	return val
}

// Scan all active stamp slots for completion. This is called from the
// event processing path (e.g., after receiving a firmware event channel
// notification) to batch-check and signal fences.
pub fn (mut em EventManager) scan_completions() {
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
		current_value := unsafe { *&u32(stamp_phys_addr + higher_half) }

		if current_value >= em.stamps[i].value {
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

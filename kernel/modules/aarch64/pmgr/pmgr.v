@[has_globals]
module pmgr

// Apple Power Manager (PMGR)
// Controls power domains for various SoC blocks (GPU, DCP, USB, etc.)
// Each power domain has a register with enable/status bits.

import aarch64.kio
import aarch64.timer
import klock

// PMGR register bit definitions
const pmgr_ps_active = u32(0xf) << 4  // Target power state: active
const pmgr_ps_mask = u32(0xf) << 4     // Target power state mask
const pmgr_actual_mask = u32(0xf) << 0  // Actual power state mask
const pmgr_active = u32(0xf)            // Active state value

__global (
	pmgr_base = u64(0)
	pmgr_lock klock.Lock
)

pub fn initialise(base u64) {
	pmgr_base = base + higher_half
	println('pmgr: Apple Power Manager at 0x${base:x}')
}

// Enable a power domain at the given register offset
pub fn enable(offset u32) bool {
	pmgr_lock.acquire()
	defer {
		pmgr_lock.release()
	}

	addr := unsafe { &u32(pmgr_base + offset) }

	// Read current state
	mut val := kio.mmin32(addr)

	// Set target state to active
	val &= ~pmgr_ps_mask
	val |= pmgr_ps_active
	kio.mmout32(addr, val)

	// Wait for actual state to reach active (with timeout)
	for i := 0; i < 10000; i++ {
		val = kio.mmin32(addr)
		if val & pmgr_actual_mask == pmgr_active {
			return true
		}
		timer.busywait_us(10)
	}

	C.printf(c'pmgr: Timeout enabling power domain at offset 0x%x\n', offset)
	return false
}

// Disable a power domain at the given register offset
pub fn disable(offset u32) {
	pmgr_lock.acquire()
	defer {
		pmgr_lock.release()
	}

	addr := unsafe { &u32(pmgr_base + offset) }

	// Read current state
	mut val := kio.mmin32(addr)

	// Set target state to off (0)
	val &= ~pmgr_ps_mask
	kio.mmout32(addr, val)
}

// Check if a power domain is active
pub fn is_active(offset u32) bool {
	addr := unsafe { &u32(pmgr_base + offset) }
	val := kio.mmin32(addr)
	return val & pmgr_actual_mask == pmgr_active
}

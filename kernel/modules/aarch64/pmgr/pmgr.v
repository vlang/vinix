@[has_globals]
module pmgr

// Apple Power Manager (PMGR)
// Controls power domains for various SoC blocks (GPU, DCP, USB, etc.)
// Each power domain has a register with enable/status bits.

import aarch64.kio
import aarch64.timer
import klock
import memory

// PMGR register bit definitions.
// Per the Apple PMGR power-state layout the *target* power state lives in
// bits [3:0] and the *actual* (current) power state is reported in bits [7:4].
// A fully-on domain reads 0xf in each field.
const pmgr_ps_target_mask = u32(0xf) << 0 // Target power state field
const pmgr_ps_target_active = u32(0xf) << 0 // Target value for "active"
const pmgr_ps_actual_mask = u32(0xf) << 4 // Actual power state field
const pmgr_ps_actual_active = u32(0xf) << 4 // Actual value once fully active
const pmgr_was_power_gated = u32(1) << 8
const pmgr_was_clock_gated = u32(1) << 9
const pmgr_auto_enable = u32(1) << 28
const pmgr_transient_flags = pmgr_was_power_gated | pmgr_was_clock_gated

__global (
	pmgr_base = u64(0)
	pmgr_lock klock.Lock
)

pub fn initialise(base u64) {
	// Map the PMGR register aperture as Device memory. The exact region size
	// should come from the device-tree reg entry; map a conservative window
	// until that is plumbed through.
	pmgr_base = memory.map_mmio(base, 0x10000)
	println('pmgr: Apple Power Manager at 0x${base:x}')
}

fn enable_mapped(base u64, offset u32) bool {
	addr := unsafe { &u32(base + offset) }
	mut val := kio.mmin32(addr)

	// Acknowledge stale transition flags and request the fully active state.
	// AUTO_ENABLE is restored only after the synchronous transition, matching
	// the upstream Apple PMGR power-domain sequence.
	val &= ~(pmgr_auto_enable | pmgr_transient_flags | pmgr_ps_target_mask)
	val |= pmgr_ps_target_active
	kio.mmout32(addr, val)

	for _ in 0 .. 10000 {
		val = kio.mmin32(addr)
		if val & pmgr_ps_actual_mask == pmgr_ps_actual_active {
			val &= ~pmgr_transient_flags
			val |= pmgr_auto_enable
			kio.mmout32(addr, val)
			return true
		}
		timer.busywait_us(10)
	}

	C.printf(c'pmgr: Timeout enabling power domain at offset 0x%x\n', offset)
	return false
}

// Enable a domain in an explicitly identified PMGR register aperture. Device
// drivers use this for phandle-resolved power domains instead of relying on
// whichever of several PMGR nodes happened to initialize the global handle.
pub fn enable_region(physical_base u64, region_size u64, offset u32) bool {
	if physical_base == 0 || region_size < 4 || u64(offset) > region_size - 4 {
		return false
	}
	mapped := memory.map_mmio(physical_base, region_size)
	if mapped == 0 {
		return false
	}
	pmgr_lock.acquire()
	defer {
		pmgr_lock.release()
	}
	return enable_mapped(mapped, offset)
}

// Enable a power domain at the given register offset
pub fn enable(offset u32) bool {
	pmgr_lock.acquire()
	defer {
		pmgr_lock.release()
	}

	if pmgr_base == 0 {
		return false
	}
	return enable_mapped(pmgr_base, offset)
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

	// Set target state to off (0), preserving unrelated bits.
	val &= ~pmgr_ps_target_mask
	kio.mmout32(addr, val)
}

// Check if a power domain is active
pub fn is_active(offset u32) bool {
	addr := unsafe { &u32(pmgr_base + offset) }
	val := kio.mmin32(addr)
	return val & pmgr_ps_actual_mask == pmgr_ps_actual_active
}

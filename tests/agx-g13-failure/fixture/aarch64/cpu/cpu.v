// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module cpu

import klock

__global snapshot_barriers = u32(0)
__global send_fences = u32(0)
__global cache_preparations = u32(0)
__global prepared_address = u64(0)
__global prepared_span = u64(0)

pub fn wfe() {}
pub fn isb() {}
pub fn dmb_ishld() { snapshot_barriers++ }
pub fn dmb_sy() { send_fences++ }
pub fn send_barriers() u32 { return send_fences }
pub fn interrupt_state() bool { return klock.interrupt_state() }
pub fn set_interrupt_state(enabled bool) { klock.set_interrupt_state(enabled) }
pub fn barriers() u32 { return snapshot_barriers }

pub fn clean_invalidate_data_cache_to_poc(address u64, span u64) {
	assert address != 0 && span == 0x4000
	for i := u64(0); i < span; i++ {
		assert unsafe { *&u8(address + i) } == 0
	}
	cache_preparations++
	prepared_address = address
	prepared_span = span
}

pub fn prepared_range() (u32, u64, u64) {
	return cache_preparations, prepared_address, prepared_span
}

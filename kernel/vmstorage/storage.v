// SPDX-License-Identifier: GPL-2.0-or-later
module vmstorage

import errno
import kbudget
import proc
import memory

// Cover V's array header/alignment and the heap allocator header, then the
// actual slab/page geometry. Big allocations need rounded data pages plus
// one metadata page; that page is also 16 KiB on AArch64.
pub fn allocation_bytes(payload u64) ?u64 {
	return allocation_bytes_for(payload, memory.page_size)
}

pub fn allocation_bytes_for(payload u64, granule u64) ?u64 {
	if payload > ~u64(0) - 128 { return none }
	if granule < 4096 || granule & (granule - 1) != 0 { return none }
	request := payload + 128
	if request > 2048 {
		pages := request / granule + if request % granule == 0 { u64(0) } else { u64(1) }
		if pages >= ~u64(0) / granule { return none }
		return (pages + 1) * granule
	}
	mut bytes := u64(128)
	for bytes < request {
		bytes *= 2
	}
	return bytes
}

// Caller owns a nonsliced metadata array, serializes its mutation, and already
// charges allocation_bytes(cap * sizeof(T)) in this object's reservation.
// Reserve both buffers at the peak; the previous buffer is released by V's
// existing .noslices growth, and its reservation then retires. Retained
// capacity remains charged until the owning object disposes of the array.
pub fn ensure_capacity[T](mut values []T, mut charge kbudget.Charge, required int) ? {
	if required < 0 {
		errno.set(errno.einval)
		return none
	}
	if required <= values.cap { return }
	assert u64(values.flags) & u64(ArrayFlags.is_slice) == 0
	mut capacity := if values.cap > 0 { values.cap } else { 2 }
	for capacity < required {
		if capacity > max_int / 2 {
			capacity = max_int
			break
		}
		capacity *= 2
	}
	if u64(capacity) > ~u64(0) / u64(sizeof(T)) {
		errno.set(errno.enomem)
		return none
	}
	old_bytes := allocation_bytes(u64(values.cap) * u64(sizeof(T))) or {
		errno.set(errno.enomem)
		return none
	}
	new_bytes := allocation_bytes(u64(capacity) * u64(sizeof(T))) or {
		errno.set(errno.enomem)
		return none
	}
	if !proc.grow_kernel(mut charge, new_bytes) { return none }
	values.flags |= .noslices
	values.ensure_cap(required)
	// The pinned V array runtime doubles capacity. A runtime change must also
	// update this admission calculation and its real-array host regressions.
	assert values.cap == capacity
	kbudget.shrink(mut charge, old_bytes)
}

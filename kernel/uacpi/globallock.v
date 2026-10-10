// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The ACPI global lock, for a driver that firmware says must hold it.
//
// Firmware and the operating system share some hardware, the embedded
// controller above all, and the global lock is how they keep out of each
// other's exchanges with it: a word in the FACS both sides set and clear. A
// device whose _GLK is 1 is to be touched only with the lock held.
//
// uACPI takes the lock by itself around every field that is declared Lock,
// and gives a driver uacpi_acquire_global_lock() for the rest. The two do
// not know of each other: behind both is one mutex of the host's, and a
// handler called for a Lock field that asked for the lock again would wait
// for the mutex its own thread holds. So a driver first has to be able to
// ask whether the calling thread has the lock already.
//
// uACPI does not say which of the mutexes it made is that one. It is found
// by watching: learn_global_lock() takes the lock once, and the mutex its
// thread acquires while it does is the one. After that the host's own record
// of who holds a mutex answers the question.
@[has_globals]
module uacpi

import acpisync

@[c_extern]
fn C.uacpi_acquire_global_lock(timeout u16, out_sequence &u32) UACPIStatus
@[c_extern]
fn C.uacpi_release_global_lock(sequence u32) UACPIStatus

__global (
	// The host mutex behind the global lock, once it has been seen.
	uacpi_global_lock_mutex voidptr
	// The thread that is taking the lock to find that out, or zero.
	uacpi_global_lock_learner u64
	uacpi_global_lock_seen    voidptr
)

// Called for every mutex uACPI acquires.
fn note_mutex(handle voidptr) {
	if uacpi_global_lock_learner != 0 && acpisync.thread_id() == uacpi_global_lock_learner {
		uacpi_global_lock_seen = handle
	}
}

// Find out which mutex the global lock is. Like every taking of the lock it
// waits for firmware to let go of it; firmware holds it for the length of
// one of its own exchanges. False when the lock could not be taken.
pub fn learn_global_lock() bool {
	if uacpi_global_lock_mutex != unsafe { nil } {
		return true
	}
	mut sequence := u32(0)
	uacpi_global_lock_seen = unsafe { nil }
	uacpi_global_lock_learner = acpisync.thread_id()
	status := C.uacpi_acquire_global_lock(0xffff, unsafe { &sequence })
	uacpi_global_lock_learner = 0
	if status != .ok {
		return false
	}
	uacpi_global_lock_mutex = uacpi_global_lock_seen
	return release_global_lock(sequence) && uacpi_global_lock_mutex != unsafe { nil }
}

// Whether the calling thread holds the global lock, through a Lock field or
// through acquire_global_lock(). False until learn_global_lock() has run.
pub fn global_lock_held() bool {
	return uacpi_global_lock_mutex != unsafe { nil } && acpisync.held_by_caller(uacpi_global_lock_mutex)
}

// Take the global lock, waiting at most `timeout_ms` for another thread of
// this kernel to let go of it. The second value is what release_global_lock()
// is to be given.
pub fn acquire_global_lock(timeout_ms u16) (bool, u32) {
	mut sequence := u32(0)
	if C.uacpi_acquire_global_lock(timeout_ms, unsafe { &sequence }) != .ok {
		return false, u32(0)
	}
	return true, sequence
}

// Give the global lock back. uACPI 2.0.0 hands out its counter and then
// advances it, and afterwards accepts only the advanced value: what
// acquiring returned is refused, with nothing done. So that is tried first,
// which is right for a uACPI where the two agree, and then the next number.
// False when neither was accepted and the lock is still held.
pub fn release_global_lock(sequence u32) bool {
	if C.uacpi_release_global_lock(sequence) == .ok {
		return true
	}
	return C.uacpi_release_global_lock(sequence + 1) == .ok
}

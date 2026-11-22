// SPDX-License-Identifier: GPL-2.0-or-later
module futex

import errno
import event.eventstruct
import memory
import proc
import time
import usercopy

const waitv_max = 128
const futex2_word = u32(2)
const futex2_private = u32(128)

struct WaitRequest {
mut:
	value    u64
	address  u64
	flags    u32
	reserved u32
}

struct VectorWait {
mut:
	request WaitRequest
	node    Wait
}

fn futex2_flags_valid(flags u32) bool {
	return flags & ~futex2_private == futex2_word
}

fn (request WaitRequest) is_private() bool {
	return request.flags & futex2_private != 0
}

fn import_wait_request(address u64, mut request WaitRequest) u64 {
	if !usercopy.copy_from_user(voidptr(&request), address, sizeof(WaitRequest)) {
		return errno.efault
	}
	if !futex2_flags_valid(request.flags) || request.reserved != 0 || request.value > u64(0xffffffff) {
		return errno.einval
	}
	return 0
}

fn futex2_deadline(address u64, clock_id int, mut deadline time.TimeSpec) u64 {
	if address == 0 { return 0 }
	if clock_id != time.clock_type_realtime && clock_id != time.clock_type_monotonic {
		return errno.einval
	}
	if !usercopy.copy_from_user(voidptr(&deadline), address, sizeof(time.TimeSpec)) {
		return errno.efault
	}
	if deadline.tv_sec < 0 || deadline.tv_nsec < 0 || deadline.tv_nsec >= 1000000000 {
		return errno.einval
	}
	return 0
}

fn queue_vector_entry(mut entry VectorWait) u64 {
	address := entry.request.address
	private := entry.request.is_private()
	for _ in 0 .. 16 {
		futex_lock.acquire()
		current := usercopy.futex_read_u32_inatomic(address) or {
			futex_lock.release()
			usercopy.read_u32(address) or { return errno.efault }
			// This entry isn't linked yet. A shared mapping may have a
			// different key after faulting the word in again.
			if !private {
				mut old := entry.node.futex
				entry.node.futex = get(address, true, false) or { return errno.efault }
				put(mut old)
			}
			continue
		}
		if current != u32(entry.request.value) {
			futex_lock.release()
			return errno.eagain
		}
		append_wait(mut entry.node.futex, &entry.node)
		futex_lock.release()
		return 0
	}
	return errno.eagain
}

fn prepare_vector(entries &VectorWait, count int, mut wake_event eventstruct.Event, bitset u32) u64 {
	// Resolve all keys before sampling values or exposing any of the nodes.
	for i in 0 .. count {
		mut entry := unsafe { &entries[i] }
		private := entry.request.is_private()
		error := address_error(entry.request.address, private)
		if error != 0 {
			return error
		}
		owner := get(entry.request.address, true, private) or { return errno.efault }
		entry.node = Wait{futex: owner, bitset: bitset, event: &wake_event}
	}
	return 0
}

fn finish_vector(entries &VectorWait, count int, queued int, error u64) (u64, u64) {
	mut woken := -1
	futex_lock.acquire()
	for i in 0 .. queued {
		mut node := unsafe { &entries[i].node }
		if node.woken {
			woken = i
		} else {
			unlink_wait(mut node.futex, node)
		}
	}
	futex_lock.release()

	// Wake removed its node under the lock. All remaining links have now
	// gone too, so requeue can no longer transfer these references.
	for i in 0 .. count {
		mut owner := unsafe { entries[i].node.futex }
		if owner == unsafe { nil } { break }
		put(mut owner)
	}
	if woken >= 0 { return u64(woken), 0 }
	return errno.err, error
}

fn wait_vector(entries &VectorWait, count int, bitset u32, deadline time.TimeSpec, timed bool, clock_id int) (u64, u64) {
	mut wake_event := unsafe { &eventstruct.Event(C.__builtin_alloca(sizeof(eventstruct.Event))) }
	mut timer := unsafe { &time.Timer(C.__builtin_alloca(sizeof(time.Timer))) }
	unsafe { *wake_event = eventstruct.Event{} }
	if timed {
		unsafe {
			*timer = time.Timer{
				index: -1
				when: deadline
				absolute_realtime: clock_id == time.clock_type_realtime
			}
		}
		if timer.absolute_realtime {
			timer.arm()
		} else {
			timer.arm_monotonic_deadline()
		}
	}
	defer {
		if timed { timer.disarm() }
	}
	prepare_error := prepare_vector(entries, count, mut wake_event, bitset)
	if prepare_error != 0 {
		return finish_vector(entries, count, 0, prepare_error)
	}
	for i in 0 .. count {
		mut entry := unsafe { &entries[i] }
		error := queue_vector_entry(mut entry)
		if error != 0 {
			return finish_vector(entries, count, i, error)
		}
	}
	mut error := await_wake(mut wake_event, if timed { timer } else { unsafe { nil } })
	if error == errno.eintr {
		error = proc.interrupted_errno
		if timed {
			// If a signal arrived while preparing an already expired wait,
			// the deadline still takes precedence over the interruption.
			mut remaining := deadline
			now := time.clock_now(clock_id) or { time.TimeSpec{} }
			if remaining.sub(now) { error = errno.etimedout }
		}
	}
	return finish_vector(entries, count, count, error)
}

pub fn syscall_waitv(_ voidptr, waiters u64, count_word u64, flags u64, timeout u64, clock_word u64) (u64, u64) {
	count := u32(count_word)
	if u32(flags) != 0 || count == 0 || count > waitv_max || waiters == 0 {
		return errno.err, errno.einval
	}
	clock_id := int(i32(clock_word))
	mut deadline := time.TimeSpec{}
	error := futex2_deadline(timeout, clock_id, mut deadline)
	if error != 0 {
		return errno.err, error
	}
	@[freed]
	entries := unsafe { &VectorWait(memory.malloc_packed_fallible(u64(count) * sizeof(VectorWait))) }
	if entries == unsafe { nil } { return errno.err, errno.enomem }
	defer { unsafe { free(entries) } }
	for i in 0 .. int(count) {
		mut entry := unsafe { &entries[i] }
		unsafe { *entry = VectorWait{} }
		import_error := import_wait_request(waiters + u64(i) * sizeof(WaitRequest), mut entry.request)
		if import_error != 0 {
			return errno.err, import_error
		}
	}
	return wait_vector(entries, int(count), u32(0xffffffff), deadline, timeout != 0, clock_id)
}

pub fn syscall_futex2_wait(_ voidptr, address u64, value u64, mask u64, flags u64, timeout u64, clock_word u64) (u64, u64) {
	if !futex2_flags_valid(u32(flags)) || value > u64(0xffffffff) || mask > u64(0xffffffff) {
		return errno.err, errno.einval
	}
	clock_id := int(i32(clock_word))
	mut deadline := time.TimeSpec{}
	error := futex2_deadline(timeout, clock_id, mut deadline)
	if error != 0 {
		return errno.err, error
	}
	if mask == 0 { return errno.err, errno.einval }
	entry := VectorWait{request: WaitRequest{address: address, value: value, flags: u32(flags)}}
	return wait_vector(unsafe { &entry }, 1, u32(mask), deadline, timeout != 0, clock_id)
}

pub fn syscall_futex2_wake(_ voidptr, address u64, mask u64, count_word u64, flags u64) (u64, u64) {
	if !futex2_flags_valid(u32(flags)) || mask == 0 || mask > u64(0xffffffff) {
		return errno.err, errno.einval
	}
	private := u32(flags) & futex2_private != 0
	error := address_error(address, private)
	if error != 0 { return errno.err, error }
	count := i32(count_word)
	if count == 0 { return 0, 0 }
	return wake_count(address, if count < 0 { u64(1) } else { u64(count) }, private, u32(mask)), 0
}

pub fn syscall_futex2_requeue(_ voidptr, waiters u64, flags u64, wake_word u64, move_word u64) (u64, u64) {
	if u32(flags) != 0 || waiters == 0 { return errno.err, errno.einval }
	mut source := WaitRequest{}
	mut target := WaitRequest{}
	source_import := import_wait_request(waiters, mut source)
	if source_import != 0 { return errno.err, source_import }
	target_import := import_wait_request(waiters + sizeof(WaitRequest), mut target)
	if target_import != 0 { return errno.err, target_import }
	wake := int(i32(wake_word))
	move := int(i32(move_word))
	if wake < 0 || move < 0 { return errno.err, errno.einval }
	source_error := address_error(source.address, source.is_private())
	if source_error != 0 { return errno.err, source_error }
	target_error := address_error(target.address, target.is_private())
	if target_error != 0 { return errno.err, target_error }
	return requeue_keys(source.address, target.address, wake, move, source.is_private(),
		target.is_private(), true, u32(source.value))
}

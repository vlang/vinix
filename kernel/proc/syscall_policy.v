// SPDX-License-Identifier: GPL-2.0-or-later
module proc

import errno
import katomic
import memory
import memory.mmap
import usercopy

pub const pr_vinix_syscall_policy = 0x56490002
const syscall_pin_limit = u32(512)
const syscall_pin_span_limit = u64(64 * 1024 * 1024)

// A single owned allocation: this header followed by count SyscallPin records.
// Records never change after publication. Only the reference count is shared
// mutable state; each Process retains its own mode and violation count.
pub struct SyscallPolicy {
pub mut:
	refs u32
	count u32
	base u64
	length u64
}

struct SyscallPinRequest {
mut:
	version u64
	base u64
	length u64
	entries u64
	count u64
	reserved u64
}

fn C.vinix_stack_alloc(size u64) voidptr

fn policy_pins(policy &SyscallPolicy) &mmap.SyscallPin {
	return unsafe { &mmap.SyscallPin(u64(policy) + sizeof(SyscallPolicy)) }
}

fn policy_drop(mut policy SyscallPolicy) {
	if !katomic.dec(mut &policy.refs) { unsafe { free(&policy) } }
}

pub fn syscall_policy_reset(mut process Process) {
	process.syscall_policy_lock.acquire()
	old := process.syscall_policy
	process.syscall_policy = unsafe { nil }
	katomic.store(mut &process.syscall_policy_mode, u32(0))
	katomic.store(mut &process.syscall_policy_violations, u64(0))
	process.syscall_policy_lock.release()
	if old != unsafe { nil } { policy_drop(mut unsafe { old }) }
}

pub fn syscall_policy_inherit(mut child Process, _parent &Process) {
	mut parent := unsafe { _parent }
	parent.syscall_policy_lock.acquire()
	defer { parent.syscall_policy_lock.release() }
	policy := parent.syscall_policy
	if policy != unsafe { nil } {
		katomic.inc(mut &policy.refs)
		child.syscall_policy = policy
		child.syscall_policy_mode = katomic.load(&parent.syscall_policy_mode)
	}
	// A child starts its own violation count, just like the stack policy.
}

// prctl actions: 0 mode, 1 install audit, 2 install enforce, 3 violations,
// 4 strengthen to enforce. Installing succeeds only once until exec.
pub fn syscall_policy_control(mut process Process, action u64, request u64) (u64, u64) {
	if action == 0 || action == 3 {
		if request != 0 { return errno.err, errno.einval }
		return if action == 0 { u64(katomic.load(&process.syscall_policy_mode)) }
			else { katomic.load(&process.syscall_policy_violations) }, 0
	}
	if action == 4 {
		if request != 0 { return errno.err, errno.einval }
		process.syscall_policy_lock.acquire()
		defer { process.syscall_policy_lock.release() }
		if process.syscall_policy == unsafe { nil } { return errno.err, errno.eperm }
		katomic.store(mut &process.syscall_policy_mode, u32(2))
		return 0, 0
	}
	if action != 1 && action != 2 { return errno.err, errno.einval }
	if katomic.load(&process.syscall_policy_mode) != 0 { return errno.err, errno.eperm }
	mut input := unsafe { &SyscallPinRequest(C.vinix_stack_alloc(sizeof(SyscallPinRequest))) }
	if !usercopy.copy_from_user(voidptr(input), request, sizeof(SyscallPinRequest)) {
		return errno.err, errno.efault
	}
	if input.version != 1 || input.reserved != 0 || input.count == 0
		|| input.count > syscall_pin_limit || input.length == 0
		|| input.length > syscall_pin_span_limit || input.base % page_size != 0
		|| input.length % page_size != 0 || !usercopy.user_range(input.base, input.length) {
		return errno.err, errno.einval
	}
	size := u64(sizeof(SyscallPolicy)) + input.count * sizeof(mmap.SyscallPin)
	mut policy := unsafe { &SyscallPolicy(memory.malloc_packed_fallible(size)) } @[freed]
	if policy == unsafe { nil } { return errno.err, errno.enomem }
	mut published := false
	defer { if !published { unsafe { free(policy) } } }
	policy.refs = 1
	policy.count = u32(input.count)
	policy.base = input.base
	policy.length = input.length
	pins := policy_pins(policy)
	if !usercopy.copy_from_user(voidptr(pins), input.entries, input.count * sizeof(mmap.SyscallPin)) {
		return errno.err, errno.efault
	}
	for i := u32(0); i < policy.count; i++ {
		pin := unsafe { pins[i] }
		if pin.flags != 0 || pin.number >= syscall_pin_limit
			|| (i > 0 && pin.number <= unsafe { pins[i - 1].number }) {
			return errno.err, errno.einval
		}
		for previous := u32(0); previous < i; previous++ {
			if pin.offset == unsafe { pins[previous].offset } { return errno.err, errno.einval }
		}
	}
	// User copies above may fault or wait for I/O. Only the owned table is
	// consulted below, while the publication lock every CLONE_THREAD attach
	// holds excludes a new sibling. Non-thread CLONE_VM copies the pagemap.
	process.threads_lock.acquire()
	defer { process.threads_lock.release() }
	if process.threads.len != 1 || katomic.load(&process.exiting) {
		return errno.err, errno.eperm
	}
	process.syscall_policy_lock.acquire()
	defer { process.syscall_policy_lock.release() }
	if process.syscall_policy != unsafe { nil } { return errno.err, errno.eperm }
	mmap.validate_syscall_pin_region(process.pagemap, policy.base, policy.length, pins, policy.count) or {
		return errno.err, errno.get()
	}
	process.syscall_policy = policy
	published = true
	katomic.store(mut &process.syscall_policy_mode, u32(action))
	return 0, 0
}

// instruction is the start of the actual SYSCALL/SVC, not its return PC. A
// process lock retains the immutable table through the bounded binary search.
pub fn syscall_origin_allowed(mut process Process, number u64, instruction u64) bool {
	if katomic.load(&process.syscall_policy_mode) == 0 { return true }
	process.syscall_policy_lock.acquire()
	defer { process.syscall_policy_lock.release() }
	mode := katomic.load(&process.syscall_policy_mode)
	if mode == 0 { return true }
	policy := process.syscall_policy
	mut valid := false
	if policy != unsafe { nil } && instruction >= policy.base
		&& instruction - policy.base < policy.length && number < syscall_pin_limit {
		pins := policy_pins(policy)
		mut lower := u32(0)
		mut upper := policy.count
		for lower < upper {
			middle := lower + (upper - lower) / 2
			pin := unsafe { pins[middle] }
			if number < pin.number { upper = middle }
			else if number > pin.number { lower = middle + 1 }
			else { valid = instruction - policy.base == pin.offset; break }
		}
	}
	if valid { return true }
	katomic.inc(mut &process.syscall_policy_violations)
	return mode != 2
}

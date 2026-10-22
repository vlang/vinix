// SPDX-License-Identifier: GPL-2.0-or-later
module proc

import errno
import katomic

// Linux nice values belong to tasks. Process.nice is the initial value for
// a fresh process; a task override must never change its siblings' weight.
pub fn nice_value(t &Thread) int {
	if katomic.load(&t.sched_has_nice_override) {
		// Nice is a signed Linux int, including when V's native int is wider
		// than the ARM64 atomic int load's 32-bit result.
		return int(i32(katomic.load(&t.sched_nice_override)))
	}
	return int(i32(katomic.load(&t.process.nice)))
}

pub fn thread_nice(tid int) ?int {
	if tid <= 0 || tid >= max_pid { errno.set(errno.esrch); return none }
	lock_table()
	defer { unlock_table() }
	t := threads_by_tid[tid]
	if t == unsafe { nil } { errno.set(errno.esrch); return none }
	if !mac_peer_allowed(current_thread().process, t.process) {
		errno.set(errno.eperm); return none
	}
	return nice_value(t)
}

pub fn set_thread_nice(tid int, wanted int) bool {
	if tid <= 0 || tid >= max_pid { errno.set(errno.esrch); return false }
	lock_table()
	defer { unlock_table() }
	mut t := threads_by_tid[tid]
	if t == unsafe { nil } { errno.set(errno.esrch); return false }
	caller := current_thread().process
	owner := t.process
	if !mac_peer_allowed(caller, owner) { errno.set(errno.eperm); return false }
	privileged := has_capability(caller, cap_sys_nice)
	if !privileged && caller.euid != owner.euid && caller.euid != owner.uid {
		errno.set(errno.eperm); return false
	}
	if wanted < nice_value(t) && !privileged
		&& !limit_allows(owner, rlimit_nice, u64(20 - wanted)) {
		errno.set(errno.eacces); return false
	}
	katomic.store(mut &t.sched_nice_override, wanted)
	katomic.store(mut &t.sched_has_nice_override, true)
	return true
}

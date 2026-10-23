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

// PRIO_PGRP and PRIO_USER choose the highest priority of every matching
// task, including nonleader threads. Keep table entries and their owners
// under the lock and return only a scalar snapshot.
pub fn aggregate_nice(local int, by_group bool) ?int {
	lock_table()
	defer { unlock_table() }
	caller := current_thread().process
	viewer := current_pid_namespace()
	group := if local == 0 { pgid_in(caller, viewer) } else { local }
	uid := if local == 0 { caller.uid } else { u32(local) }
	mut best := 20
	for tid := 1; tid < max_pid; tid++ {
		t := threads_by_tid[tid]
		if t == unsafe { nil } { continue }
		owner := t.process
		// Exit/exec can detach a thread before removing its TID. Such a
		// thread no longer belongs to a published user process.
		if owner == unsafe { nil } || voidptr(process_at(owner.pid)) != voidptr(owner)
			|| pid_in(owner, viewer) == 0 || tid_in(t, viewer) == 0 { continue }
		if by_group {
			if pgid_in(owner, viewer) != group { continue }
		} else if owner.uid != uid { continue }
		if !mac_peer_allowed(caller, owner) { errno.set(errno.eperm); return none }
		value := nice_value(t)
		if value < best { best = value }
	}
	if best == 20 { errno.set(errno.esrch); return none }
	return best
}

pub fn set_thread_nice(tid int, wanted int) bool {
	if tid <= 0 || tid >= max_pid { errno.set(errno.esrch); return false }
	lock_table()
	defer { unlock_table() }
	mut t := threads_by_tid[tid]
	if t == unsafe { nil } { errno.set(errno.esrch); return false }
	caller := current_thread().process
	code := apply_nice(mut t, wanted, caller)
	if code != 0 { errno.set(code); return false }
	return true
}

// Called with the process table locked. A group update keeps visiting
// matching tasks after a refusal, preserving successful partial updates.
fn apply_nice(mut t Thread, wanted int, caller &Process) u64 {
	owner := t.process
	if !mac_peer_allowed(caller, owner) { return errno.eperm }
	privileged := has_capability(caller, cap_sys_nice)
	if !privileged && caller.euid != owner.euid && caller.euid != owner.uid {
		return errno.eperm
	}
	if wanted < nice_value(t) && !privileged
		&& !limit_allows(owner, rlimit_nice, u64(20 - wanted)) {
		return errno.eacces
	}
	katomic.store(mut &t.sched_nice_override, wanted)
	katomic.store(mut &t.sched_has_nice_override, true)
	return 0
}

pub fn set_aggregate_nice(local int, by_group bool, wanted int) bool {
	lock_table()
	defer { unlock_table() }
	caller := current_thread().process
	viewer := current_pid_namespace()
	group := if local == 0 { pgid_in(caller, viewer) } else { local }
	uid := if local == 0 { caller.uid } else { u32(local) }
	mut result := u64(errno.esrch)
	for tid := 1; tid < max_pid; tid++ {
		mut t := threads_by_tid[tid]
		if t == unsafe { nil } { continue }
		owner := t.process
		if owner == unsafe { nil } || voidptr(process_at(owner.pid)) != voidptr(owner)
			|| pid_in(owner, viewer) == 0 || tid_in(t, viewer) == 0 { continue }
		if by_group {
			if pgid_in(owner, viewer) != group { continue }
		} else if owner.uid != uid { continue }
		code := apply_nice(mut t, wanted, caller)
		if code != 0 {
			result = code
		} else if result == errno.esrch {
			result = 0
		}
	}
	if result != 0 { errno.set(result); return false }
	return true
}

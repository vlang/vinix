// SPDX-License-Identifier: GPL-2.0-or-later
module proc

import errno

// ioprio_get(2) and ioprio_set(2), as Linux 6.12 answers them. Linux keeps an
// I/O priority in a task's I/O context, which a task first gets from
// ioprio_set, and which the default `none` block scheduler ignores; Vinix's
// block layer has no priority classes either. What is kept, inherited and
// reported is Linux's, so ionice and the programs that set their own priority
// see what they set. kcmp(KCMP_IO) compares the contexts.
const ioprio_class_shift = 13
const ioprio_class_none = 0
const ioprio_class_rt = 1
const ioprio_class_be = 2
const ioprio_class_idle = 3
const ioprio_who_process = 1
const ioprio_who_pgrp = 2
const ioprio_who_user = 3

fn ioprio_class(value int) int {
	return (value >> ioprio_class_shift) & 7
}

// Whether a priority's class is one a task can run at, as ioprio_valid().
fn ioprio_valid(value u16) bool {
	class := ioprio_class(int(value))
	return class > ioprio_class_none && class <= ioprio_class_idle
}

// A new thread or process gets a context of its own only when its creator
// had one with a valid class, which it copies (Linux's copy_io without
// CLONE_IO).
pub fn inherited_io_context(source &Thread) bool {
	return source.ioprio_context && ioprio_valid(source.ioprio_value)
}

pub fn inherited_io_priority(source &Thread) u16 {
	return if inherited_io_context(source) { source.ioprio_value } else { u16(0) }
}

// Exec keeps the task, and with it the context, whatever its class.
pub fn carry_io_context(mut replacement Thread, old &Thread) {
	replacement.ioprio_value = old.ioprio_value
	replacement.ioprio_context = old.ioprio_context
}

// Without a context, or with class NONE, a task's priority follows its CPU
// policy and nice value. ioprio_get reports this for groups and users.
fn effective_io_priority(t &Thread) int {
	if t.ioprio_context && ioprio_class(int(t.ioprio_value)) != ioprio_class_none {
		return int(t.ioprio_value)
	}
	class := match t.sched.policy {
		sched_idle { ioprio_class_idle }
		sched_fifo, sched_rr, sched_deadline { ioprio_class_rt }
		else { ioprio_class_be }
	}
	return (class << ioprio_class_shift) | ((nice_value(t) + 20) / 5)
}

// ioprio_check_cap(): RT needs CAP_SYS_NICE or CAP_SYS_ADMIN; NONE takes no
// level; classes past IDLE are invalid. Hint bits are accepted.
fn ioprio_check(caller &Process, value int) u64 {
	match ioprio_class(value) {
		ioprio_class_rt {
			if !has_capability(caller, cap_sys_nice) && !has_capability(caller, cap_sys_admin) {
				return errno.eperm
			}
		}
		ioprio_class_be, ioprio_class_idle {}
		ioprio_class_none {
			if value & 7 != 0 { return errno.einval }
		}
		else {
			return errno.einval
		}
	}
	return 0
}

// set_task_ioprio(), under the table lock: the target's real uid must be the
// caller's real or effective one, unless the caller has CAP_SYS_NICE.
fn apply_io_priority(mut t Thread, value u16, caller &Process) u64 {
	if !mac_peer_allowed(caller, t.process) { return errno.eperm }
	if !has_capability(caller, cap_sys_nice) && t.process.uid != caller.euid
		&& t.process.uid != caller.uid {
		return errno.eperm
	}
	t.ioprio_value = value
	t.ioprio_context = true
	return 0
}

// The thread a caller names, under the table lock; 0 is the caller.
fn ioprio_thread_locked(local int) &Thread {
	if local == 0 { return current_thread() }
	global := kernel_id_locked(local)
	if global <= 0 || global >= max_pid { return unsafe { nil } }
	t := threads_by_tid[global]
	if t == unsafe { nil } || t.process == unsafe { nil } { return unsafe { nil } }
	return t
}

// Whether thread `t` belongs to the group or user a PGRP/USER call names.
// Threads the caller's pid namespace cannot see are skipped, as Linux does.
fn ioprio_member_locked(t &Thread, viewer &Namespace, by_group bool, id int) bool {
	owner := t.process
	if owner == unsafe { nil } || voidptr(process_at(owner.pid)) != voidptr(owner)
		|| pid_in(owner, viewer) == 0 || tid_in(t, viewer) == 0 {
		return false
	}
	return if by_group { pgid_in(owner, viewer) == id } else { owner.uid == u32(id) }
}

pub fn syscall_ioprio_set(_ voidptr, which_word u64, who_word u64, value_word u64) (u64, u64) {
	// which, who and the priority are C ints: the low 32 bits of their
	// registers. The priority is checked before anything is looked up.
	which := int(i32(u32(which_word)))
	who := int(i32(u32(who_word)))
	value := int(i32(u32(value_word)))
	caller := current_thread().process
	check := ioprio_check(caller, value)
	if check != 0 { return errno.err, check }
	// An I/O context holds 16 bits.
	stored := u16(u32(value))
	lock_table()
	defer { unlock_table() }
	match which {
		ioprio_who_process {
			mut t := ioprio_thread_locked(who)
			if t == unsafe { nil } { return errno.err, errno.esrch }
			code := apply_io_priority(mut t, stored, caller)
			if code != 0 { return errno.err, code }
			return 0, 0
		}
		ioprio_who_pgrp, ioprio_who_user {
			viewer := current_pid_namespace()
			by_group := which == ioprio_who_pgrp
			// Linux sets uid `who` itself, so who 0 is root's tasks, even
			// though ioprio_get takes it to mean the caller's.
			id := if by_group && who == 0 { pgid_in(caller, viewer) } else { who }
			// The first refusal ends the walk; earlier tasks keep theirs.
			mut result := u64(errno.esrch)
			for tid := 1; tid < max_pid; tid++ {
				mut t := threads_by_tid[tid]
				if t == unsafe { nil } || !ioprio_member_locked(t, viewer, by_group, id) { continue }
				result = apply_io_priority(mut t, stored, caller)
				if result != 0 { break }
			}
			if result != 0 { return errno.err, result }
			return 0, 0
		}
		else {
			return errno.err, errno.einval
		}
	}
}

pub fn syscall_ioprio_get(_ voidptr, which_word u64, who_word u64) (u64, u64) {
	which := int(i32(u32(which_word)))
	who := int(i32(u32(who_word)))
	caller := current_thread().process
	lock_table()
	defer { unlock_table() }
	match which {
		ioprio_who_process {
			// The value as set, so a caller can tell an unset priority (0)
			// from one it chose.
			t := ioprio_thread_locked(who)
			if t == unsafe { nil } { return errno.err, errno.esrch }
			if !mac_peer_allowed(caller, t.process) { return errno.err, errno.eperm }
			if !t.ioprio_context { return 0, 0 }
			return u64(t.ioprio_value), 0
		}
		ioprio_who_pgrp, ioprio_who_user {
			viewer := current_pid_namespace()
			by_group := which == ioprio_who_pgrp
			id := if who != 0 { who } else if by_group { pgid_in(caller, viewer) } else { int(caller.uid) }
			// The best effective priority: the lowest value.
			mut best := -1
			for tid := 1; tid < max_pid; tid++ {
				t := threads_by_tid[tid]
				if t == unsafe { nil } || !ioprio_member_locked(t, viewer, by_group, id)
					|| !mac_peer_allowed(caller, t.process) { continue }
				value := effective_io_priority(t)
				if best < 0 || value < best { best = value }
			}
			if best < 0 { return errno.err, errno.esrch }
			return u64(best), 0
		}
		else {
			return errno.err, errno.einval
		}
	}
}

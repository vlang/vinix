// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Pid namespaces. The kernel knows every process and thread by one id, its
// pid or tid. A process in a pid namespace other than the initial one is also
// numbered by that namespace, from 1 for its init, and that number is the one
// it and everything else in the namespace see: getpid(), kill(), wait(),
// /proc. Processes outside a namespace cannot be seen from inside it and are
// numbered 0 there, as on Linux. Namespaces are one level deep here: one made
// inside another is numbered as if made in the initial namespace.
module proc

// Whether `ns` numbers its members itself.
pub fn numbers_own(ns &Namespace) bool {
	return ns != unsafe { nil } && !is_initial_namespace(ns)
}

// The pid namespace the calling process sees the world through.
pub fn current_pid_namespace() &Namespace {
	t := current_thread()
	if t == unsafe { nil } || t.process == unsafe { nil } {
		return unsafe { nil }
	}
	return t.process.numbered_in
}

// Whether `id` is still a group or session that a member of `ns` belongs to,
// so that the number must not be handed out again. Called with pid_lock held.
fn local_group_alive(ns &Namespace, id int) bool {
	for i := 1; i < max_pid; i++ {
		p := processes[i]
		if p == unsafe { nil } || voidptr(p.numbered_in) != voidptr(ns) {
			continue
		}
		if p.ns_pgid == id || p.ns_sid == id {
			return true
		}
	}
	return false
}

// Hand out the next free number in `ns` to the kernel id `id`, cycling as the
// kernel's own ids do. Called with pid_lock held; 0 if every number is taken.
fn allocate_local_id(mut ns Namespace, id int) int {
	for n := 0; n < max_pid - 1; n++ {
		candidate := (ns.next_id - 1 + n) % (max_pid - 1) + 1
		if candidate in ns.ids || local_group_alive(ns, candidate) {
			continue
		}
		ns.next_id = if candidate + 1 >= max_pid { 1 } else { candidate + 1 }
		ns.ids[candidate] = id
		return candidate
	}
	return 0
}

fn release_local_id(mut ns Namespace, local int) {
	if local > 0 {
		ns.ids.delete(local)
	}
}

// Number a new process in the pid namespace it has been put in. `parent` is
// the process that created it: a child in its creator's namespace inherits
// the numbers of its group and session, the first process of a new namespace
// belongs to none it can see.
pub fn number_process(mut process Process, parent &Process) {
	mut ns := process.ns.pid
	if !numbers_own(ns) {
		return
	}
	pid_lock.acquire()
	defer {
		pid_lock.release()
	}
	process.numbered_in = ns
	process.ns_pid = allocate_local_id(mut ns, process.pid)
	if parent != unsafe { nil } && voidptr(parent.numbered_in) == voidptr(ns) {
		process.ns_pgid = parent.ns_pgid
		process.ns_sid = parent.ns_sid
	} else {
		process.ns_pgid = 0
		process.ns_sid = 0
	}
}

// Number a thread: the first is known by its process's number, any other gets
// its own.
pub fn number_thread(mut t Thread, main bool) {
	process := t.process
	if process == unsafe { nil } || !numbers_own(process.numbered_in) {
		return
	}
	if main {
		t.ns_tid = process.ns_pid
		return
	}
	pid_lock.acquire()
	defer {
		pid_lock.release()
	}
	mut ns := process.numbered_in
	t.ns_tid = allocate_local_id(mut ns, t.tid)
}

// A process that has made itself a group or session leader: record what the
// namespace calls the group or session, which is its own number.
pub fn renumber_group(mut process Process) {
	if !numbers_own(process.numbered_in) {
		return
	}
	process.ns_pgid = if process.pgid == process.pid { process.ns_pid } else { process.ns_pgid }
	process.ns_sid = if process.sid == process.pid { process.ns_pid } else { process.ns_sid }
}

// The number `viewer` knows `p` by, 0 when it cannot see it.
pub fn pid_in(p &Process, viewer &Namespace) int {
	if p == unsafe { nil } {
		return 0
	}
	if !numbers_own(viewer) {
		return p.pid
	}
	if voidptr(p.numbered_in) == voidptr(viewer) {
		return p.ns_pid
	}
	return 0
}

pub fn tid_in(t &Thread, viewer &Namespace) int {
	if t == unsafe { nil } {
		return 0
	}
	if !numbers_own(viewer) {
		return t.tid
	}
	if t.process != unsafe { nil } && voidptr(t.process.numbered_in) == voidptr(viewer) {
		return t.ns_tid
	}
	return 0
}

pub fn pgid_in(p &Process, viewer &Namespace) int {
	if !numbers_own(viewer) {
		return p.pgid
	}
	if voidptr(p.numbered_in) == voidptr(viewer) {
		return p.ns_pgid
	}
	return 0
}

pub fn sid_in(p &Process, viewer &Namespace) int {
	if !numbers_own(viewer) {
		return p.sid
	}
	if voidptr(p.numbered_in) == voidptr(viewer) {
		return p.ns_sid
	}
	return 0
}

// The number the caller's own namespace gives it: getpid().
pub fn own_pid(p &Process) int {
	return pid_in(p, p.numbered_in)
}

pub fn own_tid(t &Thread) int {
	if t.process == unsafe { nil } {
		return t.tid
	}
	return tid_in(t, t.process.numbered_in)
}

// The kernel id of whatever `viewer` numbers `local`, or 0. Called with
// pid_lock held.
fn global_id_in(viewer &Namespace, local int) int {
	if !numbers_own(viewer) {
		return local
	}
	if local <= 0 {
		return 0
	}
	return viewer.ids[local] or { 0 }
}

// The process `viewer` calls `local`, or nil. The caller holds the table lock,
// as for process_at().
pub fn process_in(viewer &Namespace, local int) &Process {
	p := process_at(global_id_in(viewer, local))
	if p == unsafe { nil } || (numbers_own(viewer) && voidptr(p.numbered_in) != voidptr(viewer)) {
		return unsafe { nil }
	}
	return p
}

// The kernel's id for the process `viewer` calls `local`, or 0.
pub fn pid_from(viewer &Namespace, local int) int {
	lock_table()
	defer {
		unlock_table()
	}
	p := process_in(viewer, local)
	if p == unsafe { nil } {
		return 0
	}
	return p.pid
}

// The thread `viewer` calls `local`, pinned as get_thread() pins, or nil.
pub fn thread_in(viewer &Namespace, local int) &Thread {
	if !numbers_own(viewer) {
		return get_thread(local)
	}
	pid_lock.acquire()
	global := global_id_in(viewer, local)
	pid_lock.release()
	t := get_thread(global)
	if t == unsafe { nil } {
		return t
	}
	if t.process == unsafe { nil } || voidptr(t.process.numbered_in) != voidptr(viewer) {
		unpin_thread(t)
		return unsafe { nil }
	}
	return t
}

// The kernel's id for a process group or session `viewer` calls `local`, 0 if
// it has none. Its leader may have gone; its members keep the number.
pub fn group_from(viewer &Namespace, local int) int {
	if !numbers_own(viewer) {
		return local
	}
	lock_table()
	defer {
		unlock_table()
	}
	for i := 1; i < max_pid; i++ {
		p := processes[i]
		if p == unsafe { nil } || voidptr(p.numbered_in) != voidptr(viewer) {
			continue
		}
		if p.ns_pgid == local {
			return p.pgid
		}
		if p.ns_sid == local {
			return p.sid
		}
	}
	return 0
}

// A group or session id the kernel knows, as `viewer` numbers it: through any
// member of it that `viewer` can see.
pub fn group_in(viewer &Namespace, global int) int {
	if !numbers_own(viewer) || global <= 0 {
		return global
	}
	lock_table()
	defer {
		unlock_table()
	}
	for i := 1; i < max_pid; i++ {
		p := processes[i]
		if p == unsafe { nil } || voidptr(p.numbered_in) != voidptr(viewer) {
			continue
		}
		if p.pgid == global {
			return p.ns_pgid
		}
		if p.sid == global {
			return p.ns_sid
		}
	}
	return 0
}

// Give back the numbers a reaped process and its main thread held. Called with
// pid_lock held.
fn release_process_number(p &Process) {
	if p == unsafe { nil } || !numbers_own(p.numbered_in) {
		return
	}
	mut ns := p.numbered_in
	release_local_id(mut ns, p.ns_pid)
}

// Give back a thread's own number, unless it is its process's. Called with
// pid_lock held.
fn release_thread_number(t &Thread) {
	if t == unsafe { nil } || t.process == unsafe { nil } || !numbers_own(t.process.numbered_in) {
		return
	}
	if t.ns_tid == t.process.ns_pid {
		return
	}
	mut ns := t.process.numbered_in
	release_local_id(mut ns, t.ns_tid)
}

// The kernel's id for a pid or tid the caller names, as a syscall taking one
// needs it. 0, "the caller", stays 0; a number the caller's namespace has not
// handed out becomes max_pid, which every lookup already refuses with ESRCH.
pub fn kernel_id(local int) int {
	viewer := current_pid_namespace()
	if !numbers_own(viewer) || local <= 0 {
		return local
	}
	pid_lock.acquire()
	defer {
		pid_lock.release()
	}
	global := global_id_in(viewer, local)
	return if global > 0 { global } else { max_pid }
}

// A kernel pid as the caller's namespace numbers it, 0 if it cannot see it.
pub fn pid_seen_by_caller(global int) int {
	viewer := current_pid_namespace()
	if !numbers_own(viewer) {
		return global
	}
	lock_table()
	defer {
		unlock_table()
	}
	return pid_in(process_at(global), viewer)
}

// The numbers `viewer` gives the threads with kernel ids `tids`, 0 for any it
// cannot see or that has gone.
pub fn thread_numbers(tids []int, viewer &Namespace) []int {
	mut numbers := []int{len: tids.len}
	pid_lock.acquire()
	defer {
		pid_lock.release()
	}
	for i, tid in tids {
		if tid <= 0 || tid >= max_pid {
			continue
		}
		numbers[i] = tid_in(threads_by_tid[tid], viewer)
	}
	return numbers
}

// Whether any process, a zombie included, is still numbered by `ns`.
pub fn namespace_has_members(ns &Namespace) bool {
	lock_table()
	defer {
		unlock_table()
	}
	for i := 1; i < max_pid; i++ {
		p := processes[i]
		if p != unsafe { nil } && voidptr(p.numbered_in) == voidptr(ns) {
			return true
		}
	}
	return false
}

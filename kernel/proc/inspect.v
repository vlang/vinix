// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module proc

import errno
import memory

// Capabilities in a new user namespace never grant inspection of its parent.
// Vinix currently models user namespaces as identities without a parent tree.
fn inspection_capable(caller &Process, target &Process, permitted bool) bool {
	if !is_initial_namespace(caller.ns.user)
		&& voidptr(caller.ns.user) != voidptr(target.ns.user) {
		return false
	}
	mask := if permitted { caller.caps.permitted } else { caller.caps.effective }
	return mask & (u64(1) << cap_sys_ptrace) != 0
}

fn inspection_allowed(caller &Process, target &Process, real_creds bool) bool {
	if !mac_peer_allowed(caller, target) { return false }
	if voidptr(caller) == voidptr(target) || inspection_capable(caller, target, real_creds) {
		return true
	}
	if dumpability(target) != 1 || voidptr(caller.ns.user) != voidptr(target.ns.user) {
		return false
	}
	uid := if real_creds { caller.uid } else { caller.euid }
	gid := if real_creds { caller.gid } else { caller.egid }
	caps := if real_creds { caller.caps.permitted } else { caller.caps.effective }
	return target.uid == uid && target.euid == uid && target.suid == uid
		&& target.gid == gid && target.egid == gid && target.sgid == gid
		&& target.caps.permitted & ~caps == 0
}

// Whether the calling process may read where process `pid` keeps things: its
// mappings and its auxiliary vector, in /proc/<pid>/maps, smaps and auxv.
// Every user could read them for every process, which handed out each
// address the randomization of its program, libraries, stack and heap had
// picked to anyone wanting to attack it. As Linux's ptrace check for reading
// has it, they are for the process itself, for a process whose user and group
// IDs are all the caller's effective ones -- not one that changed them, as a
// daemon dropping root does -- and for a caller with CAP_SYS_PTRACE.
pub fn may_inspect(pid int) bool {
	lock_table()
	defer {
		unlock_table()
	}
	return may_inspect_locked(process_at(pid))
}

// may_inspect() for a process looked up with the table locked, as the text
// of those files is made: checked again there, a pid that changed hands
// since the read began does not hand over its new owner's layout.
pub fn may_inspect_locked(target &Process) bool {
	if target == unsafe { nil } {
		return false
	}
	current := current_thread().process
	return inspection_allowed(current, target, false)
}

pub struct ProcessInspection {
pub:
	pagemap &memory.Pagemap
	// Remote faults lack stable mapping-range and cgroup charging lifetimes.
	fault_missing bool
}

// process_vm_* uses Linux's REALCREDS access mode rather than /proc's effective
// credentials. Retain only the map, so neither an exiting Process nor a dying
// Thread is used after the table lock is released. The pid can name any thread.
pub fn inspect_pagemap(local_pid int) ?ProcessInspection {
	lock_table()
	defer { unlock_table() }
	caller := current_thread().process
	pid := global_id_in(caller.numbered_in, local_pid)
	if pid <= 0 || pid >= max_pid {
		errno.set(errno.esrch)
		return none
	}
	mut target := processes[pid]
	if target == unsafe { nil } {
		t := threads_by_tid[pid]
		if t != unsafe { nil } {
			target = t.process
		}
	}
	if target == unsafe { nil } || target.pid <= 0 || target.exiting
		|| target.pagemap == unsafe { nil }
		|| (numbers_own(caller.numbered_in)
			&& voidptr(target.numbered_in) != voidptr(caller.numbered_in)) {
		errno.set(errno.esrch)
		return none
	}
	if !inspection_allowed(caller, target, true) {
		errno.set(errno.eperm)
		return none
	}
	mut pagemap := target.pagemap
	pagemap.l.acquire()
	pagemap.inspection_refs++
	pagemap.l.release()
	return ProcessInspection{
		pagemap:       pagemap
		fault_missing: voidptr(target) == voidptr(caller)
	}
}

// Allocation call chains expose kernel addresses and the global tracker can
// be reset. Namespace root and confined domains cannot operate this facility.
pub fn may_read_kernel_diagnostics() bool {
	p := current_thread().process
	return mac_trusted() && p.euid == 0 && is_initial_namespace(p.ns.user)
		&& has_capability(p, cap_sys_admin)
}

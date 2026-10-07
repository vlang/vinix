// SPDX-License-Identifier: GPL-2.0-or-later
module proc

import errno
import katomic

// Group/session identifiers and parent relationships are changed and read
// together under the process-table lock. No borrowed process survives it.
pub fn set_process_group(pid int, pgid int) (u64, u64) {
	if pid < 0 || pgid < 0 { return errno.err, errno.einval }
	caller := current_thread().process
	mut orphan_change := unsafe { &OrphanChange(C.vinix_stack_alloc(sizeof(OrphanChange))) }
	unsafe { *orphan_change = OrphanChange{} }
	defer { dispatch_job_orphan_change(mut orphan_change) }
	lock_table()
	defer { unlock_table() }
	mut target := if pid == 0 { caller } else { process_in(caller.numbered_in, pid) }
	if target == unsafe { nil } || target.exiting { return errno.err, errno.esrch }
	if !mac_peer_allowed(caller, target) { return errno.err, errno.eperm }
	if voidptr(target) != voidptr(caller) && target.ppid != caller.pid { return errno.err, errno.esrch }
	if voidptr(target) != voidptr(caller) && katomic.load(&target.did_exec) != 0 { return errno.err, errno.eacces }
	if target.sid != caller.sid || target.sid == target.pid { return errno.err, errno.eperm }
	local := if pgid == 0 { pid_in(target, caller.numbered_in) } else { pgid }
	mut group := if local == pid_in(target, caller.numbered_in) { target.pid } else { 0 }
	if group == 0 {
		for id := 1; id < max_pid; id++ {
			member := process_at(id)
			if member == unsafe { nil } || member.exiting { continue }
			if numbers_own(caller.numbered_in) {
				if voidptr(member.numbered_in) != voidptr(caller.numbered_in) || member.ns_pgid != local { continue }
			} else if member.pgid != local { continue }
			if member.sid != caller.sid { return errno.err, errno.eperm }
			group = member.pgid
			break
		}
	}
	if group == 0 { return errno.err, errno.eperm }
	if group == target.pgid { return 0, 0 }
	prepare_job_orphan_change_locked(mut orphan_change, target, group)
	target.pgid = group
	if numbers_own(target.numbered_in) { target.ns_pgid = local }
	filter_job_orphan_change_locked(mut orphan_change)
	return 0, 0
}

pub fn get_process_group(pid int) (u64, u64) {
	if pid < 0 { return errno.err, errno.einval }
	caller := current_thread().process
	lock_table()
	defer { unlock_table() }
	target := if pid == 0 { caller } else { process_in(caller.numbered_in, pid) }
	if target == unsafe { nil } { return errno.err, errno.esrch }
	if !mac_peer_allowed(caller, target) { return errno.err, errno.eperm }
	return u64(pgid_in(target, caller.numbered_in)), 0
}

pub fn create_session() (u64, u64) {
	mut caller := current_thread().process
	mut orphan_change := unsafe { &OrphanChange(C.vinix_stack_alloc(sizeof(OrphanChange))) }
	unsafe { *orphan_change = OrphanChange{} }
	defer { dispatch_job_orphan_change(mut orphan_change) }
	lock_table()
	defer { unlock_table() }
	for id := 1; id < max_pid; id++ {
		member := process_at(id)
		if member != unsafe { nil } && member.pgid == caller.pid { return errno.err, errno.eperm }
	}
	prepare_job_orphan_change_locked(mut orphan_change, caller, caller.pid)
	caller.sid = caller.pid
	caller.pgid = caller.pid
	caller.tty_session = 0
	caller.tty_device = 0
	renumber_group(mut caller)
	filter_job_orphan_change_locked(mut orphan_change)
	return u64(own_pid(caller)), 0
}

pub fn get_process_session(pid int) (u64, u64) {
	if pid < 0 { return errno.err, errno.einval }
	caller := current_thread().process
	lock_table()
	defer { unlock_table() }
	target := if pid == 0 { caller } else { process_in(caller.numbered_in, pid) }
	if target == unsafe { nil } { return errno.err, errno.esrch }
	if !mac_peer_allowed(caller, target) { return errno.err, errno.eperm }
	return u64(sid_in(target, caller.numbered_in)), 0
}

// SPDX-License-Identifier: GPL-2.0-or-later
module userland

import errno
import katomic
import proc

// Device callers snapshot terminal state and release their locks first. A
// group is orphaned when no live member has a parent outside the group but
// inside the same session. The table lock protects every process inspected.
pub fn orphaned_job_group(pgid int, sid int) bool {
	return proc.job_group_orphaned(pgid, sid)
}

// A rejected operation has no side effects. ERESTARTSYS lets default stop
// resume the operation, while a caught handler without SA_RESTART sees EINTR.
pub fn terminal_job_check(device u64, session int, foreground int, signal int) u64 {
	caller_thread := proc.current_thread()
	process := caller_thread.process
	proc.lock_table()
	controlled := session != 0 && process.tty_device == device && process.tty_session == session && process.sid == session
	group := process.pgid
	sid := process.sid
	// A sibling may change this process's group/session after the snapshot.
	// Keep these scalar identities reserved through orphan checks and delivery.
	proc.retain_job_identity_locked(group, sid)
	proc.unlock_table()
	defer { proc.release_job_identity(group, sid) }
	if !controlled || foreground == 0 || group == foreground { return 0 }
	blocked := katomic.load(&caller_thread.masked_signals) & (u64(1) << (signal - 1)) != 0
	ignored := caller_thread.sigactions[signal].sa_sigaction == sig_ign
	if blocked || ignored {
		return if signal == sigttin { errno.eio } else { 0 }
	}
	if orphaned_job_group(group, sid) { return errno.eio }
	signal_group(group, sid, signal)
	return errno.erestartsys
}

// Resolve and validate a user-visible group while its members stay protected.
// A pty master may query state, but only the controlling session may set it.
pub fn terminal_foreground_group(device u64, session int, local int) ?int {
	process := proc.current_thread().process
	proc.lock_table()
	defer { proc.unlock_table() }
	if session == 0 || process.sid != session || process.tty_session != session || process.tty_device != device {
		errno.set(errno.enotty)
		return none
	}
	if local < 0 { errno.set(errno.einval); return none }
	mut group := 0
	for id := 1; id < proc.max_pid; id++ {
		member := proc.process_at(id)
		if member == unsafe { nil } || member.exiting { continue }
		if proc.numbers_own(process.numbered_in) {
			if voidptr(member.numbered_in) != voidptr(process.numbered_in) || member.ns_pgid != local { continue }
		} else if member.pgid != local { continue }
		if member.sid != session { errno.set(errno.eperm); return none }
		group = member.pgid
	}
	if group == 0 { errno.set(errno.esrch); return none }
	// The caller releases this temporary hold after publishing device state
	// or rejecting a changed terminal. Its device then owns a separate hold.
	proc.retain_job_identity_locked(group, session)
	return group
}

pub fn terminal_is_controlling(device u64, session int) bool {
	return proc.controls_terminal(device, session)
}

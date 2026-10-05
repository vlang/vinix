// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module proc

type SessionExitHook = fn (u64, int)

__global (session_exit_hook voidptr)

pub fn register_session_exit_hook(hook voidptr) { session_exit_hook = hook }

// Only the teardown owner calls this, before leaving its Process. The device
// callback takes its state lock, then detaches matching process identities.
pub fn notify_session_exit(process &Process) {
	lock_table()
	device := if process.pid == process.sid && process.tty_session == process.sid { process.tty_device } else { u64(0) }
	session := process.sid
	unlock_table()
	if device != 0 && session_exit_hook != unsafe { nil } {
		hook := unsafe { SessionExitHook(session_exit_hook) }
		hook(device, session)
	}
}

pub fn detach_terminal_members(device u64, session int) {
	if device == 0 || session == 0 { return }
	lock_table()
	for id := 1; id < max_pid; id++ {
		mut member := process_at(id)
		if member != unsafe { nil } && member.tty_device == device && member.tty_session == session {
			member.tty_session = 0
			member.tty_device = 0
		}
	}
	unlock_table()
}

// Terminal identity is a permanent, unique device number, never a borrowed
// PtyPair pointer. Session identity alone cannot distinguish terminals that
// were detached and replaced within the same session.
pub fn inherit_job_identity(mut child Process, parent &Process) {
	lock_table()
	child.ppid = parent.pid
	child.pgid = parent.pgid
	child.sid = parent.sid
	child.ns_pgid = parent.ns_pgid
	child.ns_sid = parent.ns_sid
	child.inherited_job_namespace = if parent.numbered_in != unsafe { nil } { parent.numbered_in.id } else { u64(0) }
	child.tty_session = parent.tty_session
	child.tty_device = parent.tty_device
	unlock_table()
}

pub fn claim_controlling_terminal(device u64) bool {
	mut caller := current_thread().process
	lock_table()
	defer { unlock_table() }
	if caller.pid != caller.sid || device == 0
		|| (caller.tty_device != 0 && caller.tty_device != device) { return false }
	caller.tty_device = device
	caller.tty_session = caller.sid
	return true
}

// The caller holds the device state lock; membership changes are atomic with
// other terminal claims and fork snapshots under the process-table lock.
pub fn release_controlling_terminal(device u64) bool {
	mut caller := current_thread().process
	lock_table()
	defer { unlock_table() }
	if caller.tty_device != device || caller.tty_session == 0 { return false }
	if caller.pid == caller.sid {
		for id := 1; id < max_pid; id++ {
			mut member := process_at(id)
			if member != unsafe { nil } && member.tty_device == device && member.tty_session == caller.sid {
				member.tty_session = 0
				member.tty_device = 0
			}
		}
	} else {
		caller.tty_session = 0
		caller.tty_device = 0
	}
	return true
}

pub fn controls_terminal(device u64, session int) bool {
	caller := current_thread().process
	lock_table()
	result := session != 0 && caller.sid == session && caller.tty_session == session && caller.tty_device == device
	unlock_table()
	return result
}

pub fn controlling_terminal_identity() (u64, int) {
	caller := current_thread().process
	lock_table()
	device := caller.tty_device
	session := caller.tty_session
	unlock_table()
	return device, session
}

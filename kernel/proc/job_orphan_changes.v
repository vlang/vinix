// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module proc

import katomic

// One caller-owned 8-KiB stack descriptor spans capture, identity mutation,
// filtering and delivery. It carries global IDs, never borrowed Processes.
// ID holds keep an emptied group/session from being recycled before delivery.
pub struct OrphanChange {
pub mut:
	sid    int
	held   bool
	groups [1024]u64
}

type JobOrphanHook = fn (int, int)

__global (
	job_identity_holds [65536]u32
	job_orphan_hook voidptr
)

pub fn register_job_orphan_hook(hook voidptr) {
	job_orphan_hook = hook
}

// A device owns these scalar IDs while its foreground/session state names
// them. Temporary delivery holds outlive the device lock, without retaining
// any Process or allowing an empty group's number to be recycled.
pub fn retain_job_identity_locked(group int, sid int) {
	if group > 0 && group < max_pid { job_identity_holds[group]++ }
	if sid > 0 && sid < max_pid { job_identity_holds[sid]++ }
}

fn release_job_identity_locked(group int, sid int) {
	if group > 0 && group < max_pid {
		assert job_identity_holds[group] != 0
		job_identity_holds[group]--
	}
	if sid > 0 && sid < max_pid {
		assert job_identity_holds[sid] != 0
		job_identity_holds[sid]--
	}
}

pub fn retain_job_identity(group int, sid int) {
	pid_lock.acquire()
	retain_job_identity_locked(group, sid)
	pid_lock.release()
}

pub fn release_job_identity(group int, sid int) {
	pid_lock.acquire()
	release_job_identity_locked(group, sid)
	pid_lock.release()
}

pub fn replace_job_identity(old_group int, old_sid int, group int, sid int) {
	pid_lock.acquire()
	retain_job_identity_locked(group, sid)
	release_job_identity_locked(old_group, old_sid)
	pid_lock.release()
}

fn hold_orphan_group(mut change OrphanChange, group int) {
	if group <= 0 || group >= max_pid { return }
	index := group / 64
	bit := u64(1) << (group % 64)
	if change.groups[index] & bit != 0 { return }
	change.groups[index] |= bit
	job_identity_holds[group]++
}

// Caller holds pid_lock. Capture before changing exiting, pgid, sid or ppid.
// A parent's move may orphan any of its children's groups, as well as its own
// old/new groups. The old SID bounds every group affected by this mutation.
pub fn prepare_job_orphan_change_locked(mut change OrphanChange, target &Process, new_group int) {
	if target.sid <= 0 || target.sid >= max_pid { return }
	change.sid = target.sid
	change.held = true
	job_identity_holds[change.sid]++
	if !job_group_orphaned_locked(target.pgid, change.sid) {
		hold_orphan_group(mut change, target.pgid)
	}
	if new_group != target.pgid && !job_group_orphaned_locked(new_group, change.sid) {
		hold_orphan_group(mut change, new_group)
	}
	if target.pid == 1 || target.exiting { return }
	for id := 1; id < max_pid; id++ {
		member := processes[id]
		if member != unsafe { nil } && !member.exiting && member.ppid == target.pid
			&& member.sid == change.sid && member.pgid != target.pgid {
			// The live non-init parent is outside this group in the same SID,
			// so it is non-orphaned without another complete table walk.
			hold_orphan_group(mut change, member.pgid)
		}
	}
}

fn job_group_stopped_locked(group int, sid int) bool {
	for id := 1; id < max_pid; id++ {
		member := processes[id]
		if member != unsafe { nil } && !member.exiting && member.pgid == group
			&& member.sid == sid && katomic.load(&member.job_stop_signal) != 0 {
			return true
		}
	}
	return false
}

// Caller holds pid_lock after the identity mutation. Exit callers filter only
// after reparenting, so a same-session subreaper may keep a group non-orphaned.
pub fn filter_job_orphan_change_locked(mut change OrphanChange) {
	if !change.held { return }
	for group := 1; group < max_pid; group++ {
		index := group / 64
		bit := u64(1) << (group % 64)
		if change.groups[index] & bit == 0 { continue }
		if !job_group_stopped_locked(group, change.sid)
			|| !job_group_orphaned_locked(group, change.sid) {
			change.groups[index] &= ~bit
			job_identity_holds[group]--
		}
	}
}

// Caller has released all table, child-list, thread and device locks. Holds
// remain until both signals have been queued; even an empty group cannot be
// confused with a newly allocated process/session bearing the same number.
pub fn dispatch_job_orphan_change(mut change OrphanChange) {
	if !change.held { return }
	if job_orphan_hook != unsafe { nil } {
		hook := unsafe { JobOrphanHook(job_orphan_hook) }
		for group := 1; group < max_pid; group++ {
			if change.groups[group / 64] & (u64(1) << (group % 64)) != 0 {
				hook(group, change.sid)
			}
		}
	}
	discard_job_orphan_change(mut change)
}

// Release an abandoned snapshot without delivering. Failed mutation callers
// can use this after dropping pid_lock; a descriptor never prepared is a no-op.
pub fn discard_job_orphan_change(mut change OrphanChange) {
	if !change.held { return }
	pid_lock.acquire()
	for group := 1; group < max_pid; group++ {
		bit := u64(1) << (group % 64)
		if change.groups[group / 64] & bit != 0 {
			job_identity_holds[group]--
			change.groups[group / 64] &= ~bit
		}
	}
	job_identity_holds[change.sid]--
	change.held = false
	pid_lock.release()
}

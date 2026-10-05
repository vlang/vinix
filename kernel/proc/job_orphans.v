// SPDX-License-Identifier: GPL-2.0-or-later
module proc

// Group/session identities are global kernel numbers. The table lock owns
// every inspected Process; none of its pointers escapes this snapshot.
pub fn job_group_orphaned(pgid int, sid int) bool {
	pid_lock.acquire()
	defer { pid_lock.release() }
	return job_group_orphaned_locked(pgid, sid)
}

pub fn job_group_orphaned_locked(pgid int, sid int) bool {
	for id := 1; id < max_pid; id++ {
		member := processes[id]
		if member == unsafe { nil } || member.exiting || member.pgid != pgid
			|| member.sid != sid || member.ppid <= 1 || member.ppid >= max_pid {
			continue
		}
		parent := processes[member.ppid]
		if parent != unsafe { nil } && !parent.exiting && parent.sid == sid
			&& parent.pgid != pgid {
			return false
		}
	}
	return true
}

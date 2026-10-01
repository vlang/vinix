// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module proc

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
	if voidptr(current) == voidptr(target) || has_capability(current, cap_sys_ptrace) {
		return true
	}
	return target.uid == current.euid && target.euid == current.euid
		&& target.suid == current.euid && target.gid == current.egid
		&& target.egid == current.egid && target.sgid == current.egid
}

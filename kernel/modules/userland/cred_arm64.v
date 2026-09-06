module userland

// Credentials and the session/process-group calls that go with them. All of
// these used to return 0 without touching anything, so a program could not tell
// whether it was root, and setuid() reported success while changing nothing.

import errno
import proc
import usercopy

// The most supplementary groups a process may hold. Linux's default is 65536;
// this is a bound the kernel can carry without an allocation growing without
// limit, and far past anything a Vinix userland asks for.
const max_groups = 32

fn current_process() &proc.Process {
	return proc.current_thread().process
}

// Whether the caller may hand itself arbitrary credentials.
fn is_privileged(process &proc.Process) bool {
	return process.euid == 0
}

pub fn syscall_getuid(_ voidptr) (u64, u64) {
	return u64(current_process().uid), 0
}

pub fn syscall_geteuid(_ voidptr) (u64, u64) {
	return u64(current_process().euid), 0
}

pub fn syscall_getgid(_ voidptr) (u64, u64) {
	return u64(current_process().gid), 0
}

pub fn syscall_getegid(_ voidptr) (u64, u64) {
	return u64(current_process().egid), 0
}

// setuid(2). Privileged callers set all three ids; everyone else may only move
// the effective id between the real and the saved one, which is what lets a
// program drop privilege temporarily and take it back.
pub fn syscall_setuid(_ voidptr, uid u32) (u64, u64) {
	mut process := current_process()

	if is_privileged(process) {
		process.uid = uid
		process.euid = uid
		process.suid = uid
		return 0, 0
	}

	if uid != process.uid && uid != process.suid {
		return errno.err, errno.eperm
	}

	process.euid = uid
	return 0, 0
}

pub fn syscall_setgid(_ voidptr, gid u32) (u64, u64) {
	mut process := current_process()

	if is_privileged(process) {
		process.gid = gid
		process.egid = gid
		process.sgid = gid
		return 0, 0
	}

	if gid != process.gid && gid != process.sgid {
		return errno.err, errno.eperm
	}

	process.egid = gid
	return 0, 0
}

// An argument of -1 means "leave this one alone".
fn unchanged(id u32) bool {
	return id == u32(0xffffffff)
}

pub fn syscall_setreuid(_ voidptr, ruid u32, euid u32) (u64, u64) {
	mut process := current_process()
	privileged := is_privileged(process)

	if !unchanged(ruid) {
		if !privileged && ruid != process.uid && ruid != process.euid {
			return errno.err, errno.eperm
		}
	}
	if !unchanged(euid) {
		if !privileged && euid != process.uid && euid != process.euid
			&& euid != process.suid {
			return errno.err, errno.eperm
		}
	}

	changed_real := !unchanged(ruid)
	if changed_real {
		process.uid = ruid
	}
	if !unchanged(euid) {
		process.euid = euid
	}
	// Setting the real id, or setting the effective id to something other than
	// the real one, fixes the saved id at the new effective id.
	if changed_real || (!unchanged(euid) && euid != process.uid) {
		process.suid = process.euid
	}

	return 0, 0
}

pub fn syscall_setregid(_ voidptr, rgid u32, egid u32) (u64, u64) {
	mut process := current_process()
	privileged := is_privileged(process)

	if !unchanged(rgid) {
		if !privileged && rgid != process.gid && rgid != process.egid {
			return errno.err, errno.eperm
		}
	}
	if !unchanged(egid) {
		if !privileged && egid != process.gid && egid != process.egid
			&& egid != process.sgid {
			return errno.err, errno.eperm
		}
	}

	changed_real := !unchanged(rgid)
	if changed_real {
		process.gid = rgid
	}
	if !unchanged(egid) {
		process.egid = egid
	}
	if changed_real || (!unchanged(egid) && egid != process.gid) {
		process.sgid = process.egid
	}

	return 0, 0
}

// setresuid(2). Syscall 147, which the table used to point at setregid — a
// three-argument call landing in a two-argument handler.
pub fn syscall_setresuid(_ voidptr, ruid u32, euid u32, suid u32) (u64, u64) {
	mut process := current_process()

	if !is_privileged(process) {
		for wanted in [ruid, euid, suid] {
			if unchanged(wanted) {
				continue
			}
			if wanted != process.uid && wanted != process.euid && wanted != process.suid {
				return errno.err, errno.eperm
			}
		}
	}

	if !unchanged(ruid) {
		process.uid = ruid
	}
	if !unchanged(euid) {
		process.euid = euid
	}
	if !unchanged(suid) {
		process.suid = suid
	}

	return 0, 0
}

pub fn syscall_setresgid(_ voidptr, rgid u32, egid u32, sgid u32) (u64, u64) {
	mut process := current_process()

	if !is_privileged(process) {
		for wanted in [rgid, egid, sgid] {
			if unchanged(wanted) {
				continue
			}
			if wanted != process.gid && wanted != process.egid && wanted != process.sgid {
				return errno.err, errno.eperm
			}
		}
	}

	if !unchanged(rgid) {
		process.gid = rgid
	}
	if !unchanged(egid) {
		process.egid = egid
	}
	if !unchanged(sgid) {
		process.sgid = sgid
	}

	return 0, 0
}

pub fn syscall_getresuid(_ voidptr, ruid u64, euid u64, suid u64) (u64, u64) {
	process := current_process()

	if !usercopy.copy_to_user(ruid, voidptr(&process.uid), sizeof(u32))
		|| !usercopy.copy_to_user(euid, voidptr(&process.euid), sizeof(u32))
		|| !usercopy.copy_to_user(suid, voidptr(&process.suid), sizeof(u32)) {
		return errno.err, errno.efault
	}

	return 0, 0
}

pub fn syscall_getresgid(_ voidptr, rgid u64, egid u64, sgid u64) (u64, u64) {
	process := current_process()

	if !usercopy.copy_to_user(rgid, voidptr(&process.gid), sizeof(u32))
		|| !usercopy.copy_to_user(egid, voidptr(&process.egid), sizeof(u32))
		|| !usercopy.copy_to_user(sgid, voidptr(&process.sgid), sizeof(u32)) {
		return errno.err, errno.efault
	}

	return 0, 0
}

// getgroups(size, list). A size of zero asks only for the count, which is how
// a caller sizes its buffer.
pub fn syscall_getgroups(_ voidptr, size int, list u64) (u64, u64) {
	process := current_process()

	if size < 0 {
		return errno.err, errno.einval
	}

	count := process.groups.len

	if size == 0 {
		return u64(count), 0
	}
	if size < count {
		return errno.err, errno.einval
	}
	if count == 0 {
		return 0, 0
	}
	if list == 0 {
		return errno.err, errno.efault
	}

	if !usercopy.copy_to_user(list, unsafe { voidptr(&process.groups[0]) }, u64(count) * sizeof(u32)) {
		return errno.err, errno.efault
	}

	return u64(count), 0
}

// setgroups(size, list).
pub fn syscall_setgroups(_ voidptr, size int, list u64) (u64, u64) {
	mut process := current_process()

	if size < 0 || size > max_groups {
		return errno.err, errno.einval
	}
	if !is_privileged(process) {
		return errno.err, errno.eperm
	}

	mut incoming := []u32{len: size}
	if size > 0 {
		if list == 0 {
			unsafe { incoming.free() }
			return errno.err, errno.efault
		}
		if !usercopy.copy_from_user(unsafe { voidptr(&incoming[0]) }, list, u64(size) * sizeof(u32)) {
			unsafe { incoming.free() }
			return errno.err, errno.efault
		}
	}

	unsafe { process.groups.free() }
	process.groups = incoming

	return 0, 0
}

// ── sessions and process groups ──────────────────────────────────────────────

// setsid(2). The caller becomes the leader of a new session and of a new
// process group within it, and loses any controlling terminal it had. A
// process group leader cannot do this: its group would end up split across
// two sessions.
pub fn syscall_setsid(_ voidptr) (u64, u64) {
	mut process := current_process()

	if process.pgid == process.pid {
		return errno.err, errno.eperm
	}

	process.sid = process.pid
	process.pgid = process.pid
	process.tty_session = 0

	return u64(process.pid), 0
}

// getsid(pid). Zero means the caller.
pub fn syscall_getsid(_ voidptr, pid int) (u64, u64) {
	mut target := current_process()

	if pid != 0 {
		if pid < 0 || pid >= proc.max_pid {
			return errno.err, errno.esrch
		}
		target = processes[pid]
		if target == unsafe { nil } {
			return errno.err, errno.esrch
		}
	}

	return u64(target.sid), 0
}

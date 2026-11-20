// SPDX-License-Identifier: GPL-2.0-or-later
module proc

// The filesystem ids: what file permission checks and new files' owners use.
// They follow the effective ids through every setuid/setgid family call, as
// on Linux, and setfsuid/setfsgid move them on their own, which file servers
// do to act for a client without changing who they are otherwise. Vinix
// keeps credentials per process, so they are per process too.

// CAP_CHOWN, DAC_OVERRIDE, DAC_READ_SEARCH, FOWNER, FSETID, LINUX_IMMUTABLE,
// MKNOD and MAC_OVERRIDE: Linux's CAP_FS_SET.
const capability_fs_set = u64(0x1f) | (u64(1) << 9) | (u64(1) << cap_mknod) | (u64(1) << 32)

// Any set*uid call leaves the filesystem uid at the effective one; a change
// makes the process undumpable, as a credential change does on Linux.
pub fn follow_effective_uid(mut process Process) {
	old := process.fsuid
	process.fsuid = process.euid
	if old != process.fsuid { set_dumpability(mut process, 0) }
}

pub fn follow_effective_gid(mut process Process) {
	old := process.fsgid
	process.fsgid = process.egid
	if old != process.fsgid { set_dumpability(mut process, 0) }
}

// setfsuid(uid): always the previous filesystem uid. The new one must be the
// real, effective, saved or current filesystem uid, or the caller needs
// CAP_SETUID; otherwise, as for -1, nothing changes. Leaving uid 0 drops the
// filesystem capabilities from the effective set and returning to it restores
// them from the permitted set, unless SECBIT_NO_SETUID_FIXUP says otherwise.
pub fn syscall_setfsuid(_ voidptr, uid_word u64) (u64, u64) {
	uid := u32(uid_word)
	mut process := current_thread().process
	lock_table()
	defer { unlock_table() }
	old := process.fsuid
	if uid == u32(0xffffffff) || uid == old { return u64(old), 0 }
	if uid != process.uid && uid != process.euid && uid != process.suid
		&& !has_capability(process, cap_setuid) {
		return u64(old), 0
	}
	process.fsuid = uid
	if securebits_state(current_thread()) & secbit_no_setuid_fixup == 0 {
		if old == 0 && uid != 0 {
			process.caps.effective &= ~capability_fs_set
		} else if old != 0 && uid == 0 {
			process.caps.effective |= process.caps.permitted & capability_fs_set
		}
	}
	set_dumpability(mut process, 0)
	return u64(old), 0
}

// setfsgid(gid): the same for the filesystem gid, with CAP_SETGID.
pub fn syscall_setfsgid(_ voidptr, gid_word u64) (u64, u64) {
	gid := u32(gid_word)
	mut process := current_thread().process
	lock_table()
	defer { unlock_table() }
	old := process.fsgid
	if gid == u32(0xffffffff) || gid == old { return u64(old), 0 }
	if gid != process.gid && gid != process.egid && gid != process.sgid
		&& !has_capability(process, cap_setgid) {
		return u64(old), 0
	}
	process.fsgid = gid
	set_dumpability(mut process, 0)
	return u64(old), 0
}

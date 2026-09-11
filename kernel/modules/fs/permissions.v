module fs

import errno
import proc
import stat

pub const access_exec = u32(1)
pub const access_write = u32(2)
pub const access_read = u32(4)

fn credential_in_group(process &proc.Process, gid u32, effective bool) bool {
	primary := if effective { process.egid } else { process.gid }
	if primary == gid {
		return true
	}
	for group in process.groups {
		if group == gid { return true }
	}
	return false
}

// Check owner/group/other mode bits against either the effective credentials
// used by normal filesystem operations or the real credentials used by
// access(2). Root bypasses read/write checks, but a regular file still needs at
// least one execute bit before root may execute it.
pub fn check_access(node &VFSNode, requested u32, effective bool) bool {
	if unsafe { node == nil } || unsafe { node.resource == nil } {
		return false
	}
	process := proc.current_thread().process
	uid := if effective { process.euid } else { process.uid }
	mode := node.resource.stat.mode
	if uid == 0 {
		if requested & access_exec != 0 && !stat.isdir(mode) && mode & 0o111 == 0 {
			return false
		}
		return true
	}

	mut allowed := mode & 0o7
	if uid == node.resource.stat.uid {
		allowed = (mode >> 6) & 0o7
	} else if credential_in_group(process, node.resource.stat.gid, effective) {
		allowed = (mode >> 3) & 0o7
	}
	return allowed & requested == requested
}

fn require_access(node &VFSNode, requested u32) ? {
	if !check_access(node, requested, true) {
		errno.set(errno.eacces)
		return none
	}
}

fn may_remove(parent &VFSNode, target &VFSNode) bool {
	if !check_access(parent, access_write | access_exec, true) {
		return false
	}
	if parent.resource.stat.mode & 0o1000 == 0 {
		return true
	}
	process := proc.current_thread().process
	return process.euid == 0 || process.euid == parent.resource.stat.uid
		|| process.euid == target.resource.stat.uid
}

fn owns_resource(uid u32) bool {
	process := proc.current_thread().process
	return process.euid == 0 || process.euid == uid
}

fn may_chown(uid u32, new_uid u32, new_gid u32) bool {
	process := proc.current_thread().process
	if process.euid == 0 {
		return true
	}
	if process.euid != uid || (new_uid != u32(-1) && new_uid != uid) {
		return false
	}
	return new_gid == u32(-1) || credential_in_group(process, new_gid, true)
}

fn apply_creation_identity(mut node VFSNode, parent &VFSNode) {
	process := proc.current_thread().process
	node.resource.stat.uid = process.euid
	node.resource.stat.gid = if parent.resource.stat.mode & 0o2000 != 0 {
		parent.resource.stat.gid
	} else {
		process.egid
	}
	if stat.isdir(node.resource.stat.mode) && parent.resource.stat.mode & 0o2000 != 0 {
		node.resource.stat.mode |= 0o2000
	}
}

pub fn syscall_umask(_ voidptr, mask u32) (u64, u64) {
	mut process := proc.current_thread().process
	old := process.umask
	process.umask = mask & 0o777
	return old, 0
}

module fs

import errno
import proc
import resource
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

// Whether the caller holds `cap`. access(2) asks with the real credentials,
// for which Linux counts a real uid of zero as holding the permitted set.
fn holds_capability(process &proc.Process, cap int, effective bool) bool {
	caps := if effective {
		process.caps.effective
	} else if process.uid == 0 {
		process.caps.permitted
	} else {
		u64(0)
	}
	return caps & (u64(1) << cap) != 0
}

// Check owner/group/other mode bits against either the effective credentials
// used by normal filesystem operations or the real credentials used by
// access(2). Being root is not what lifts the checks, capabilities are, so
// a container's root that has had them dropped is bound by the mode bits:
// CAP_DAC_OVERRIDE allows any access except executing a file with no execute
// bit at all, and CAP_DAC_READ_SEARCH allows reading and searching.
pub fn check_access(node &VFSNode, requested u32, effective bool) bool {
	if unsafe { node == nil } || unsafe { node.resource == nil } {
		return false
	}
	process := proc.current_thread().process
	uid := if effective { process.euid } else { process.uid }
	mode := node.resource.stat.mode
	if holds_capability(process, proc.cap_dac_override, effective) {
		if requested & access_exec != 0 && !stat.isdir(mode) && mode & 0o111 == 0 {
			return false
		}
		return true
	}
	if holds_capability(process, proc.cap_dac_read_search, effective) {
		searching := stat.isdir(mode) && requested & ~(access_read | access_exec) == 0
		if requested & ~access_read == 0 || searching {
			return true
		}
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
	return holds_capability(process, proc.cap_fowner, true)
		|| process.euid == parent.resource.stat.uid || process.euid == target.resource.stat.uid
}

fn owns_resource(uid u32) bool {
	process := proc.current_thread().process
	return holds_capability(process, proc.cap_fowner, true) || process.euid == uid
}

fn may_chown(uid u32, new_uid u32, new_gid u32) bool {
	process := proc.current_thread().process
	if holds_capability(process, proc.cap_chown, true) {
		return true
	}
	if process.euid != uid || (new_uid != u32(-1) && new_uid != uid) {
		return false
	}
	return new_gid == u32(-1) || credential_in_group(process, new_gid, true)
}

fn apply_creation_identity(mut node VFSNode, parent &VFSNode) ? {
	process := proc.current_thread().process
	desired_gid := if parent.resource.stat.mode & 0o2000 != 0 {
		parent.resource.stat.gid
	} else {
		process.egid
	}
	mut desired_mode := node.resource.stat.mode
	if stat.isdir(node.resource.stat.mode) && parent.resource.stat.mode & 0o2000 != 0 {
		desired_mode |= 0o2000
	}
	if node.resource.stat.uid == process.euid && node.resource.stat.gid == desired_gid
		&& node.resource.stat.mode == desired_mode {
		return
	}
	node.resource.stat.uid = process.euid
	node.resource.stat.gid = desired_gid
	node.resource.stat.mode = desired_mode
	mut res := node.resource
	resource.persist_metadata(mut res)?
}

pub fn syscall_umask(_ voidptr, mask u32) (u64, u64) {
	mut process := proc.current_thread().process
	old := process.umask
	process.umask = mask & 0o777
	return old, 0
}

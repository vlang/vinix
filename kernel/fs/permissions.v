module fs

import errno
import proc
import posix_acl
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
// Success grants the request; failures preserve EACCES or the backend's EIO.
// ACL lookup errors cannot be turned into a capability-based permission grant.
pub fn check_access(node &VFSNode, requested u32, effective bool) ? {
	if unsafe { node == nil } || unsafe { node.resource == nil } {
		errno.set(errno.eacces)
		return none
	}
	if requested == 0 { return }
	mut mandatory := u32(0)
	if requested & access_read != 0 { mandatory |= proc.mac_read }
	if requested & access_write != 0 { mandatory |= proc.mac_write }
	if requested & access_exec != 0 {
		mandatory |= if stat.isdir(node.resource.stat.mode) { proc.mac_search } else { proc.mac_execute }
	}
	mac_node(node, mandatory)?
	process := proc.current_thread().process
	uid := if effective { process.euid } else { process.uid }
	gid := if effective { process.egid } else { process.gid }
	mut res := unsafe { node.resource }
	mut acl := []u8{} @[freed]
	acl.flags |= .noslices
	defer { unsafe { acl.free() } }
	metadata := resource.permission_snapshot(mut res, mut acl)?
	mode := metadata.mode
	has_acl := acl.len != 0
	mut permitted := false
	if has_acl {
		if acl.len <= 4 || !posix_acl.valid(acl) { errno.set(errno.eio); return none }
		derived, _ := posix_acl.mode(acl, mode)
		if derived & 0o777 != mode & 0o777 { errno.set(errno.eio); return none }
		permitted = posix_acl.permits(acl, metadata.uid, metadata.gid, uid, gid,
			process.groups, requested)
	} else {
		mut allowed := mode & 0o7
		if uid == metadata.uid { allowed = (mode >> 6) & 0o7 }
		else if credential_in_group(process, metadata.gid, effective) { allowed = (mode >> 3) & 0o7 }
		permitted = allowed & requested == requested
	}
	if permitted { return }
	if holds_capability(process, proc.cap_dac_override, effective) {
		if requested & access_exec != 0 && !stat.isdir(mode) && mode & 0o111 == 0 {
			errno.set(errno.eacces)
			return none
		}
		return
	}
	if holds_capability(process, proc.cap_dac_read_search, effective) {
		searching := stat.isdir(mode) && requested & ~(access_read | access_exec) == 0
		if requested & ~access_read == 0 || searching {
			return
		}
	}

	errno.set(errno.eacces)
	return none
}

fn require_access(node &VFSNode, requested u32) ? {
	check_access(node, requested, true)?
}

fn may_remove(parent &VFSNode, target &VFSNode) ? {
	mac_node(target, proc.mac_remove)?
	mac_node(parent, proc.mac_remove)?
	check_access(parent, access_write | access_exec, true)?
	if parent.resource.stat.mode & 0o1000 == 0 {
		return
	}
	process := proc.current_thread().process
	if holds_capability(process, proc.cap_fowner, true)
		|| process.euid == parent.resource.stat.uid || process.euid == target.resource.stat.uid { return }
	errno.set(errno.eperm)
	return none
}

fn owns_resource(uid u32) bool {
	process := proc.current_thread().process
	return holds_capability(process, proc.cap_fowner, true) || process.euid == uid
}

fn may_keep_setgid(gid u32) bool {
	process := proc.current_thread().process
	return holds_capability(process, proc.cap_fsetid, true)
		|| credential_in_group(process, gid, true)
}

fn chmod_permissions(mode u32, gid u32) u32 {
	return if may_keep_setgid(gid) { mode } else { mode & ~u32(0o2000) }
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
	mac_creation(parent, mut node)?
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

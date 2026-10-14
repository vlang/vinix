// SPDX-License-Identifier: GPL-2.0-or-later
module fs

import proc
import resource
import katomic
import errno
import lib

// Resolve and authorize while namespace writers are excluded: permission
// snapshots can block on backing storage, so a fixed retirement grace is not
// a lifetime pin. Transfer one resource reference before unlocking; transport
// callers release it after their operation, including waits and failures.
pub fn resolve_socket_target(parent &VFSNode, path string) ?&resource.Resource {
	vfs_lock.acquire()
	mut target := get_node(parent, path, true) or {
		vfs_lock.release()
		return none
	}
	katomic.inc(mut &target.handles)
	mut res := target.resource
	resource.retain_resource(mut res)
	mut transferred := false
	defer {
		// A final release may remove a dynamic device name and take vfs_lock.
		vfs_lock.release()
		if !transferred {
			failure := errno.get()
			resource.release_resource(mut res)
			errno.set(failure)
		}
		release_handle_node(voidptr(target))
	}
	if !policy_check(target, proc.policy_socket | proc.policy_write) { return none }
	check_access(target, access_write, true)?
	transferred = true
	return res
}

// Path metadata operations can now enter a socket's slow backing callbacks.
// Hold both identities through backend errors and notification, like an FD.
struct PathTarget {
	node &VFSNode = unsafe { nil }
	res &resource.Resource = unsafe { nil }
}

fn retain_path_target(parent &VFSNode, path string, follow bool) ?PathTarget {
	vfs_lock.acquire()
	defer { vfs_lock.release() }
	mut node := get_node(parent, path, follow)?
	katomic.inc(mut &node.handles)
	mut res := node.resource
	resource.retain_resource(mut res)
	return PathTarget{node, res}
}

// The caller supplies a saved starting route and receives the resolved one.
// Keep the existing node/resource pins without extending PathTarget's layout.
fn retain_path_target_on_mount(parent &VFSNode, path string, follow bool,
	identity &lib.MountContext) ?PathTarget {
	vfs_lock.acquire()
	defer { vfs_lock.release() }
	mut node := get_node_on_mount(parent, path, follow, identity)?
	katomic.inc(mut &node.handles)
	mut res := node.resource
	resource.retain_resource(mut res)
	return PathTarget{node, res}
}

fn release_path_target(target PathTarget) {
	if target.node == unsafe { nil } { return }
	mut res := target.res
	resource.release_resource(mut res)
	release_handle_node(voidptr(target.node))
}

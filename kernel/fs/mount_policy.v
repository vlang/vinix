// SPDX-License-Identifier: GPL-2.0-or-later
module fs

import errno
import file
import proc
import stat

pub struct ResolvedNode {
pub:
	node &VFSNode = unsafe { nil }
	mount voidptr
}

// Namespace copies retain a mount's id. A descriptor or working directory
// inherited across unshare must consult the caller's copy, not the old flags.
fn namespace_mount(identity voidptr) &Mount {
	if identity == unsafe { nil } { return unsafe { nil } }
	entry := unsafe { &Mount(identity) }
	mut table := table_of(calling_process())
	if table == unsafe { nil } { return entry }
	table.lock.acquire()
	defer { table.lock.release() }
	for candidate in table.mounts {
		if candidate.id == entry.id { return candidate }
	}
	// Lazy-unmounted descriptors keep the policy of their detached mount.
	return entry
}

pub fn mount_flags(identity voidptr) u64 {
	entry := namespace_mount(identity)
	return if entry == unsafe { nil } { u64(0) } else { entry.flags }
}

// Only a filesystem's original mount can be inferred from an inode. Bind
// identities must be preserved by the path walk instead: newest matching root
// would apply one alias's permissions to every other alias of the inode.
fn native_mount(node &VFSNode) voidptr {
	mut table := table_of(calling_process())
	if table == unsafe { nil } { return unsafe { nil } }
	table.lock.acquire()
	defer { table.lock.release() }
	mut current := unsafe { node }
	for _ in 0 .. 4096 {
		if current == unsafe { nil } { break }
		for i := table.mounts.len - 1; i >= 0; i-- {
			entry := table.mounts[i]
			if entry.detached { continue }
			if voidptr(entry.root) == voidptr(current) && entry.options != 'bind' { return voidptr(entry) }
		}
		current = current.parent
	}
	return unsafe { nil }
}

fn mount_at(covered &VFSNode, root &VFSNode) voidptr {
	mut table := table_of(calling_process())
	if table == unsafe { nil } { return unsafe { nil } }
	table.lock.acquire()
	for i := table.mounts.len - 1; i >= 0; i-- {
		entry := table.mounts[i]
		if entry.detached { continue }
		if voidptr(entry.covered) == voidptr(covered) && voidptr(entry.root) == voidptr(root) {
			table.lock.release()
			return voidptr(entry)
		}
	}
	table.lock.release()
	// New initial-namespace mounts remain visible in namespaces that have
	// not overridden their covered node.
	if voidptr(table) != voidptr(initial_mount_table) && initial_mount_table != unsafe { nil } {
		mut initial := initial_mount_table
		initial.lock.acquire()
		defer { initial.lock.release() }
		for i := initial.mounts.len - 1; i >= 0; i-- {
			entry := initial.mounts[i]
			if entry.detached { continue }
			if voidptr(entry.covered) == voidptr(covered) && voidptr(entry.root) == voidptr(root) { return voidptr(entry) }
		}
	}
	return unsafe { nil }
}

// A self mount has no node.mountpoint (that would recurse forever). Select it
// only when entering from its containing mount; another bind alias sharing
// the same inode retains its own policy.
fn self_mount_at(node &VFSNode, identity voidptr) voidptr {
	mut table := table_of(calling_process())
	if table == unsafe { nil } { return identity }
	current := namespace_mount(identity)
	table.lock.acquire()
	defer { table.lock.release() }
	for i := table.mounts.len - 1; i >= 0; i-- {
		entry := table.mounts[i]
		if entry.detached { continue }
		if voidptr(entry.root) != voidptr(node) || voidptr(entry.covered) != voidptr(node) { continue }
		if current != unsafe { nil } && entry.id == current.id { return identity }
		if (entry.parent == unsafe { nil } && current == unsafe { nil })
			|| (entry.parent != unsafe { nil } && current != unsafe { nil }
				&& entry.parent.id == current.id) { return voidptr(entry) }
	}
	return identity
}

fn starting_mount(node &VFSNode) voidptr {
	process := calling_process()
	if process != unsafe { nil } {
		if voidptr(node) == proc.current_directory_of(process) {
			identity := proc.current_mount_of(process)
			if identity != unsafe { nil } { return voidptr(namespace_mount(identity)) }
		}
		if voidptr(node) == voidptr(process_root(process)) {
			identity := proc.root_mount_of(process)
			if identity != unsafe { nil } { return voidptr(namespace_mount(identity)) }
		}
	}
	return native_mount(node)
}

// The mount belonging to the directory argument of an *at syscall.
pub fn parent_mount_for(dirfd int, path string) ?voidptr {
	if path.len > 0 && path[0] == `/` { return starting_mount(calling_root()) }
	if is_fdcwd(dirfd) { return starting_mount(calling_directory()) }
	mut fd := file.fd_from_fdnum(unsafe { nil }, int(i32(dirfd))) or { return none }
	defer { fd.unref() }
	if !stat.isdir(fd.handle.resource.stat.mode) {
		errno.set(errno.enotdir)
		return none
	}
	return voidptr(namespace_mount(fd.handle.mount))
}

// `..` crosses the actual bind alias rather than searching by inode identity.
fn parent_on_mount(node &VFSNode, identity &voidptr) &VFSNode {
	if is_calling_root(node) { return unsafe { node } }
	entry := namespace_mount(unsafe { *identity })
	if entry != unsafe { nil } && voidptr(node) == voidptr(entry.root) {
		unsafe { *identity = voidptr(namespace_mount(voidptr(entry.parent))) }
		if voidptr(entry.covered) != voidptr(entry.root) {
			return parent_on_mount(entry.covered, identity)
		}
		if entry.parent != unsafe { nil } && entry.parent.id != entry.id {
			return parent_on_mount(node, identity)
		}
	}
	return if node.parent == unsafe { nil } { unsafe { node } } else { node.parent }
}

pub fn get_node_on_mount(parent &VFSNode, path string, follow_links bool,
	initial_mount voidptr) ?ResolvedNode {
	initial := if initial_mount == unsafe { nil } {
		starting_mount(parent)
	} else { voidptr(namespace_mount(initial_mount)) }
	identity := unsafe { &voidptr(C.vinix_stack_alloc(sizeof(voidptr))) }
	unsafe { *identity = initial }
	return get_node_with_mount_cursor(parent, path, follow_links, identity)
}

// Leave the cursor at the containing mount even when the final name is
// absent. openat can then attach that identity to the node it actually
// creates, without looking its name up again after releasing the VFS lock.
fn get_node_with_mount_cursor(parent &VFSNode, path string, follow_links bool,
	identity &voidptr) ?ResolvedNode {
	_, node, _ := walk_path_on_mount(parent, path, 0, true, identity)
	if node == unsafe { nil } { return none }
	result := reduce_node_on_mount(node, follow_links, 0, true, identity)
	if result == unsafe { nil } { return none }
	return ResolvedNode{node: result, mount: unsafe { *identity }}
}

pub fn get_node_and_mount(parent &VFSNode, path string, follow_links bool) ?ResolvedNode {
	return get_node_on_mount(parent, path, follow_links, starting_mount(parent))
}

// /proc magic links carry the source description's mount policy too. Looking
// it up uses no string copies or new references: mount identities are permanent.
fn magic_link_mount(node &VFSNode) voidptr {
	if node.resource == unsafe { nil } || !is_procfs_resource(node.resource) {
		return native_mount(node.magic_target)
	}
	res := unsafe { &ProcFSResource(node.resource) }
	proc.lock_table()
	defer { proc.unlock_table() }
	mut process := proc.process_at(res.pid)
	if process == unsafe { nil } { return unsafe { nil } }
	if node.name == 'exe' { return process.exe_mount }
	if node.name == 'cwd' { return proc.current_mount_of(process) }
	if node.name == 'root' { return proc.root_mount_of(process) }
	if node.parent != unsafe { nil } && node.parent.name == 'fd' {
		fdnum := node.name.int()
		if fdnum < 0 { return unsafe { nil } }
		process.fds_lock.acquire()
		defer { process.fds_lock.release() }
		if fdnum < process.fds.len && process.fds[fdnum] != unsafe { nil } {
			fd := unsafe { &file.FD(process.fds[fdnum]) }
			return fd.handle.mount
		}
	}
	return native_mount(node.magic_target)
}

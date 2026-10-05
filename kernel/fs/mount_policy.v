// SPDX-License-Identifier: GPL-2.0-or-later
module fs

import errno
import file
import proc
import stat
import lib

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

pub fn mount_flags(identity &lib.MountContext) u64 {
	entry := namespace_mount(lib.mount_context_top(identity))
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

fn mounted_identity(covered &VFSNode, root &VFSNode) voidptr {
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

// A descent records the caller's route rather than the mount's one canonical
// parent. No allocations occur: one bounded cursor belongs to the public walk.
fn enter_mount(identity &lib.MountContext, _entry &Mount) bool {
	if _entry == unsafe { nil } { return true }
	mut entry := unsafe { _entry }
	entry.lock.acquire()
	defer { entry.lock.release() }
	return append_mount_step(identity, entry, entry.move_epoch)
}

fn append_mount_step(identity &lib.MountContext, entry &Mount, move_epoch u64) bool {
	top := lib.mount_context_top(identity)
	if top != unsafe { nil } && unsafe { &Mount(top) }.id == entry.id { return true }
	if identity.depth < 0 || identity.depth >= 64 {
		errno.set(errno.eloop)
		return false
	}
	unsafe {
		identity.steps[identity.depth] = lib.MountStep{identity: voidptr(entry), move_epoch: move_epoch}
		identity.depth++
	}
	return true
}

fn mount_at(covered &VFSNode, root &VFSNode, identity &lib.MountContext) bool {
	entry := unsafe { &Mount(mounted_identity(covered, root)) }
	// A detach/move between the node and table lookups cannot authorize a
	// mounted inode using the containing directory's policy.
	if entry == unsafe { nil } {
		errno.set(errno.enoent)
		return false
	}
	return enter_mount(identity, entry)
}

// A self mount has no node.mountpoint (that would recurse forever). Enter it
// only from its containing mount; other bind aliases retain their own route.
fn self_mount_at(node &VFSNode, identity &lib.MountContext) bool {
	mut table := table_of(calling_process())
	if table == unsafe { nil } { return true }
	table.lock.acquire()
	defer { table.lock.release() }
	for _ in 0 .. 64 {
		current := lib.mount_context_top(identity)
		mut next := &Mount(unsafe { nil })
		for i := table.mounts.len - 1; i >= 0; i-- {
			entry := table.mounts[i]
			if entry.detached { continue }
			mut candidate := unsafe { entry }
			candidate.lock.acquire()
			self_bind := voidptr(candidate.root) == voidptr(node)
				&& voidptr(candidate.covered) == voidptr(node)
			parent := lib.mount_context_top(&candidate.parent)
			candidate.lock.release()
			if !self_bind { continue }
			if current != unsafe { nil } && entry.id == unsafe { &Mount(current) }.id { return true }
			if (parent == unsafe { nil } && current == unsafe { nil })
				|| (parent != unsafe { nil } && current != unsafe { nil }
					&& unsafe { &Mount(parent) }.id == unsafe { &Mount(current) }.id) {
				next = entry
				break
			}
		}
		if next == unsafe { nil } { return true }
		if !enter_mount(identity, next) { return false }
	}
	errno.set(errno.eloop)
	return false
}

fn native_context(node &VFSNode, identity &lib.MountContext) bool {
	mut entry := namespace_mount(native_mount(node))
	if entry == unsafe { nil } {
		lib.copy_mount_context(identity, unsafe { nil })
		return true
	}
	entry.lock.acquire()
	defer { entry.lock.release() }
	lib.copy_mount_context(identity, &entry.parent)
	return append_mount_step(identity, entry, entry.move_epoch)
}

fn starting_mount(node &VFSNode, identity &lib.MountContext) bool {
	process := calling_process()
	if process != unsafe { nil } {
		current := proc.snapshot_current_directory(process, identity)
		if voidptr(node) == current && identity.depth > 0 { return true }
		root := proc.snapshot_root_directory(process, identity)
		if voidptr(node) == root && identity.depth > 0 { return true }
	}
	return native_context(node, identity)
}

// Absolute paths use a single root/node snapshot, including when cwd names
// the same inode through another alias after chroot.
fn root_with_context(identity &lib.MountContext) ?&VFSNode {
	root := proc.snapshot_root_directory(calling_process(), identity)
	node := if root == unsafe { nil } { vfs_root } else { unsafe { &VFSNode(root) } }
	if identity.depth == 0 && !native_context(node, identity) { return none }
	return node
}

// Capture the directory and its route together before resolving an *at path.
// A shared CLONE_FS chdir cannot mix one alias's node with another's policy.
pub fn parent_and_mount_for(dirfd int, path string, identity &lib.MountContext) ?&VFSNode {
	if path.len > 0 && path[0] == `/` {
		return root_with_context(identity)
	}
	if is_fdcwd(dirfd) {
		current := proc.snapshot_current_directory(calling_process(), identity)
		node := if current == unsafe { nil } { vfs_root } else { unsafe { &VFSNode(current) } }
		if identity.depth == 0 && !native_context(node, identity) { return none }
		return node
	}
	mut fd := file.fd_from_fdnum(unsafe { nil }, int(i32(dirfd))) or { return none }
	defer { fd.unref() }
	if !stat.isdir(fd.handle.resource.stat.mode) || fd.handle.node == unsafe { nil } {
		errno.set(errno.enotdir)
		return none
	}
	lib.copy_mount_context(identity, &fd.handle.mount)
	return unsafe { &VFSNode(fd.handle.node) }
}

// `..` pops the actual alias parent. A move changes the mount's attachment,
// including for an already held fd/cwd; rebase only when its epoch changed.
fn parent_on_mount(node &VFSNode, identity &lib.MountContext) &VFSNode {
	mut current := unsafe { node }
	for _ in 0 .. 64 {
		if is_calling_root(current) { return current }
		mut entry := namespace_mount(lib.mount_context_top(identity))
		if entry == unsafe { nil } || voidptr(current) != voidptr(entry.root) {
			return if current.parent == unsafe { nil } { current } else { current.parent }
		}
		entry.lock.acquire()
		covered := entry.covered
		root := entry.root
		if identity.steps[identity.depth - 1].move_epoch != entry.move_epoch {
			lib.copy_mount_context(identity, &entry.parent)
		} else {
			unsafe { identity.depth-- }
		}
		entry.lock.release()
		if voidptr(covered) != voidptr(root) { current = covered }
	}
	errno.set(errno.eloop)
	return unsafe { nil }
}

pub fn get_node_on_mount(parent &VFSNode, path string, follow_links bool,
	identity &lib.MountContext) ?&VFSNode {
	return get_node_with_mount_cursor(parent, path, follow_links, identity)
}

// Leave the cursor at the containing mount even when the final name is
// absent. openat can attach it to the node it actually creates.
fn get_node_with_mount_cursor(parent &VFSNode, path string, follow_links bool,
	identity &lib.MountContext) ?&VFSNode {
	_, node, _ := walk_path_on_mount(parent, path, 0, true, identity)
	if node == unsafe { nil } { return none }
	result := reduce_node_on_mount(node, follow_links, 0, true, identity)
	if result == unsafe { nil } { return none }
	return result
}

pub fn get_node_and_mount(parent &VFSNode, path string, follow_links bool,
	identity &lib.MountContext) ?&VFSNode {
	if !starting_mount(parent, identity) { return none }
	return get_node_on_mount(parent, path, follow_links, identity)
}

// /proc magic links snapshot their target and route together under the
// source's existing process/fd lock. Mount identities remain permanent.
fn magic_link_mount(node &VFSNode, identity &lib.MountContext) &VFSNode {
	if node.resource == unsafe { nil } || !is_procfs_resource(node.resource) {
		if !starting_mount(node.magic_target, identity) { return unsafe { nil } }
		return node.magic_target
	}
	res := unsafe { &ProcFSResource(node.resource) }
	proc.lock_table()
	defer { proc.unlock_table() }
	mut process := proc.process_at(res.pid)
	if process == unsafe { nil } { errno.set(errno.enoent); return unsafe { nil } }
	if node.name == 'exe' { return unsafe { &VFSNode(proc.snapshot_executable(process, identity)) } }
	if node.name == 'cwd' { return unsafe { &VFSNode(proc.snapshot_current_directory(process, identity)) } }
	if node.name == 'root' {
		root := proc.snapshot_root_directory(process, identity)
		return if root == unsafe { nil } { vfs_root } else { unsafe { &VFSNode(root) } }
	}
	if node.parent != unsafe { nil } && node.parent.name == 'fd' {
		fdnum := node.name.int()
		if fdnum < 0 { errno.set(errno.enoent); return unsafe { nil } }
		process.fds_lock.acquire()
		defer { process.fds_lock.release() }
		if fdnum < process.fds.len && process.fds[fdnum] != unsafe { nil } {
			fd := unsafe { &file.FD(process.fds[fdnum]) }
			lib.copy_mount_context(identity, &fd.handle.mount)
			return unsafe { &VFSNode(fd.handle.node) }
		}
		errno.set(errno.enoent)
		return unsafe { nil }
	}
	if !starting_mount(node.magic_target, identity) { return unsafe { nil } }
	return node.magic_target
}

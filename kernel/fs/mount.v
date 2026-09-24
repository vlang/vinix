// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Mounts, mount namespaces, chroot(2) and pivot_root(2).
//
// A mount attaches the root of a tree to the node it covers. In the initial
// namespace that is the node's own `mountpoint` field. Any other namespace keeps
// an override table on top: a node it mounts over, or unmounts, is looked up
// there first, and everything it has not touched falls through to the initial
// namespace. Mounts made there later therefore show up everywhere, much like a
// Linux mount namespace whose mounts are slaves of the initial one, while the
// mounts a container makes stay its own.
//
// Every namespace also lists its mounts in order. /proc/<pid>/mountinfo is made
// from that list, and it is what `..` consults at the root of a mount: the way
// out of a mount is through the directory it covers in this namespace, which
// for a filesystem mounted in two places depends on who is asking.
@[has_globals]
module fs

import errno
import katomic
import klock
import proc
import security
import stat
import usercopy

pub const ms_rdonly = u64(0x1)
pub const ms_nosuid = u64(0x2)
pub const ms_nodev = u64(0x4)
pub const ms_noexec = u64(0x8)
pub const ms_remount = u64(0x20)
pub const ms_noatime = u64(0x400)
pub const ms_nodiratime = u64(0x800)
pub const ms_bind = u64(0x1000)
pub const ms_move = u64(0x2000)
pub const ms_rec = u64(0x4000)
pub const ms_unbindable = u64(0x20000)
pub const ms_private = u64(0x40000)
pub const ms_slave = u64(0x80000)
pub const ms_shared = u64(0x100000)
pub const ms_relatime = u64(0x200000)
pub const ms_strictatime = u64(0x1000000)

const ms_propagation = ms_unbindable | ms_private | ms_slave | ms_shared
const ms_per_mount = ms_rdonly | ms_nosuid | ms_nodev | ms_noexec | ms_noatime | ms_nodiratime | ms_relatime | ms_strictatime

const mnt_detach = 2
const umount_nofollow = 8

@[heap]
pub struct Mount {
pub mut:
	id      int
	covered &VFSNode = unsafe { nil }
	root    &VFSNode = unsafe { nil }
	source  string
	fstype  string
	flags   u64
	options string
}

@[heap]
pub struct MountTable {
pub mut:
	lock      klock.Lock
	mounts    []&Mount
	overrides map[u64]voidptr
	initial   bool
	// The root pivot_root(2) last installed here: where setns(2) into this
	// namespace puts the joining process.
	root_hint &VFSNode = unsafe { nil }
}

__global (
	initial_mount_table &MountTable
	mount_id_counter    = int(0)
)

fn init_mount_tables() {
	initial_mount_table = &MountTable{
		initial: true
	}
}

fn calling_process() &proc.Process {
	thread := proc.current_thread()
	if thread == unsafe { nil } {
		return unsafe { nil }
	}
	return thread.process
}

fn table_of(process &proc.Process) &MountTable {
	ns := proc.mount_namespace_of(process)
	if ns == unsafe { nil } || ns.data == unsafe { nil } {
		return initial_mount_table
	}
	return unsafe { &MountTable(ns.data) }
}

// The directory a process' absolute paths start from, as the calling thread
// sees it.
pub fn process_root(process &proc.Process) &VFSNode {
	root := proc.root_directory_of(process)
	if root == unsafe { nil } {
		return vfs_root
	}
	return unsafe { &VFSNode(root) }
}

fn calling_root() &VFSNode {
	return process_root(calling_process())
}

// What is mounted on `node` for the calling process, or nil.
fn mount_of(node &VFSNode) &VFSNode {
	if node.ns_mounts > 0 {
		mut table := table_of(calling_process())
		if !table.initial {
			key := u64(voidptr(node))
			table.lock.acquire()
			if key in table.overrides {
				target := unsafe { &VFSNode(table.overrides[key]) }
				table.lock.release()
				return target
			}
			table.lock.release()
		}
	}
	return node.mountpoint
}

fn attach_mount(mut table MountTable, mut covered VFSNode, root &VFSNode) {
	if table.initial {
		covered.mountpoint = unsafe { root }
		return
	}
	key := u64(voidptr(covered))
	table.lock.acquire()
	if key !in table.overrides {
		katomic.inc(mut &covered.ns_mounts)
	}
	table.overrides[key] = voidptr(root)
	table.lock.release()
}

fn record_mount(mut table MountTable, covered &VFSNode, root &VFSNode, source string,
	fstype string, flags u64, options string) &Mount {
	entry := &Mount{
		id:      katomic.inc(mut &mount_id_counter) + 1
		covered: unsafe { covered }
		root:    unsafe { root }
		source:  source
		fstype:  fstype
		flags:   flags & ms_per_mount
		options: options
	}
	if voidptr(covered) != voidptr(root) {
		mut root_node := unsafe { root }
		root_node.mount_root = true
	}
	table.lock.acquire()
	table.mounts << entry
	table.lock.release()
	return entry
}

// The mount table a new mount namespace starts with: a copy of its parent's.
pub fn copy_mount_table(parent &MountTable) &MountTable {
	mut table := &MountTable{}
	mut source := unsafe { parent }
	source.lock.acquire()
	for entry in source.mounts {
		table.mounts << &Mount{
			id:      entry.id
			covered: entry.covered
			root:    entry.root
			source:  entry.source
			fstype:  entry.fstype
			flags:   entry.flags
			options: entry.options
		}
	}
	if !source.initial {
		for key, value in source.overrides {
			table.overrides[key] = value
			mut node := unsafe { &VFSNode(key) }
			katomic.inc(mut &node.ns_mounts)
		}
	}
	source.lock.release()
	return table
}

pub fn release_mount_table(mut table MountTable) {
	if table.initial {
		return
	}
	table.lock.acquire()
	for key, _ in table.overrides {
		mut node := unsafe { &VFSNode(key) }
		katomic.dec(mut &node.ns_mounts)
	}
	table.overrides.clear()
	table.mounts.clear()
	table.lock.release()
}

// The node a mount root stands for in the caller's namespace: the one it
// covers. Nil for anything that is not the root of a mount here.
fn covered_by(node &VFSNode) &VFSNode {
	if !node.mount_root {
		return unsafe { nil }
	}
	mut table := table_of(calling_process())
	table.lock.acquire()
	defer {
		table.lock.release()
	}
	for i := table.mounts.len - 1; i >= 0; i-- {
		entry := table.mounts[i]
		if voidptr(entry.root) == voidptr(node) && voidptr(entry.covered) != voidptr(node) {
			return entry.covered
		}
	}
	return unsafe { nil }
}

fn is_calling_root(node &VFSNode) bool {
	root := calling_root()
	if voidptr(node) == voidptr(root) {
		return true
	}
	top := reduce_node_bounded(root, false, 0, false)
	return top != unsafe { nil } && voidptr(node) == voidptr(top)
}

// Where `..` leads from `node`. The root of the caller's tree is its own
// parent, and the root of a mount leads out through the node it covers.
fn logical_parent(node &VFSNode) &VFSNode {
	mut current := unsafe { node }
	for _ in 0 .. 64 {
		if is_calling_root(current) {
			return current
		}
		covered := covered_by(current)
		if covered == unsafe { nil } {
			break
		}
		current = covered
	}
	if is_calling_root(current) || current.parent == unsafe { nil } {
		return current
	}
	return current.parent
}

// The path of `node` as seen from `root`, or none when it cannot be reached
// from there at all.
pub fn path_from_root(node &VFSNode, root &VFSNode) ?string {
	top := reduce_node_bounded(root, false, 0, false)
	mut components := []string{}
	defer {
		unsafe { components.free() }
	}
	mut current := unsafe { node }
	for _ in 0 .. 4096 {
		if current == unsafe { nil } {
			return none
		}
		if voidptr(current) == voidptr(root) || (top != unsafe { nil }
			&& voidptr(current) == voidptr(top)) {
			if components.len == 0 {
				return '/'
			}
			mut path := ''
			for i := components.len - 1; i >= 0; i-- {
				path += '/${components[i]}'
			}
			return path
		}
		covered := covered_by(current)
		if covered != unsafe { nil } {
			current = covered
			continue
		}
		if current.parent == unsafe { nil } {
			return none
		}
		components << current.name
		current = current.parent
	}
	return none
}

// ── mount(2) ─────────────────────────────────────────────────────────────────

fn optional_user_string(pointer charptr, limit int) string {
	if pointer == unsafe { nil } {
		return ''
	}
	mut bytes := []u8{}
	for i := 0; i < limit; i++ {
		mut c := u8(0)
		if !usercopy.copy_from_user(voidptr(&c), u64(pointer) + u64(i), 1) {
			break
		}
		if c == 0 {
			break
		}
		bytes << c
	}
	return bytes.bytestr()
}

pub fn syscall_mount(_ voidptr, src charptr, tgt charptr, fs_type charptr, mountflags u64, data voidptr) (u64, u64) {
	if !security.permitted(security.filesystem_mount) {
		return errno.err, errno.eperm
	}
	target := user_path(tgt) or { return errno.err, errno.get() }
	source := optional_user_string(src, 4096)
	fstype := optional_user_string(fs_type, 256)
	options := optional_user_string(charptr(data), 4096)
	mut flags := mountflags
	// Old programs still put MS_MGC_VAL in the top half of the flags.
	if flags & 0xffff0000 == 0xc0ed0000 {
		flags &= 0xffff
	}
	directory := calling_directory()
	mount_request(directory, source, target, fstype, flags, options) or {
		return errno.err, errno.get()
	}
	return 0, 0
}

fn calling_directory() &VFSNode {
	directory := proc.current_directory_of(calling_process())
	if directory == unsafe { nil } {
		return vfs_root
	}
	return unsafe { &VFSNode(directory) }
}

fn mount_request(parent &VFSNode, source string, target string, fstype string, flags u64, options string) ? {
	if flags & ms_remount != 0 {
		return remount(parent, target, flags, options)
	}
	if flags & ms_propagation != 0 {
		// Propagation types are accepted but not modelled: see the top of this
		// file for the one arrangement every namespace has.
		get_node(parent, target, true)?
		return
	}
	if flags & ms_bind != 0 {
		return bind_mount(parent, source, target, flags)
	}
	if flags & ms_move != 0 {
		return move_mount(parent, source, target)
	}
	return new_mount(parent, source, target, fstype, flags, options)
}

// Kernel callers: mount a new filesystem instance with default options.
pub fn mount(parent &VFSNode, source string, target string, filesystem string) ? {
	return new_mount(parent, source, target, filesystem, 0, '')
}

// The registered filesystem behind a Linux filesystem type name.
fn filesystem_kind(fstype string) string {
	return match fstype {
		'proc' { 'procfs' }
		'mqueue', 'shm', 'ramfs' { 'tmpfs' }
		else { fstype }
	}
}

// The name mountinfo shows for a filesystem type.
fn display_fstype(fstype string) string {
	return match fstype {
		'procfs' { 'proc' }
		else { fstype }
	}
}

const pseudo_filesystems = ['tmpfs', 'procfs', 'sysfs', 'devtmpfs', 'cgroup2']

fn new_mount(parent &VFSNode, source string, target string, fstype string, flags u64, options string) ? {
	kind := filesystem_kind(fstype)
	if kind == 'devpts' {
		return mount_devpts(parent, target, flags, options)
	}
	if kind !in filesystems {
		errno.set(errno.enodev)
		return none
	}

	mut source_node := &VFSNode(unsafe { nil })
	if source.len != 0 && kind !in pseudo_filesystems {
		_, source_node, _ = path2node(parent, source)
		if voidptr(source_node) == unsafe { nil } {
			errno.set(errno.enoent)
			return none
		}
		if stat.isdir(source_node.resource.stat.mode) {
			errno.set(errno.enotblk)
			return none
		}
	}

	parent_of_tgt_node, mut target_node, basename := path2node(parent, target)
	if target_node == unsafe { nil } {
		errno.set(errno.enoent)
		return none
	}
	// The mount point is reached through normal path resolution, so a final
	// symlink is followed too. runc mounts onto /proc/self/fd/<n>, a magic link
	// to the real directory it opened, to avoid a TOCTOU on the path.
	target_node = reduce_node(target_node, true)
	if target_node == unsafe { nil } {
		errno.set(errno.enoent)
		return none
	}
	mounting_root := voidptr(target_node) == voidptr(vfs_root)
	if !mounting_root && !stat.isdir(target_node.resource.stat.mode) {
		errno.set(errno.enotdir)
		return none
	}

	mut mount_node := &VFSNode(unsafe { nil })
	if kind == 'cgroup2' {
		mount_node = cgroup_mount_root(parent_of_tgt_node, basename)?
	} else {
		mut f_sys := unsafe { filesystems[kind].instantiate() }
		mount_node = f_sys.mount(parent_of_tgt_node, basename, source_node)?
	}
	if mount_node.children != unsafe { nil } && '.' !in mount_node.children {
		mount_node.create_dotentries(parent_of_tgt_node)
	}
	if kind == 'tmpfs' {
		apply_tmpfs_options(mut mount_node, options)
	}

	mut table := table_of(calling_process())
	attach_mount(mut table, mut target_node, mount_node)
	shown := if fstype == kind { display_fstype(kind) } else { fstype }
	record_mount(mut table, target_node, mount_node, if source.len > 0 { source } else { shown },
		shown, flags, options)

	if source.len > 0 {
		print('vfs: Mounted `${source}` to `${target}` with filesystem `${fstype}`\n')
	} else {
		print('vfs: Mounted ${fstype} to `${target}`\n')
	}
}

// tmpfs takes mode=, uid= and gid= for its root directory. Sizes are accepted
// and not enforced: tmpfs here grows until memory runs out.
fn apply_tmpfs_options(mut root VFSNode, options string) {
	if root.resource == unsafe { nil } {
		return
	}
	mut res := root.resource
	for option in options.split(',') {
		if option.starts_with('mode=') {
			mut mode := u32(0)
			for digit in option[5..] {
				if digit < `0` || digit > `7` {
					break
				}
				mode = mode * 8 + u32(digit - `0`)
			}
			res.stat.mode = (res.stat.mode & stat.ifmt) | (mode & 0o7777)
		} else if option.starts_with('uid=') {
			res.stat.uid = u32(option[4..].int())
		} else if option.starts_with('gid=') {
			res.stat.gid = u32(option[4..].int())
		}
	}
}

// devpts: there is one pseudo terminal namespace, /dev/pts, and a devpts mount
// elsewhere shows that directory again.
fn mount_devpts(parent &VFSNode, target string, flags u64, options string) ? {
	if devtmpfs_root == unsafe { nil } {
		errno.set(errno.enodev)
		return none
	}
	mut pts := &VFSNode(unsafe { nil })
	if 'pts' in devtmpfs_root.children {
		pts = unsafe { devtmpfs_root.children['pts'] }
	} else {
		pts = internal_create(devtmpfs_root, 'pts', stat.ifdir | 0o755)?
	}
	_, mut target_node, _ := path2node(parent, target)
	if target_node == unsafe { nil } {
		errno.set(errno.enoent)
		return none
	}
	target_node = reduce_node(target_node, true)
	if target_node == unsafe { nil } {
		errno.set(errno.enoent)
		return none
	}
	if !stat.isdir(target_node.resource.stat.mode) {
		errno.set(errno.enotdir)
		return none
	}
	mut table := table_of(calling_process())
	if voidptr(target_node) != voidptr(pts) {
		attach_mount(mut table, mut target_node, pts)
	}
	record_mount(mut table, target_node, pts, 'devpts', 'devpts', flags, options)
}

// mount --bind: make `target` lead to what `source` names. Everything mounted
// below the source is part of what it names, so every bind here behaves as a
// recursive one.
fn bind_mount(parent &VFSNode, source string, target string, flags u64) ? {
	source_node := get_node(parent, source, true)?
	_, mut target_node, _ := path2node(parent, target)
	if target_node == unsafe { nil } {
		errno.set(errno.enoent)
		return none
	}
	target_node = reduce_node(target_node, true)
	if target_node == unsafe { nil } {
		errno.set(errno.enoent)
		return none
	}
	if stat.isdir(source_node.resource.stat.mode) != stat.isdir(target_node.resource.stat.mode) {
		errno.set(if stat.isdir(target_node.resource.stat.mode) {
			errno.enotdir
		} else {
			errno.eisdir
		})
		return none
	}
	mut table := table_of(calling_process())
	// Binding a directory onto itself -- how a runtime turns its root into a
	// mount point -- changes nothing about where paths lead.
	if voidptr(source_node) != voidptr(target_node) {
		attach_mount(mut table, mut target_node, source_node)
	}
	origin := path_from_root(source_node, vfs_root) or { pathname(source_node) }
	mut fstype := 'none'
	table.lock.acquire()
	for i := table.mounts.len - 1; i >= 0; i-- {
		entry := table.mounts[i]
		if is_beneath(source_node, entry.root) {
			fstype = entry.fstype
			break
		}
	}
	table.lock.release()
	record_mount(mut table, target_node, source_node, origin, fstype, flags, 'bind')
}

fn is_beneath(node &VFSNode, ancestor &VFSNode) bool {
	mut current := unsafe { node }
	for _ in 0 .. 4096 {
		if current == unsafe { nil } {
			return false
		}
		if voidptr(current) == voidptr(ancestor) {
			return true
		}
		current = current.parent
	}
	return false
}

fn find_mount(mut table MountTable, root &VFSNode) &Mount {
	table.lock.acquire()
	defer {
		table.lock.release()
	}
	for i := table.mounts.len - 1; i >= 0; i-- {
		if voidptr(table.mounts[i].root) == voidptr(root) {
			return table.mounts[i]
		}
	}
	return unsafe { nil }
}

fn move_mount(parent &VFSNode, source string, target string) ? {
	source_root := get_node(parent, source, true)?
	mut table := table_of(calling_process())
	mut entry := find_mount(mut table, source_root)
	if entry == unsafe { nil } {
		errno.set(errno.einval)
		return none
	}
	_, mut target_node, _ := path2node(parent, target)
	if target_node == unsafe { nil } {
		errno.set(errno.enoent)
		return none
	}
	mut old_covered := entry.covered
	if voidptr(old_covered) != voidptr(entry.root) {
		attach_mount(mut table, mut old_covered, unsafe { nil })
	}
	attach_mount(mut table, mut target_node, entry.root)
	entry.covered = target_node
}

fn remount(parent &VFSNode, target string, flags u64, options string) ? {
	node := get_node(parent, target, true)?
	mut table := table_of(calling_process())
	mut entry := find_mount(mut table, node)
	if entry == unsafe { nil } {
		errno.set(errno.einval)
		return none
	}
	entry.flags = flags & ms_per_mount
	if flags & ms_bind == 0 && options.len > 0 {
		entry.options = options
	}
}

// ── umount2(2) ───────────────────────────────────────────────────────────────

pub fn syscall_umount(_ voidptr, tgt charptr, flags u64) (u64, u64) {
	if !security.permitted(security.filesystem_unmount) {
		return errno.err, errno.eperm
	}
	target := user_path(tgt) or { return errno.err, errno.get() }
	if flags & ~u64(0xf) != 0 {
		return errno.err, errno.einval
	}
	unmount(calling_directory(), target, flags) or { return errno.err, errno.get() }
	return 0, 0
}

fn unmount(parent &VFSNode, target string, flags u64) ? {
	node := get_node(parent, target, flags & umount_nofollow == 0)?
	mut table := table_of(calling_process())
	entry := find_mount(mut table, node)
	if entry == unsafe { nil } {
		errno.set(errno.einval)
		return none
	}
	if voidptr(entry.covered) != voidptr(entry.root) {
		mut covered := entry.covered
		attach_mount(mut table, mut covered, unsafe { nil })
	}
	table.lock.acquire()
	index := table.mounts.index(entry)
	if index >= 0 {
		table.mounts.delete(index)
	}
	table.lock.release()

	// A lazy unmount takes everything mounted inside the tree with it. What
	// is still reachable from the caller's root stays, which is how the old
	// root is shed after pivot_root without losing the new root's mounts.
	if flags & mnt_detach != 0 {
		root := calling_root()
		mut stale := []&Mount{}
		table.lock.acquire()
		for candidate in table.mounts {
			if is_beneath(candidate.covered, entry.root) {
				stale << candidate
			}
		}
		table.lock.release()
		for candidate in stale {
			if _ := path_from_root(candidate.covered, root) {
				continue
			}
			table.lock.acquire()
			i := table.mounts.index(candidate)
			if i >= 0 {
				table.mounts.delete(i)
			}
			table.lock.release()
		}
		unsafe { stale.free() }
	}
}

// ── chroot(2) and pivot_root(2) ──────────────────────────────────────────────

pub fn syscall_chroot(_ voidptr, _path charptr) (u64, u64) {
	if !proc.current_has_capability(proc.cap_sys_chroot) {
		return errno.err, errno.eperm
	}
	path := user_path(_path) or { return errno.err, errno.get() }
	if path.len == 0 {
		return errno.err, errno.enoent
	}
	node := get_node(calling_directory(), path, true) or { return errno.err, errno.get() }
	if !stat.isdir(node.resource.stat.mode) {
		return errno.err, errno.enotdir
	}
	if !check_access(node, access_exec, true) {
		return errno.err, errno.eacces
	}
	mut process := calling_process()
	proc.set_root_directory(mut process, voidptr(node))
	return 0, 0
}

pub fn syscall_pivot_root(_ voidptr, _new_root charptr, _put_old charptr) (u64, u64) {
	if !security.permitted(security.filesystem_mount) {
		return errno.err, errno.eperm
	}
	new_path := user_path(_new_root) or { return errno.err, errno.get() }
	old_path := user_path(_put_old) or { return errno.err, errno.get() }
	directory := calling_directory()
	mut new_root := get_node(directory, new_path, true) or { return errno.err, errno.get() }
	mut put_old := get_node(directory, old_path, true) or { return errno.err, errno.get() }
	if !stat.isdir(new_root.resource.stat.mode) || !stat.isdir(put_old.resource.stat.mode) {
		return errno.err, errno.enotdir
	}

	mut process := calling_process()
	old_root := process_root(process)
	old_top := reduce_node(old_root, false)
	if old_top == unsafe { nil } || voidptr(new_root) == voidptr(old_top) {
		return errno.err, errno.ebusy
	}
	// put_old has to be the new root or somewhere below it.
	if !is_beneath(put_old, new_root) {
		return errno.err, errno.einval
	}

	mut table := table_of(process)
	old_entry := find_mount(mut table, old_top)
	attach_mount(mut table, mut put_old, old_top)
	record_mount(mut table, put_old, old_top, if old_entry != unsafe { nil } {
		old_entry.source
	} else {
		'rootfs'
	}, if old_entry != unsafe { nil } { old_entry.fstype } else { 'rootfs' }, 0, '')

	table.root_hint = new_root

	// Every process of this namespace that was rooted, or standing, at the
	// old root moves to the new one. These are the processes' own roots, not
	// the calling thread's view of its own process.
	ns := proc.mount_namespace_of(process)
	proc.lock_table()
	for pid := 1; pid < proc.max_pid; pid++ {
		mut other := proc.process_at(pid)
		if other == unsafe { nil } || voidptr(other.ns.mnt) != voidptr(ns) {
			continue
		}
		other_root := if other.root_directory == unsafe { nil } {
			vfs_root
		} else {
			unsafe { &VFSNode(other.root_directory) }
		}
		if voidptr(other_root) == voidptr(old_root) || voidptr(other_root) == voidptr(old_top) {
			other.root_directory = voidptr(new_root)
		}
		if other.current_directory == voidptr(old_root) || other.current_directory == voidptr(old_top) {
			other.current_directory = voidptr(new_root)
		}
	}
	proc.unlock_table()
	// A thread with a view of its own moves by itself.
	mut own := proc.thread_fs_of(process)
	if own != unsafe { nil } {
		own_root := if own.root_directory == unsafe { nil } {
			vfs_root
		} else {
			unsafe { &VFSNode(own.root_directory) }
		}
		if voidptr(own_root) == voidptr(old_root) || voidptr(own_root) == voidptr(old_top) {
			own.root_directory = voidptr(new_root)
		}
		if own.current_directory == voidptr(old_root) || own.current_directory == voidptr(old_top) {
			own.current_directory = voidptr(new_root)
		}
	}
	return 0, 0
}

// ── /proc/<pid>/mountinfo and /proc/<pid>/mounts ─────────────────────────────

fn mount_option_text(flags u64) string {
	mut text := if flags & ms_rdonly != 0 { 'ro' } else { 'rw' }
	if flags & ms_nosuid != 0 {
		text += ',nosuid'
	}
	if flags & ms_nodev != 0 {
		text += ',nodev'
	}
	if flags & ms_noexec != 0 {
		text += ',noexec'
	}
	if flags & ms_noatime != 0 {
		text += ',noatime'
	} else {
		text += ',relatime'
	}
	return text
}

// Linux escapes whitespace and backslashes in these fields as octal.
fn escape_mount_field(text string) string {
	if !text.contains_any(' \t\n\\') {
		return text
	}
	mut out := ''
	for c in text {
		match c {
			` ` { out += '\\040' }
			`\t` { out += '\\011' }
			`\n` { out += '\\012' }
			`\\` { out += '\\134' }
			else { out += c.ascii_str() }
		}
	}
	return out
}

struct VisibleMount {
	entry &Mount
	path  string
}

fn visible_mounts(pid int) []VisibleMount {
	mut visible := []VisibleMount{}
	proc.lock_table()
	process := proc.process_at(pid)
	proc.unlock_table()
	if process == unsafe { nil } {
		return visible
	}
	root := process_root(process)
	mut table := table_of(process)
	table.lock.acquire()
	entries := table.mounts.clone()
	table.lock.release()
	for entry in entries {
		path := path_from_root(entry.covered, root) or { continue }
		visible << VisibleMount{
			entry: entry
			path:  path
		}
	}
	return visible
}

pub fn mountinfo_text(pid int) string {
	visible := visible_mounts(pid)
	mut text := ''
	for item in visible {
		entry := item.entry
		// The parent is the mount this one sits in: the closest one whose
		// mount point is a prefix of this one's.
		mut parent_id := entry.id
		mut best := -1
		for other in visible {
			if other.entry.id == entry.id {
				continue
			}
			prefix := if other.path == '/' { '/' } else { other.path + '/' }
			if (item.path.starts_with(prefix) || (other.path == '/' && item.path != '/'))
				&& other.path.len > best {
				best = other.path.len
				parent_id = other.entry.id
			}
		}
		dev := if entry.root != unsafe { nil } && entry.root.resource != unsafe { nil } {
			entry.root.resource.stat.dev
		} else {
			u64(0)
		}
		root_field := if entry.options == 'bind' { entry.source } else { '/' }
		super_options := if entry.options.len > 0 && entry.options != 'bind' {
			'rw,' + entry.options
		} else {
			'rw'
		}
		text += '${entry.id} ${parent_id} 0:${dev} ${escape_mount_field(root_field)} ${escape_mount_field(item.path)} ${mount_option_text(entry.flags)} - ${entry.fstype} ${escape_mount_field(entry.source)} ${super_options}\n'
	}
	return text
}

pub fn mounts_text(pid int) string {
	visible := visible_mounts(pid)
	mut text := ''
	for item in visible {
		entry := item.entry
		text += '${escape_mount_field(entry.source)} ${escape_mount_field(item.path)} ${entry.fstype} ${mount_option_text(entry.flags)} 0 0\n'
	}
	return text
}

// The boot code swaps the system root for an on-disk one, carrying /dev and
// /proc across and giving it RAM-backed scratch directories. The initial
// table is rebuilt from what the new root has mounted on it.
pub fn record_root_switch(root &VFSNode, fstype string) {
	mut table := initial_mount_table
	table.lock.acquire()
	old := table.mounts.clone()
	table.mounts.clear()
	table.lock.release()
	record_mount(mut table, root, root, '/dev/root', fstype, 0, '')
	for name in root.children.keys() {
		if is_dot_name(name) {
			continue
		}
		child := unsafe { root.children[name] }
		if child.mountpoint == unsafe { nil } {
			continue
		}
		mut shown := 'tmpfs'
		for entry in old {
			if voidptr(entry.root) == voidptr(child.mountpoint) {
				shown = entry.fstype
			}
		}
		record_mount(mut table, child, child.mountpoint, shown, shown, 0, '')
	}
}

// Whether a directory entry is `.` or `..`. A function of its own because
// comparing the key of a loop over a node's children in place is miscompiled.
fn is_dot_name(name string) bool {
	return name == '.' || name == '..'
}

// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// unshare(2), setns(2), the namespace flags of clone(2), and the nsfs files
// /proc/<pid>/ns/* lead to. See proc/container.v for what each namespace kind
// keeps apart.
@[has_globals]
module fs

import errno
import event.eventstruct
import file
import katomic
import klock
import lib
import net
import proc
import resource
import stat
import sysvmsg

@[heap]
struct NsFSResource {
pub mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock
	event    eventstruct.Event
	status   int
	can_mmap bool

	ns &proc.Namespace = unsafe { nil }
}

__global (
	nsfs_dev_id u64
)

fn namespace_kind_name(kind u64) string {
	return match kind {
		proc.clone_newns { 'mnt' }
		proc.clone_newuts { 'uts' }
		proc.clone_newipc { 'ipc' }
		proc.clone_newnet { 'net' }
		proc.clone_newpid { 'pid' }
		proc.clone_newcgroup { 'cgroup' }
		proc.clone_newuser { 'user' }
		proc.clone_newtime { 'time' }
		else { 'unknown' }
	}
}

// "<kind>:[<id>]", what a /proc/<pid>/ns link says and its node is named.
// Built without the string an interpolated number leaves behind: the links
// are made again on every lookup in the directory.
fn namespace_link_text(ns &proc.Namespace) string {
	mut text := unsafe { &lib.Text(C.__builtin_alloca(sizeof(lib.Text))) }
	unsafe { *text = lib.new_text(32) }
	text.add(namespace_kind_name(ns.kind))
	text.add(':[')
	text.add_unsigned(u64(ns.id))
	text.add_byte(`]`)
	return text.str()
}

// The one nsfs node that stands for a namespace.
fn namespace_node(mut ns proc.Namespace) &VFSNode {
	ns.lock.acquire()
	defer {
		ns.lock.release()
	}
	if ns.node != unsafe { nil } {
		return unsafe { &VFSNode(ns.node) }
	}
	if nsfs_dev_id == 0 {
		nsfs_dev_id = resource.create_dev_id()
	}
	mut res := &NsFSResource{
		refcount: 1
		ns:       ns
	}
	res.stat.dev = nsfs_dev_id
	res.stat.ino = ns.id
	res.stat.mode = stat.ifreg | 0o444
	res.stat.nlink = 1
	res.stat.blksize = 4096
	res.stat.atim = realtime_clock
	res.stat.ctim = realtime_clock
	res.stat.mtim = realtime_clock
	mut node := create_node(unsafe { filesystems['tmpfs'] }, unsafe { nil }, namespace_link_text(ns),
		false)
	node.resource = res
	ns.node = voidptr(node)
	return node
}

fn (mut this NsFSResource) read(_handle voidptr, _buf voidptr, _loc u64, _count u64) ?i64 {
	errno.set(errno.einval)
	return none
}

fn (mut this NsFSResource) write(_handle voidptr, _buf voidptr, _loc u64, _count u64) ?i64 {
	errno.set(errno.einval)
	return none
}

fn (mut this NsFSResource) ioctl(handle voidptr, request u64, argp voidptr) ?int {
	return resource.default_ioctl(handle, request, argp)
}

fn (mut this NsFSResource) mmap(_handle voidptr, _page u64, _flags int) voidptr {
	return unsafe { nil }
}

fn (mut this NsFSResource) grow(_handle voidptr, _new_size u64) ? {
	errno.set(errno.einval)
	return none
}

// Called by the concrete VFS description factory even for O_PATH. dup/fork
// retain the Handle, so one namespace pin belongs to each open description.
fn (mut this NsFSResource) pin_description() ? {
	mut ns := this.ns
	if !proc.try_get_namespace(mut ns) {
		errno.set(errno.enoent)
		return none
	}
}

fn (mut this NsFSResource) unref(handle voidptr) ? {
	katomic.dec(mut &this.refcount)
	if handle != unsafe { nil } {
		mut ns := this.ns
		release_namespace(mut ns)
	}
}

fn (mut this NsFSResource) link(_handle voidptr) ? {
	katomic.inc(mut &this.stat.nlink)
}

fn (mut this NsFSResource) unlink(_handle voidptr) ? {
	katomic.dec(mut &this.stat.nlink)
}

fn (mut this NsFSResource) filesystem_stat() resource.FileSystemStat {
	return resource.FileSystemStat{
		@type:   0x6e736673 // NSFS_MAGIC
		bsize:   4096
		namelen: 255
		frsize:  4096
	}
}

// /proc/<pid>/ns: one link per namespace kind. Refreshed on every lookup,
// because unshare(2) and setns(2) change what a process is in.
fn refresh_ns_directory(mut dir VFSNode, pid int) {
	proc.lock_table()
	process := proc.process_at(pid)
	if process == unsafe { nil } || process.ns.mnt == unsafe { nil } {
		proc.unlock_table()
		return
	}
	set := process.ns
	proc.unlock_table()

	// Fixed arrays: a map literal here was made, and lost, on every lookup,
	// with a copy of each of its keys.
	names := ['cgroup', 'ipc', 'mnt', 'net', 'pid', 'pid_for_children', 'time',
		'time_for_children', 'user', 'uts']!
	pointers := [set.cgroup, set.ipc, set.mnt, set.net, set.pid, set.pid_for_children, set.time,
		set.time, set.user, set.uts]!
	for i, ns_ptr in pointers {
		if ns_ptr == unsafe { nil } {
			continue
		}
		name := names[i]
		mut ns := unsafe { ns_ptr }
		target := namespace_node(mut ns)
		if name in dir.children {
			mut existing := unsafe { dir.children[name] }
			// A namespace node's kind/id and text are immutable. Keep the
			// existing string while its identity is unchanged; rebuilding it
			// promotes a temporary lib.Text on every repeated namespace open.
			if voidptr(existing.magic_target) == voidptr(target) { continue }
			existing.magic_target = target
			set_link_text(mut existing, namespace_link_text(ns))
			continue
		}
		mut link := create_node(dir.filesystem, dir, name, false)
		link.resource = new_procfs_resource(.symlink, stat.iflnk | 0o777, pid, 0)
		link.symlink_target = namespace_link_text(ns)
		link.magic_target = target
		unsafe {
			dir.children[name] = link
		}
	}
}

// ── Making namespaces ────────────────────────────────────────────────────────

// A fresh namespace of the kind `old` is, inheriting what it should, and the
// reference to `old` dropped.
fn replace_namespace(process &proc.Process, mut old proc.Namespace) &proc.Namespace {
	mut ns := proc.copy_namespace(old)
	match old.kind {
		proc.clone_newipc {
			ns.ipc_user_ns = if process.ns.user == unsafe { nil } { u64(4026531837) } else { process.ns.user.id }
		}
		proc.clone_newns {
			ns.data = voidptr(copy_mount_table(table_of(process)))
		}
		proc.clone_newcgroup {
			ns.data = cgroup_namespace_data(process)
		}
		proc.clone_newuts {
			// The initial namespace keeps its names in the net module.
			if proc.is_initial_namespace(old) {
				ns.hostname = net.hostname_text()
				ns.domainname = net.domainname_text()
			}
		}
		else {}
	}
	release_namespace(mut old)
	return ns
}

fn release_namespace(mut ns proc.Namespace) {
	if !proc.put_namespace(mut ns) { return }
	if ns.kind == proc.clone_newipc {
		sysvmsg.destroy_namespace(ns.id)
	}
	if ns.kind == proc.clone_newns && ns.data != unsafe { nil } {
		mut table := unsafe { &MountTable(ns.data) }
		release_mount_table(mut table)
	}
}

// Move `process` into new namespaces of every kind `flags` names. For clone
// the process is the child, which has just taken its parent's references.
pub fn create_namespaces(mut process proc.Process, flags u64, for_child bool) {
	// Linux creates the user namespace first when both flags are supplied;
	// subsequently created IPC namespaces belong to that new user identity.
	// Pair these swaps with queue permission snapshots and fork inheritance.
	proc.lock_table()
	if flags & proc.clone_newuser != 0 {
		process.ns.user = replace_namespace(process, mut process.ns.user)
	}
	if flags & proc.clone_newipc != 0 {
		process.ns.ipc = replace_namespace(process, mut process.ns.ipc)
	}
	proc.unlock_table()
	if flags & proc.clone_newns != 0 {
		process.ns.mnt = replace_namespace(process, mut process.ns.mnt)
	}
	if flags & proc.clone_newuts != 0 {
		process.ns.uts = replace_namespace(process, mut process.ns.uts)
	}
	if flags & proc.clone_newnet != 0 {
		process.ns.net = replace_namespace(process, mut process.ns.net)
	}
	if flags & proc.clone_newcgroup != 0 {
		process.ns.cgroup = replace_namespace(process, mut process.ns.cgroup)
	}
	if flags & proc.clone_newtime != 0 {
		process.ns.time = replace_namespace(process, mut process.ns.time)
	}
	if flags & proc.clone_newpid != 0 {
		// unshare(CLONE_NEWPID) moves only the caller's future children; a
		// clone(CLONE_NEWPID) child is itself the first member.
		mut fresh := proc.copy_namespace(process.ns.pid_for_children)
		release_namespace(mut process.ns.pid_for_children)
		process.ns.pid_for_children = fresh
		if for_child {
			release_namespace(mut process.ns.pid)
			process.ns.pid = proc.get_namespace(mut fresh)
		}
	}
}

// The part of fork that belongs here: namespaces the flags ask for, and the
// first process born into a new pid namespace becoming its init.
pub fn fork_namespaces(mut child proc.Process, flags u64) {
	create_namespaces(mut child, flags & proc.clone_namespace_flags, true)
	mut pid_ns := child.ns.pid
	if pid_ns != unsafe { nil } && pid_ns.init_pid == 0 {
		pid_ns.init_pid = child.pid
	}
}

// Everything a process held goes when it dies.
pub fn release_process_namespaces(mut process proc.Process) {
	proc.lock_table()
	if process.ns.mnt == unsafe { nil } {
		proc.unlock_table()
		return
	}
	set := process.ns
	process.ns = proc.NamespaceSet{}
	proc.unlock_table()
	// A fixed array: a literal one was allocated, and lost, at every exit.
	for ns_ptr in [set.mnt, set.uts, set.ipc, set.net, set.pid, set.pid_for_children,
		set.cgroup, set.user, set.time]! {
		if ns_ptr != unsafe { nil } {
			mut ns := unsafe { ns_ptr }
			release_namespace(mut ns)
		}
	}
}

const clone_fs = u64(0x00000200)

const unshare_allowed = proc.clone_namespace_flags | u64(0x00000100) | clone_fs | u64(0x00000400) | u64(0x00040000)

pub fn syscall_unshare(_ voidptr, flags u64) (u64, u64) {
	// CLONE_FILES, CLONE_SIGHAND and CLONE_SYSVSEM ask to stop sharing what a
	// Vinix process never shares with another in the first place.
	if flags & ~unshare_allowed != 0 {
		return errno.err, errno.einval
	}
	if flags & proc.clone_namespace_flags & ~proc.clone_newuser != 0
		&& !proc.current_has_capability(proc.cap_sys_admin) {
		return errno.err, errno.eperm
	}
	mut process := proc.current_thread().process
	mut ns_flags := flags & proc.clone_namespace_flags
	// Root, working directory and mounts are per process until a thread of a
	// multithreaded one asks to stop sharing them (CLONE_NEWNS implies
	// CLONE_FS). From then on that thread alone sees what it changes.
	if flags & (clone_fs | proc.clone_newns) != 0
		&& (process.threads.len > 1 || proc.thread_fs_of(process) != unsafe { nil }) {
		mut own := proc.own_thread_fs()
		if ns_flags & proc.clone_newns != 0 && own.mnt != unsafe { nil } {
			own.mnt = replace_namespace(process, mut own.mnt)
			ns_flags &= ~proc.clone_newns
		}
	}
	create_namespaces(mut process, ns_flags, false)
	return 0, 0
}

// Give back a thread's own view of the filesystem when it exits.
pub fn release_thread_fs(mut t proc.Thread) {
	mut process := t.process
	process.threads_lock.acquire()
	if t.fs == unsafe { nil } {
		process.threads_lock.release()
		return
	}
	mut own := t.fs
	proc.directory_releasing(own.root_directory)
	proc.directory_releasing(own.current_directory)
	t.fs = unsafe { nil }
	process.threads_lock.release()
	if own.mnt != unsafe { nil } {
		release_namespace(mut own.mnt)
	}
	unsafe { free(own) }
}

pub fn syscall_setns(_ voidptr, fdnum int, nstype int) (u64, u64) {
	mut process := proc.current_thread().process
	mut fd := file.fd_from_fdnum(process, fdnum) or { return errno.err, errno.ebadf }
	defer {
		fd.unref()
	}
	mut res := fd.handle.resource
	if mut res !is NsFSResource {
		// A pidfd names every namespace of a process at once; Vinix has none.
		return errno.err, errno.einval
	}
	// Read through the smart cast: `res as NsFSResource` copied the resource
	// onto the heap at every call.
	mut ns := res.ns
	if nstype != 0 && u64(nstype) != ns.kind {
		return errno.err, errno.einval
	}
	if !proc.current_has_capability(proc.cap_sys_admin) {
		return errno.err, errno.eperm
	}
	match ns.kind {
		proc.clone_newns {
			// A thread with a view of its own joins by itself.
			mut own := proc.thread_fs_of(process)
			if own != unsafe { nil } && own.mnt != unsafe { nil } {
				mut old := own.mnt
				own.mnt = proc.get_namespace(mut ns)
				release_namespace(mut old)
			} else {
				mut old := process.ns.mnt
				process.ns.mnt = proc.get_namespace(mut ns)
				release_namespace(mut old)
			}
			// Joining a mount namespace puts the caller at its root.
			mut table := table_of(process)
			identity := unsafe { &lib.MountContext(C.vinix_stack_alloc(sizeof(lib.MountContext))) }
			table.lock.acquire()
			root := if table.initial || table.root_hint == unsafe { nil } {
				vfs_root
			} else {
				table.root_hint
			}
			lib.copy_mount_context(identity, &table.root_hint_mount)
			table.lock.release()
			if identity.depth == 0 && !native_context(root, identity) { return errno.err, errno.get() }
			proc.set_root_fs(mut process, if voidptr(root) == voidptr(vfs_root) {
				unsafe { nil }
			} else {
				voidptr(root)
			}, identity)
			node := get_node_on_mount(root, '.', true, identity) or { return errno.err, errno.get() }
			proc.set_current_fs(mut process, voidptr(node), identity)
		}
		proc.clone_newuts {
			mut old := process.ns.uts
			process.ns.uts = proc.get_namespace(mut ns)
			release_namespace(mut old)
		}
		proc.clone_newipc {
			proc.lock_table()
			if !proc.has_capability(process, proc.cap_sys_admin)
				|| (!proc.is_initial_namespace(process.ns.user)
					&& process.ns.user.id != ns.ipc_user_ns) {
				proc.unlock_table()
				return errno.err, errno.eperm
			}
			mut old := process.ns.ipc
			if !proc.try_get_namespace(mut ns) {
				proc.unlock_table()
				return errno.err, errno.enoent
			}
			process.ns.ipc = ns
			proc.unlock_table()
			release_namespace(mut old)
		}
		proc.clone_newnet {
			mut old := process.ns.net
			process.ns.net = proc.get_namespace(mut ns)
			release_namespace(mut old)
		}
		proc.clone_newpid {
			mut old := process.ns.pid_for_children
			process.ns.pid_for_children = proc.get_namespace(mut ns)
			release_namespace(mut old)
		}
		proc.clone_newcgroup {
			mut old := process.ns.cgroup
			process.ns.cgroup = proc.get_namespace(mut ns)
			release_namespace(mut old)
		}
		proc.clone_newuser {
			proc.lock_table()
			mut old := process.ns.user
			process.ns.user = proc.get_namespace(mut ns)
			proc.unlock_table()
			release_namespace(mut old)
		}
		proc.clone_newtime {
			mut old := process.ns.time
			process.ns.time = proc.get_namespace(mut ns)
			release_namespace(mut old)
		}
		else {
			return errno.err, errno.einval
		}
	}
	return 0, 0
}

// The hostname of the caller's UTS namespace, or none for the initial one,
// whose name the net module keeps.
pub fn uts_hostname() ?string {
	current := proc.current_thread()
	if current == unsafe { nil } || unsafe { current.process == nil } {
		return none
	}
	ns := current.process.ns.uts
	if proc.is_initial_namespace(ns) {
		return none
	}
	return ns.hostname
}

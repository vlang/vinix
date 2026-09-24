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
import net
import proc
import resource
import stat

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
	mut node := create_node(unsafe { filesystems['tmpfs'] }, unsafe { nil },
		'${namespace_kind_name(ns.kind)}:[${ns.id}]', false)
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

fn (mut this NsFSResource) unref(_handle voidptr) ? {
	katomic.dec(mut &this.refcount)
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

	entries := {
		'cgroup':            set.cgroup
		'ipc':               set.ipc
		'mnt':               set.mnt
		'net':               set.net
		'pid':               set.pid
		'pid_for_children':  set.pid_for_children
		'time':              set.time
		'time_for_children': set.time
		'user':              set.user
		'uts':               set.uts
	}
	for name, ns_ptr in entries {
		if ns_ptr == unsafe { nil } {
			continue
		}
		mut ns := unsafe { ns_ptr }
		target := namespace_node(mut ns)
		text := '${namespace_kind_name(ns.kind)}:[${ns.id}]'
		if unsafe { name in *dir.children } {
			mut existing := unsafe { dir.children[name] }
			existing.magic_target = target
			existing.symlink_target = text
			continue
		}
		mut link := create_node(dir.filesystem, dir, name, false)
		link.resource = new_procfs_resource(.symlink, stat.iflnk | 0o777, pid, 0)
		link.symlink_target = text
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
	if proc.put_namespace(mut ns) && ns.kind == proc.clone_newns && ns.data != unsafe { nil } {
		mut table := unsafe { &MountTable(ns.data) }
		release_mount_table(mut table)
	}
}

// Move `process` into new namespaces of every kind `flags` names. For clone
// the process is the child, which has just taken its parent's references.
pub fn create_namespaces(mut process proc.Process, flags u64, for_child bool) {
	if flags & proc.clone_newns != 0 {
		process.ns.mnt = replace_namespace(process, mut process.ns.mnt)
	}
	if flags & proc.clone_newuts != 0 {
		process.ns.uts = replace_namespace(process, mut process.ns.uts)
	}
	if flags & proc.clone_newipc != 0 {
		process.ns.ipc = replace_namespace(process, mut process.ns.ipc)
	}
	if flags & proc.clone_newnet != 0 {
		process.ns.net = replace_namespace(process, mut process.ns.net)
	}
	if flags & proc.clone_newcgroup != 0 {
		process.ns.cgroup = replace_namespace(process, mut process.ns.cgroup)
	}
	if flags & proc.clone_newuser != 0 {
		process.ns.user = replace_namespace(process, mut process.ns.user)
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
	if process.ns.mnt == unsafe { nil } {
		return
	}
	set := process.ns
	process.ns = proc.NamespaceSet{}
	for ns_ptr in [set.mnt, set.uts, set.ipc, set.net, set.pid, set.pid_for_children,
		set.cgroup, set.user, set.time] {
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
	if t.fs == unsafe { nil } {
		return
	}
	mut own := t.fs
	t.fs = unsafe { nil }
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
	ns_res := res as NsFSResource
	mut ns := ns_res.ns
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
			table := table_of(process)
			root := if table.initial || table.root_hint == unsafe { nil } {
				vfs_root
			} else {
				table.root_hint
			}
			proc.set_root_directory(mut process, if voidptr(root) == voidptr(vfs_root) {
				unsafe { nil }
			} else {
				voidptr(root)
			})
			proc.set_current_directory(mut process, voidptr(reduce_node(root, false)))
		}
		proc.clone_newuts {
			mut old := process.ns.uts
			process.ns.uts = proc.get_namespace(mut ns)
			release_namespace(mut old)
		}
		proc.clone_newipc {
			mut old := process.ns.ipc
			process.ns.ipc = proc.get_namespace(mut ns)
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
			mut old := process.ns.user
			process.ns.user = proc.get_namespace(mut ns)
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

// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// A small procfs: enough of /proc for Linux userspace to find out about itself.
//
// Vinix answered the two entries that mattered most — /proc/self/exe and
// /proc/self/fd/N — by substituting a pathname during resolution, which is all
// readlink(2) and exec(2) need. Directories cannot be answered that way, and
// Chromium needs three of them: every child process checks that it is still
// single-threaded by reading the link count of /proc/self/task, relative to a
// descriptor it opened on /proc itself.
//
// The tree is therefore real VFS nodes, rebuilt from the process table when a
// directory is looked up or read rather than maintained from the scheduler.
// Nothing in the clone or exit path has to take a filesystem lock, and a
// directory can never describe a process that has already gone.
@[has_globals]
module fs

import stat
import klock
import memory
import katomic
import errno
import proc
import file
import resource
import event.eventstruct
import memory.mmap
import time

// Matches what uname(2) reports, so a program that compares the two agrees
// with itself.
const uname_release = '0.1.0'

// What a node under /proc describes. Directories are rebuilt on access; the
// files generate their contents when they are read.
enum ProcFSKind {
	directory
	symlink
	cmdline
	comm
	process_stat
	statm
	status
	meminfo
	uptime
	version
	text
}

@[heap]
struct ProcFSResource {
pub mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock
	event    eventstruct.Event
	status   int
	can_mmap bool

	kind ProcFSKind
	// The process and thread this node describes, or zero for the machine-wide
	// files and the static ones under /proc/sys.
	pid  int
	tid  int
	text string
}

struct ProcFS {}

__global (
	procfs_dev_id        u64
	procfs_inode_counter u64
	procfs_root          &VFSNode
	// The per-process `self` link. Its target depends on who is reading it, so
	// path resolution asks this module rather than reading a stored string.
	procfs_self_node &VFSNode
	// procfs owns only its own subtree. Keeping it off vfs_lock means a refresh
	// can run from the middle of path resolution, which does not hold that lock
	// and must not start to.
	procfs_lock klock.Lock
)

fn (this ProcFS) instantiate() &FileSystem {
	return &ProcFS{}
}

fn (this ProcFS) populate(_node &VFSNode) {}

fn (mut this ProcFS) mount(parent &VFSNode, name string, _source &VFSNode) ?&VFSNode {
	if procfs_dev_id == 0 {
		procfs_dev_id = resource.create_dev_id()
	}
	if unsafe { procfs_root != 0 } {
		return procfs_root
	}

	mut root := create_node(this, parent, name, true)
	root.resource = new_procfs_resource(.directory, stat.ifdir | 0o555, 0, 0)
	procfs_root = root

	// The machine-wide files never come and go, so they are made once.
	// Only what the kernel can answer truthfully. Per-CPU accounting is not
	// exported yet, so there is no cpuinfo or stat here to be believed;
	// sysconf() counts processors through sched_getaffinity(2), which is
	// accurate.
	add_procfs_file(mut root, 'meminfo', .meminfo)
	add_procfs_file(mut root, 'uptime', .uptime)
	add_procfs_file(mut root, 'version', .version)

	mut sys := add_procfs_directory(mut root, 'sys')
	mut sys_fs := add_procfs_directory(mut sys, 'fs')
	add_procfs_text(mut sys_fs, 'nr_open', '${proc.max_fds}\n')
	mut inotify := add_procfs_directory(mut sys_fs, 'inotify')
	add_procfs_text(mut inotify, 'max_user_watches', '8192\n')
	add_procfs_text(mut inotify, 'max_user_instances', '128\n')
	add_procfs_text(mut inotify, 'max_queued_events', '16384\n')
	mut sys_kernel := add_procfs_directory(mut sys, 'kernel')
	add_procfs_text(mut sys_kernel, 'ostype', 'Linux\n')
	add_procfs_text(mut sys_kernel, 'osrelease', '${uname_release}\n')
	add_procfs_text(mut sys_kernel, 'pid_max', '${proc.max_pid}\n')

	// `self` is a symlink whose target is the reader's own directory. The
	// stored target is only what a listing shows; resolution goes through
	// procfs_self_target().
	mut self_node := create_node(this, root, 'self', false)
	self_node.resource = new_procfs_resource(.symlink, stat.iflnk | 0o777, 0, 0)
	self_node.symlink_target = 'self'
	unsafe {
		root.children['self'] = self_node
	}
	procfs_self_node = self_node

	return root
}

fn (mut this ProcFS) create(_parent &VFSNode, _name string, _mode u32) &VFSNode {
	return unsafe { nil }
}

fn (mut this ProcFS) symlink(_parent &VFSNode, _dest string, _target string) &VFSNode {
	return unsafe { nil }
}

fn (mut this ProcFS) link(_parent &VFSNode, _path string, mut _old_node VFSNode) ?&VFSNode {
	errno.set(errno.eperm)
	return none
}

fn (mut this ProcFS) rename(_old_parent &VFSNode, _old_name string, _new_parent &VFSNode,
	_new_name string, _flags int) ? {
	errno.set(errno.eperm)
	return none
}

fn new_procfs_resource(kind ProcFSKind, mode u32, pid int, tid int) &ProcFSResource {
	mut new_resource := &ProcFSResource{
		kind:     kind
		pid:      pid
		tid:      tid
		refcount: 1
	}
	new_resource.stat.size = 0
	new_resource.stat.blocks = 0
	new_resource.stat.blksize = 512
	new_resource.stat.dev = procfs_dev_id
	new_resource.stat.ino = procfs_inode_counter++
	new_resource.stat.mode = mode
	// A directory starts at two links, for itself and for its `.` entry. Each
	// subdirectory adds one; Chromium reads exactly this number off
	// /proc/self/task to count the threads of the process it is running in.
	new_resource.stat.nlink = if stat.isdir(mode) { u64(2) } else { u64(1) }
	new_resource.stat.atim = realtime_clock
	new_resource.stat.ctim = realtime_clock
	new_resource.stat.mtim = realtime_clock
	return new_resource
}

fn add_procfs_directory(mut parent VFSNode, name string) &VFSNode {
	mut node := create_node(parent.filesystem, parent, name, true)
	node.resource = new_procfs_resource(.directory, stat.ifdir | 0o555, 0, 0)
	node.create_dotentries(parent)
	unsafe {
		parent.children[name] = node
		parent.resource.stat.nlink++
	}
	return node
}

fn add_procfs_file(mut parent VFSNode, name string, kind ProcFSKind) &VFSNode {
	mut node := create_node(parent.filesystem, parent, name, false)
	node.resource = new_procfs_resource(kind, stat.ifreg | 0o444, 0, 0)
	unsafe {
		parent.children[name] = node
	}
	return node
}

fn add_procfs_text(mut parent VFSNode, name string, text string) &VFSNode {
	mut node := add_procfs_file(mut parent, name, .text)
	mut file_resource := unsafe { &ProcFSResource(node.resource) }
	file_resource.text = text
	file_resource.stat.size = u64(text.len)
	return node
}

// ── Generated file contents ──────────────────────────────────────────────────

fn (this &ProcFSResource) contents() string {
	match this.kind {
		.text {
			return this.text
		}
		.meminfo {
			total_kb := memory.total_bytes() / 1024
			free_kb := memory.free_bytes() / 1024
			return 'MemTotal:       ${total_kb} kB\nMemFree:        ${free_kb} kB\nMemAvailable:   ${free_kb} kB\nBuffers:               0 kB\nCached:                0 kB\nSwapTotal:             0 kB\nSwapFree:              0 kB\n'
		}
		.uptime {
			seconds := time.monotonic_ns() / 1000000000
			hundredths := (time.monotonic_ns() / 10000000) % 100
			return '${seconds}.${hundredths:02} ${seconds}.${hundredths:02}\n'
		}
		.version {
			return 'Linux version ${uname_release} (vinix) #1 SMP\n'
		}
		.cmdline {
			// Vinix does not retain the argument vector after exec, so the one
			// thing the kernel does know goes here: the program that is running.
			// Linux NUL-terminates each argument, and readers split on that.
			return '${proc.process_program(this.pid)}\x00'
		}
		.comm {
			return '${proc.process_command(this.pid)}\n'
		}
		.process_stat {
			return proc.process_stat_line(this.pid)
		}
		.statm {
			pages := resident_bytes(this.pid) / page_size
			return '${pages} ${pages} 0 0 0 0 0\n'
		}
		.status {
			return proc.process_status_text(this.pid)
		}
		else {
			return ''
		}
	}
}

fn (mut this ProcFSResource) read(_handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
	if stat.isdir(this.stat.mode) {
		errno.set(errno.eisdir)
		return none
	}

	text := this.contents()
	if loc >= u64(text.len) {
		return i64(0)
	}
	mut actual_count := count
	if loc + actual_count > u64(text.len) {
		actual_count = u64(text.len) - loc
	}
	unsafe { C.memcpy(buf, &u8(text.str) + loc, actual_count) }
	return i64(actual_count)
}

fn (mut this ProcFSResource) write(_handle voidptr, _buf voidptr, _loc u64, _count u64) ?i64 {
	errno.set(errno.eperm)
	return none
}

fn (mut this ProcFSResource) ioctl(handle voidptr, request u64, argp voidptr) ?int {
	return resource.default_ioctl(handle, request, argp)
}

fn (mut this ProcFSResource) mmap(_handle voidptr, _page u64, _flags int) voidptr {
	return unsafe { nil }
}

fn (mut this ProcFSResource) grow(_handle voidptr, _new_size u64) ? {
	errno.set(errno.eperm)
	return none
}

fn (mut this ProcFSResource) unref(_handle voidptr) ? {
	katomic.dec(mut &this.refcount)
}

fn (mut this ProcFSResource) link(_handle voidptr) ? {
	katomic.inc(mut &this.stat.nlink)
}

fn (mut this ProcFSResource) unlink(_handle voidptr) ? {
	katomic.dec(mut &this.stat.nlink)
}

fn (mut this ProcFSResource) filesystem_stat() resource.FileSystemStat {
	return resource.FileSystemStat{
		@type:   0x9fa0 // PROC_SUPER_MAGIC
		bsize:   page_size
		blocks:  0
		bfree:   0
		bavail:  0
		files:   0
		ffree:   0
		namelen: 255
		frsize:  page_size
	}
}

// A process' committed address space. mmap() pre-faults every accessible range,
// so its length is resident; a PROT_NONE reservation deliberately owns no pages
// and must not be counted as memory in use.
fn resident_bytes(pid int) u64 {
	proc.lock_table()
	defer {
		proc.unlock_table()
	}
	process := proc.process_at(pid)
	if process == unsafe { nil } {
		return 0
	}
	mut pagemap := process.pagemap
	if unsafe { pagemap == nil } {
		return 0
	}
	// Taken without blocking: a process in the middle of an mmap holds its
	// pagemap while it goes on to touch the allocator, and blocking here would
	// put a lock this file takes underneath one the rest of the kernel takes
	// first. A process that is busy remapping itself reports zero this once.
	if !pagemap.l.test_and_acquire() {
		return 0
	}
	mut total := u64(0)
	for i := 0; i < pagemap.mmap_ranges.len; i++ {
		local_range := unsafe { &mmap.MmapRangeLocal(pagemap.mmap_ranges[i]) }
		if unsafe { local_range == nil } || local_range.prot == mmap.prot_none {
			continue
		}
		total += local_range.length
	}
	pagemap.l.release()
	return total
}

// ── Rebuilding the tree ──────────────────────────────────────────────────────

// The target of /proc/self for the process that is reading it.
pub fn procfs_self_target() string {
	mut process := proc.current_thread().process
	if unsafe { process == 0 } {
		return ''
	}
	return '/proc/${process.pid}'
}

// True when the node is the `self` link, which resolves per reading process.
pub fn procfs_is_self_link(node &VFSNode) bool {
	return unsafe { procfs_self_node != 0 } && voidptr(node) == voidptr(procfs_self_node)
}

// Bring a procfs directory up to date with the process table. Called from path
// resolution and from readdir, and a no-op for every other filesystem.
pub fn procfs_refresh(node &VFSNode) {
	if unsafe { procfs_root == 0 } || node == unsafe { nil } {
		return
	}
	mut target := unsafe { node }
	if target.resource == unsafe { nil } || !stat.isdir(target.resource.stat.mode) {
		return
	}
	if voidptr(target.filesystem) == unsafe { nil } || target.children == unsafe { nil } {
		return
	}
	if !is_procfs_resource(target.resource) {
		return
	}
	directory := unsafe { &ProcFSResource(target.resource) }

	procfs_lock.acquire()
	defer {
		procfs_lock.release()
	}

	if voidptr(target) == voidptr(procfs_root) {
		refresh_process_directories(mut target)
	} else if directory.tid == 0 && directory.pid != 0 {
		if target.name == 'task' {
			refresh_thread_directories(mut target, directory.pid)
		} else if target.name == 'fd' {
			refresh_fd_directory(mut target, directory.pid)
		}
	}
}

fn is_procfs_resource(res &resource.Resource) bool {
	return res.stat.dev == procfs_dev_id && procfs_dev_id != 0
}

// One directory per live process, named by pid.
fn refresh_process_directories(mut root VFSNode) {
	mut live := []int{}
	defer {
		unsafe { live.free() }
	}
	proc.lock_table()
	for pid := 1; pid < proc.max_pid; pid++ {
		if unsafe { proc.process_at(pid) != 0 } {
			live << pid
		}
	}
	proc.unlock_table()

	for pid in live {
		name := '${pid}'
		if name in root.children {
			// exec() replaces the program without replacing the process, so
			// the link has to be taken again rather than only created once.
			mut existing := unsafe { root.children[name] }
			if existing != unsafe { nil } && existing.children != unsafe { nil }
				&& 'exe' in existing.children {
				mut exe := unsafe { existing.children['exe'] }
				exe.symlink_target = proc.process_program(pid)
			}
			continue
		}
		add_process_directory(mut root, pid)
	}
	prune_directories(mut root, live)
}

fn add_process_directory(mut root VFSNode, pid int) {
	name := '${pid}'
	mut node := create_node(root.filesystem, root, name, true)
	node.resource = new_procfs_resource(.directory, stat.ifdir | 0o555, pid, 0)
	node.create_dotentries(root)
	unsafe {
		root.children[name] = node
		root.resource.stat.nlink++
	}

	add_process_file(mut node, 'cmdline', .cmdline, pid)
	add_process_file(mut node, 'comm', .comm, pid)
	add_process_file(mut node, 'stat', .process_stat, pid)
	add_process_file(mut node, 'statm', .statm, pid)
	add_process_file(mut node, 'status', .status, pid)

	mut exe := create_node(node.filesystem, node, 'exe', false)
	exe.resource = new_procfs_resource(.symlink, stat.iflnk | 0o777, pid, 0)
	exe.symlink_target = proc.process_program(pid)
	unsafe {
		node.children['exe'] = exe
	}

	mut task := add_procfs_directory(mut node, 'task')
	mut task_resource := unsafe { &ProcFSResource(task.resource) }
	task_resource.pid = pid
	refresh_thread_directories(mut task, pid)

	mut descriptors := add_procfs_directory(mut node, 'fd')
	mut fd_resource := unsafe { &ProcFSResource(descriptors.resource) }
	fd_resource.pid = pid
	refresh_fd_directory(mut descriptors, pid)
}

// One symlink per open descriptor, named by its number. Chromium's sandbox
// counts these and refuses to start a child that inherited a directory.
fn refresh_fd_directory(mut descriptors VFSNode, pid int) {
	mut live := []int{}
	mut nodes := []&VFSNode{}
	defer {
		unsafe {
			live.free()
			nodes.free()
		}
	}

	proc.lock_table()
	mut process := proc.process_at(pid)
	if process != unsafe { nil } {
		// Taken without blocking: this already holds the process table, and a
		// process in the middle of opening a file holds its descriptor table
		// while it goes on to take filesystem locks. A process that is busy
		// changing its descriptors lists none for this one lookup.
		if process.fds_lock.test_and_acquire() {
			for fdnum := 0; fdnum < proc.max_fds; fdnum++ {
				if process.fds[fdnum] == unsafe { nil } {
					continue
				}
				entry := unsafe { &file.FD(process.fds[fdnum]) }
				if entry.handle == unsafe { nil } || entry.handle.node == unsafe { nil } {
					continue
				}
				// Sockets, pipes and memfds have no node and so no entry here.
				// Linux names them `socket:[n]` and answers a stat of that name
				// from the open file itself; a pathname Vinix cannot resolve
				// would be worse than leaving the descriptor out of the list.
				live << fdnum
				nodes << unsafe { &VFSNode(entry.handle.node) }
			}
			process.fds_lock.release()
		}
	}
	proc.unlock_table()

	for index, fdnum in live {
		name := '${fdnum}'
		if name in descriptors.children {
			mut existing := unsafe { descriptors.children[name] }
			existing.redir = nodes[index]
			continue
		}
		// A redirect rather than a stored pathname: the entry has to lead to
		// the file the descriptor is open on, and Chromium stats these names
		// through the directory it opened rather than by path.
		mut link := create_node(descriptors.filesystem, descriptors, name, false)
		link.resource = new_procfs_resource(.symlink, stat.iflnk | 0o777, pid, 0)
		link.redir = nodes[index]
		unsafe {
			descriptors.children[name] = link
		}
	}
	prune_directories(mut descriptors, live)
}

fn add_process_file(mut parent VFSNode, name string, kind ProcFSKind, pid int) {
	mut node := create_node(parent.filesystem, parent, name, false)
	node.resource = new_procfs_resource(kind, stat.ifreg | 0o444, pid, 0)
	unsafe {
		parent.children[name] = node
	}
}

// One directory per live thread, named by tid. Its link count is what tells a
// caller how many threads the process has.
fn refresh_thread_directories(mut task VFSNode, pid int) {
	mut live := proc.thread_ids(pid)
	defer {
		unsafe { live.free() }
	}

	for tid in live {
		name := '${tid}'
		if name in task.children {
			continue
		}
		mut node := create_node(task.filesystem, task, name, true)
		node.resource = new_procfs_resource(.directory, stat.ifdir | 0o555, pid, tid)
		node.create_dotentries(task)
		unsafe {
			task.children[name] = node
			task.resource.stat.nlink++
		}
		add_process_file(mut node, 'comm', .comm, pid)
		add_process_file(mut node, 'stat', .process_stat, pid)
	}
	prune_directories(mut task, live)
}

// Drop the directories whose process or thread has gone. A node is only freed
// when procfs holds the last reference to its resource; one that a descriptor
// is still open on is unlinked from the tree and left to that descriptor.
fn prune_directories(mut parent VFSNode, live []int) {
	mut stale := []string{}
	defer {
		unsafe { stale.free() }
	}
	for name, _ in parent.children {
		if name.len == 0 || name[0] < `0` || name[0] > `9` {
			continue
		}
		mut identifier := 0
		mut numeric := true
		for digit in name {
			if digit < `0` || digit > `9` {
				numeric = false
				break
			}
			identifier = identifier * 10 + int(digit - `0`)
		}
		if !numeric {
			continue
		}
		mut found := false
		for value in live {
			if value == identifier {
				found = true
				break
			}
		}
		if !found {
			stale << name
		}
	}

	for name in stale {
		mut node := unsafe { parent.children[name] }
		parent.children.delete(name)
		unsafe {
			if parent.resource.stat.nlink > 2 {
				parent.resource.stat.nlink--
			}
		}
		if node == unsafe { nil } {
			continue
		}
		mut node_resource := node.resource
		if node_resource != unsafe { nil } {
			node_resource.stat.nlink = 0
			node_resource.unref(unsafe { nil }) or {}
		}
	}
}

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
import lib
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
	self_link
	thread_self_link
	cmdline
	comm
	process_stat
	statm
	status
	meminfo
	uptime
	version
	text
	cpuinfo
	machine_stat
	filesystems
	self_mounts
	mountinfo
	mounts
	mountstats
	maps
	smaps
	oom_score_adj
	setgroups
	uid_map
	gid_map
	loginuid
	process_cgroup
	environ
	sysctl
	sysrq_trigger
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
	// A /proc/<pid> or /proc/<pid>/task/<tid> directory is filled in the first
	// time something looks inside it. Building every entry of every process
	// and thread on each refresh of /proc cost a few hundred nodes per Go
	// program, which outlive the process: pruning cannot free nodes a
	// concurrent path walk may still be standing on.
	lazy      bool
	populated bool
	// On a /proc root and the process and thread directories under it, the
	// pid namespace whose numbers name them; nil for the initial one.
	view voidptr
	// The text each open file of maps or smaps is reading; see snapshot_read().
	snapshots []ProcFSSnapshot
}

struct ProcFSSnapshot {
mut:
	handle voidptr
	text   string
}

struct ProcFS {}

// A /proc mounted from inside a pid namespace lists that namespace's members,
// by the numbers it gives them. Each namespace gets its own tree, made the
// first time it mounts one.
struct ProcFSView {
	ns   voidptr
	root &VFSNode = unsafe { nil }
}

__global (
	procfs_dev_id        u64
	procfs_inode_counter u64
	procfs_root          &VFSNode
	// The per-process `self` link. Its target depends on who is reading it, so
	// path resolution asks this module rather than reading a stored string.
	procfs_self_node        &VFSNode
	procfs_thread_self_node &VFSNode
	procfs_views            []ProcFSView
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
	// Linux numbers the procfs root inode PROC_ROOT_INO (1), and container
	// runtimes reject a /proc whose root is not inode 1 as a spoofed procfs
	// (CVE-2019-16884). Start the counter there so the root, made first, is 1;
	// a namespace's root is given inode 1 too.
	if procfs_inode_counter == 0 {
		procfs_inode_counter = 1
	}
	view := proc.current_pid_namespace()
	if proc.numbers_own(view) {
		procfs_lock.acquire()
		defer {
			procfs_lock.release()
		}
		for existing in procfs_views {
			if existing.ns == voidptr(view) {
				return existing.root
			}
		}
		// A namespace nothing is left in has no more use for its tree, and a
		// container's comes and goes with every run.
		for i in 0 .. procfs_views.len {
			if !proc.namespace_has_members(unsafe { &proc.Namespace(procfs_views[i].ns) }) {
				procfs_views[i].ns = voidptr(view)
				mut reused := procfs_views[i].root
				retarget_view(mut reused, voidptr(view))
				return reused
			}
		}
		mut root := this.build_root(parent, name, voidptr(view))
		procfs_views << ProcFSView{
			ns:   voidptr(view)
			root: root
		}
		return root
	}
	if unsafe { procfs_root != 0 } {
		return procfs_root
	}
	mut root := this.build_root(parent, name, unsafe { nil })
	procfs_root = root
	procfs_self_node = unsafe { root.children['self'] }
	procfs_thread_self_node = unsafe { root.children['thread-self'] }
	return root
}

// Hand a tree to another pid namespace. The directories of the old one's
// processes go: its numbers start again at 1 in the new one.
fn retarget_view(mut root VFSNode, view voidptr) {
	mut root_resource := unsafe { &ProcFSResource(root.resource) }
	root_resource.view = view
	for link_name in ['self', 'thread-self'] {
		if link_name in root.children {
			link := unsafe { root.children[link_name] }
			mut link_resource := unsafe { &ProcFSResource(link.resource) }
			link_resource.view = view
		}
	}
	prune_directories(mut root, []int{})
}

// A /proc tree: the machine-wide files, and the process directories of the pid
// namespace `view` (nil for the initial one), filled in on first look.
fn (mut this ProcFS) build_root(parent &VFSNode, name string, view voidptr) &VFSNode {
	mut root := create_node(this, parent, name, true)
	mut root_resource := new_procfs_resource(.directory, stat.ifdir | 0o555, 0, 0)
	root_resource.view = view
	if view != unsafe { nil } {
		root_resource.stat.ino = 1
	}
	root.resource = root_resource

	// The machine-wide files never come and go, so they are made once.
	// Only what the kernel can answer truthfully. Per-CPU accounting is not
	// exported yet, so there is no cpuinfo or stat here to be believed;
	// sysconf() counts processors through sched_getaffinity(2), which is
	// accurate.
	add_procfs_file(mut root, 'meminfo', .meminfo)
	add_procfs_file(mut root, 'uptime', .uptime)
	add_procfs_file(mut root, 'version', .version)
	mut sysrq := add_procfs_file(mut root, 'sysrq-trigger', .sysrq_trigger)
	sysrq.resource.stat.mode = stat.ifreg | 0o200

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
	add_procfs_text(mut sys_kernel, 'threads-max', '${proc.max_pid}\n')
	mut sys_kernel_keys := add_procfs_directory(mut sys_kernel, 'keys')
	add_procfs_text(mut sys_kernel_keys, 'root_maxkeys', '1000000\n')
	add_procfs_text(mut sys_kernel_keys, 'root_maxbytes', '25000000\n')
	add_procfs_text(mut sys_kernel_keys, 'maxkeys', '1000000\n')
	add_procfs_text(mut sys_kernel_keys, 'maxbytes', '25000000\n')

	// `self` is a symlink whose target is the reader's own directory. The
	// stored target is only what a listing shows; resolution goes through
	// procfs_self_target().
	mut self_node := create_node(this, root, 'self', false)
	mut self_resource := new_procfs_resource(.self_link, stat.iflnk | 0o777, 0, 0)
	self_resource.view = view
	self_node.resource = self_resource
	self_node.symlink_target = 'self'
	unsafe {
		root.children['self'] = self_node
	}

	mut thread_self := create_node(this, root, 'thread-self', false)
	mut thread_self_resource := new_procfs_resource(.thread_self_link, stat.iflnk | 0o777,
		0, 0)
	thread_self_resource.view = view
	thread_self.resource = thread_self_resource
	thread_self.symlink_target = 'thread-self'
	unsafe {
		root.children['thread-self'] = thread_self
	}

	// Machine-wide files a container runtime reads at startup.
	add_procfs_file(mut root, 'cpuinfo', .cpuinfo)
	add_procfs_file(mut root, 'stat', .machine_stat)
	add_procfs_file(mut root, 'filesystems', .filesystems)
	add_procfs_file(mut root, 'mounts', .self_mounts)
	add_procfs_text(mut sys_kernel, 'cap_last_cap', '${proc.cap_last_cap}\n')
	add_procfs_text(mut sys_kernel, 'hostname', 'vinix\n')
	mut sys_vm := add_procfs_directory(mut sys, 'vm')
	add_procfs_text(mut sys_vm, 'overcommit_memory', '0\n')
	add_procfs_text(mut sys_vm, 'max_map_count', '1048576\n')
	add_procfs_text(mut sys_vm, 'mmap_min_addr', '65536\n')
	mut sys_net := add_procfs_directory(mut sys, 'net')
	mut sys_net_core := add_procfs_directory(mut sys_net, 'core')
	add_procfs_text(mut sys_net_core, 'somaxconn', '4096\n')
	build_net_sysctls(mut sys_net)

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

// A writable /proc/sys knob. Vinix does not act on most of these, but a
// container runtime reads and writes them at startup and refuses to run if one
// it expects is missing, so each is present, readable and remembers what was
// written.
fn add_procfs_sysctl(mut parent VFSNode, name string, default string) &VFSNode {
	mut node := create_node(parent.filesystem, parent, name, false)
	mut res := new_procfs_resource(.sysctl, stat.ifreg | 0o644, 0, 0)
	res.text = default
	res.stat.size = u64(default.len)
	node.resource = res
	unsafe {
		parent.children[name] = node
	}
	return node
}

// The /proc/sys/net tree Docker's bridge driver and libnetwork consult:
// forwarding switches per family and per interface class, and a few netfilter
// and conntrack tunables. ip_forward in particular is read during bridge
// driver registration, and its absence stops the daemon from starting.
fn build_net_sysctls(mut sys_net VFSNode) {
	mut ipv4 := add_procfs_directory(mut sys_net, 'ipv4')
	add_procfs_sysctl(mut ipv4, 'ip_forward', '1\n')
	add_procfs_sysctl(mut ipv4, 'ip_local_port_range', '32768\t60999\n')
	add_procfs_sysctl(mut ipv4, 'ip_unprivileged_port_start', '1024\n')
	mut ipv4_conf := add_procfs_directory(mut ipv4, 'conf')
	for scope in ['all', 'default'] {
		mut dir := add_procfs_directory(mut ipv4_conf, scope)
		add_procfs_sysctl(mut dir, 'forwarding', '1\n')
		add_procfs_sysctl(mut dir, 'route_localnet', '0\n')
		add_procfs_sysctl(mut dir, 'rp_filter', '0\n')
		add_procfs_sysctl(mut dir, 'accept_redirects', '0\n')
	}
	mut ipv4_neigh := add_procfs_directory(mut ipv4, 'neigh')
	mut ipv4_neigh_default := add_procfs_directory(mut ipv4_neigh, 'default')
	add_procfs_sysctl(mut ipv4_neigh_default, 'gc_thresh1', '128\n')
	add_procfs_sysctl(mut ipv4_neigh_default, 'gc_thresh2', '512\n')
	add_procfs_sysctl(mut ipv4_neigh_default, 'gc_thresh3', '1024\n')

	mut ipv6 := add_procfs_directory(mut sys_net, 'ipv6')
	add_procfs_sysctl(mut ipv6, 'ip_nonlocal_bind', '0\n')
	mut ipv6_conf := add_procfs_directory(mut ipv6, 'conf')
	for scope in ['all', 'default'] {
		mut dir := add_procfs_directory(mut ipv6_conf, scope)
		add_procfs_sysctl(mut dir, 'forwarding', '0\n')
		add_procfs_sysctl(mut dir, 'disable_ipv6', '0\n')
		add_procfs_sysctl(mut dir, 'accept_ra', '1\n')
	}

	mut netfilter := add_procfs_directory(mut sys_net, 'netfilter')
	add_procfs_sysctl(mut netfilter, 'nf_conntrack_max', '131072\n')
	add_procfs_sysctl(mut netfilter, 'nf_conntrack_tcp_timeout_established', '86400\n')

	mut bridge := add_procfs_directory(mut sys_net, 'bridge')
	for knob in ['bridge-nf-call-iptables', 'bridge-nf-call-ip6tables',
		'bridge-nf-call-arptables'] {
		add_procfs_sysctl(mut bridge, knob, '0\n')
	}
}

fn add_procfs_file(mut parent VFSNode, name string, kind ProcFSKind) &VFSNode {
	mut node := create_node(parent.filesystem, parent, name, false)
	node.resource = new_procfs_resource(kind, stat.ifreg | 0o444, 0, 0)
	unsafe {
		parent.children[name] = node
	}
	return node
}

// A per-process file a container runtime writes to. The id maps and setgroups
// are writable by definition; oom_score_adj is 0644 as on Linux.
fn add_process_writable(mut parent VFSNode, name string, kind ProcFSKind, pid int) {
	mut node := create_node(parent.filesystem, parent, name, false)
	node.resource = new_procfs_resource(kind, stat.ifreg | 0o644, pid, 0)
	unsafe {
		parent.children[name] = node
	}
}

// The node /proc/<pid>/root, /cwd and /exe lead to. A magic link, so a runtime
// entering a container's mount view through /proc/<pid>/root reaches the real
// directory rather than a stored path.
fn process_root_node(pid int) &VFSNode {
	proc.lock_table()
	defer { proc.unlock_table() }
	process := proc.process_at(pid)
	if process == unsafe { nil } || process.root_directory == unsafe { nil } {
		return vfs_root
	}
	return unsafe { &VFSNode(process.root_directory) }
}

fn process_cwd_node(pid int) &VFSNode {
	proc.lock_table()
	defer { proc.unlock_table() }
	process := proc.process_at(pid)
	if process == unsafe { nil } || process.current_directory == unsafe { nil } {
		return unsafe { nil }
	}
	return unsafe { &VFSNode(process.current_directory) }
}

fn process_exe_node(pid int) &VFSNode {
	proc.lock_table()
	defer { proc.unlock_table() }
	process := proc.process_at(pid)
	if process == unsafe { nil } || process.exe_node == unsafe { nil } {
		return unsafe { nil }
	}
	return unsafe { &VFSNode(process.exe_node) }
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
		.text, .sysctl {
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
			return text_with_ending(proc.process_program(this.pid), 0)
		}
		.comm {
			return text_with_ending(proc.process_command(this.pid), `\n`)
		}
		.process_stat {
			return proc.process_stat_line(this.pid, unsafe { &proc.Namespace(this.view) })
		}
		.statm {
			pages := resident_bytes(this.pid) / page_size
			mut text := lib.new_text(64)
			text.add_unsigned(pages)
			text.add_byte(` `)
			text.add_unsigned(pages)
			text.add(' 0 0 0 0 0\n')
			return text.str()
		}
		.status {
			return proc.process_status_text(this.pid, unsafe { &proc.Namespace(this.view) })
		}
		.cpuinfo {
			return cpuinfo_text()
		}
		.machine_stat {
			return machine_stat_text()
		}
		.filesystems {
			// The `nodev` column matters: a container runtime skips those when
			// choosing what to mount for a rootfs.
			return 'nodev\ttmpfs\nnodev\tproc\nnodev\tsysfs\nnodev\tdevtmpfs\nnodev\tcgroup2\nnodev\tdevpts\nnodev\toverlay\n\text2\n'
		}
		.self_mounts, .mounts {
			pid := if this.kind == .self_mounts { proc.current_thread().process.pid } else { this.pid }
			return mounts_text(pid)
		}
		.mountinfo {
			return mountinfo_text(this.pid)
		}
		.mountstats {
			return ''
		}
		.maps {
			return maps_text(this.pid, false)
		}
		.smaps {
			return maps_text(this.pid, true)
		}
		.oom_score_adj {
			mut text := lib.new_text(16)
			text.add_decimal(proc.process_oom_score_adj(this.pid))
			text.add_byte(`\n`)
			return text.str()
		}
		.setgroups {
			return 'allow\n'
		}
		.uid_map {
			return proc.id_map_text(this.pid, false)
		}
		.gid_map {
			return proc.id_map_text(this.pid, true)
		}
		.loginuid {
			return '4294967295\n'
		}
		.process_cgroup {
			return process_cgroup_text(this.pid)
		}
		.environ {
			return ''
		}
		else {
			return ''
		}
	}
}

// `owned` with one byte after it, as a new string; `owned` is freed.
fn text_with_ending(owned string, ending u8) string {
	mut text := lib.new_text(owned.len + 1)
	text.add(owned)
	text.add_byte(ending)
	unsafe { owned.free() }
	return text.str()
}

fn cpuinfo_text() string {
	mut text := ''
	count := numa.cpu_count()
	for i := 0; i < count; i++ {
		text += 'processor\t: ${i}\nBogoMIPS\t: 100.00\nFeatures\t: fp asimd\nCPU implementer\t: 0x61\nCPU architecture: 8\nCPU variant\t: 0x0\nCPU part\t: 0x000\nCPU revision\t: 0\n\n'
	}
	return text
}

fn machine_stat_text() string {
	count := numa.cpu_count()
	mut text := 'cpu  0 0 0 0 0 0 0 0 0 0\n'
	for i := 0; i < count; i++ {
		text += 'cpu${i} 0 0 0 0 0 0 0 0 0 0\n'
	}
	seconds := time.monotonic_ns() / 1000000000
	boot := (realtime_clock.tv_sec - i64(seconds))
	text += 'intr 0\nctxt 0\nbtime ${boot}\nprocesses ${proc.process_count()}\nprocs_running 1\nprocs_blocked 0\n'
	return text
}

fn (mut this ProcFSResource) read(_handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
	if stat.isdir(this.stat.mode) {
		errno.set(errno.eisdir)
		return none
	}
	if (this.kind == .maps || this.kind == .smaps) && _handle != unsafe { nil } {
		return this.snapshot_read(_handle, buf, loc, count)
	}

	text := this.contents()
	// Every kind but the stored ones makes its text afresh for each read, and
	// it is only needed until copied out.
	defer {
		if this.kind != .text && this.kind != .sysctl {
			unsafe { text.free() }
		}
	}
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

fn (mut this ProcFSResource) write(_handle voidptr, buf voidptr, _loc u64, count u64) ?i64 {
	// The writable tunables a container runtime sets. Vinix keeps only what it
	// can act on -- oom_score_adj is remembered, the user-namespace id maps are
	// accepted and applied identity-only -- and takes the rest without storing
	// it so that a runtime configuring a container is not stopped by an EPERM.
	match this.kind {
		.oom_score_adj {
			mut text := []u8{len: int(count)}
			unsafe { C.memcpy(&text[0], buf, count) }
			value := text.bytestr().trim_space().int()
			proc.set_process_oom_score_adj(this.pid, value)
			return i64(count)
		}
		.uid_map, .gid_map, .setgroups, .loginuid {
			return i64(count)
		}
		.sysrq_trigger {
			// Of the magic SysRq commands only 't', the task dump, is here.
			if count > 0 && unsafe { *&u8(buf) } == `t` {
				proc.dump_tasks()
			}

			return i64(count)
		}
		.sysctl {
			mut text := []u8{len: int(count)}
			unsafe { C.memcpy(&text[0], buf, count) }
			this.text = text.bytestr()
			this.stat.size = u64(this.text.len)
			return i64(count)
		}
		else {
			errno.set(errno.eperm)
			return none
		}
	}
}

fn (mut this ProcFSResource) ioctl(handle voidptr, request u64, argp voidptr) ?int {
	return resource.default_ioctl(handle, request, argp)
}

fn (mut this ProcFSResource) mmap(_handle voidptr, _page u64, _flags int) voidptr {
	return unsafe { nil }
}

fn (mut this ProcFSResource) grow(_handle voidptr, new_size u64) ? {
	// Opening a writable knob with O_TRUNC -- `echo 0 > file`, or a container
	// runtime setting a sysctl -- truncates it first. That is not a request to
	// resize anything; the write that follows replaces the value.
	match this.kind {
		.sysctl {
			if new_size == 0 {
				this.text = ''
				this.stat.size = 0
			}
			return
		}
		.oom_score_adj, .uid_map, .gid_map, .setgroups, .loginuid, .sysrq_trigger {
			return
		}
		else {
			errno.set(errno.eperm)
			return none
		}
	}
}

// A list of mappings is read in pieces, and made afresh for every piece it
// changed under the reader: a piece could begin in other lines than the last
// one ended in, and a reader going through smaps a kilobyte at a time, as
// musl's stdio does, found the numbers of another mapping under the one it
// looked for. Each open file reads one text, made when it starts at the
// beginning, as Linux's seq_file does.
fn (mut this ProcFSResource) snapshot_read(handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
	this.l.acquire()
	mut index := this.snapshot_index(handle)
	if index < 0 || loc == 0 {
		this.l.release()
		fresh := this.contents()
		this.l.acquire()
		index = this.snapshot_index(handle)
		if index < 0 {
			this.snapshots << ProcFSSnapshot{
				handle: handle
				text:   fresh
			}
			index = this.snapshots.len - 1
		} else {
			unsafe { this.snapshots[index].text.free() }
			this.snapshots[index].text = fresh
		}
	}
	defer {
		this.l.release()
	}
	text := this.snapshots[index].text
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

fn (this &ProcFSResource) snapshot_index(handle voidptr) int {
	for i, snapshot in this.snapshots {
		if snapshot.handle == handle {
			return i
		}
	}
	return -1
}

fn (mut this ProcFSResource) unref(_handle voidptr) ? {
	// A closed file's text goes with it.
	if _handle != unsafe { nil } && this.snapshots.len > 0 {
		this.l.acquire()
		index := this.snapshot_index(_handle)
		if index >= 0 {
			unsafe { this.snapshots[index].text.free() }
			this.snapshots.delete(index)
		}
		this.l.release()
	}
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

// /proc/<pid>/maps, and with `detailed` smaps: every mapping of the process
// as Linux lists it. glibc finds the main thread's stack in maps for
// pthread_getattr_np(), and redis will not start without smaps: it checks
// there that a page its child shares after fork counts as shared and dirty.
fn maps_text(pid int, detailed bool) string {
	mut list := []mmap.MappingInfo{}
	mut brk_base := u64(0)
	mut brk_current := u64(0)
	mut stack_end := u64(0)
	mut exe_node := &VFSNode(unsafe { nil })
	// The page map is only waited for a little at a time, with the process
	// table let go of in between.
	for _ in 0 .. 50 {
		proc.lock_table()
		process := proc.process_at(pid)
		if process == unsafe { nil } {
			proc.unlock_table()
			return ''
		}
		brk_base = process.brk_base
		brk_current = process.brk_current
		stack_end = process.stack_end
		exe_node = unsafe { &VFSNode(process.exe_node) }
		got := mmap.mappings(process.pagemap, detailed) or {
			proc.unlock_table()
			continue
		}
		proc.unlock_table()
		list = got
		break
	}
	defer {
		mmap.release_mappings(mut list)
	}

	mut exe_dev := u64(0)
	mut exe_ino := u64(0)
	if exe_node != unsafe { nil } && exe_node.resource != unsafe { nil } {
		exe_dev = exe_node.resource.stat.dev
		exe_ino = exe_node.resource.stat.ino
	}
	mut text := lib.new_text(list.len * if detailed { 900 } else { 100 })
	for info in list {
		line_start := text.len()
		text.add_radix(info.base, 16, 8)
		text.add_byte(`-`)
		text.add_radix(info.end, 16, 8)
		text.add_byte(` `)
		text.add_byte(if info.prot & mmap.prot_read != 0 { `r` } else { `-` })
		text.add_byte(if info.prot & mmap.prot_write != 0 { `w` } else { `-` })
		text.add_byte(if info.prot & mmap.prot_exec != 0 { `x` } else { `-` })
		text.add_byte(if info.shared { `s` } else { `p` })
		text.add_byte(` `)
		text.add_radix(info.offset, 16, 8)
		text.add_byte(` `)
		// st_dev split as glibc's major() and minor() split it.
		text.add_radix(((info.dev >> 8) & 0xfff) | ((info.dev >> 32) & ~u64(0xfff)), 16, 2)
		text.add_byte(`:`)
		text.add_radix((info.dev & 0xff) | ((info.dev >> 12) & ~u64(0xff)), 16, 2)
		text.add_byte(` `)
		text.add_unsigned(info.ino)
		text.add_byte(` `)
		name := mapping_name(info, exe_node, exe_dev, exe_ino, brk_base, brk_current, stack_end)
		if name.len > 0 {
			// The name starts in the column Linux pads it out to.
			for text.len() < line_start + 72 {
				text.add_byte(` `)
			}
			text.add_byte(` `)
			text.add(name)
			unsafe { name.free() }
		}
		text.add_byte(`\n`)
		if detailed {
			add_smaps_details(mut text, info)
		}
	}
	return text.str()
}

// What names a mapping, as a string of its own: the file it maps, or what
// Linux calls the program's break and its first thread's stack. Empty for
// anonymous memory.
fn mapping_name(info mmap.MappingInfo, exe_node &VFSNode, exe_dev u64, exe_ino u64, brk_base u64, brk_current u64, stack_end u64) string {
	if info.handle != unsafe { nil } {
		handle := unsafe { &file.Handle(info.handle) }
		if handle.node != unsafe { nil } {
			return pathname(unsafe { &VFSNode(handle.node) })
		}
	}
	// The program and its interpreter are mapped by exec, with no open file
	// to name them; the program is known by its inode.
	if info.file && exe_node != unsafe { nil } && info.dev == exe_dev && info.ino == exe_ino {
		return pathname(exe_node)
	}
	if info.brk && brk_current > brk_base && info.base < brk_current {
		return '[heap]'.clone()
	}
	if stack_end != 0 && info.end == stack_end {
		return '[stack]'.clone()
	}
	return ''
}

fn add_smaps_details(mut text lib.Text, info mmap.MappingInfo) {
	resident := info.resident / 1024
	shared := info.shared_resident / 1024
	private := resident - shared
	// Anonymous memory is dirty once it is there; what a file mapping holds is
	// counted as the file's, and clean.
	anonymous := !info.file
	add_smaps_line(mut text, 'Size:', (info.end - info.base) / 1024)
	add_smaps_line(mut text, 'KernelPageSize:', page_size / 1024)
	add_smaps_line(mut text, 'MMUPageSize:', page_size / 1024)
	add_smaps_line(mut text, 'Rss:', resident)
	add_smaps_line(mut text, 'Pss:', info.share / 1024)
	add_smaps_line(mut text, 'Pss_Dirty:', if anonymous { info.share / 1024 } else { u64(0) })
	add_smaps_line(mut text, 'Shared_Clean:', if anonymous { u64(0) } else { shared })
	add_smaps_line(mut text, 'Shared_Dirty:', if anonymous { shared } else { u64(0) })
	add_smaps_line(mut text, 'Private_Clean:', if anonymous { u64(0) } else { private })
	add_smaps_line(mut text, 'Private_Dirty:', if anonymous { private } else { u64(0) })
	add_smaps_line(mut text, 'Referenced:', resident)
	add_smaps_line(mut text, 'Anonymous:', if anonymous { resident } else { u64(0) })
	for name in ['KSM:', 'LazyFree:', 'AnonHugePages:', 'ShmemPmdMapped:', 'FilePmdMapped:',
		'Shared_Hugetlb:', 'Private_Hugetlb:', 'Swap:', 'SwapPss:', 'Locked:'] {
		add_smaps_line(mut text, name, 0)
	}
	text.add('THPeligible:    0\nVmFlags:')
	if info.prot & mmap.prot_read != 0 {
		text.add(' rd')
	}
	if info.prot & mmap.prot_write != 0 {
		text.add(' wr')
	}
	if info.prot & mmap.prot_exec != 0 {
		text.add(' ex')
	}
	if info.shared {
		text.add(' sh')
	}
	text.add(' mr mw me\n')
}

// `name` padded to sixteen columns and `kb` right-aligned in eight after it,
// as Linux lays out a line of smaps.
fn add_smaps_line(mut text lib.Text, name string, kb u64) {
	text.add(name)
	mut width := name.len
	mut digits := 1
	for rest := kb / 10; rest > 0; rest /= 10 {
		digits++
	}
	for width < 16 + 8 - digits {
		text.add_byte(` `)
		width++
	}
	text.add_unsigned(kb)
	text.add(' kB\n')
}

// ── Rebuilding the tree ──────────────────────────────────────────────────────

// True when the node resolves per reading thread: /proc/self and
// /proc/thread-self.
pub fn procfs_is_dynamic_link(node &VFSNode) bool {
	if node == unsafe { nil } || node.resource == unsafe { nil } || !is_procfs_resource(node.resource) {
		return false
	}
	link := unsafe { &ProcFSResource(node.resource) }
	return link.kind == .self_link || link.kind == .thread_self_link
}

// Where /proc/self or /proc/thread-self leads for the thread reading it.
pub fn procfs_dynamic_link_target(node &VFSNode) string {
	current := proc.current_thread()
	if current == unsafe { nil } || unsafe { current.process == nil } {
		return ''
	}
	// The reader as the tree the link is in numbers it. A runtime inside a new
	// pid namespace still reads the /proc it started with until it mounts the
	// namespace's own, and there it is known by its kernel pid. A reader that
	// tree cannot see has no self in it.
	link := unsafe { &ProcFSResource(node.resource) }
	view := unsafe { &proc.Namespace(link.view) }
	pid := proc.pid_in(current.process, view)
	if pid <= 0 {
		return ''
	}
	if link.kind == .thread_self_link {
		return '/proc/${pid}/task/${proc.tid_in(current, view)}'
	}
	return '/proc/${pid}'
}

// Kept for callers that only need /proc/self.
pub fn procfs_self_target() string {
	current := proc.current_thread()
	if current == unsafe { nil } || unsafe { current.process == nil } {
		return ''
	}
	return '/proc/${proc.own_pid(current.process)}'
}

// Bring a procfs directory up to date with the process table. Called from path
// resolution and from readdir, and a no-op for every other filesystem.
pub fn procfs_refresh(node &VFSNode) {
	procfs_refresh_named(node, '')
}

// The same for a lookup of `name` in it; '' is a listing.
fn procfs_refresh_named(node &VFSNode, name string) {
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
	mut directory := unsafe { &ProcFSResource(target.resource) }

	procfs_lock.acquire()
	defer {
		procfs_lock.release()
	}

	if directory.lazy && !directory.populated {
		if name.len > 0 {
			add_process_entry(mut target, directory.pid, name, directory.tid == 0)
			return
		}
		directory.populated = true
		if directory.tid == 0 {
			populate_process_directory(mut target, directory.pid)
		} else {
			add_process_entries(mut target, directory.pid)
		}
		return
	}

	if voidptr(target) == voidptr(procfs_root) || (directory.view != unsafe { nil }
		&& directory.pid == 0) {
		refresh_process_directories(mut target, directory.view)
	} else if directory.tid == 0 && directory.pid != 0 {
		if target.name == 'task' {
			refresh_thread_directories(mut target, directory.pid)
		} else if target.name == 'fd' {
			refresh_fd_directory(mut target, directory.pid)
		} else if target.name == 'ns' {
			refresh_ns_directory(mut target, directory.pid)
		}
	}
}

// Called for every name looked up in a procfs directory. The descriptor and
// namespace directories, and a process' exe, cwd and root links, change under
// a process that is already listed, so they are brought up to date on each
// lookup; the rest of the tree only when a name is missing.
pub fn procfs_lookup_refresh(node &VFSNode, name string) {
	if unsafe { procfs_root == 0 } || node == unsafe { nil } || node.resource == unsafe { nil }
		|| node.children == unsafe { nil } || !is_procfs_resource(node.resource) {
		return
	}
	directory := unsafe { &ProcFSResource(node.resource) }
	if directory.pid != 0 && (node.name == 'fd' || node.name == 'ns') {
		procfs_refresh(node)
		return
	}
	// A process directory is filled in as it is used; do that before looking
	// at what it holds.
	if name !in node.children {
		procfs_refresh_named(node, name)
	}
	if directory.pid != 0 && name in ['exe', 'cwd', 'root'] && name in node.children {
		mut link := unsafe { node.children[name] }
		match name {
			'exe' {
				set_link_text(mut link, proc.process_program(directory.pid))
				link.magic_target = process_exe_node(directory.pid)
			}
			'cwd' {
				link.magic_target = process_cwd_node(directory.pid)
			}
			else {
				link.magic_target = process_root_node(directory.pid)
			}
		}
		if link.magic_target != unsafe { nil } {
			set_link_text(mut link, pathname(link.magic_target))
		}
	}
}

// Give a link freshly made text, keeping what it has if that is the same.
// Links are looked up on every path walk through them and nearly always say
// what they said before, so the new copy is the one freed. A changed text
// leaves the old one behind: a readlink on another CPU may be copying it.
fn set_link_text(mut link VFSNode, text string) {
	if link.symlink_target == text {
		unsafe { text.free() }
		return
	}
	link.symlink_target = text
}

fn is_procfs_resource(res &resource.Resource) bool {
	return res.stat.dev == procfs_dev_id && procfs_dev_id != 0
}

// One directory per live process `view` can see, named by the number it
// gives the process.
fn refresh_process_directories(mut root VFSNode, view voidptr) {
	mut live := []int{}
	mut numbers := []int{}
	defer {
		unsafe {
			live.free()
			numbers.free()
		}
	}
	viewer := unsafe { &proc.Namespace(view) }
	proc.lock_table()
	for pid := 1; pid < proc.max_pid; pid++ {
		process := proc.process_at(pid)
		if process == unsafe { nil } {
			continue
		}
		number := proc.pid_in(process, viewer)
		if number > 0 {
			live << pid
			numbers << number
		}
	}
	proc.unlock_table()

	for i, pid in live {
		name := numbers[i].str()
		if name in root.children {
			// exec() replaces the program without replacing the process, so
			// the link has to be taken again rather than only created once.
			mut existing := unsafe { root.children[name] }
			if existing != unsafe { nil } && existing.children != unsafe { nil }
				&& 'exe' in existing.children {
				mut exe := unsafe { existing.children['exe'] }
				set_link_text(mut exe, proc.process_program(pid))
			}
			unsafe { name.free() }
			continue
		}
		add_process_directory(mut root, pid, name, view)
	}
	prune_directories(mut root, numbers)
}

fn add_process_directory(mut root VFSNode, pid int, name string, view voidptr) {
	mut node := create_node(root.filesystem, root, name, true)
	mut directory := new_procfs_resource(.directory, stat.ifdir | 0o555, pid, 0)
	directory.lazy = true
	directory.view = view
	node.resource = directory
	node.create_dotentries(root)
	unsafe {
		root.children[name] = node
		root.resource.stat.nlink++
	}
}

// What a /proc/<pid> directory holds. A listing makes all of it; a lookup
// makes only the entry it names (see add_process_entry()).
fn populate_process_directory(mut node VFSNode, pid int) {
	add_process_entries(mut node, pid)
	add_process_entry(mut node, pid, 'task', true)
}

// What /proc/<pid> and /proc/<pid>/task/<tid> both hold. A thread's
// descriptors, namespaces and mounts are its process', since Vinix threads
// share all three.
const process_entry_names = ['cmdline', 'comm', 'stat', 'statm', 'status', 'cgroup', 'environ',
	'mountinfo', 'mounts', 'mountstats', 'maps', 'smaps', 'loginuid', 'oom_score_adj', 'uid_map',
	'gid_map', 'setgroups', 'root', 'cwd', 'exe', 'fd', 'ns', 'attr']

fn add_process_entries(mut node VFSNode, pid int) {
	for name in process_entry_names {
		add_process_entry(mut node, pid, name, false)
	}
}

// Make the entry `name` of a process or thread directory unless it is there
// already, and answer whether such a directory has one. A lookup makes only
// the entry it names. Making them all on the first look gave every process
// anything looked in about thirty nodes of a kilobyte and more each, and
// each of its threads as many again, none of them ever freed: some 400 KB
// for every container a runtime started. `name` is only compared; the nodes
// are named by the literals here.
fn add_process_entry(mut node VFSNode, pid int, name string, is_process bool) bool {
	if name in node.children {
		return true
	}
	match name {
		'cmdline' { add_process_file(mut node, 'cmdline', .cmdline, pid) }
		'comm' { add_process_file(mut node, 'comm', .comm, pid) }
		'stat' { add_process_file(mut node, 'stat', .process_stat, pid) }
		'statm' { add_process_file(mut node, 'statm', .statm, pid) }
		'status' { add_process_file(mut node, 'status', .status, pid) }
		'cgroup' { add_process_file(mut node, 'cgroup', .process_cgroup, pid) }
		'environ' { add_process_file(mut node, 'environ', .environ, pid) }
		'mountinfo' { add_process_file(mut node, 'mountinfo', .mountinfo, pid) }
		'mounts' { add_process_file(mut node, 'mounts', .mounts, pid) }
		'mountstats' { add_process_file(mut node, 'mountstats', .mountstats, pid) }
		'maps' { add_process_file(mut node, 'maps', .maps, pid) }
		'smaps' { add_process_file(mut node, 'smaps', .smaps, pid) }
		'loginuid' { add_process_file(mut node, 'loginuid', .loginuid, pid) }
		'oom_score_adj' { add_process_writable(mut node, 'oom_score_adj', .oom_score_adj, pid) }
		'uid_map' { add_process_writable(mut node, 'uid_map', .uid_map, pid) }
		'gid_map' { add_process_writable(mut node, 'gid_map', .gid_map, pid) }
		'setgroups' { add_process_writable(mut node, 'setgroups', .setgroups, pid) }
		'root' {
			mut root_link := add_process_link(mut node, 'root', pid)
			root_link.magic_target = process_root_node(pid)
			if root_link.magic_target != unsafe { nil } {
				root_link.symlink_target = pathname(root_link.magic_target)
			}
		}
		'cwd' {
			mut cwd_link := add_process_link(mut node, 'cwd', pid)
			cwd_link.magic_target = process_cwd_node(pid)
			if cwd_link.magic_target != unsafe { nil } {
				cwd_link.symlink_target = pathname(cwd_link.magic_target)
			}
		}
		'exe' {
			mut exe := add_process_link(mut node, 'exe', pid)
			exe.symlink_target = proc.process_program(pid)
			exe.magic_target = process_exe_node(pid)
		}
		'fd' {
			mut descriptors := add_procfs_directory(mut node, 'fd')
			mut fd_resource := unsafe { &ProcFSResource(descriptors.resource) }
			fd_resource.pid = pid
			refresh_fd_directory(mut descriptors, pid)
		}
		'ns' {
			mut namespaces := add_procfs_directory(mut node, 'ns')
			mut ns_resource := unsafe { &ProcFSResource(namespaces.resource) }
			ns_resource.pid = pid
			refresh_ns_directory(mut namespaces, pid)
		}
		'attr' {
			mut attr := add_procfs_directory(mut node, 'attr')
			add_process_file(mut attr, 'current', .environ, pid)
		}
		'task' {
			if !is_process {
				return false
			}
			mut task := add_procfs_directory(mut node, 'task')
			mut task_resource := unsafe { &ProcFSResource(task.resource) }
			task_resource.pid = pid
			task_resource.view = unsafe { &ProcFSResource(node.resource) }.view
			refresh_thread_directories(mut task, pid)
		}
		else {
			return false
		}
	}
	return true
}

fn add_process_link(mut node VFSNode, name string, pid int) &VFSNode {
	mut link := create_node(node.filesystem, node, name, false)
	link.resource = new_procfs_resource(.symlink, stat.iflnk | 0o777, pid, 0)
	unsafe {
		node.children[name] = link
	}
	return link
}

// One symlink per open descriptor, named by its number. Chromium's sandbox
// counts these and refuses to start a child that inherited a directory.
fn refresh_fd_directory(mut descriptors VFSNode, pid int) {
	mut live := []int{}
	mut nodes := []&VFSNode{}
	mut texts := []string{}
	defer {
		unsafe {
			live.free()
			nodes.free()
			texts.free()
		}
	}

	// Taken without blocking: this holds the process table and procfs, and a
	// process in the middle of opening a file holds its descriptor table while
	// it goes on to take filesystem locks. A busy table is retried a bounded
	// number of times; if it stays busy the listing is left exactly as it was,
	// since pruning against an empty scan would make every descriptor of a
	// busy multithreaded process vanish from /proc/<pid>/fd for that lookup.
	mut scanned := false
	for attempt := 0; attempt < 4096 && !scanned; attempt++ {
		proc.lock_table()
		mut process := proc.process_at(pid)
		if process == unsafe { nil } {
			proc.unlock_table()
			break
		}
		if process.fds_lock.test_and_acquire() {
			scanned = true
			// Sized first: an array that outgrows its buffer leaves the old one
			// behind, and this runs on every lookup in the directory.
			mut open_count := 0
			for fdnum := 0; fdnum < process.fds.len; fdnum++ {
				if process.fds[fdnum] != unsafe { nil } {
					open_count++
				}
			}
			unsafe {
				live.free()
				nodes.free()
				texts.free()
			}
			live = []int{cap: open_count}
			nodes = []&VFSNode{cap: open_count}
			texts = []string{cap: open_count}
			for fdnum := 0; fdnum < process.fds.len; fdnum++ {
				if process.fds[fdnum] == unsafe { nil } {
					continue
				}
				entry := unsafe { &file.FD(process.fds[fdnum]) }
				if entry.handle == unsafe { nil } || entry.handle.resource == unsafe { nil } {
					continue
				}
				live << fdnum
				if entry.handle.node == unsafe { nil } {
					// Pipes, sockets and the anonymous descriptors have no
					// name. Linux shows their kind and inode instead, and so
					// does this; opening one again by this name is not
					// supported.
					nodes << unsafe { nil }
					texts << anonymous_descriptor_text(entry.handle.resource)
				} else {
					nodes << unsafe { &VFSNode(entry.handle.node) }
					texts << ''
				}
			}
			process.fds_lock.release()
		}
		proc.unlock_table()
	}
	if !scanned {
		return
	}

	for index, fdnum in live {
		name := fdnum.str()
		target := nodes[index]
		// A copy of the kind-and-inode text: freeing `texts` frees the strings
		// in it, and the link keeps this one.
		text := if target == unsafe { nil } { texts[index].clone() } else { descriptor_link_text(target) }
		if name in descriptors.children {
			mut existing := unsafe { descriptors.children[name] }
			existing.redir = unsafe { nil }
			existing.magic_target = target
			set_link_text(mut existing, text)
			unsafe { name.free() }
			continue
		}
		// A magic link rather than a stored pathname: following it leads to
		// the file the descriptor is open on, which Chromium relies on when it
		// stats these names through the directory, and which runc relies on
		// when it re-executes itself from a memfd.
		mut link := create_node(descriptors.filesystem, descriptors, name, false)
		link.resource = new_procfs_resource(.symlink, stat.iflnk | 0o700, pid, 0)
		link.magic_target = target
		link.symlink_target = text
		unsafe {
			descriptors.children[name] = link
		}
	}
	prune_directories(mut descriptors, live)
}

fn descriptor_link_text(node &VFSNode) string {
	if node.parent == unsafe { nil } && node.name.len > 0 {
		// A memfd or another file that was never in a directory.
		return '/${node.name} (deleted)'
	}
	return pathname(node)
}

// A /proc/<pid>/fd/<n> link to a descriptor that no name leads to: a pipe,
// a socket, an eventfd. Its text only says what that is, so following it
// takes the descriptor from the process instead; see
// open_anonymous_descriptor().
pub struct AnonymousDescriptor {
pub:
	pid   int
	fdnum int
}

pub fn procfs_anonymous_descriptor(node &VFSNode) ?AnonymousDescriptor {
	if node == unsafe { nil } || node.resource == unsafe { nil } || node.magic_target != unsafe { nil }
		|| node.parent == unsafe { nil } || node.name.len == 0 || !is_procfs_resource(node.resource) {
		return none
	}
	link := unsafe { &ProcFSResource(node.resource) }
	if link.kind != .symlink || link.pid == 0 || node.parent.name != 'fd' {
		return none
	}
	mut fdnum := 0
	for c in node.name {
		if c < `0` || c > `9` {
			return none
		}
		fdnum = fdnum * 10 + int(c - `0`)
	}
	return AnonymousDescriptor{
		pid:   link.pid
		fdnum: fdnum
	}
}

fn anonymous_descriptor_text(res &resource.Resource) string {
	mode := res.stat.mode & stat.ifmt
	if mode == stat.ifpipe || mode == stat.ififo {
		return 'pipe:[${res.stat.ino}]'
	}
	if mode == stat.ifsock {
		return 'socket:[${res.stat.ino}]'
	}
	return 'anon_inode:[${res.stat.ino}]'
}

// A process's file shows ids as the tree it is in numbers them.
fn add_process_file(mut parent VFSNode, name string, kind ProcFSKind, pid int) {
	mut node := create_node(parent.filesystem, parent, name, false)
	mut file := new_procfs_resource(kind, stat.ifreg | 0o444, pid, 0)
	file.view = unsafe { &ProcFSResource(parent.resource) }.view
	node.resource = file
	unsafe {
		parent.children[name] = node
	}
}

// One directory per live thread, named by tid. Its link count is what tells a
// caller how many threads the process has.
fn refresh_thread_directories(mut task VFSNode, pid int) {
	mut live := proc.thread_ids(pid)
	view := unsafe { &ProcFSResource(task.resource) }.view
	mut numbers := proc.thread_numbers(live, unsafe { &proc.Namespace(view) })
	defer {
		unsafe {
			live.free()
			numbers.free()
		}
	}

	for i, tid in live {
		if numbers[i] <= 0 {
			continue
		}
		name := numbers[i].str()
		if name in task.children {
			unsafe { name.free() }
			continue
		}
		mut node := create_node(task.filesystem, task, name, true)
		mut directory := new_procfs_resource(.directory, stat.ifdir | 0o555, pid, tid)
		directory.lazy = true
		directory.view = view
		node.resource = directory
		node.create_dotentries(task)
		unsafe {
			task.children[name] = node
			task.resource.stat.nlink++
		}
	}
	prune_directories(mut task, numbers)
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


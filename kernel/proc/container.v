// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The per-process state container runtimes build on: namespaces and
// capabilities.
//
// A namespace here is an identity and whatever state the kernel keeps apart
// for it. The UTS namespace owns a hostname, the mount namespace a mount table
// (kept by fs), and the pid namespace remembers its init so that its members
// can be killed together when that init dies, as Linux does. Process ids are
// not renumbered inside a pid namespace, and network, IPC, cgroup and time
// namespaces are identities only: their members share the system's stack.
@[has_globals]
module proc

import katomic
import klock

// clone(2)/unshare(2) flags that name a namespace.
pub const clone_newtime = u64(0x00000080)
pub const clone_newns = u64(0x00020000)
pub const clone_newcgroup = u64(0x02000000)
pub const clone_newuts = u64(0x04000000)
pub const clone_newipc = u64(0x08000000)
pub const clone_newuser = u64(0x10000000)
pub const clone_newpid = u64(0x20000000)
pub const clone_newnet = u64(0x40000000)

pub const clone_namespace_flags = clone_newtime | clone_newns | clone_newcgroup | clone_newuts | clone_newipc | clone_newuser | clone_newpid | clone_newnet

@[heap]
pub struct Namespace {
pub mut:
	kind     u64
	id       u64
	refcount int
	// UTS namespaces.
	hostname   string
	domainname string
	// Mount namespaces carry their mount table, cgroup namespaces the cgroup
	// that is their root. Both belong to fs.
	data voidptr
	// Pid namespaces: the process that is their init, once there is one.
	init_pid int
	// A pid namespace other than the initial one numbers its members itself:
	// `ids` maps each number it has handed out to the kernel's id for that
	// process or thread. Changed with pid_lock held.
	ids     map[int]int
	next_id int = 1
	lock    klock.Lock
	// The nsfs file /proc/<pid>/ns/<kind> leads to. One per namespace, so that
	// comparing two of them by inode tells whether they are the same one.
	node voidptr
}

// Which namespace of each kind a process is in. pid_for_children is where the
// process' next children go, which unshare(CLONE_NEWPID) changes without
// moving the caller itself.
pub struct NamespaceSet {
pub mut:
	mnt              &Namespace = unsafe { nil }
	uts              &Namespace = unsafe { nil }
	ipc              &Namespace = unsafe { nil }
	net              &Namespace = unsafe { nil }
	pid              &Namespace = unsafe { nil }
	pid_for_children &Namespace = unsafe { nil }
	cgroup           &Namespace = unsafe { nil }
	user             &Namespace = unsafe { nil }
	time             &Namespace = unsafe { nil }
}

// The Linux capability sets, one bit per CAP_* number.
pub struct Capabilities {
pub mut:
	effective   u64
	permitted   u64
	inheritable u64
	bounding    u64
	ambient     u64
	// SECBIT_KEEP_CAPS, from prctl(PR_SET_KEEPCAPS).
	keep bool
}

// CAP_CHECKPOINT_RESTORE is the highest capability Linux 6.x defines.
pub const cap_last_cap = 40
pub const cap_all = (u64(1) << (cap_last_cap + 1)) - 1

pub const cap_chown = 0
pub const cap_dac_override = 1
pub const cap_dac_read_search = 2
pub const cap_fowner = 3
pub const cap_kill = 5
pub const cap_setgid = 6
pub const cap_setuid = 7
pub const cap_setpcap = 8
pub const cap_net_admin = 12
pub const cap_sys_chroot = 18
pub const cap_sys_ptrace = 19
pub const cap_sys_admin = 21
pub const cap_sys_boot = 22
pub const cap_sys_resource = 24
pub const cap_mknod = 27
pub const cap_setfcap = 31

__global (
	namespace_id_counter = u64(4026532000)
	initial_namespaces   NamespaceSet
)

fn new_namespace(kind u64, id u64) &Namespace {
	return &Namespace{
		kind:     kind
		id:       id
		refcount: 1
	}
}

// The namespaces every process starts out in. Their ids are the ones a Linux
// system gives its initial namespaces, which is what tools expect to see.
pub fn initial_namespace_set() NamespaceSet {
	if unsafe { initial_namespaces.mnt == nil } {
		initial_namespaces = NamespaceSet{
			mnt:    new_namespace(clone_newns, 4026531841)
			uts:    new_namespace(clone_newuts, 4026531838)
			ipc:    new_namespace(clone_newipc, 4026531839)
			net:    new_namespace(clone_newnet, 4026531840)
			pid:    new_namespace(clone_newpid, 4026531836)
			cgroup: new_namespace(clone_newcgroup, 4026531835)
			user:   new_namespace(clone_newuser, 4026531837)
			time:   new_namespace(clone_newtime, 4026531834)
		}
		initial_namespaces.pid_for_children = initial_namespaces.pid
		initial_namespaces.pid.init_pid = 1
	}
	return initial_namespaces
}

pub fn is_initial_namespace(ns &Namespace) bool {
	return ns == unsafe { nil } || ns.id < 4026532000
}

// A new namespace of the same kind as `parent`, starting from its state.
pub fn copy_namespace(parent &Namespace) &Namespace {
	mut ns := new_namespace(parent.kind, katomic.inc(mut &namespace_id_counter))
	ns.hostname = parent.hostname.clone()
	ns.domainname = parent.domainname.clone()
	return ns
}

pub fn get_namespace(mut ns Namespace) &Namespace {
	katomic.inc(mut &ns.refcount)
	return ns
}

// Drop a reference, reporting whether it was the last one.
pub fn put_namespace(mut ns Namespace) bool {
	if unsafe { ns == nil } || is_initial_namespace(ns) {
		return false
	}
	return !katomic.dec(mut &ns.refcount)
}

// A thread's own root, working directory and mount namespace. Linux keeps all
// three per thread; Vinix keeps them per process, which is the same thing
// until one thread of a multithreaded process asks for its own with
// unshare(CLONE_FS) or unshare(CLONE_NEWNS). Go programs do exactly that to
// chroot inside a goroutine locked to its thread while the rest of the
// program stays put -- dockerd unpacks every image layer that way, and moving
// the whole daemon into the layer instead loses it everything else it has.
@[heap]
pub struct ThreadFS {
pub mut:
	root_directory    voidptr
	current_directory voidptr
	mnt               &Namespace = unsafe { nil }
}

// The calling thread's own view of `process`' filesystem, or nil when it sees
// the process' like every other thread does.
pub fn thread_fs_of(process &Process) &ThreadFS {
	t := current_thread()
	if t == unsafe { nil } || t.fs == unsafe { nil } || voidptr(t.process) != voidptr(process) {
		return unsafe { nil }
	}
	return t.fs
}

// Split the calling thread's root, working directory and mount namespace off
// from its process', starting from what they are now.
pub fn own_thread_fs() &ThreadFS {
	mut t := current_thread()
	if t.fs == unsafe { nil } {
		mut process := t.process
		mut own := &ThreadFS{
			root_directory:    process.root_directory
			current_directory: process.current_directory
		}
		if process.ns.mnt != unsafe { nil } {
			own.mnt = get_namespace(mut process.ns.mnt)
		}
		t.fs = own
	}
	return t.fs
}

// Where `process` resolves absolute paths from, as the calling thread sees it.
// Nil is the global root.
pub fn root_directory_of(process &Process) voidptr {
	if unsafe { process == nil } {
		return unsafe { nil }
	}
	own := thread_fs_of(process)
	if own != unsafe { nil } {
		return own.root_directory
	}
	return process.root_directory
}

pub fn set_root_directory(mut process Process, directory voidptr) {
	mut own := thread_fs_of(process)
	if own != unsafe { nil } {
		own.root_directory = directory
		return
	}
	process.root_directory = directory
}

pub fn current_directory_of(process &Process) voidptr {
	if unsafe { process == nil } {
		return unsafe { nil }
	}
	own := thread_fs_of(process)
	if own != unsafe { nil } {
		return own.current_directory
	}
	return process.current_directory
}

pub fn set_current_directory(mut process Process, directory voidptr) {
	mut own := thread_fs_of(process)
	if own != unsafe { nil } {
		own.current_directory = directory
		return
	}
	process.current_directory = directory
}

pub fn mount_namespace_of(process &Process) &Namespace {
	if unsafe { process == nil } {
		return unsafe { nil }
	}
	own := thread_fs_of(process)
	if own != unsafe { nil } {
		return own.mnt
	}
	return process.ns.mnt
}

// Everything a child takes from its parent at fork. The caller owns the
// references this takes and gives them back through release_namespaces().
pub fn inherit_container_state(mut child Process, parent &Process) {
	if unsafe { parent == nil } || unsafe { parent.ns.mnt == nil } {
		child.ns = initial_namespace_set()
		child.caps = full_capabilities()
		return
	}
	// A thread with a view of its own passes that on, as on Linux.
	mut parent_mnt := mount_namespace_of(parent)
	if unsafe { parent_mnt == nil } {
		parent_mnt = parent.ns.mnt
	}
	child.ns = NamespaceSet{
		mnt:              get_namespace(mut parent_mnt)
		uts:              get_namespace(mut parent.ns.uts)
		ipc:              get_namespace(mut parent.ns.ipc)
		net:              get_namespace(mut parent.ns.net)
		pid:              get_namespace(mut parent.ns.pid_for_children)
		pid_for_children: get_namespace(mut parent.ns.pid_for_children)
		cgroup:           get_namespace(mut parent.ns.cgroup)
		user:             get_namespace(mut parent.ns.user)
		time:             get_namespace(mut parent.ns.time)
	}
	child.root_directory = root_directory_of(parent)
	child.caps = parent.caps
	child.no_new_privs = parent.no_new_privs
	child.cgroup = parent.cgroup
	child.cgroup_account = parent.cgroup_account
	child.oom_score_adj = parent.oom_score_adj
	child.exe_node = parent.exe_node
}

pub fn full_capabilities() Capabilities {
	return Capabilities{
		effective: cap_all
		permitted: cap_all
		bounding:  cap_all
	}
}

pub fn has_capability(process &Process, cap int) bool {
	if unsafe { process == nil } {
		return true
	}
	return process.caps.effective & (u64(1) << cap) != 0
}

pub fn current_has_capability(cap int) bool {
	return has_capability(current_thread().process, cap)
}

// The capability sets a program starts with after execve(2), for a file that
// carries no file capabilities: root gets everything its bounding set and
// inheritable set allow, everybody else keeps only the ambient set.
pub fn capabilities_after_exec(mut process Process) {
	mut caps := process.caps
	if process.euid == 0 || process.uid == 0 {
		caps.permitted = (caps.inheritable | caps.bounding) | caps.ambient
		caps.effective = if process.euid == 0 { caps.permitted } else { caps.ambient }
	} else {
		caps.permitted = caps.ambient
		caps.effective = caps.ambient
	}
	// SECBIT_KEEP_CAPS does not survive exec; no_new_privs does.
	caps.keep = false
	process.caps = caps
}

// Linux clears the permitted and effective sets when a process that had a uid
// of zero keeps none, unless it asked to keep them; dropping the effective uid
// alone clears only the effective set. Called after every credential change.
pub fn capabilities_after_setuid(mut process Process, old_ruid u32, old_euid u32, old_suid u32) {
	had_root := old_ruid == 0 || old_euid == 0 || old_suid == 0
	has_root := process.uid == 0 || process.euid == 0 || process.suid == 0
	if had_root && !has_root && !process.caps.keep {
		process.caps.permitted = 0
		process.caps.effective = 0
		process.caps.ambient = 0
	}
	if old_euid == 0 && process.euid != 0 {
		process.caps.effective = 0
	}
	if old_euid != 0 && process.euid == 0 {
		process.caps.effective = process.caps.permitted
	}
}

pub fn process_oom_score_adj(pid int) int {
	lock_table()
	defer { unlock_table() }
	process := process_at(pid)
	if process == unsafe { nil } {
		return 0
	}
	return process.oom_score_adj
}

pub fn set_process_oom_score_adj(pid int, value int) {
	lock_table()
	defer { unlock_table() }
	mut process := process_at(pid)
	if process == unsafe { nil } {
		return
	}
	mut clamped := value
	if clamped < -1000 {
		clamped = -1000
	}
	if clamped > 1000 {
		clamped = 1000
	}
	process.oom_score_adj = clamped
}

// The identity id map a process starts a user namespace with: everything maps
// to itself, since Vinix does not renumber ids across a user namespace.
pub fn id_map_text(pid int, _group bool) string {
	lock_table()
	defer { unlock_table() }
	process := process_at(pid)
	if process == unsafe { nil } || is_initial_namespace(process.ns.user) {
		return '         0          0 4294967295\n'
	}
	return '         0          0 4294967295\n'
}

// Every live process whose pid namespace is `ns`, other than its init.
pub fn pid_namespace_members(ns &Namespace) []int {
	mut members := []int{}
	lock_table()
	defer { unlock_table() }
	for pid := 1; pid < max_pid; pid++ {
		process := processes[pid]
		if process == unsafe { nil } || process.pid == ns.init_pid {
			continue
		}
		if voidptr(process.ns.pid) == voidptr(ns) && !process.exiting {
			members << pid
		}
	}
	return members
}

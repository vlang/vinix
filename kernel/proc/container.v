// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The per-process state container runtimes build on: namespaces and
// capabilities.
//
// A namespace here is an identity and whatever state the kernel keeps apart
// for it. The UTS namespace owns a hostname, the mount namespace a mount table
// (kept by fs), and the pid namespace remembers its init so that its members
// can be killed together when that init dies, as Linux does.
// System V message queues have separate IPC registries; existing semaphores
// and shared-memory segments still use global registries. A network
// namespace other than the initial one has only loopback and no IP sockets
// (socket/socket.v); abstract Unix socket names are per network namespace.
// A user namespace gives its creator capabilities that act only on the
// namespaces it owns (has_namespace_capability). Cgroup and time namespace
// identities do not alone separate their subsystems.
@[has_globals]
module proc

import errno
import katomic
import klock
import lib

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

// An identity without isolated state is not a namespace implementation.
// Refuse these requests before clone/unshare changes any process state.
pub const unsupported_namespace_flags = clone_newtime

// setns(2) may not join these: entering a user namespace would need the
// credential rules Linux applies there, which Vinix does not implement, and
// a network namespace keeps state (IP sockets, abstract names) per process.
pub const unsupported_setns_flags = unsupported_namespace_flags | clone_newuser | clone_newnet

@[heap]
pub struct Namespace {
pub mut:
	kind     u64
	id       u64
	refcount int
	// Immutable user-namespace identity that governs IPC capabilities. A user
	// namespace alone must not transfer ownership of an inherited IPC one.
	ipc_user_ns u64 = 4026531837
	ipc_fsuid u32
	ipc_fsgid u32
	// UTS namespaces.
	hostname   string
	domainname string
	// Mount namespaces carry their mount table, cgroup namespaces the cgroup
	// that is their root. Both belong to fs.
	data voidptr
	// Pid namespaces: the process that is their init, once there is one.
	init_pid int
	// Each PID namespace pins its immutable parent. The live memfd policy
	// includes every ancestor's local setting.
	pid_parent &Namespace = unsafe { nil }
	memfd_noexec u32
	// A pid namespace other than the initial one numbers its members itself:
	// `ids` maps each number it has handed out to the kernel's id for that
	// process or thread. Changed with pid_lock held. Made on first use: as a
	// map value it was allocated, and never freed, for every namespace of
	// every kind that unshare or clone created.
	ids     &map[int]int = unsafe { nil }
	next_id int = 1
	lock    klock.Lock
	// The user namespace that owns this one: the creator's, or the user
	// namespace created in the same clone/unshare call. Capabilities held in
	// a user namespace act only on the namespaces it owns.
	owner_user u64 = initial_user_namespace_id
	// User namespaces: the parent (nil for a child of the initial one; never
	// freed, see fs.release_namespace), nesting depth, and the id maps written
	// to /proc/<pid>/uid_map and gid_map: one extent each, `uid_inside` here
	// standing for the global uid `uid_global` (-1 until written). Every other
	// id is unmapped. Credentials stay global; ids are translated where they
	// cross the system call boundary (visible_id, global_id).
	parent_user    u64
	parent_ns      voidptr
	user_depth     int
	// The parent's quota account and ceiling for charges from this subtree.
	user_owner_uid u32
	user_msgqueue_limit u64
	uid_inside     i64 = -1
	uid_global     i64 = -1
	gid_inside     i64 = -1
	gid_global     i64 = -1
	setgroups_deny bool
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
}

// CAP_CHECKPOINT_RESTORE is the highest capability Linux 6.x defines.
pub const cap_last_cap = 40
pub const cap_all = (u64(1) << (cap_last_cap + 1)) - 1

pub const cap_chown = 0
pub const cap_dac_override = 1
pub const cap_dac_read_search = 2
pub const cap_fowner = 3
pub const cap_fsetid = 4
pub const cap_kill = 5
pub const cap_setgid = 6
pub const cap_setuid = 7
pub const cap_setpcap = 8
pub const cap_net_bind_service = 10
pub const cap_net_admin = 12
pub const cap_linux_immutable = 9
pub const cap_ipc_owner = 15
pub const cap_ipc_lock = 14
pub const cap_sys_chroot = 18
pub const cap_sys_ptrace = 19
pub const cap_sys_admin = 21
pub const cap_sys_boot = 22
pub const cap_sys_nice = 23
pub const cap_sys_resource = 24
pub const cap_sys_time = 25
pub const cap_mknod = 27
pub const cap_setfcap = 31
pub const cap_audit_read = 37

__global (
	namespace_id_counter = u64(4026532000)
	initial_namespaces   NamespaceSet
	ipc_namespace_release_hook voidptr
	user_namespaces_made u64
)

// User namespaces are never freed (fs.release_namespace drops references
// only), so this bounds how many any user can make after boot, and the
// memory they keep. Linux's user.max_user_namespaces bounds live ones.
pub const max_user_namespaces = u64(256)
pub const max_user_namespace_depth = 32

pub fn count_user_namespace() {
	katomic.inc(mut &user_namespaces_made)
}

pub fn user_namespaces_exhausted() bool {
	return katomic.load(&user_namespaces_made) >= max_user_namespaces
}

type IPCNamespaceReleaseHook = fn (u64)

pub fn register_ipc_namespace_release_hook(hook voidptr) {
	ipc_namespace_release_hook = hook
}

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
	if parent.kind == clone_newpid {
		mut ancestor := unsafe { parent }
		ns.pid_parent = if is_initial_namespace(ancestor) { ancestor } else { get_namespace(mut ancestor) }
		ns.memfd_noexec = memfd_noexec_scope(ancestor)
	}
	return ns
}

pub const memfd_noexec_default = u32(1)
pub const memfd_noexec_enforced = u32(2)

pub fn memfd_noexec_scope(ns &Namespace) u32 {
	mut current := ns
	mut scope := u32(0)
	for current != unsafe { nil } {
		local := katomic.load(&current.memfd_noexec)
		if local > scope {
			scope = local
		}
		current = current.pid_parent
	}
	return scope
}

pub fn pid_namespace_contains(ancestor &Namespace, ns &Namespace) bool {
	mut current := ns
	for current != unsafe { nil } {
		if voidptr(current) == voidptr(ancestor) {
			return true
		}
		current = current.pid_parent
	}
	return false
}

pub fn get_namespace(mut ns Namespace) &Namespace {
	katomic.inc(mut &ns.refcount)
	return ns
}

// An nsfs open may race the final process leaving. It may retain a live
// namespace, but cannot bring back state already destroyed at refcount zero.
pub fn try_get_namespace(mut ns Namespace) bool {
	if ns == unsafe { nil } { return false }
	if is_initial_namespace(ns) { return true }
	for {
		count := katomic.load(&ns.refcount)
		if count <= 0 { return false }
		if katomic.cas(mut &ns.refcount, count, count + 1) { return true }
	}
	return false
}

// Drop a reference, reporting whether it was the last one.
pub fn put_namespace(mut ns Namespace) bool {
	if unsafe { ns == nil } || is_initial_namespace(ns) {
		return false
	}
	last := !katomic.dec(mut &ns.refcount)
	if last && ns.kind == clone_newipc && ipc_namespace_release_hook != unsafe { nil } {
		hook := unsafe { IPCNamespaceReleaseHook(ipc_namespace_release_hook) }
		hook(ns.id)
	}
	if last && ns.kind == clone_newpid {
		mut parent := ns.pid_parent
		for !is_initial_namespace(parent) {
			if katomic.dec(mut &parent.refcount) {
				break
			}
			parent = parent.pid_parent
		}
	}
	return last
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
	lock              klock.Lock
	root_directory    voidptr
	current_directory voidptr
	root_mount        lib.MountContext
	current_mount     lib.MountContext
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
		process.fs_lock.acquire()
		mut own := &ThreadFS{
			root_directory:    process.root_directory
			current_directory: process.current_directory
			root_mount: process.root_mount
			current_mount: process.current_mount
		}
		if process.ns.mnt != unsafe { nil } {
			own.mnt = get_namespace(mut process.ns.mnt)
		}
		// The directory reaper scans ThreadFS under threads_lock. Publish a
		// complete snapshot with that lock, before the scanner can use it.
		process.threads_lock.acquire()
		t.fs = own
		process.threads_lock.release()
		process.fs_lock.release()
	}
	return t.fs
}

// Where `process` resolves absolute paths from, as the calling thread sees it.
// Nil is the global root.
pub fn root_directory_of(process &Process) voidptr {
	return snapshot_root_directory(process, unsafe { nil })
}

pub fn set_root_directory(mut process Process, directory voidptr) {
	set_root_fs(mut process, directory, unsafe { nil })
}

pub fn current_directory_of(process &Process) voidptr {
	return snapshot_current_directory(process, unsafe { nil })
}

pub fn set_current_directory(mut process Process, directory voidptr) {
	set_current_fs(mut process, directory, unsafe { nil })
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
	lock_table()
	if unsafe { parent == nil } || unsafe { parent.ns.mnt == nil } {
		child.ns = initial_namespace_set()
		child.caps = full_capabilities()
		unlock_table()
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
	child.caps = parent.caps
	// Keep the table lock throughout the source-to-child handoff. A reused
	// child PID can precede its parent in the reaper's scan; independent field
	// locks alone could let that scan miss both sides of a transferred cwd.
	child.fs_lock.acquire()
	child.root_directory = snapshot_root_directory(parent, &child.root_mount)
	child.current_directory = snapshot_current_directory(parent, &child.current_mount)
	child.exe_node = snapshot_executable(parent, &child.exe_mount)
	child.fs_lock.release()
	unlock_table()
	child.mac_domain = parent.mac_domain
	child.mac_next_domain = parent.mac_next_domain
	child.login_uid = parent.login_uid
	child.login_session = parent.login_session
	child.stack_policy_mode = katomic.load(&parent.stack_policy_mode)
	syscall_policy_inherit(mut child, parent)
	if !child.constructing {
		child.cgroup = parent.cgroup
		child.cgroup_account = parent.cgroup_account
	}
	child.oom_score_adj = parent.oom_score_adj
	pledge_inherit(mut child, parent)
	child.sigcookie = parent.sigcookie
}

pub fn full_capabilities() Capabilities {
	return Capabilities{
		effective: cap_all
		permitted: cap_all
		bounding:  cap_all
	}
}

// A capability over the whole system. Capabilities a process holds inside a
// user namespace it created are namespace-local (Linux ns_capable) and never
// satisfy this: they act only through has_namespace_capability.
pub fn has_capability(process &Process, cap int) bool {
	if unsafe { process == nil } {
		return true
	}
	return is_initial_namespace(process.ns.user) && process.caps.effective & (u64(1) << cap) != 0
}

// A capability over a namespace owned by user namespace `owner`. A process in
// the initial user namespace holds it over every namespace; one in a child
// user namespace only over those its own user namespace owns.
pub fn has_namespace_capability(process &Process, cap int, owner u64) bool {
	if unsafe { process == nil } {
		return true
	}
	if process.caps.effective & (u64(1) << cap) == 0 {
		return false
	}
	return is_initial_namespace(process.ns.user) || process.ns.user.id == owner
}

// A capability over the process's own state in its own user namespace:
// dropping capabilities, installing seccomp filters, creating namespaces
// that its user namespace will own.
pub fn has_own_capability(process &Process, cap int) bool {
	if unsafe { process == nil } {
		return true
	}
	return process.caps.effective & (u64(1) << cap) != 0
}

pub fn user_namespace_of(process &Process) u64 {
	if unsafe { process == nil } || process.ns.user == unsafe { nil } {
		return initial_user_namespace_id
	}
	return process.ns.user.id
}

pub fn current_has_capability(cap int) bool {
	return has_capability(current_thread().process, cap)
}

// Read while owning the running task, a lookup lock, or a pinned reference.
// A constructor can run before a boot CPU has a current task.
pub fn no_new_privs_state(task &Thread) u32 {
	if task == unsafe { nil } { return 0 }
	return katomic.load(&task.no_new_privs)
}

pub fn set_no_new_privs() {
	mut task := current_thread()
	katomic.store(mut &task.no_new_privs, u32(1))
	if task.tid == task.process.pid {
		katomic.store(mut &task.process.leader_no_new_privs, u32(1))
	}
}

// The capability sets a program starts with after execve(2), for a file that
// carries no file capabilities: root gets everything its bounding set and
// inheritable set allow, everybody else keeps only the ambient set.
pub fn capabilities_after_exec(mut process Process) {
	dumpability_after_exec(mut process)
	katomic.store(mut &process.stack_policy_mode, u32(0))
	katomic.store(mut &process.stack_policy_violations, u64(0))
	syscall_policy_reset(mut process)
	mut caps := process.caps
	old_permitted := caps.permitted
	bits := securebits_state(current_thread())
	if bits & secbit_noroot == 0 && (process.euid == 0 || process.uid == 0) {
		caps.permitted = (caps.inheritable | caps.bounding) | caps.ambient
		caps.effective = if process.euid == 0 { caps.permitted } else { caps.ambient }
	} else {
		caps.permitted = caps.ambient
		caps.effective = caps.ambient
	}
	// Even uid 0 must not regain dropped privileges through exec when NNP
	// is set. The bounding/inheritable sets are not the pre-exec ceiling.
	if no_new_privs_state(current_thread()) != 0 {
		caps.permitted &= old_permitted
		caps.effective &= caps.permitted
	}
	// SECBIT_KEEP_CAPS does not survive exec; no_new_privs does.
	securebits_after_exec()
	process.caps = caps
}

// Linux clears the permitted and effective sets when a process that had a uid
// of zero keeps none, unless it asked to keep them; dropping the effective uid
// alone clears only the effective set. Called after every credential change.
pub fn capabilities_after_setuid(mut process Process, old_ruid u32, old_euid u32, old_suid u32) {
	if process.euid != old_euid { set_dumpability(mut process, 0) }
	bits := securebits_state(current_thread())
	if bits & secbit_no_setuid_fixup != 0 { return }
	had_root := old_ruid == 0 || old_euid == 0 || old_suid == 0
	has_root := process.uid == 0 || process.euid == 0 || process.suid == 0
	if had_root && !has_root {
		if bits & secbit_keep_caps == 0 {
			process.caps.permitted = 0
			process.caps.effective = 0
		}
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

// Linux's overflow uid and gid: what an id no mapping covers reads as.
pub const overflow_id = u32(65534)

// The id `global` as a process in user namespace `ns` sees it.
pub fn visible_id(ns &Namespace, global u32, group bool) u32 {
	if unsafe { ns == nil } || is_initial_namespace(ns) {
		return global
	}
	inside := if group { ns.gid_inside } else { ns.uid_inside }
	mapped := if group { ns.gid_global } else { ns.uid_global }
	if mapped >= 0 && i64(global) == mapped {
		return u32(inside)
	}
	return overflow_id
}

// The global id that `id`, as user namespace `ns` names it, stands for.
pub fn global_id(ns &Namespace, id u32, group bool) ?u32 {
	if unsafe { ns == nil } || is_initial_namespace(ns) {
		return id
	}
	inside := if group { ns.gid_inside } else { ns.uid_inside }
	mapped := if group { ns.gid_global } else { ns.uid_global }
	if inside >= 0 && i64(id) == inside {
		return u32(mapped)
	}
	return none
}

// How the calling process sees one of its own ids (getuid and friends).
pub fn own_visible_id(process &Process, global u32, group bool) u32 {
	if unsafe { process == nil } {
		return global
	}
	return visible_id(process.ns.user, global, group)
}

// /proc/<pid>/uid_map or gid_map: the initial namespace's identity map, or
// the one extent written, its outside id as the parent namespace names it.
pub fn id_map_text(pid int, group bool) string {
	lock_table()
	defer { unlock_table() }
	process := process_at(pid)
	if process == unsafe { nil } || is_initial_namespace(process.ns.user) {
		return '         0          0 4294967295\n'
	}
	user := process.ns.user
	inside := if group { user.gid_inside } else { user.uid_inside }
	mapped := if group { user.gid_global } else { user.uid_global }
	if inside < 0 {
		return ''
	}
	outside := visible_id(unsafe { &Namespace(user.parent_ns) }, u32(mapped), group)
	// Linux's format: three right-aligned ten-wide fields.
	// On the stack: a plain local builder would be moved to the heap.
	mut text := unsafe { &lib.Text(C.vinix_stack_alloc(sizeof(lib.Text))) }
	unsafe { *text = lib.new_text(40) }
	fields := [inside, i64(outside), i64(1)]!
	for i in 0 .. 3 {
		value := unsafe { fields[i] }
		mut digits := 1
		for rest := value / 10; rest > 0; rest /= 10 { digits++ }
		for pad := digits; pad < 10; pad++ { text.add_byte(` `) }
		text.add_decimal(value)
		text.add_byte(if i == 2 { `\n` } else { ` ` })
	}
	return text.str()
}

pub fn setgroups_text(pid int) string {
	lock_table()
	defer { unlock_table() }
	process := process_at(pid)
	if process != unsafe { nil } && !is_initial_namespace(process.ns.user)
		&& process.ns.user.setgroups_deny {
		return 'deny\n'
	}
	return 'allow\n'
}

// The user namespace of `pid` that the caller may configure, holding
// `cap` there and living in it or its parent (Linux's rules for the id map
// files). Called with the table lock held.
fn configurable_user_namespace(pid int, cap int) ?&Namespace {
	writer := current_thread().process
	target := process_at(pid)
	if target == unsafe { nil } {
		errno.set(errno.esrch)
		return none
	}
	mut user := target.ns.user
	writer_ns := user_namespace_of(writer)
	if is_initial_namespace(user) || (writer_ns != user.id && writer_ns != user.parent_user)
		|| !has_namespace_capability(writer, cap, user.id) {
		errno.set(errno.eperm)
		return none
	}
	return user
}

// Write /proc/<pid>/uid_map or gid_map: the one-line map Linux lets any user
// write, "inside outside 1", where `outside` -- named as the parent user
// namespace names ids, whether the writer is in it or in the target -- is
// the writer's own effective uid or gid. Written once. A gid map needs
// setgroups "deny" first. Several extents, or another id, are refused.
pub fn write_id_map(pid int, group bool, inside i64, outside i64, count i64) ? {
	lock_table()
	defer { unlock_table() }
	mut user := configurable_user_namespace(pid, if group { cap_setgid } else { cap_setuid })?
	writer := current_thread().process
	own := if group { writer.egid } else { writer.euid }
	current := if group { user.gid_inside } else { user.uid_inside }
	if current >= 0 || count != 1 || inside < 0 || inside >= i64(u32(0xffffffff))
		|| outside < 0 || outside >= i64(u32(0xffffffff)) || (group && !user.setgroups_deny) {
		errno.set(errno.eperm)
		return none
	}
	global := global_id(unsafe { &Namespace(user.parent_ns) }, u32(outside), group) or {
		errno.set(errno.eperm)
		return none
	}
	if global != own {
		errno.set(errno.eperm)
		return none
	}
	if group {
		user.gid_inside = inside
		user.gid_global = i64(global)
	} else {
		user.uid_inside = inside
		user.uid_global = i64(global)
	}
}

// Write /proc/<pid>/setgroups: "deny" must precede an unprivileged gid map
// and is permanent; nothing may change it once the gid map is written.
pub fn write_setgroups(pid int, deny bool) ? {
	lock_table()
	defer { unlock_table() }
	mut user := configurable_user_namespace(pid, cap_sys_admin)?
	if user.gid_inside >= 0 || (user.setgroups_deny && !deny) {
		errno.set(errno.eperm)
		return none
	}
	user.setgroups_deny = deny
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

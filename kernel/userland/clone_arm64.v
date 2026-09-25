// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module userland

// Linux process and thread lifecycle syscalls: clone/clone3, wait4/waitid,
// exit/exit_group and the tid/robust-list bookkeeping they depend on.

import aarch64.cpu.local as cpulocal
import errno
import event
import event.eventstruct
import file
import fs
import futex
import katomic
import lib
import memory.mmap
import posixtimer
import proc
import sched
import term
import time
import usercopy

// clone(2) flags. Only the ones that change what we build are listed.
pub const clone_thread = u64(0x00010000)

pub const clone_settls = u64(0x00080000)

pub const clone_parent_settid = u64(0x00100000)

pub const clone_child_cleartid = u64(0x00200000)

pub const clone_child_settid = u64(0x01000000)

// The child's parent is the caller's parent, as for a sibling.
pub const clone_parent = u64(0x00008000)

pub const clone_pidfd = u64(0x00001000)

// clone3 only: start the child in the cgroup the args' directory fd names.
pub const clone_into_cgroup = u64(0x200000000)

// wait4(2)/waitid(2) options. `wnohang` lives in userland_arm64.v.
const wstopped = 2

const wexited = 4

const wcontinued = 8

const wnowait = 0x01000000

// waitid(2) id types.
const p_all = 0

const p_pid = 1

const p_pgid = 2

// siginfo si_code values for SIGCHLD.
const cld_exited = 1

const cld_killed = 2

// Robust futex list, as laid out by glibc/musl.
const robust_list_head_size = u64(24)

const robust_list_limit = 2048

const futex_waiters = u32(0x80000000)

const futex_owner_died = u32(0x40000000)

const futex_tid_mask = u32(0x3fffffff)

// struct rusage, 18 longs on LP64.
struct Rusage {
mut:
	ru_utime_sec  i64
	ru_utime_usec i64
	ru_stime_sec  i64
	ru_stime_usec i64
	ru_maxrss     i64
	ru_ixrss      i64
	ru_idrss      i64
	ru_isrss      i64
	ru_minflt     i64
	ru_majflt     i64
	ru_nswap      i64
	ru_inblock    i64
	ru_oublock    i64
	ru_msgsnd     i64
	ru_msgrcv     i64
	ru_nsignals   i64
	ru_nvcsw      i64
	ru_nivcsw     i64
}

// The SIGCHLD arm of siginfo_t, padded to the full 128-byte structure.
struct SigInfoChld {
mut:
	si_signo  i32
	si_errno  i32
	si_code   i32
	pad0      i32
	si_pid    i32
	si_uid    u32
	si_status i32
	pad1      i32
	si_utime  i64
	si_stime  i64
	pad       [80]u8
}

// struct clone_args as of CLONE_ARGS_SIZE_VER2.
struct CloneArgs {
mut:
	flags        u64
	pidfd        u64
	child_tid    u64
	parent_tid   u64
	exit_signal  u64
	stack        u64
	stack_size   u64
	tls          u64
	set_tid      u64
	set_tid_size u64
	cgroup       u64
}

const clone_args_size_ver0 = u64(64)

// ── clone ────────────────────────────────────────────────────────────────────

// clone(flags, child_stack, parent_tid, tls, child_tid). AArch64 selects
// CLONE_BACKWARDS, so tls comes before child_tid — the order musl's __clone
// marshals its arguments into.
pub fn syscall_clone(_gpr_state voidptr, flags u64, child_stack u64, parent_tid u64, tls u64, child_tid u64) (u64, u64) {
	state := unsafe { &cpulocal.GPRState(_gpr_state) }

	return do_clone(state, flags, child_stack, parent_tid, tls, child_tid)
}

// clone3(&clone_args, size).
pub fn syscall_clone3(_gpr_state voidptr, uargs u64, size u64) (u64, u64) {
	state := unsafe { &cpulocal.GPRState(_gpr_state) }

	if size < clone_args_size_ver0 {
		return errno.err, errno.einval
	}
	if size > sizeof(CloneArgs) {
		return errno.err, errno.e2big
	}

	mut args := CloneArgs{}
	if !usercopy.copy_from_user(voidptr(&args), uargs, size) {
		return errno.err, errno.efault
	}

	// Unlike clone, clone3 is handed the low end of the stack plus its length
	// and has to derive the initial stack pointer itself.
	mut child_sp := u64(0)
	if args.stack != 0 {
		if args.stack_size == 0 {
			return errno.err, errno.einval
		}
		child_sp = lib.align_down(args.stack + args.stack_size, 16)
	} else if args.stack_size != 0 {
		return errno.err, errno.einval
	}

	mut cgroup := voidptr(unsafe { nil })
	if args.flags & clone_into_cgroup != 0 {
		if size < sizeof(CloneArgs) {
			return errno.err, errno.einval
		}
		mut cgroup_fd := file.fd_from_fdnum(unsafe { nil }, int(args.cgroup)) or {
			return errno.err, errno.ebadf
		}
		node := unsafe { &fs.VFSNode(cgroup_fd.handle.node) }
		cgroup_fd.unref()
		cgroup = fs.cgroup_from_node(node) or { return errno.err, errno.ebadf }
	}

	return do_clone_into(state, args.flags, child_sp, args.parent_tid, args.tls, args.child_tid,
		args.flags & clone_into_cgroup != 0, cgroup)
}

fn do_clone(state &cpulocal.GPRState, flags u64, child_stack u64, parent_tid u64, tls u64, child_tid u64) (u64, u64) {
	return do_clone_into(state, flags & 0xffffffff, child_stack, parent_tid, tls, child_tid,
		false, unsafe { nil })
}

fn do_clone_into(state &cpulocal.GPRState, flags u64, child_stack u64, parent_tid u64, tls u64, child_tid u64, into_cgroup bool, cgroup voidptr) (u64, u64) {
	// A new namespace other than a user namespace takes CAP_SYS_ADMIN, and none
	// can be made for a thread, which shares its process' namespaces.
	if flags & proc.clone_namespace_flags != 0 {
		if flags & clone_thread != 0 {
			return errno.err, errno.einval
		}
		if flags & proc.clone_namespace_flags & ~proc.clone_newuser != 0
			&& !proc.current_has_capability(proc.cap_sys_admin) {
			return errno.err, errno.eperm
		}
	}
	// pids.max counts threads and processes alike. A group at its limit refuses
	// one more, and the clone fails with EAGAIN, as on Linux.
	if into_cgroup {
		if !proc.cgroup_account_may_add_task(fs.cgroup_account_of(cgroup)) {
			return errno.err, errno.eagain
		}
	} else if !proc.cgroup_may_add_task(proc.current_thread().process) {
		return errno.err, errno.eagain
	}
	// CLONE_THREAD, not CLONE_VM, decides between a thread and a process:
	// posix_spawn and vfork ask for CLONE_VM but still expect a child that can
	// execve without replacing us, which our separate address spaces give them.
	if flags & clone_thread != 0 {
		return clone_thread_of_current(state, flags, child_stack, parent_tid, tls,
			child_tid)
	}

	return clone_new_process(state, flags, child_stack, parent_tid, tls, child_tid, into_cgroup,
		cgroup)
}

// CLONE_THREAD: another thread inside the calling process, sharing its address
// space, descriptors and pending-child bookkeeping.
fn clone_thread_of_current(state &cpulocal.GPRState, flags u64, child_stack u64, parent_tid u64, tls u64, child_tid u64) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	if child_stack == 0 {
		// Two threads cannot share one stack; there is nothing sensible to do.
		return errno.err, errno.einval
	}

	mut new_thread := sched.new_cloned_thread(process, current_thread, state, child_stack,
		tls, flags & clone_settls != 0) or { return errno.err, errno.eagain }

	if flags & clone_child_cleartid != 0 {
		new_thread.clear_child_tid = child_tid
	}

	tid := u32(proc.own_tid(new_thread))

	// Both tid words live in the address space we share with the new thread, so
	// they can be written here, before it is allowed to run. As on Linux, a
	// write that does not land is not worth failing the whole clone over.
	if flags & clone_parent_settid != 0 && parent_tid != 0 {
		usercopy.copy_to_user(parent_tid, voidptr(&tid), sizeof(u32))
	}
	if flags & clone_child_settid != 0 && child_tid != 0 {
		usercopy.copy_to_user(child_tid, voidptr(&tid), sizeof(u32))
	}

	sched.enqueue_thread(new_thread, false)

	return u64(tid), 0
}

// Everything else: a new process with a copy of our address space and
// descriptor table, running a single thread that resumes where we did.
fn clone_new_process(state &cpulocal.GPRState, flags u64, child_stack u64, parent_tid u64, tls u64, child_tid u64, into_cgroup bool, cgroup voidptr) (u64, u64) {
	mut old_thread := proc.current_thread()
	mut old_process := old_thread.process

	mut new_process := sched.new_process(old_process, unsafe { nil }) or {
		return errno.err, errno.get()
	}

	new_process.name = '${old_process.name}[${new_process.pid}]'
	fs.fork_namespaces(mut new_process, flags)
	if into_cgroup {
		new_process.cgroup = cgroup
		new_process.cgroup_account = fs.cgroup_account_of(cgroup)
	}

	// CLONE_PARENT makes the child its creator's sibling: runc's init stages
	// are all children of the runtime that started the first of them.
	mut parent_process := old_process
	if flags & clone_parent != 0 && old_process.ppid > 0 {
		mut grandparent := processes[old_process.ppid]
		if grandparent != unsafe { nil } {
			parent_process = grandparent
			new_process.ppid = grandparent.pid
		}
	}

	// Duplicate the descriptor table, preserving each fd's O_CLOEXEC flag. The
	// open numbers are read under the table's lock: another thread of the
	// parent may make a descriptor meanwhile, and grow the table as it does.
	mut open := file.open_fdnums(old_process)
	for i in open {
		mut old_fd := file.fd_from_fdnum(old_process, i) or { continue }
		flags := old_fd.flags
		old_fd.unref()
		file.fdnum_dup(old_process, i, new_process, i, flags, true, false) or {
			continue
		}
	}
	unsafe { open.free() }

	mut child_sp := state.sp
	if child_stack != 0 {
		child_sp = child_stack
	}

	// Numbered once its pid namespace is settled, and before its first thread
	// is, which takes the process's number.
	proc.number_process(mut new_process, old_process)

	mut new_thread := sched.new_cloned_thread(new_process, old_thread, state, child_sp,
		tls, flags & clone_settls != 0) or {
		// Detached under the process table lock first, as exec does, so
		// nothing walking page maps is on it when it is freed.
		proc.lock_table()
		mut doomed := new_process.pagemap
		new_process.pagemap = unsafe { nil }
		proc.unlock_table()
		mmap.delete_pagemap(mut doomed) or {}
		proc.free_pid(new_process.pid)
		return errno.err, errno.eagain
	}

	if flags & clone_child_cleartid != 0 {
		new_thread.clear_child_tid = child_tid
	}

	// The parent's word gets the child's tid as the parent sees it, the child's
	// as the child does: in a new pid namespace the child is 1.
	viewer := old_process.numbered_in
	tid := u32(proc.tid_in(new_thread, viewer))
	child_view_tid := u32(proc.own_tid(new_thread))

	if flags & clone_parent_settid != 0 && parent_tid != 0 {
		usercopy.copy_to_user(parent_tid, voidptr(&tid), sizeof(u32))
	}
	// The child's pages were copied eagerly, so its tid word has to be written
	// through its own pagemap rather than ours.
	if flags & clone_child_settid != 0 && child_tid != 0 {
		usercopy.copy_to_pagemap(new_process.pagemap, child_tid, voidptr(&child_view_tid),
			sizeof(u32))
	}

	parent_process.children_lock.acquire()
	parent_process.children << new_process
	parent_process.children_lock.release()

	sched.enqueue_thread(new_thread, false)

	return u64(proc.pid_in(new_process, viewer)), 0
}

// ── exit ─────────────────────────────────────────────────────────────────────

// exit(2): terminate the calling thread only. The process goes away with its
// last thread.
@[noreturn]
pub fn syscall_exit(_ voidptr, status int) {
	thread_exit(status, false)
}

// exit_group(2): terminate every thread of the calling process.
@[noreturn]
pub fn syscall_exit_group(_ voidptr, status int) {
	thread_exit(status, true)
}

@[noreturn]
fn thread_exit(status int, group bool) {
	mut current_thread := proc.current_thread()
	mut current_process := current_thread.process

	// A sibling tearing the process down may already have given up waiting and
	// taken charge of this thread. Then it is the one releasing what this
	// thread holds, and this thread only has to get out of its way.
	if !proc.claim_thread_exit(current_thread) {
		sched.park_stopped_thread()
	}

	// Hand back whatever this thread still owns while its address space is
	// mapped: robust futexes it holds, and the tid word pthread_join waits on.
	release_robust_list(mut current_thread)
	clear_child_tid(mut current_thread)
	fs.release_thread_fs(mut current_thread)

	if !group && !leave_process(mut current_process, current_thread) {
		proc.free_tid(current_thread.tid)
		event.trigger(mut &current_thread.exited, false)
		sched.dequeue_and_die()
	}

	exit_process(mut current_process, mut current_thread, encode_exit_status(status))
}

// Terminate the calling process because one of its own instructions raised a
// fatal signal nothing handled: a BRK, an undefined instruction or a memory
// fault with no handler and no way to retry. Linux reports that to wait(2) as
// a death by signal rather than an exit code, and the kernel keeps running.
@[noreturn]
pub fn exit_with_fatal_signal(signal u8) {
	mut current_thread := proc.current_thread()
	mut current_process := current_thread.process

	if !proc.claim_thread_exit(current_thread) {
		sched.park_stopped_thread()
	}

	release_robust_list(mut current_thread)
	clear_child_tid(mut current_thread)
	fs.release_thread_fs(mut current_thread)

	exit_process(mut current_process, mut current_thread, encode_fatal_signal(signal))
}

// Drop the calling thread from its process, reporting whether it was the last
// one. Done under the process lock so that of several threads exiting at once
// exactly one is told to tear the process down.
fn leave_process(mut process proc.Process, current_thread &proc.Thread) bool {
	process.threads_lock.acquire()
	defer {
		process.threads_lock.release()
	}

	for i := 0; i < process.threads.len; i++ {
		if voidptr(process.threads[i]) == voidptr(current_thread) {
			process.threads.delete(i)
			break
		}
	}

	return process.threads.len == 0
}

// Claim the right to tear the process down. exit_group() can arrive while
// another thread is already at it, and the teardown is not repeatable.
fn claim_teardown(mut process proc.Process) bool {
	process.threads_lock.acquire()
	defer {
		process.threads_lock.release()
	}

	if process.exiting {
		return false
	}
	process.exiting = true
	return true
}

@[noreturn]
fn exit_process(mut current_process proc.Process, mut current_thread proc.Thread, status int) {
	if !claim_teardown(mut current_process) {
		// Somebody else got here first. Step out of the thread list before
		// dying so the thread doing the teardown never has to reach us.
		leave_process(mut current_process, current_thread)
		proc.free_tid(current_thread.tid)
		sched.dequeue_and_die()
	}

	// Get every other thread off the CPUs before the address space goes away.
	kill_sibling_threads(mut current_process, current_thread)
	posixtimer.remove_process_timers(current_process)

	// If this process had the framebuffer (the desktop, say), the console is
	// dark on its account; give it back before the shell that follows prints.
	term.leave_graphics_mode_if_owner(current_process.pid)

	mut old_pagemap := current_process.pagemap

	kernel_pagemap.switch_to()
	current_thread.process = kernel_process
	// Detached under the process table lock, which cgroup memory accounting
	// and /proc hold while they walk a process' page map, so none is still
	// walking the one freed below, and none finds it on the zombie afterwards.
	proc.lock_table()
	current_process.pagemap = unsafe { nil }
	proc.unlock_table()

	for i := 0; i < current_process.fds.len; i++ {
		if current_process.fds[i] == unsafe { nil } {
			continue
		}

		file.fdnum_close(current_process, i, true) or {}
	}

	// The nearest ancestor that asked to be a child subreaper, or else PID 1,
	// adopts whatever children we leave behind. Taken off our own list first
	// so that the two children locks are never held at the same time.
	current_process.children_lock.acquire()
	mut orphans := unsafe { current_process.children }
	current_process.children = []&proc.Process{}
	current_process.children_lock.release()

	// The init of a pid namespace takes every other member with it.
	mut pid_ns := current_process.ns.pid
	if pid_ns != unsafe { nil } && !proc.is_initial_namespace(pid_ns)
		&& pid_ns.init_pid == current_process.pid {
		for member in proc.pid_namespace_members(pid_ns) {
			signal_pid(member, 9)
		}
	}

	mut adopter := find_reaper(current_process)
	if adopter != unsafe { nil } && voidptr(adopter) != voidptr(current_process) {
		mut adopted_zombie := false
		adopter.children_lock.acquire()
		for mut child_proc in orphans {
			child_proc.ppid = adopter.pid
			adopter.children << child_proc
			if child_proc.exiting {
				adopted_zombie = true
			}
		}
		adopter.children_lock.release()
		// A child that had already died is the adopter's to reap now; tell it,
		// as the dead child's own SIGCHLD went to a parent that is gone.
		if adopted_zombie {
			notify_process(adopter)
		}
	}
	for mut child_proc in orphans {
		if child_proc.pdeathsig > 0 && !child_proc.exiting {
			signal_pid(child_proc.pid, child_proc.pdeathsig)
		}
	}
	unsafe { orphans.free() }

	fs.release_process_namespaces(mut current_process)

	mmap.delete_pagemap(mut old_pagemap) or {}

	// The Thread structs are about to be recycled, so nothing may reach them
	// through the zombie process that is left behind.
	current_process.threads_lock.acquire()
	current_process.threads = []&proc.Thread{}
	current_process.threads_lock.release()

	proc.free_tid(current_thread.tid)

	katomic.store(mut &current_process.status, status)
	// Wakes a parent blocked in wait4()/waitid()...
	event.trigger(mut &current_process.event, false)
	// ...and tells one that is not waiting yet, which is how a daemon reaps.
	notify_parent(current_process)

	sched.dequeue_and_die()
}

// wait(2) reports a normal exit with the code in bits 8..15.
fn encode_exit_status(status int) int {
	return (status & 0xff) << 8
}

// ...and a death by signal with the signal number in bits 0..6, which is what
// WIFSIGNALED/WTERMSIG read. Bit 7 stays clear: there is no core dump.
fn encode_fatal_signal(signal u8) int {
	return int(signal) & 0x7f
}

// How long exit_group() and execve() give the other threads to leave on their
// own before stopping whatever is still running.
const sibling_exit_grace_ns = u64(500000000)

// A thread told to go by a sibling's exit_group() or execve() leaves here, on
// its way back to userspace, after the syscall it was in has unwound and given
// back what it held.
pub fn exit_if_told_to() {
	t := proc.current_thread()
	if t == unsafe { nil } || !katomic.load(&t.must_exit) {
		return
	}
	thread_exit(0, false)
}

fn has_other_threads(mut process proc.Process, current_thread &proc.Thread) bool {
	process.threads_lock.acquire()
	defer {
		process.threads_lock.release()
	}
	for t in process.threads {
		if voidptr(t) != voidptr(current_thread) {
			return true
		}
	}
	return false
}

// Get every other thread of the process out, for good. Each is told to exit and
// woken if it is waiting, so that one blocked in the kernel unwinds its
// syscall -- giving back the descriptors, references and memory that syscall
// holds -- and leaves by itself on the way back to userspace. Stopping them where they
// stood leaked all of that: a Go program exits with a thread parked in
// epoll_pwait, and each one left references on the sockets and pipes it was
// watching, which then never closed, plus the thread's own kernel stack.
//
// A thread that does not leave within the grace period -- one busy in
// userspace, which holds nothing of the kernel's -- is stopped where it is.
// Its kernel stack is deliberately left allocated: it may still be parked
// mid-syscall on it, and there is no safe moment to free it here.
fn kill_sibling_threads(mut current_process proc.Process, current_thread &proc.Thread) {
	// Pinned while still on the list: any of them may leave and die by itself
	// the moment the lock is let go, and its memory must not be handed to a new
	// thread while this is still telling it to exit.
	current_process.threads_lock.acquire()
	mut others := []&proc.Thread{cap: current_process.threads.len}
	for t in current_process.threads {
		if voidptr(t) != voidptr(current_thread) {
			proc.pin_thread(t)
			others << t
		}
	}
	current_process.threads_lock.release()
	for mut other in others {
		katomic.store(mut &other.must_exit, true)
		sched.enqueue_thread(other, true)
		proc.unpin_thread(other)
	}
	unsafe { others.free() }

	deadline := time.monotonic_ns() + sibling_exit_grace_ns
	for has_other_threads(mut current_process, current_thread) && time.monotonic_ns() < deadline {
		mut timer := time.new_timer(time.TimeSpec{
			tv_sec:  0
			tv_nsec: 1000000
		})
		mut timer_events := [&timer.event]
		event.await(mut timer_events, true) or {}
		timer.disarm()
		unsafe {
			timer_events.free()
			free(timer)
		}
	}

	current_process.threads_lock.acquire()
	mut victims := []&proc.Thread{cap: current_process.threads.len}
	for t in current_process.threads {
		if voidptr(t) != voidptr(current_thread) {
			proc.pin_thread(t)
			victims << t
		}
	}
	current_process.threads_lock.release()

	for mut victim in victims {
		// One that has started leaving by itself -- it may have been just about
		// to when the grace period ran out -- gives back its own tid and root.
		// Doing that here as well freed them twice, and could stop and free the
		// tid of whatever new thread had taken its place. Wait for it to be off
		// the list instead, and leave it alone.
		if !proc.claim_thread_exit(victim) {
			wait_for_thread_to_leave(mut current_process, victim)
			proc.unpin_thread(victim)
			continue
		}
		// Marked first so that an event trigger racing with us cannot put the
		// thread back on the run queue behind our back.
		katomic.store(mut &victim.is_dead, true)
		sched.intercept_thread(victim) or {}
		sched.dequeue_thread(victim)
		// It may still be on another CPU finishing what it was doing; the
		// descriptors and address space it could reach are torn down next.
		for n := 0; n < 1000000 && katomic.load(&victim.running_on) != u64(-1); n++ {
			asm volatile aarch64 {
				yield
				; ; ; memory
			}
		}
		sched.set_itimer_real(victim, 0, 0)
		// A thread that split off its own root and mount namespace -- runc
		// keeps one in the container's namespace for opening mount sources --
		// holds a reference that would otherwise keep the namespace, and every
		// directory it has something mounted on, alive for good.
		fs.release_thread_fs(mut victim)
		proc.free_tid(victim.tid)
		proc.unpin_thread(victim)
	}

	unsafe { victims.free() }
}

fn thread_listed(mut process proc.Process, t &proc.Thread) bool {
	process.threads_lock.acquire()
	defer {
		process.threads_lock.release()
	}
	for listed in process.threads {
		if voidptr(listed) == voidptr(t) {
			return true
		}
	}
	return false
}

// A thread that has claimed its own exit has nothing left to block on, so it
// is off the list within moments. The bound is only there so that a teardown
// can never hang on one.
fn wait_for_thread_to_leave(mut process proc.Process, t &proc.Thread) {
	deadline := time.monotonic_ns() + sibling_exit_grace_ns
	for thread_listed(mut process, t) && time.monotonic_ns() < deadline {
		mut timer := time.new_timer(time.TimeSpec{
			tv_sec:  0
			tv_nsec: 1000000
		})
		mut timer_events := [&timer.event]
		event.await(mut timer_events, true) or {}
		timer.disarm()
		unsafe {
			timer_events.free()
			free(timer)
		}
	}
}

// Who adopts the children of `process`: its closest living ancestor that set
// PR_SET_CHILD_SUBREAPER, or the init of its pid namespace -- a container's,
// which is what lets tini reap the zombies inside it -- or PID 1.
fn find_reaper(process &proc.Process) &proc.Process {
	mut ppid := process.ppid
	for _ in 0 .. proc.max_pid {
		if ppid <= 1 || ppid >= proc.max_pid {
			break
		}
		ancestor := processes[ppid]
		if ancestor == unsafe { nil } {
			break
		}
		if ancestor.child_subreaper && !ancestor.exiting {
			return ancestor
		}
		ppid = ancestor.ppid
	}
	pid_ns := process.numbered_in
	if proc.numbers_own(pid_ns) && pid_ns.init_pid != process.pid && pid_ns.init_pid > 0
		&& pid_ns.init_pid < proc.max_pid {
		namespace_init := processes[pid_ns.init_pid]
		if namespace_init != unsafe { nil } && !namespace_init.exiting {
			return namespace_init
		}
	}
	if process.pid == 1 {
		return unsafe { nil }
	}
	return processes[1]
}

fn notify_process(parent &proc.Process) {
	mut target := unsafe { parent }
	signal_process(mut target, sigchld)
}

// Raise SIGCHLD in the parent, as a signal to the whole process. sendsig()
// drops it where the parent neither handles nor blocks it -- its default
// disposition is to be ignored -- and wakes no thread for it that only
// blocks it, so a parent in an unrelated syscall gets no needless EINTR. A
// parent that blocks it keeps it pending for sigwait(2); it was dropped
// unless a handler had been installed.
fn notify_parent(current_process &proc.Process) {
	mut parent := processes[current_process.ppid]
	if parent == unsafe { nil } || parent.pid == current_process.pid {
		return
	}
	signal_process(mut parent, sigchld)
}

// ── tid address and robust futex lists ───────────────────────────────────────

// set_tid_address(2): remember where to publish this thread's death.
pub fn syscall_set_tid_address(_ voidptr, tidptr u64) (u64, u64) {
	mut current_thread := proc.current_thread()

	current_thread.clear_child_tid = tidptr

	return u64(proc.own_tid(current_thread)), 0
}

pub fn syscall_set_robust_list(_ voidptr, head u64, len u64) (u64, u64) {
	if len != robust_list_head_size {
		return errno.err, errno.einval
	}

	mut current_thread := proc.current_thread()
	current_thread.robust_list_head = head

	return 0, 0
}

pub fn syscall_get_robust_list(_ voidptr, tid int, head_ptr u64, len_ptr u64) (u64, u64) {
	mut head := proc.current_thread().robust_list_head
	if tid != 0 {
		target := proc.thread_in(proc.current_pid_namespace(), tid)
		if target == unsafe { nil } {
			return errno.err, errno.esrch
		}
		head = target.robust_list_head
		proc.unpin_thread(target)
	}

	if head_ptr == 0 || len_ptr == 0 {
		return errno.err, errno.efault
	}

	len := robust_list_head_size

	if !usercopy.copy_to_user(head_ptr, voidptr(&head), sizeof(u64)) {
		return errno.err, errno.efault
	}
	if !usercopy.copy_to_user(len_ptr, voidptr(&len), sizeof(u64)) {
		return errno.err, errno.efault
	}

	return 0, 0
}

// CLONE_CHILD_CLEARTID / set_tid_address(2): zero the word and wake whoever is
// blocked on it. This is how pthread_join() learns the thread is gone.
fn clear_child_tid(mut t proc.Thread) {
	address := t.clear_child_tid
	if address == 0 {
		return
	}
	t.clear_child_tid = 0

	zero := u32(0)
	if !usercopy.copy_to_user(address, voidptr(&zero), sizeof(u32)) {
		return
	}

	futex.wake(address)
}

// Walk the list registered with set_robust_list(2) and pass on every lock the
// dying thread still holds, flagged FUTEX_OWNER_DIED so the next owner knows
// the state it inherits may be inconsistent.
fn release_robust_list(mut t proc.Thread) {
	head := t.robust_list_head
	if head == 0 {
		return
	}
	t.robust_list_head = 0

	mut entry := u64(0)
	mut offset := i64(0)
	mut pending := u64(0)
	if !usercopy.copy_from_user(voidptr(&entry), head, sizeof(u64)) {
		return
	}
	if !usercopy.copy_from_user(voidptr(&offset), head + 8, sizeof(i64)) {
		return
	}
	if !usercopy.copy_from_user(voidptr(&pending), head + 16, sizeof(u64)) {
		return
	}

	// The head itself is a list member, so the walk stops when it comes back
	// round; the iteration cap guards against a corrupted list.
	for i := 0; i < robust_list_limit && entry != 0 && entry != head; i++ {
		mut next := u64(0)
		if !usercopy.copy_from_user(voidptr(&next), entry, sizeof(u64)) {
			break
		}
		if entry != pending {
			abandon_robust_futex(proc.own_tid(t), u64(i64(entry) + offset))
		}
		entry = next
	}

	// list_op_pending covers the lock the thread was in the middle of taking
	// or releasing when it died.
	if pending != 0 {
		abandon_robust_futex(proc.own_tid(t), u64(i64(pending) + offset))
	}
}

// `tid` is the thread's own number, which is what userspace stored as the
// owner.
fn abandon_robust_futex(tid int, address u64) {
	mut value := u32(0)
	if !usercopy.copy_from_user(voidptr(&value), address, sizeof(u32)) {
		return
	}
	if value & futex_tid_mask != u32(tid) {
		return
	}

	new_value := (value & futex_waiters) | futex_owner_died
	if !usercopy.copy_to_user(address, voidptr(&new_value), sizeof(u32)) {
		return
	}

	if value & futex_waiters != 0 {
		futex.wake(address)
	}
}

// ── wait ─────────────────────────────────────────────────────────────────────

// Selector semantics shared by wait4() and waitid(): >0 one pid, 0 the caller's
// process group, -1 any child, < -1 the process group -pid.
// `pid` is as the caller's pid namespace numbers processes and groups.
fn child_matches(current_process &proc.Process, child &proc.Process, pid int) bool {
	if pid == -1 {
		return true
	}
	viewer := current_process.numbered_in
	if pid > 0 {
		return proc.pid_in(child, viewer) == pid
	}
	if pid == 0 {
		return child.pgid == current_process.pgid
	}
	return proc.pgid_in(child, viewer) == -pid
}

// Look for a child selected by `pid` that has already exited. A nil child with
// errno 0 means "nothing ready yet", which only happens under WNOHANG.
fn take_exited_child(mut current_process proc.Process, pid int, block bool) (&proc.Process, u64) {
	mut candidates := []&proc.Process{}
	mut events := []&eventstruct.Event{}
	defer {
		unsafe {
			candidates.free()
			events.free()
		}
	}

	// Snapshot the selection: event.await() below can block, which no spinlock
	// may be held across. Process structs outlive their pid, so the events
	// stay valid even if another thread reaps one of them meanwhile.
	current_process.children_lock.acquire()
	for c in current_process.children {
		if child_matches(current_process, c, pid) {
			candidates << c
			events << &c.event
		}
	}
	current_process.children_lock.release()

	if candidates.len == 0 {
		return unsafe { nil }, errno.echild
	}

	// A non-blocking look attaches no listeners, so it can cover every child
	// however many there are.
	if which := event.await(mut events, false) {
		return candidates[which], u64(0)
	}
	if !block {
		return unsafe { nil }, u64(0)
	}

	// Blocking does attach listeners, and a thread can only hold
	// proc.max_events of them. With more children than that we sleep on the
	// first batch; any of them waking us sends us round for another full sweep.
	mut watched := unsafe { events }
	if watched.len > proc.max_events {
		watched = events[..proc.max_events]
	}

	which := event.await(mut watched, true) or {
		// A signal cut the wait short. The child's exit itself raises SIGCHLD,
		// so look once more before reporting an interruption.
		retry := event.await(mut events, false) or { return unsafe { nil }, errno.eintr }
		return candidates[retry], u64(0)
	}

	return candidates[which], u64(0)
}

fn release_child(mut current_process proc.Process, child &proc.Process) {
	current_process.children_lock.acquire()
	index := current_process.children.index(child)
	if index >= 0 {
		current_process.children.delete(index)
	}
	current_process.children_lock.release()

	proc.account_reaped_child(mut current_process, child)
	proc.free_pid(child.pid)
}

// A failed copy-out must not swallow the exit: hand the event back so the child
// is still reapable, and report EFAULT.
fn put_back(mut child proc.Process) u64 {
	event.trigger(mut &child.event, false)
	return errno.efault
}

fn write_child_rusage(rusage_ptr u64, child &proc.Process) bool {
	if rusage_ptr == 0 {
		return true
	}

	ns := katomic.load(&child.cpu_time_ns)
	usage := Rusage{
		ru_utime_sec:  i64(ns / 1000000000)
		ru_utime_usec: i64((ns % 1000000000) / 1000)
	}
	return usercopy.copy_to_user(rusage_ptr, voidptr(&usage), sizeof(Rusage))
}

// wait4(pid, status, options, rusage).
pub fn syscall_wait4(_ voidptr, pid int, status_ptr u64, options int, rusage_ptr u64) (u64, u64) {
	mut current_process := proc.current_thread().process

	mut child, err := take_exited_child(mut current_process, pid, options & wnohang == 0)
	if child == unsafe { nil } {
		if err != 0 {
			return errno.err, err
		}
		return 0, 0
	}

	status := i32(child.status)
	reaped := proc.pid_in(child, current_process.numbered_in)

	if status_ptr != 0 && !usercopy.copy_to_user(status_ptr, voidptr(&status), sizeof(i32)) {
		return errno.err, put_back(mut child)
	}
	if !write_child_rusage(rusage_ptr, child) {
		return errno.err, put_back(mut child)
	}

	release_child(mut current_process, child)

	return u64(reaped), 0
}

// waitid(idtype, id, infop, options, rusage).
pub fn syscall_waitid(_ voidptr, idtype int, id u64, infop u64, options int, rusage_ptr u64) (u64, u64) {
	mut current_process := proc.current_thread().process

	// Exactly which state changes to report has to be asked for; we only ever
	// report exits, since nothing here stops or continues a process yet.
	if options & (wexited | wstopped | wcontinued) == 0 {
		return errno.err, errno.einval
	}

	mut pid := 0
	match idtype {
		p_all {
			pid = -1
		}
		p_pid {
			if id == 0 || id > u64(0x7fffffff) {
				return errno.err, errno.einval
			}
			pid = int(id)
		}
		p_pgid {
			if id > u64(0x7fffffff) {
				return errno.err, errno.einval
			}
			pid = if id == 0 { 0 } else { -int(id) }
		}
		else {
			return errno.err, errno.einval
		}
	}

	mut child, err := take_exited_child(mut current_process, pid, options & wnohang == 0)
	if child == unsafe { nil } {
		if err != 0 {
			return errno.err, err
		}
		// WNOHANG with nothing to report: Linux signals that with si_pid == 0.
		if infop != 0 {
			info := SigInfoChld{}
			if !usercopy.copy_to_user(infop, voidptr(&info), sizeof(SigInfoChld)) {
				return errno.err, errno.efault
			}
		}
		return 0, 0
	}

	status := child.status
	mut info := SigInfoChld{
		si_signo:  i32(sigchld)
		si_code:   i32(cld_exited)
		si_pid:    i32(proc.pid_in(child, current_process.numbered_in))
		si_status: i32((status >> 8) & 0xff)
	}
	if status & 0x7f != 0 {
		info.si_code = i32(cld_killed)
		info.si_status = i32(status & 0x7f)
	}

	if infop != 0 && !usercopy.copy_to_user(infop, voidptr(&info), sizeof(SigInfoChld)) {
		return errno.err, put_back(mut child)
	}
	if !write_child_rusage(rusage_ptr, child) {
		return errno.err, put_back(mut child)
	}

	if options & wnowait != 0 {
		// Leave the child reapable: put back the event we just consumed.
		event.trigger(mut &child.event, false)
	} else {
		release_child(mut current_process, child)
	}

	return 0, 0
}

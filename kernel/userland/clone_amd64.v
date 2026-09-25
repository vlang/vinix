// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module userland

// Linux clone, clone3, exit and the per-thread signal calls for amd64. musl
// builds pthread_create() on clone(CLONE_THREAD), fork() on fork(2), and
// posix_spawn() on clone(CLONE_VM | CLONE_VFORK); a thread ends with exit(2)
// and a process with exit_group(2). Without them a Linux program could not
// start a thread: curl's resolver, git's pack workers and every GTK program
// need one. The argument block, the tid word and the robust futex list are
// shared with arm64 in linux_task.v.

import errno
import file
import fs
import lib
import memory.mmap
import proc
import sched
import usercopy
import x86.cpu.local as cpulocal

// The signal number a clone's low byte carries.
const clone_exit_signal_mask = u64(0xff)

// clone(flags, child_stack, parent_tid, child_tid, tls). x86-64 is not a
// CLONE_BACKWARDS architecture: child_tid comes before tls, the reverse of
// arm64's order.
pub fn syscall_clone(gpr_state voidptr, flags u64, child_stack u64, parent_tid u64, child_tid u64, tls u64) (u64, u64) {
	state := unsafe { &cpulocal.GPRState(gpr_state) }
	return do_clone(state, flags & 0xffffffff, child_stack, parent_tid, child_tid, tls, false,
		unsafe { nil })
}

// clone3(&clone_args, size).
pub fn syscall_clone3(gpr_state voidptr, uargs u64, size u64) (u64, u64) {
	state := unsafe { &cpulocal.GPRState(gpr_state) }

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
	if args.exit_signal & ~clone_exit_signal_mask != 0 {
		return errno.err, errno.einval
	}

	// clone3 is handed the low end of the stack and its length, not the
	// initial stack pointer.
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

	return do_clone(state, args.flags, child_sp, args.parent_tid, args.child_tid, args.tls,
		args.flags & clone_into_cgroup != 0, cgroup)
}

fn do_clone(state &cpulocal.GPRState, flags u64, child_stack u64, parent_tid u64, child_tid u64, tls u64, into_cgroup bool, cgroup voidptr) (u64, u64) {
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
	// pids.max counts threads and processes alike.
	if into_cgroup {
		if !proc.cgroup_account_may_add_task(fs.cgroup_account_of(cgroup)) {
			return errno.err, errno.eagain
		}
	} else if !proc.cgroup_may_add_task(proc.current_thread().process) {
		return errno.err, errno.eagain
	}
	// CLONE_THREAD, not CLONE_VM, decides between a thread and a process:
	// posix_spawn and vfork ask for CLONE_VM but only need a child that can
	// execve without replacing us, which a copied address space gives them.
	if flags & clone_thread != 0 {
		return clone_thread_of_current(state, flags, child_stack, parent_tid, child_tid, tls)
	}
	return clone_new_process(state, flags, child_stack, parent_tid, child_tid, tls, into_cgroup,
		cgroup)
}

// CLONE_THREAD: another thread in the calling process, sharing its address
// space, descriptors and signal dispositions.
fn clone_thread_of_current(state &cpulocal.GPRState, flags u64, child_stack u64, parent_tid u64, child_tid u64, tls u64) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	if child_stack == 0 {
		// Two threads cannot share one stack.
		return errno.err, errno.einval
	}

	mut new_thread := sched.new_cloned_thread(process, current_thread, state, child_stack, tls,
		flags & clone_settls != 0) or { return errno.err, errno.eagain }

	if flags & clone_child_cleartid != 0 {
		new_thread.clear_child_tid = child_tid
	}

	tid := u32(proc.own_tid(new_thread))

	// Both tid words live in the address space the new thread shares, so they
	// are written before it can run. A write that does not land is not worth
	// failing the clone over, as on Linux.
	if flags & clone_parent_settid != 0 && parent_tid != 0 {
		usercopy.copy_to_user(parent_tid, voidptr(&tid), sizeof(u32))
	}
	if flags & clone_child_settid != 0 && child_tid != 0 {
		usercopy.copy_to_user(child_tid, voidptr(&tid), sizeof(u32))
	}

	sched.enqueue_thread(new_thread, false)

	return u64(tid), 0
}

// Everything else, fork(2) and vfork(2) included: a new process with a copy of
// the caller's address space and descriptor table, running one thread that
// resumes where the caller did.
fn clone_new_process(state &cpulocal.GPRState, flags u64, child_stack u64, parent_tid u64, child_tid u64, tls u64, into_cgroup bool, cgroup voidptr) (u64, u64) {
	mut old_thread := proc.current_thread()
	mut old_process := old_thread.process

	mut new_process := sched.new_process(old_process, unsafe { nil }) or {
		return errno.err, errno.get()
	}

	new_process.name = proc.process_name(old_process.name, new_process.pid)
	fs.fork_namespaces(mut new_process, flags)
	if into_cgroup {
		new_process.cgroup = cgroup
		new_process.cgroup_account = fs.cgroup_account_of(cgroup)
	}

	// CLONE_PARENT makes the child its creator's sibling.
	mut parent_process := old_process
	if flags & clone_parent != 0 && old_process.ppid > 0 {
		mut grandparent := processes[old_process.ppid]
		if grandparent != unsafe { nil } {
			parent_process = grandparent
			new_process.ppid = grandparent.pid
		}
	}

	// Duplicate the descriptor table, keeping each descriptor's flags: a
	// close-on-exec pipe end that lost its flag here would outlive the
	// child's execve and keep the reader from ever seeing end of file. The
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

	mut child_sp := state.rsp
	if child_stack != 0 {
		child_sp = child_stack
	}

	// Numbered once its pid namespace is settled, and before its first thread
	// is, which takes the process's number.
	proc.number_process(mut new_process, old_process)

	mut new_thread := sched.new_cloned_thread(new_process, old_thread, state, child_sp, tls,
		flags & clone_settls != 0) or {
		proc.lock_table()
		mut doomed := new_process.pagemap
		new_process.pagemap = unsafe { nil }
		proc.unlock_table()
		mmap.delete_pagemap(mut doomed) or {}
		proc.free_pid(new_process.pid)
		return errno.err, errno.eagain
	}

	// The native Vinix ABI returns errno in rdx, and the child's is 0. The
	// Linux one leaves rdx as it was, which the child's copy already is.
	if !old_process.linux_abi {
		new_thread.gpr_state.rdx = 0
	}

	if flags & clone_child_cleartid != 0 {
		new_thread.clear_child_tid = child_tid
	}

	viewer := old_process.numbered_in
	tid := u32(proc.tid_in(new_thread, viewer))
	child_view_tid := u32(proc.own_tid(new_thread))

	if flags & clone_parent_settid != 0 && parent_tid != 0 {
		usercopy.copy_to_user(parent_tid, voidptr(&tid), sizeof(u32))
	}
	// The child's pages are its own copy, so its tid word has to be written
	// through its page map rather than ours.
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

// fork(2) and vfork(2) for both ABIs.
pub fn syscall_fork(gpr_state &cpulocal.GPRState) (u64, u64) {
	return clone_new_process(gpr_state, u64(sigchld), 0, 0, 0, 0, false, unsafe { nil })
}

// exit(2) for a Linux program: only the calling thread ends. The process goes
// with its last thread. pthread_exit() and a returning thread function both
// arrive here.
@[noreturn]
pub fn syscall_linux_exit(_ voidptr, status int) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	// Hand back what this thread still owns while its address space is
	// mapped: the robust futexes it holds and the tid word pthread_join()
	// waits on.
	release_robust_list(mut current_thread)
	clear_child_tid(mut current_thread)
	fs.release_thread_fs(mut current_thread)

	process.threads_lock.acquire()
	index := process.threads.index(current_thread)
	last := process.threads.len == 1 && index == 0
	if !last && index >= 0 && !process.exiting {
		process.threads.delete(index)
		process.threads_lock.release()
		proc.free_tid(current_thread.tid)
		// Off the process's page tables before the thread goes: a sibling's
		// exit may free them while this CPU is still on its way out.
		kernel_pagemap.switch_to()
		sched.dequeue_and_die()
	}
	process.threads_lock.release()

	exit_process(u32(status & 0xff) << 8)
}

// exit_group(2): every thread of the process ends.
@[noreturn]
pub fn syscall_exit_group(_ voidptr, status int) {
	mut current_thread := proc.current_thread()
	release_robust_list(mut current_thread)
	exit_process(u32(status & 0xff) << 8)
}

// Stop every thread of `process` but the caller, for good: exit_group() and
// execve() both need the rest gone before the address space goes. A thread
// taken off the CPU here is marked dead first, so no wakeup can put it back.
fn kill_sibling_threads(mut process proc.Process, current &proc.Thread) {
	mut victims := []&proc.Thread{}
	defer {
		unsafe { victims.free() }
	}

	process.threads_lock.acquire()
	for t in process.threads {
		if voidptr(t) != voidptr(current) {
			victims << t
		}
	}
	process.threads.clear()
	process.threads << unsafe { current }
	process.threads_lock.release()

	for victim in victims {
		mut t := unsafe { victim }
		t.is_dead = true
		sched.stop_thread_for_good(t)
		if t.tid != process.pid {
			proc.free_tid(t.tid)
		}
	}
}

// ── signals aimed at one thread ─────────────────────────────────────────────

pub fn syscall_tkill(_ voidptr, tid int, signal int) (u64, u64) {
	return signal_thread(0, tid, signal)
}

pub fn syscall_tgkill(_ voidptr, tgid int, tid int, signal int) (u64, u64) {
	if tgid <= 0 {
		return errno.err, errno.einval
	}
	return signal_thread(tgid, tid, signal)
}

// Raise `signal` on the thread the caller's pid namespace calls `local_tid`,
// which has to belong to the process `tgid` names when that is given. This
// kernel's masks keep signal n in bit n, so 63 is the last one there is room
// for.
fn signal_thread(tgid int, local_tid int, signal int) (u64, u64) {
	if local_tid <= 0 || signal < 0 || signal > 63 {
		return errno.err, errno.einval
	}
	viewer := proc.current_pid_namespace()
	target := proc.thread_in(viewer, local_tid)
	if target == unsafe { nil } {
		return errno.err, errno.esrch
	}
	defer {
		proc.unpin_thread(target)
	}
	if target.is_dead || target.process == unsafe { nil } {
		return errno.err, errno.esrch
	}
	if tgid > 0 && proc.pid_in(target.process, viewer) != tgid {
		return errno.err, errno.esrch
	}
	if signal != 0 {
		sendsig(target, u8(signal))
	}
	return 0, 0
}

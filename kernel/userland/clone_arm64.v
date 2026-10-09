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
	// Returning a PID while leaving the requested pidfd word untouched would
	// falsely report success. Descriptor construction/rollback is unsupported.
	if flags & clone_pidfd != 0 { return errno.err, errno.einval }
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

	new_process.name = proc.process_name(old_process.name, new_process.pid)
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
	mut snapshot := file.open_fdnums(old_process) or {
		failure := errno.get()
		abandon_new_process(mut new_process)
		return errno.err, failure
	}
	for i in snapshot.nums {
		mut old_fd := file.fd_from_fdnum(old_process, i) or { continue }
		fd_flags := old_fd.flags
		old_fd.unref()
		file.fdnum_dup(old_process, i, new_process, i, fd_flags, true, false) or {
			failure := errno.get()
			// The parent may close this slot after the snapshot.
			if failure == errno.ebadf { continue }
			snapshot.dispose()
			abandon_new_process(mut new_process)
			return errno.err, failure
		}
	}
	snapshot.dispose()

	mut child_sp := state.sp
	if child_stack != 0 {
		child_sp = child_stack
	}

	// Numbered once its pid namespace is settled, and before its first thread
	// is, which takes the process's number.
	proc.number_process(mut new_process, old_process)

	mut new_thread := sched.new_cloned_thread(new_process, old_thread, state, child_sp,
		tls, flags & clone_settls != 0) or {
		abandon_new_process(mut new_process)
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

	// Another parent thread can reap the child as soon as it runs.
	pid := proc.pid_in(new_process, viewer)
	sched.publish_user_thread(mut new_process, new_thread)

	return u64(pid), 0
}

// What exit gives back of the process' x86 segments: nothing, on arm64.
fn release_process_segments(mut _ proc.Process) {}

// Whether `t`, stopped by a sibling tearing the process down, was inside the
// kernel -- a syscall, or a page fault -- rather than in userspace: its saved
// PSTATE says EL1. See kill_sibling_threads() in exit.v.
fn thread_in_kernel(t &proc.Thread) bool {
	return t.gpr_state.pstate & 0xf != 0
}

// Take `victim`, stopped in userspace and claimed for exit by a sibling
// tearing the process down, off the CPUs for good and give back what it
// holds. See kill_sibling_threads() in exit.v.
fn stop_claimed_thread(mut victim proc.Thread) {
	// Marked first so that an event trigger racing with us cannot put the
	// thread back on the run queue behind our back.
	katomic.store(mut &victim.is_dead, true)
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
	// A thread that split off its own root and mount namespace -- runc keeps
	// one in the container's namespace for opening mount sources -- holds a
	// reference that would otherwise keep the namespace, and every directory it
	// has something mounted on, alive for good.
	fs.release_thread_fs(mut victim)
	proc.free_tid(victim.tid)
}

fn abandon_new_process(mut new_process proc.Process) {
	proc.lock_table()
	mut doomed := new_process.pagemap
	new_process.pagemap = unsafe { nil }
	proc.unlock_table()
	if doomed != unsafe { nil } { mmap.delete_pagemap(mut doomed) or {} }
	for i in 0 .. new_process.fds.len { file.fdnum_close(&new_process, i, true) or {} }
	fs.release_process_namespaces(mut new_process)
	proc.free_pid(new_process.pid)
}

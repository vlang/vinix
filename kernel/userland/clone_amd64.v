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
import futex
import katomic
import lib
import memory
import memory.mmap
import proc
import sched
import usercopy
import x86.cpu.local as cpulocal
import x86.gdt

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
	if !valid_clone_sharing(flags) { return errno.err, errno.einval }
	if !supported_clone_sharing(flags) { return errno.err, errno.enotsup }
	// Returning a PID while leaving the requested pidfd word untouched would
	// falsely report success. Descriptor construction/rollback is unsupported.
	if flags & clone_pidfd != 0 { return errno.err, errno.einval }
	// The TLS pointer becomes the child's FS base. A non-canonical one would
	// fault the kernel's own WRMSR, so it is refused as Linux refuses it.
	if flags & clone_settls != 0 && tls >= memory.user_address_limit() {
		return errno.err, errno.eperm
	}
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
	// CLONE_VM shares the map independently of CLONE_THREAD's task identity.
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

	sched.publish_cloned_thread(new_thread)

	return u64(tid), 0
}

// A separate process, with a shared or forked map as requested.
fn clone_new_process(state &cpulocal.GPRState, flags u64, child_stack u64, parent_tid u64, child_tid u64, tls u64, into_cgroup bool, cgroup voidptr) (u64, u64) {
	mut old_thread := proc.current_thread()
	mut old_process := old_thread.process

	mut new_process := sched.new_process_with_vm(old_process, unsafe { nil }, if into_cgroup { fs.cgroup_account_of(cgroup) } else { old_process.cgroup_account }, flags & clone_vm != 0) or {
		return errno.err, errno.get()
	}

	new_process.name = proc.process_name(old_process.name, new_process.pid)
	// sched.new_process already owns the inherited executable path.
	// Cloning again overwrote that owned string on every process clone.
	new_process.exe_node = old_process.exe_node
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

	mut child_sp := state.rsp
	if child_stack != 0 {
		child_sp = child_stack
	}

	// Numbered once its pid namespace is settled, and before its first thread
	// is, which takes the process's number.
	proc.number_process(mut new_process, old_process)

	// A copy of the LDT, as of the address space, before the child can run.
	if !sched.copy_ldt(old_process, mut new_process) {
		abandon_new_process(mut new_process)
		return errno.err, errno.enomem
	}
	mut new_thread := sched.new_cloned_thread(new_process, old_thread, state, child_sp, tls,
		flags & clone_settls != 0) or {
		sched.discard_ldt(mut new_process)
		abandon_new_process(mut new_process)
		return errno.err, errno.eagain
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

	// Another parent thread can reap the child as soon as it runs.
	pid := proc.pid_in(new_process, viewer)
	if flags & clone_vfork != 0 {
		new_process.vfork_pending = true
		proc.pin_process(new_process)
	}
	sched.publish_user_thread(mut new_process, new_thread)
	if flags & clone_vfork != 0 { await_vfork(mut new_process) }

	return u64(pid), 0
}

// Give back a process clone_new_process() made but could not start.
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

// fork(2) and the dedicated x86 vfork(2) entry.
pub fn syscall_fork(gpr_state &cpulocal.GPRState) (u64, u64) {
	return clone_new_process(gpr_state, u64(sigchld), 0, 0, 0, 0, false, unsafe { nil })
}

pub fn syscall_vfork(gpr_state &cpulocal.GPRState) (u64, u64) {
	return clone_new_process(gpr_state, clone_vm | clone_vfork | u64(sigchld), 0, 0, 0, 0, false, unsafe { nil })
}

// What exit gives back of the process' x86 segments: its LDT.
fn release_process_segments(mut process proc.Process) {
	sched.drop_ldt(mut process)
}

// Whether `t`, stopped by a sibling tearing the process down, was inside the
// kernel -- a syscall, or a page fault -- rather than in userspace. See
// kill_sibling_threads() in exit.v.
fn thread_in_kernel(t &proc.Thread) bool {
	return t.gpr_state.cs & 3 == 0
}

// Take `victim`, stopped in userspace and claimed for exit by a sibling
// tearing the process down, off the CPUs for good and give back what it
// holds. See kill_sibling_threads() in exit.v.
fn stop_claimed_thread(mut victim proc.Thread) {
	// Marked first so that no wakeup can put it back on the run queue.
	katomic.store(mut &victim.is_dead, true)
	// Waits until it is off every CPU and gives its
	// stacks back.
	sched.stop_thread_for_good(victim)
	futex.release_pi_owner(victim, victim.process.pagemap)
	fs.release_thread_fs(mut victim)
	proc.free_tid(victim.tid)
}

// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module sched

// What a thread and a process start with from the ones that made them, the
// same on both architectures.

import elf
import errno
import memory
import memory.mmap
import proc

// What a new thread gets from the one that created it. Policy and priority are
// inherited -- a program that starts a worker to share the job it is doing
// expects it to be scheduled the same way -- unless the creator carries
// SCHED_RESET_ON_FORK, whose entire purpose is that it does not hand what it
// holds to anything it starts. The flag itself is not passed on either, so a
// child cannot be made to strip a grandchild it never asked to.
//
// The deadline bookkeeping is left behind in any case: a new thread is at the
// start of its first period, not part-way through its parent's.
fn inherited_sched_params(source &proc.Thread) proc.SchedParams {
	if source.sched.reset_on_fork {
		return proc.SchedParams{
			policy: proc.sched_other
		}
	}

	mut inherited := source.sched
	inherited.dl_budget_ns = 0
	inherited.dl_period_end = 0
	inherited.dl_abs_deadline = 0
	return inherited
}

fn attach_thread(mut process proc.Process, mut t proc.Thread) ?int {
	process.threads_lock.acquire()
	defer {
		process.threads_lock.release()
	}

	if process.threads.len == 0 && process.pid != 0 {
		t.tid = process.pid
		proc.bind_tid(t.tid, t)
		proc.number_thread(mut t, true)
	} else {
		t.tid = proc.allocate_tid(t)?
		proc.number_thread(mut t, false)
		// Signal dispositions are the process's, and rt_sigaction keeps every
		// thread on this list in step under this lock. The copy the caller made
		// from its creator can predate an rt_sigaction that ran on another CPU
		// in the meantime, and would then stay behind for good: musl's barrier
		// handler found such a thread still carrying another handler for
		// SIGSYNCCALL, which never acknowledged, and Firefox hung at startup.
		t.sigactions = process.threads[0].sigactions
	}

	process.threads << t
	return t.tid
}

pub fn new_process(old_process &proc.Process, pagemap &memory.Pagemap) ?&proc.Process {
	if unsafe { old_process != nil } && !proc.may_create_process(old_process) {
		errno.set(errno.eagain)
		return none
	}
	// Freed when the process is reaped, in proc.free_pid().
	fds := []voidptr{len: proc.initial_fds} @[freed]
	mut new_proc := &proc.Process{
		pagemap: unsafe { nil }
		fds:     fds
	}

	new_proc.pid = proc.allocate_pid(new_proc) or {
		unsafe {
			new_proc.fds.free()
			free(new_proc)
		}
		return none
	}

	if unsafe { old_process != 0 } {
		new_proc.ppid = old_process.pid
		new_proc.pgid = old_process.pgid
		new_proc.sid = old_process.sid
		// A child is in its parent's session, so the same terminal controls it.
		new_proc.tty_session = old_process.tty_session
		new_proc.uid = old_process.uid
		new_proc.euid = old_process.euid
		new_proc.suid = old_process.suid
		new_proc.gid = old_process.gid
		new_proc.egid = old_process.egid
		new_proc.sgid = old_process.sgid
		new_proc.groups = old_process.groups.clone()
		new_proc.umask = old_process.umask
		new_proc.nice = old_process.nice
		new_proc.executable_path = old_process.executable_path.clone()
		new_proc.rlimits = old_process.rlimits
		new_proc.allow_wx = old_process.allow_wx
		new_proc.sigreturn_page = old_process.sigreturn_page
		// A NUMA memory policy is process state, like nice and the rlimits, so
		// a fork keeps the placement its parent asked for.
		new_proc.mempolicy_mode = old_process.mempolicy_mode
		new_proc.mempolicy_nodemask = old_process.mempolicy_nodemask
		new_proc.pagemap = mmap.fork_pagemap(old_process.pagemap) or { return none }
		new_proc.thread_stack_top = old_process.thread_stack_top
		new_proc.stack_end = old_process.stack_end
		new_proc.saved_auxv = old_process.saved_auxv.clone()
		// The child has the parent's heap, so it has its break too. Starting
		// from none, its first brk() tried to reserve the arena the copy of the
		// address space already held there, failed, and reported a break of 0.
		new_proc.brk_base = old_process.brk_base
		new_proc.brk_current = old_process.brk_current
		new_proc.mmap_anon_non_fixed_base = old_process.mmap_anon_non_fixed_base
		new_proc.current_directory = proc.current_directory_of(old_process)
		proc.inherit_container_state(mut new_proc, old_process)
	} else {
		new_proc.ppid = 0
		new_proc.pgid = new_proc.pid
		new_proc.sid = new_proc.pid
		new_proc.pagemap = unsafe { pagemap }
		new_proc.thread_stack_top = elf.initial_stack_top()
		new_proc.mmap_anon_non_fixed_base = elf.initial_mmap_base()
		new_proc.current_directory = voidptr(vfs_root)
		new_proc.rlimits = proc.default_rlimits()
		proc.inherit_container_state(mut new_proc, unsafe { nil })
	}

	return new_proc
}

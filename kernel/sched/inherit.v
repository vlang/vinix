// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module sched

// What a thread and a process start with from the ones that made them, the
// same on both architectures.

import kbudget
import elf
import errno
import katomic
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

// Publish the identity and first runnable thread together. A signal through
// the new pidfd may otherwise finish and free t before the creator enqueues it.
pub fn publish_user_thread(mut process proc.Process, t &proc.Thread) {
	proc.lock_table()
	proc.publish_pidfd_identity_locked(mut process)
	enqueue_thread(t, false)
	proc.unlock_table()
}

fn attach_thread(mut process proc.Process, mut t proc.Thread) ?int {
	return proc.attach_thread(mut process, mut t)
}

pub fn new_process(old_process &proc.Process, pagemap &memory.Pagemap) ?&proc.Process {
	if unsafe { old_process != nil } && !proc.may_create_process(old_process) {
		errno.set(errno.eagain)
		return none
	}
	kbudget.configure(memory.total_bytes())
	owner := kbudget.open_owner() or { errno.set(errno.eagain); return none }
	mut published := false
	defer { if !published { kbudget.close_owner(owner) } }
	charge := proc.reserve_kernel_for(owner, .process, u64(sizeof(proc.Process)) * 2 + 16384) or { return none }
	mut owned := false
	defer { if !owned { kbudget.release(charge) } }
	table_charge := proc.reserve_kernel_for(owner, .descriptor, u64(proc.initial_fds) * sizeof(voidptr) * 2) or { return none }
	defer { if !owned { kbudget.release(table_charge) } }
	// Freed when the process is reaped, in proc.free_pid().
	fds := unsafe { []voidptr{len: proc.initial_fds} } @[freed]
	mut new_proc := &proc.Process{
		kernel_owner: owner
		kernel_charge: charge
		fd_table_charge: table_charge
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

	owned = true
	published = true

	if unsafe { old_process != 0 } {
		proc.inherit_job_identity(mut new_proc, old_process)
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
		proc.set_cpu_limit(mut new_proc, new_proc.rlimits[proc.rlimit_cpu])
		new_proc.allow_wx = old_process.allow_wx
		new_proc.dumpable = proc.dumpability(old_process)
		new_proc.sigreturn_page = old_process.sigreturn_page
		// A NUMA memory policy is process state, like nice and the rlimits, so
		// a fork keeps the placement its parent asked for.
		new_proc.mempolicy_mode = old_process.mempolicy_mode
		new_proc.mempolicy_nodemask = old_process.mempolicy_nodemask
		new_proc.pagemap = mmap.fork_pagemap(old_process.pagemap, owner) or {
			proc.free_pid(new_proc.pid)
			return none
		}
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
  proc.inherit_command_line(mut new_proc, old_process) or {
   proc.lock_table()
   mut doomed := new_proc.pagemap
   new_proc.pagemap = unsafe { nil }
   proc.unlock_table()
   mmap.delete_pagemap(mut doomed) or {}
   proc.free_pid(new_proc.pid)
   return none
  }
		proc.inherit_container_state(mut new_proc, old_process)
	} else {
		new_proc.ppid = 0
		new_proc.pgid = new_proc.pid
		new_proc.sid = new_proc.pid
		new_proc.pagemap = unsafe { pagemap }
  if new_proc.pagemap != unsafe { nil } {
   new_proc.pagemap.l.acquire()
   memory.account_pagemap(mut new_proc.pagemap, owner) or {
    new_proc.pagemap.l.release()
    new_proc.pagemap = unsafe { nil }
    proc.free_pid(new_proc.pid)
    return none
   }
   new_proc.pagemap.l.release()
  }
		new_proc.thread_stack_top = elf.initial_stack_top()
		new_proc.mmap_anon_non_fixed_base = elf.initial_mmap_base()
		new_proc.current_directory = voidptr(vfs_root)
		new_proc.rlimits = proc.default_rlimits()
		proc.inherit_container_state(mut new_proc, unsafe { nil })
	}

	return new_proc
}

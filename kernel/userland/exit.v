// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module userland

// Threads and processes ending, the same on both architectures: exit(2),
// exit_group(2), a death by signal, and tearing down the siblings of a thread
// that ends the process or execs. The two things that differ -- whether a
// stopped thread was in the kernel, and how one is taken off the CPUs for
// good -- are thread_in_kernel() and stop_claimed_thread() in clone_arm64.v
// and clone_amd64.v.

import event
import file
import fs
import katomic
import memory.mmap
import posixtimer
import proc
import sched
import term
import time

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
		// Off the process's page tables before the thread goes: a sibling's
		// exit may free them while this CPU is still on its way out.
		kernel_pagemap.switch_to()
		sched.dequeue_and_die()
	}

	exit_process(mut current_process, mut current_thread, encode_exit_status(status))
}

// OpenBSD kills a process that breaks a pledge(2) promise with SIGABRT,
// which it cannot catch or ignore.
@[noreturn]
pub fn exit_on_pledge_violation() {
	exit_with_fatal_signal(u8(6))
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

	for i := 0; i < process.threads.len; i++ {
		if voidptr(process.threads[i]) == voidptr(current_thread) {
			process.threads.delete(i)
			break
		}
	}

	last := process.threads.len == 0
	process.threads_lock.release()
	if !last { recheck_group_stop(mut process) }
	return last
}

// Claim the right to tear the process down. exit_group() can arrive while
// another thread is already at it, and the teardown is not repeatable.
fn claim_teardown(mut process proc.Process, mut orphan_change proc.OrphanChange) bool {
	proc.lock_table()
	defer {
		proc.unlock_table()
	}

	if process.exiting {
		return false
	}
	proc.prepare_job_orphan_change_locked(mut orphan_change, process, 0)
	process.exiting = true
	process.exec_transition = false
	process.exec_pending_signals = 0
	process.exec_signal_thread = unsafe { nil }
	return true
}

// Once exec has installed the replacement page map, its old image cannot
// resume after an error. Keep signal selection excluded until exit claims
// teardown, then report a fatal signal through the ordinary exit path.
@[noreturn]
fn abort_exec(mut process proc.Process, mut old_thread proc.Thread) {
	proc.lock_table()
	process.threads_lock.acquire()
	old_thread.process = &process
	process.threads_lock.release()
	proc.unlock_table()
	exit_with_fatal_signal(u8(9))
}

@[noreturn]
fn exit_process(mut current_process proc.Process, mut current_thread proc.Thread, status int) {
	// The descriptor belongs to this owned Thread frame across teardown. A
	// fixed alloca avoids V promotion and carries no child/adopter pointers.
	mut orphan_change := unsafe { &proc.OrphanChange(C.__builtin_alloca(sizeof(proc.OrphanChange))) }
	unsafe { *orphan_change = proc.OrphanChange{} }
	if !claim_teardown(mut current_process, mut orphan_change) {
		// Somebody else got here first. Step out of the thread list before
		// dying so the thread doing the teardown never has to reach us.
		leave_process(mut current_process, current_thread)
		proc.free_tid(current_thread.tid)
		sched.dequeue_and_die()
	}

	// Get every other thread off the CPUs before the address space goes away.
	kill_sibling_threads(mut current_process, current_thread)
	proc.notify_session_exit(current_process)
	posixtimer.remove_process_timers(current_process)
	release_process_segments(mut current_process)

	// If this process had the framebuffer (the desktop, say), the console is
	// dark on its account; give it back before the shell that follows prints.
	term.leave_graphics_mode_if_owner(current_process.pid)

	mut old_pagemap := current_process.pagemap

	// Finish the original process's last turn before its Thread starts
	// carrying kernel_process; the final dequeue must not bill it there.
	proc.charge_cpu_time(mut current_thread, proc.cpu_time_now_ns())
	kernel_pagemap.switch_to()
	current_thread.process = kernel_process
	proc.begin_cpu_time(mut current_thread, proc.cpu_time_now_ns())
	proc.cpu_enter_kernel()
	// Detached under the process table lock, which cgroup memory accounting
	// and /proc hold while they walk a process' page map, so none is still
	// walking the one freed below, and none finds it on the zombie afterwards.
	proc.lock_table()
	proc.preserve_peak_rss(current_process, old_pagemap)
	current_process.pagemap = unsafe { nil }
	proc.unlock_table()

	for i := 0; i < current_process.fds.len; i++ {
		if current_process.fds[i] == unsafe { nil } {
			continue
		}

		file.fdnum_close(current_process, i, true) or {}
	}
	// What closing them changed -- the inode of an unlinked file, freed with
	// its last descriptor -- goes out before the parent can wait for the exit,
	// as it would on the way back from close(2).
	flush_owed_sync()

	// The nearest ancestor that asked to be a child subreaper, or else PID 1,
	// adopts whatever children we leave behind. Taken off our own list first
	// so that the two children locks are never held at the same time.
	current_process.children_lock.acquire()
	mut orphans := unsafe { current_process.children }
	current_process.children = []&proc.Process{}
	current_process.children_lock.release()
	// The sole teardown thread owns this detached list; no old-parent waiter
	// can reap a child now. Retain each Process before transferring its list
	// ownership, since the adopter may reap it before our pdeathsig pass.
	for child_proc in orphans { proc.pin_process_at(child_proc.pid) }

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
		// Parent identity belongs to the process-table snapshot contract. Publish
		// it before taking the new child-list lock, preserving table/list ordering.
		proc.lock_table()
		for mut child_proc in orphans { child_proc.ppid = adopter.pid }
		proc.filter_job_orphan_change_locked(mut orphan_change)
		proc.unlock_table()
		adopter.children_lock.acquire()
		for mut child_proc in orphans {
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
	} else {
		proc.lock_table()
		proc.filter_job_orphan_change_locked(mut orphan_change)
		proc.unlock_table()
	}
	if adopter != unsafe { nil } { proc.unpin_process(adopter) }
	proc.dispatch_job_orphan_change(mut orphan_change)
	for mut child_proc in orphans {
		if child_proc.pdeathsig > 0 && !child_proc.exiting {
			signal_process(mut child_proc, child_proc.pdeathsig)
		}
		proc.unpin_process(child_proc)
	}
	unsafe { orphans.free() }

	proc.save_pidfd_exit_identity(mut current_process)
	fs.release_process_namespaces(mut current_process)

	mmap.delete_pagemap(mut old_pagemap) or {}
	oom_victim_gone(current_process)

	// The Thread structs are about to be recycled, so nothing may reach them
	// through the zombie process that is left behind.
	current_process.threads_lock.acquire()
	current_process.threads.clear()
	current_process.threads_lock.release()

	proc.free_tid(current_thread.tid)

	// Publishing exit state permits an unrelated waiting CPU to reap us.
	// Retain the Process until its final event and parent notification finish.
	publish_ref := proc.pin_process_at(current_process.pid)
	katomic.store(mut &current_process.status, status)
	current_process.job_lock.acquire()
	current_process.wait_exit_ready = true
	current_process.wait_stop_epoch = 0
	current_process.wait_continue_epoch = 0
	current_process.job_lock.release()
	proc.publish_pidfd_exit(mut current_process, status)
	// Wakes a parent blocked in wait4()/waitid()...
	event.trigger(mut &current_process.event, false)
	// ...and tells one that is not waiting yet, which is how a daemon reaps.
	notify_parent(current_process)
	if publish_ref != unsafe { nil } { proc.unpin_process(publish_ref) }

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

// Whether the current thread's process has told it to exit.
pub fn told_to_exit() bool {
	t := proc.current_thread()
	return t != unsafe { nil } && katomic.load(&t.must_exit)
}

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
// After the grace period, only a thread stopped in userspace can be removed
// directly. A sibling still in a syscall or page fault must unwind itself;
// otherwise its filesystem and page-cache locks would be left held.
fn kill_sibling_threads(mut current_process proc.Process, current_thread &proc.Thread) {
	// Pinned while still on the list: any of them may leave and die by itself
	// the moment the lock is let go, and its memory must not be handed to a new
	// thread while this is still telling it to exit.
	current_process.threads_lock.acquire()
	mut others := []&proc.Thread{cap: current_process.threads.len} @[freed]
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
		event.await_one(mut timer.event, true) or {}
		timer.disarm()
		unsafe { free(timer) }
	}

	current_process.threads_lock.acquire()
	mut victims := []&proc.Thread{cap: current_process.threads.len} @[freed]
	for t in current_process.threads {
		if voidptr(t) != voidptr(current_thread) {
			proc.pin_thread(t)
			victims << t
		}
	}
	current_process.threads_lock.release()

	for mut victim in victims {
		if katomic.load(&victim.exit_claimed) != 0 {
			wait_for_thread_to_leave(mut current_process, victim)
			proc.unpin_thread(victim)
			continue
		}
		// Quiesce the target before deciding where it was stopped. A thread
		// faulting a mapped file has no syscall number, but its saved PSTATE
		// still says EL1. Stopping it there strands EXT2's lock and freeing its
		// address space or stack leaves every later disk reader spinning.
		sched.intercept_thread(victim) or {}
		if katomic.load(&victim.exit_claimed) != 0 {
			sched.enqueue_thread(victim, true)
			wait_for_thread_to_leave(mut current_process, victim)
			proc.unpin_thread(victim)
			continue
		}
		if victim.syscall_nr != -1 || thread_in_kernel(victim) {
			// The syscall or page fault owns kernel references and locks. Let it
			// resume and leave through the ordinary must_exit path before the
			// process tears down what it is using.
			sched.enqueue_thread(victim, true)
			wait_for_thread_to_leave(mut current_process, victim)
			proc.unpin_thread(victim)
			continue
		}
		// One that has started leaving by itself gives back its own tid and
		// root. Wait for it rather than tearing down its address space early.
		if !proc.claim_thread_exit(victim) {
			wait_for_thread_to_leave(mut current_process, victim)
			proc.unpin_thread(victim)
			continue
		}
		stop_claimed_thread(mut victim)
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

// A process cannot release its address space while a sibling still runs in
// the kernel on it. The sibling was told to exit and woken above; wait until
// it has left the thread list, even if a loaded guest needs longer than the
// usual grace period to finish its file I/O.
fn wait_for_thread_to_leave(mut process proc.Process, t &proc.Thread) {
	for thread_listed(mut process, t) {
		mut timer := time.new_timer(time.TimeSpec{
			tv_sec:  0
			tv_nsec: 1000000
		})
		event.await_one(mut timer.event, true) or {}
		timer.disarm()
		unsafe { free(timer) }
	}
}

// Returns an owned Process pin for the caller to release.
// Who adopts the children of `process`: its closest living ancestor that set
// PR_SET_CHILD_SUBREAPER, or the init of its pid namespace -- a container's,
// which is what lets tini reap the zombies inside it -- or PID 1.
fn find_reaper(process &proc.Process) &proc.Process {
	mut ppid := process.ppid
	for _ in 0 .. proc.max_pid {
		if ppid <= 1 || ppid >= proc.max_pid {
			break
		}
		ancestor := proc.pin_process_at(ppid)
		if ancestor == unsafe { nil } {
			break
		}
		if ancestor.child_subreaper && !ancestor.exiting {
			return ancestor
		}
		ppid = ancestor.ppid
		proc.unpin_process(ancestor)
	}
	pid_ns := process.numbered_in
	if proc.numbers_own(pid_ns) && pid_ns.init_pid != process.pid && pid_ns.init_pid > 0
		&& pid_ns.init_pid < proc.max_pid {
		namespace_init := proc.pin_process_at(pid_ns.init_pid)
		if namespace_init != unsafe { nil } && !namespace_init.exiting {
			return namespace_init
		}
		if namespace_init != unsafe { nil } { proc.unpin_process(namespace_init) }
	}
	if process.pid == 1 {
		return unsafe { nil }
	}
	return proc.pin_process_at(1)
}

fn notify_process(parent &proc.Process) {
	mut target := unsafe { parent }
	wake_child_waiters(mut target)
	signal_process(mut target, sigchld)
}

// Raise SIGCHLD in the parent, as a signal to the whole process. sendsig()
// drops it where the parent neither handles nor blocks it -- its default
// disposition is to be ignored -- and wakes no thread for it that only
// blocks it, so a parent in an unrelated syscall gets no needless EINTR. A
// parent that blocks it keeps it pending for sigwait(2); it was dropped
// unless a handler had been installed.
fn notify_parent(current_process &proc.Process) {
	publish_child_change(current_process, false)
}

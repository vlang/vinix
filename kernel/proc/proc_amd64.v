@[has_globals]
module proc

import klock
import katomic
import x86.cpu.local as cpulocal
import event.eventstruct

pub fn (t &Thread) current_syscall() (i64, u64) {
	return -1, 0
}

pub fn (t &Thread) syscall_args_text() string {
	return ''
}

// What a wait a signal interrupted reports. The x86-64 syscall exit has no
// restart, so the caller sees EINTR.
pub const interrupted_errno = 4

pub struct Thread {
pub mut:
	// Fixed members, DO NOT MOVE
	running_on   u64
	self         voidptr
	errno        u64
	kernel_stack u64
	user_stack   u64
	syscall_num  u64
	// Movable members
	tid                int
	ns_tid             int
	is_in_queue        bool
	// A filesystem change this thread made during its syscall that is not on
	// the device yet. It is flushed on the way back to userspace, or once an
	// exiting process' descriptors are closed, where no lock is held; see
	// flush_on_return in fs/ext2.
	owes_sync          bool
	l                  klock.Lock
	process            &Process = unsafe { nil }
	gpr_state          cpulocal.GPRState
	gs_base            u64
	fs_base            u64
	pf_stack           u64
	cr3                u64
	fpu_storage        voidptr
	yield_await        klock.Lock
	timeslice          u64
	which_event        u64
	exit_value         voidptr
	exited             eventstruct.Event
	sigactions         [256]SigAction
	pending_signals    u64
	masked_signals     u64
	enqueued_by_signal bool
	// Per-signal origin data for Linux siginfo_t, indexed by signal - 1.
	// Ordinary signals keep these zero; POSIX timers populate them until
	// delivery consumes the pending bit.
	pending_signal_codes    [64]int
	pending_signal_values   [64]u64
	pending_signal_overruns [64]int
	stacks             []voidptr
	// The name PR_SET_NAME gave the thread; empty for one never named.
	comm string
	attached_events    [max_events]&eventstruct.Event
	attached_events_i  u64
	// Monotonic reading taken when this thread was last put on a CPU, or 0
	// when it is not running. What it owes is charged to its process at the
	// moment it is switched away, so the running total never counts a span
	// twice and never counts one that has not finished.
	scheduled_at_ns u64
	cpu_time_ns     u64
	// When this thread's CPU time was last charged to its cgroup, or 0 when it
	// is off the CPU. See charge_cgroup_cpu().
	cgroup_charged_ns u64
	affinity_mask   u64 = u64(-1)
	// Scheduling policy, priority and, under SCHED_DEADLINE, the budget left
	// in this period. Inherited by fork and by every thread a process clones,
	// and kept across exec, so `chrt -f 50 ./program` gives the program the
	// priority and not just the shell that asked for it.
	sched SchedParams
	// Set by a thread that has asked to give up the rest of its turn. It is
	// what tells the scheduler that an equally ranked thread may take the CPU
	// from a policy which otherwise runs to completion.
	yield_requested bool
	// The memory node this thread is at home on. Unset until a CPU first picks
	// it up, which is what claims it: the scheduler then prefers to keep it
	// there, next to the pages it faulted in. -1 means no CPU has run it yet.
	numa_node int = -1
	// Root, working directory and mount namespace of this thread's own, once
	// unshare(2) has split them off from its process'. See ThreadFS.
	fs &ThreadFS = unsafe { nil }
	// References held by code that found this thread under a lock and went on
	// using it after letting go. See pin_thread().
	pins int
	// A mask sigsuspend(2) installed temporarily. The next handler frame has to
	// carry the mask from before the call, so that sigreturn restores it.
	saved_mask       u64
	saved_mask_valid bool
	// The promises a call this thread is making broke, with pledge_set, or
	// 0; the thread is killed on its way back to userspace. And the call's
	// number, for the report. See proc/pledge.v.
	pledge_violation u64
	pledge_syscall   i64
	// Linux thread bookkeeping, as on arm64: the futex word set_tid_address()
	// or CLONE_CHILD_CLEARTID names, and the set_robust_list() head, both
	// handed back when the thread exits.
	clear_child_tid  u64
	robust_list_head u64
	// Torn down by exit_group() or execve() in a sibling; it must never be
	// enqueued again.
	is_dead bool
	// sigaltstack(2): where SA_ONSTACK handlers run.
	sigaltstack_sp   u64
	sigaltstack_size u64
	// What the syscall a seccomp filter turned away returns: an errno, or 0.
	seccomp_errno u64
	// Set by sched.resume_saved_context(): the thread resumes from the context
	// already in gpr_state, not from where the scheduler interrupted it.
	context_preset bool
	// Who gives back the stacks of the dead thread; see
	// sched.stop_thread_for_good(). A word, as katomic.cas needs 4 or 8 bytes.
	reap_claim u32
}

pub fn current_thread() &Thread {
	mut ret := &Thread(unsafe { nil })

	asm volatile amd64 {
		mov ret, gs:[8] // get self
		; =r (ret)
	}

	return ret
}

// Code that keeps using a thread past the lock it found it under pins it first
// and unpins it when done. The arm64 reaper holds a pinned corpse back; see the
// longer note in proc_arm64.v. Shared callers use the same calls on both.

// Pin a thread found under pid_lock or its process' threads_lock, before
// letting go of that lock.
pub fn pin_thread(t &Thread) {
	mut thread := unsafe { t }
	katomic.inc(mut &thread.pins)
}

// Give back a pin. The thread may be freed as soon as this returns, so this is
// the last thing the caller does with it.
pub fn unpin_thread(t &Thread) {
	mut thread := unsafe { t }
	katomic.dec(mut &thread.pins)
}

pub fn thread_is_pinned(t &Thread) bool {
	return katomic.load(&t.pins) != 0
}

// The thread with id `tid`, pinned; the caller unpins it. Nil if there is none.
pub fn get_thread(tid int) &Thread {
	if tid <= 0 || tid >= max_pid {
		return unsafe { nil }
	}

	pid_lock.acquire()
	defer {
		pid_lock.release()
	}

	t := threads_by_tid[tid]
	if t != unsafe { nil } {
		pin_thread(t)
	}
	return t
}

// The first thread of `process`, which is the one signals aimed at the process
// as a whole wait on, pinned; the caller unpins it. Nil if it has none left.
pub fn get_main_thread(process &Process) &Thread {
	mut target := unsafe { process }
	target.threads_lock.acquire()
	defer {
		target.threads_lock.release()
	}

	if target.threads.len == 0 {
		return unsafe { nil }
	}
	t := target.threads[0]
	pin_thread(t)
	return t
}

// A Linux sigset keeps signal n in bit n-1; this kernel's amd64 masks and
// pending sets keep it in bit n. Shared code that takes a sigset from the
// calling program, or hands one back, converts through these.
pub fn sigset_from_user(set u64) u64 {
	return set << 1
}

pub fn sigset_to_user(mask u64) u64 {
	return mask >> 1
}

// What a seccomp program sees as seccomp_data.arch.
pub const seccomp_audit_arch = audit_arch_x86_64

// The bit of a pending or masked set signal `signum` takes: signal n in bit n,
// which leaves no room for signal 64.
pub fn pending_bit(signum int) u8 {
	return u8(signum)
}

pub const max_pending_signal = 63

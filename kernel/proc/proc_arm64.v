@[has_globals]
module proc

import klock
import katomic
import aarch64.cpu
import aarch64.cpu.local as cpulocal
import event.eventstruct

// Per-CPU current thread pointers indexed by CPU number (from TPIDR_EL1)
__global (
	per_cpu_current_thread [256]voidptr
)

pub struct Thread {
pub mut:
	// Fixed members, DO NOT MOVE (offsets match vectors.S expectations)
	running_on   u64
	self         voidptr
	errno        u64
	kernel_stack u64
	user_stack   u64
	syscall_num  u64
	// Movable members
	tid                int
	// The tid as the thread's pid namespace numbers it; see Process.ns_pid.
	ns_tid             int
	is_in_queue        bool
	l                  klock.Lock
	process            &Process = unsafe { nil }
	gpr_state          cpulocal.GPRState
	tpidr_el0          u64 // user TLS pointer (saved/restored on context switch)
	ttbr0              u64 // user page table root
	fpu_storage        voidptr // NEON/FP register state
	yield_await        klock.Lock
	timeslice          u64
	which_event        u64
	exit_value         voidptr
	exited             eventstruct.Event
	sigentry           u64
	sigactions         [256]SigAction
	pending_signals    u64
	masked_signals     u64
	enqueued_by_signal bool
	// The signals rt_sigtimedwait(2) is waiting for on this thread, and zero
	// the rest of the time.
	sigwait_set u64
	// Per-signal origin data for Linux siginfo_t. Ordinary signals keep these
	// zero; POSIX timers populate them until delivery consumes the pending bit.
	pending_signal_codes    [64]int
	pending_signal_values   [64]u64
	pending_signal_overruns [64]int
	stacks             []voidptr
	// The name PR_SET_NAME gave the thread, which a new thread takes from the
	// one that made it; empty for one never named, which goes by its
	// process's.
	comm string
	attached_events    [max_events]&eventstruct.Event
	attached_events_i  u64
	// Linux thread bookkeeping
	clear_child_tid  u64  // set_tid_address()/CLONE_CHILD_CLEARTID futex word
	robust_list_head u64  // set_robust_list() head, walked on thread exit
	is_dead          bool // torn down; must never be enqueued again
	// Physical bases of the pages backing this thread, so that they can be
	// reclaimed once nothing is executing on them any more.
	kstack_phys      u64
	fpu_storage_phys u64
	// sigaltstack(2): where SA_ONSTACK handlers run.
	sigaltstack_sp   u64
	sigaltstack_size u64
	on_sigaltstack   bool
	// A mask sigsuspend(2) installed temporarily. The next handler frame has to
	// carry the mask from before the call, not the one that let it through, so
	// that sigreturn puts the caller back the way POSIX promises.
	saved_mask       u64
	saved_mask_valid bool
	// Monotonic reading taken when this thread was last put on a CPU, or 0
	// when it is not running. What it owes is charged to its process at the
	// moment it is switched away, so the running total never counts a span
	// twice and never counts one that has not finished.
	scheduled_at_ns u64
	cpu_time_ns     u64
	// When this thread's CPU time was last charged to its cgroup, or 0 when it
	// is off the CPU. See charge_cgroup_cpu().
	cgroup_charged_ns u64
	// Set while the thread waits on its way back to userspace for its frozen or
	// throttled cgroup, so the scheduler treats it as stopped in userspace.
	at_user_boundary bool
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
	// The first argument of the syscall in progress, which the result
	// overwrites in the saved registers. A restarted syscall needs it back.
	syscall_x0 u64
	// The syscall this thread is in, or -1 when it is in userspace. What
	// sysrq 't' reports for a thread that is stuck.
	syscall_nr i64 = -1
	syscall_x1 u64
	syscall_x2 u64
	syscall_x3 u64
	// What the syscall a seccomp filter turned away returns: an errno, or 0.
	seccomp_errno u64
	// Set on the way out of a syscall that is being rewound to run again, for
	// the signal dispatched next to take back if its handler wants EINTR.
	restarting_syscall bool
	// Set by a sibling's exit_group() or execve(): leave at the next return to
	// userspace, once the syscall in progress has unwound.
	must_exit bool
	// References held by code that found this thread under a lock and went on
	// using it after letting go. The reaper does not free a pinned corpse. See
	// pin_thread().
	pins int
	// Whoever sets this owns taking the thread down: the thread itself on its
	// way out, or a sibling tearing the process down that has given up waiting
	// for it. Never both, so nothing is released twice. A word rather than a
	// bool, since katomic.cas works on 4 and 8 bytes only.
	exit_claimed u32
}

pub fn (t &Thread) current_syscall() (i64, u64) {
	return t.syscall_nr, t.syscall_x0
}

pub fn (t &Thread) syscall_args_text() string {
	cpu := if t.running_on == u64(-1) { '-' } else { t.running_on.str() }
	return 'x1=0x${t.syscall_x1:x} x2=0x${t.syscall_x2:x} x3=0x${t.syscall_x3:x} blocked=0x${t.masked_signals:x} pending=0x${t.pending_signals:x} cpu=${cpu} queued=${t.is_in_queue}'
}

// What a wait a signal interrupted reports: a restart once the signal is
// handled, which the AArch64 syscall exit knows how to do.
pub const interrupted_errno = 512

pub fn current_thread() &Thread {
	cpu_num := cpu.read_tpidr_el1()
	return unsafe { &Thread(per_cpu_current_thread[cpu_num]) }
}

pub fn set_current_thread(cpu_num u64, thrd &Thread) {
	per_cpu_current_thread[cpu_num] = voidptr(thrd)
}

// ── Thread lifetime ─────────────────────────────────────────────────────────
//
// A Thread's memory goes back to the heap a little after the thread dies: the
// scheduler's reaper frees each corpse when the next thread dies on the same
// CPU. Until it dies, the tid table and its process' thread list are how the
// rest of the kernel finds it, and a dying thread takes itself out of both --
// under pid_lock and its process' threads_lock -- before it gets that far. So a
// thread found through either is alive for as long as that lock is held, and
// not a moment longer.
//
// Signalling a thread, reading its process or stopping it all happen after the
// lock is gone, and with Go's threads coming and going on every CPU a corpse
// was sometimes freed, and its memory handed to a new thread, in between. The
// signal or the stop then landed on an unrelated thread. Code that keeps using
// a thread past the lock it found it under pins it first, while still holding
// that lock, and unpins it when done; the reaper keeps a pinned corpse until
// the last pin is gone.

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

// Take charge of `t`'s exit. Exactly one caller -- the thread leaving on its
// own, or a sibling stopping it -- is told yes.
pub fn claim_thread_exit(t &Thread) bool {
	mut thread := unsafe { t }
	return katomic.cas(mut &thread.exit_claimed, u32(0), u32(1))
}

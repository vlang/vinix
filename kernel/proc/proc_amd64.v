@[has_globals]
module proc

import klock
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
	is_in_queue        bool
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
	sigentry           u64
	sigactions         [256]SigAction
	pending_signals    u64
	masked_signals     u64
	enqueued_by_signal bool
	stacks             []voidptr
	signalfds_lock     klock.Lock
	signalfds          []voidptr
	attached_events    [max_events]&eventstruct.Event
	attached_events_i  u64
	// Monotonic reading taken when this thread was last put on a CPU, or 0
	// when it is not running. What it owes is charged to its process at the
	// moment it is switched away, so the running total never counts a span
	// twice and never counts one that has not finished.
	scheduled_at_ns u64
	cpu_time_ns     u64
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
}

pub fn current_thread() &Thread {
	mut ret := &Thread(unsafe { nil })

	asm volatile amd64 {
		mov ret, gs:[8] // get self
		; =r (ret)
	}

	return ret
}

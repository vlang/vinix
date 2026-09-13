@[has_globals]
module proc

import klock
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
	// Per-signal origin data for Linux siginfo_t. Ordinary signals keep these
	// zero; POSIX timers populate them until delivery consumes the pending bit.
	pending_signal_codes    [64]int
	pending_signal_values   [64]u64
	pending_signal_overruns [64]int
	stacks             []voidptr
	signalfds_lock     klock.Lock
	signalfds          []voidptr
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
	affinity_mask   u64 = u64(-1)
	// The memory node this thread is at home on. Unset until a CPU first picks
	// it up, which is what claims it: the scheduler then prefers to keep it
	// there, next to the pages it faulted in. -1 means no CPU has run it yet.
	numa_node int = -1
}

pub fn current_thread() &Thread {
	cpu_num := cpu.read_tpidr_el1()
	return unsafe { &Thread(per_cpu_current_thread[cpu_num]) }
}

pub fn set_current_thread(cpu_num u64, thrd &Thread) {
	per_cpu_current_thread[cpu_num] = voidptr(thrd)
}

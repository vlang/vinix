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
	stacks             []voidptr
	signalfds_lock     klock.Lock
	signalfds          []voidptr
	attached_events    [max_events]&eventstruct.Event
	attached_events_i  u64
}

pub fn current_thread() &Thread {
	cpu_num := cpu.read_tpidr_el1()
	return unsafe { &Thread(per_cpu_current_thread[cpu_num]) }
}

pub fn set_current_thread(cpu_num u64, thrd &Thread) {
	per_cpu_current_thread[cpu_num] = voidptr(thrd)
}

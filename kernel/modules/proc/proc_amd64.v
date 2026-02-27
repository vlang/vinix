@[has_globals]
module proc

import klock
import x86.cpu.local as cpulocal
import event.eventstruct

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
}

pub fn current_thread() &Thread {
	mut ret := &Thread(unsafe { nil })

	asm volatile amd64 {
		mov ret, gs:[8] // get self
		; =r (ret)
	}

	return ret
}

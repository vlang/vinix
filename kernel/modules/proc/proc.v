// proc.v: Process registry.
// Code is governed by the GPL-2.0 license.
// Copyright (C) 2021-2022 The Vinix authors.

module proc

import klock
import x86.cpu.local as cpulocal
import memory
import katomic
import event.eventstruct

pub const max_fds = 256

pub const max_events = 32

pub struct Process {
pub mut:
	pid                      int
	ppid                     int
	pagemap                  &memory.Pagemap
	thread_stack_top         u64
	threads                  []&Thread
	fds_lock                 klock.Lock
	fds                      [max_fds]voidptr
	children                 []&Process
	mmap_anon_non_fixed_base u64
	current_directory        voidptr
	event                    eventstruct.Event
	status                   int
	itimers                  [4096]u8
	name                     string
}

pub struct SigAction {
pub mut:
	sa_sigaction voidptr
	sa_mask      u64
	sa_flags     int
}

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
	process            &Process
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
	mut ret := &Thread(0)

	asm volatile amd64 {
		mov ret, gs:[8] // get self
		; =r (ret)
	}

	return ret
}

__global (
	processes [65536]&Process
)

pub fn allocate_pid(process &Process) ?int {
	for i := int(1); i < 65536; i++ {
		if katomic.cas(voidptr(&processes[i]), u64(0), u64(process)) {
			return i
		}
	}
	return none
}

pub fn free_pid(pid int) {
	katomic.store(voidptr(&processes[pid]), u64(0))
}

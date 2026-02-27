@[has_globals]
module local

import aarch64.cpu

pub struct GPRState {
pub mut:
	x0     u64
	x1     u64
	x2     u64
	x3     u64
	x4     u64
	x5     u64
	x6     u64
	x7     u64
	x8     u64
	x9     u64
	x10    u64
	x11    u64
	x12    u64
	x13    u64
	x14    u64
	x15    u64
	x16    u64
	x17    u64
	x18    u64
	x19    u64
	x20    u64
	x21    u64
	x22    u64
	x23    u64
	x24    u64
	x25    u64
	x26    u64
	x27    u64
	x28    u64
	x29    u64 // frame pointer
	x30    u64 // link register
	sp        u64
	pc        u64 // elr_el1
	pstate    u64 // spsr_el1
	tpidr_el0 u64 // user TLS pointer
}

pub const abort_stack_size = 128

pub struct Local {
pub mut:
	cpu_number           u64
	zero                 u64
	online               u64
	is_idle              bool
	last_run_queue_index int
	abort_stack          [abort_stack_size]u64
	aborted              bool
	timer_freq           u64
}

__global (
	cpu_locals []&Local
)

pub fn current() &Local {
	ints := cpu.interrupt_state()
	if ints != false {
		panic('Attempted to get current CPU struct without disabling ints')
	}

	cpu_number := cpu.read_tpidr_el1()
	return cpu_locals[cpu_number]
}

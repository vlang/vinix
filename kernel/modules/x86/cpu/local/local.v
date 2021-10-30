module local

import x86.cpu
import trace

[packed]
struct TSS {
pub mut:
	unused0 u32
	rsp0    u64
	rsp1    u64
	rsp2    u64
	unused1 u64
	ist1    u64
	ist2    u64
	ist3    u64
	ist4    u64
	ist5    u64
	ist6    u64
	ist7    u64
	unused2 u64
	iopb    u32
}

pub struct GPRState {
pub mut:
	ds     u64
	es     u64
	rax    u64
	rbx    u64
	rcx    u64
	rdx    u64
	rsi    u64
	rdi    u64
	rbp    u64
	r8     u64
	r9     u64
	r10    u64
	r11    u64
	r12    u64
	r13    u64
	r14    u64
	r15    u64
	err    u64
	rip    u64
	cs     u64
	rflags u64
	rsp    u64
	ss     u64
}

pub const abort_stack_size = 128

struct Local {
pub mut:
	cpu_number           u64
	zero                 u64
	tss                  TSS
	lapic_id             u32
	lapic_timer_freq     u64
	online               u64
	is_idle              bool
	nvme_io_queue_pair   voidptr
	last_run_queue_index int
	abort_stack          [abort_stack_size]u64
	aborted              bool
}

__global (
	cpu_locals []&Local
)

pub fn current() &Local {
	ints := cpu.interrupt_state()
	if ints != false {
		print('Attempted to get current CPU struct without disabling ints\n')
		trace.stacktrace(0)
		panic('')
	}

	mut cpu_number := u64(0)
	asm volatile amd64 {
		mov cpu_number, [0]
		; =r (cpu_number)
	}
	return cpu_locals[cpu_number]
}

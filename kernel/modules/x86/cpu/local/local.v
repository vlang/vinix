module local

import cpu

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
	rip    u64
	cs     u64
	rflags u64
	rsp    u64
	ss     u64
}

pub struct GPRStateErr {
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
	error_code u64
	rip    u64
	cs     u64
	rflags u64
	rsp    u64
	ss     u64
}

struct Local {
pub mut:
	cpu_number           u64
	kernel_stack         u64
	user_stack           u64
	errno                i64
	tss                  TSS
	lapic_id             u32
	lapic_timer_freq     u64
	online				 u64
	is_idle              bool
	fpu_storage_size     u64
	fpu_save             fn (voidptr)
	fpu_restore          fn (voidptr)
	current_thread       voidptr
	last_run_queue_index int
}

__global (
	cpu_locals []&Local
)

pub fn current() &Local {
	return cpu_locals[cpu.get_id()]
}

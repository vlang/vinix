module proc

import klock
import x86.cpu.local as cpulocal
import memory
import file

pub struct Process {
pub mut:
	pagemap memory.Pagemap
	thread_stack_top u64
	threads []&Thread
	fds []&file.FD
	children []&Process
	mmap_anon_non_fixed_base u64
}

pub struct Thread {
pub mut:
	is_in_queue bool
	running_on u64
	l klock.Lock
	process &Process
	gpr_state cpulocal.GPRState
	user_gs u64
	user_fs u64
	kernel_stack u64
	cr3 u64
	event_block_dequeue klock.Lock
	event_occurred klock.Lock
	yield_await klock.Lock
	timeslice u64
}

pub fn current_thread() &Thread {
	asm volatile amd64 { cli }
	cpu_local := cpulocal.current()
	ret := &Thread(cpu_local.current_thread)
	asm volatile amd64 { sti }
	return ret
}

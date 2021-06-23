[manualfree] module proc

import klock
import x86.cpu.local as cpulocal
import memory

pub const max_fds = 256

pub struct Process {
pub mut:
	ppid int
	pagemap memory.Pagemap
	thread_stack_top u64
	threads []&Thread
	fds_lock klock.Lock
	fds [max_fds]voidptr
	children []&Process
	mmap_anon_non_fixed_base u64
	current_directory voidptr
}

pub struct Thread {
pub mut:
	is_in_queue bool
	running_on u64
	l klock.Lock
	process &Process
	gpr_state cpulocal.GPRState
	gs_base u64
	fs_base u64
	kernel_stack u64
	pf_stack u64
	cr3 u64
	event_block_dequeue klock.Lock
	event_occurred klock.Lock
	yield_await klock.Lock
	timeslice u64
}

pub fn current_thread() &Thread {
	mut f := u64(0)
	asm volatile amd64 {
		pushfq
		pop f
		cli
		; =rm (f)
	}
	cpu_local := cpulocal.current()
	ret := cpu_local.current_thread
	if f & (1 << 9) != 0 {
		asm volatile amd64 { sti }
	}
	return ret
}

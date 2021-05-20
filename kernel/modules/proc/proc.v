module proc

import klock
import x86.cpu.local as cpulocal
import memory

pub struct Process {
pub mut:
	pagemap memory.Pagemap
}

pub struct Thread {
pub mut:
	is_in_queue bool
	l klock.Lock
	process &Process
	gpr_state cpulocal.GPRState
	user_gs u64
	user_fs u64
	user_stack u64
	kernel_stack u64
	event_block_dequeue klock.Lock
	event_occurred klock.Lock
	yield_await klock.Lock
}

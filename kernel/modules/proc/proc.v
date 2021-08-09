module proc

import klock
import x86.cpu.local as cpulocal
import memory
import katomic
import event.eventstruct

pub const max_fds = 256

pub struct Process {
pub mut:
	pid int
	ppid int
	pagemap &memory.Pagemap
	thread_stack_top u64
	threads []&Thread
	fds_lock klock.Lock
	fds [max_fds]voidptr
	children []&Process
	mmap_anon_non_fixed_base u64
	current_directory voidptr
	event eventstruct.Event
	status int
}

pub struct SigAction {
pub mut:
	sa_sigaction voidptr
	sa_mask u64
	sa_flags int
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
	fpu_storage voidptr
	yield_await klock.Lock
	timeslice u64
	which_event u64
	exit_value voidptr
	exited eventstruct.Event
	errno u64
	sigentry u64
	sigactions [256]SigAction
	pending_signals u64
	masked_signals u64
	enqueued_by_signal bool
	stacks []voidptr
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

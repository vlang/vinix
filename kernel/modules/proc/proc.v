@[has_globals]
module proc

import klock
import memory
import katomic
import event.eventstruct

pub const max_fds = 256

pub const max_events = 32

pub struct Process {
pub mut:
	pid                      int
	ppid                     int
	pagemap                  &memory.Pagemap = unsafe { nil }
	thread_stack_top         u64
	threads                  []&Thread
	fds_lock                 klock.Lock
	fds                      [max_fds]voidptr
	children                 []&Process
	mmap_anon_non_fixed_base u64
	current_directory        voidptr
	event                    eventstruct.Event
	status                   int
	name                     string
}

pub struct SigAction {
pub mut:
	sa_sigaction voidptr
	sa_mask      u64
	sa_flags     int
	sa_restorer  voidptr // SA_RESTORER trampoline (musl: __restore_rt)
}

__global (
	processes [65536]&Process
)

pub fn allocate_pid(process &Process) ?int {
	for i := int(1); i < 65536; i++ {
		if katomic.cas[&Process](mut &processes[i], unsafe { nil }, process) {
			return i
		}
	}
	return none
}

pub fn free_pid(pid int) {
	katomic.store[&Process](mut &processes[pid], unsafe { nil })
}

@[has_globals]
module proc

import klock
import memory
import event.eventstruct

pub const max_fds = 256

pub const max_events = 32

pub const max_pid = 65536

pub struct Process {
pub mut:
	pid                      int
	ppid                     int
	pgid                     int
	sid                      int
	pagemap                  &memory.Pagemap = unsafe { nil }
	thread_stack_top         u64
	threads                  []&Thread
	threads_lock             klock.Lock
	fds_lock                 klock.Lock
	fds                      [max_fds]voidptr
	children                 []&Process
	children_lock            klock.Lock
	mmap_anon_non_fixed_base u64
	current_directory        voidptr
	event                    eventstruct.Event
	status                   int
	// Set once exit_group() (or a fatal fault) has started tearing the
	// process down, so late-arriving threads do not try to do it again.
	exiting bool
	name    string
}

pub struct SigAction {
pub mut:
	sa_sigaction voidptr
	sa_mask      u64
	sa_flags     int
	sa_restorer  voidptr // SA_RESTORER trampoline (musl: __restore_rt)
}

// PIDs and TIDs live in a single namespace, as on Linux: the main thread of a
// process has tid == pid, and every other thread holds an id that no process
// can be given while it is alive.
__global (
	processes      [max_pid]&Process
	threads_by_tid [max_pid]&Thread
	pid_lock       klock.Lock
)

fn find_free_id() ?int {
	for i := int(1); i < max_pid; i++ {
		if processes[i] == unsafe { nil } && threads_by_tid[i] == unsafe { nil } {
			return i
		}
	}
	return none
}

pub fn allocate_pid(process &Process) ?int {
	pid_lock.acquire()
	defer {
		pid_lock.release()
	}

	i := find_free_id()?
	processes[i] = unsafe { process }
	return i
}

pub fn free_pid(pid int) {
	if pid <= 0 || pid >= max_pid {
		return
	}

	pid_lock.acquire()
	defer {
		pid_lock.release()
	}

	processes[pid] = unsafe { nil }
	// The main thread's tid aliases the pid, so it is released together.
	threads_by_tid[pid] = unsafe { nil }
}

pub fn allocate_tid(thrd &Thread) ?int {
	pid_lock.acquire()
	defer {
		pid_lock.release()
	}

	i := find_free_id()?
	threads_by_tid[i] = unsafe { thrd }
	return i
}

// Claim an already-reserved id for a thread. Used to give a process' main
// thread the tid that matches its pid.
pub fn bind_tid(tid int, thrd &Thread) {
	if tid <= 0 || tid >= max_pid {
		return
	}

	pid_lock.acquire()
	defer {
		pid_lock.release()
	}

	threads_by_tid[tid] = unsafe { thrd }
}

pub fn free_tid(tid int) {
	if tid <= 0 || tid >= max_pid {
		return
	}

	pid_lock.acquire()
	defer {
		pid_lock.release()
	}

	threads_by_tid[tid] = unsafe { nil }
}

pub fn thread_by_tid(tid int) &Thread {
	if tid <= 0 || tid >= max_pid {
		return unsafe { nil }
	}

	pid_lock.acquire()
	defer {
		pid_lock.release()
	}

	return threads_by_tid[tid]
}

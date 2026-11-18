@[has_globals]
module proc

import klock

pub const max_fds = 32
pub const initial_fds = 4
pub const rlimit_nofile = 0
pub const mac_inspect = u32(1)
pub struct RLimit { pub mut: cur u64 }

pub struct Process {
pub mut:
	name string = 'fixture'
	shared_pending_signals u64
	fds_lock klock.Lock
	fds []voidptr
	fds_reserved voidptr
	rlimits [1]RLimit
}

pub struct Thread {
pub mut:
	pending_signals u64
	masked_signals u64
	must_exit bool
	process &Process = unsafe { nil }
}

pub const interrupted_errno = 512
__global wait_capture_thread = Thread{}
__global wait_capture_process = Process{}

pub fn reset() {
	assert wait_capture_process.fds_reserved == unsafe { nil }
	for fd in wait_capture_process.fds { assert fd == unsafe { nil } }
	unsafe { wait_capture_process.fds.free() }
	wait_capture_process = Process{ fds: unsafe { []voidptr{len: initial_fds} }, rlimits: [RLimit{ cur: u64(max_fds) }]! }
	wait_capture_thread = Thread{ process: unsafe { &wait_capture_process } }
}

pub fn current_thread() &Thread { return unsafe { &wait_capture_thread } }
pub fn interrupted() bool {
	task := current_thread()
	return task.must_exit || pending_signals(task) & ~task.masked_signals != 0
}
pub fn private_signal(masked bool) {
	wait_capture_thread.pending_signals = u64(1) << 14
	wait_capture_thread.masked_signals = if masked { u64(1) << 14 } else { u64(0) }
}
pub fn shared_signal() { wait_capture_process.shared_pending_signals = u64(1) << 14 }
pub fn exit_thread() { wait_capture_thread.must_exit = true }

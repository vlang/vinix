@[has_globals]
module proc

pub struct Process {
pub mut:
	shared_pending_signals u64
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
	wait_capture_process = Process{}
	wait_capture_thread = Thread{ process: unsafe { &wait_capture_process } }
}

pub fn current_thread() &Thread { return unsafe { &wait_capture_thread } }
pub fn private_signal(masked bool) {
	wait_capture_thread.pending_signals = u64(1) << 14
	wait_capture_thread.masked_signals = if masked { u64(1) << 14 } else { u64(0) }
}
pub fn shared_signal() { wait_capture_process.shared_pending_signals = u64(1) << 14 }
pub fn exit_thread() { wait_capture_thread.must_exit = true }

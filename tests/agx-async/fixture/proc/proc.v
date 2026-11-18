@[has_globals]
module proc

pub struct Thread {
pub mut:
	must_exit bool
	masked_signals u64
	pending u64
	process &Process = unsafe { nil }
}

pub struct Process {
pub mut:
	job_stop_signal int
}

__global host_task Thread

pub fn current_thread() &Thread { return &host_task }

pub fn pending_signals(t &Thread) u64 { return t.pending }

pub fn interrupted() bool { return host_task.must_exit || host_task.pending & ~host_task.masked_signals != 0 }

@[has_globals]
module proc

import klock

pub const max_pid = 2

pub struct Namespace {
pub mut:
	data voidptr
}

pub struct Process {
pub mut:
	euid           u32
	egid           u32
	exit_published bool
	fs_lock klock.Lock
	threads_lock klock.Lock
	ns NamespaceSet
	threads []&Thread
}

pub struct NamespaceSet {
pub mut:
	mnt &Namespace = unsafe { nil }
}

pub struct ThreadFS {
pub mut:
	lock klock.Lock
	mnt &Namespace = unsafe { nil }
}

pub struct Thread {
pub mut:
	process &Process = unsafe { nil }
	fs &ThreadFS = unsafe { nil }
}

__global (
	thread  Thread
	process Process
	fixture_owner &Process
)

pub fn current_thread() &Thread {
	thread.process = &process
	return &thread
}

pub fn process_at(_ int) &Process { return fixture_owner }

pub fn set_owner(owner &Process) { fixture_owner = unsafe { owner } }

pub fn mount_namespace_of(_ &Process) &Namespace { return unsafe { nil } }

pub fn lock_table() {}

pub fn unlock_table() {}

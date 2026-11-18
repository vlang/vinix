// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module proc

pub struct Process {
pub:
	pid int
}

pub struct Thread {
pub:
	process &Process = unsafe { nil }
}

__global timestamp_test_process = Process{pid: 7}
__global timestamp_test_thread Thread
__global timestamp_test_owner_enabled = false

pub fn enable_owner(enabled bool) {
	timestamp_test_owner_enabled = enabled
	timestamp_test_thread = Thread{process: unsafe { &timestamp_test_process }}
}

pub fn current_thread() &Thread {
	return unsafe { if timestamp_test_owner_enabled { &timestamp_test_thread } else { nil } }
}

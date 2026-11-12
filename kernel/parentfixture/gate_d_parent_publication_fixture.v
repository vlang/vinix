// SPDX-License-Identifier: GPL-2.0-or-later
// Fixture kernels only. No userspace pointer is retained by this gate.
@[has_globals]
module parentfixture

import errno
import klock
import proc
import sched
import time

struct Gate {
mut:
	target int
	mode int
	phase int
}
__global (
	parent_fixture_lock klock.Lock
	parent_fixture_gate Gate
)

pub fn control(operation u64, target u64, mode u64, reserved u64) (u64, u64) {
	if proc.current_thread().process.pid != 1 { return errno.err, errno.eperm }
	if target <= 1 || target >= u64(proc.max_pid) || mode !in [u64(1), 2]! || reserved != 0 { return errno.err, errno.einval }
	parent_fixture_lock.acquire()
	defer { parent_fixture_lock.release() }
	if operation == 1 {
		if parent_fixture_gate.target != 0 && parent_fixture_gate.phase !in [2, 3]! { return errno.err, errno.ebusy }
		parent_fixture_gate = Gate{target: int(target), mode: int(mode)}
		return 0, 0
	}
	if parent_fixture_gate.target != int(target) || parent_fixture_gate.mode != int(mode) { return errno.err, errno.einval }
	if operation == 2 { return u64(parent_fixture_gate.phase), 0 }
	if operation == 3 && parent_fixture_gate.phase == 1 { parent_fixture_gate.phase = 2; return 0, 0 }
	return errno.err, errno.einval
}

// Called without process-table or child-list locks, including from exit
// after its thread has detached. The caller supplies the exiting PID then.
pub fn pause(mode int, target int) {
	parent_fixture_lock.acquire()
	if parent_fixture_gate.target != target || parent_fixture_gate.mode != mode || parent_fixture_gate.phase != 0 { parent_fixture_lock.release(); return }
	parent_fixture_gate.phase = 1
	parent_fixture_lock.release()
	deadline := time.monotonic_ns() + 20 * u64(1000000000)
	for {
		parent_fixture_lock.acquire()
		if parent_fixture_gate.phase == 2 { parent_fixture_lock.release(); return }
		if time.monotonic_ns() > deadline { parent_fixture_gate.phase = 3; parent_fixture_lock.release(); return }
		parent_fixture_lock.release()
		sched.yield(true)
	}
}

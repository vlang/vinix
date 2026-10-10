// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Stopping userspace for a system sleep.
//
// Before the devices are suspended every program has to be off the CPU: one
// that carried on would find its disk asleep and its display gone. A frozen
// cgroup already keeps its threads off the CPU, and only once they are in
// userspace, so that nothing held in the kernel stays held; this is the same
// thing for every thread at once, at the same two places -- the scheduler's
// choice of what to run, and the way back to userspace from a syscall or a
// fault. See cgroup_holds_thread_back() and park_for_cgroup() in policy.v.
//
// A thread inside a syscall runs on until it returns: the one that asked for
// the sleep among them, which is how it gets to carry the sleep out. A thread
// with SIGKILL pending still gets through, as it does through a frozen cgroup.
@[has_globals]
module sched

import katomic

__global (
	sched_userspace_frozen u32
)

// Keep every thread out of userspace from its next scheduling point on.
// Kernel threads are not affected. Threads already in userspace on other CPUs
// leave at their next timer interrupt, within a time slice.
pub fn freeze_userspace() {
	katomic.store(mut &sched_userspace_frozen, u32(1))
}

pub fn thaw_userspace() {
	katomic.store(mut &sched_userspace_frozen, u32(0))
}

fn userspace_frozen() bool {
	return katomic.load(&sched_userspace_frozen) != 0
}

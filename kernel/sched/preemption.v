// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module sched

import katomic
import proc

const max_preemption_cpus = 256

__global (
	// Scalar snapshots only: enqueue never borrows another CPU's Thread.
	// That CPU publishes its effective rank while holding the thread lock.
	cpu_dispatch_rank [max_preemption_cpus]int
	cpu_dispatch_deadline [max_preemption_cpus]u64
	cpu_reschedule_pending [max_preemption_cpus]u32
)

fn publish_dispatch_priority(number u64, t &proc.Thread, now_ns u64) {
	if number >= max_preemption_cpus { return }
	if t == unsafe { nil } {
		katomic.store(mut &cpu_dispatch_rank[number], -1)
		return
	}
	mut running := unsafe { t }
	rank := runnable_rank(mut running, now_ns, realtime_throttled(number, now_ns))
	katomic.store(mut &cpu_dispatch_deadline[number], running.sched.dl_abs_deadline)
	katomic.store(mut &cpu_dispatch_rank[number], rank)
}

fn enqueue_outranks(rank int, deadline u64, current_rank int, current_deadline u64) bool {
	return rank > current_rank || (rank == proc.rank_deadline
		&& current_rank == proc.rank_deadline && deadline < current_deadline)
}

// Called with the queue lock held. Prefer an eligible idle CPU, otherwise
// interrupt one CPU running lower-ranked work. Snapshots are advisory: the
// destination's normal policy scan rechecks affinity, bandwidth and cgroups.
// A stale snapshot can cost an extra interrupt, never grant an entitlement.
fn request_enqueue_preemption(t &proc.Thread) {
	mut target := u64(-1)
	mut lowest := int(0x7fffffff)
	rank := t.sched.rank()
	for entry in cpu_locals {
		number := entry.cpu_number
		if number >= max_preemption_cpus || katomic.load(&entry.online) == 0
			|| !may_run_here(t, number) { continue }
		if katomic.load(&entry.is_idle) {
			target = number
			break
		}
		current_rank := katomic.load(&cpu_dispatch_rank[number])
		if current_rank < lowest && enqueue_outranks(rank, t.sched.dl_abs_deadline,
			current_rank, katomic.load(&cpu_dispatch_deadline[number])) {
			target = number
			lowest = current_rank
		}
	}
	if target == u64(-1) { return }
	if katomic.cas(mut &cpu_reschedule_pending[target], u32(0), u32(1)) {
		if !send_reschedule(target) {
			katomic.store(mut &cpu_reschedule_pending[target], u32(0))
		}
	}
}

fn consume_reschedule(number u64) {
	if number < max_preemption_cpus {
		katomic.store(mut &cpu_reschedule_pending[number], u32(0))
	}
}

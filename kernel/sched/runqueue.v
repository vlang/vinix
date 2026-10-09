// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module sched

import katomic
import klock
import proc
import time

const max_runqueue_cpus = 256

struct RunQueue {
mut:
	lock  klock.Lock
	head  &proc.Thread = unsafe { nil }
	tail  &proc.Thread = unsafe { nil }
	count u64
}

__global (
	runqueues      [max_runqueue_cpus]RunQueue
	// Firmware capacity snapshots, published before userspace. Zero is unknown.
	cpu_capacities [max_runqueue_cpus]u32
)

pub fn cpu_capacity(number u64) u32 {
	if number >= max_runqueue_cpus { return 1024 }
	value := katomic.load(&cpu_capacities[number])
	return if value == 0 { u32(1024) } else { value }
}

pub fn set_cpu_capacity(number u64, value u32) {
	if number < max_runqueue_cpus && value > 0 && value <= 1024 {
		katomic.store(mut &cpu_capacities[number], value)
	}
}

// Affinity is mandatory; capacity hints only bias placement. Unknown or
// insufficient capacity never makes an otherwise allowed CPU ineligible.
fn placement_cpu(t &proc.Thread) u64 {
	mut target := u64(0)
	mut best := ~u64(0)
	count := cpu_locals.len
	if count == 0 { return target }
	start := u64(t.tid) % u64(count)
	for step in 0 .. count {
		number := (start + u64(step)) % u64(count)
		entry := cpu_locals[number]
		if katomic.load(&entry.online) == 0 || !may_run_here(t, number) { continue }
		capacity := cpu_capacity(number)
		load := katomic.load(&runqueues[number % max_runqueue_cpus].count)
		mut score := load * 1024 / u64(capacity)
		if capacity < t.sched.util_min { score += u64(1) << 40 }
		if t.sched.util_max < 1024 { score += u64(capacity) / 128 }
		if score < best {
			target = number
			best = score
		}
	}
	return target
}

fn capacity_preferred(t &proc.Thread, number u64) bool {
	capacity := cpu_capacity(number)
	if capacity >= t.sched.util_min && t.sched.util_max == 1024 { return true }
	// An idle suitable core gets first refusal. Busy preferred cores permit
	// stealing onto another allowed CPU; hints cannot leave a task stranded.
	for entry in cpu_locals {
		other := entry.cpu_number
		if other == number || katomic.load(&entry.online) == 0
			|| !katomic.load(&entry.is_idle) || !may_run_here(t, other) {
			continue
		}
		other_capacity := cpu_capacity(other)
		if other_capacity >= t.sched.util_min && (capacity < t.sched.util_min
			|| (t.sched.util_max < 1024 && other_capacity < capacity)) {
			return false
		}
	}
	return true
}

fn queue_append(mut q RunQueue, mut t proc.Thread) {
	t.queue_previous = q.tail
	t.queue_next = unsafe { nil }
	if q.tail == unsafe { nil } {
		q.head = &t
	} else {
		q.tail.queue_next = &t
	}
	q.tail = &t
}

fn queue_unlink(mut q RunQueue, mut t proc.Thread) {
	if t.queue_previous == unsafe { nil } {
		q.head = t.queue_next
	} else {
		t.queue_previous.queue_next = t.queue_next
	}
	if t.queue_next == unsafe { nil } {
		q.tail = t.queue_previous
	} else {
		t.queue_next.queue_previous = t.queue_previous
	}
	t.queue_previous = unsafe { nil }
	t.queue_next = unsafe { nil }
}

// The caller owns Thread storage. The membership lock serializes duplicate
// wakes with dequeue; each queue protects its links and their Thread lifetime.
fn queue_enqueue(t &proc.Thread, wake bool) bool {
	mut task := unsafe { t }
	task.queue_membership_lock.acquire()
	defer { task.queue_membership_lock.release() }
	if katomic.load(&task.is_dead) { return false }
	if katomic.load(&task.is_in_queue) {
		if wake { request_enqueue_preemption(task) }
		return true
	}
	number := placement_cpu(task) % max_runqueue_cpus
	mut q := unsafe { &runqueues[number] }
	q.lock.acquire()
	task.queue_cpu = u32(number)
	queue_append(mut q, mut task)
	katomic.store(mut &task.is_in_queue, true)
	katomic.store(mut &q.count, q.count + 1)
	q.lock.release()
	$if amd64 {
		$if linuxkpi ? {
			scheduler_queue_lock.acquire()
			linuxkpi_iowait_end_locked(mut task)
			scheduler_queue_lock.release()
		}
	}
	if wake { request_enqueue_preemption(task) }
	return true
}

fn queue_dequeue(t &proc.Thread) bool {
	mut task := unsafe { t }
	task.queue_membership_lock.acquire()
	defer { task.queue_membership_lock.release() }
	if katomic.load(&task.is_in_queue) {
		mut q := unsafe { &runqueues[task.queue_cpu] }
		q.lock.acquire()
		queue_unlink(mut q, mut task)
		katomic.store(mut &task.is_in_queue, false)
		katomic.store(mut &q.count, q.count - 1)
		q.lock.release()
	}
	$if amd64 {
		$if linuxkpi ? {
			if katomic.load(&task.is_dead) {
				scheduler_queue_lock.acquire()
				linuxkpi_iowait_end_locked(mut task)
				scheduler_queue_lock.release()
			}
		}
	}
	return true
}

// Selection holds at most one queue lock. Taking t.l while its queue is
// locked transfers the queue's lifetime guarantee into scheduler ownership;
// teardown drains t.l before freeing storage. Stealing needs no node move:
// a running task remains linked and locked until it blocks or exits.
fn scan_run_queue(cpu_number u64, last_index &int, want_node int) &proc.Thread {
	ranked := proc.scheduling_policies_in_use() || proc.priority_donations_active()
	now := clock_ns()
	throttled := realtime_throttled(cpu_number, now)
	mut best := &proc.Thread(unsafe { nil })
	mut best_rank := -1
	mut best_deadline := u64(0)
	count := if cpu_locals.len < max_runqueue_cpus { cpu_locals.len } else { max_runqueue_cpus }
	if count == 0 { return best }
	// Periodic remote-first scans prevent a busy home queue hiding work that
	// has an affinity restriction or was placed before an affinity change.
	mut turn := *last_index + 1
	if turn >= count * 8 { turn = 0 }
	unsafe { *last_index = turn }
	start := if turn % 8 == 0 { u64(turn / 8) % u64(count) } else { cpu_number % u64(count) }
	for step in 0 .. count {
		number := (start + u64(step)) % u64(count)
		mut q := unsafe { &runqueues[number] }
		if katomic.load(&q.count) == 0 { continue }
		q.lock.acquire()
		for t := q.head; t != unsafe { nil }; t = t.queue_next {
			if katomic.load(&t.is_dead) || !may_run_here(t, cpu_number)
				|| !capacity_preferred(t, cpu_number)
				|| (want_node >= 0 && t.numa_node >= 0 && t.numa_node != want_node) {
				continue
			}
			mut candidate := unsafe { t }
			if !candidate.l.test_and_acquire() { continue }
			if cgroup_parks(candidate, &candidate.gpr_state) {
				candidate.l.release()
				continue
			}
			rank := runnable_rank(mut candidate, now, throttled)
			if !ranked || rank > best_rank || (rank == proc.rank_deadline && rank == best_rank
				&& candidate.sched.dl_abs_deadline < best_deadline) {
				if best != unsafe { nil } { best.l.release() }
				best = candidate
				best_rank = rank
				best_deadline = candidate.sched.dl_abs_deadline
				if !ranked { break }
			} else {
				candidate.l.release()
			}
		}
		if best != unsafe { nil } && best.queue_cpu == u32(number) {
			queue_unlink(mut q, mut best)
			queue_append(mut q, mut best)
		}
		q.lock.release()
		if best != unsafe { nil } && !ranked { return best }
	}
	return best
}

fn queue_realtime_pending(cpu_number u64) bool {
	for number in 0 .. max_runqueue_cpus {
		mut q := unsafe { &runqueues[number] }
		if katomic.load(&q.count) == 0 { continue }
		q.lock.acquire()
		mut found := false
		for t := q.head; t != unsafe { nil }; t = t.queue_next {
			if !katomic.load(&t.is_dead) && may_run_here(t, cpu_number)
				&& !t.l.is_held() && proc.effective_sched_rank(t) >= proc.rank_realtime_base {
				found = true
				break
			}
		}
		q.lock.release()
		if found { return true }
	}
	return false
}

fn idle_wakeup_us(ceiling u64) u64 {
	for i in 0 .. max_runqueue_cpus {
		if katomic.load(&runqueues[i].count) != 0 {
			return time.next_wakeup_us(if ceiling < 1000 { ceiling } else { u64(1000) })
		}
	}
	return time.next_wakeup_us(ceiling)
}

fn timer_deadline_changed() {
	if katomic.load(&scheduler_ready) && cpu_locals.len != 0 { send_reschedule(0) }
}

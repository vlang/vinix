// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
@[has_globals]
module sched

// Which thread a CPU runs, and for how long: affinity, the real-time and
// deadline policies with their bandwidth cap, cgroup freezing and cpu.max, and
// the round-robin scan over the run queue -- the same on both architectures.
// Each supplies clock_ns(), the clock the scheduler bills with, and
// interrupts_off().

import katomic
import proc

// May this thread run on this CPU at all? Asked by the run-queue scan before it
// picks a thread up, and by the timer handler about the thread already on the
// CPU: an affinity change while a thread is running has to take effect, so a CPU
// it may no longer use puts it down even with nothing to replace it.
fn may_run_here(t &proc.Thread, cpu_number u64) bool {
	if cpu_number >= 64 {
		return true
	}
	return t.affinity_mask & (u64(1) << cpu_number) != 0
}

// ── Real-time scheduling ─────────────────────────────────────────────────────

// How many laps the ranked scan makes before it gives up. A lap that loses the
// thread it settled on to another CPU looks again, where that thread's lock is
// now held and is skipped like any other; a CPU that still comes away with
// nothing simply idles until its next tick.
const pick_attempts = 4

// What an ordinary thread's timeslice is shortened to while anything on the
// machine is scheduled by policy. See effective_timeslice().
const realtime_preempt_slice_us = u64(1000)

// SCHED_IDLE only runs when no other thread will have the CPU, and hands it
// back quickly when it does get one.
const idle_policy_slice_us = u64(1000)

// How often a CPU with nothing to run looks for real-time work, rather than
// waiting for its next idle tick. See await(): this, and not the tick, is what
// bounds how long a real-time thread waits on a machine that has a CPU free.
const realtime_poll_interval_ns = u64(25000)

// The real-time bandwidth cap, at Linux's default of 950 ms in every second.
// Without one, a SCHED_FIFO loop at any priority takes a CPU and never gives
// it back, which on a single-processor machine means the whole machine --
// including the shell that would have to kill it.
//
// A throttled CPU does not stop running real-time threads. It demotes them
// behind every ordinary thread instead, so one that is holding a lock somebody
// else is waiting on still gets to finish with it.
const rt_period_ns = u64(1000000000)

const rt_runtime_ns = u64(950000000)

const max_rt_cpus = 64

__global (
	// When this CPU's bandwidth window opened and how much of it real-time
	// threads have spent. Written only by the CPU they belong to.
	rt_window_start_ns [max_rt_cpus]u64
	rt_window_used_ns  [max_rt_cpus]u64
	// The reading this CPU last billed for, so a turn spanning several trips
	// through the scheduler is charged once, in pieces.
	rt_account_last_ns [max_rt_cpus]u64
)

// Where a thread sits in the picking order as the queue stands now. A deadline
// thread with nothing left of this period's budget, and every real-time thread
// on a CPU that has spent its bandwidth, drops behind the ordinary threads
// rather than being passed over altogether.
fn runnable_rank(mut t proc.Thread, now_ns u64, throttled bool) int {
	rank := t.sched.rank()
	if rank < proc.rank_realtime_base {
		return rank
	}
	if throttled {
		return proc.rank_idle
	}
	if t.sched.policy == proc.sched_deadline && !replenish_deadline(mut t, now_ns) {
		return proc.rank_idle
	}
	return rank
}

// Open a deadline thread's next period if the last one has ended, and report
// whether it has runtime left in the one it is now in.
fn replenish_deadline(mut t proc.Thread, now_ns u64) bool {
	if t.sched.dl_period == 0 {
		return true
	}
	if now_ns >= t.sched.dl_period_end {
		t.sched.dl_period_end = now_ns + t.sched.dl_period
		t.sched.dl_abs_deadline = now_ns + t.sched.dl_deadline
		t.sched.dl_budget_ns = t.sched.dl_runtime
	}
	return t.sched.dl_budget_ns > 0
}

// What is left of this period's budget, capped at an ordinary timeslice. The
// cap is not a limit on the turn -- a deadline thread with budget left is not
// preempted, so it simply carries on after the tick -- it is there because the
// clocks, the interval timers and every sleeping thread's wakeup are driven by
// the timer coming round.
fn deadline_timeslice(t &proc.Thread) u64 {
	mut slice := t.sched.dl_budget_ns / 1000
	if slice == 0 {
		slice = 1
	}
	if slice > t.timeslice {
		slice = t.timeslice
	}
	return slice
}

fn realtime_throttled(cpu_number u64, now_ns u64) bool {
	if cpu_number >= max_rt_cpus {
		return false
	}
	start := rt_window_start_ns[cpu_number]
	if start == 0 || now_ns - start >= rt_period_ns {
		return false
	}
	return rt_window_used_ns[cpu_number] >= rt_runtime_ns
}

// Bill the span since this CPU last came through the scheduler to whatever was
// running on it. A deadline thread pays for it out of this period's budget;
// every real-time thread pays it into this CPU's bandwidth window.
fn account_realtime_time(cpu_number u64, current &proc.Thread, now_ns u64) {
	if cpu_number >= max_rt_cpus {
		return
	}

	last := rt_account_last_ns[cpu_number]
	rt_account_last_ns[cpu_number] = now_ns

	if unsafe { current == nil } || last == 0 || now_ns <= last {
		return
	}
	mut t := unsafe { current }
	if !t.sched.is_realtime() {
		return
	}
	span := now_ns - last

	if t.sched.policy == proc.sched_deadline {
		if t.sched.dl_budget_ns <= span {
			t.sched.dl_budget_ns = 0
		} else {
			t.sched.dl_budget_ns -= span
		}
	}

	start := rt_window_start_ns[cpu_number]
	if start == 0 || now_ns - start >= rt_period_ns {
		rt_window_start_ns[cpu_number] = now_ns
		rt_window_used_ns[cpu_number] = span
		return
	}
	rt_window_used_ns[cpu_number] += span
}

// Does the thread the scan came back with take the CPU, or does the one on it
// keep it? Rank decides. A tie goes to the thread already running, unless its
// policy hands the CPU on at the end of a turn, or it has just asked to give
// the rest of its turn away, or both are deadline threads and the waiting one
// has the earlier deadline to meet.
fn should_preempt(mut current proc.Thread, next &proc.Thread, now_ns u64, throttled bool) bool {
	if unsafe { next == nil } {
		return false
	}
	mut candidate := unsafe { next }

	current_rank := runnable_rank(mut current, now_ns, throttled)
	next_rank := runnable_rank(mut candidate, now_ns, throttled)
	if next_rank != current_rank {
		return next_rank > current_rank
	}
	if current.yield_requested {
		return true
	}
	if current_rank == proc.rank_deadline {
		return candidate.sched.dl_abs_deadline < current.sched.dl_abs_deadline
	}
	return !current.sched.runs_to_completion()
}

// A thread whose cgroup is frozen, or has used up its CPU quota for the period,
// stays off the CPU -- but only once it is in userspace. One stopped inside a
// syscall runs on until it returns, so nothing it holds stays held for a whole
// period, or for as long as the group stays frozen. A thread with SIGKILL
// pending, or told to exit, always gets through, so killing a paused or
// throttled container works. `in_kernel` is whether the thread would resume
// in the kernel.
fn cgroup_holds_thread_back(t &proc.Thread, in_kernel bool) bool {
	if unsafe { t.process == nil } || t.process.cgroup_account == unsafe { nil } {
		return false
	}
	if in_kernel && !katomic.load(&t.at_user_boundary) {
		return false
	}
	if katomic.load(&t.must_exit) || katomic.load(&t.pending_signals) & (u64(1) << 8) != 0 {
		return false
	}
	return proc.cgroup_holds_back(t.process, clock_ns())
}

// Called on the way back to userspace from every syscall. A thread whose cgroup
// is frozen, or out of CPU quota, gives the CPU up here and waits until the
// group may run again. The timer alone would rarely stop a thread that spends
// its time in syscalls -- a shell loop of echo and sleep is in userspace for
// microseconds at a time -- so this is where docker pause catches it, and it is
// also the point where a thread holds nothing of the kernel's.
pub fn park_for_cgroup() {
	mut t := proc.current_thread()
	if unsafe { t == nil } || unsafe { t.process == nil }
		|| t.process.cgroup_account == unsafe { nil } {
		return
	}
	mut parked := false
	for {
		if katomic.load(&t.must_exit) || katomic.load(&t.pending_signals) & (u64(1) << 8) != 0 {
			break
		}
		if !proc.cgroup_holds_back(t.process, clock_ns()) {
			break
		}
		katomic.store(mut &t.at_user_boundary, true)
		parked = true
		reschedule()
		katomic.store(mut &t.at_user_boundary, false)
	}
	if parked {
		// reschedule() comes back with interrupts on; the syscall exit expects
		// them off.
		interrupts_off()
	}
}

// Pick a thread for CPU `cpu_number`, which is on memory node `numa_node`,
// with the run-queue lock held. On a machine with more than one memory node
// this runs twice: once accepting only threads already at home on this CPU's
// node, and then accepting anything. A thread therefore tends to keep running
// next to the memory it faulted in, while a node with nothing to do still
// takes work from a busy one rather than idling. `last_index` points to where
// this CPU's last scan stopped, and is moved to where this one stops.
fn pick_next_thread(cpu_number u64, numa_node int, last_index &int) &proc.Thread {
	if numa_multinode {
		local_thread := scan_run_queue(cpu_number, last_index, numa_node)
		if unsafe { local_thread != nil } {
			return local_thread
		}
	}
	return scan_run_queue(cpu_number, last_index, -1)
}

// `want_node` of -1 accepts every thread; otherwise only those whose home node
// matches, plus those no CPU has claimed yet.
//
// A machine where every thread is scheduled by turn takes the first runnable
// thread it finds; one where anything has asked for a policy weighs the whole
// queue instead. The two are the same lap, and the split exists so that the
// ordinary machine goes on paying exactly what it used to.
fn scan_run_queue(cpu_number u64, last_index &int, want_node int) &proc.Thread {
	if proc.scheduling_policies_in_use() {
		return scan_run_queue_ranked(cpu_number, last_index, want_node)
	}
	return scan_run_queue_in_turn(cpu_number, last_index, want_node)
}

// Exactly one lap of the queue, from wherever this CPU last stopped, so the
// order stays round-robin. The lap is counted rather than compared against a
// starting index: the skip cases used to `continue` straight past the
// wrap-around check, so a slot that this CPU could not take and that happened
// to sit at the start index sent the scan round the queue for ever. Nothing was
// skipped before affinity masks and memory nodes existed, which is why it took
// until a pinned thread on another node to find.
fn scan_run_queue_in_turn(cpu_number u64, last_index &int, want_node int) &proc.Thread {
	mut start := *last_index
	if start < 0 || start >= max_running_threads {
		start = 0
	}

	for step := 1; step <= max_running_threads; step++ {
		index := (start + step) % max_running_threads

		mut t := scheduler_running_queue[index]
		if unsafe { t == nil } {
			continue
		}
		if katomic.load(&t.is_dead) {
			continue
		}
		if !may_run_here(t, cpu_number) {
			continue
		}
		if want_node >= 0 && t.numa_node >= 0 && t.numa_node != want_node {
			continue
		}
		if cgroup_parks(t, &t.gpr_state) {
			continue
		}
		if t.l.test_and_acquire() == true {
			unsafe {
				*last_index = index
			}
			return t
		}
	}

	return unsafe { nil }
}

// The same lap, ending at the most urgent thread this CPU may run rather than
// at the first one it can have. Equal ranks keep the round-robin order: the lap
// starts where the last one stopped, and a thread found later has to beat the
// one already in hand rather than tie it. Deadline threads are the exception
// and are ordered by the deadline each of them is trying to meet.
//
// A thread running on another CPU is still in the queue, holding its own lock.
// The lap has to see past those rather than stop at them, so it peeks at each
// lock and only takes the one it has settled on. If another CPU takes that one
// first, it looks again -- and on that pass the lock it lost to is held, and
// skipped like any other.
fn scan_run_queue_ranked(cpu_number u64, last_index &int, want_node int) &proc.Thread {
	now_ns := clock_ns()
	throttled := realtime_throttled(cpu_number, now_ns)

	for attempt := 0; attempt < pick_attempts; attempt++ {
		mut start := *last_index
		if start < 0 || start >= max_running_threads {
			start = 0
		}

		mut best := &proc.Thread(unsafe { nil })
		mut best_index := -1
		mut best_rank := -1
		mut best_deadline := u64(0)

		for step := 1; step <= max_running_threads; step++ {
			index := (start + step) % max_running_threads

			mut t := scheduler_running_queue[index]
			if unsafe { t == nil } {
				continue
			}
			if katomic.load(&t.is_dead) {
				continue
			}
			if !may_run_here(t, cpu_number) {
				continue
			}
			if want_node >= 0 && t.numa_node >= 0 && t.numa_node != want_node {
				continue
			}
			if t.l.is_held() {
				continue
			}
			if cgroup_parks(t, &t.gpr_state) {
				continue
			}
			rank := runnable_rank(mut t, now_ns, throttled)
			if rank < best_rank {
				continue
			}
			if rank == best_rank {
				if rank != proc.rank_deadline || t.sched.dl_abs_deadline >= best_deadline {
					continue
				}
			}
			best = t
			best_index = index
			best_rank = rank
			best_deadline = t.sched.dl_abs_deadline
		}

		if best_index < 0 {
			return unsafe { nil }
		}
		if best.l.test_and_acquire() == true {
			unsafe {
				*last_index = best_index
			}
			return best
		}
	}

	return unsafe { nil }
}

fn effective_timeslice(t &proc.Thread) u64 {
	mut slice := u64(0)

	match t.sched.policy {
		proc.sched_fifo {
			// Nothing here ends a FIFO thread's turn. The timer only has to
			// come round often enough to notice something more urgent becoming
			// runnable, and to keep the clocks moving.
			slice = t.timeslice
		}
		proc.sched_rr {
			// A fixed quantum, and the one sched_rr_get_interval(2) reports.
			// Nice does not scale it: what a real-time thread is entitled to is
			// decided by its priority and by nothing else.
			slice = t.timeslice
		}
		proc.sched_deadline {
			slice = deadline_timeslice(t)
		}
		proc.sched_idle {
			slice = idle_policy_slice_us
		}
		else {
			weight := u64(20 - t.process.nice)
			slice = t.timeslice * weight / 20
		}
	}

	// An ordinary thread gives the CPU back promptly while anything on this
	// machine is scheduled by policy. Lacking a way to interrupt another CPU on
	// demand, the next time it comes through here is the soonest a real-time
	// thread that has just woken can be given the CPU it is sitting on -- so
	// this interval is the machine's worst-case dispatch latency under load.
	if !t.sched.is_special() && proc.scheduling_policies_in_use()
		&& slice > realtime_preempt_slice_us {
		slice = realtime_preempt_slice_us
	}

	if slice == 0 {
		slice = 1
	}
	return slice
}

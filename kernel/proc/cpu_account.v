// SPDX-License-Identifier: GPL-2.0-or-later
module proc

import katomic

pub struct CPUIntervalTimer {
pub mut:
	deadline_ns u64
	interval_ns u64
}

__global (
	cpu_signal_hook voidptr
)

type CPUSignalHook = fn (&Process, int)

// Registered by the signal layer before userspace starts. The process is
// alive while its running thread charges time; no timer retains a raw thread
// pointer or allocates anything on the repeated tick path.
pub fn register_cpu_signal_hook(hook voidptr) {
	cpu_signal_hook = hook
}

fn send_cpu_signals(process &Process, signals u64) {
	if signals == 0 || cpu_signal_hook == unsafe { nil } {
		return
	}
	hook := unsafe { CPUSignalHook(cpu_signal_hook) }
	for signal in [9, 24, 26, 27]! {
		if signals & (u64(1) << (signal - 1)) != 0 {
			hook(process, signal)
		}
	}
}

fn add_cpu_counter(value &u64, span u64) {
	for {
		previous := katomic.load(value)
		if katomic.cas(mut unsafe { value }, previous, previous + span) {
			return
		}
	}
}

// Only called with process.cpu_lock held. Preserving the original period's
// phase avoids drift, and coalesces missed expirations like ordinary signals.
fn expire_cpu_timer(mut timer CPUIntervalTimer, consumed u64) bool {
	if timer.deadline_ns == 0 || consumed < timer.deadline_ns {
		return false
	}
	if timer.interval_ns == 0 {
		timer.deadline_ns = 0
	} else {
		remaining := timer.interval_ns - (consumed - timer.deadline_ns) % timer.interval_ns
		timer.deadline_ns = if consumed > u64(-1) - remaining { u64(-1) } else { consumed + remaining }
	}
	return true
}

fn cpu_signals_locked(mut process Process) u64 {
	mut signals := u64(0)
	if expire_cpu_timer(mut process.cpu_timers[0], process.cpu_user_ns) {
		signals |= u64(1) << 25 // SIGVTALRM
	}
	if expire_cpu_timer(mut process.cpu_timers[1], process.cpu_time_ns) {
		signals |= u64(1) << 26 // SIGPROF
	}
	seconds := process.cpu_time_ns / 1000000000
	limit := process.cpu_limit
	// Linux treats a zero-second CPU limit as one second.
	hard := if limit.max == 0 { u64(1) } else { limit.max }
	soft := if limit.cur == 0 { u64(1) } else { limit.cur }
	if hard != rlim_infinity && seconds >= hard {
		if !process.cpu_kill_sent {
			process.cpu_kill_sent = true
			signals |= u64(1) << 8 // SIGKILL; also wins when soft == hard
		}
	} else if soft != rlim_infinity && seconds >= soft
		&& seconds >= process.cpu_xcpu_next_second {
		process.cpu_xcpu_next_second = seconds + 1
		signals |= u64(1) << 23 // SIGXCPU, once per additional CPU second
	}
	return signals
}

fn charge_cpu_locked(mut t Thread, now_ns u64) {
	started := t.scheduled_at_ns
	if started == 0 || now_ns <= started {
		return
	}
	span := now_ns - started
	t.scheduled_at_ns = now_ns
	t.cpu_time_ns += span
	t.process.cpu_time_ns += span
	if t.cpu_in_kernel {
		t.cpu_system_ns += span
		t.process.cpu_system_ns += span
	} else {
		t.cpu_user_ns += span
		t.process.cpu_user_ns += span
	}
}

pub fn begin_cpu_time(mut t Thread, now_ns u64) {
	if t.process == unsafe { nil } { return }
	t.process.cpu_lock.acquire()
	// Scheduler/cgroup time can use a tick-driven clock. CPU-mode accounting
	// always uses the same hardware clock as syscall and interrupt boundaries.
	t.scheduled_at_ns = cpu_time_now_ns()
	t.cgroup_charged_ns = now_ns
	t.cpu_in_kernel = saved_context_in_kernel(&t)
	t.process.cpu_lock.release()
}

// Charge a running thread on every scheduler tick, including when it keeps
// the CPU. A FIFO thread or lone userspace loop cannot evade timers/limits by
// avoiding context switches. Stop clears the marker before the final switch.
pub fn tick_cpu_time(mut t Thread, _now_ns u64) {
	update_cpu_time(mut t, cpu_time_now_ns(), false, t.cpu_in_kernel, false)
}

pub fn charge_cpu_time(mut t Thread, now_ns u64) {
	charge_cgroup_cpu(mut t, now_ns)
	t.cgroup_charged_ns = 0
	update_cpu_time(mut t, cpu_time_now_ns(), true, t.cpu_in_kernel, false)
}

fn update_cpu_time(mut t Thread, now_ns u64, stop bool, in_kernel bool, change_mode bool) {
	if t.process == unsafe { nil } { return }
	mut process := t.process
	process.cpu_lock.acquire()
	charge_cpu_locked(mut t, now_ns)
	if stop { t.scheduled_at_ns = 0 }
	if change_mode { t.cpu_in_kernel = in_kernel }
	signals := cpu_signals_locked(mut process)
	process.cpu_lock.release()
	// Signal delivery may take the thread-list or run-queue locks. Those
	// locks are never acquired while the accounting lock is held.
	send_cpu_signals(process, signals)
}

pub fn cpu_enter_kernel() {
	mut t := current_thread()
	if t == unsafe { nil } { return }
	update_cpu_time(mut t, cpu_time_now_ns(), false, true, true)
}

pub fn cpu_leave_kernel() {
	mut t := current_thread()
	if t == unsafe { nil } { return }
	update_cpu_time(mut t, cpu_time_now_ns(), false, false, true)
}

pub fn thread_cpu_times(t &Thread, _sampled_ns u64) (u64, u64) {
	now_ns := cpu_time_now_ns()
	mut process := t.process
	process.cpu_lock.acquire()
	mut user := t.cpu_user_ns
	mut system := t.cpu_system_ns
	started := t.scheduled_at_ns
	if started != 0 && now_ns > started {
		if t.cpu_in_kernel { system += now_ns - started } else { user += now_ns - started }
	}
	process.cpu_lock.release()
	return user, system
}

// Snapshot every running sibling, rather than adding only the calling
// thread's unfinished turn. Exited threads remain in the process totals.
fn process_cpu_times_locked(process &Process, now_ns u64) (u64, u64) {
	mut user := process.cpu_user_ns
	mut system := process.cpu_system_ns
	for t in process.threads {
		started := t.scheduled_at_ns
		if started != 0 && now_ns > started {
			if t.cpu_in_kernel { system += now_ns - started } else { user += now_ns - started }
		}
	}
	return user, system
}

pub fn process_cpu_times(process &Process, _sampled_ns u64) (u64, u64) {
	now_ns := cpu_time_now_ns()
	mut p := unsafe { process }
	p.threads_lock.acquire()
	p.cpu_lock.acquire()
	user, system := process_cpu_times_locked(p, now_ns)
	p.cpu_lock.release()
	p.threads_lock.release()
	return user, system
}

pub fn thread_cpu_time(t &Thread, now_ns u64) u64 {
	user, system := thread_cpu_times(t, now_ns)
	return user + system
}

pub fn process_cpu_time(process &Process, now_ns u64) u64 {
	user, system := process_cpu_times(process, now_ns)
	return user + system
}

fn cpu_timer_value(timer CPUIntervalTimer, consumed u64) (u64, u64) {
	remaining := if timer.deadline_ns > consumed { timer.deadline_ns - consumed } else { u64(0) }
	// Keep an armed sub-microsecond remainder distinguishable from disarmed.
	return remaining / 1000 + if remaining % 1000 != 0 { u64(1) } else { u64(0) }, timer.interval_ns / 1000
}

pub fn get_cpu_itimer(process &Process, which int) (u64, u64) {
	mut p := unsafe { process }
	p.threads_lock.acquire()
	p.cpu_lock.acquire()
	user, system := process_cpu_times_locked(p, cpu_time_now_ns())
	value, interval := cpu_timer_value(p.cpu_timers[which - 1], if which == 1 { user } else { user + system })
	p.cpu_lock.release()
	p.threads_lock.release()
	return value, interval
}

pub fn set_cpu_itimer(mut process Process, which int, value_us u64, interval_us u64) (u64, u64) {
	process.threads_lock.acquire()
	process.cpu_lock.acquire()
	user, system := process_cpu_times_locked(&process, cpu_time_now_ns())
	consumed := if which == 1 { user } else { user + system }
	mut timer := unsafe { &process.cpu_timers[which - 1] }
	old_value, old_interval := cpu_timer_value(*timer, consumed)
	// Clamp extremely long requests instead of allowing a wrapped deadline.
	max_us := (u64(-1) - consumed) / 1000
	timer.deadline_ns = if value_us == 0 { u64(0) } else if value_us > max_us { u64(-1) } else { consumed + value_us * 1000 }
	timer.interval_ns = if interval_us > u64(-1) / 1000 { u64(-1) } else { interval_us * 1000 }
	process.cpu_lock.release()
	process.threads_lock.release()
	return old_value, old_interval
}

// Called while rlimits_lock serializes the whole {cur,max} replacement.
pub fn set_cpu_limit(mut process Process, limit RLimit) {
	process.cpu_lock.acquire()
	process.cpu_limit = limit
	process.cpu_xcpu_next_second = if limit.cur == 0 { u64(1) } else { limit.cur }
	process.cpu_kill_sent = false
	process.cpu_lock.release()
}

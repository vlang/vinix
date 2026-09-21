// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
@[has_globals]
module posixtimer

// Linux POSIX timers. Musl implements SIGEV_THREAD in userspace by creating a
// helper thread, asking the kernel for a SIGEV_THREAD_ID timer aimed at that
// thread, and synchronously accepting the notification with rt_sigtimedwait.

import errno
import katomic
import klock
import proc
import sched
import time
import usercopy

const max_posix_timers = 64

const clock_realtime = 0

const clock_monotonic = 1

const clock_boottime = 7

const timer_abstime = 1

const sigev_signal = 0

const sigev_none = 1

const sigev_thread_id = 4

// Musl's SIGEV_THREAD helper ignores wakeups unless siginfo reports SI_TIMER.
pub const si_timer = -2

const itimerspec_size = u64(32)

struct KernelSigEvent {
mut:
	value  u64
	signum int
	notify int
	tid    int
}

struct PosixTimer {
mut:
	in_use bool
	owner  &proc.Process = unsafe { nil }

	clock_id int
	notify   int
	signum   int
	tid      int
	value    u64

	// Deadlines use the monotonic clock internally. Absolute realtime timers
	// are translated when armed, matching the clocks Vinix currently keeps.
	deadline_ns u64
	interval_ns u64

	// Information for the last notification, consumed by rt_sigtimedwait or
	// an asynchronous SA_SIGINFO handler.
	pending_target_tid int
	pending            bool
	overrun            int
}

pub struct SignalInfo {
pub:
	found   bool
	code    int
	value   u64
	overrun int
}

__global (
	posix_timers         [max_posix_timers]PosixTimer
	posix_timers_lock    klock.Lock
	posix_hook_installed = bool(false)
)

fn valid_clock(clock_id int) bool {
	return clock_id == clock_realtime || clock_id == clock_monotonic
		|| clock_id == clock_boottime
}

fn timespec_to_ns(value time.TimeSpec) ?u64 {
	if value.tv_sec < 0 || value.tv_nsec < 0 || value.tv_nsec >= 1000000000 {
		errno.set(errno.einval)
		return none
	}
	seconds := u64(value.tv_sec)
	nanoseconds := u64(value.tv_nsec)
	if seconds > (u64(-1) - nanoseconds) / 1000000000 {
		errno.set(errno.eoverflow)
		return none
	}
	return seconds * 1000000000 + nanoseconds
}

fn clock_now_ns(clock_id int) ?u64 {
	if clock_id == clock_realtime {
		now := time.clock_now(time.clock_type_realtime)?
		return timespec_to_ns(now)
	}
	if clock_id == clock_monotonic || clock_id == clock_boottime {
		return time.monotonic_ns()
	}
	return none
}

fn ns_to_timespec(value u64) time.TimeSpec {
	return time.TimeSpec{
		tv_sec: i64(value / 1000000000)
		tv_nsec: i64(value % 1000000000)
	}
}

fn find_timer(timer_id int, owner &proc.Process) ?&PosixTimer {
	if timer_id < 0 || timer_id >= max_posix_timers {
		errno.set(errno.einval)
		return none
	}
	mut timer := unsafe { &posix_timers[timer_id] }
	if !timer.in_use || timer.owner != owner {
		errno.set(errno.einval)
		return none
	}
	return timer
}

fn remaining(timer &PosixTimer, now_ns u64) u64 {
	if timer.deadline_ns == 0 {
		return 0
	}
	if timer.deadline_ns <= now_ns {
		// The tick has not observed it yet. Linux reports a nonzero value for
		// an armed timer, so expose the smallest representable interval.
		return 1
	}
	return timer.deadline_ns - now_ns
}

fn timer_target(timer &PosixTimer) &proc.Thread {
	if timer.notify == sigev_thread_id {
		target := proc.thread_by_tid(timer.tid)
		if target == unsafe { nil } || target.is_dead || target.process != timer.owner {
			return unsafe { nil }
		}
		return target
	}

	mut owner := timer.owner
	if owner == unsafe { nil } {
		return unsafe { nil }
	}
	owner.threads_lock.acquire()
	mut target := &proc.Thread(unsafe { nil })
	if owner.threads.len > 0 {
		target = owner.threads[0]
	}
	owner.threads_lock.release()
	return target
}

fn add_overrun(current int, amount u64) int {
	if amount >= u64(0x7fffffff) || current > 0x7fffffff - int(amount) {
		return 0x7fffffff
	}
	return current + int(amount)
}

// Called by the common clock tick after monotonic time has advanced.
pub fn tick_posix_timers() {
	if !posix_timers_lock.test_and_acquire() {
		return
	}

	now_ns := time.monotonic_ns()
	for i := 0; i < max_posix_timers; i++ {
		mut timer := unsafe { &posix_timers[i] }
		if !timer.in_use || timer.deadline_ns == 0 || now_ns < timer.deadline_ns {
			continue
		}

		mut expirations := u64(1)
		if timer.interval_ns == 0 {
			timer.deadline_ns = 0
		} else {
			elapsed := now_ns - timer.deadline_ns
			expirations += elapsed / timer.interval_ns
			timer.deadline_ns = now_ns + timer.interval_ns - (elapsed % timer.interval_ns)
		}

		if timer.notify == sigev_none {
			continue
		}

		mut target := timer_target(timer)
		if target == unsafe { nil } {
			continue
		}

		bit := u64(1) << u64(timer.signum - 1)
		if katomic.load(&target.pending_signals) & bit != 0 {
			// Standard signals coalesce. Preserve how many additional timer
			// expirations occurred while the first notification was pending.
			timer.overrun = add_overrun(timer.overrun, expirations)
			target.pending_signal_overruns[timer.signum - 1] = timer.overrun
			continue
		}

		timer.pending = true
		timer.pending_target_tid = target.tid
		timer.overrun = add_overrun(0, expirations - 1)
		target.pending_signal_codes[timer.signum - 1] = si_timer
		target.pending_signal_values[timer.signum - 1] = timer.value
		target.pending_signal_overruns[timer.signum - 1] = timer.overrun
		katomic.bts(mut &target.pending_signals, u8(timer.signum - 1))
		sched.enqueue_thread(target, true)
	}

	posix_timers_lock.release()
}

fn ensure_tick_hook() bool {
	if posix_hook_installed {
		return true
	}
	if !time.register_tick_hook(tick_posix_timers) {
		return false
	}
	posix_hook_installed = true
	return true
}

// timer_create(clockid, sigevent, timerid).
pub fn syscall_timer_create(_ voidptr, clock_id int, event_ptr u64, timer_id_ptr u64) (u64, u64) {
	if !valid_clock(clock_id) {
		return errno.err, errno.einval
	}
	if timer_id_ptr == 0 {
		return errno.err, errno.efault
	}

	mut event := KernelSigEvent{
		signum: 14 // SIGALRM is the Linux default when sigevent is NULL.
		notify: sigev_signal
	}
	if event_ptr != 0 {
		// Linux's kernel sigevent has five meaningful fields here; the rest is
		// padding owned by libc.
		mut raw := [3]u64{}
		if !usercopy.copy_from_user(voidptr(&raw[0]), event_ptr, 20) {
			return errno.err, errno.efault
		}
		event.value = raw[0]
		event.signum = int(u32(raw[1]))
		event.notify = int(u32(raw[1] >> 32))
		event.tid = int(u32(raw[2]))
	}
	if event.notify != sigev_none && event.notify != sigev_signal
		&& event.notify != sigev_thread_id {
		return errno.err, errno.einval
	}
	if event.notify != sigev_none && (event.signum <= 0 || event.signum > 64) {
		return errno.err, errno.einval
	}

	owner := proc.current_thread().process
	if event.notify == sigev_thread_id {
		target := proc.thread_by_tid(event.tid)
		if target == unsafe { nil } || target.is_dead || target.process != owner {
			return errno.err, errno.einval
		}
	}

	posix_timers_lock.acquire()
	defer {
		posix_timers_lock.release()
	}
	if !ensure_tick_hook() {
		return errno.err, errno.eagain
	}

	for i := 0; i < max_posix_timers; i++ {
		mut timer := unsafe { &posix_timers[i] }
		if timer.in_use {
			continue
		}
		unsafe {
			*timer = PosixTimer{
				in_use: true
				owner: owner
				clock_id: clock_id
				notify: event.notify
				signum: event.signum
				tid: event.tid
				value: event.value
			}
		}
		timer_id := u32(i)
		if !usercopy.copy_to_user(timer_id_ptr, voidptr(&timer_id), sizeof(u32)) {
			unsafe {
				*timer = PosixTimer{}
			}
			return errno.err, errno.efault
		}
		return 0, 0
	}

	return errno.err, errno.eagain
}

// timer_settime(timerid, flags, new_value, old_value).
pub fn syscall_timer_settime(_ voidptr, timer_id int, flags int, new_value u64, old_value u64) (u64, u64) {
	if flags & ~timer_abstime != 0 {
		return errno.err, errno.einval
	}
	if new_value == 0 {
		return errno.err, errno.efault
	}

	mut incoming := [2]time.TimeSpec{}
	if !usercopy.copy_from_user(voidptr(&incoming[0]), new_value, itimerspec_size) {
		return errno.err, errno.efault
	}
	interval_ns := timespec_to_ns(incoming[0]) or { return errno.err, errno.get() }
	value_ns := timespec_to_ns(incoming[1]) or { return errno.err, errno.get() }

	owner := proc.current_thread().process
	posix_timers_lock.acquire()
	defer {
		posix_timers_lock.release()
	}
	mut timer := find_timer(timer_id, owner) or { return errno.err, errno.get() }
	now_ns := time.monotonic_ns()

	if old_value != 0 {
		mut previous := [2]time.TimeSpec{}
		previous[0] = ns_to_timespec(timer.interval_ns)
		previous[1] = ns_to_timespec(remaining(timer, now_ns))
		if !usercopy.copy_to_user(old_value, voidptr(&previous[0]), itimerspec_size) {
			return errno.err, errno.efault
		}
	}

	timer.interval_ns = interval_ns
	if value_ns == 0 {
		timer.deadline_ns = 0
		return 0, 0
	}
	if flags & timer_abstime != 0 {
		clock_ns := clock_now_ns(timer.clock_id) or { return errno.err, errno.einval }
		if value_ns <= clock_ns {
			timer.deadline_ns = now_ns
		} else {
			delay := value_ns - clock_ns
			if delay > u64(-1) - now_ns {
				return errno.err, errno.eoverflow
			}
			timer.deadline_ns = now_ns + delay
		}
	} else {
		if value_ns > u64(-1) - now_ns {
			return errno.err, errno.eoverflow
		}
		timer.deadline_ns = now_ns + value_ns
	}
	return 0, 0
}

// timer_gettime(timerid, current_value).
pub fn syscall_timer_gettime(_ voidptr, timer_id int, current_value u64) (u64, u64) {
	if current_value == 0 {
		return errno.err, errno.efault
	}
	owner := proc.current_thread().process
	posix_timers_lock.acquire()
	defer {
		posix_timers_lock.release()
	}
	timer := find_timer(timer_id, owner) or { return errno.err, errno.get() }
	mut current := [2]time.TimeSpec{}
	current[0] = ns_to_timespec(timer.interval_ns)
	current[1] = ns_to_timespec(remaining(timer, time.monotonic_ns()))
	if !usercopy.copy_to_user(current_value, voidptr(&current[0]), itimerspec_size) {
		return errno.err, errno.efault
	}
	return 0, 0
}

pub fn syscall_timer_getoverrun(_ voidptr, timer_id int) (u64, u64) {
	owner := proc.current_thread().process
	posix_timers_lock.acquire()
	defer {
		posix_timers_lock.release()
	}
	timer := find_timer(timer_id, owner) or { return errno.err, errno.get() }
	return u64(timer.overrun), 0
}

pub fn syscall_timer_delete(_ voidptr, timer_id int) (u64, u64) {
	owner := proc.current_thread().process
	posix_timers_lock.acquire()
	defer {
		posix_timers_lock.release()
	}
	mut timer := find_timer(timer_id, owner) or { return errno.err, errno.get() }
	unsafe {
		*timer = PosixTimer{}
	}
	return 0, 0
}

// Signal delivery asks for this after it atomically claims the pending bit.
// Leaving the metadata in place until acknowledge_signal() also means an
// EFAULT while writing siginfo_t can put the signal back without losing it.
pub fn signal_info(thrd &proc.Thread, signum int) SignalInfo {
	if signum <= 0 || signum > 64 {
		return SignalInfo{}
	}
	code := thrd.pending_signal_codes[signum - 1]
	if code != si_timer {
		return SignalInfo{}
	}
	return SignalInfo{
		found: true
		code: code
		value: thrd.pending_signal_values[signum - 1]
		overrun: thrd.pending_signal_overruns[signum - 1]
	}
}

pub fn acknowledge_signal(mut thrd proc.Thread, signum int) {
	if signum <= 0 || signum > 64 {
		return
	}
	was_timer := thrd.pending_signal_codes[signum - 1] == si_timer
	thrd.pending_signal_codes[signum - 1] = 0
	thrd.pending_signal_values[signum - 1] = 0
	thrd.pending_signal_overruns[signum - 1] = 0
	if !was_timer {
		return
	}

	posix_timers_lock.acquire()
	for i := 0; i < max_posix_timers; i++ {
		mut timer := unsafe { &posix_timers[i] }
		if timer.in_use && timer.pending && timer.signum == signum
			&& timer.pending_target_tid == thrd.tid {
			timer.pending = false
			timer.pending_target_tid = 0
			break
		}
	}
	posix_timers_lock.release()
}

// An ordinary tkill/kill for the same signal must not inherit stale SI_TIMER
// metadata. Musl uses such a wakeup when deleting a SIGEV_THREAD timer and
// expects its helper not to invoke the callback for it.
pub fn clear_signal_info(mut thrd proc.Thread, signum int) {
	acknowledge_signal(mut thrd, signum)
}

// POSIX timers are not inherited across fork and do not survive exec. Process
// teardown also removes them before Thread pointers can be recycled.
pub fn remove_process_timers(owner &proc.Process) {
	posix_timers_lock.acquire()
	for i := 0; i < max_posix_timers; i++ {
		mut timer := unsafe { &posix_timers[i] }
		if timer.in_use && timer.owner == owner {
			unsafe {
				*timer = PosixTimer{}
			}
		}
	}
	posix_timers_lock.release()
}

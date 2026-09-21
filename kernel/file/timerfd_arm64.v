// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
@[has_globals]
module file

// timerfd(2): a timer a program can wait on with the same call it waits on
// everything else with. An event loop wants one descriptor set, not a poll plus
// a separate deadline, which is why servers reach for this.

import errno
import event
import event.eventstruct
import klock
import resource
import stat
import time
import usercopy

// timerfd_create flags, which are the same bits open(2) uses.
const tfd_cloexec = 0o2000000

const tfd_nonblock = 0o4000

// timerfd_settime flags.
const tfd_timer_abstime = 1

// A struct itimerspec is two timespecs: the interval, then the first deadline.
const itimerspec_size = u64(32)

// Expiries are noticed on the timer tick, so the number of live timerfds is
// bounded the same way the interval timers are.
const max_timerfds = 32

struct TimerFD {
mut:
	stat     stat.Stat
	refcount int = 1
	l        klock.Lock
	event    eventstruct.Event
	status   int
	can_mmap bool

	clock_id int
	// Both in nanoseconds on the monotonic clock. A deadline of zero means the
	// timer is disarmed; an interval of zero makes it fire once.
	deadline_ns u64
	interval_ns u64
	expirations u64
	nonblocking bool
}

__global (
	timerfd_entries        [max_timerfds]&TimerFD
	timerfd_lock           klock.Lock
	timerfd_hook_installed = bool(false)
)

fn monotonic_ns() u64 {
	now := monotonic_clock
	return u64(now.tv_sec) * 1000000000 + u64(now.tv_nsec)
}

// Called from the scheduler tick, next to the interval timers. A timerfd that
// has come due gets its count raised and its readers woken; a periodic one is
// carried forward past however many periods the tick covered, so a long tick
// does not lose expiries.
pub fn tick_timerfds() {
	if !timerfd_lock.test_and_acquire() {
		return
	}

	now := monotonic_ns()

	for i := 0; i < max_timerfds; i++ {
		mut entry := timerfd_entries[i]
		if entry == unsafe { nil } || entry.deadline_ns == 0 {
			continue
		}
		if now < entry.deadline_ns {
			continue
		}

		if entry.interval_ns == 0 {
			entry.expirations++
			entry.deadline_ns = 0
		} else {
			elapsed := now - entry.deadline_ns
			entry.expirations += 1 + elapsed / entry.interval_ns
			entry.deadline_ns = now + entry.interval_ns - (elapsed % entry.interval_ns)
		}

		entry.status |= pollin
		event.trigger(mut &entry.event, false)
	}

	timerfd_lock.release()
}

fn register_timerfd(mut t TimerFD) bool {
	timerfd_lock.acquire()
	defer {
		timerfd_lock.release()
	}

	for i := 0; i < max_timerfds; i++ {
		if timerfd_entries[i] == unsafe { nil } {
			timerfd_entries[i] = t
			return true
		}
	}
	return false
}

fn (mut this TimerFD) mmap(_handle voidptr, _page u64, _flags int) voidptr {
	return 0
}

// A read hands over the number of times the timer has gone off since the last
// one, and resets the count.
fn (mut this TimerFD) read(_handle voidptr, buf voidptr, _loc u64, count u64) ?i64 {
	if count < sizeof(u64) {
		errno.set(errno.einval)
		return none
	}

	handle := unsafe { &Handle(_handle) }
	nonblocking := this.nonblocking
		|| (handle != unsafe { nil } && handle.flags & resource.o_nonblock != 0)

	for {
		timerfd_lock.acquire()
		got := this.expirations
		if got != 0 {
			this.expirations = 0
			this.status &= ~pollin
		}
		timerfd_lock.release()

		if got != 0 {
			unsafe {
				*&u64(buf) = got
			}
			return i64(sizeof(u64))
		}

		if nonblocking {
			errno.set(errno.ewouldblock)
			return none
		}

		mut events := [&this.event]
		event.await(mut events, true) or {
			unsafe { events.free() }
			errno.set(errno.eintr)
			return none
		}
		unsafe { events.free() }
	}

	return 0
}

fn (mut this TimerFD) write(_handle voidptr, _buf voidptr, _loc u64, _count u64) ?i64 {
	errno.set(errno.einval)
	return none
}

fn (mut this TimerFD) ioctl(handle voidptr, request u64, argp voidptr) ?int {
	return resource.default_ioctl(handle, request, argp)
}

fn (mut this TimerFD) unref(_handle voidptr) ? {
	this.refcount--
	if this.refcount > 0 {
		return
	}

	// The tick walks this table, so a closed timer has to leave it.
	timerfd_lock.acquire()
	for i := 0; i < max_timerfds; i++ {
		if timerfd_entries[i] == unsafe { this } {
			timerfd_entries[i] = unsafe { nil }
			break
		}
	}
	timerfd_lock.release()
}

fn (mut this TimerFD) link(_handle voidptr) ? {
	errno.set(errno.einval)
	return none
}

fn (mut this TimerFD) unlink(_handle voidptr) ? {
	errno.set(errno.einval)
	return none
}

fn (mut this TimerFD) grow(_handle voidptr, _new_size u64) ? {
	errno.set(errno.einval)
	return none
}

fn timerfd_from_fd(fdnum int) ?(&FD, &TimerFD) {
	mut fd := fd_from_fdnum(unsafe { nil }, fdnum)?

	mut res := fd.handle.resource
	if mut res is TimerFD {
		return fd, res
	}

	fd.unref()
	errno.set(errno.einval)
	return none
}

// Only the clocks this kernel keeps, and only the ones a timerfd can sensibly
// count against.
fn valid_timerfd_clock(clock_id int) bool {
	// CLOCK_REALTIME, CLOCK_MONOTONIC, CLOCK_BOOTTIME.
	return clock_id == 0 || clock_id == 1 || clock_id == 7
}

pub fn syscall_timerfd_create(_ voidptr, clock_id int, flags int) (u64, u64) {
	if !valid_timerfd_clock(clock_id) {
		return errno.err, errno.einval
	}
	if flags & ~(tfd_cloexec | tfd_nonblock) != 0 {
		return errno.err, errno.einval
	}

	// Registered on first use, so there is no init ordering to get right and
	// nothing to pay on a system that never creates one.
	if !timerfd_hook_installed {
		timerfd_hook_installed = true
		time.register_tick_hook(tick_timerfds)
	}

	mut timer := &TimerFD{
		clock_id:    clock_id
		nonblocking: flags & tfd_nonblock != 0
	}
	timer.stat.mode = stat.ifchr | 0o600
	timer.stat.blksize = 512

	if !register_timerfd(mut timer) {
		return errno.err, errno.emfile
	}

	mut res := &resource.Resource(unsafe { timer })

	mut open_flags := resource.o_rdwr
	if flags & tfd_cloexec != 0 {
		open_flags |= resource.o_cloexec
	}
	if flags & tfd_nonblock != 0 {
		open_flags |= resource.o_nonblock
	}

	fdnum := fdnum_create_from_resource(unsafe { nil }, mut res, open_flags, 0, false) or {
		return errno.err, errno.get()
	}

	return u64(fdnum), 0
}

fn timespec_to_ns(value time.TimeSpec) u64 {
	return u64(value.tv_sec) * 1000000000 + u64(value.tv_nsec)
}

fn ns_to_timespec(value u64) time.TimeSpec {
	return time.TimeSpec{
		tv_sec:  i64(value / 1000000000)
		tv_nsec: i64(value % 1000000000)
	}
}

// What is left to run and the interval, which is what gettime reports and what
// settime hands back as the old value.
fn (this &TimerFD) remaining() (u64, u64) {
	if this.deadline_ns == 0 {
		return 0, this.interval_ns
	}
	now := monotonic_ns()
	if this.deadline_ns <= now {
		// Due but not yet noticed by the tick. Linux never reports zero for an
		// armed timer, so report the smallest step instead.
		return 1, this.interval_ns
	}
	return this.deadline_ns - now, this.interval_ns
}

pub fn syscall_timerfd_settime(_ voidptr, fdnum int, flags int, new_value u64, old_value u64) (u64, u64) {
	if flags & ~tfd_timer_abstime != 0 {
		return errno.err, errno.einval
	}
	if new_value == 0 {
		return errno.err, errno.efault
	}

	mut fd, mut timer := timerfd_from_fd(fdnum) or { return errno.err, errno.get() }
	defer {
		fd.unref()
	}

	mut incoming := [2]time.TimeSpec{}
	if !usercopy.copy_from_user(voidptr(&incoming[0]), new_value, itimerspec_size) {
		return errno.err, errno.efault
	}

	interval := incoming[0]
	value := incoming[1]

	if interval.tv_nsec < 0 || interval.tv_nsec >= 1000000000 || interval.tv_sec < 0
		|| value.tv_nsec < 0 || value.tv_nsec >= 1000000000 || value.tv_sec < 0 {
		return errno.err, errno.einval
	}

	if old_value != 0 {
		left, period := timer.remaining()
		mut previous := [2]time.TimeSpec{}
		previous[0] = ns_to_timespec(period)
		previous[1] = ns_to_timespec(left)
		if !usercopy.copy_to_user(old_value, voidptr(&previous[0]), itimerspec_size) {
			return errno.err, errno.efault
		}
	}

	timerfd_lock.acquire()
	defer {
		timerfd_lock.release()
	}

	wanted := timespec_to_ns(value)

	if wanted == 0 {
		// A zero value disarms, whatever the interval says.
		timer.deadline_ns = 0
		timer.interval_ns = 0
		timer.expirations = 0
		timer.status &= ~pollin
		return 0, 0
	}

	timer.interval_ns = timespec_to_ns(interval)
	timer.expirations = 0
	timer.status &= ~pollin

	if flags & tfd_timer_abstime != 0 {
		// An absolute deadline is on the timer's own clock. Both clocks advance
		// together here, so the monotonic reading is the one to keep.
		now_wall := if timer.clock_id == 0 { timespec_to_ns(realtime_clock) } else { monotonic_ns() }
		if wanted <= now_wall {
			// Already past: it fires on the next tick.
			timer.deadline_ns = monotonic_ns()
		} else {
			timer.deadline_ns = monotonic_ns() + (wanted - now_wall)
		}
	} else {
		timer.deadline_ns = monotonic_ns() + wanted
	}

	return 0, 0
}

pub fn syscall_timerfd_gettime(_ voidptr, fdnum int, curr_value u64) (u64, u64) {
	if curr_value == 0 {
		return errno.err, errno.efault
	}

	mut fd, mut timer := timerfd_from_fd(fdnum) or { return errno.err, errno.get() }
	defer {
		fd.unref()
	}

	left, period := timer.remaining()

	mut out := [2]time.TimeSpec{}
	out[0] = ns_to_timespec(period)
	out[1] = ns_to_timespec(left)

	if !usercopy.copy_to_user(curr_value, voidptr(&out[0]), itimerspec_size) {
		return errno.err, errno.efault
	}

	return 0, 0
}

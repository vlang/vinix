// SPDX-License-Identifier: GPL-2.0-or-later
module table

import errno
import event
import klock
import kprint
import proc
import time
import usercopy

// syslog(2), the call behind klogctl() and busybox dmesg, over the kernel's
// retained output (kprint.bootlog). Linux 6.12 as distributions build it,
// with dmesg_restrict: every action needs CAP_SYSLOG or CAP_SYS_ADMIN in the
// initial user namespace, checked before the action itself. A record is one
// complete line, given as `<6>` and the line: Vinix's messages carry neither
// a level nor a timestamp. /proc/bootlog remains readable as before.
const cap_syslog = 34
const syslog_close = 0
const syslog_open = 1
const syslog_read = 2
const syslog_read_all = 3
const syslog_read_clear = 4
const syslog_clear = 5
const syslog_console_off = 6
const syslog_console_on = 7
const syslog_console_level = 8
const syslog_size_unread = 9
const syslog_size_buffer = 10
const syslog_prefix = c'<6>'
const syslog_prefix_len = u64(3)

__global (
	syslog_lock klock.Lock
	// Where READ continues, and how much of that record it already returned.
	syslog_read_next    u64
	syslog_read_partial u64
	// READ_ALL starts here; CLEAR moves it to the end.
	syslog_clear_from u64
	// The console level actions 6-8 set. Vinix's messages have no level, so
	// it filters nothing.
	syslog_loglevel       = 7
	syslog_saved_loglevel = -1
)

// A copy of the retained log: positions are offsets among every byte logged.
struct SyslogView {
mut:
	data   &u8 = unsafe { nil }
	length int
	base   u64
}

fn syslog_capture(mut view SyslogView) bool {
	view.data = unsafe { &u8(malloc(kprint.bootlog_capacity)) }
	if view.data == unsafe { nil } { return false }
	view.length, view.base = kprint.bootlog_capture(voidptr(view.data))
	return true
}

fn syslog_release(view &SyslogView) {
	if view.data != unsafe { nil } { unsafe { free(view.data) } }
}

fn (view &SyslogView) end() u64 {
	return view.base + u64(view.length)
}

// The first whole line at or after `position`. Retained data that no longer
// starts the log begins mid-line; that fragment is skipped.
fn (view &SyslogView) line_start(position u64) u64 {
	if position >= view.base { return position }
	if view.base == 0 { return 0 }
	for i in 0 .. view.length {
		if unsafe { view.data[i] } == `\n` { return view.base + u64(i) + 1 }
	}
	return view.end()
}

// Where the complete line at `position` ends, after its newline; 0 if the line
// is not complete yet.
fn (view &SyslogView) line_end(position u64) u64 {
	for offset := position - view.base; offset < u64(view.length); offset++ {
		if unsafe { view.data[offset] } == `\n` { return view.base + offset + 1 }
	}
	return 0
}

fn syslog_record_size(start u64, end u64) u64 {
	return syslog_prefix_len + end - start
}

// Copy `count` bytes of the record [start, end) to `destination`, starting
// `skip` bytes into it.
fn (view &SyslogView) copy_record(start u64, end u64, skip u64, count u64, destination u64) bool {
	mut done := u64(0)
	if skip < syslog_prefix_len {
		part := if syslog_prefix_len - skip < count { syslog_prefix_len - skip } else { count }
		if !usercopy.copy_to_user(destination, unsafe { voidptr(u64(syslog_prefix) + skip) }, part) {
			return false
		}
		done = part
	}
	if done < count {
		from := start + skip + done - syslog_prefix_len
		if !usercopy.copy_to_user(destination + done, unsafe { voidptr(u64(view.data) + from - view.base) },
			count - done) {
			return false
		}
	}
	return true
}

fn syslog_permitted() bool {
	process := proc.current_thread().process
	return proc.is_initial_namespace(process.ns.user)
		&& (proc.has_capability(process, cap_syslog) || proc.has_capability(process, proc.cap_sys_admin))
}

// The newest whole records after the clear point that fit in `length`.
fn syslog_read_all(buffer u64, length i64, clear bool) (u64, u64) {
	if buffer == 0 || length < 0 { return errno.err, errno.einval }
	if length == 0 { return 0, 0 }
	mut view := SyslogView{}
	if !syslog_capture(mut view) { return errno.err, errno.enomem }
	defer { syslog_release(&view) }
	syslog_lock.acquire()
	from := syslog_clear_from
	syslog_lock.release()
	mut first := view.line_start(from)
	mut total := u64(0)
	mut last := first
	for {
		end := view.line_end(last)
		if end == 0 { break }
		total += syslog_record_size(last, end)
		last = end
	}
	for total > u64(length) {
		end := view.line_end(first)
		total -= syslog_record_size(first, end)
		first = end
	}
	mut written := u64(0)
	for position := first; position < last; {
		end := view.line_end(position)
		size := syslog_record_size(position, end)
		if !view.copy_record(position, end, 0, size, buffer + written) {
			return errno.err, errno.efault
		}
		written += size
		position = end
	}
	if clear {
		syslog_lock.acquire()
		if syslog_clear_from < last { syslog_clear_from = last }
		syslog_lock.release()
	}
	return written, 0
}

// Unread records, as many whole ones as fit; a record that does not fit is
// returned in part only when it comes first, and READ continues inside it
// next time. Waits until at least one whole line is there.
fn syslog_read_records(buffer u64, length i64) (u64, u64) {
	if buffer == 0 || length < 0 { return errno.err, errno.einval }
	if length == 0 { return 0, 0 }
	for {
		mut view := SyslogView{}
		if !syslog_capture(mut view) { return errno.err, errno.enomem }
		syslog_lock.acquire()
		next := syslog_read_next
		partial := syslog_read_partial
		syslog_lock.release()
		mut start := view.line_start(next)
		// Text that wrapped away under the reader takes its partial with it.
		mut skip := if start == next { partial } else { u64(0) }
		mut copied := u64(0)
		mut new_next := start
		mut new_partial := u64(0)
		for start < view.end() {
			end := view.line_end(start)
			if end == 0 { break }
			size := syslog_record_size(start, end) - skip
			room := u64(length) - copied
			count := if size <= room { size } else if copied == 0 { room } else { u64(0) }
			if count == 0 { break }
			if !view.copy_record(start, end, skip, count, buffer + copied) {
				syslog_release(&view)
				return errno.err, errno.efault
			}
			copied += count
			if count < size {
				new_next = start
				new_partial = skip + count
				break
			}
			start = end
			new_next = end
			skip = 0
		}
		syslog_release(&view)
		if copied != 0 {
			syslog_lock.acquire()
			// Another reader took these records meanwhile: read again.
			if syslog_read_next != next || syslog_read_partial != partial {
				syslog_lock.release()
				continue
			}
			syslog_read_next = new_next
			syslog_read_partial = new_partial
			syslog_lock.release()
			return copied, 0
		}
		// Nothing complete to read: sleep a little, as interruptibly as Linux.
		mut timer := time.new_coalesced_timer(time.TimeSpec{
			tv_sec:  0
			tv_nsec: 100000000
		}, proc.timer_slack())
		event.await_one(mut timer.event, true) or {
			timer.disarm()
			unsafe { free(timer) }
			return errno.err, proc.interrupted_errno
		}
		timer.disarm()
		unsafe { free(timer) }
	}
	return errno.err, errno.einval
}

fn syslog_unread() (u64, u64) {
	mut view := SyslogView{}
	if !syslog_capture(mut view) { return errno.err, errno.enomem }
	defer { syslog_release(&view) }
	syslog_lock.acquire()
	next := syslog_read_next
	partial := syslog_read_partial
	syslog_lock.release()
	start := view.line_start(next)
	mut total := u64(0)
	mut position := start
	for position < view.end() {
		end := view.line_end(position)
		if end == 0 { break }
		total += syslog_record_size(position, end)
		position = end
	}
	if start == next && total >= partial { total -= partial }
	return total, 0
}

// The end of the last complete line.
fn syslog_clear_point() ?u64 {
	mut view := SyslogView{}
	if !syslog_capture(mut view) { return none }
	defer { syslog_release(&view) }
	mut position := view.line_start(0)
	for position < view.end() {
		end := view.line_end(position)
		if end == 0 { break }
		position = end
	}
	return position
}

pub fn syscall_syslog(_ voidptr, type_word u64, buffer u64, length_word u64) (u64, u64) {
	if !syslog_permitted() { return errno.err, errno.eperm }
	kind := int(i32(u32(type_word)))
	length := i64(i32(u32(length_word)))
	match kind {
		syslog_close, syslog_open {
			return 0, 0
		}
		syslog_read {
			return syslog_read_records(buffer, length)
		}
		syslog_read_all, syslog_read_clear {
			return syslog_read_all(buffer, length, kind == syslog_read_clear)
		}
		syslog_clear {
			point := syslog_clear_point() or { return errno.err, errno.enomem }
			syslog_lock.acquire()
			if syslog_clear_from < point { syslog_clear_from = point }
			syslog_lock.release()
			return 0, 0
		}
		syslog_console_off {
			syslog_lock.acquire()
			if syslog_saved_loglevel == -1 {
				syslog_saved_loglevel = syslog_loglevel
			}
			syslog_loglevel = 1
			syslog_lock.release()
			return 0, 0
		}
		syslog_console_on {
			syslog_lock.acquire()
			if syslog_saved_loglevel != -1 {
				syslog_loglevel = syslog_saved_loglevel
				syslog_saved_loglevel = -1
			}
			syslog_lock.release()
			return 0, 0
		}
		syslog_console_level {
			if length < 1 || length > 8 { return errno.err, errno.einval }
			syslog_lock.acquire()
			syslog_loglevel = int(length)
			syslog_saved_loglevel = -1
			syslog_lock.release()
			return 0, 0
		}
		syslog_size_unread {
			return syslog_unread()
		}
		syslog_size_buffer {
			return u64(kprint.bootlog_capacity), 0
		}
		else {
			return errno.err, errno.einval
		}
	}
}

// restart_syscall(2). Vinix restarts an interrupted call by running it again,
// so no restart block is ever left behind: Linux then answers EINTR.
pub fn syscall_restart_syscall(_ voidptr) (u64, u64) {
	return errno.err, errno.eintr
}

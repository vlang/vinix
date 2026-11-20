// SPDX-License-Identifier: GPL-2.0-or-later
// syslog(2) and restart_syscall(2): buffer size, whole `<level>` records for
// READ_ALL, one consumed record (or part) per READ, unread counts, CLEAR,
// console levels, argument errors, dmesg_restrict refusals for UID 1000, and
// EINTR without a restart block. Log text differs between systems, so the
// checks are on records, sizes and positions.
// The same ELF runs as Vinix's init and, given --reference, under Linux.
module syslogfixture

#include <alloca.h>
#include <errno.h>
#include <grp.h>
#include <stdio.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

fn C.syscall(isize, ...) isize
fn C.__errno_location() &i32
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.pause() i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C._exit(i32)
fn C.alloca(usize) voidptr
fn C.strcmp(&char, &char) i32
fn C.setgroups(usize, voidptr) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32

struct State {
mut:
	checks   int
	failures int
}

struct Result {
	value isize
	err   int
}

fn klog(kind i64, buffer voidptr, length i64) Result {
	unsafe {
		errno_ptr := C.__errno_location()
		*errno_ptr = 0
		value := C.syscall(isize(C.SYS_syslog), kind, buffer, length)
		return Result{value, if value < 0 { *errno_ptr } else { 0 }}
	}
}

fn check(mut s State, label &char, ok bool, got Result) {
	s.checks++
	if !ok {
		s.failures++
		C.printf(c'LINUX SYSLOG FAIL: %s value=%ld errno=%d\n', label, got.value, got.err)
	}
}

fn works(mut s State, label &char, got Result, want isize) {
	check(mut s, label, got.err == 0 && got.value == want, got)
}

fn fails(mut s State, label &char, got Result, err int) {
	check(mut s, label, got.value == -1 && got.err == err, got)
}

// Whether `length` bytes are whole records: `<digit>` then text up to a newline.
fn whole_records(text &u8, length isize) bool {
	unsafe {
		mut at := isize(0)
		for at < length {
			if length - at < 4 || text[at] != `<` || text[at + 1] < `0` || text[at + 1] > `9`
				|| text[at + 2] != `>` { return false }
			for at < length && text[at] != `\n` { at++ }
			if at == length { return false }
			at++
		}
		return true
	}
}

fn privileged(mut s State) {
	unsafe {
		buffer := &u8(C.alloca(1 << 20))
		size := klog(10, nil, 0)
		check(mut s, c'buffer size', size.value >= 4096 && size.value & (size.value - 1) == 0, size)
		works(mut s, c'close', klog(0, nil, 0), 0)
		works(mut s, c'open', klog(1, nil, 0), 0)
		all := klog(3, buffer, 1 << 20)
		check(mut s, c'read all', all.value > 0 && whole_records(buffer, all.value), all)
		check(mut s, c'read all within buffer', all.value <= size.value + size.value / 2, all)
		small := klog(3, buffer, 100)
		check(mut s, c'newest records', small.value >= 0 && small.value <= 100
			&& whole_records(buffer, small.value), small)
		works(mut s, c'read all zero', klog(3, buffer, 0), 0)
		fails(mut s, c'read all null', klog(3, nil, 10), C.EINVAL)
		fails(mut s, c'read all negative', klog(3, buffer, -1), C.EINVAL)
		fails(mut s, c'read all length word', klog(3, buffer, i64(0x1_8000_0000)), C.EINVAL)
		// No record fits in three bytes, so nothing is copied to the bad address.
		works(mut s, c'nothing fits', klog(3, voidptr(1), 3), 0)
		fails(mut s, c'bad buffer', klog(3, voidptr(1), 1 << 20), C.EFAULT)
		for kind in [i64(11), -1, 0x7fffffff]! {
			fails(mut s, c'unknown action', klog(kind, nil, 0), C.EINVAL)
		}
		fails(mut s, c'console level zero', klog(8, nil, 0), C.EINVAL)
		fails(mut s, c'console level nine', klog(8, nil, 9), C.EINVAL)
		works(mut s, c'console level', klog(8, nil, 4), 0)
		works(mut s, c'console level one', klog(8, nil, 1), 0)
		works(mut s, c'console off', klog(6, nil, 0), 0)
		works(mut s, c'console on', klog(7, nil, 0), 0)
		// READ consumes: a part of a record first, then the rest of it.
		unread := klog(9, nil, 0)
		check(mut s, c'unread', unread.value > 2, unread)
		works(mut s, c'read zero', klog(2, buffer, 0), 0)
		fails(mut s, c'read null', klog(2, nil, 10), C.EINVAL)
		part := klog(2, buffer, 2)
		check(mut s, c'read part', part.value == 2 && buffer[0] == `<`, part)
		works(mut s, c'unread after part', klog(9, nil, 0), unread.value - 2)
		// Then as many whole records as fit: the rest of that one and every
		// other unread record.
		rest := klog(2, buffer, 1 << 20)
		mut first_end := isize(0)
		for first_end < rest.value && buffer[first_end] != `\n` { first_end++ }
		check(mut s, c'rest of record', rest.value > 0 && buffer[0] != `<` && first_end < rest.value
			&& whole_records(&u8(u64(buffer) + u64(first_end) + 1), rest.value - first_end - 1), rest)
		check(mut s, c'read everything unread', rest.value == unread.value - 2, rest)
		left := klog(9, nil, 0)
		works(mut s, c'nothing unread', left, 0)
		// CLEAR hides records from READ_ALL but not from READ.
		works(mut s, c'clear', klog(5, nil, 0), 0)
		works(mut s, c'read all after clear', klog(3, buffer, 1 << 20), 0)
		works(mut s, c'unread after clear', klog(9, nil, 0), left.value)
		works(mut s, c'read clear', klog(4, buffer, 1 << 20), 0)
	}
}

fn unprivileged(mut s State) {
	unsafe {
		child := C.fork()
		if child == 0 {
			C.setgroups(0, nil)
			C.setgid(1000)
			C.setuid(1000)
			buffer := C.alloca(256)
			mut local := State{}
			// Permission comes before everything, the action itself included.
			for kind in [i64(10), 3, 9, 2, 5, 0, 1, 8, 11, -1]! {
				fails(mut local, c'unprivileged', klog(kind, buffer, 4), C.EPERM)
			}
			C.printf(c'LINUX SYSLOG CHILD: checks=%d failures=%d\n', local.checks, local.failures)
			C.fflush(nil)
			C._exit(if local.failures == 0 { 0 } else { 1 })
		}
		mut status := i32(0)
		C.waitpid(child, &status, 0)
		check(mut s, c'unprivileged child', status == 0, Result{isize(status), 0})
	}
}

@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		reference := argc > 1 && C.strcmp(argv[1], c'--reference') == 0
		mut s := State{}
		restart := C.syscall(isize(C.SYS_restart_syscall))
		check(mut s, c'restart without block', restart == -1 && *C.__errno_location() == C.EINTR,
			Result{restart, *C.__errno_location()})
		privileged(mut s)
		unprivileged(mut s)
		C.printf(c'LINUX SYSLOG SUMMARY: checks=%d failures=%d\n', s.checks, s.failures)
		if s.failures == 0 {
			C.puts(if reference { c'LINUX SYSLOG REFERENCE: PASS' } else { c'LINUX SYSLOG: PASS' })
		}
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}

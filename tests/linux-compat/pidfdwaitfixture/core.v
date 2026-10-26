// SPDX-License-Identifier: GPL-2.0-or-later
module pidfdwaitfixture

#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

@[typedef]
struct C.siginfo_t {
mut:
	si_signo  i32
	si_errno  i32
	si_code   i32
	si_pid    i32
	si_uid    u32
	si_status i32
}

@[typedef]
struct C.pthread_t {}

struct Result {
	ret  isize
	code i32
}

struct Child {
	pid  i32
	door i32
	uid  u32
}

struct Counts {
mut:
	calls    [20]i32
	failures [20]i32
}

struct Waiter {
	fd    i32
	pid   i32
	plain bool
mut:
	tid    i32
	done   i32
	result Result
	info   C.siginfo_t
	status i32
}

fn C.__errno_location() &i32
fn C.syscall(isize, ...) isize
fn C.getpid() i32
fn C.getuid() u32
fn C.pipe2(&i32, i32) i32
fn C.read(i32, voidptr, usize) isize
fn C.write(i32, voidptr, usize) isize
fn C.open(&char, i32, ...) i32
fn C.close(i32) i32
fn C.dup(i32) i32
fn C.fork() i32
fn C.waitid(i32, u32, &C.siginfo_t, i32) i32
fn C._exit(i32)
fn C.alarm(u32) u32
fn C.usleep(u32) i32
fn C.pause() i32
fn C.strcmp(&char, &char) i32
fn C.strstr(&char, &char) &char
fn C.snprintf(&char, usize, &char, ...) i32
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.memset(voidptr, i32, usize) voidptr
fn C.pthread_create(&C.pthread_t, voidptr, fn (voidptr) voidptr, voidptr) i32
fn C.pthread_join(C.pthread_t, voidptr) i32
fn C.__atomic_store_n(&i32, i32, i32)
fn C.__atomic_load_n(&i32, i32) i32

fn fatal(stage i32) {
	unsafe {
		C.printf(c'LINUX PIDFDWAIT FAIL: setup stage=%d errno=%d\n', stage, *C.__errno_location())
		C.fflush(nil)
		C._exit(1)
	}
}

// Forms 2..6 poison only the upper word of each int syscall argument.
fn word(value i32, form i32) u64 {
	if form == 0 { return u64(u32(value)) }
	if form == 1 || form == 7 { return u64(i64(value)) }
	if form == 2 { return u64(u32(value)) | 0x0000000100000000 }
	if form == 3 { return u64(u32(value)) | 0x1234567800000000 }
	if form == 4 { return u64(u32(value)) | 0x8000000000000000 }
	if form == 5 { return u64(u32(value)) | 0x7fffffff00000000 }
	return u64(u32(value)) | 0xffffffff00000000
}

fn wait_id(which i32, fd i32, options i32, form i32, info voidptr, usage voidptr) Result {
	unsafe {
		slot := C.__errno_location()
		*slot = 0
		ret := if form == 7 && usage == nil {
			isize(C.waitid(which, u32(fd), &C.siginfo_t(info), options))
		} else {
			C.syscall(isize(C.SYS_waitid), word(which, form), word(fd, form), info, word(options, form), usage)
		}
		return Result{ret, *slot}
	}
}

fn wait_fd(fd i32, options i32, form i32, info voidptr) Result {
	return wait_id(3, fd, options, form, info, unsafe { nil })
}

fn expected(actual Result, code i32) bool {
	return actual.ret == if code == 0 { isize(0) } else { isize(-1) } && actual.code == code
}

fn empty(info &C.siginfo_t) bool {
	return info.si_signo == 0 && info.si_errno == 0 && info.si_code == 0 && info.si_pid == 0 && info.si_uid == 0 && info.si_status == 0
}

fn matches(info &C.siginfo_t, child Child) bool {
	return info.si_signo == C.SIGCHLD && info.si_errno == 0 && info.si_code == C.CLD_EXITED && info.si_pid == child.pid && info.si_uid == child.uid && info.si_status == 37
}

fn record(counts &Counts, kind int, good bool, actual Result) {
	unsafe {
		counts.calls[kind]++
		if !good {
			counts.failures[kind]++
			C.printf(c'LINUX PIDFDWAIT DETAIL: kind=%d call=%d actual=%ld/%d\n', kind, counts.calls[kind], actual.ret, actual.code)
			C.fflush(nil)
		}
	}
}

fn open_pid(pid i32, flags i32) i32 {
	unsafe {
		fd := i32(C.syscall(isize(434), isize(pid), isize(flags)))
		if fd < 0 { fatal(1) }
		return fd
	}
}

fn launch() Child {
	unsafe {
		mut door := [i32(-1), i32(-1)]!
		if C.pipe2(&door[0], C.O_CLOEXEC) != 0 { fatal(2) }
		uid := C.getuid()
		pid := C.fork()
		if pid < 0 { fatal(3) }
		if pid == 0 {
			C.close(door[1])
			mut token := u8(0)
			good := C.read(door[0], &token, 1) == 1 && token == `X`
			C.close(door[0])
			C._exit(if good { 37 } else { 1 })
		}
		C.close(door[0])
		return Child{pid, door[1], uid}
	}
}

fn release(child Child) {
	unsafe {
		token := u8(`X`)
		if C.write(child.door, &token, 1) != 1 || C.close(child.door) != 0 { fatal(4) }
	}
}

// P_PID is an independent readiness barrier; it never consumes the event.
fn observe(child Child) {
	unsafe {
		mut info := C.siginfo_t{}
		actual := wait_id(C.P_PID, child.pid, C.WEXITED | C.WNOWAIT, 0, &info, nil)
		if !expected(actual, 0) || !matches(&info, child) { fatal(5) }
	}
}

fn worker(argument voidptr) voidptr {
	unsafe {
		request := &Waiter(argument)
		tid := i32(C.syscall(isize(C.SYS_gettid)))
		// Nothing that can sleep occurs between publication and the wait syscall.
		C.__atomic_store_n(&request.tid, tid, 5)
		if request.plain {
			slot := C.__errno_location()
			*slot = 0
			ret := C.syscall(isize(C.SYS_wait4), isize(request.pid), &request.status, isize(0), nil)
			request.result = Result{ret, *slot}
		} else {
			request.result = wait_fd(request.fd, C.WEXITED, 0, &request.info)
		}
		C.__atomic_store_n(&request.done, 1, 5)
		return nil
	}
}

// Reading the worker's sleeping state proves the kernel wait has started.
// A ready notification followed by a fixed delay cannot prove this ordering.
fn blocked(request &Waiter) bool {
	unsafe {
		for _ in 0 .. 5000 {
			tid := C.__atomic_load_n(&request.tid, 5)
			if C.__atomic_load_n(&request.done, 5) != 0 { return false }
			if tid > 0 {
				mut path := [128]char{}
				C.snprintf(&path[0], 128, c'/proc/self/task/%d/status', tid)
				fd := C.open(&path[0], C.O_RDONLY | C.O_CLOEXEC)
				if fd < 0 { return false }
				mut data := [2048]char{}
				size := C.read(fd, &data[0], 2047)
				C.close(fd)
				if size <= 0 { return false }
				if C.strstr(&data[0], c'State:\tS') != nil && C.__atomic_load_n(&request.done, 5) == 0 {
					return true
				}
			}
			C.usleep(1000)
		}
		return false
	}
}

fn races(counts &Counts) {
	unsafe {
		for _ in 0 .. 8 {
			child := launch()
			fd := open_pid(child.pid, 0)
			duplicate := C.dup(fd)
			if duplicate < 0 { fatal(6) }
			mut request := Waiter{ fd: fd }
			mut waiter_thread := C.pthread_t{}
			if C.pthread_create(&waiter_thread, nil, worker, &request) != 0 || !blocked(&request) {
				fatal(7)
			}
			if C.close(fd) != 0 { fatal(8) }
			release(child)
			if C.pthread_join(waiter_thread, nil) != 0 { fatal(9) }
			record(counts, 17, expected(request.result, 0) && matches(&request.info, child), request.result)
			mut info := C.siginfo_t{}
			actual := wait_fd(duplicate, C.WEXITED | C.WNOHANG, 0, &info)
			record(counts, 17, expected(actual, C.ECHILD) && empty(&info), actual)
			C.close(duplicate)
		}
		for _ in 0 .. 8 {
			child := launch()
			fd := open_pid(child.pid, 0)
			mut first := Waiter{ fd: fd }
			mut second := Waiter{ pid: child.pid, plain: true }
			mut a := C.pthread_t{}
			mut b := C.pthread_t{}
			if C.pthread_create(&a, nil, worker, &first) != 0 || !blocked(&first) || C.pthread_create(&b, nil, worker, &second) != 0 || !blocked(&second) {
				fatal(10)
			}
			if C.close(fd) != 0 { fatal(11) }
			release(child)
			if C.pthread_join(a, nil) != 0 || C.pthread_join(b, nil) != 0 { fatal(12) }
			pidfd_won := expected(first.result, 0) && matches(&first.info, child)
			wait4_won := second.result.ret == child.pid && second.result.code == 0 && second.status == 37 << 8
			record(counts, 18, (pidfd_won && expected(second.result, C.ECHILD)) || (wait4_won && expected(first.result, C.ECHILD) && empty(&first.info)), first.result)
			record(counts, 18, pidfd_won != wait4_won, second.result)
		}
		child := launch()
		mut status := i32(0x12345678)
		slot := C.__errno_location()
		*slot = 0
		mut ret := C.syscall(isize(C.SYS_wait4), isize(child.pid), &status, isize(C.WNOHANG), nil)
		mut actual := Result{ret, *slot}
		record(counts, 19, expected(actual, 0) && status == 0x12345678, actual)
		release(child)
		*slot = 0
		ret = C.syscall(isize(C.SYS_wait4), isize(child.pid), &status, isize(0), nil)
		actual = Result{ret, *slot}
		record(counts, 19, ret == child.pid && actual.code == 0 && status == 37 << 8, actual)
	}
}

fn suite(counts &Counts) {
	unsafe {
		child := launch()
		fd := open_pid(child.pid, 0)
		duplicate := C.dup(fd)
		nonblock := open_pid(child.pid, C.O_NONBLOCK)
		own := open_pid(C.getpid(), 0)
		own_duplicate := C.dup(own)
		nullfd := C.open(c'/dev/null', C.O_RDONLY | C.O_CLOEXEC)
		if duplicate < 0 || own_duplicate < 0 || nullfd < 0 { fatal(13) }
		for form in 0 .. 8 {
			mut info := C.siginfo_t{}
			C.memset(&info, 0xa5, sizeof(C.siginfo_t))
			mut actual := wait_fd(fd, C.WEXITED | C.WNOHANG, i32(form), &info)
			record(counts, 0, expected(actual, 0) && empty(&info), actual)
			actual = wait_fd(nonblock, C.WEXITED, i32(form), &info)
			record(counts, 1, expected(actual, C.EAGAIN) && empty(&info), actual)
			actual = wait_fd(nonblock, C.WEXITED | C.WNOHANG, i32(form), &info)
			record(counts, 2, expected(actual, 0) && empty(&info), actual)
			for negative in [i32(-1), i32(-2147483647 - 1)]! {
				actual = wait_fd(negative, C.WEXITED, i32(form), &info)
				record(counts, 7, expected(actual, C.EINVAL) && empty(&info), actual)
			}
			actual = wait_fd(0x7fffffff, C.WEXITED, i32(form), &info)
			record(counts, 8, expected(actual, C.EBADF) && empty(&info), actual)
		}
		mut info := C.siginfo_t{}
		closed := C.dup(fd)
		if closed < 0 || C.close(closed) != 0 { fatal(15) }
		closed_result := wait_fd(closed, C.WEXITED | C.WNOHANG, 0, &info)
		record(counts, 8, expected(closed_result, C.EBADF) && empty(&info), closed_result)
		for wrong in [child.door, nullfd]! {
			actual := wait_fd(wrong, C.WEXITED, 0, &info)
			record(counts, 9, expected(actual, C.EBADF) && empty(&info), actual)
		}
		for other in [own, own_duplicate]! {
			actual := wait_fd(other, C.WEXITED | C.WNOHANG, 0, &info)
			record(counts, 10, expected(actual, C.ECHILD) && empty(&info), actual)
		}
		for options in [i32(C.WNOHANG), i32(C.WEXITED) | 0x00800000]! {
			actual := wait_fd(0x7fffffff, options, 0, &info)
			record(counts, 11, expected(actual, C.EINVAL) && empty(&info), actual)
		}
		invalid := wait_id(0x7fffffff, fd, C.WEXITED, 0, &info, nil)
		record(counts, 11, expected(invalid, C.EINVAL) && empty(&info), invalid)
		for index in 0 .. 4 {
			target := if index == 0 {
				i32(-1)
			} else if index < 3 {
				i32(0x7fffffff)
			} else {
				fd
			}
			options := if index == 2 { i32(C.WNOHANG) } else { i32(C.WEXITED | C.WNOHANG) }
			actual := wait_fd(target, options, 0, voidptr(1))
			record(counts, 12, expected(actual, C.EFAULT), actual)
		}
		live_null := wait_fd(fd, C.WEXITED | C.WNOHANG, 0, nil)
		record(counts, 16, expected(live_null, 0), live_null)
		release(child)
		observe(child)
		for form in 0 .. 8 {
			actual := wait_fd(if form % 2 == 0 { fd } else { duplicate }, C.WEXITED | C.WNOWAIT, i32(form), &info)
			record(counts, 3, expected(actual, 0) && matches(&info, child), actual)
		}
		fault := wait_fd(fd, C.WEXITED | C.WNOWAIT, 0, voidptr(1))
		record(counts, 13, expected(fault, C.EFAULT), fault)
		preserved := wait_fd(duplicate, C.WEXITED | C.WNOWAIT, 0, &info)
		record(counts, 13, expected(preserved, 0) && matches(&info, child), preserved)
		C.memset(&info, 0xa5, sizeof(C.siginfo_t))
		bad_usage := wait_id(3, fd, C.WEXITED | C.WNOWAIT, 0, &info, voidptr(1))
		record(counts, 15, expected(bad_usage, C.EFAULT) && info.si_signo == i32(0xa5a5a5a5) && info.si_pid == i32(0xa5a5a5a5), bad_usage)
		usage_preserved := wait_fd(duplicate, C.WEXITED | C.WNOWAIT, 0, &info)
		record(counts, 15, expected(usage_preserved, 0) && matches(&info, child), usage_preserved)
		consumed := wait_fd(duplicate, C.WEXITED, 7, &info)
		record(counts, 4, expected(consumed, 0) && matches(&info, child), consumed)
		for reaped in [fd, duplicate]! {
			actual := wait_fd(reaped, C.WEXITED | C.WNOHANG, 0, &info)
			record(counts, 5, expected(actual, C.ECHILD) && empty(&info), actual)
		}
		for closefd in [fd, duplicate, nonblock, own, own_duplicate, nullfd]! { C.close(closefd) }

		first := launch()
		second := launch()
		firstfd := open_pid(first.pid, 0)
		secondfd := open_pid(second.pid, 0)
		release(second)
		observe(second)
		mut actual := wait_fd(firstfd, C.WEXITED | C.WNOHANG, 0, &info)
		record(counts, 6, expected(actual, 0) && empty(&info), actual)
		actual = wait_fd(secondfd, C.WEXITED, 0, &info)
		record(counts, 6, expected(actual, 0) && matches(&info, second), actual)
		actual = wait_fd(firstfd, C.WEXITED | C.WNOHANG, 0, &info)
		record(counts, 6, expected(actual, 0) && empty(&info), actual)
		release(first)
		actual = wait_fd(firstfd, C.WEXITED, 0, &info)
		record(counts, 6, expected(actual, 0) && matches(&info, first), actual)
		C.close(firstfd)
		C.close(secondfd)

		faulty := launch()
		faultyfd := open_pid(faulty.pid, 0)
		release(faulty)
		observe(faulty)
		actual = wait_fd(faultyfd, C.WEXITED, 0, voidptr(1))
		record(counts, 14, expected(actual, C.EFAULT), actual)
		actual = wait_fd(faultyfd, C.WEXITED | C.WNOHANG, 0, &info)
		record(counts, 14, expected(actual, C.ECHILD) && empty(&info), actual)
		C.close(faultyfd)
		nullchild := launch()
		nullchildfd := open_pid(nullchild.pid, 0)
		release(nullchild)
		actual = wait_fd(nullchildfd, C.WEXITED, 0, nil)
		record(counts, 16, expected(actual, 0), actual)
		C.close(nullchildfd)
		races(counts)
	}
}

fn name(index int) &char {
	return match index {
		0 { c'live' }
		1 { c'nonblock' }
		2 { c'nonblock_nohang' }
		3 { c'nowait' }
		4 { c'consume' }
		5 { c'reaped' }
		6 { c'identity' }
		7 { c'negative_fd' }
		8 { c'missing_fd' }
		9 { c'wrong_type' }
		10 { c'nonchild' }
		11 { c'options' }
		12 { c'copyout_error' }
		13 { c'copyout_nowait' }
		14 { c'copyout_consume' }
		15 { c'rusage_order' }
		16 { c'null_info' }
		17 { c'blocked_close' }
		18 { c'sibling_reap' }
		else { c'plain_wait4' }
	}
}

@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		reference := argc == 2 && C.strcmp(argv[1], c'--reference') == 0
		if argc != 1 && !reference { fatal(14) }
		C.alarm(120)
		mut counts := Counts{}
		suite(&counts)
		expected_calls := [i32(8), 8, 8, 8, 1, 2, 4, 16, 9, 2, 2, 3, 4, 2, 2, 2, 2, 16, 16, 2]!
		mut failed := false
		for index in 0 .. 20 {
			C.printf(c'LINUX PIDFDWAIT CASE: name=%s calls=%d failures=%d\n', name(index), counts.calls[index], counts.failures[index])
			if counts.calls[index] != expected_calls[index] || counts.failures[index] != 0 {
				failed = true
			}
		}
		if failed {
			C.puts(c'LINUX PIDFDWAIT FAIL: semantic checks')
			C.fflush(nil)
			return 1
		}
		C.alarm(0)
		C.puts(if reference { c'LINUX PIDFDWAIT REFERENCE: PASS' } else { c'LINUX PIDFDWAIT: PASS' })
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}

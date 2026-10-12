// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module pipezerofixture

#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

@[typedef]
struct C.sigset_t {}
struct C.sigaction {
mut:
	sa_handler fn(i32)
	sa_mask C.sigset_t
	sa_flags i32
}
struct C.pollfd { fd i32 events i16 mut: revents i16 }
__global ( alarms i32 broken_signals i32 )

fn C.sigaction(i32, &C.sigaction, &C.sigaction) i32
fn C.sigemptyset(&C.sigset_t) i32
fn C.alarm(u32) u32
fn C.__errno_location() &i32
fn C.syscall(isize, ...) isize
fn C.open(&char, i32, ...) i32
fn C.fcntl(i32, i32, ...) i32
fn C.close(i32) i32
fn C.read(i32, voidptr, usize) isize
fn C.write(i32, voidptr, usize) isize
fn C.poll(&C.pollfd, usize, i32) i32
fn C.ioctl(i32, usize, ...) i32
fn C.mkfifo(&char, u32) i32
fn C.mkdir(&char, u32) i32
fn C.chmod(&char, u32) i32
fn C.unlink(&char) i32
fn C.setgroups(usize, voidptr) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C._exit(i32)
fn C.mmap(voidptr, usize, i32, i32, i32, isize) voidptr
fn C.munmap(voidptr, usize) i32
fn C.sysconf(i32) isize
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.pause() i32

fn handler(signum i32) {
	if signum == C.SIGALRM { alarms++ }
	if signum == C.SIGPIPE { broken_signals++ }
}
fn io(fd i32, buffer voidptr, count usize, write bool, wanted isize, error_code i32) bool {
	unsafe {
		e := C.__errno_location(); *e = 0
		number := if write { C.SYS_write } else { C.SYS_read }
		actual := C.syscall(isize(number), isize(fd), buffer, count)
		code := *e
		if actual != wanted || code != error_code {
			C.printf(c'LINUX PIPEZERO DETAIL: fd=%d write=%d count=%lu actual=%ld/%d expected=%ld/%d alarms=%d\n', fd, i32(write), count, actual, code, wanted, error_code, alarms)
			C.fflush(nil)
			return false
		}
		return true
	}
}
fn readiness(fd i32) i32 {
	unsafe {
		mut item := C.pollfd{fd: fd, events: i16(C.POLLIN | C.POLLOUT)}
		if C.poll(&item, 1, 0) < 0 { return -1 }
		return i32(item.revents)
	}
}
fn queued(fd i32) i32 {
	unsafe {
		mut value := i32(-1)
		if C.ioctl(fd, usize(C.FIONREAD), &value) != 0 { return -1 }
		return value
	}
}
fn zeros(reader i32, writer i32, protected voidptr) bool {
	unsafe {
		before_read := readiness(reader); before_write := readiness(writer); before_bytes := queued(reader)
		if before_read < 0 || before_write < 0 || before_bytes < 0 { return false }
		for _ in 0 .. 64 {
			for buffer in [voidptr(nil), voidptr(1), protected]! {
				if !io(reader, buffer, 0, false, 0, 0) || !io(writer, buffer, 0, true, 0, 0) { return false }
			}
		}
		return alarms == 0 && broken_signals == 0 && queued(reader) == before_bytes
			&& readiness(reader) == before_read && readiness(writer) == before_write
	}
}
fn probe(kind i32) bool {
	unsafe {
		mut action := C.sigaction{sa_handler: handler}
		if C.sigemptyset(&action.sa_mask) != 0 || C.sigaction(C.SIGALRM, &action, nil) != 0
			|| C.sigaction(C.SIGPIPE, &action, nil) != 0 { return false }
		page := usize(C.sysconf(C._SC_PAGESIZE))
		protected := C.mmap(nil, page, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
		if u64(protected) == u64(-1) { return false }
		defer { C.munmap(protected, page) }
		mut pipes := [2]i32{}
		if C.pipe(&pipes[0]) != 0 { return false }
		defer { C.close(pipes[0]); C.close(pipes[1]) }
		C.alarm(5)
		defer { C.alarm(0) }
		mut byte := u8(0x5a)
		if kind == 0 {
			if !zeros(pipes[0], pipes[1], protected) { return false }
		} else if kind == 1 {
			if C.fcntl(pipes[0], C.F_SETFL, C.O_NONBLOCK) != 0
				|| !io(pipes[0], &byte, 1, false, -1, C.EAGAIN)
				|| !zeros(pipes[0], pipes[1], protected)
				|| !io(pipes[0], &byte, 1, false, -1, C.EAGAIN) { return false }
		} else if kind == 2 {
			if C.write(pipes[1], &byte, 1) != 1 || queued(pipes[0]) != 1
				|| !zeros(pipes[0], pipes[1], protected) { return false }
			byte = 0
			if C.read(pipes[0], &byte, 1) != 1 || byte != 0x5a || queued(pipes[0]) != 0 { return false }
		} else if kind == 3 {
			if C.fcntl(pipes[1], C.F_SETFL, C.O_NONBLOCK) != 0 { return false }
			mut data := [4096]u8{}
			mut total := isize(0)
			e := C.__errno_location()
			for _ in 0 .. 256 {
				*e = 0
				n := C.write(pipes[1], &data[0], 4096)
				if n < 0 { if *e != C.EAGAIN { return false }; break }
				if n != 4096 { return false }; total += n
			}
			if total < 4096 || queued(pipes[0]) != i32(total)
				|| !io(pipes[1], &byte, 1, true, -1, C.EAGAIN)
				|| !zeros(pipes[0], pipes[1], protected)
				|| !io(pipes[1], &byte, 1, true, -1, C.EAGAIN) { return false }
		} else if kind == 4 {
			if C.write(pipes[1], &byte, 1) != 1 || C.close(pipes[1]) != 0 { return false }
			for buffer in [voidptr(nil), voidptr(1), protected]! {
				if !io(pipes[0], buffer, 0, false, 0, 0) || queued(pipes[0]) != 1 { return false }
			}
			if !io(pipes[0], &byte, 1, false, 1, 0) || !io(pipes[0], protected, 0, false, 0, 0)
				|| !io(pipes[0], &byte, 1, false, 0, 0) { return false }
			mut broken := [2]i32{}
			if C.pipe(&broken[0]) != 0 || C.close(broken[0]) != 0 { return false }
			for buffer in [voidptr(nil), voidptr(1), protected]! {
				if !io(broken[1], buffer, 0, true, 0, 0) { return false }
			}
			if broken_signals != 0 || C.close(broken[1]) != 0 { return false }
		} else if kind == 5 {
			if C.mkfifo(c'/tmp/linux-pipezero/fifo', u32(0o600)) != 0 { C.printf(c'LINUX PIPEZERO DETAIL: FIFO create errno=%d\n', *C.__errno_location()); return false }
			fd := C.open(c'/tmp/linux-pipezero/fifo', C.O_RDWR)
			if fd < 0 { return false }
			if !zeros(fd, fd, protected) || C.fcntl(fd, C.F_SETFL, C.O_NONBLOCK) != 0
				|| !io(fd, &byte, 1, false, -1, C.EAGAIN) || !zeros(fd, fd, protected)
				|| C.close(fd) != 0 || C.unlink(c'/tmp/linux-pipezero/fifo') != 0 { return false }
		} else {
			if !io(-1, nil, 0, false, -1, C.EBADF) || !io(-1, nil, 0, true, -1, C.EBADF)
				|| !io(pipes[1], nil, 0, false, -1, C.EBADF) || !io(pipes[0], nil, 0, true, -1, C.EBADF) { return false }
			fd := C.open(c'/tmp/linux-pipezero/file', C.O_CREAT | C.O_RDWR, u32(0o600))
			if fd < 0 || !io(fd, protected, 0, false, 0, 0) || !io(fd, protected, 0, true, 0, 0)
				|| C.close(fd) != 0 || !io(fd, nil, 0, false, -1, C.EBADF)
				|| C.unlink(c'/tmp/linux-pipezero/file') != 0 { return false }
		}
		return alarms == 0 && broken_signals == 0
	}
}

fn C.pipe(&i32) i32
@[export: 'main']
pub fn run() i32 {
	unsafe {
		if C.mkdir(c'/tmp/linux-pipezero', u32(0o777)) != 0 || C.chmod(c'/tmp/linux-pipezero', u32(0o777)) != 0 { return 1 }
		if C.setgroups(0, nil) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0 { return 1 }
		for kind in 0 .. 7 {
			C.fflush(nil)
			child := C.fork()
			if child < 0 { return 1 }
			if child == 0 { C._exit(if probe(i32(kind)) { 0 } else { 1 }) }
			mut outcome := i32(-1)
			if C.waitpid(child, &outcome, 0) != child || outcome != 0 {
				C.printf(c'LINUX PIPEZERO DETAIL: kind=%d outcome=%d\n', i32(kind), outcome)
				C.puts(c'LINUX PIPEZERO FAIL: zero-length I/O, readiness, data or descriptor errors')
				C.fflush(nil); return 1
			}
			C.printf(c'LINUX PIPEZERO CASE: kind=%d PASS\n', i32(kind))
		}
		C.puts(c'LINUX PIPEZERO PASS: blocking/nonblocking empty, populated/full, hangup/broken and named FIFO zero I/O preserves readiness/data; null/unmapped/protected buffers and exact descriptor errors')
		C.puts(c'LINUX PIPEZERO: PASS'); C.fflush(nil)
		for { C.pause() }
	}
	return 0
}

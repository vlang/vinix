// SPDX-License-Identifier: GPL-2.0-or-later
// POSIX message queues: mq_open names, attributes, limits and errors, the
// descriptor's flags and stat, priority order, timeouts, blocked senders and
// receivers, interruption and restart, the status text, poll, mq_getsetattr,
// mq_notify's signal, none and thread (netlink cookie) kinds and when they
// are dropped, mq_unlink, permissions, RLIMIT_MSGQUEUE accounting, the
// namespace's queue limit and IPC namespaces.
// The same ELF runs as Vinix's init and, given --reference, under Linux.
module mqueuefixture

#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/resource.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

struct C.sigaction {
mut:
	sa_sigaction voidptr
	sa_flags     i32
}

@[typedef]
struct C.siginfo_t {}

struct C.pollfd {
mut:
	fd      i32
	events  i16
	revents i16
}

struct C.stat {
mut:
	st_ino   u64
	st_mode  u32
	st_nlink u64
	st_uid   u32
	st_gid   u32
	st_size  i64
}

fn C.syscall(isize, ...) isize
fn C.__errno_location() &i32
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.pause() i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C._exit(i32)
fn C.malloc(usize) voidptr
fn C.memset(voidptr, i32, usize) voidptr
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.memcmp(voidptr, voidptr, usize) i32
fn C.strcmp(&char, &char) i32
fn C.strlen(&char) usize
fn C.snprintf(&char, usize, &char, ...) i32
fn C.close(i32) i32
fn C.dup(i32) i32
fn C.read(i32, voidptr, usize) isize
fn C.write(i32, voidptr, usize) isize
fn C.pread(i32, voidptr, usize, i64) isize
fn C.lseek(i32, i64, i32) i64
fn C.open(&char, i32, ...) i32
fn C.fcntl(i32, i32, ...) i32
fn C.fstat(i32, &C.stat) i32
fn C.poll(&C.pollfd, u64, i32) i32
fn C.socket(i32, i32, i32) i32
fn C.socketpair(i32, i32, i32, &i32) i32
fn C.recv(i32, voidptr, usize, i32) isize
fn C.pipe(&i32) i32
fn C.mount(&char, &char, &char, u64, voidptr) i32
fn C.umask(u32) u32
fn C.getpid() i32
fn C.getppid() i32
fn C.setgroups(usize, voidptr) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.sigaction(i32, &C.sigaction, voidptr) i32
fn C.kill(i32, i32) i32

const o_rdonly = 0
const o_wronly = 1
const o_rdwr = 2
const o_creat = 0o100
const o_excl = 0o200
const o_nonblock = 0o4000
const usr1 = 10
const alrm = 14
const si_mesgq = -3
const sa_restart = 0x10000000
const af_netlink = 16
const af_unix = 1
const sock_raw = 3
const sock_stream = 1
const rlimit_msgqueue = 12
const clone_newipc = 0x08000000

struct State {
mut:
	checks   int
	failures int
	label    &char = c'MAIN'
	// Scratch the size of an mq_attr, a second one, a message buffer, a
	// sigevent, a siginfo and a few words.
	attr  &i64 = unsafe { nil }
	old   &i64 = unsafe { nil }
	buf   &u8  = unsafe { nil }
	sev   &u8  = unsafe { nil }
	info  &u8  = unsafe { nil }
	words &i64 = unsafe { nil }
	text  &u8  = unsafe { nil }
	st    &C.stat = unsafe { nil }
}

fn check(mut s State, label &char, ok bool, got i64) {
	s.checks++
	if !ok {
		s.failures++
		C.printf(c'LINUX MQUEUE FAIL: %s: %s value=%ld\n', s.label, label, got)
	}
}

// A raw syscall's result, or -errno.
fn result(r isize) i64 {
	if r < 0 {
		unsafe {
			return -i64(*C.__errno_location())
		}
	}
	return i64(r)
}

fn mq_open(name voidptr, flags i64, mode i64, attr voidptr) i64 {
	return result(C.syscall(isize(C.SYS_mq_open), name, flags, mode, attr))
}

fn mq_unlink(name voidptr) i64 {
	return result(C.syscall(isize(C.SYS_mq_unlink), name))
}

fn mq_send(fd i64, message voidptr, length u64, priority u64, timeout voidptr) i64 {
	return result(C.syscall(isize(C.SYS_mq_timedsend), fd, message, length, priority, timeout))
}

fn mq_receive(fd i64, buffer voidptr, length u64, priority voidptr, timeout voidptr) i64 {
	return result(C.syscall(isize(C.SYS_mq_timedreceive), fd, buffer, length, priority, timeout))
}

fn mq_notify(fd i64, sev voidptr) i64 {
	return result(C.syscall(isize(C.SYS_mq_notify), fd, sev))
}

fn mq_getsetattr(fd i64, new voidptr, old voidptr) i64 {
	return result(C.syscall(isize(C.SYS_mq_getsetattr), fd, new, old))
}

fn set_attr(attr &i64, flags i64, maxmsg i64, msgsize i64, curmsgs i64) voidptr {
	unsafe {
		C.memset(attr, 0, 64)
		attr[0] = flags
		attr[1] = maxmsg
		attr[2] = msgsize
		attr[3] = curmsgs
	}
	return voidptr(attr)
}

// mq_getsetattr's old attributes into s.old; -1 on failure.
fn current(mut s State, fd i64) i64 {
	unsafe { C.memset(s.old, 0xff, 64) }
	return mq_getsetattr(fd, nil, s.old)
}

fn curmsgs(mut s State, fd i64) i64 {
	if current(mut s, fd) != 0 {
		return -1
	}
	return unsafe { s.old[3] }
}

// An absolute CLOCK_REALTIME time `ms` from now, in s.words[0..2].
fn deadline(mut s State, ms i64) voidptr {
	unsafe {
		C.syscall(isize(C.SYS_clock_gettime), 0, s.words)
		s.words[1] += (ms % 1000) * 1000000
		s.words[0] += ms / 1000
		if s.words[1] >= 1000000000 {
			s.words[1] -= 1000000000
			s.words[0]++
		}
		if s.words[1] < 0 {
			s.words[1] += 1000000000
			s.words[0]--
		}
		return voidptr(s.words)
	}
}

fn monotonic_ms() i64 {
	unsafe {
		mut ts := &i64(C.malloc(16))
		C.syscall(isize(C.SYS_clock_gettime), 1, ts)
		ms := ts[0] * 1000 + ts[1] / 1000000
		C.free(ts)
		return ms
	}
}

fn C.free(voidptr)

fn sleep_ms(ms i64) {
	unsafe {
		mut ts := &i64(C.malloc(16))
		ts[0] = ms / 1000
		ts[1] = (ms % 1000) * 1000000
		C.syscall(isize(C.SYS_nanosleep), ts, nil)
		C.free(ts)
	}
}

// Whether process `pid` sleeps, from /proc/<pid>/stat; waits up to 10 s.
fn wait_sleeping(pid i32) bool {
	unsafe {
		path := &char(C.malloc(64))
		text := &u8(C.malloc(512))
		C.snprintf(path, 64, c'/proc/%d/stat', pid)
		for _ in 0 .. 1000 {
			fd := C.open(path, 0)
			if fd >= 0 {
				n := C.read(fd, text, 511)
				C.close(fd)
				if n > 0 {
					text[n] = 0
					mut i := int(n) - 1
					for i > 0 && text[i] != `)` {
						i--
					}
					if i > 0 && i + 2 < int(n) && text[i + 2] == `S` {
						C.free(path)
						C.free(text)
						return true
					}
				}
			}
			sleep_ms(10)
		}
		C.free(path)
		C.free(text)
		return false
	}
}

// The status text read at offset 0 equals what Linux prints for the values.
fn status_is(mut s State, label &char, fd i64, qsize u64, notify int, signo int, pid int) {
	unsafe {
		expected := &char(C.malloc(128))
		C.snprintf(expected, 128, c'QSIZE:%-10lu NOTIFY:%-5d SIGNO:%-5d NOTIFY_PID:%-6d\n', qsize,
			notify, signo, pid)
		C.memset(s.text, 0, 160)
		n := C.pread(i32(fd), s.text, 150, 0)
		ok := n == isize(C.strlen(expected)) && C.strcmp(&char(s.text), expected) == 0
		if !ok {
			C.printf(c'LINUX MQUEUE STATUS: got [%s]\n', &char(s.text))
		}
		check(mut s, label, ok, i64(n))
		C.free(expected)
	}
}

fn block_usr1() {
	unsafe {
		mut set := &u64(C.malloc(8))
		*set = u64(1) << (usr1 - 1)
		C.syscall(isize(C.SYS_rt_sigprocmask), 0, set, nil, 8)
		C.free(set)
	}
}

// A pending SIGUSR1 taken without waiting into s.info, or -errno.
fn take_usr1(mut s State) i64 {
	unsafe {
		mut set := &u64(C.malloc(8))
		*set = u64(1) << (usr1 - 1)
		mut zero := &i64(C.malloc(16))
		zero[0] = 0
		zero[1] = 0
		C.memset(s.info, 0, 128)
		r := result(C.syscall(isize(C.SYS_rt_sigtimedwait), set, s.info, zero, 8))
		C.free(set)
		C.free(zero)
		return r
	}
}

fn set_signal_event(mut s State, notify int, signo int, value u64) voidptr {
	unsafe {
		C.memset(s.sev, 0, 64)
		*&u64(s.sev) = value
		*&i32(s.sev + 8) = i32(signo)
		*&i32(s.sev + 12) = i32(notify)
	}
	return voidptr(s.sev)
}

fn on_alarm(signal i32, info &C.siginfo_t, context voidptr) {}

fn alarm_handler(restart bool) {
	unsafe {
		mut action := &C.sigaction(C.malloc(256))
		C.memset(action, 0, 256)
		action.sa_sigaction = voidptr(on_alarm)
		action.sa_flags = if restart { sa_restart } else { 0 }
		C.sigaction(alrm, action, nil)
		C.free(action)
	}
}

fn alarm_in(ms i64) {
	unsafe {
		mut value := &i64(C.malloc(32))
		value[0] = 0
		value[1] = 0
		value[2] = ms / 1000
		value[3] = (ms % 1000) * 1000
		C.syscall(isize(C.SYS_setitimer), 0, value, nil)
		C.free(value)
	}
}

fn names(mut s State) {
	unsafe {
		s.label = c'names'
		check(mut s, c'missing', mq_open(c'q1', o_rdwr, 0, nil) == -C.ENOENT, mq_open(c'q1', o_rdwr, 0, nil))
		check(mut s, c'leading slash', mq_open(c'/q1', o_creat | o_rdwr, 0o600, nil) == -C.EACCES, 0)
		check(mut s, c'inner slash', mq_open(c'a/b', o_creat | o_rdwr, 0o600, nil) == -C.EACCES, 0)
		check(mut s, c'empty', mq_open(c'', o_creat | o_rdwr, 0o600, nil) == -C.ENOENT, 0)
		check(mut s, c'dot', mq_open(c'.', o_creat | o_rdwr, 0o600, nil) == -C.EACCES, 0)
		check(mut s, c'dotdot', mq_open(c'..', o_creat | o_rdwr, 0o600, nil) == -C.EACCES, 0)
		check(mut s, c'null', mq_open(nil, o_creat | o_rdwr, 0o600, nil) == -C.EFAULT, 0)
		check(mut s, c'bad pointer', mq_open(voidptr(8), o_creat | o_rdwr, 0o600, nil) == -C.EFAULT, 0)
		mut long := &u8(C.malloc(400))
		C.memset(long, `a`, 399)
		long[299] = 0
		check(mut s, c'299 bytes', mq_open(long, o_creat | o_rdwr, 0o600, nil) == -C.ENAMETOOLONG, 0)
		long[256] = 0
		check(mut s, c'256 bytes', mq_open(long, o_creat | o_rdwr, 0o600, nil) == -C.ENAMETOOLONG, 0)
		long[255] = 0
		fd := mq_open(long, o_creat | o_rdwr, 0o600, nil)
		check(mut s, c'255 bytes', fd >= 0, fd)
		check(mut s, c'255 bytes unlink', mq_unlink(long) == 0, 0)
		C.close(i32(fd))
		long[255] = `a`
		long[10] = `/`
		check(mut s, c'long name with slash', mq_open(long, o_creat | o_rdwr, 0o600, nil) == -C.EACCES, 0)
		C.free(long)
		check(mut s, c'unlink missing', mq_unlink(c'q1') == -C.ENOENT, 0)
		check(mut s, c'unlink slash', mq_unlink(c'/q1') == -C.EACCES, 0)
		check(mut s, c'unlink empty', mq_unlink(c'') == -C.ENOENT, 0)
		check(mut s, c'unlink null', mq_unlink(nil) == -C.EFAULT, 0)
		// The descriptor number is taken before the name is looked up or made.
		mut limits := &u64(s.words + 12)
		C.syscall(isize(C.SYS_prlimit64), 0, 7, nil, limits)
		saved := limits[0]
		lowest := C.dup(0)
		C.close(lowest)
		limits[0] = u64(lowest)
		C.syscall(isize(C.SYS_prlimit64), 0, 7, limits, nil)
		check(mut s, c'no descriptor: create', mq_open(c'qf', o_creat | o_rdwr, 0o600, nil) == -C.EMFILE, 0)
		check(mut s, c'no descriptor: lookup', mq_open(c'missing', o_rdwr, 0, nil) == -C.EMFILE, 0)
		limits[0] = saved
		C.syscall(isize(C.SYS_prlimit64), 0, 7, limits, nil)
		check(mut s, c'no descriptor: nothing made', mq_unlink(c'qf') == -C.ENOENT, 0)
	}
}

fn attributes(mut s State) {
	unsafe {
		s.label = c'attributes'
		a := s.attr
		check(mut s, c'maxmsg 0', mq_open(c'qa', o_creat | o_rdwr, 0o600, set_attr(a, 0, 0, 16, 0)) == -C.EINVAL, 0)
		check(mut s, c'msgsize 0', mq_open(c'qa', o_creat | o_rdwr, 0o600, set_attr(a, 0, 4, 0, 0)) == -C.EINVAL, 0)
		check(mut s, c'maxmsg -1', mq_open(c'qa', o_creat | o_rdwr, 0o600, set_attr(a, 0, -1, 16, 0)) == -C.EINVAL, 0)
		check(mut s, c'msgsize -1', mq_open(c'qa', o_creat | o_rdwr, 0o600, set_attr(a, 0, 4, -1, 0)) == -C.EINVAL, 0)
		check(mut s, c'maxmsg 65537', mq_open(c'qa', o_creat | o_rdwr, 0o600, set_attr(a, 0, 65537, 16, 0)) == -C.EINVAL, 0)
		check(mut s, c'msgsize 16M+1', mq_open(c'qa', o_creat | o_rdwr, 0o600, set_attr(a, 0, 1, 16777217, 0)) == -C.EINVAL, 0)
		check(mut s, c'maxmsg 65536 over rlimit', mq_open(c'qa', o_creat | o_rdwr, 0o600, set_attr(a, 0, 65536, 16, 0)) == -C.EMFILE, 0)
		check(mut s, c'msgsize 1M over rlimit', mq_open(c'qa', o_creat | o_rdwr, 0o600, set_attr(a, 0, 4, 1048576, 0)) == -C.EMFILE, 0)
		check(mut s, c'both largest over rlimit', mq_open(c'qa', o_creat | o_rdwr, 0o600, set_attr(a, 0, 65536, 16777216, 0)) == -C.EMFILE, 0)
		check(mut s, c'attr fault', mq_open(c'qa', o_creat | o_rdwr, 0o600, voidptr(8)) == -C.EFAULT, 0)
		check(mut s, c'attr fault before name', mq_open(nil, o_creat | o_rdwr, 0o600, voidptr(8)) == -C.EFAULT, 0)
		// Root holds CAP_SYS_RESOURCE: over msg_max and msgsize_max.
		big := mq_open(c'qa', o_creat | o_rdwr, 0o600, set_attr(a, 0x12345, 11, 8193, 77))
		check(mut s, c'privileged 11x8193', big >= 0, big)
		check(mut s, c'given attr', current(mut s, big) == 0 && s.old[0] == 0 && s.old[1] == 11
			&& s.old[2] == 8193 && s.old[3] == 0, s.old[1])
		check(mut s, c'reserved words zero', s.old[4] == 0 && s.old[5] == 0 && s.old[6] == 0 && s.old[7] == 0, s.old[4])
		again := mq_open(c'qa', o_creat | o_rdwr, 0o600, set_attr(a, 0, 0, 0, 0))
		check(mut s, c'existing ignores attr', again >= 0, again)
		check(mut s, c'existing excl', mq_open(c'qa', o_creat | o_excl | o_rdwr, 0o600, nil) == -C.EEXIST, 0)
		check(mut s, c'existing accmode 3', mq_open(c'qa', 3, 0, nil) == -C.EINVAL, 0)
		check(mut s, c'accmode 3 excl first', mq_open(c'qa', o_creat | o_excl | 3, 0, nil) == -C.EEXIST, 0)
		C.close(i32(again))
		C.close(i32(big))
		mq_unlink(c'qa')
		d := mq_open(c'qd', o_creat | o_rdwr | 0x40000000, 0o640, nil)
		check(mut s, c'default with unknown flag', d >= 0, d)
		check(mut s, c'default attr', current(mut s, d) == 0 && s.old[1] == 10 && s.old[2] == 8192, s.old[2])
		ro := mq_open(c'qd', o_rdonly, 0, nil)
		wo := mq_open(c'qd', o_wronly | o_nonblock, 0, nil)
		check(mut s, c'open ro and wo', ro >= 0 && wo >= 0, wo)
		check(mut s, c'nonblock flag', current(mut s, wo) == 0 && s.old[0] == o_nonblock, s.old[0])
		check(mut s, c'close-on-exec', C.fcntl(i32(wo), C.F_GETFD) == C.FD_CLOEXEC, 0)
		check(mut s, c'status flags', C.fcntl(i32(wo), C.F_GETFL) == o_wronly | o_nonblock, C.fcntl(i32(wo), C.F_GETFL))
		C.fstat(i32(d), s.st)
		check(mut s, c'mode', s.st.st_mode == 0o100640, i64(s.st.st_mode))
		check(mut s, c'owner', s.st.st_uid == 0 && s.st.st_gid == 0, i64(s.st.st_uid))
		check(mut s, c'size', s.st.st_size == 80, s.st.st_size)
		check(mut s, c'nlink', s.st.st_nlink == 1, i64(s.st.st_nlink))
		inode := s.st.st_ino
		C.fstat(i32(ro), s.st)
		check(mut s, c'same inode', s.st.st_ino == inode, 0)
		check(mut s, c'send on ro', mq_send(ro, c'x', 1, 0, nil) == -C.EBADF, 0)
		check(mut s, c'receive on wo', mq_receive(wo, s.buf, 8192, nil, nil) == -C.EBADF, 0)
		check(mut s, c'write on queue', result(C.write(i32(d), c'x', 1)) == -C.EINVAL, 0)
		check(mut s, c'read on wo', result(C.read(i32(wo), s.buf, 10)) == -C.EBADF, 0)
		C.umask(0o022)
		p := mq_open(c'qm', o_creat | o_rdwr, 0o4777, nil)
		C.fstat(i32(p), s.st)
		check(mut s, c'umask and setuid bit', s.st.st_mode == 0o104755, i64(s.st.st_mode))
		C.close(i32(p))
		mq_unlink(c'qm')
		C.umask(0)
		check(mut s, c'unlink', mq_unlink(c'qd') == 0, 0)
		C.fstat(i32(d), s.st)
		check(mut s, c'nlink after unlink', s.st.st_nlink == 0, i64(s.st.st_nlink))
		check(mut s, c'unlinked still usable', mq_send(d, c'z', 1, 0, nil) == 0 && curmsgs(mut s, ro) == 1, 0)
		n := mq_open(c'qd', o_creat | o_excl | o_rdwr, 0o600, nil)
		C.fstat(i32(n), s.st)
		check(mut s, c'new queue after unlink', n >= 0 && s.st.st_ino != inode && curmsgs(mut s, n) == 0, n)
		C.close(i32(n))
		mq_unlink(c'qd')
		C.close(i32(d))
		C.close(i32(ro))
		C.close(i32(wo))
	}
}

fn send_receive(mut s State) {
	unsafe {
		s.label = c'transfer'
		q := mq_open(c'qt', o_creat | o_rdwr, 0o600, nil)
		mut prio := &u32(s.words + 4)
		check(mut s, c'too long', mq_send(q, s.buf, 8193, 0, nil) == -C.EMSGSIZE, 0)
		check(mut s, c'priority 32768', mq_send(q, c'x', 1, 32768, nil) == -C.EINVAL, 0)
		check(mut s, c'priority before descriptor', mq_send(999, c'x', 1, 32768, nil) == -C.EINVAL, 0)
		check(mut s, c'timeout fault first', mq_send(q, c'x', 1, 32768, voidptr(8)) == -C.EFAULT, 0)
		check(mut s, c'bad descriptor', mq_send(999, c'x', 1, 0, nil) == -C.EBADF, 0)
		check(mut s, c'not a queue', mq_send(0, c'x', 1, 0, nil) == -C.EBADF, 0)
		check(mut s, c'send low', mq_send(q, c'low', 3, 1, nil) == 0, 0)
		check(mut s, c'send mid', mq_send(q, c'mid', 3, 5, nil) == 0, 0)
		check(mut s, c'send mid2', mq_send(q, c'mid2', 4, 5, nil) == 0, 0)
		check(mut s, c'send empty', mq_send(q, nil, 0, 9, nil) == 0, 0)
		// The priority word is an unsigned int: 2^32 + 3 is 3.
		check(mut s, c'send high word', mq_send(q, c'three', 5, (u64(1) << 32) | 3, nil) == 0, 0)
		check(mut s, c'curmsgs 5', curmsgs(mut s, q) == 5, s.old[3])
		status_is(mut s, c'status qsize', q, 15, 0, 0, 0)
		check(mut s, c'buffer too small', mq_receive(q, s.buf, 8191, nil, nil) == -C.EMSGSIZE, 0)
		*prio = 99
		check(mut s, c'first highest', mq_receive(q, s.buf, 8192, prio, nil) == 0 && *prio == 9, *prio)
		check(mut s, c'then mid', mq_receive(q, s.buf, 8192, prio, nil) == 3 && *prio == 5
			&& C.memcmp(s.buf, c'mid', 3) == 0, *prio)
		check(mut s, c'then mid2', mq_receive(q, s.buf, 8192, prio, nil) == 4 && *prio == 5
			&& C.memcmp(s.buf, c'mid2', 4) == 0, *prio)
		check(mut s, c'then three', mq_receive(q, s.buf, 8192, prio, nil) == 5 && *prio == 3, *prio)
		check(mut s, c'then low', mq_receive(q, s.buf, 8192, nil, nil) == 3
			&& C.memcmp(s.buf, c'low', 3) == 0, 0)
		nb := mq_open(c'qt', o_rdwr | o_nonblock, 0, nil)
		check(mut s, c'empty nonblock', mq_receive(nb, s.buf, 8192, nil, nil) == -C.EAGAIN, 0)
		start := monotonic_ms()
		check(mut s, c'timeout', mq_receive(q, s.buf, 8192, nil, deadline(mut s, 100)) == -C.ETIMEDOUT, 0)
		elapsed := monotonic_ms() - start
		check(mut s, c'timeout waited', elapsed >= 80 && elapsed < 5000, elapsed)
		check(mut s, c'past timeout', mq_receive(q, s.buf, 8192, nil, deadline(mut s, -1000)) == -C.ETIMEDOUT, 0)
		s.words[0] = 1
		s.words[1] = 1000000000
		check(mut s, c'nanoseconds 1e9', mq_receive(q, s.buf, 8192, nil, s.words) == -C.EINVAL, 0)
		check(mut s, c'invalid before nonblock', mq_receive(nb, s.buf, 8192, nil, s.words) == -C.EINVAL, 0)
		s.words[0] = -1
		s.words[1] = 0
		check(mut s, c'negative seconds', mq_receive(q, s.buf, 8192, nil, s.words) == -C.EINVAL, 0)
		check(mut s, c'timeout fault', mq_receive(q, s.buf, 8192, nil, voidptr(8)) == -C.EFAULT, 0)
		mq_send(q, c'ready', 5, 0, nil)
		check(mut s, c'past timeout with a message', mq_receive(q, s.buf, 8192, nil, deadline(mut s, -1000)) == 5, 0)
		check(mut s, c'message fault', mq_send(q, voidptr(8), 4, 0, nil) == -C.EFAULT && curmsgs(mut s, q) == 0, 0)
		mq_send(q, c'abcd', 4, 0, nil)
		check(mut s, c'buffer fault', mq_receive(q, voidptr(8), 8192, nil, nil) == -C.EFAULT, 0)
		check(mut s, c'buffer fault consumed', curmsgs(mut s, q) == 0, s.old[3])
		mq_send(q, c'efgh', 4, 3, nil)
		check(mut s, c'priority fault', mq_receive(q, s.buf, 8192, voidptr(8), nil) == -C.EFAULT, 0)
		check(mut s, c'priority fault consumed', curmsgs(mut s, q) == 0, s.old[3])
		check(mut s, c'empty send null', mq_send(q, nil, 0, 0, nil) == 0, 0)
		check(mut s, c'empty receive bad buffer', mq_receive(q, voidptr(8), 8192, nil, nil) == 0, 0)
		C.close(i32(nb))
		C.close(i32(q))
		mq_unlink(c'qt')
		// A queue of two 16-byte messages.
		small := mq_open(c'qs', o_creat | o_rdwr | o_nonblock, 0o600, set_attr(s.attr, 0, 2, 16, 0))
		check(mut s, c'exact size', mq_send(small, s.buf, 16, 0, nil) == 0, 0)
		check(mut s, c'one over', mq_send(small, s.buf, 17, 0, nil) == -C.EMSGSIZE, 0)
		check(mut s, c'fill', mq_send(small, c'2', 1, 0, nil) == 0, 0)
		check(mut s, c'full nonblock', mq_send(small, c'3', 1, 0, nil) == -C.EAGAIN, 0)
		mq_getsetattr(small, set_attr(s.attr, 0, 0, 0, 0), nil)
		check(mut s, c'full timeout', mq_send(small, c'3', 1, 0, deadline(mut s, 50)) == -C.ETIMEDOUT, 0)
		check(mut s, c'full past timeout', mq_send(small, c'3', 1, 0, deadline(mut s, -10)) == -C.ETIMEDOUT, 0)
		check(mut s, c'still two', curmsgs(mut s, small) == 2, s.old[3])
		mut pfd := &C.pollfd(s.words + 2)
		pfd.fd = i32(small)
		pfd.events = i16(C.POLLIN | C.POLLOUT)
		pfd.revents = 0
		check(mut s, c'poll full', C.poll(pfd, 1, 0) == 1 && pfd.revents == i16(C.POLLIN), pfd.revents)
		pfd.events = i16(C.POLLRDNORM | C.POLLWRNORM)
		check(mut s, c'poll full norm', C.poll(pfd, 1, 0) == 1 && pfd.revents == i16(C.POLLRDNORM), pfd.revents)
		status_is(mut s, c'status full', small, 17, 0, 0, 0)
		check(mut s, c'read status', C.read(i32(small), s.buf, 200) == 60, 0)
		check(mut s, c'read at end', C.read(i32(small), s.buf, 200) == 0, 0)
		C.lseek(i32(small), 6, 0)
		check(mut s, c'read part', C.read(i32(small), s.buf, 2) == 2 && s.buf[0] == `1` && s.buf[1] == `7`, 0)
		mq_receive(small, s.buf, 16, nil, nil)
		mq_receive(small, s.buf, 16, nil, nil)
		pfd.events = i16(C.POLLIN | C.POLLOUT)
		check(mut s, c'poll empty', C.poll(pfd, 1, 0) == 1 && pfd.revents == i16(C.POLLOUT), pfd.revents)
		mq_send(small, c'1', 1, 0, nil)
		check(mut s, c'poll partly', C.poll(pfd, 1, 0) == 1 && pfd.revents == i16(C.POLLIN | C.POLLOUT), pfd.revents)
		C.close(i32(small))
		mq_unlink(c'qs')
	}
}

fn blocking(mut s State) {
	unsafe {
		s.label = c'blocking'
		q := mq_open(c'qb', o_creat | o_rdwr, 0o600, set_attr(s.attr, 0, 2, 16, 0))
		block_usr1()
		check(mut s, c'register', mq_notify(q, set_signal_event(mut s, 0, usr1, 7)) == 0, 0)
		me := C.getpid()
		// A waiting receiver gets the message; the notification stays.
		mut child := C.fork()
		if child == 0 {
			wait_sleeping(me)
			C._exit(if mq_send(q, c'handed', 6, 4, nil) == 0 { 0 } else { 1 })
		}
		mut prio := &u32(s.words + 6)
		got := mq_receive(q, s.buf, 16, prio, deadline(mut s, 10000))
		mut status := &i32(s.words + 7)
		C.waitpid(child, status, 0)
		check(mut s, c'waiting receiver', got == 6 && *prio == 4 && C.memcmp(s.buf, c'handed', 6) == 0, got)
		check(mut s, c'no notification', take_usr1(mut s) == -C.EAGAIN, 0)
		status_is(mut s, c'still registered', q, 0, 0, usr1, me)
		mq_notify(q, nil)
		// A waiting sender's message goes in when there is room.
		mq_send(q, c'a', 1, 0, nil)
		mq_send(q, c'b', 1, 0, nil)
		child = C.fork()
		if child == 0 {
			C._exit(if mq_send(q, c'c', 1, 7, nil) == 0 { 0 } else { 1 })
		}
		check(mut s, c'sender sleeps', wait_sleeping(child), 0)
		check(mut s, c'receive a', mq_receive(q, s.buf, 16, nil, nil) == 1 && s.buf[0] == `a`, 0)
		C.waitpid(child, status, 0)
		check(mut s, c'sender done', *status == 0, *status)
		check(mut s, c'its message is in', curmsgs(mut s, q) == 2, s.old[3])
		check(mut s, c'receive c first', mq_receive(q, s.buf, 16, nil, nil) == 1 && s.buf[0] == `c`, 0)
		check(mut s, c'then b', mq_receive(q, s.buf, 16, nil, nil) == 1 && s.buf[0] == `b`, 0)
		// A signal ends a wait with EINTR, or restarts it with SA_RESTART.
		alarm_handler(false)
		alarm_in(50)
		check(mut s, c'interrupted', mq_receive(q, s.buf, 16, nil, deadline(mut s, 5000)) == -C.EINTR, 0)
		alarm_handler(true)
		alarm_in(50)
		start := monotonic_ms()
		r := mq_receive(q, s.buf, 16, nil, deadline(mut s, 400))
		elapsed := monotonic_ms() - start
		check(mut s, c'restarted to timeout', r == -C.ETIMEDOUT && elapsed >= 300, elapsed)
		mq_send(q, c'1', 1, 0, nil)
		mq_send(q, c'2', 1, 0, nil)
		alarm_handler(false)
		alarm_in(50)
		check(mut s, c'sender interrupted', mq_send(q, c'3', 1, 0, nil) == -C.EINTR, 0)
		check(mut s, c'nothing added', curmsgs(mut s, q) == 2, s.old[3])
		C.close(i32(q))
		mq_unlink(c'qb')
	}
}

fn attr_calls(mut s State) {
	unsafe {
		s.label = c'getsetattr'
		q := mq_open(c'qg', o_creat | o_rdwr | o_nonblock, 0o600, set_attr(s.attr, 0, 3, 32, 0))
		mq_send(q, c'x', 1, 0, nil)
		C.memset(s.old, 0xff, 64)
		check(mut s, c'set and get', mq_getsetattr(q, set_attr(s.attr, 0, 99, 99, 99), s.old) == 0, 0)
		check(mut s, c'old values', s.old[0] == o_nonblock && s.old[1] == 3 && s.old[2] == 32 && s.old[3] == 1, s.old[0])
		check(mut s, c'old reserved', s.old[4] == 0 && s.old[7] == 0, s.old[4])
		check(mut s, c'cleared', current(mut s, q) == 0 && s.old[0] == 0 && s.old[1] == 3, s.old[0])
		check(mut s, c'fcntl sees it', C.fcntl(i32(q), C.F_GETFL) & o_nonblock == 0, 0)
		C.fcntl(i32(q), C.F_SETFL, o_nonblock)
		check(mut s, c'sees fcntl', current(mut s, q) == 0 && s.old[0] == o_nonblock, s.old[0])
		check(mut s, c'other flags', mq_getsetattr(q, set_attr(s.attr, o_nonblock | 2, 0, 0, 0), nil) == -C.EINVAL, 0)
		check(mut s, c'unknown flag', mq_getsetattr(q, set_attr(s.attr, 0x10000, 0, 0, 0), nil) == -C.EINVAL, 0)
		check(mut s, c'flags before descriptor', mq_getsetattr(999, set_attr(s.attr, 1, 0, 0, 0), nil) == -C.EINVAL, 0)
		check(mut s, c'bad descriptor', mq_getsetattr(999, nil, s.old) == -C.EBADF, 0)
		check(mut s, c'not a queue', mq_getsetattr(0, nil, s.old) == -C.EBADF, 0)
		check(mut s, c'new fault', mq_getsetattr(q, voidptr(8), s.old) == -C.EFAULT, 0)
		check(mut s, c'old fault', mq_getsetattr(q, set_attr(s.attr, 0, 0, 0, 0), voidptr(8)) == -C.EFAULT, 0)
		check(mut s, c'change kept', current(mut s, q) == 0 && s.old[0] == 0, s.old[0])
		check(mut s, c'neither', mq_getsetattr(q, nil, nil) == 0, 0)
		C.close(i32(q))
		mq_unlink(c'qg')
	}
}

fn notifications(mut s State) {
	unsafe {
		s.label = c'notify'
		block_usr1()
		me := C.getpid()
		q := mq_open(c'qn', o_creat | o_rdwr | o_nonblock, 0o600, nil)
		check(mut s, c'register', mq_notify(q, set_signal_event(mut s, 0, usr1, 0x4242)) == 0, 0)
		status_is(mut s, c'status registered', q, 0, 0, usr1, me)
		check(mut s, c'busy', mq_notify(q, set_signal_event(mut s, 0, usr1, 1)) == -C.EBUSY, 0)
		mut status := &i32(s.words + 7)
		mut child := C.fork()
		if child == 0 {
			mut code := 0
			if mq_notify(q, set_signal_event(mut s, 0, usr1, 1)) != -C.EBUSY { code |= 1 }
			// Not the owner: unregistering does nothing, and succeeds.
			if mq_notify(q, nil) != 0 { code |= 2 }
			if mq_send(q, c'n', 1, 0, nil) != 0 { code |= 4 }
			C._exit(code)
		}
		C.waitpid(child, status, 0)
		check(mut s, c'child', *status == 0, *status)
		got := take_usr1(mut s)
		check(mut s, c'signal', got == usr1, got)
		check(mut s, c'si_code', *&i32(s.info + 8) == si_mesgq, *&i32(s.info + 8))
		check(mut s, c'si_pid', *&i32(s.info + 16) == child, *&i32(s.info + 16))
		check(mut s, c'si_uid', *&u32(s.info + 20) == 0, i64(*&u32(s.info + 20)))
		check(mut s, c'si_value', *&u64(s.info + 24) == 0x4242, i64(*&u64(s.info + 24)))
		status_is(mut s, c'used up', q, 1, 0, 0, 0)
		// Only an empty queue gaining a message notifies.
		check(mut s, c'register again', mq_notify(q, set_signal_event(mut s, 0, usr1, 5)) == 0, 0)
		mq_send(q, c'm', 1, 0, nil)
		check(mut s, c'not empty: none', take_usr1(mut s) == -C.EAGAIN, 0)
		mq_receive(q, s.buf, 8192, nil, nil)
		mq_receive(q, s.buf, 8192, nil, nil)
		mq_send(q, c'm', 1, 0, nil)
		check(mut s, c'empty again: sent', take_usr1(mut s) == usr1 && *&i32(s.info + 16) == me, 0)
		mq_receive(q, s.buf, 8192, nil, nil)
		check(mut s, c'unregister', mq_notify(q, set_signal_event(mut s, 0, usr1, 5)) == 0
			&& mq_notify(q, nil) == 0, 0)
		check(mut s, c'unregister again', mq_notify(q, nil) == 0, 0)
		mq_send(q, c'm', 1, 0, nil)
		check(mut s, c'unregistered: none', take_usr1(mut s) == -C.EAGAIN, 0)
		mq_receive(q, s.buf, 8192, nil, nil)
		// SIGEV_NONE owns the queue's notification without a signal.
		check(mut s, c'none', mq_notify(q, set_signal_event(mut s, 1, 0, 0)) == 0, 0)
		status_is(mut s, c'status none', q, 0, 1, 0, me)
		check(mut s, c'none busy', mq_notify(q, set_signal_event(mut s, 0, usr1, 0)) == -C.EBUSY, 0)
		mq_send(q, c'm', 1, 0, nil)
		status_is(mut s, c'none used up', q, 1, 0, 0, 0)
		mq_receive(q, s.buf, 8192, nil, nil)
		check(mut s, c'signal 0', mq_notify(q, set_signal_event(mut s, 0, 0, 0)) == 0, 0)
		mq_send(q, c'm', 1, 0, nil)
		status_is(mut s, c'signal 0 used up', q, 1, 0, 0, 0)
		mq_receive(q, s.buf, 8192, nil, nil)
		check(mut s, c'kind 7', mq_notify(q, set_signal_event(mut s, 7, usr1, 0)) == -C.EINVAL, 0)
		check(mut s, c'thread id kind', mq_notify(q, set_signal_event(mut s, 4, usr1, 0)) == -C.EINVAL, 0)
		check(mut s, c'signal 65', mq_notify(q, set_signal_event(mut s, 0, 65, 0)) == -C.EINVAL, 0)
		check(mut s, c'signal 64', mq_notify(q, set_signal_event(mut s, 0, 64, 0)) == 0 && mq_notify(q, nil) == 0, 0)
		check(mut s, c'signal -1', mq_notify(q, set_signal_event(mut s, 0, -1, 0)) == -C.EINVAL, 0)
		check(mut s, c'kind before descriptor', mq_notify(999, set_signal_event(mut s, 7, usr1, 0)) == -C.EINVAL, 0)
		check(mut s, c'fault', mq_notify(q, voidptr(8)) == -C.EFAULT, 0)
		check(mut s, c'bad descriptor', mq_notify(999, nil) == -C.EBADF, 0)
		check(mut s, c'not a queue', mq_notify(0, nil) == -C.EBADF, 0)
		// Closing any descriptor of the queue drops the owner's notification.
		mq_notify(q, set_signal_event(mut s, 0, usr1, 0))
		copy := C.dup(i32(q))
		C.close(copy)
		status_is(mut s, c'close drops it', q, 0, 0, 0, 0)
		// And so does the owner's exit.
		child = C.fork()
		if child == 0 {
			C._exit(if mq_notify(q, set_signal_event(mut s, 0, usr1, 0)) == 0 { 0 } else { 1 })
		}
		C.waitpid(child, status, 0)
		check(mut s, c'exit drops it', *status == 0 && mq_notify(q, set_signal_event(mut s, 0, usr1, 0)) == 0, *status)
		mq_notify(q, nil)
		// SIGEV_THREAD: a netlink socket gets the cookie, its last byte saying
		// why: 1 for a message, 2 for a removed notification.
		cookie := s.text + 200
		for i in 0 .. 32 {
			cookie[i] = u8(0x40 + i)
		}
		sock := C.socket(af_netlink, sock_raw, 0)
		check(mut s, c'netlink socket', sock >= 0, sock)
		mut sev := set_signal_event(mut s, 2, sock, u64(cookie))
		check(mut s, c'thread', mq_notify(q, sev) == 0, 0)
		status_is(mut s, c'status thread', q, 0, 2, 0, me)
		mq_send(q, c'm', 1, 0, nil)
		mut pfd := &C.pollfd(s.words + 2)
		pfd.fd = sock
		pfd.events = i16(C.POLLIN)
		pfd.revents = 0
		C.poll(pfd, 1, 2000)
		mut n := if pfd.revents & i16(C.POLLIN) != 0 { C.recv(sock, s.buf, 64, 0) } else { isize(-1) }
		check(mut s, c'woken cookie', n == 32 && C.memcmp(s.buf, cookie, 31) == 0 && s.buf[31] == 1, i64(n))
		status_is(mut s, c'thread used up', q, 1, 0, 0, 0)
		mq_receive(q, s.buf, 8192, nil, nil)
		check(mut s, c'thread again', mq_notify(q, sev) == 0 && mq_notify(q, nil) == 0, 0)
		pfd.revents = 0
		C.poll(pfd, 1, 2000)
		n = if pfd.revents & i16(C.POLLIN) != 0 { C.recv(sock, s.buf, 64, 0) } else { isize(-1) }
		check(mut s, c'removed cookie', n == 32 && C.memcmp(s.buf, cookie, 31) == 0 && s.buf[31] == 2, i64(n))
		check(mut s, c'thread on a queue', mq_notify(q, set_signal_event(mut s, 2, i32(q), u64(cookie))) == -C.ENOTSOCK, 0)
		pair := &i32(s.words + 8)
		C.socketpair(af_unix, sock_stream, 0, pair)
		check(mut s, c'thread on unix', mq_notify(q, set_signal_event(mut s, 2, pair[0], u64(cookie))) == -C.EINVAL, 0)
		check(mut s, c'thread bad fd', mq_notify(q, set_signal_event(mut s, 2, 999, u64(cookie))) == -C.EBADF, 0)
		check(mut s, c'thread cookie fault', mq_notify(q, set_signal_event(mut s, 2, sock, 8)) == -C.EFAULT, 0)
		check(mut s, c'thread then descriptor', mq_notify(999, set_signal_event(mut s, 2, sock, u64(cookie))) == -C.EBADF, 0)
		C.close(pair[0])
		C.close(pair[1])
		C.close(sock)
		C.close(i32(q))
		mq_unlink(c'qn')
	}
}

// As UID/GID 1000: permissions, limits and accounting.
fn unprivileged(mut s State) {
	unsafe {
		s.label = c'user'
		C.umask(0o022)
		shared := mq_open(c'qp', o_creat | o_rdwr, 0o666, nil)
		group := mq_open(c'qq', o_creat | o_rdwr, 0o660, nil)
		C.fstat(i32(group), s.st)
		mut status := &i32(s.words + 7)
		child := C.fork()
		if child == 0 {
			C.setgroups(0, nil)
			C.setgid(1000)
			C.setuid(1000)
			mut local := State{
				label: c'child'
				attr:  s.attr
				old:   s.old
				buf:   s.buf
				sev:   s.sev
				info:  s.info
				words: s.words
				text:  s.text
				st:    s.st
			}
			check(mut local, c'rdwr refused', mq_open(c'qp', o_rdwr, 0, nil) == -C.EACCES, 0)
			check(mut local, c'wronly refused', mq_open(c'qp', o_wronly, 0, nil) == -C.EACCES, 0)
			ro := mq_open(c'qp', o_rdonly, 0, nil)
			check(mut local, c'rdonly', ro >= 0, ro)
			check(mut local, c'unlink refused', mq_unlink(c'qp') == -C.EPERM, 0)
			check(mut local, c'excl first', mq_open(c'qp', o_creat | o_excl | o_rdwr, 0, nil) == -C.EEXIST, 0)
			check(mut local, c'group refused', mq_open(c'qq', o_rdonly, 0, nil) == -C.EACCES, 0)
			check(mut local, c'maxmsg 11', mq_open(c'u1', o_creat | o_rdwr, 0o600, set_attr(s.attr, 0, 11, 16, 0)) == -C.EINVAL, 0)
			check(mut local, c'msgsize 8193', mq_open(c'u1', o_creat | o_rdwr, 0o600, set_attr(s.attr, 0, 4, 8193, 0)) == -C.EINVAL, 0)
			mine := mq_open(c'u1', o_creat | o_rdwr, 0o600, set_attr(s.attr, 0, 10, 8192, 0))
			check(mut local, c'create', mine >= 0, mine)
			C.fstat(i32(mine), s.st)
			check(mut local, c'owner', s.st.st_uid == 1000 && s.st.st_gid == 1000 && s.st.st_mode == 0o100600, i64(s.st.st_uid))
			check(mut local, c'unlink own', mq_unlink(c'u1') == 0, 0)
			C.close(i32(mine))
			// RLIMIT_MSGQUEUE: 96 bytes a message plus the messages, counted
			// until the queue is freed.
			mut limit := &u64(s.words + 10)
			limit[0] = 1000
			limit[1] = 819200
			check(mut local, c'lower limit', C.syscall(isize(C.SYS_prlimit64), 0, rlimit_msgqueue, limit, nil) == 0, 0)
			first := mq_open(c'r1', o_creat | o_rdwr, 0o600, set_attr(s.attr, 0, 1, 904, 0))
			check(mut local, c'exactly the limit', first >= 0, first)
			check(mut local, c'one byte over', mq_open(c'r2', o_creat | o_rdwr, 0o600, set_attr(s.attr, 0, 1, 1, 0)) == -C.EMFILE, 0)
			mq_unlink(c'r1')
			check(mut local, c'unlinked still counts', mq_open(c'r2', o_creat | o_rdwr, 0o600, set_attr(s.attr, 0, 1, 1, 0)) == -C.EMFILE, 0)
			C.close(i32(first))
			second := mq_open(c'r2', o_creat | o_rdwr, 0o600, set_attr(s.attr, 0, 1, 1, 0))
			check(mut local, c'freed', second >= 0, second)
			C.close(i32(second))
			mq_unlink(c'r2')
			limit[0] = 819200
			C.syscall(isize(C.SYS_prlimit64), 0, rlimit_msgqueue, limit, nil)
			C.printf(c'LINUX MQUEUE CHILD: checks=%d failures=%d\n', local.checks, local.failures)
			C.fflush(nil)
			C._exit(if local.failures == 0 { 0 } else { 1 })
		}
		C.waitpid(child, status, 0)
		check(mut s, c'unprivileged child', *status == 0, *status)
		C.close(i32(shared))
		C.close(i32(group))
		mq_unlink(c'qp')
		mq_unlink(c'qq')
		C.umask(0)
		// Root may remove another user's queue.
		child2 := C.fork()
		if child2 == 0 {
			C.setgroups(0, nil)
			C.setgid(1000)
			C.setuid(1000)
			C._exit(if mq_open(c'u2', o_creat | o_rdwr, 0o600, nil) >= 0 { 0 } else { 1 })
		}
		C.waitpid(child2, status, 0)
		check(mut s, c'user queue made', *status == 0, *status)
		check(mut s, c'root removes it', mq_unlink(c'u2') == 0, 0)
	}
}

// queues_max: 256 queues in a namespace for users without CAP_SYS_RESOURCE.
fn queue_limit(mut s State) {
	unsafe {
		s.label = c'queues_max'
		mut status := &i32(s.words + 7)
		child := C.fork()
		if child == 0 {
			C.setgroups(0, nil)
			C.setgid(1000)
			C.setuid(1000)
			name := &char(C.malloc(32))
			mut made := 0
			mut last := i64(0)
			for i in 0 .. 300 {
				C.snprintf(name, 32, c'l%d', i)
				last = mq_open(name, o_creat | o_rdwr, 0o600, set_attr(s.attr, 0, 1, 1, 0))
				if last < 0 {
					break
				}
				C.close(i32(last))
				made++
			}
			C.printf(c'LINUX MQUEUE QUEUES: made=%d last=%ld\n', made, last)
			C.fflush(nil)
			C._exit(if made == 256 && last == -C.ENOSPC { 0 } else { 1 })
		}
		C.waitpid(child, status, 0)
		check(mut s, c'256 then ENOSPC', *status == 0, *status)
		extra := mq_open(c'root', o_creat | o_rdwr, 0o600, nil)
		check(mut s, c'privileged beyond', extra >= 0, extra)
		C.close(i32(extra))
		mq_unlink(c'root')
		name := &char(C.malloc(32))
		mut removed := 0
		for i in 0 .. 256 {
			C.snprintf(name, 32, c'l%d', i)
			if mq_unlink(name) == 0 {
				removed++
			}
		}
		check(mut s, c'all removed', removed == 256, removed)
		C.free(name)
	}
}

fn namespaces(mut s State) {
	unsafe {
		s.label = c'namespace'
		q := mq_open(c'qns', o_creat | o_rdwr, 0o600, nil)
		mut status := &i32(s.words + 7)
		child := C.fork()
		if child == 0 {
			mut code := 0
			if C.syscall(isize(C.SYS_unshare), clone_newipc) != 0 { code |= 1 }
			if mq_open(c'qns', o_rdwr, 0, nil) != -C.ENOENT { code |= 2 }
			inner := mq_open(c'qns', o_creat | o_excl | o_rdwr, 0o600, set_attr(s.attr, 0, 3, 8, 0))
			if inner < 0 { code |= 4 }
			if mq_send(inner, c'i', 1, 0, nil) != 0 { code |= 8 }
			// The parent's descriptor still reaches the parent's queue.
			if curmsgs(mut s, q) != 0 { code |= 16 }
			C._exit(code)
		}
		C.waitpid(child, status, 0)
		check(mut s, c'separate namespace', *status == 0, *status)
		check(mut s, c'own queue untouched', current(mut s, q) == 0 && s.old[1] == 10 && s.old[3] == 0, s.old[1])
		check(mut s, c'name still ours', mq_unlink(c'qns') == 0, 0)
		C.close(i32(q))
	}
}

@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		reference := argc > 1 && C.strcmp(argv[1], c'--reference') == 0
		C.mount(c'proc', c'/proc', c'proc', 0, nil)
		C.umask(0)
		mut s := State{
			attr:  &i64(C.malloc(64))
			old:   &i64(C.malloc(64))
			buf:   &u8(C.malloc(70000))
			sev:   &u8(C.malloc(64))
			info:  &u8(C.malloc(128))
			words: &i64(C.malloc(256))
			text:  &u8(C.malloc(256))
			st:    &C.stat(C.malloc(256))
		}
		C.memset(s.buf, 0, 70000)
		queue_limit(mut s)
		names(mut s)
		attributes(mut s)
		send_receive(mut s)
		blocking(mut s)
		attr_calls(mut s)
		notifications(mut s)
		unprivileged(mut s)
		namespaces(mut s)
		C.printf(c'LINUX MQUEUE SUMMARY: checks=%d failures=%d\n', s.checks, s.failures)
		if s.failures == 0 {
			C.puts(if reference { c'LINUX MQUEUE REFERENCE: PASS' } else { c'LINUX MQUEUE: PASS' })
		}
		C.fflush(nil)
		for {
			C.pause()
		}
	}
	return 0
}

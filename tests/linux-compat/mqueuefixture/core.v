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
#include <dirent.h>
#include <fcntl.h>
#include <poll.h>
#include <sched.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/resource.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/statfs.h>
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
	st_dev   u64
	st_ino   u64
	st_mode  u32
	st_nlink u64
	st_uid   u32
	st_gid   u32
	st_size  i64
}

struct C.statfs {
	f_type u64
	f_namelen i64
}

struct C.dirent {
	d_ino u64
	d_type u8
	d_name [256]char
}

struct C.sched_param {
	sched_priority i32
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
fn C.dup2(i32, i32) i32
fn C.execve(&char, &&char, &&char) i32
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
fn C.umount(&char) i32
fn C.umount2(&char, i32) i32
fn C.openat(i32, &char, i32, ...) i32
fn C.mkdir(&char, u32) i32
fn C.chmod(&char, u32) i32
fn C.unlink(&char) i32
fn C.statfs(&char, &C.statfs) i32
fn C.opendir(&char) voidptr
fn C.readdir(voidptr) &C.dirent
fn C.closedir(voidptr) i32
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
const notification_ready_fd = 100
const notification_proceed_fd = 101
const notification_queue_fd = 102
const clone_newns = 0x00020000

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

fn waiter_order(mut s State, sending bool) {
	unsafe {
		s.label = if sending { c'sender order' } else { c'receiver order' }
		q := mq_open(c'qw', o_creat | o_excl | o_rdwr, 0o600, set_attr(s.attr, 0, 1, 1, 0))
		check(mut s, c'open queue', q >= 0, q)
		if q < 0 { return }
		defer {
			C.close(i32(q))
			mq_unlink(c'qw')
		}
		if sending {
			check(mut s, c'fill queue', mq_send(q, c'x', 1, 0, nil) == 0, 0)
		}
		mut children := [4]i32{}
		for slot in 0 .. children.len {
			pid := C.fork()
			if pid == 0 {
				if slot == 3 {
					params := C.sched_param{sched_priority: 1}
					if C.syscall(isize(C.SYS_sched_setscheduler), 0, C.SCHED_FIFO, &params) != 0 {
						C.printf(c'LINUX MQUEUE FAIL: FIFO setup errno=%d\n', *C.__errno_location())
						C.fflush(nil)
						C._exit(3)
					}
				}
				timeout := deadline(mut s, 10000)
				if sending {
					// The lowest-ranked sender has the highest message priority.
					// A one-slot queue makes the admission order observable.
					message := `a` + u8(slot)
					C._exit(if mq_send(q, &message, 1, u64(4 - slot), timeout) == 0 { 0 } else { 1 })
				}
				got := mq_receive(q, s.buf, 1, nil, timeout)
				C._exit(if got == 1 && s.buf[0] == u8(c'4231'[slot]) { 0 } else { 2 })
			}
			children[slot] = pid
			check(mut s, c'waiter blocks', pid > 0 && wait_sleeping(pid), pid)
			if slot == 0 && pid > 0 {
				changed := result(C.syscall(isize(C.SYS_setpriority), C.PRIO_PROCESS, pid, 10))
				check(mut s, c'lower the blocked waiter priority', changed == 0, changed)
			}
		}
		if sending {
			for expected in [u8(`x`), `d`, `b`, `c`, `a`]! {
				got := mq_receive(q, s.buf, 1, nil, deadline(mut s, 2000))
				check(mut s, c'promote sender in scheduling order', got == 1 && s.buf[0] == expected,
					if got == 1 { i64(s.buf[0]) } else { got })
			}
		} else {
			for index in 0 .. children.len {
				message := `1` + u8(index)
				sent := mq_send(q, &message, 1, 0, deadline(mut s, 2000))
				check(mut s, c'offer message to one waiter', sent == 0, sent)
			}
		}
		for pid in children {
			if pid <= 0 { continue }
			mut status := i32(-1)
			check(mut s, c'waiter got its expected result', C.waitpid(pid, &status, 0) == pid && status == 0, status)
		}
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

fn exec_notification_owner(mut s State, q i32, ready i32, proceed i32) i32 {
	unsafe {
		if C.dup2(q, notification_queue_fd) != notification_queue_fd
			|| C.dup2(ready, notification_ready_fd) != notification_ready_fd
			|| C.dup2(proceed, notification_proceed_fd) != notification_proceed_fd { return 1 }
		C.close(q)
		C.close(ready)
		C.close(proceed)
		if mq_notify(notification_queue_fd, set_signal_event(mut s, 0, usr1, 0x1111)) != 0 { return 2 }
		mut args := [3]&char{}
		args[0] = c'mqueue-probe'
		args[1] = c'--notification-image'
		mut env := [1]&char{}
		if C.execve(c'/mnt/no-such-notification-image', &args[0], &env[0]) != -1
			|| *C.__errno_location() != C.ENOENT { return 3 }
		if mq_send(notification_queue_fd, c'f', 1, 0, nil) != 0 || take_usr1(mut s) != usr1
			|| *&u64(s.info + 24) != 0x1111 || mq_receive(notification_queue_fd, s.buf, 16, nil, nil) != 1 { return 4 }
		if mq_notify(notification_queue_fd, set_signal_event(mut s, 0, usr1, 0x2222)) != 0 { return 5 }
		C.execve(c'/proc/self/exe', &args[0], &env[0])
		return 6
	}
}

fn notification_after_exec(mut s State) i32 {
	unsafe {
		if C.write(notification_ready_fd, c'e', 1) != 1 || C.read(notification_proceed_fd, s.buf, 1) != 1 { return 7 }
		old := take_usr1(mut s)
		if mq_receive(notification_queue_fd, s.buf, 16, nil, nil) != 1 || s.buf[0] != `n` { return 8 }
		if mq_notify(notification_queue_fd, set_signal_event(mut s, 0, usr1, 0x3333)) != 0
			|| mq_send(notification_queue_fd, c'r', 1, 0, nil) != 0 { return 9 }
		if take_usr1(mut s) != usr1 || *&u64(s.info + 24) != 0x3333 { return 10 }
		return if old == -C.EAGAIN { 0 } else { 11 }
	}
}

fn notification_exec(mut s State) {
	unsafe {
		s.label = c'notification exec'
		q := mq_open(c'notify-image', o_creat | o_excl | o_rdwr | o_nonblock, 0o600, set_attr(s.attr, 0, 1, 16, 0))
		mut ready := [2]i32{}
		mut proceed := [2]i32{}
		prepared := q >= 0 && C.pipe(&ready[0]) == 0 && C.pipe(&proceed[0]) == 0
		check(mut s, c'create queue and pipes', prepared, q)
		child := if prepared { C.fork() } else { -1 }
		if child == 0 {
			C.close(ready[0])
			C.close(proceed[1])
			C._exit(exec_notification_owner(mut s, i32(q), ready[1], proceed[0]))
		}
		entered := if child > 0 {
			C.close(ready[1])
			C.close(proceed[0])
			C.read(ready[0], s.buf, 1) == 1 && s.buf[0] == `e`
		} else { false }
		check(mut s, c'failed exec preserved signal and replacement image started', entered, child)
		check(mut s, c'registration still owns queue across exec', entered
			&& mq_notify(q, set_signal_event(mut s, 0, usr1, 1)) == -C.EBUSY, 0)
		check(mut s, c'trigger pre-exec registration', entered && mq_send(q, c'n', 1, 0, nil) == 0
			&& C.write(proceed[1], c'g', 1) == 1, 0)
		if child > 0 {
			C.close(ready[0])
			C.close(proceed[1])
		}
		mut status := i32(-1)
		waited := child > 0 && C.waitpid(child, &status, 0) == child
		check(mut s, c'old signal dropped and new registration delivers', waited && status == 0, status)
		C.close(i32(q))
		mq_unlink(c'notify-image')
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

fn listed(directory &char, name &char, inode u64) bool {
	stream := C.opendir(directory)
	if stream == unsafe { nil } { return false }
	defer { C.closedir(stream) }
	for {
		entry := C.readdir(stream)
		if entry == unsafe { nil } { return false }
		if unsafe { C.strcmp(&entry.d_name[0], name) == 0 } {
			return entry.d_ino == inode && entry.d_type == C.DT_REG
		}
	}
	return false
}

fn mounted_namespace_child(mut s State) i32 {
	unsafe {
		if C.syscall(isize(C.SYS_unshare), clone_newipc) != 0 { return 1 }
		if mq_open(c'mounted-existing', o_rdonly, 0, nil) != -C.ENOENT { return 2 }
		inherited := C.open(c'/tmp/mq-view/mounted-existing', C.O_RDONLY)
		if inherited < 0 || curmsgs(mut s, inherited) != 0 { return 3 }
		C.close(inherited)
		if C.mount(c'none', c'/tmp/mq-child', c'mqueue', 0, nil) != 0 { return 4 }
		if C.open(c'/tmp/mq-child/mounted-existing', C.O_RDONLY) != -1 || *C.__errno_location() != C.ENOENT { return 5 }
		q := mq_open(c'mounted-existing', o_creat | o_rdwr, 0o600, set_attr(s.attr, 0, 2, 8, 0))
		view := C.open(c'/tmp/mq-child/mounted-existing', C.O_RDONLY)
		if q < 0 || view < 0 || current(mut s, view) != 0 || s.old[2] != 8 { return 6 }
		C.close(view)
		C.close(i32(q))
		if mq_unlink(c'mounted-existing') != 0 || C.umount(c'/tmp/mq-child') != 0 { return 7 }
		return 0
	}
}

fn mount_view(mut s State) {
	unsafe {
		s.label = c'mqueuefs'
		check(mut s, c'mount directories', C.mkdir(c'/tmp/mq-view', 0o755) == 0
			&& C.mkdir(c'/tmp/mq-child', 0o755) == 0, 0)
		q := mq_open(c'mounted-existing', o_creat | o_rdwr, 0o666, set_attr(s.attr, 0, 2, 16, 0))
		check(mut s, c'create before mounting', q >= 0, q)
		mounted := result(C.mount(c'none', c'/tmp/mq-view', c'mqueue', 0, nil))
		check(mut s, c'mount mqueue', mounted == 0, mounted)
		if mounted != 0 { return }
		view := &char(c'/tmp/mq-view/mounted-existing')
		root := C.open(c'/tmp/mq-view', C.O_RDONLY | C.O_DIRECTORY)
		check(mut s, c'sticky directory', root >= 0 && C.fstat(root, s.st) == 0
			&& s.st.st_mode == 0o41777 && s.st.st_nlink == 2, s.st.st_mode)
		check(mut s, c'directory rejects mq operations', current(mut s, root) == -C.EBADF, 0)
		check(mut s, c'directory read fails', C.read(root, s.buf, 1) == -1 && *C.__errno_location() == C.EISDIR, 0)
		C.close(root)
		mut filesystem := C.statfs{}
		check(mut s, c'filesystem identity', C.statfs(c'/tmp/mq-view', &filesystem) == 0
			&& filesystem.f_type == 0x19800202 && filesystem.f_namelen == 255, i64(filesystem.f_type))
		fd := C.open(view, C.O_RDWR)
		check(mut s, c'open pre-existing queue by path', fd >= 0, fd)
		if fd < 0 { return }
		check(mut s, c'queue inode', C.fstat(i32(q), s.st) == 0, 0)
		ino := s.st.st_ino
		dev := s.st.st_dev
		check(mut s, c'path shares queue identity', C.fstat(fd, s.st) == 0
			&& s.st.st_ino == ino && s.st.st_dev == dev, i64(s.st.st_ino))
		check(mut s, c'readdir includes queue inode', listed(c'/tmp/mq-view', c'mounted-existing', ino), 0)
		status_is(mut s, c'path fd exposes status', fd, 0, 0, 0, 0)
		check(mut s, c'path fd sends to mq descriptor', mq_send(fd, c'k', 1, 0, nil) == 0
			&& mq_receive(q, s.buf, 16, nil, nil) == 1 && s.buf[0] == `k`, 0)
		opath := C.open(view, C.O_PATH)
		check(mut s, c'path-only fd refuses mq operations', opath >= 0 && current(mut s, opath) == -C.EBADF, opath)
		C.close(opath)
		created := C.open(c'/tmp/mq-view/mounted-new', C.O_CREAT | C.O_EXCL | C.O_RDWR, 0o600)
		check(mut s, c'create queue by path with default attributes', created >= 0 && current(mut s, created) == 0
			&& s.old[1] == 10 && s.old[2] == 8192, created)
		other := mq_open(c'mounted-new', o_rdonly, 0, nil)
		check(mut s, c'mq_open sees path-created queue', other >= 0, other)
		check(mut s, c'mq_unlink removes pathname', mq_unlink(c'mounted-new') == 0
			&& C.open(c'/tmp/mq-view/mounted-new', C.O_RDONLY) == -1 && *C.__errno_location() == C.ENOENT, 0)
		C.close(i32(other))
		C.close(created)
		check(mut s, c'refuse subdirectories', C.mkdir(c'/tmp/mq-view/sub', 0o755) == -1
			&& *C.__errno_location() == C.EPERM, *C.__errno_location())
		fifo := result(C.syscall(isize(C.SYS_mknodat), C.AT_FDCWD, c'/tmp/mq-view/fifo', C.S_IFIFO | 0o600, 0))
		check(mut s, c'refuse FIFOs', fifo == -C.EPERM, fifo)
		mount_view_lifetime(mut s, q, fd, view)
	}
}

fn mount_view_lifetime(mut s State, q i64, fd i32, view &char) {
	unsafe {
		check(mut s, c'restrict queue directory', C.chmod(c'/tmp/mq-view', 0o1700) == 0, 0)
		mut child := C.fork()
		if child == 0 {
			if C.setgid(1000) != 0 || C.setuid(1000) != 0 { C._exit(1) }
			if mq_open(c'mounted-existing', o_rdonly, 0, nil) != -C.EACCES { C._exit(2) }
			if mq_unlink(c'mounted-existing') != -C.EACCES { C._exit(3) }
			if C.open(view, C.O_RDONLY) != -1 || *C.__errno_location() != C.EACCES { C._exit(4) }
			C._exit(0)
		}
		mut status := i32(-1)
		check(mut s, c'queue syscalls and pathname search honor directory mode', child > 0
			&& C.waitpid(child, &status, 0) == child && status == 0, status)
		check(mut s, c'restore queue directory', C.chmod(c'/tmp/mq-view', 0o1777) == 0, 0)
		child = C.fork()
		if child == 0 { C._exit(mounted_namespace_child(mut s)) }
		status = -1
		check(mut s, c'mount stays with its original IPC namespace', child > 0
			&& C.waitpid(child, &status, 0) == child && status == 0, status)
		check(mut s, c'mount a second view', C.mount(c'none', c'/tmp/mq-child', c'mqueue', 0, nil) == 0, 0)
		alias := C.open(c'/tmp/mq-child/mounted-existing', C.O_RDONLY)
		check(mut s, c'second view sees the same queue', alias >= 0 && current(mut s, alias) == 0 && s.old[2] == 16, alias)
		C.close(alias)
		check(mut s, c'remount only the second view read-only', C.mount(nil, c'/tmp/mq-child', nil,
			C.MS_BIND | C.MS_REMOUNT | C.MS_RDONLY | C.MS_NOEXEC | C.MS_NODEV, nil) == 0, 0)
		check(mut s, c'read-only view refuses writers', C.open(c'/tmp/mq-child/mounted-existing', C.O_RDWR) == -1
			&& *C.__errno_location() == C.EROFS, *C.__errno_location())
		check(mut s, c'unmount the second view', C.umount(c'/tmp/mq-child') == 0, 0)
		mask := C.open(c'/tmp/mq-mask', C.O_CREAT | C.O_RDWR, 0o600)
		check(mut s, c'file bind mount covers queue', mask >= 0
			&& C.mount(c'/tmp/mq-mask', view, nil, C.MS_BIND, nil) == 0, 0)
		check(mut s, c'covered pathname refuses unlink', C.unlink(view) == -1 && *C.__errno_location() == C.EBUSY, *C.__errno_location())
		check(mut s, c'covered queue refuses mq_unlink', mq_unlink(c'mounted-existing') == -C.EBUSY, 0)
		check(mut s, c'covered queue still has messages interface', current(mut s, q) == 0, 0)
		check(mut s, c'unmount covered queue', C.umount(view) == 0, 0)
		C.close(mask)
		C.unlink(c'/tmp/mq-mask')
		check(mut s, c'pathname unlink removes queue name', C.unlink(view) == 0
			&& mq_open(c'mounted-existing', o_rdonly, 0, nil) == -C.ENOENT, 0)
		check(mut s, c'open descriptor survives pathname unlink', C.fstat(fd, s.st) == 0 && s.st.st_nlink == 0
			&& mq_send(q, c'r', 1, 0, nil) == 0 && mq_receive(fd, s.buf, 16, nil, nil) == 1 && s.buf[0] == `r`, 0)
		C.close(fd)
		C.close(i32(q))
		check(mut s, c'unmount filesystem', C.umount(c'/tmp/mq-view') == 0, 0)
	}
}

fn make_surviving_namespace(mut s State) i32 {
	unsafe {
		if C.syscall(isize(C.SYS_unshare), clone_newipc) != 0 { return 1 }
		if C.mount(c'none', c'/tmp/mq-survive', c'mqueue', 0, nil) != 0 { return 2 }
		if C.setgid(1022) != 0 || C.setuid(1022) != 0 { return 3 }
		q := mq_open(c'surviving-queue', o_creat | o_excl | o_rdwr, 0o644, set_attr(s.attr, 0, 1, 904, 0))
		if q < 0 || mq_send(q, c'z', 1, 6, nil) != 0 || C.close(i32(q)) != 0 { return 4 }
		return 0
	}
}

fn use_copied_queue_mount(mut s State, ready i32, proceed i32) i32 {
	unsafe {
		if C.syscall(isize(C.SYS_unshare), clone_newns) != 0 { return 1 }
		if C.write(ready, c'r', 1) != 1 || C.read(proceed, s.buf, 1) != 1 { return 2 }
		dir := C.open(c'/tmp/mq-survive-bind', C.O_RDONLY | C.O_DIRECTORY)
		if dir < 0 { return 3 }
		if C.umount2(c'/tmp/mq-survive-bind', C.MNT_DETACH) != 0 { return 4 }
		// A maintenance pass can now try to retire the lazy attachment.
		sleep_ms(6500)
		fd := C.openat(dir, c'surviving-queue', C.O_RDONLY)
		if fd < 0 || C.fstat(fd, s.st) != 0 || s.st.st_nlink != 1 { return 5 }
		if mq_receive(fd, s.buf, 904, nil, deadline(mut s, 1000)) != 1 || s.buf[0] != `z` { return 6 }
		if C.close(fd) != 0 || C.close(dir) != 0 { return 7 }
		return 0
	}
}

fn check_namespace_quota(mut s State, uid u32, expect_busy bool) i32 {
	unsafe {
		if C.setgid(uid) != 0 || C.setuid(uid) != 0 { return 1 }
		mut limit := &u64(s.words + 10)
		limit[0] = 1000
		limit[1] = 819200
		if C.syscall(isize(C.SYS_prlimit64), 0, rlimit_msgqueue, limit, nil) != 0 { return 2 }
		attempts := if expect_busy { 1 } else { 80 }
		for _ in 0 .. attempts {
			q := mq_open(c'quota-after-mount', o_creat | o_excl | o_rdwr, 0o600, set_attr(s.attr, 0, 1, 904, 0))
			if q >= 0 {
				if mq_unlink(c'quota-after-mount') != 0 || C.close(i32(q)) != 0 { return 3 }
				return if expect_busy { 4 } else { 0 }
			}
			if q != -C.EMFILE { return 5 }
			if expect_busy { return 0 }
			sleep_ms(250)
		}
		return 6
	}
}

fn surviving_mount(mut s State) {
	unsafe {
		s.label = c'mqueuefs namespace lifetime'
		check(mut s, c'mount directories', C.mkdir(c'/tmp/mq-survive', 0o755) == 0
			&& C.mkdir(c'/tmp/mq-survive-bind', 0o755) == 0, 0)
		mut child := C.fork()
		if child == 0 { C._exit(make_surviving_namespace(mut s)) }
		mut status := i32(-1)
		check(mut s, c'queue creator and namespace exited', child > 0
			&& C.waitpid(child, &status, 0) == child && status == 0, status)
		check(mut s, c'foreign queue syscall sees no name', mq_open(c'surviving-queue', o_rdonly, 0, nil) == -C.ENOENT, 0)
		fd := C.open(c'/tmp/mq-survive/surviving-queue', C.O_RDONLY)
		check(mut s, c'surviving mount retains the queue and message', fd >= 0 && curmsgs(mut s, fd) == 1, fd)
		C.close(fd)
		created := C.open(c'/tmp/mq-survive/new-queue', C.O_CREAT | C.O_EXCL | C.O_RDWR, 0o600)
		check(mut s, c'defunct namespace refuses creation', created == -1 && *C.__errno_location() == C.EACCES, created)
		child = C.fork()
		if child == 0 { C._exit(check_namespace_quota(mut s, 1022, true)) }
		status = -1
		check(mut s, c'surviving queue still charged to its creator', child > 0
			&& C.waitpid(child, &status, 0) == child && status == 0, status)
		check(mut s, c'bind the surviving directory', C.mount(c'/tmp/mq-survive', c'/tmp/mq-survive-bind', nil,
			C.MS_BIND, nil) == 0, 0)
		check(mut s, c'detach original mount', C.umount(c'/tmp/mq-survive') == 0, 0)
		mut ready := [2]i32{}
		mut proceed := [2]i32{}
		pipes := C.pipe(&ready[0]) == 0 && C.pipe(&proceed[0]) == 0
		child = if pipes { C.fork() } else { -1 }
		if child == 0 {
			C.close(ready[0])
			C.close(proceed[1])
			C._exit(use_copied_queue_mount(mut s, ready[1], proceed[0]))
		}
		copied := if child > 0 {
			C.close(ready[1])
			C.close(proceed[0])
			C.read(ready[0], s.buf, 1) == 1
		} else { false }
		check(mut s, c'copy mount namespace', copied, 0)
		check(mut s, c'detach bind from original namespace', C.umount(c'/tmp/mq-survive-bind') == 0, 0)
		if child > 0 {
			if copied { C.write(proceed[1], c'p', 1) }
			C.close(proceed[1])
			C.close(ready[0])
		}
		status = -1
		check(mut s, c'copied mount and lazily detached directory fd keep names', child > 0
			&& C.waitpid(child, &status, 0) == child && status == 0, status)
		child = C.fork()
		if child == 0 { C._exit(check_namespace_quota(mut s, 1022, false)) }
		status = -1
		check(mut s, c'last detached view releases queue charge', child > 0
			&& C.waitpid(child, &status, 0) == child && status == 0, status)
	}
}

fn make_bound_queue(mut s State, uid u32, name &char) i32 {
	unsafe {
		if C.setgid(uid) != 0 || C.setuid(uid) != 0 { return 1 }
		q := mq_open(name, o_creat | o_excl | o_rdwr, 0o644, set_attr(s.attr, 0, 1, 904, 0))
		if q < 0 || mq_send(q, c'b', 1, 2, nil) != 0 || C.close(i32(q)) != 0 { return 2 }
		return 0
	}
}

fn use_copied_file_bind(mut s State, ready i32, proceed i32) i32 {
	unsafe {
		if C.syscall(isize(C.SYS_unshare), clone_newns) != 0 { return 1 }
		if C.write(ready, c'r', 1) != 1 || C.read(proceed, s.buf, 1) != 1 { return 2 }
		fd := C.open(c'/tmp/mq-file-alias', C.O_RDONLY)
		if fd < 0 || C.fstat(fd, s.st) != 0 || s.st.st_nlink != 0 { return 3 }
		if C.umount2(c'/tmp/mq-file-alias', C.MNT_DETACH) != 0 { return 4 }
		sleep_ms(6500)
		child := C.fork()
		if child == 0 { C._exit(check_namespace_quota(mut s, 1023, true)) }
		mut status := i32(-1)
		if child < 0 || C.waitpid(child, &status, 0) != child || status != 0 { return 5 }
		if mq_receive(fd, s.buf, 904, nil, deadline(mut s, 1000)) != 1 || s.buf[0] != `b` { return 6 }
		return if C.close(fd) == 0 { 0 } else { 7 }
	}
}

fn check_queue_quota(mut s State, description &char, uid u32, busy bool) {
	unsafe {
		child := C.fork()
		if child == 0 { C._exit(check_namespace_quota(mut s, uid, busy)) }
		mut status := i32(-1)
		check(mut s, description, child > 0 && C.waitpid(child, &status, 0) == child && status == 0, status)
	}
}

fn bound_file_lifetime(mut s State) {
	unsafe {
		s.label = c'mqueuefs file bind lifetime'
		check(mut s, c'create queue mount', C.mkdir(c'/tmp/mq-file-view', 0o755) == 0
			&& C.mount(c'none', c'/tmp/mq-file-view', c'mqueue', 0, nil) == 0, 0)
		alias := C.open(c'/tmp/mq-file-alias', C.O_CREAT | C.O_EXCL | C.O_WRONLY, 0o600)
		check(mut s, c'create regular bind target', alias >= 0 && C.close(alias) == 0, alias)
		mut child := C.fork()
		if child == 0 { C._exit(make_bound_queue(mut s, 1023, c'bound-file')) }
		mut status := i32(-1)
		check(mut s, c'create charged queue', child > 0 && C.waitpid(child, &status, 0) == child && status == 0, status)
		check(mut s, c'bind individual queue', C.mount(c'/tmp/mq-file-view/bound-file', c'/tmp/mq-file-alias', nil,
			C.MS_BIND, nil) == 0, 0)
		check(mut s, c'unlink original name', mq_unlink(c'bound-file') == 0
			&& mq_open(c'bound-file', o_rdonly, 0, nil) == -C.ENOENT, 0)
		check_queue_quota(mut s, c'bind alone retains unlinked queue charge', 1023, true)
		mut ready := [2]i32{}
		mut proceed := [2]i32{}
		pipes := C.pipe(&ready[0]) == 0 && C.pipe(&proceed[0]) == 0
		child = if pipes { C.fork() } else { -1 }
		if child == 0 {
			C.close(ready[0])
			C.close(proceed[1])
			C._exit(use_copied_file_bind(mut s, ready[1], proceed[0]))
		}
		copied := if child > 0 {
			C.close(ready[1])
			C.close(proceed[0])
			C.read(ready[0], s.buf, 1) == 1
		} else { false }
		check(mut s, c'copy mount namespace', copied, 0)
		check(mut s, c'unmount original bind', C.umount(c'/tmp/mq-file-alias') == 0, 0)
		if child > 0 {
			if copied { C.write(proceed[1], c'p', 1) }
			C.close(proceed[1])
			C.close(ready[0])
		}
		status = -1
		check(mut s, c'copied bind and lazy fd keep queue usable', child > 0
			&& C.waitpid(child, &status, 0) == child && status == 0, status)
		check_queue_quota(mut s, c'detach and last close release bound queue charge', 1023, false)

		child = C.fork()
		if child == 0 { C._exit(make_bound_queue(mut s, 1024, c'covered-file')) }
		status = -1
		check(mut s, c'create charged cover target', child > 0 && C.waitpid(child, &status, 0) == child && status == 0, status)
		check(mut s, c'bind regular file over queue', C.mount(c'/tmp/mq-file-alias', c'/tmp/mq-file-view/covered-file', nil,
			C.MS_BIND, nil) == 0, 0)
		check(mut s, c'covered name cannot be unlinked', mq_unlink(c'covered-file') == -C.EBUSY, 0)
		check(mut s, c'unmount covering file and unlink queue', C.umount(c'/tmp/mq-file-view/covered-file') == 0
			&& mq_unlink(c'covered-file') == 0, 0)
		check_queue_quota(mut s, c'uncover and unlink release queue charge', 1024, false)
		check(mut s, c'unmount queue filesystem', C.umount(c'/tmp/mq-file-view') == 0, 0)
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
		if argc > 1 && C.strcmp(argv[1], c'--notification-image') == 0 {
			C._exit(notification_after_exec(mut s))
		}
		C.memset(s.buf, 0, 70000)
		queue_limit(mut s)
		names(mut s)
		attributes(mut s)
		send_receive(mut s)
		blocking(mut s)
		waiter_order(mut s, true)
		waiter_order(mut s, false)
		attr_calls(mut s)
		notifications(mut s)
		notification_exec(mut s)
		notification_buffer(mut s)
		unprivileged(mut s)
		namespaces(mut s)
		mount_view(mut s)
		surviving_mount(mut s)
		bound_file_lifetime(mut s)
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

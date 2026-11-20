// SPDX-License-Identifier: GPL-2.0-or-later
// pidfd_getfd(2): shared descriptions, close-on-exec copies, data through a
// child's pipe, O_PATH descriptors, argument words, error order, exiting and
// reaped processes, unprivileged access and EMFILE.
// The same ELF runs as Vinix's init and, given --reference, under Linux.
module pidfdgetfdfixture

#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <stdio.h>
#include <string.h>
#include <sys/prctl.h>
#include <sys/resource.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

struct C.rlimit {
mut:
	rlim_cur u64
	rlim_max u64
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
fn C.getpid() i32
fn C.pipe(&i32) i32
fn C.read(i32, voidptr, usize) isize
fn C.write(i32, voidptr, usize) isize
fn C.close(i32) i32
fn C.dup(i32) i32
fn C.open(&char, i32, ...) i32
fn C.fcntl(i32, i32, ...) i32
fn C.strcmp(&char, &char) i32
fn C.memcmp(voidptr, voidptr, usize) i32
fn C.setgroups(usize, voidptr) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.prctl(i32, ...) i32
fn C.kill(i32, i32) i32
fn C.setrlimit(i32, &C.rlimit) i32
fn C.getrlimit(i32, &C.rlimit) i32
fn C.waitid(i32, u32, voidptr, i32) i32
fn C.alloca(usize) voidptr

struct State {
mut:
	checks   int
	failures int
}

struct Result {
	value isize
	err   int
}

fn call(number isize, a u64, b u64, c u64) Result {
	unsafe {
		errno_ptr := C.__errno_location()
		*errno_ptr = 0
		value := C.syscall(number, a, b, c)
		return Result{value, if value < 0 { *errno_ptr } else { 0 }}
	}
}

fn pidfd_open(pid i32) i32 {
	return i32(C.syscall(isize(C.SYS_pidfd_open), pid, 0))
}

fn getfd(pidfd i32, target i64, flags u64) Result {
	return call(isize(C.SYS_pidfd_getfd), u64(pidfd), u64(target), flags)
}

fn same_file(a i32, b i32) bool {
	pid := C.getpid()
	return C.syscall(isize(C.SYS_kcmp), pid, pid, 0, a, b) == 0
}

fn check(mut s State, label &char, ok bool, got Result) {
	s.checks++
	if !ok {
		s.failures++
		C.printf(c'LINUX PIDFDGETFD FAIL: %s value=%ld errno=%d\n', label, got.value, got.err)
	}
}

fn fails(mut s State, label &char, got Result, err int) {
	check(mut s, label, got.value == -1 && got.err == err, got)
}

fn own_process(mut s State) {
	unsafe {
		mut ends := [2]i32{}
		C.pipe(&ends[0])
		me := pidfd_open(C.getpid())
		copy := getfd(me, i64(ends[0]), 0)
		check(mut s, c'self copy', copy.value >= 0, copy)
		fd := i32(copy.value)
		check(mut s, c'shares description', same_file(fd, ends[0]), copy)
		check(mut s, c'close on exec', C.fcntl(fd, C.F_GETFD) == C.FD_CLOEXEC, copy)
		C.fcntl(ends[0], C.F_SETFL, C.O_NONBLOCK)
		check(mut s, c'status flags shared', C.fcntl(fd, C.F_GETFL) & C.O_NONBLOCK != 0, copy)
		C.close(fd)
		// Only the low 32 bits of each argument count.
		wide := getfd(me, i64((u64(3) << 32) | u64(ends[1])), u64(5) << 32)
		check(mut s, c'argument words', wide.value >= 0 && same_file(i32(wide.value), ends[1]), wide)
		if wide.value >= 0 { C.close(i32(wide.value)) }
		path := C.open(c'/', C.O_PATH)
		path_copy := getfd(me, i64(path), 0)
		check(mut s, c'o_path copy', path_copy.value >= 0
			&& C.fcntl(i32(path_copy.value), C.F_GETFL) & C.O_PATH != 0, path_copy)
		if path_copy.value >= 0 { C.close(i32(path_copy.value)) }
		C.close(path)
		closed := C.dup(ends[0])
		C.close(closed)
		fails(mut s, c'flags first', getfd(closed, i64(closed), 1), C.EINVAL)
		fails(mut s, c'any flag', getfd(me, i64(ends[0]), 0x80000000), C.EINVAL)
		fails(mut s, c'closed pidfd', getfd(closed, i64(ends[0]), 0), C.EBADF)
		fails(mut s, c'not a pidfd', getfd(ends[1], i64(ends[0]), 0), C.EBADF)
		fails(mut s, c'closed target', getfd(me, i64(closed), 0), C.EBADF)
		fails(mut s, c'negative target', getfd(me, -1, 0), C.EBADF)
		fails(mut s, c'huge target', getfd(me, 0x7ffffff0, 0), C.EBADF)
		// EMFILE when no number is free below the limit.
		child := C.fork()
		if child == 0 {
			lowest := C.open(c'/', C.O_RDONLY)
			C.close(lowest)
			mut limit := C.rlimit{}
			C.getrlimit(C.RLIMIT_NOFILE, &limit)
			limit.rlim_cur = u64(lowest)
			C.setrlimit(C.RLIMIT_NOFILE, &limit)
			r := getfd(me, i64(ends[0]), 0)
			C._exit(if r.value == -1 && r.err == C.EMFILE { 0 } else { 1 })
		}
		mut status := i32(0)
		C.waitpid(child, &status, 0)
		check(mut s, c'emfile', status == 0, Result{isize(status), 0})
		C.close(me)
		C.close(ends[0])
		C.close(ends[1])
	}
}

fn other_process(mut s State) {
	unsafe {
		mut ready := [2]i32{}
		mut resume := [2]i32{}
		C.pipe(&ready[0])
		C.pipe(&resume[0])
		child := C.fork()
		if child == 0 {
			mut data := [2]i32{}
			C.pipe(&data[0])
			C.write(data[1], c'from child', 10)
			mut number := u8(data[0])
			C.write(ready[1], &number, 1)
			mut byte := u8(0)
			C.read(resume[0], &byte, 1)
			C._exit(0)
		}
		mut number := u8(0)
		C.read(ready[0], &number, 1)
		handle := pidfd_open(child)
		taken := getfd(handle, i64(number), 0)
		check(mut s, c'child descriptor', taken.value >= 0, taken)
		buffer := C.alloca(16)
		got := C.read(i32(taken.value), buffer, 16)
		check(mut s, c'child data', got == 10 && C.memcmp(buffer, c'from child', 10) == 0,
			Result{got, 0})
		C.close(i32(taken.value))
		fails(mut s, c'child closed target', getfd(handle, 999, 0), C.EBADF)
		mut byte := u8(1)
		C.write(resume[1], &byte, 1)
		// An exited child that is not reaped yet has no descriptors.
		C.waitid(C.P_PID, u32(child), C.alloca(128), C.WEXITED | C.WNOWAIT)
		fails(mut s, c'zombie', getfd(handle, i64(number), 0), C.ESRCH)
		C.waitpid(child, nil, 0)
		fails(mut s, c'reaped', getfd(handle, i64(number), 0), C.ESRCH)
		C.close(handle)
		for fd in [ready[0], ready[1], resume[0], resume[1]]! { C.close(fd) }
	}
}

// A process may take only from what it may trace: as UID 1000 its own child,
// never root's processes.
fn unprivileged(mut s State) {
	unsafe {
		root_pid := C.getpid()
		child := C.fork()
		if child == 0 {
			C.setgroups(0, nil)
			C.setgid(1000)
			C.setuid(1000)
			C.prctl(C.PR_SET_DUMPABLE, 1, 0, 0, 0)
			mut local := State{}
			root := pidfd_open(root_pid)
			fails(mut local, c'root process', getfd(root, 0, 0), C.EPERM)
			// Permission is checked before the descriptor.
			fails(mut local, c'root before target', getfd(root, 999, 0), C.EPERM)
			mut ready := [2]i32{}
			C.pipe(&ready[0])
			grandchild := C.fork()
			if grandchild == 0 {
				C.prctl(C.PR_SET_DUMPABLE, 1, 0, 0, 0)
				mut byte := u8(1)
				C.write(ready[1], &byte, 1)
				for { C.pause() }
			}
			mut byte := u8(0)
			C.read(ready[0], &byte, 1)
			own := pidfd_open(grandchild)
			taken := getfd(own, i64(ready[1]), 0)
			check(mut local, c'own child', taken.value >= 0 && same_file(i32(taken.value), ready[1]), taken)
			C.kill(grandchild, 9)
			C.waitpid(grandchild, nil, 0)
			C.printf(c'LINUX PIDFDGETFD CHILD: checks=%d failures=%d\n', local.checks, local.failures)
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
		own_process(mut s)
		other_process(mut s)
		unprivileged(mut s)
		C.printf(c'LINUX PIDFDGETFD SUMMARY: checks=%d failures=%d\n', s.checks, s.failures)
		if s.failures == 0 {
			C.puts(if reference { c'LINUX PIDFDGETFD REFERENCE: PASS' } else { c'LINUX PIDFDGETFD: PASS' })
		}
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}

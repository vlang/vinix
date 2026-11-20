// SPDX-License-Identifier: GPL-2.0-or-later
// kcmp(2): shared-object identity, ordering, argument words and error order,
// for the calling process, a thread, a fork child and an unprivileged child.
// The same ELF runs as Vinix's init and, given --reference, under Linux.
module kcmpfixture

#include <alloca.h>
#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <pthread.h>
#include <sched.h>
#include <stdio.h>
#include <sys/epoll.h>
#include <sys/prctl.h>
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
fn C.getpid() i32
fn C.pipe(&i32) i32
fn C.read(i32, voidptr, usize) isize
fn C.write(i32, voidptr, usize) isize
fn C.close(i32) i32
fn C.dup(i32) i32
fn C.dup2(i32, i32) i32
fn C.fcntl(i32, i32, ...) i32
fn C.open(&char, i32, ...) i32
fn C.epoll_create1(i32) i32
fn C.epoll_ctl(i32, i32, i32, voidptr) i32
fn C.setgroups(usize, voidptr) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.prctl(i32, ...) i32
fn C.unshare(i32) i32
fn C.kill(i32, i32) i32
struct C.pthread_t {}

fn C.alloca(usize) voidptr
fn C.pthread_create(&C.pthread_t, voidptr, fn (voidptr) voidptr, voidptr) i32
fn C.pthread_join(C.pthread_t, voidptr) i32
fn C.strcmp(&char, &char) i32

struct C.epoll_event {
mut:
	events u32
}

const kcmp_file = u64(0)
const kcmp_vm = u64(1)
const kcmp_files = u64(2)
const kcmp_fs = u64(3)
const kcmp_sighand = u64(4)
const kcmp_io = u64(5)
const kcmp_sysvsem = u64(6)
const kcmp_epoll_tfd = u64(7)

struct Slot {
mut:
	efd  u32
	tfd  u32
	toff u32
}

struct State {
mut:
	checks   int
	failures int
}

struct Result {
	value isize
	err   int
}

fn kcmp(pid1 u64, pid2 u64, kind u64, idx1 u64, idx2 u64) Result {
	unsafe {
		errno_ptr := C.__errno_location()
		*errno_ptr = 0
		value := C.syscall(isize(C.SYS_kcmp), pid1, pid2, kind, idx1, idx2)
		return Result{value, if value < 0 { *errno_ptr } else { 0 }}
	}
}

fn check(mut s State, label &char, ok bool, got Result) {
	s.checks++
	if !ok {
		s.failures++
		C.printf(c'LINUX KCMP FAIL: %s value=%ld errno=%d\n', label, got.value, got.err)
	}
}

fn equal(mut s State, label &char, got Result) {
	check(mut s, label, got.value == 0 && got.err == 0, got)
}

// Distinct objects order as 1 or 2; the reversed comparison gives the other.
fn distinct(mut s State, label &char, p1 int, p2 int, kind u64, a u64, b u64) isize {
	forward := kcmp(u64(p1), u64(p2), kind, a, b)
	backward := kcmp(u64(p2), u64(p1), kind, b, a)
	check(mut s, label, (forward.value == 1 || forward.value == 2) && backward.value == 3 - forward.value,
		forward)
	return forward.value
}

fn failure(mut s State, label &char, got Result, wanted int) {
	check(mut s, label, got.value == -1 && got.err == wanted, got)
}

fn byte_read(fd i32) u8 {
	mut value := u8(0)
	unsafe { C.read(fd, &value, 1) }
	return value
}

fn byte_write(fd i32, value u8) {
	mut byte := value
	unsafe { C.write(fd, &byte, 1) }
}

struct ThreadShare {
mut:
	ready [2]i32
	resume [2]i32
	tid   i32
}

fn thread_main(arg voidptr) voidptr {
	mut share := unsafe { &ThreadShare(arg) }
	share.tid = i32(C.syscall(isize(C.SYS_gettid)))
	byte_write(share.ready[1], 1)
	// The main thread compares, then asks this thread for its own fs view.
	if byte_read(share.resume[0]) == 2 {
		code := C.unshare(i32(C.CLONE_FS))
		byte_write(share.ready[1], if code == 0 { u8(1) } else { u8(0) })
		byte_read(share.resume[0])
	}
	return unsafe { nil }
}

fn same_process(mut s State, pid int, r int, w int, root1 int, root2 int) {
	unsafe {
	p := u64(pid)
	equal(mut s, c'file self', kcmp(p, p, kcmp_file, u64(r), u64(r)))
	d := C.dup(r)
	equal(mut s, c'file dup', kcmp(p, p, kcmp_file, u64(r), u64(d)))
	c := C.fcntl(r, C.F_DUPFD_CLOEXEC, 100)
	equal(mut s, c'file dupfd', kcmp(p, p, kcmp_file, u64(c), u64(r)))
	ab := distinct(mut s, c'file reopened', pid, pid, kcmp_file, u64(root1), u64(root2))
	bc := distinct(mut s, c'file pipe ends', pid, pid, kcmp_file, u64(root2), u64(w))
	ac := distinct(mut s, c'file third', pid, pid, kcmp_file, u64(root1), u64(w))
	// One total order: a<b and b<c imply a<c, and so on.
	s.checks++
	if ab == bc && ac != ab {
		s.failures++
		C.puts(c'LINUX KCMP FAIL: order not transitive')
	}
	// fd, pid and type words are C ints; their upper register halves are ignored.
	equal(mut s, c'file idx width', kcmp(p, p, kcmp_file, (u64(1) << 32) | u64(r), u64(d)))
	equal(mut s, c'pid width', kcmp((u64(0xdead) << 32) | p, (u64(1) << 32) | p, kcmp_file, u64(r), u64(r)))
	equal(mut s, c'type width', kcmp(p, p, (u64(7) << 32) | kcmp_file, u64(r), u64(d)))
	closed := C.dup(r)
	C.close(closed)
	failure(mut s, c'file closed first', kcmp(p, p, kcmp_file, u64(closed), u64(r)), C.EBADF)
	failure(mut s, c'file closed second', kcmp(p, p, kcmp_file, u64(r), u64(closed)), C.EBADF)
	failure(mut s, c'file huge', kcmp(p, p, kcmp_file, u64(r), 0x7ffffff0), C.EBADF)
	for kind in [kcmp_vm, kcmp_files, kcmp_fs, kcmp_sighand, kcmp_io, kcmp_sysvsem]! {
		equal(mut s, c'self object', kcmp(p, p, kind, 99, 77))
	}
	for kind in [8, -1, 0x7fffffff]! {
		failure(mut s, c'unknown type', kcmp(p, p, u64(u32(kind)), 0, 0), C.EINVAL)
	}
	for bad in [0, -1, 0x3fffffff]! {
		failure(mut s, c'missing first', kcmp(u64(u32(bad)), p, kcmp_file, u64(r), u64(r)), C.ESRCH)
		failure(mut s, c'missing second', kcmp(p, u64(u32(bad)), kcmp_file, u64(r), u64(r)), C.ESRCH)
		// A missing task is reported before an unknown type.
		failure(mut s, c'missing before type', kcmp(u64(u32(bad)), p, 99, 0, 0), C.ESRCH)
	}
	C.close(d)
	C.close(c)
	}
}

fn epoll_cases(mut s State, pid int, r int, w int) {
	unsafe {
	p := u64(pid)
	ep := C.epoll_create1(0)
	mut event := C.epoll_event{events: u32(C.EPOLLIN)}
	C.epoll_ctl(ep, C.EPOLL_CTL_ADD, r, &event)
	C.epoll_ctl(ep, C.EPOLL_CTL_ADD, w, &event)
	mut slot := Slot{u32(ep), u32(r), 0}
	address := u64(voidptr(&slot))
	equal(mut s, c'epoll target', kcmp(p, p, kcmp_epoll_tfd, u64(r), address))
	d := C.dup(r)
	equal(mut s, c'epoll target dup', kcmp(p, p, kcmp_epoll_tfd, u64(d), address))
	other := kcmp(p, p, kcmp_epoll_tfd, u64(w), address)
	file_order := kcmp(p, p, kcmp_file, u64(w), u64(r))
	check(mut s, c'epoll other', (other.value == 1 || other.value == 2) && other.value == file_order.value,
		other)
	slot.toff = 1
	failure(mut s, c'epoll offset', kcmp(p, p, kcmp_epoll_tfd, u64(r), address), C.ENOENT)
	slot = Slot{u32(ep), 999, 0}
	failure(mut s, c'epoll unregistered', kcmp(p, p, kcmp_epoll_tfd, u64(r), address), C.ENOENT)
	slot = Slot{u32(r), u32(r), 0}
	failure(mut s, c'epoll not a set', kcmp(p, p, kcmp_epoll_tfd, u64(r), address), C.EINVAL)
	closed := C.dup(r)
	C.close(closed)
	slot = Slot{u32(closed), u32(r), 0}
	failure(mut s, c'epoll closed set', kcmp(p, p, kcmp_epoll_tfd, u64(r), address), C.EBADF)
	slot = Slot{u32(ep), u32(r), 0}
	failure(mut s, c'epoll closed file', kcmp(p, p, kcmp_epoll_tfd, u64(closed), address), C.EBADF)
	// The slot is read before either descriptor is resolved.
	failure(mut s, c'epoll slot fault', kcmp(p, p, kcmp_epoll_tfd, u64(closed), 1), C.EFAULT)
	// A registration belongs to its number and description: replacing the
	// number's description keeps the old one, and adding it again makes a
	// second registration of the same number.
	moved := C.dup(r)
	C.epoll_ctl(ep, C.EPOLL_CTL_ADD, moved, &event)
	C.dup2(w, moved)
	C.epoll_ctl(ep, C.EPOLL_CTL_ADD, moved, &event)
	slot = Slot{u32(ep), u32(moved), 0}
	first_r := kcmp(p, p, kcmp_epoll_tfd, u64(r), address)
	first_w := kcmp(p, p, kcmp_epoll_tfd, u64(w), address)
	slot.toff = 1
	second_r := kcmp(p, p, kcmp_epoll_tfd, u64(r), address)
	second_w := kcmp(p, p, kcmp_epoll_tfd, u64(w), address)
	slot.toff = 2
	failure(mut s, c'epoll third registration', kcmp(p, p, kcmp_epoll_tfd, u64(r), address), C.ENOENT)
	check(mut s, c'epoll reused number', (first_r.value == 0) != (second_r.value == 0)
		&& (first_w.value == 0) != (second_w.value == 0) && (first_r.value == 0) != (first_w.value == 0), first_r)
	C.close(moved)
	C.close(d)
	C.close(ep)
	}
}

fn thread_cases(mut s State, pid int, r int) {
	unsafe {
	mut share := &ThreadShare(C.alloca(usize(sizeof(ThreadShare))))
	*share = ThreadShare{}
	C.pipe(&share.ready[0])
	C.pipe(&share.resume[0])
	handle := &C.pthread_t(C.alloca(usize(sizeof(C.pthread_t))))
	C.pthread_create(handle, nil, thread_main, share)
	byte_read(share.ready[0])
	p := u64(pid)
	t := u64(share.tid)
	for kind in [kcmp_vm, kcmp_files, kcmp_fs, kcmp_sighand, kcmp_io, kcmp_sysvsem]! {
		equal(mut s, c'thread object', kcmp(p, t, kind, 0, 0))
	}
	equal(mut s, c'thread file', kcmp(p, t, kcmp_file, u64(r), u64(r)))
	byte_write(share.resume[1], 2)
	unshared := byte_read(share.ready[0])
	check(mut s, c'thread unshare', unshared == 1, Result{0, 0})
	distinct(mut s, c'thread fs', pid, share.tid, kcmp_fs, 0, 0)
	equal(mut s, c'thread vm after fs', kcmp(p, t, kcmp_vm, 0, 0))
	byte_write(share.resume[1], 3)
	C.pthread_join(*handle, nil)
	for fd in [share.ready[0], share.ready[1], share.resume[0], share.resume[1]]! { C.close(fd) }
	}
}

fn fork_cases(mut s State, pid int, r int, root1 int) {
	unsafe {
	mut ready := [2]i32{}
	mut resume := [2]i32{}
	C.pipe(&ready[0])
	C.pipe(&resume[0])
	child := C.fork()
	if child == 0 {
		child_root := C.open(c'/', C.O_RDONLY | C.O_DIRECTORY)
		byte_write(ready[1], u8(child_root))
		byte_read(resume[0])
		C._exit(0)
	}
	own := int(byte_read(ready[0]))
	p := u64(pid)
	c := u64(child)
	equal(mut s, c'fork inherited file', kcmp(p, c, kcmp_file, u64(r), u64(r)))
	distinct(mut s, c'fork own file', pid, child, kcmp_file, u64(root1), u64(own))
	for kind in [kcmp_vm, kcmp_files, kcmp_fs, kcmp_sighand]! {
		distinct(mut s, c'fork object', pid, child, kind, 0, 0)
	}
	equal(mut s, c'fork io', kcmp(p, c, kcmp_io, 0, 0))
	// The thread made earlier gave this process an undo list; the child has none
	// until unshare drops this one.
	distinct(mut s, c'fork sysvsem after thread', pid, child, kcmp_sysvsem, 0, 0)
	check(mut s, c'unshare sysvsem', C.unshare(i32(C.CLONE_SYSVSEM)) == 0, Result{0, 0})
	equal(mut s, c'fork sysvsem after unshare', kcmp(p, c, kcmp_sysvsem, 0, 0))
	// The child shares the set it inherited, and with it the registrations.
	ep := C.epoll_create1(0)
	mut event := C.epoll_event{events: u32(C.EPOLLIN)}
	C.epoll_ctl(ep, C.EPOLL_CTL_ADD, r, &event)
	C.close(ep)
	byte_write(resume[1], 1)
	mut status := i32(0)
	C.waitpid(child, &status, 0)
	failure(mut s, c'reaped child', kcmp(p, c, kcmp_vm, 0, 0), C.ESRCH)
	for fd in [ready[0], ready[1], resume[0], resume[1]]! { C.close(fd) }
	}
}

// An unprivileged process may compare only what it may inspect: itself and
// processes of exactly its own dumpable credentials, never root's.
fn unprivileged_cases(mut s State, pid int, r int) {
	unsafe {
	mut ready := [2]i32{}
	mut resume := [2]i32{}
	C.pipe(&ready[0])
	C.pipe(&resume[0])
	mut children := [2]i32{}
	for index in 0 .. 2 {
		children[index] = C.fork()
		if children[index] == 0 {
			C.setgroups(0, nil)
			C.setgid(1000)
			C.setuid(1000)
			C.prctl(C.PR_SET_DUMPABLE, 1, 0, 0, 0)
			if index == 0 {
				byte_write(ready[1], 1)
				byte_read(resume[0])
				C._exit(0)
			}
			byte_read(ready[0])
			mut local := State{}
			me := u64(C.getpid())
			sibling := u64(children[0])
			root := u64(pid)
			equal(mut local, c'unprivileged self', kcmp(me, me, kcmp_vm, 0, 0))
			equal(mut local, c'unprivileged own file', kcmp(me, me, kcmp_file, u64(r), u64(r)))
			sibling_vm := kcmp(me, sibling, kcmp_vm, 0, 0)
			check(mut local, c'unprivileged sibling', sibling_vm.value == 1 || sibling_vm.value == 2,
				sibling_vm)
			equal(mut local, c'unprivileged sibling file', kcmp(me, sibling, kcmp_file, u64(r), u64(r)))
			failure(mut local, c'unprivileged root first', kcmp(root, me, kcmp_vm, 0, 0), C.EPERM)
			failure(mut local, c'unprivileged root second', kcmp(me, root, kcmp_file, u64(r), u64(r)),
				C.EPERM)
			// Permission is checked before the type, and after the lookup.
			failure(mut local, c'unprivileged before type', kcmp(me, root, 99, 0, 0), C.EPERM)
			failure(mut local, c'unprivileged lookup first', kcmp(0, root, 99, 0, 0), C.ESRCH)
			C.printf(c'LINUX KCMP CHILD: checks=%d failures=%d\n', local.checks, local.failures)
			C.fflush(nil)
			byte_write(resume[1], 1)
			C._exit(if local.failures == 0 { 0 } else { 1 })
		}
	}
	// Root may inspect both.
	equal(mut s, c'root unprivileged io', kcmp(u64(pid), u64(children[0]), kcmp_io, 0, 0))
	for index in 0 .. 2 {
		mut status := i32(0)
		C.waitpid(children[1 - index], &status, 0)
		check(mut s, c'unprivileged child', status == 0, Result{isize(status), 0})
	}
	for fd in [ready[0], ready[1], resume[0], resume[1]]! { C.close(fd) }
	}
}

@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
	reference := argc > 1 && C.strcmp(argv[1], c'--reference') == 0
	mut s := State{}
	pid := C.getpid()
	mut pipe_fds := [2]i32{}
	C.pipe(&pipe_fds[0])
	r := int(pipe_fds[0])
	w := int(pipe_fds[1])
	root1 := C.open(c'/', C.O_RDONLY | C.O_DIRECTORY)
	root2 := C.open(c'/', C.O_RDONLY | C.O_DIRECTORY)
	same_process(mut s, pid, r, w, root1, root2)
	epoll_cases(mut s, pid, r, w)
	thread_cases(mut s, pid, r)
	fork_cases(mut s, pid, r, root1)
	unprivileged_cases(mut s, pid, r)
	C.printf(c'LINUX KCMP SUMMARY: checks=%d failures=%d\n', s.checks, s.failures)
	if s.failures == 0 {
		C.puts(if reference { c'LINUX KCMP REFERENCE: PASS' } else { c'LINUX KCMP: PASS' })
	}
	C.fflush(nil)
	for { C.pause() }
	return 0
	}
}

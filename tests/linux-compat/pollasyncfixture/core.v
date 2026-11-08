// SPDX-License-Identifier: GPL-2.0-or-later
module pollasyncfixture

#include <alloca.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <stdio.h>
#include <sys/epoll.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

struct Poll { mut: fd i32 events i16 revents i16 }
fn C.alloca(uint) voidptr
fn C.open(&char, i32, ...) i32
fn C.close(i32) i32
fn C.dup(i32) i32
fn C.read(i32, voidptr, uint) int
fn C.pread(i32, voidptr, uint, i64) int
fn C.write(i32, voidptr, uint) int
fn C.poll(voidptr, uint, i32) i32
fn C.epoll_create1(i32) i32
fn C.epoll_ctl(i32, i32, i32, voidptr) i32
fn C.epoll_wait(i32, voidptr, i32, i32) i32
fn C.printf(&char, ...) i32
fn C.fflush(voidptr) i32
fn C.__errno_location() &i32
fn C._exit(i32)
fn C.fork() i32
fn C.pipe(&i32) i32
fn C.waitpid(i32, &i32, i32) i32
fn C.syscall(int, ...) int
fn C.mkdir(&char, u32) i32
fn C.mount(&char, &char, &char, u64, voidptr) i32
fn C.alarm(u32) u32
fn C.pause() i32

fn require(good bool, stage int) {
	if good { return }
	C.printf(c'LINUX POLLASYNC FAIL: stage=%d errno=%d\n', stage, unsafe { *C.__errno_location() })
	C.fflush(unsafe { nil }); C._exit(1)
}
fn ready(fd i32, mask i16) i16 {
	mut p := Poll{fd: fd, events: mask, revents: -1}
	ret := C.poll(voidptr(&p), 1, 0)
	require(ret == 0 || ret == 1, 1)
	require(ret == (if p.revents == 0 { 0 } else { 1 }), 2)
	return p.revents
}
fn acknowledge(fd i32) {
	mut bytes := [768]u8{}
	require(C.pread(fd, &bytes[0], sizeof(bytes), 0) > 0, 3)
}
fn watch(fd i32, mask u32) i32 {
	unsafe {
		ep := C.epoll_create1(C.EPOLL_CLOEXEC)
		require(ep >= 0, 4)
		bytes := &u64(C.alloca(32))
		for i in 0 .. 4 { bytes[i] = 0 }
		(&u32(bytes))[0] = mask
		require(C.epoll_ctl(ep, C.EPOLL_CTL_ADD, fd, voidptr(bytes)) == 0, 5)
		return ep
	}
}
fn events(ep i32, timeout i32) i32 {
	mut bytes := [4]u64{}
	return C.epoll_wait(ep, voidptr(&bytes[0]), 1, timeout)
}
fn subscription(path &char, mask i16) {
	a := C.open(path, C.O_RDONLY)
	b := C.open(path, C.O_RDONLY)
	require(a >= 0 && b >= 0, 6)
	require(ready(a, 0x147) == mask && ready(b, 0x147) == mask, 7)
	epa := watch(a, u32(mask))
	require(events(epa, 0) == 1, 8)
	acknowledge(a)
	require(ready(a, 0x147) == 0 && ready(b, 0x147) == mask, 9)
	require(events(epa, 0) == 0, 10)
	duplicate := C.dup(b)
	require(duplicate >= 0, 11)
	acknowledge(duplicate)
	require(ready(b, 0x147) == 0, 12)
	C.close(duplicate); C.close(epa); C.close(a); C.close(b)
}
fn put(path &char, value &char, length uint) {
	fd := C.open(path, C.O_WRONLY)
	require(fd >= 0, 13)
	require(C.write(fd, value, length) == int(length), 14)
	C.close(fd)
}
fn cgroup() {
	require(C.mkdir(c'/tmp/pollasync', 0o700) == 0, 15)
	require(C.mount(c'none', c'/tmp/pollasync', c'cgroup2', 0, unsafe { nil }) == 0, 16)
	require(C.mkdir(c'/tmp/pollasync/tasks', 0o700) == 0, 17)
	subscription(c'/tmp/pollasync/tasks/resource.pressure', 3)
	a := C.open(c'/tmp/pollasync/tasks/resource.pressure', C.O_RDONLY)
	require(a >= 0, 18)
	acknowledge(a)
	ep := watch(a, 3)
	require(events(ep, 0) == 0, 19)
	put(c'/tmp/pollasync/tasks/pids.max', c'0', 1)
	require(events(ep, 2500) == 1, 20)
	require(ready(a, 3) == 3, 21)
	acknowledge(a)
	require(events(ep, 0) == 0 && ready(a, 3) == 0, 22)
	put(c'/tmp/pollasync/tasks/pids.max', c'max', 3)
	require(events(ep, 2500) == 1, 23)
	acknowledge(a)
	require(events(ep, 0) == 0, 24)
	C.close(ep); C.close(a)
}
fn pidfd() {
	mut pipes := [2]i32{}
	require(C.pipe(&pipes[0]) == 0, 25)
	pid := C.fork()
	require(pid >= 0, 26)
	if pid == 0 {
		C.close(pipes[1])
		mut byte := u8(0)
		if C.read(pipes[0], &byte, 1) != 1 { C._exit(90) }
		C._exit(42)
	}
	C.close(pipes[0])
	fd := i32(C.syscall(int(C.SYS_pidfd_open), pid, 0))
	require(fd >= 0, 27)
	ep := watch(fd, 0x41)
	require(ready(fd, 0x145) == 0 && events(ep, 0) == 0, 28)
	byte := u8(1)
	require(C.write(pipes[1], &byte, 1) == 1, 29)
	C.close(pipes[1])
	require(events(ep, 2500) == 1, 30)
	require(ready(fd, 0x145) == 0x41, 31)
	mut status := i32(0)
	require(C.waitpid(pid, &status, 0) == pid && status == (42 << 8), 32)
	require(ready(fd, 0x145) == 0x51 && events(ep, 0) == 1, 33)
	C.close(ep); C.close(fd)
}
fn virtual_file(path &char) {
	fd := C.open(path, C.O_RDONLY)
	require(fd >= 0 && ready(fd, 0x145) == 0x145, 34)
	ep := watch(fd, 5)
	require(events(ep, 0) == 1, 35)
	C.close(ep); C.close(fd)
}
@[export: 'main']
pub fn run() i32 {
	C.alarm(60)
	subscription(c'/proc/vmpressure', 1)
	C.printf(c'LINUX POLLASYNC CASE: vmpressure PASS\n')
	cgroup()
	C.printf(c'LINUX POLLASYNC CASE: cgroup PASS\n')
	virtual_file(c'/proc/version')
	virtual_file(c'/sys/devices/system/cpu/online')
	virtual_file(c'/tmp/pollasync/tasks/pids.max')
	C.printf(c'LINUX POLLASYNC CASE: virtual-files PASS\n')
	pidfd()
	C.printf(c'LINUX POLLASYNC CASE: pidfd PASS\n')
	C.printf(c'LINUX POLLASYNC SUMMARY: cases=4 failures=0\nLINUX POLLASYNC: PASS\n')
	C.fflush(unsafe { nil }); C.alarm(0)
	for { C.pause() }
	return 0
}

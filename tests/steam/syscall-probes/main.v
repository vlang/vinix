// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

#include <unistd.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/wait.h>
#include <sys/sem.h>
#include <sys/eventfd.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/epoll.h>
#include <netinet/in.h>
#include <time.h>
#include <sys/mount.h>
#include <sys/reboot.h>
#include <sys/ioctl.h>
#include <net/if.h>

fn C.semget(i32, i32, i32) i32
fn C.semctl(i32, i32, i32, ...int) i32
fn C.semop(i32, &C.sembuf, usize) i32
fn C.eventfd(u32, i32) i32
fn C.socketpair(i32, i32, i32, &i32) i32
fn C.socket(i32, i32, i32) i32
fn C.bind(i32, &C.sockaddr, u32) i32
fn C.pread(i32, voidptr, usize, i64) isize
fn C.mincore(voidptr, usize, &u8) i32
fn C.epoll_create1(i32) i32
fn C.epoll_ctl(i32, i32, i32, &C.epoll_event) i32
fn C.epoll_wait(i32, &C.epoll_event, i32, i32) i32
fn C.recvmsg(i32, &C.msghdr, i32) isize
fn C.getsockname(i32, &C.sockaddr, &u32) i32
fn C.sendto(i32, voidptr, usize, i32, &C.sockaddr, u32) isize
fn C.htonl(u32) u32
fn C.clock_gettime(i32, &C.timespec) i32
fn C.syscall(i64, ...voidptr) isize
fn C.alarm(u32) u32
fn C.usleep(u32) i32
fn C.unlink(&char) i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C.kill(i32, i32) i32
fn C._exit(i32)
fn C.mount(&char, &char, &char, usize, voidptr) i32
fn C.reboot(i32) i32
fn C.ioctl(i32, u64, ...voidptr) i32

struct C.ifreq {
mut:
	ifr_name  [16]u8
	ifr_flags i16
}

struct C.sembuf {
	sem_num u16
	sem_op  i16
	sem_flg i16
}

struct C.iovec {
	iov_base voidptr
	iov_len  usize
}

struct C.msghdr {
mut:
	msg_name       voidptr
	msg_namelen    u32
	msg_iov        &C.iovec
	msg_iovlen     usize
	msg_control    voidptr
	msg_controllen usize
	msg_flags      i32
}

struct C.timespec {
	tv_sec  i64
	tv_nsec i64
}

struct C.sockaddr {}

struct C.epoll_event {
	events u32
}

struct C.in_addr {
	s_addr u32
}

struct C.sockaddr_in {
	sin_family u16
	sin_port   u16
	sin_addr   C.in_addr
}

fn require(condition bool, text string) ! { if !condition { return error(text) } }

fn semaphores() ! {
	id := C.semget(0, 1, 0o1600)
	require(id >= 0, 'semget')!
	mut removed := false
	defer { if !removed { C.semctl(id, 0, 0) } }
	require(C.semctl(id, 0, 16, 0) == 0, 'semctl SETVAL')!
	child := C.fork()
	require(child >= 0, 'fork')!
	if child == 0 {
		C.alarm(5)
		operation := C.sembuf{ sem_op: -1 }
		result := C.semop(id, unsafe { &operation }, 1)
		C._exit(if result == 0 { 0 } else { 1 })
	}
	mut waited := false
	defer {
		if !waited {
			C.kill(child, 9)
			mut status := i32(0)
			C.waitpid(child, &status, 0)
		}
	}
	C.usleep(100000)
	operation := C.sembuf{ sem_op: 1 }
	require(C.semop(id, unsafe { &operation }, 1) == 0, 'semop wake')!
	mut status := i32(0)
	require(C.waitpid(child, &status, 0) == child, 'waitpid')!
	waited = true
	require(status == 0, 'semaphore child exit')!
	require(C.semctl(id, 0, 12) == 0, 'semctl GETVAL')!
	require(C.semctl(id, 0, 0) == 0, 'semctl IPC_RMID')!
	removed = true
}

fn lazy_buffer(path string) ! {
	mut counter := C.eventfd(0, 0)
	require(counter >= 0, 'eventfd')!
	defer { if counter >= 0 { C.close(counter) } }
	one := u64(1)
	require(C.write(counter, &one, 8) == 8, 'eventfd write')!
	mut returned := u64(0)
	require(C.read(counter, &returned, 8) == 8 && returned == 1, 'eventfd read')!
	require(C.close(counter) == 0, 'eventfd close')!
	counter = -1
	mut fd := C.open(path.str, 0)
	require(fd >= 0, 'lazy-buffer input')!
	defer { if fd >= 0 { C.close(fd) } }
	mut area := unsafe { C.mmap(nil, 65536, 3, 0x22, -1, 0) }
	require(area != voidptr(-1), 'anonymous mmap')!
	defer { if area != voidptr(-1) { unsafe { C.munmap(area, 65536) } } }
	// Do not touch the mapping before pread: the kernel must fault its pages in.
	require(C.pread(fd, area, 65536, 0) > 0, 'pread into unfaulted mapping')!
	require(unsafe { C.munmap(area, 65536) } == 0, 'lazy-buffer munmap')!
	$if steam_probe_sdk ? {
		mut pages := [16]u8{}
		require(C.mincore(area, 65536, unsafe { &pages[0] }) < 0 && C.errno == C.ENOMEM, 'SDK lazy-buffer mapping retirement')!
	}
	area = voidptr(-1)
	require(C.close(fd) == 0, 'lazy-buffer close')!
	fd = -1
}

fn unix_hangup() ! {
	mut pair := [i32(0), i32(0)]!
	require(C.socketpair(1, 1, 0, &pair[0]) == 0, 'socketpair')!
	defer {
		if pair[0] >= 0 { C.close(pair[0]) }
		if pair[1] >= 0 { C.close(pair[1]) }
	}
	flags := C.fcntl(pair[0], 3, 0)
	require(flags >= 0 && C.fcntl(pair[0], 4, flags | 2048) == 0, 'nonblocking socket')!
	mut poller := C.epoll_create1(0)
	require(poller >= 0, 'epoll_create1')!
	defer { if poller >= 0 { C.close(poller) } }
	mut event := C.epoll_event{ events: 1 }
	require(C.epoll_ctl(poller, 1, pair[0], &event) == 0, 'epoll_ctl')!
	require(C.write(pair[1], c'abc', 3) == 3, 'socket write')!
	require(C.close(pair[1]) == 0, 'socket close')!
	pair[1] = -1
	require(C.epoll_wait(poller, &event, 1, 1000) > 0, 'hangup epoll wake')!
	mut payload := [u8(0), u8(0)]!
	vector := C.iovec{ iov_base: unsafe { &payload[0] }, iov_len: 2 }
	for expected in ['ab', 'c', ''] {
		mut message := C.msghdr{ msg_iov: unsafe { &vector }, msg_iovlen: 1 }
		length := C.recvmsg(pair[0], &message, 0)
		require(length == expected.len, 'recvmsg drain/EOF length')!
		for index, byte in expected.bytes() { require(payload[index] == byte, 'recvmsg payload')! }
	}
	require(C.close(poller) == 0, 'epoll close')!
	poller = -1
	require(C.close(pair[0]) == 0, 'Unix reader close')!
	pair[0] = -1
}

fn ipv4_ancillary() ! {
	mut reader := C.socket(2, 2, 0)
	require(reader >= 0, 'UDP reader')!
	defer { if reader >= 0 { C.close(reader) } }
	mut writer := C.socket(2, 2, 0)
	require(writer >= 0, 'UDP writer')!
	defer { if writer >= 0 { C.close(writer) } }
	mut address := C.sockaddr_in{ sin_family: 2, sin_addr: C.in_addr{ s_addr: C.htonl(0x7f000001) } }
	require(C.bind(reader, unsafe { &C.sockaddr(&address) }, 16) == 0, 'UDP bind')!
	mut width := u32(16)
	require(C.getsockname(reader, unsafe { &C.sockaddr(&address) }, &width) == 0 && width == 16, 'UDP port')!
	require(C.sendto(writer, c'x', 1, 0, unsafe { &C.sockaddr(&address) }, width) == 1, 'UDP sendto')!
	mut payload := [8]u8{}
	mut control := [128]u8{}
	vector := C.iovec{ iov_base: unsafe { &payload[0] }, iov_len: 8 }
	mut message := C.msghdr{ msg_iov: unsafe { &vector }, msg_iovlen: 1, msg_control: unsafe { &control[0] }, msg_controllen: 128, msg_flags: -1 }
	require(C.recvmsg(reader, &message, 0) == 1 && payload[0] == `x`, 'UDP recvmsg')!
	require(message.msg_controllen == 0 && message.msg_flags == 0, 'recvmsg spare control/flags')!
	require(C.close(reader) == 0, 'UDP reader close')!
	reader = -1
	require(C.close(writer) == 0, 'UDP writer close')!
	writer = -1
}

fn ppoll_sleep() ! {
	mut before := C.timespec{}
	mut after := C.timespec{}
	period := C.timespec{ tv_nsec: 150000000 }
	require(C.clock_gettime(1, &before) == 0, 'monotonic start')!
	number := $if arm64 { i64(73) } $else { i64(271) }
	// Linux ppoll: no fds, 150 ms, no signal mask, 8-byte kernel sigset size.
	require(C.syscall(number, voidptr(0), voidptr(0), unsafe { &period }, voidptr(0), voidptr(8)) == 0, 'empty ppoll')!
	require(C.clock_gettime(1, &after) == 0, 'monotonic finish')!
	require((after.tv_sec - before.tv_sec) * 1000000000 + after.tv_nsec - before.tv_nsec >= 100000000, 'ppoll slept less than 100 ms')!
}

fn shared_mapping(path string) ! {
	length := usize(26214416)
	mut fd := C.open(path.str, 0o302, 0o600)
	require(fd >= 0, 'exclusive shared-memory file')!
	mut named := true
	defer {
		if fd >= 0 { C.close(fd) }
		if named { C.unlink(path.str) }
	}
	require(C.ftruncate(fd, u64(length)) == 0, 'shared-memory ftruncate')!
	mut area := unsafe { C.mmap(nil, length, 3, 1, fd, 0) }
	require(area != voidptr(-1), 'shared mmap')!
	defer { if area != voidptr(-1) { unsafe { C.munmap(area, length) } } }
	mut bytes := unsafe { &u8(area) }
	unsafe {
		bytes[0] = 0x5a
		bytes[int(length) - 1] = 0xa5
	}
	require(unsafe { bytes[0] == 0x5a && bytes[int(length) - 1] == 0xa5 }, 'shared-memory endpoints')!
	require(unsafe { C.munmap(area, length) } == 0, 'shared-memory munmap')!
	$if steam_probe_sdk ? {
		mut pages := [6401]u8{}
		require(C.mincore(area, length, unsafe { &pages[0] }) < 0 && C.errno == C.ENOMEM, 'SDK shared-memory mapping retirement')!
	}
	area = voidptr(-1)
	require(C.close(fd) == 0, 'shared-memory close')!
	fd = -1
	require(C.unlink(path.str) == 0, 'shared-memory unlink')!
	named = false
}

fn run(arguments []string) ! {
	$if steam_probe_sdk ? {
		if arguments == ['--sdk-boot'] {
			require(C.mount(c'tmpfs', c'/dev/shm', c'tmpfs', 0, unsafe { nil }) == 0, 'SDK tmpfs')!
			require(C.mount(c'proc', c'/proc', c'proc', 0, unsafe { nil }) == 0, 'SDK procfs')!
			control := C.socket(2, 2, 0)
			require(control >= 0, 'SDK network control')!
			mut request := C.ifreq{}
			unsafe {
				request.ifr_name[0] = `l`
				request.ifr_name[1] = `o`
			}
			require(C.ioctl(control, 0x8913, &request) == 0, 'SDK loopback flags')!
			request.ifr_flags |= 1
			require(C.ioctl(control, 0x8914, &request) == 0, 'SDK loopback up')!
			require(C.close(control) == 0, 'SDK network control close')!
			before := os.ls('/proc/self/fd')!.len
			for _ in 0 .. 10 {
				for name in ['semaphores', 'lazy-buffer', 'unix-hangup', 'ipv4-ancillary', 'ppoll',
					'shared-mapping'] {
					run([name])!
					println('STEAM SDK PASS: ' + name)
				}
				require(os.ls('/proc/self/fd')!.len == before, 'SDK descriptor retention')!
				require(!os.exists('/dev/shm/vinix-steam-shm-probe'), 'SDK mapping file retention')!
				mut status := i32(0)
				require(C.waitpid(-1, &status, 1) < 0, 'SDK unreaped semaphore child')!
			}
			println('NATIVE STEAM SDK: PASS')
			C.reboot(0x4321fedc)
			return error('SDK poweroff returned')
		}
	}
	if arguments.len == 0 {
		return error('expected semaphores|lazy-buffer|unix-hangup|ipv4-ancillary|ppoll|shared-mapping')
	}
	if arguments == ['--help'] {
		println('steam-syscall-probe semaphores|lazy-buffer|unix-hangup|ipv4-ancillary|ppoll|shared-mapping [probe input/path]')
		return
	}
	if arguments.len > 2 { return error('too many probe arguments') }
	if arguments.len == 2 && arguments[0] !in ['lazy-buffer', 'shared-mapping'] {
		return error('probe takes no path argument')
	}
	match arguments[0] {
		'semaphores' { semaphores()! }
		'lazy-buffer' {
			lazy_buffer(if arguments.len == 2 { arguments[1] } else { '/usr/bin/qemu-i386' })!
		}
		'unix-hangup' { unix_hangup()! }
		'ipv4-ancillary' { ipv4_ancillary()! }
		'ppoll' { ppoll_sleep()! }
		'shared-mapping' {
			shared_mapping(if arguments.len == 2 {
				arguments[1]
			} else {
				'/dev/shm/vinix-steam-shm-probe'
			})!
		}
		else { return error('unknown Steam syscall probe') }
	}
}

fn main() {
	run(os.args[1..]) or {
		eprintln(err)
		exit(1)
	}
}

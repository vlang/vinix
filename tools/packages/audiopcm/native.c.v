// SPDX-License-Identifier: GPL-2.0-or-later
module audiopcm

import time

#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include <poll.h>
#include <fcntl.h>
#include <signal.h>
#include <unistd.h>
$if linux {
	#include <sys/syscall.h>
}
#define vinix_pcm_address sockaddr_un
#define vinix_pcm_poll(fds, count, timeout) poll((struct pollfd *)(fds), (count), (timeout))
#define vinix_pcm_bind(fd, address, length) bind((fd), (const struct sockaddr *)(address), (length))
#define vinix_pcm_connect(fd, address, length) connect((fd), (const struct sockaddr *)(address), (length))
#define vinix_pcm_send send
#define vinix_pcm_recv recv

struct C.vinix_pcm_address { mut: sun_family u16 sun_path [108]char }
struct Poll { mut: fd i32 events i16 revents i16 }
struct Credentials { mut: pid i32 uid u32 gid u32 }
struct LoginIdentity { mut: uid u32 session u32 }
fn C.vinix_pcm_poll(voidptr, u64, int) int
fn C.socket(int, int, int) int
fn C.socketpair(int, int, int, &i32) int
fn C.vinix_pcm_bind(int, voidptr, u32) int
fn C.vinix_pcm_connect(int, voidptr, u32) int
fn C.listen(int, int) int
fn C.accept(int, voidptr, voidptr) int
fn C.getsockopt(int, int, int, voidptr, &u32) int
fn C.setsockopt(int, int, int, voidptr, u32) int
fn C.vinix_pcm_send(i32, voidptr, usize, i32) isize
fn C.vinix_pcm_recv(i32, voidptr, usize, i32) isize
fn C.read(int, voidptr, usize) isize
fn C.write(int, voidptr, usize) isize
fn C.close(int) int
fn C.open(&char, int, ...int) int
fn C.openat(int, &char, int, ...int) int
fn C.fstat(int, &C.stat) int
fn C.fstatat(int, &char, &C.stat, int) int
fn C.fcntl(int, int, ...int) int
fn C.unlinkat(int, &char, int) int
fn C.fchmodat(int, &char, u32, int) int
fn C.ioctl(int, u64, ...voidptr) int
fn C.fork() int
fn C._exit(int)
fn C.kill(int, int) int
fn C.waitpid(int, &i32, int) int
fn C.getpid() int
fn C.geteuid() int
fn C.syscall(i64, ...voidptr) i64
fn C.getdtablesize() int
$if !linux { fn C.getpeereid(int, &u32, &u32) int }

fn peer(fd int) !Credentials {
	$if linux {
		mut value := Credentials{}
		mut size := u32(sizeof(Credentials))
		if C.getsockopt(fd, C.SOL_SOCKET, C.SO_PEERCRED, &value, &size) != 0 || size != sizeof(Credentials) { return error('audio peer identity unavailable') }
		return value
	} $else {
		mut uid := u32(0)
		mut gid := u32(0)
		if C.getpeereid(fd, &uid, &gid) != 0 { return error('audio peer identity unavailable') }
		return Credentials{ uid: uid, gid: gid }
	}
}

// Vinix caches this immutable login label with the socket's peer identity.
// A PID lookup cannot authenticate it: a departed creator's PID may be reused.
fn peer_login(fd int) !LoginIdentity {
	mut value := LoginIdentity{}
	mut size := u32(sizeof(LoginIdentity))
	if C.getsockopt(fd, C.SOL_SOCKET, 0x564c, &value, &size) != 0
		|| size != 8 || value.uid == 0xffff_ffff || value.session == 0 {
		return error('audio peer has no immutable kernel login identity')
	}
	return value
}

fn active_login(identity LoginIdentity, uid u32, seat u32) bool {
	return uid != 0 && uid != 0xffff_ffff && seat != 0
		&& identity.uid == uid && identity.session == seat
}

fn address(path string) !C.vinix_pcm_address {
	if path.len == 0 || path.len >= 100 || path.contains('\x00') { return error('invalid private audio endpoint') }
	mut result := C.vinix_pcm_address{ sun_family: u16(C.AF_UNIX) }
	unsafe { vmemcpy(&result.sun_path[0], path.str, path.len) }
	return result
}

fn nonblocking(fd int) ! {
	flags := C.fcntl(fd, C.F_GETFL)
	if flags < 0 || C.fcntl(fd, C.F_SETFL, flags | C.O_NONBLOCK) != 0 || C.fcntl(fd, C.F_SETFD, C.FD_CLOEXEC) != 0 { return error('cannot bound audio connection') }
}

fn worker_isolation(listener int, guard int, runtime int, path string) ! {
	$if linux {
		// Preserve only these descriptors, including when the caller's table
		// contains descriptors above 1024. No ambient app/service fd survives.
		mut keep := [listener, guard, runtime]!
		for i in 0 .. 3 { for j in i + 1 .. 3 { if keep[j] < keep[i] { value := keep[i]; keep[i] = keep[j]; keep[j] = value } } }
		mut first := u32(0)
		for fd in keep {
			if first < u32(fd) && C.syscall(i64(C.SYS_close_range), first, u32(fd - 1), u32(0)) != 0 { return error('cannot close inherited audio-worker descriptors') }
			first = u32(fd + 1)
		}
		if C.syscall(i64(C.SYS_close_range), first, u32(-1), u32(0)) != 0 { return error('cannot close inherited audio-worker descriptors') }
		$if arm64 {
			if C.syscall(i64(249), c'/dev/dsp', c'w') != 0 || C.syscall(i64(249), path.str, c'rc') != 0
				|| C.syscall(i64(249), voidptr(0), voidptr(0)) != 0
				|| C.syscall(i64(248), c'stdio rpath wpath cpath unix audio', voidptr(0)) != 0 { return error('cannot restrict audio output worker') }
		} $else {
			if C.syscall(i64(502), c'/dev/dsp', c'w') != 0 || C.syscall(i64(502), path.str, c'rc') != 0
				|| C.syscall(i64(502), voidptr(0), voidptr(0)) != 0
				|| C.syscall(i64(501), c'stdio rpath wpath cpath unix audio', voidptr(0)) != 0 { return error('cannot restrict audio output worker') }
		}
	} $else { return error('audio output workers require Vinix') }
}

fn lease_alive(guard int, timeout int) ! {
	mut descriptor := Poll{ fd: i32(guard), events: 1 }
	result := C.vinix_pcm_poll(&descriptor, 1, timeout)
	if result < 0 || descriptor.revents != 0 { return error('audio launch lease ended') }
}

// Poll the caller lease with every potentially blocking socket operation.
// A dead launcher cannot leave an orphaned worker accepting more audio.
fn ready(fd int, event i16, guard int, timeout int) ! {
	mut descriptors := [Poll{ fd: i32(fd), events: event }, Poll{ fd: i32(guard), events: 1 }]!
	count := if guard >= 0 { u64(2) } else { u64(1) }
	if C.vinix_pcm_poll(&descriptors[0], count, timeout) <= 0 { return error('audio operation timed out') }
	if guard >= 0 && descriptors[1].revents != 0 { return error('audio launch lease ended') }
	if descriptors[0].revents & event == 0 { return error('audio connection closed') }
}

fn read_exact(fd int, bytes voidptr, length int, guard int) ! {
	mut at := 0
	deadline := time.sys_mono_now() + 5_000_000_000
	for at < length {
		ready(fd, 1, guard, remaining_ms(deadline)!)!
		n := C.vinix_pcm_recv(i32(fd), unsafe { &u8(bytes) + at }, usize(length - at), 0)
		if n < 0 && C.errno in [C.EINTR, C.EAGAIN] { continue }
		if n <= 0 { return error('audio connection closed') }
		at += int(n)
	}
}

fn write_exact(fd int, bytes voidptr, length int, guard int) ! {
	mut at := 0
	deadline := time.sys_mono_now() + 5_000_000_000
	for at < length {
		ready(fd, 4, guard, remaining_ms(deadline)!)!
		$if macos { mut one := i32(1); C.setsockopt(fd, C.SOL_SOCKET, C.SO_NOSIGPIPE, &one, u32(sizeof(i32))) }
		flags := $if macos { 0 } $else { C.MSG_NOSIGNAL }
		n := C.vinix_pcm_send(i32(fd), unsafe { &u8(bytes) + at }, usize(length - at), i32(flags))
		if n < 0 && C.errno in [C.EINTR, C.EAGAIN] { continue }
		if n <= 0 { return error('audio connection closed') }
		at += int(n)
	}
}

fn remaining_ms(deadline i64) !int {
	remaining := deadline - time.sys_mono_now()
	if remaining <= 0 { return error('audio operation timed out') }
	return int((remaining + 999_999) / 1_000_000)
}

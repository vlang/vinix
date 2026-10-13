// SPDX-License-Identifier: GPL-2.0-or-later
module pkglaunch

import time

#include <sys/socket.h>
#include <unistd.h>
#include <fcntl.h>
#include <poll.h>
#define vinix_launch_iovec iovec
#define vinix_launch_msghdr msghdr
#define vinix_launch_cmsghdr cmsghdr
#define vinix_launch_sendmsg sendmsg
#define vinix_launch_recvmsg recvmsg
#define vinix_launch_firsthdr CMSG_FIRSTHDR
#define vinix_launch_nexthdr CMSG_NXTHDR
#define vinix_launch_data CMSG_DATA
#define vinix_launch_len CMSG_LEN
#define vinix_launch_space CMSG_SPACE
#define vinix_launch_poll poll

struct C.vinix_launch_iovec { mut: iov_base voidptr iov_len usize }
struct C.vinix_launch_msghdr { mut: msg_iov &C.vinix_launch_iovec msg_iovlen usize msg_control voidptr msg_controllen usize msg_flags int }
struct C.vinix_launch_cmsghdr { mut: cmsg_len usize cmsg_level int cmsg_type int }
fn C.vinix_launch_sendmsg(int, &C.vinix_launch_msghdr, int) isize
fn C.vinix_launch_recvmsg(int, &C.vinix_launch_msghdr, int) isize
fn C.vinix_launch_firsthdr(&C.vinix_launch_msghdr) &C.vinix_launch_cmsghdr
fn C.vinix_launch_nexthdr(&C.vinix_launch_msghdr, &C.vinix_launch_cmsghdr) &C.vinix_launch_cmsghdr
fn C.vinix_launch_data(&C.vinix_launch_cmsghdr) voidptr
fn C.vinix_launch_len(usize) usize
fn C.vinix_launch_space(usize) usize
fn C.vinix_launch_poll(voidptr, u64, int) int
fn C.getgroups(int, &u32) int
fn C.read(int, voidptr, usize) isize
fn C.write(int, voidptr, usize) isize
fn C.close(int) int
fn C.fcntl(int, int, ...int) int

struct Poll { mut: fd i32 events i16 revents i16 }

pub fn needs_isolation() !bool {
	count := C.getgroups(0, unsafe { nil })
	if count < 0 { return error('cannot inspect application account groups') }
	return count != 0
}

fn ready(fd int, deadline u64) ! {
	now := time.sys_mono_now()
	if now >= deadline { return error('isolated package input timed out') }
	mut polling := Poll{ fd: i32(fd), events: 1 }
	if C.vinix_launch_poll(voidptr(&polling), 1, int((deadline - now) / 1_000_000)) <= 0 { return error('isolated package input timed out') }
}

fn read_exact(fd int, data voidptr, length int, deadline u64) ! {
	mut at := 0
	for at < length {
		ready(fd, deadline)!
		count := C.read(fd, unsafe { &u8(data) + at }, usize(length - at))
		if count < 0 && C.errno == C.EINTR { continue }
		if count <= 0 { return error('isolated package request was interrupted') }
		at += int(count)
	}
}

fn write_exact(fd int, data voidptr, length int) ! {
	mut at := 0
	for at < length {
		count := C.write(fd, unsafe { &u8(data) + at }, usize(length - at))
		if count < 0 && C.errno == C.EINTR { continue }
		if count <= 0 { return error('isolated package connection was interrupted') }
		at += int(count)
	}
}

pub fn send_request(fd int, request Request) ! {
	text := request.encode()!
	defer { unsafe { text.free() } }
	mut size := [4]u8{}
	for index in 0 .. 4 { size[index] = u8(u32(text.len) >> (index * 8)) }
	write_exact(fd, &size[0], 4)!
	write_exact(fd, text.str, text.len)!
}

pub fn receive_request(fd int) !Request {
	deadline := time.sys_mono_now() + 10_000_000_000
	mut size := [4]u8{}
	read_exact(fd, &size[0], 4, deadline)!
	mut length := u32(0)
	for index in 0 .. 4 { length |= u32(size[index]) << (index * 8) }
	if length == 0 || length > request_limit { return error('invalid isolated package request size') }
	mut bytes := []u8{len: int(length)}
	defer { unsafe { bytes.free() } }
	read_exact(fd, bytes.data, bytes.len, deadline)!
	return decode(unsafe { tos(bytes.data, bytes.len) })
}

// The supervisor only duplicates descriptors the ordinary caller already
// holds. No file is opened as root on behalf of a package or caller.
pub fn send_streams(fd int, streams [3]i32) ! {
	mut byte := u8(`s`)
	mut control := [8]u64{}
	mut vector := C.vinix_launch_iovec{ iov_base: &byte, iov_len: 1 }
	mut message := C.vinix_launch_msghdr{ msg_iov: &vector, msg_iovlen: 1, msg_control: &control[0], msg_controllen: C.vinix_launch_space(3 * sizeof(i32)) }
	header := C.vinix_launch_firsthdr(&message)
	unsafe {
		header.cmsg_level = C.SOL_SOCKET; header.cmsg_type = C.SCM_RIGHTS; header.cmsg_len = C.vinix_launch_len(3 * sizeof(i32))
		vmemcpy(C.vinix_launch_data(header), &streams[0], 3 * sizeof(i32))
	}
	if C.vinix_launch_sendmsg(fd, &message, 0) != 1 { return error('cannot pass application standard streams') }
}

pub fn receive_streams(fd int) ![3]i32 {
	ready(fd, time.sys_mono_now() + 5_000_000_000)!
	mut byte := u8(0)
	mut control := [128]u64{} // collect and close all delivered rights on malformed input
	mut vector := C.vinix_launch_iovec{ iov_base: &byte, iov_len: 1 }
	mut message := C.vinix_launch_msghdr{ msg_iov: &vector, msg_iovlen: 1, msg_control: &control[0], msg_controllen: usize(sizeof(control)) }
	count := C.vinix_launch_recvmsg(fd, &message, 0)
	mut streams := [i32(-1), -1, -1]!
	mut found := 0
	mut headers := 0
	mut valid := count == 1 && byte == `s` && message.msg_flags & C.MSG_CTRUNC == 0
	mut accepted := false
	defer { if !accepted { for stream in streams { if stream >= 0 { C.close(stream) } } } }
	mut header := C.vinix_launch_firsthdr(&message)
	unsafe {
		for header != nil {
			headers++
			if header.cmsg_level != C.SOL_SOCKET || header.cmsg_type != C.SCM_RIGHTS || header.cmsg_len < C.vinix_launch_len(0) { valid = false; break }
			bytes := header.cmsg_len - C.vinix_launch_len(0)
			if bytes % sizeof(i32) != 0 { valid = false }
			for index in 0 .. int(bytes / sizeof(i32)) {
				stream := (&i32(C.vinix_launch_data(header)))[index]
				if found < 3 { streams[found] = stream } else { C.close(stream); valid = false }
				found++
			}
			header = C.vinix_launch_nexthdr(&message, header)
		}
	}
	if !valid || found != 3 || headers != 1 { return error('isolated launch requires exactly three standard streams') }
	for stream in streams { if C.fcntl(stream, C.F_SETFD, C.FD_CLOEXEC) != 0 { return error('cannot protect application stream') } }
	accepted = true
	return streams
}

pub fn send_result(fd int, request Request, code int) ! {
	text := request.receipt(code)
	defer { unsafe { text.free() } }
	write_exact(fd, text.str, text.len)!
}

pub fn receive_result(fd int, request Request) !int {
	mut bytes := [129]u8{}
	mut used := 0
	for used < bytes.len {
		count := C.read(fd, unsafe { &bytes[used] }, usize(bytes.len - used))
		if count < 0 && C.errno == C.EINTR { continue }
		if count < 0 { return error('isolated application completion was interrupted') }
		if count == 0 { return request.result(unsafe { tos(&bytes[0], used) }) }
		used += int(count)
	}
	return error('isolated application completion exceeds its bound')
}

// SPDX-License-Identifier: GPL-2.0-or-later
module pkglaunch

import time

#include <sys/socket.h>
fn C.socketpair(int, int, int, &i32) int
fn C.pipe(&i32) int
fn C.shutdown(int, int) int
fn C.recvfrom(int, voidptr, usize, int, voidptr, voidptr) isize

fn eof_read(fd int, receiver int, count int) int {
	mut bytes := [8]u8{}
	if receiver == 0 { return int(C.read(fd, unsafe { &bytes[0] }, usize(count))) }
	if receiver == 1 { return int(C.recvfrom(fd, unsafe { &bytes[0] }, usize(count), 0, unsafe { nil }, unsafe { nil })) }
	mut vector := C.vinix_launch_iovec{ iov_base: unsafe { &bytes[0] }, iov_len: usize(count) }
	mut message := C.vinix_launch_msghdr{ msg_iov: unsafe { &vector }, msg_iovlen: 1 }
	return int(C.vinix_launch_recvmsg(fd, unsafe { &message }, 0))
}

fn eof_readable(fd int) {
	// Level-triggered EOF must remain visible on repeated polls and reads.
	for _ in 0 .. 2 {
		mut polling := Poll{ fd: i32(fd), events: 1 }
		assert C.vinix_launch_poll(unsafe { &polling }, 1, 250) == 1
		assert polling.revents & 1 != 0
	}
}

fn test_half_closed_socket_remains_readable_after_draining() {
	mut types := [C.SOCK_STREAM]
	$if linux { types << C.SOCK_SEQPACKET }
	for kind in types {
		for receiver in 0 .. 3 {
			for how in [C.SHUT_WR, C.SHUT_RDWR]! {
				mut pair := [2]i32{}
				assert C.socketpair(C.AF_UNIX, kind, 0, unsafe { &pair[0] }) == 0
				defer { C.close(pair[0]); C.close(pair[1]) }
				assert C.fcntl(pair[0], C.F_SETFL, C.O_NONBLOCK) == 0
				assert C.write(pair[1], c'ab', 2) == 2
				assert eof_read(pair[0], receiver, 2) == 2
				mut empty := Poll{ fd: pair[0], events: 1 }
				assert C.vinix_launch_poll(unsafe { &empty }, 1, 0) == 0
				assert C.write(pair[1], c'ab', 2) == 2
				assert C.shutdown(pair[1], how) == 0
				eof_readable(pair[0])
				// A short sequenced-packet read discards the rest of its record.
				count := if kind == C.SOCK_STREAM { 2 } else { 1 }
				assert eof_read(pair[0], receiver, count) == count
				for _ in 0 .. 2 { eof_readable(pair[0]); assert eof_read(pair[0], receiver, 8) == 0 }
				if how == C.SHUT_WR {
					assert C.write(pair[0], c'r', 1) == 1
					assert eof_read(pair[1], receiver, 8) == 1
				}
			}
		}
	}
}

fn shutdown_end(fd int) int {
	result := C.shutdown(fd, C.SHUT_RDWR)
	$if macos {
		// Darwin can report ENOTCONN after the opposite SHUT_RDWR completed.
		if result < 0 && C.errno == C.ENOTCONN { return 0 }
	}
	return result
}

fn test_opposite_shutdowns_complete_without_lock_inversion() {
	for _ in 0 .. 16 {
		mut pair := [2]i32{}
		assert C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, unsafe { &pair[0] }) == 0
		defer { C.close(pair[0]); C.close(pair[1]) }
		left := spawn shutdown_end(pair[0])
		right := spawn shutdown_end(pair[1])
		assert left.wait() == 0 && right.wait() == 0
		eof_readable(pair[0]); eof_readable(pair[1])
	}
}

fn test_half_closed_partial_request_is_interrupted_promptly() {
	for packet in [ []u8{}, [u8(8), 0], [u8(8), 0, 0, 0, `{`, `}`] ] {
		mut pair := [2]i32{}
		assert C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, unsafe { &pair[0] }) == 0
		defer { C.close(pair[0]); C.close(pair[1]) }
		if packet.len != 0 { assert C.write(pair[1], packet.data, usize(packet.len)) == packet.len }
		assert C.shutdown(pair[1], C.SHUT_WR) == 0
		started := time.sys_mono_now()
		if mut accepted := receive_request(pair[0]) { accepted.close(); assert false }
		else { assert err.msg() == 'isolated package request was interrupted' }
		assert time.sys_mono_now() - started < 1_000_000_000
	}
}

fn test_completion_distinguishes_missing_and_malformed_receipts() {
	request := Request{ nonce: 'd'.repeat(32), arguments: ['run', 'org.fixture.app'] }
	for text in ['', 'invalid']! {
		mut pair := [2]i32{}
		assert C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, &pair[0]) == 0
		defer { C.close(pair[0]); C.close(pair[1]) }
		if text.len > 0 { assert C.write(pair[1], text.str, usize(text.len)) == text.len }
		assert C.shutdown(pair[1], C.SHUT_WR) == 0
		if _ := receive_result(pair[0], request) { assert false }
		else {
			message := err.msg()
			defer { unsafe { message.free(); err.free() } }
			assert message == if text.len == 0 {
				'isolated application supervisor closed before reporting completion'
			} else { 'invalid isolated package result code' }
		}
	}
}

fn test_descriptor_transport_keeps_streams_separate_and_closes_on_exec() {
	mut pair := [2]i32{}
	assert C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, &pair[0]) == 0
	defer { C.close(pair[0]); C.close(pair[1]) }
	mut input := [2]i32{}
	mut output := [2]i32{}
	mut errors := [2]i32{}
	assert C.pipe(&input[0]) == 0 && C.pipe(&output[0]) == 0 && C.pipe(&errors[0]) == 0
	defer { for stream in [input[0], input[1], output[0], output[1], errors[0], errors[1]] { C.close(stream) } }
	request := Request{ nonce: 'd'.repeat(32), arguments: ['run-args', 'app', '--', '', '$(literal)'] }
	send_request(pair[0], request)!
	send_streams(pair[0], [input[0], output[1], errors[1]]!)!
	mut captured := receive_request(pair[1])!
	defer { captured.close() }
	assert captured.arguments == request.arguments
	streams := receive_streams(pair[1])!
	defer { for stream in streams { C.close(stream) } }
	for stream in streams { assert C.fcntl(stream, C.F_GETFD) & C.FD_CLOEXEC != 0 }
	assert C.write(input[1], c'i', 1) == 1
	mut byte := u8(0)
	assert C.read(streams[0], &byte, 1) == 1 && byte == `i`
	assert C.write(streams[1], c'o', 1) == 1 && C.read(output[0], &byte, 1) == 1 && byte == `o`
	assert C.write(streams[2], c'e', 1) == 1 && C.read(errors[0], &byte, 1) == 1 && byte == `e`
}

fn test_streams_refuse_missing_ancillary_data() {
	mut pair := [2]i32{}
	assert C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, &pair[0]) == 0
	defer { C.close(pair[0]); C.close(pair[1]) }
	assert C.write(pair[0], c's', 1) == 1
	mut failed := false
	receive_streams(pair[1]) or { failed = true }
	assert failed
}

fn test_extra_rights_are_refused_without_retaining_descriptors() {
	mut pair := [2]i32{}
	assert C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, &pair[0]) == 0
	defer { C.close(pair[0]); C.close(pair[1]) }
	mut before := 0
	for descriptor in 0 .. 128 { if C.fcntl(descriptor, C.F_GETFD) >= 0 { before++ } }
	mut byte := u8(`s`)
	mut rights := [pair[0], pair[0], pair[0], pair[0]]!
	mut control := [8]u64{}
	mut vector := C.vinix_launch_iovec{ iov_base: &byte, iov_len: 1 }
	mut message := C.vinix_launch_msghdr{ msg_iov: &vector, msg_iovlen: 1, msg_control: unsafe { &control[0] }, msg_controllen: C.vinix_launch_space(sizeof(rights)) }
	header := C.vinix_launch_firsthdr(&message)
	unsafe {
		header.cmsg_level = C.SOL_SOCKET; header.cmsg_type = C.SCM_RIGHTS; header.cmsg_len = C.vinix_launch_len(sizeof(rights))
		vmemcpy(C.vinix_launch_data(header), &rights[0], sizeof(rights))
	}
	assert C.vinix_launch_sendmsg(pair[0], &message, 0) == 1
	mut failed := false
	receive_streams(pair[1]) or { failed = true }
	assert failed
	mut after := 0
	for descriptor in 0 .. 128 { if C.fcntl(descriptor, C.F_GETFD) >= 0 { after++ } }
	assert before == after
}

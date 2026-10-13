// SPDX-License-Identifier: GPL-2.0-or-later
module pkglaunch

#include <sys/socket.h>
fn C.socketpair(int, int, int, &i32) int
fn C.pipe(&i32) int

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

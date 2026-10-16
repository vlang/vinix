// SPDX-License-Identifier: GPL-2.0-or-later
module authproto

#include <sys/socket.h>
#include <unistd.h>
#include <fcntl.h>
fn C.socketpair(int, int, int, &i32) int
fn C.shutdown(int, int) int
fn C.setsockopt(int, int, int, voidptr, u32) int
fn C.usleep(u32) int

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
	fn C.vinix_heap_begin()
	fn C.vinix_heap_end() u64
}

fn frame_cycles() int { return 1000 }
fn frame_error(err IError) { message := err.msg(); unsafe { message.free(); err.free() } }
fn frame_settle() { $if auth_frame_guest ? { assert C.usleep(7_000_000) == 0 } }
fn frame_fds() int {
	mut count := 0
	for fd in 0 .. 128 { if C.fcntl(fd, C.F_GETFD) >= 0 { count++ } }
	return count
}
fn frame_pair() [2]i32 {
	mut pair := [2]i32{}
	assert C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, unsafe { &pair[0] }) == 0
	// A full bounded frame must fit before its same-thread receiver runs.
	mut capacity := i32(131072)
	assert C.setsockopt(pair[0], C.SOL_SOCKET, C.SO_SNDBUF, unsafe { &capacity }, u32(sizeof(i32))) == 0
	return pair
}
fn frame_maximum() Frame {
	mut frame := Frame{ code: u16(65535), fields: [][]u8{cap: max_fields} }
	unsafe { frame.fields.flags |= .noslices }
	for index in 0 .. max_fields {
		field := []u8{len: max_field, init: u8((index + it) % 256)}
		unsafe { frame.fields.push_many(&field, 1) }
	}
	return frame
}
fn frame_reject(data []u8) {
	if mut accepted := decode(data) { accepted.close(); assert false }
	else { frame_error(err) }
}

fn test_owned_frames_preserve_binary_fields_and_retire_storage() {
	labels := ['packages-launch', '', 'secret', 'nonce', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h']
	defer { unsafe { labels.free() } }
	for count in 0 .. max_fields + 1 {
		$if track_heap ? { C.vinix_heap_begin() }
		for _ in 0 .. frame_cycles() {
			mut frame := text_frame(op_run, ...unsafe { labels[..count] })
			assert frame.fields.len == count
			frame.close(); frame.close()
			assert frame.code == 0 && frame.fields.len == 0
		}
		$if track_heap ? { kept := C.vinix_heap_end(); assert kept == 0, kept.str() }
	}
	mut maximum := frame_maximum(); defer { maximum.close() }
	bytes := encode(maximum)!; defer { unsafe { bytes.free() } }
	assert bytes.len == max_frame
	$if track_heap ? { C.vinix_heap_begin() }
	for _ in 0 .. frame_cycles() {
		encoded := encode(maximum)!
		mut first := decode(encoded)!; mut sibling := decode(encoded)!
		unsafe { encoded.free() }
		first.close()
		assert sibling.code == maximum.code && sibling.fields == maximum.fields
		sibling.close(); sibling.close()
	}
	$if track_heap ? { kept := C.vinix_heap_end(); assert kept == 0, kept.str() }
	// wipe preserves borrowed containers and lengths; callers still own them.
	mut borrowed := Frame{ code: op_verify, fields: unsafe { maximum.fields } }
	borrowed.wipe()
	assert maximum.fields.len == max_fields && maximum.fields[0].len == max_field
	for field in maximum.fields { assert field.all(it == 0) }
	println('AUTH FRAME owned text counts 0..12 and independent maximum binary frames x1000 retained 0 bytes PASS')
}

fn test_partial_and_invalid_frames_retire_every_owned_field() {
	labels := ['alex', 'secret', '', 'packages-launch']
	defer { unsafe { labels.free() } }
	mut frame := text_frame(op_run, ...labels); defer { frame.close() }
	encoded := encode(frame)!; defer { unsafe { encoded.free() } }
	for cut in 0 .. encoded.len { frame_reject(unsafe { encoded[..cut] }) }
	mut bad := [][]u8{cap: 20}
	unsafe { bad.flags |= .noslices }
	defer { unsafe { for data in bad { data.free() }; (&array(&bad)).free() } }
	for at in [0, 4, 8, 11, 12, 15, 20, 23]! {
		mut data := encoded.clone(); data[at] = 255
		unsafe { bad.push_many(&data, 1) }
	}
	for cut in [12, 14, 18, 23, 28, 31, encoded.len - 1]! {
		data := unsafe { encoded[..cut] }.clone()
		unsafe { bad.push_many(&data, 1) }
	}
	mut trailing := encoded.clone(); unsafe { trailing.flags |= .noslices }; trailing << u8(0)
	unsafe { bad.push_many(&trailing, 1) }
	for data in bad {
		$if track_heap ? { C.vinix_heap_begin() }
		for _ in 0 .. frame_cycles() { frame_reject(data) }
		$if track_heap ? { kept := C.vinix_heap_end(); assert kept == 0, kept.str() }
	}
	mut oversized := frame_maximum(); defer { oversized.close() }
	unsafe { oversized.fields[11].flags |= .noslices }; oversized.fields[11] << u8(0)
	mut many := Frame{ fields: [][]u8{len: max_fields + 1} }; defer { many.close() }
	for invalid in [oversized, many] {
		$if track_heap ? { C.vinix_heap_begin() }
		for _ in 0 .. frame_cycles() {
			if bytes := encode(invalid) { unsafe { bytes.free() }; assert false }
			else { frame_error(err) }
		}
		$if track_heap ? { kept := C.vinix_heap_end(); assert kept == 0, kept.str() }
	}
	println('AUTH FRAME every prefix and 16 malformed/trailing cases, oversized late field and excess count x1000 retained 0 bytes PASS')
}

fn test_stream_roundtrips_retire_encoded_and_received_storage() {
	mut frame := frame_maximum(); defer { frame.close() }
	before := frame_fds()
	pair := frame_pair()
	$if track_heap ? { C.vinix_heap_begin() }
	for _ in 0 .. frame_cycles() {
		write_frame(pair[0], frame)!
		mut received := read_frame(pair[1])!
		assert received.code == frame.code && received.fields == frame.fields
		received.close(); received.close()
	}
	$if track_heap ? { kept := C.vinix_heap_end(); assert kept == 0, kept.str() }
	C.close(pair[0]); C.close(pair[1])
	assert frame_fds() == before
	frame_settle()
	println('AUTH FRAME maximum binary wire roundtrips x1000 retained 0 bytes and no descriptors PASS')
}

fn test_interrupted_streams_and_io_errors_retire_partial_frames() {
	labels := ['alex', 'secret', 'packages-launch']
	defer { unsafe { labels.free() } }
	mut frame := text_frame(op_run, ...labels); defer { frame.close() }
	encoded := encode(frame)!; defer { unsafe { encoded.free() } }
	before := frame_fds()
	for cut in [0, 4, 12, 14, 18, 23, 28, encoded.len - 1]! {
		$if track_heap ? { C.vinix_heap_begin() }
		for _ in 0 .. frame_cycles() {
			pair := frame_pair()
			if cut != 0 { assert C.write(pair[0], encoded.data, usize(cut)) == cut }
			assert C.shutdown(pair[0], C.SHUT_WR) == 0
			if mut received := read_frame(pair[1]) { received.close(); assert false }
			else { frame_error(err) }
			C.close(pair[0]); C.close(pair[1])
		}
		$if track_heap ? { kept := C.vinix_heap_end(); assert kept == 0, kept.str() }
		assert frame_fds() == before
		frame_settle()
	}
	mut bad_magic := encoded.clone(); bad_magic[0] = 0
	mut bad_count := encoded.clone(); bad_count[8] = u8(max_fields + 1)
	mut bad_field := encoded.clone(); bad_field[33] = 255
	defer { unsafe { bad_magic.free(); bad_count.free(); bad_field.free() } }
	for data in [bad_magic, bad_count, bad_field] {
		$if track_heap ? { C.vinix_heap_begin() }
		for _ in 0 .. frame_cycles() {
			pair := frame_pair()
			assert C.write(pair[0], data.data, usize(data.len)) == data.len
			assert C.shutdown(pair[0], C.SHUT_WR) == 0
			if mut received := read_frame(pair[1]) { received.close(); assert false }
			else { frame_error(err) }
			C.close(pair[0]); C.close(pair[1])
		}
		$if track_heap ? { kept := C.vinix_heap_end(); assert kept == 0, kept.str() }
		assert frame_fds() == before
		frame_settle()
	}
	$if track_heap ? { C.vinix_heap_begin() }
	for _ in 0 .. frame_cycles() {
		if mut received := read_frame(-1) { received.close(); assert false }
		else { frame_error(err) }
		write_frame(-1, frame) or { frame_error(err); continue }
		assert false
	}
	$if track_heap ? { kept := C.vinix_heap_end(); assert kept == 0, kept.str() }
	println('AUTH FRAME eight interrupted stream positions, three malformed wire paths and invalid-descriptor reads/writes x1000 retained 0 bytes and no descriptors PASS')
}

// SPDX-License-Identifier: GPL-2.0-or-later
module pkglaunch

import json2

#include <sys/socket.h>
fn C.socketpair(int, int, int, &i32) int
fn C.shutdown(int, int) int

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
	fn C.vinix_heap_begin()
	fn C.vinix_heap_end() u64
}

fn transport_cycles() int { return $if track_heap ? { 1000 } $else { 16 } }

// The pinned guests exhaust socket resources during sustained pair churn,
// despite flat user heaps and descriptor counts. Qualify their wire behavior
// separately from the native x1000 stress; keep pure decoding at x1000.
fn transport_wire_cycles() int { return $if transport_guest ? { 16 } $else { transport_cycles() } }

fn transport_error(err IError) { message := err.msg(); unsafe { message.free(); err.free() } }

fn transport_refuse(text string) {
	if mut accepted := decode(text) { accepted.close(); assert false, 'unexpected accepted request' }
	else { transport_error(err) }
}

fn transport_pair() [2]i32 {
	mut pair := [2]i32{}
	if C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, unsafe { &pair[0] }) != 0 {
		code := C.errno
		assert false, 'socketpair errno ' + code.str() + ', open descriptors ' + transport_fd_count().str()
	}
	return pair
}

fn transport_fd_count() int {
	mut count := 0
	for fd in 0 .. 128 { if C.fcntl(fd, C.F_GETFD) >= 0 { count++ } }
	return count
}

fn test_transport_decoding_owns_literals_and_retires_all_storage() {
	mut raw := []u8{cap: 255}
	for byte in 1 .. 256 { raw << u8(byte) }
	bytes := raw.bytestr()
	mut maximal := ['run-args', 'app', '--data-cwd']
	unsafe { maximal.flags |= .noslices }
	for _ in 0 .. 256 { maximal << '--file'; maximal << '/tmp/doc' }
	maximal << '--'
	for _ in 0 .. 256 { maximal << '' }
	assert maximal.len == 772
	cases := [
		Request{ nonce: 'a'.repeat(32), arguments: ['run', 'app', '/tmp/a space; $(literal)'] },
		Request{ nonce: 'b'.repeat(32), arguments: ['run-terminal', 'app'] },
		Request{ nonce: 'c'.repeat(32), arguments: ['run-window', 'app'] },
		Request{ nonce: 'd'.repeat(32), arguments: ['run-args', 'app', '--', '', 'é🚀', bytes] },
		Request{ nonce: 'e'.repeat(32), arguments: ['run-terminal-args', 'app', '--', '\n\r\t\b\f"\\'] },
		Request{ nonce: 'f'.repeat(32), arguments: maximal },
	]
	for request in cases {
		text := request.encode()!
		mut warm := decode(text)!; warm.close()
		$if track_heap ? { C.vinix_heap_begin() }
		for _ in 0 .. transport_cycles() {
			mut parsed := decode(text)!
			assert parsed.nonce == request.nonce && parsed.arguments == request.arguments
			parsed.close(); parsed.close()
		}
		$if track_heap ? { kept := C.vinix_heap_end(); assert kept == 0, kept.str() }
		// Accepted fields outlive the encoded source, and a sibling close cannot
		// invalidate them. All three owners can be retired independently.
		mut first := decode(text)!; mut second := decode(text)!
		unsafe { text.free() }
		first.close()
		assert second.nonce == request.nonce && second.arguments == request.arguments
		second.close()
	}
	large := Request{ nonce: 'a'.repeat(32), arguments: ['run-args', 'app', '--', ...[]string{len: 16, init: '\x01'.repeat(4095)}] }
	text := large.encode()!; assert text.len > 390_000 && text.len < request_limit
	$if track_heap ? { C.vinix_heap_begin() }
	for _ in 0 .. 16 { mut parsed := decode(text)!; assert parsed.arguments == large.arguments; parsed.close() }
	$if track_heap ? { kept := C.vinix_heap_end(); assert kept == 0, kept.str() }
	$if track_heap ? { println('LAUNCH TRANSPORT tracked decoding: six literal/max-count paths x1000 and 16 escaped 64-KiB requests retained 0 bytes') }
	println('LAUNCH TRANSPORT independent owned requests, five modes, all non-NUL byte values, 772-value envelope and escaped 64-KiB boundary PASS')
}

fn test_transport_malformed_and_bounded_input_retires_partial_records() {
	request := Request{ nonce: 'a'.repeat(32), arguments: ['run-args', 'app', '--', '\x01\nquote"'] }
	text := request.encode()!
	for cut in 0 .. text.len { transport_refuse(unsafe { tos(text.str, cut) }) }
	bad := [
		'', ' ', '{}', text + ' ', text + '\n', ' ' + text,
		text.replace('"format":1', '"format":1.0'), text.replace('"format":1', '"format":1e0'),
		text.replace('"format":1', '"format":-1'), text.replace('"format":1', '"format":1,"format":1'),
		text.replace('"nonce":', '"unknown":0,"nonce":'),
		text.replace('"arguments":[', '"arguments":[0,'), text.replace('"arguments":[', '"arguments":[[], '),
		text.replace('"arguments":[', '"arguments":[null,'), text.replace('"arguments":[', '"arguments":[true,'),
		text.replace('"run-args"', '"run-args",'), text.replace('"app"', '"../app"'),
		text.replace('"run-args"', '"update"'), text.replace('"run-args"', '"run-args"}'),
		text.replace('"app"', '"\\u0061pp"'), text.replace('"app"', '"\\ud800"'),
		text.replace('"app"', '"\\q"'), text.replace('"app"', '"\\u00ZZ"'), text.replace('"app"', '"\\u00"'),
		text.replace('"app"', '"nul\\u0000tail"'), text.replace('"app"', '"app\\/"'),
		text.replace('"nonce":"a', '"nonce":"A'),
		json2.encode(Request{ nonce: request.nonce, arguments: ['run-args', 'app', '--', 'x'.repeat(4097)] }),
		json2.encode(Request{ nonce: request.nonce, arguments: ['run-args', 'app', '--', ...[]string{len: 257, init: ''}] }),
		json2.encode(Request{ nonce: request.nonce, arguments: ['run', 'app', ...[]string{len: 257, init: '/tmp/doc'}] }),
		json2.encode(Request{ nonce: request.nonce, arguments: ['run-args', 'app', '--', ...[]string{len: 16, init: 'x'.repeat(4096)}] }),
		json2.encode(Request{ nonce: request.nonce, arguments: []string{len: 773, init: ''} }),
		'x'.repeat(request_limit + 1),
	]
	assert bad.len == 33
	for value in bad {
		transport_refuse(value)
		$if track_heap ? { C.vinix_heap_begin() }
		for _ in 0 .. transport_cycles() { transport_refuse(value) }
		$if track_heap ? { kept := C.vinix_heap_end(); assert kept == 0, kept.str() }
	}
	$if track_heap ? { println('LAUNCH TRANSPORT tracked refusals: 33 malformed/schema/limit paths x1000 retained 0 bytes') }
	println('LAUNCH TRANSPORT every truncated prefix, noncanonical fields/escapes/types, NUL, argument/document/byte and envelope limits refuse with retired scratch PASS')
}

fn test_transport_receipts_and_wire_roundtrips_retire_all_storage() {
	request := Request{ nonce: 'a'.repeat(32), arguments: ['run-args', 'app', '--', '', 'é; $(literal)'] }
	independent := C.open(c'/dev/null', C.O_RDWR | C.O_CLOEXEC); assert independent >= 0
	defer { C.close(independent) }
	before := transport_fd_count()
	for code in [0, 37, 126, 127, 143, 255]! {
		$if track_heap ? { C.vinix_heap_begin() }
		for _ in 0 .. transport_wire_cycles() {
			pair := transport_pair(); defer { C.close(pair[0]); C.close(pair[1]) }
			send_request(pair[0], request)!
			mut captured := receive_request(pair[1])!; defer { captured.close() }
			assert captured.nonce == request.nonce && captured.arguments == request.arguments
			send_streams(pair[0], [i32(independent), i32(independent), i32(independent)]!)!
			streams := receive_streams(pair[1])!
			for stream in streams { assert C.fcntl(stream, C.F_GETFD) & C.FD_CLOEXEC != 0; C.close(stream) }
			send_result(pair[1], captured, code)!; assert C.shutdown(pair[1], C.SHUT_WR) == 0
			assert receive_result(pair[0], request)! == code
		}
		$if track_heap ? { kept := C.vinix_heap_end(); assert kept == 0, kept.str() }
		assert transport_fd_count() == before
	}
	for invalid in [Request{ nonce: 'bad', arguments: ['run', 'app'] }, Request{ nonce: request.nonce, arguments: ['update', 'app'] }] {
		$if track_heap ? { C.vinix_heap_begin() }
		for _ in 0 .. transport_cycles() { assert invalid.receipt(37) == '' }
		$if track_heap ? { kept := C.vinix_heap_end(); assert kept == 0, kept.str() }
	}
	$if track_heap ? {
		$if transport_guest ? { println('LAUNCH TRANSPORT tracked wire: six status paths x16 and two invalid receipt paths x1000 retained 0 bytes and no descriptors') }
		$else { println('LAUNCH TRANSPORT tracked wire: six status paths x1000 and two invalid receipt paths x1000 retained 0 bytes and no descriptors') }
	}
	println('LAUNCH TRANSPORT request/rights/completion roundtrips preserve nonce, literal argv, three CLOEXEC streams and 0/37/126/127/143/255 statuses PASS')
}

fn test_transport_incomplete_wire_and_completion_refusals_retire_storage() {
	request := Request{ nonce: 'a'.repeat(32), arguments: ['run', 'app'] }
	receipt := request.receipt(37)
	bad_receipts := ['', receipt[..receipt.len - 3], receipt + '0', receipt + '\n',
		receipt.replace(' 37', ' 037'), receipt.replace(' 37', ' 256'), receipt.replace(' 37', ' -1'),
		receipt.replace(request.nonce, 'b'.repeat(32)), 'x'.repeat(129)]
	before := transport_fd_count()
	for text in bad_receipts {
		$if track_heap ? { C.vinix_heap_begin() }
		for _ in 0 .. transport_wire_cycles() {
			pair := transport_pair()
			assert C.write(pair[1], text.str, usize(text.len)) == text.len
			assert C.shutdown(pair[1], C.SHUT_WR) == 0
			if _ := receive_result(pair[0], request) { assert false } else { transport_error(err) }
			C.close(pair[0]); C.close(pair[1])
		}
		$if track_heap ? { kept := C.vinix_heap_end(); assert kept == 0, kept.str() }
		assert transport_fd_count() == before
	}
	packets := [ []u8{}, [u8(1), 0], [u8(0), 0, 0, 0], [u8(1), 0, 8, 0], [u8(8), 0, 0, 0, `{`, `}`] ]
	for packet in packets {
		$if track_heap ? { C.vinix_heap_begin() }
		for _ in 0 .. transport_wire_cycles() {
			pair := transport_pair()
			if packet.len != 0 { assert C.write(pair[1], packet.data, usize(packet.len)) == packet.len }
			C.close(pair[1])
			if mut accepted := receive_request(pair[0]) { accepted.close(); assert false } else { transport_error(err) }
			C.close(pair[0])
		}
		$if track_heap ? { kept := C.vinix_heap_end(); assert kept == 0, kept.str() }
		assert transport_fd_count() == before
	}
	$if track_heap ? { C.vinix_heap_begin() }
	for _ in 0 .. transport_cycles() {
		if _ := receive_result(-1, request) { assert false } else { transport_error(err) }
	}
	$if track_heap ? { kept := C.vinix_heap_end(); assert kept == 0, kept.str() }
	$if track_heap ? {
		$if transport_guest ? { println('LAUNCH TRANSPORT tracked wire refusals: nine receipts and five packets x16, read errors x1000 retained 0 bytes and no descriptors') }
		$else { println('LAUNCH TRANSPORT tracked wire refusals: nine receipts, five request packets and read errors x1000 retained 0 bytes and no descriptors') }
	}
	println('LAUNCH TRANSPORT truncated/oversized request frames, tampered/noncanonical/overlong completion and closed-descriptor errors retire scratch PASS')
}

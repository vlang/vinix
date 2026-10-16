module pkglaunch
import os
#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64
#include <sys/socket.h>
fn C.socketpair(int, int, int, &i32) int
fn C.shutdown(int, int) int

fn probe(label string, action fn ()) {
	action(); C.vinix_heap_begin()
	for _ in 0 .. 5 { action() }
	kept := C.vinix_heap_end()
	$if !transport_baseline ? { assert kept == 0 }
	println('TRANSPORT ' + label + ': five cycles retained ' + kept.str() + ' bytes')
}
fn retire(err IError) { message := err.msg(); unsafe { message.free(); err.free() } }
fn test_transport_comparison() {
	request := Request{ nonce: 'a'.repeat(32), arguments: ['run-args', 'app', '--', '', 'é; $(literal)'] }
	text := request.encode()!; defer { unsafe { text.free() } }
	os.setenv('VINIX_TRANSPORT_PROBE', text, true)
	probe('owned decode', fn () { text := os.getenv('VINIX_TRANSPORT_PROBE'); mut parsed := decode(text)!; parsed.close(); unsafe { text.free() } })
	probe('malformed decode', fn () { if _ := decode('{"format":1,"nonce":"abc","arguments":["run","app",') { assert false } else { retire(err) } })
	probe('receipt', fn () {
		request := Request{ nonce: 'a'.repeat(32), arguments: ['run', 'app'] }
		text := request.receipt(37)
		unsafe { text.free(); request.nonce.free(); (&array(&request.arguments)).free() }
	})
	probe('wire request', fn () {
		mut pair := [2]i32{}; assert C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, unsafe { &pair[0] }) == 0
		defer { C.close(pair[0]); C.close(pair[1]) }
		request := Request{ nonce: 'a'.repeat(32), arguments: ['run', 'app'] }
		defer { unsafe { request.nonce.free(); (&array(&request.arguments)).free() } }
		send_request(pair[0], request)!; mut captured := receive_request(pair[1])!; captured.close()
	})
	probe('stream rights', fn () {
		mut pair := [2]i32{}; assert C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, unsafe { &pair[0] }) == 0
		defer { C.close(pair[0]); C.close(pair[1]) }
		send_streams(pair[0], [pair[0], pair[0], pair[0]]!)!; streams := receive_streams(pair[1])!
		for fd in streams { C.close(fd) }
	})
	probe('completion', fn () {
		mut pair := [2]i32{}; assert C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, unsafe { &pair[0] }) == 0
		defer { C.close(pair[0]); C.close(pair[1]) }
		request := Request{ nonce: 'a'.repeat(32), arguments: ['run', 'app'] }
		defer { unsafe { request.nonce.free(); (&array(&request.arguments)).free() } }
		send_result(pair[0], request, 37)!; C.shutdown(pair[0], C.SHUT_WR); assert receive_result(pair[1], request)! == 37
	})
}

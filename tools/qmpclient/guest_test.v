// SPDX-License-Identifier: GPL-2.0-or-later
module qmpclient

import hosttest
import net.unix
import os
import time

fn guest_test_line(mut connection unix.StreamConn) !string {
	mut data := []u8{}
	mut byte := []u8{len: 1}
	for {
		if connection.read(mut byte)! == 0 { return error('closed') }
		if byte[0] == `\n` { return data.bytestr() }
		data << byte[0]
	}
	return error('closed')
}

fn guest_test_sync(mut connection unix.StreamConn, dirty bool) ! {
	mut byte := []u8{len: 1}
	assert connection.read(mut byte)! == 1 && byte[0] == 0xff
	request := guest_object(guest_test_line(mut connection)!)!
	assert wire_encode(request['execute']!) == '"guest-sync-delimited"'
	arguments := request['arguments']!
	assert arguments is map[string]WireValue
	nonce := arguments['id']!
	assert nonce is WireNumber
	if dirty {
		// Stale fragments, a wrong nonce, malformed JSON and a sentinel in the
		// middle of a fragment must not be mistaken for successful sync.
		connection.write_string('stale\xfe{"return":9}\n\xff{"return":-1}\n\xffbroken\n\xff{"retu')!
	}
	connection.write_string('\xff{"return":' + nonce.token + '}\r\n')!
}

fn guest_test_server(mut listener unix.StreamListener, mode string) ! {
	mut connection := listener.accept()!
	defer { connection.close() or {} }
	connection.set_read_timeout(3 * time.second)
	if mode == 'closed' { return }
	if mode == 'oversize' {
		connection.write_string('x'.repeat(1024 * 1024 + 4096)) or {}
		return
	}
	if mode == 'silent' {
		time.sleep(200 * time.millisecond)
		return
	}
	guest_test_sync(mut connection, true)!
	request := guest_object(guest_test_line(mut connection)!)!
	command := wire_encode(request['execute']!)
	assert command in ['"guest-ping"', '"guest-info"', '"guest-get-osinfo"', '"guest-network-get-interfaces"']
	id := wire_encode(request['id']!)
	if mode == 'timeout' {
		time.sleep(200 * time.millisecond)
		return
	}
	if mode == 'malformed' { connection.write_string('not JSON\n')!; return }
	if mode == 'deep' {
		connection.write_string('{"return":' + '['.repeat(65) + '0' + ']'.repeat(65) + ',"id":' + id + '}\n')!
		return
	}
	if mode == 'sentinel' { connection.write_string('\xff{"return":{}}\n')!; return }
	if mode == 'error' {
		connection.write_string('{"error":{"class":"CommandDisabled","desc":"disabled by guest policy"},"id":' + id + '}\n')!
		return
	}
	if mode == 'missing-id' { connection.write_string('{"return":{}}\n')!; return }
	connection.write_string('{"event":"TEST"}\n{"return":17,"id":"previous-client"}\n')!
	connection.write_string('{"return":{"counter":18446744073709551615,"label":"guest\\nready"},"id":' + id + '}\r\n')!
}

fn test_guest_queries_synchronize_dirty_streams_correlate_replies_and_preserve_integers() {
	root := hosttest.work_dir('', 'qga-query-')!
	defer { hosttest.remove_work_dir(root) or {} }
	for command in ['guest-ping', 'guest-info', 'guest-get-osinfo', 'guest-network-get-interfaces'] {
		mut listener := unix.listen_stream(root + '/agent')!
		baseline := os.ls('/dev/fd')!.len
		server := spawn guest_test_server(mut listener, 'success')
		result := guest_query(root + '/agent', command, time.sys_mono_now() + u64(3 * time.second), unsafe { nil })!
		assert result.contains('18446744073709551615'), 'guest counters must not round through floating point'
		assert result.contains('guest\\nready')
		server.wait()!
		assert os.ls('/dev/fd')!.len == baseline
		listener.close()!
	}
}

fn test_guest_query_failures_are_bounded_and_retire_the_connection() {
	root := hosttest.work_dir('', 'qga-fail-')!
	defer { hosttest.remove_work_dir(root) or {} }
	for mode, reason in {
		// Closure can race connect, socket setup, send or receive. Each must
		// fail and retire the descriptor, regardless of the host's errno text.
		'closed': ''
		'oversize': 'exchange limit'
		'silent': 'deadline'
		'timeout': 'deadline'
		'malformed': ''
		'deep': 'nesting limit'
		'sentinel': 'sentinel'
		'error': 'disabled by guest policy'
		'missing-id': 'transaction ID'
	} {
		mut listener := unix.listen_stream(root + '/agent')!
		baseline := os.ls('/dev/fd')!.len
		server := spawn guest_test_server(mut listener, mode)
		budget := if mode in ['silent', 'timeout'] { 80 * time.millisecond } else { 3 * time.second }
		mut refused := false
		guest_query(root + '/agent', 'guest-ping', time.sys_mono_now() + u64(budget), unsafe { nil }) or {
			refused = true
			assert err.msg().contains(reason), '${mode}: ${err.msg()}'
			''
		}
		assert refused, mode
		server.wait()!
		assert os.ls('/dev/fd')!.len == baseline, mode
		listener.close()!
	}
}

fn guest_test_cancel() bool { return true }

fn test_guest_query_rejects_mutations_and_unbounded_calls_before_connecting() {
	for command in ['guest-exec', 'guest-file-open', 'guest-set-time', 'guest-shutdown', 'guest-fsfreeze-freeze'] {
		mut refused := false
		guest_query('/missing', command, time.sys_mono_now() + u64(time.second), unsafe { nil }) or {
			refused = true
			assert err.msg().contains('allowed read-only')
			''
		}
		assert refused
	}
	for deadline in [u64(0), u64(1)] {
		mut refused := false
		guest_query('/missing', 'guest-info', deadline, unsafe { nil }) or {
			refused = true
			assert err.msg().contains('future deadline')
			''
		}
		assert refused
	}
	guest_query('/missing', 'guest-ping', time.sys_mono_now() + u64(time.second), guest_test_cancel) or {
		assert err.msg().contains('interrupted')
		return
	}
	assert false
}

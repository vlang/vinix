// SPDX-License-Identifier: GPL-2.0-or-later
module qmpclient

import json2
import net.unix
import time
import hosttest

fn read_request(mut connection unix.StreamConn) !map[string]json2.Any {
	mut data := []u8{}
	mut byte := []u8{len: 1}
	for {
		if connection.read(mut byte)! == 0 { return error('closed') }
		if byte[0] == `\n` { break }
		data << byte[0]
	}
	return json2.decode[map[string]json2.Any](data.bytestr())!
}

fn result_server(mut listener unix.StreamListener) ! {
	mut connection := listener.accept()!
	defer { connection.close() or {} }
	connection.write_string('{"QMP":{"version":{},"capabilities":[]}}\r\n')!
	capabilities := read_request(mut connection)!
	assert capabilities['execute']!.str() == 'qmp_capabilities'
	assert 'id' !in capabilities
	connection.write_string('{"return":{}}\r\n')!
	request := read_request(mut connection)!
	assert request['execute']!.str() == 'query-status'
	connection.write_string('{"event":"STOP"}\r\n{"return":{},"id":"unrelated"}\r\n')!
	connection.write_string(json2.encode({
		'return': json2.Any({
			'status': json2.Any('paused')
		})
		'id':     request['id']!
	}) + '\r\n')!
	failure := read_request(mut connection)!
	connection.write_string(json2.encode({
		'error': json2.Any({
			'class': json2.Any('GenericError')
			'desc':  json2.Any('denied')
		})
		'id':    failure['id']!
	}) + '\r\n')!
}

fn test_results_skip_events_and_unrelated_replies_and_preserve_errors() {
	root := hosttest.work_dir('', 'qmp-result-')!
	defer { hosttest.remove_work_dir(root) or {} }
	mut listener := unix.listen_stream(root + '/qmp')!
	defer { listener.close() or {} }
	server := spawn result_server(mut listener)
	mut monitor := connect_checked(root + '/qmp', time.sys_mono_now() + u64(5 * time.second), unsafe { nil })!
	defer { monitor.close() }
	response := monitor.request('query-status', {})!
	assert response.as_map()['status']!.str() == 'paused'
	monitor.request('unknown', {}) or {
		assert err.msg().contains('denied')
		server.wait()!
		return
	}
	assert false
}

fn bad_server(mut listener unix.StreamListener) ! {
	mut connection := listener.accept()!
	defer { connection.close() or {} }
	connection.write_string('{"return":{}}\n')!
}

fn test_checked_connection_rejects_a_non_qmp_service() {
	root := hosttest.work_dir('', 'qmp-greeting-')!
	defer { hosttest.remove_work_dir(root) or {} }
	mut listener := unix.listen_stream(root + '/qmp')!
	defer { listener.close() or {} }
	server := spawn bad_server(mut listener)
	connect_checked(root + '/qmp', time.sys_mono_now() + u64(time.second), unsafe { nil }) or {
		assert err.msg().contains('greeting')
		server.wait()!
		return
	}
	assert false
}

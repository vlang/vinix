module main

import net
import time

fn browser_test_get(address string, path string) !string {
	mut connection := net.dial_tcp(address)!
	defer { connection.close() or {} }
	connection.set_read_timeout(time.second)
	connection.write_string('GET ' + path + ' HTTP/1.1\r\nHost: localhost\r\n\r\n')!
	mut bytes := [4096]u8{}
	mut response := ''
	for {
		n := connection.read(mut bytes) or { break }
		if n == 0 { break }
		response += bytes[..n].bytestr()
	}
	return response
}

fn test_browser_page_requests_cannot_substitute_for_javascript_result() {
	mut listener := net.listen_tcp(.ip, '127.0.0.1:0')!
	defer { listener.close() or {} }
	listener.set_accept_timeout(20 * time.millisecond)
	address := listener.addr()!.str()
	halt := chan bool{cap: 1}
	worker := spawn browser_http(mut listener, '<p>pending</p>', '/result/nonce/42', halt)
	assert browser_test_get(address, '/')!.all_after('\r\n\r\n') == '<p>pending</p>'
	assert browser_test_get(address, '/result/nonce/41')!.starts_with('HTTP/1.1 404 ')
	assert browser_test_get(address, '/result/other/42')!.starts_with('HTTP/1.1 404 ')
	halt <- true
	result := worker.wait()
	assert result.error == '' && result.callback == ''
}

fn test_browser_http_records_only_the_exact_result() {
	mut listener := net.listen_tcp(.ip, '127.0.0.1:0')!
	defer { listener.close() or {} }
	listener.set_accept_timeout(20 * time.millisecond)
	address := listener.addr()!.str()
	halt := chan bool{cap: 1}
	worker := spawn browser_http(mut listener, 'page', '/result/nonce/42', halt)
	assert browser_test_get(address, '/result/nonce/42')!.starts_with('HTTP/1.1 200 ')
	halt <- true
	result := worker.wait()
	assert result.error == '' && result.callback == 'GET /result/nonce/42 HTTP/1.1'
}

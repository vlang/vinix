// SPDX-License-Identifier: GPL-2.0-or-later
// Localhost only; no browser, account, guest, or credential operations.
module main

import browsertransfer
import crypto.sha256
import net
import os
import time

fn writer(address string, body []u8, hold bool) ! {
	mut connection := net.dial_tcp(address)!
	defer { connection.close() or {} }
	connection.set_write_deadline(time.now().add(time.second))
	if body.len > 0 { connection.write(body)! }
	if hold { time.sleep(400 * time.millisecond) }
}

fn stream_case(root string, name string, body []u8, pin browsertransfer.Expected, hold bool, wanted string) ! {
	mut listener := net.listen_tcp(.ip, '127.0.0.1:0')!
	defer { listener.close() or {} }
	worker := spawn writer(listener.addr()!.str(), body, hold)
	mut connection := listener.accept()!
	defer { connection.close() or {} }
	mut failure := ''
	browsertransfer.receive_stream(mut connection, root + '/' + name, pin, time.now().add(200 * time.millisecond)) or {
		failure = err.msg()
	}
	worker.wait()!
	if wanted == '' {
		assert failure == '', failure
		assert browsertransfer.file_hash(root + '/' + name)! == pin.sha256
	} else {
		assert failure != '', name + ' unexpectedly accepted'
		if wanted != 'timeout' {
			assert failure.contains(wanted), failure
		}
	}
	assert os.lstat(root + '/' + name)!.mode & 0o777 == 0o600
}

fn main() {
	selftest() or {
		eprintln(err.msg())
		exit(1)
	}
}

fn stalled_peer(mut listener net.TcpListener) ! {
	mut connection := listener.accept()!
	defer { connection.close() or {} }
	time.sleep(500 * time.millisecond)
}

fn selftest() ! {
	if _ := browsertransfer.checked('relative-output') {
		return error('relative transfer path accepted')
	}
	mut rejected_checkout := false
	browsertransfer.external_path(os.getwd() + '/transfer-results') or { rejected_checkout = true }
	assert rejected_checkout, 'Git checkout artifact output accepted'
	root := os.join_path(os.real_path(os.temp_dir()), 'vinix-browser-tcp-selftest-' + os.getpid().str())
	os.mkdir(root)!
	defer { os.rmdir_all(root) or {} }
	// Includes NUL/newlines and crosses multiple fixed 64 KiB read buffers.
	body := ('exact\x00binary\n'.repeat(12000)).bytes()
	pin := browsertransfer.expected(sha256.sum(body).hex(), body.len.str())!
	stream_case(root, 'valid', body, pin, false, '')!
	stream_case(root, 'truncated', body[..body.len - 1], pin, false, 'truncated')!
	stream_case(root, 'oversize', body, browsertransfer.expected(pin.sha256, (pin.bytes - 1).str())!, false, 'extra')!
	stream_case(root, 'wronghash', body, browsertransfer.expected('0'.repeat(64), pin.bytes.str())!, false, 'hash')!
	stream_case(root, 'missing-eof', body, pin, true, 'timeout')!
	if _ := browsertransfer.expected(pin.sha256, '033') {
		return error('noncanonical size accepted')
	}
	if _ := browsertransfer.expected(pin.sha256, (browsertransfer.limit + 1).str()) {
		return error('archive limit ignored')
	}
	serial := root + '/source.serial'
	header := 'VINIX-BROWSER-RESULTS-1 BEGIN ' + pin.sha256 + ' ' + pin.bytes.str() + ' ' + ((pin.bytes + 511) / 512).str() + '\n'
	os.write_file(serial, 'unrelated UART chatter\n' + header + 'damaged historical UART export\n')!
	sha, size := browsertransfer.source_pin(serial, pin)!
	assert sha == sha256.sum(os.read_bytes(serial)!).hex() && size == u64(os.file_size(serial))
	os.write_file(serial, header + header)!
	if _, _ := browsertransfer.source_pin(serial, pin) { return error('duplicate BEGIN accepted') }
	os.write_file(serial, header.replace(pin.sha256, '0'.repeat(64)))!
	if _, _ := browsertransfer.source_pin(serial, pin) {
		return error('wrong source BEGIN accepted')
	}
	// A peer accepting without reading must not block send() indefinitely.
	large := root + '/sender-archive'
	os.write_file(large, 's'.repeat(8 * 1024 * 1024))!
	large_pin := browsertransfer.expected(browsertransfer.file_hash(large)!, os.file_size(large).str())!
	mut listener := net.listen_tcp(.ip, '127.0.0.1:0')!
	defer { listener.close() or {} }
	address := listener.addr()!.str()
	worker := spawn stalled_peer(mut listener)
	mut failed := false
	watch := time.new_stopwatch()
	browsertransfer.send(large, address, large_pin, 100 * time.millisecond) or { failed = true }
	assert failed && watch.elapsed() < 2 * time.second, 'stalled sender deadline ignored'
	worker.wait()!
	println('BROWSER-TCP SELF-TEST PASS localhost exact-binary fixed-buffers truncated oversized wronghash EOF-deadline source-BEGIN bounds stalled-sender-deadline')
}

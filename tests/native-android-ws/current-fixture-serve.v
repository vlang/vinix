// SPDX-License-Identifier: GPL-2.0-or-later
// Deliver one signed test APK to the owned QEMU via its host-loopback alias.
module main

import crypto.sha256
import net
import os
import time

fn main() {
	if os.args.len != 2 { panic('usage: current-fixture-serve APK') }
	size := os.file_size(os.args[1])
	if size == 0 || size > 4 * 1024 * 1024 { panic('bounded APK required') }
	data := os.read_bytes(os.args[1])!
	mut listener := net.listen_tcp(.ip, '127.0.0.1:28441')!
	defer { listener.close() or {} }
	listener.set_accept_timeout(60 * time.second)
	println('FIXTURE-SERVE-READY sha256=' + sha256.sum(data).hex())
	mut client := listener.accept()!
	defer { client.close() or {} }
	client.set_read_timeout(5 * time.second)
	client.set_write_timeout(5 * time.second)
	mut header := []u8{cap: 8192}
	mut chunk := [1024]u8{}
	for !header.bytestr().contains('\r\n\r\n') {
		count := client.read(mut chunk)!
		if count == 0 || header.len + count > 8192 { panic('bounded request required') }
		header << chunk[..count]
	}
	if !header.bytestr().starts_with('GET /probe.apk HTTP/1.') { panic('fixture GET required') }
	client.write_string('HTTP/1.1 200 OK\r\nContent-Length: ${data.len}\r\nConnection: close\r\nContent-Type: application/vnd.android.package-archive\r\n\r\n')!
	client.write(data)!
	println('FIXTURE-SERVE-PASS bytes=${data.len}')
}

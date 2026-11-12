// SPDX-License-Identifier: GPL-2.0-or-later
// Accept one local TLS ClientHello and deliberately withhold the handshake.
module main

import net
import time

fn main() {
	mut listener := net.listen_tcp(.ip, '127.0.0.1:28443')!
	defer { listener.close() or {} }
	listener.set_accept_timeout(60 * time.second)
	println('CERTIFICATE-STALL-READY')
	mut client := listener.accept()!
	defer { client.close() or {} }
	client.set_read_timeout(5 * time.second)
	mut hello := [4096]u8{}
	count := client.read(mut hello)!
	if count < 5 || hello[0] != 22 || hello[1] != 3 { panic('TLS ClientHello required') }
	println('CERTIFICATE-STALL-CLIENT-HELLO bytes=${count}')
	time.sleep(10 * time.second)
	println('CERTIFICATE-STALL-END')
}

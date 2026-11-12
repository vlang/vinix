// SPDX-License-Identifier: GPL-2.0-or-later
module main

import net.openssl
import os
import time

fn handle(mut conn openssl.SSLConn, index int) {
	conn.duration = 10 * time.second
	conn.write('R'.bytes()) or { return }
	println('TLS-LIFETIME-SERVER-ACCEPT ${index}')
	time.sleep(4 * time.second)
	conn.shutdown() or {}
}

fn main() {
	if os.args.len != 3 { panic('usage: tls-lifetime-server --prepare|--serve FRESH_STATE') }
	root := os.abs_path(os.args[2])
	if os.args[1] == '--prepare' {
		if os.exists(root) { panic('fresh state required') }
		os.mkdir_all(root)!
		args := ['/opt/homebrew/opt/openssl@3/bin/openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes',
			'-keyout', root + '/key.pem', '-out', root + '/cert.pem', '-days', '2',
			'-subj', '/CN=Vinix TLS lifetime fixture', '-addext', 'subjectAltName=IP:10.0.2.2']
		if os.system_args(args) != 0 { panic('fixture certificate generation failed') }
		os.chmod(root + '/key.pem', 0o600)!
		return
	}
	if os.args[1] != '--serve' { panic('unknown operation') }
	mut listener := openssl.new_ssl_listener('127.0.0.1:28444', openssl.SSLConnectConfig{
		cert: root + '/cert.pem'
		cert_key: root + '/key.pem'
	}, family: .ip)!
	defer { listener.shutdown() or {} }
	println('TLS-LIFETIME-SERVER-READY loopback=127.0.0.1:28444')
	mut workers := []thread{}
	for index in 0 .. 4 {
		mut conn := listener.accept()!
		// Read/write clients deliberately wait against a silent authenticated
		// peer. Each has an independent connection; no public service is used.
		workers << spawn handle(mut conn, index)
	}
	workers.wait()
}

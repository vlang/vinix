// SPDX-License-Identifier: GPL-2.0-or-later
// Reuse the complete serial and packet verdict for an alternate boot medium.
module main

import os
import systemhost

fn run() ! {
	if os.args.len != 4 || os.args[1] !in ['aarch64', 'amd64'] {
		return error('usage: security-verdict aarch64|amd64 SERIAL PCAP')
	}
	serial := os.read_file(os.args[2])!
	mut failures := systemhost.security_verdict(serial, 'security', os.args[1], true)
	if serial.contains('OPENBSD SECURITY WIRE: sent') {
		failures << systemhost.security_packets(systemhost.capture_frames(os.args[3])!)
	}
	if failures.len > 0 { return error(failures.join('\n')) }
	println('OPENBSD SECURITY serial and packet verdict PASS')
}

fn main() {
	run() or {
		eprintln(err)
		exit(1)
	}
}

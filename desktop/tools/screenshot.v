// SPDX-License-Identifier: GPL-2.0-or-later
import os
import policyhost
import screenhost

fn main() {
	guard := policyhost.own_commands()
	defer { guard.close() }
	if os.args.len == 2 && os.args[1] in ['--help', '-h'] {
		println('Usage: screenshot.sh [OUTPUT.png|OUTPUT.ppm|OUTPUT.ext]')
		return
	}
	if os.args.len > 2 {
		eprintln('Usage: screenshot.sh [OUTPUT.png|OUTPUT.ppm|OUTPUT.ext]')
		exit(2)
	}
	output := if os.args.len == 2 { os.args[1] } else { '/tmp/vinix-screen.png' }
	socket := os.getenv_opt('VINIX_QMP_SOCKET') or { '/tmp/vinix-qmp' }
	screenhost.capture(socket, output) or {
		eprintln(err.msg())
		exit(1)
	}
	println(output)
}

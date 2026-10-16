// SPDX-License-Identifier: GPL-2.0-or-later
module main

import hwhost
import os

fn main() {
	exit(hwhost.run_suite(hwhost.Suite{
		name: 'package-launch-socket'
		guest: 'tests/packages/launch-socket-guest'
		module_paths: ['.', 'tools/accounts']
		programs: [hwhost.Program{ source: 'tools/packages/pkglaunch/streams_test.v', path: 'usr/share/package-fixtures/streams' }]
		scenarios: [hwhost.Scenario{
			name: 'packages-launch-socket'
			arches: ['aarch64', 'x86_64']
			about: 'UNIX EOF readiness after read/recvfrom/recvmsg, simultaneous shutdown, partial launch requests and descriptor transport'
			required: ['HWTEST START packages-launch-socket', 'LAUNCH SOCKET EOF and descriptor regressions PASS', 'HWTEST PASS packages-launch-socket']
			ending: .poweroff
			timeout: 120
		}]
	}, os.args[1..], @FILE))
}

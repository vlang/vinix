// SPDX-License-Identifier: GPL-2.0-or-later
// Boot a kernel in QEMU with the peer-login fixture as an ordinary child of
// a small init and judge what it prints. The machine-booting half is the
// hardware tests' (hwhost). README.md says what the fixture checks.
module main

import hwhost
import os

fn main() {
	exit(hwhost.run_suite(hwhost.Suite{
		name:      'socket-peer-login'
		guest:     'tests/socket-peer-login/vm'
		programs:  [
			hwhost.Program{
				source: 'tests/socket-peer-login/guest.v'
				path:   'usr/bin/peer-login'
			},
		]
		scenarios: [
			hwhost.Scenario{
				name:      'peer-login'
				about:     'SO_PEERLOGIN records, failed and repeated connects, peer close, 32 concurrent connect rounds and three logins seen from the system'
				arches:    ['aarch64', 'x86_64']
				required:  [
					'HWTEST START peer-login',
					'PEER-LOGIN failed-retry repeated-connect peer-close PASS',
					'PEER-LOGIN concurrent-connect rounds=32 PASS',
					'PEER-LOGIN ALL PASS',
					'PEER-LOGIN across-logins',
					'PEER-LOGIN unconnected-and-foreign refusals PASS',
					'HWTEST PASS peer-login',
				]
				forbidden: ['PEER-LOGIN VM FAIL', 'PEER-LOGIN FAIL', 'HWTEST FAIL', 'V panic:']
				ending:    .poweroff
				timeout:   120
			},
		]
	}, os.args[1..], @FILE))
}

// SPDX-License-Identifier: GPL-2.0-or-later
module main

import fixturehost
import hosttest
import os
import policyhost

fn run() ! {
	hosttest.parse_arguments(os.args[1..], [], 0, 'Native V Wi-Fi protocol and MMIO fixtures',
		'Runs both immutable C/V host comparisons under ASan/UBSan.')!
	for suite in ['run-protocol', 'run-platform'] {
		fixturehost.inherited_command_environment_preferred([hosttest.root() + '/tests/m1-wifi/' + suite],
			policyhost.environment(), policyhost.caller_arch())!
	}
	println('PASS V Wi-Fi C ABI, ASan/UBSan and explicit allocator sites')
}

fn main() {
	run() or {
		eprintln(err.msg())
		exit(1)
	}
}

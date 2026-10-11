// SPDX-License-Identifier: GPL-2.0-or-later
module main

import fixturehost
import hosttest
import policyhost

fn main() {
	for family in ['kernel-cpu', 'kernel-job-control', 'kernel-sysvmsg', 'kernel-retention', 'stack-protector', 'elf-text', 'userland-demo', 'uname'] {
		output := fixturehost.capture_in_preferred([hosttest.root() + '/tests/' + family + '/run', '--help'],
			'', policyhost.environment(), false, '/tmp', false, policyhost.caller_arch()) or { panic(err) }
		assert output.contains('Usage:')
		println('Cold native front outside checkout PASS: ' + family)
	}
}

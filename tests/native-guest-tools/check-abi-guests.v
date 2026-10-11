// SPDX-License-Identifier: GPL-2.0-or-later
module main

import guesthost
import os

// Boot an already cross-built qualification profile with the same image,
// controller and evidence path as the public native command.
fn main() {
	if os.args.len < 5 {
		eprintln('Usage: check-abi-guests STATE KERNEL ARCH SUITE [reuse|readable|baseline]')
		exit(2)
	}
	variant := if os.args.len > 5 { os.args[5] } else { '' }
	build := guesthost.AbiBuild{
		family:          os.args[4]
		arch:            os.args[3]
		case_name:       if variant == 'reuse' { 'reuse' } else { 'full' }
		expect_readable: variant == 'readable'
		baseline:        variant == 'baseline'
		timeout:         120
	}
	result := guesthost.run_abi_guest(os.args[1], os.args[2], build, true) or {
		eprintln(err.msg())
		exit(1)
	}
	exit(result)
}

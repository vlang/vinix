// SPDX-License-Identifier: GPL-2.0-or-later
module main

import accountmanifest
import os

fn main() {
	if os.args.len != 4 {
		eprintln('usage: verify APK EXPECTED_PACKAGE EXPECTED_ACTIVITY_CLASS')
		exit(2)
	}
	accountmanifest.verify_activity(os.args[1], os.args[2], os.args[3]) or {
		eprintln('ACCOUNT-MANIFEST-FAIL: ${err}')
		exit(1)
	}
	println('ACCOUNT-MANIFEST-PASS package=${os.args[2]} activity=${os.args[3]}')
}

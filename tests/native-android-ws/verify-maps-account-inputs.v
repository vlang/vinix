// SPDX-License-Identifier: GPL-2.0-or-later
// Check complete retained account/framework bundles before media assembly.
module main

import mapsaccountstage as stage
import os

fn run(args []string) ! {
	if args.len !in [7, 9, 11] {
		return error('usage: verify-maps-account-inputs FRAMEWORK FRAMEWORK_SEAL JAR_SHA DEX_SHA ACCOUNT ACCOUNT_SEAL [NATIVE NATIVE_SEAL [LAUNCH LAUNCH_SEAL]]')
	}
	framework := stage.load_bundle(args[1], args[2])!
	profile := stage.verify_framework(framework, args[2], args[3], args[4])!
	account := stage.load_bundle(args[5], args[6])!
	dependencies := stage.verify_account(account)!
	if args.len >= 9 {
		native := stage.load_bundle(args[7], args[8])!
		stage.verify_native(native, framework)!
		if args.len == 11 {
			launch := stage.load_bundle(args[9], args[10])!
			stage.verify_launch(launch, framework, native)!
			stage.recheck(launch)!
			println('MAPS-LAUNCH-INPUTS PASS seal=' + launch.seal)
		}
		stage.recheck(native)!
		println('MAPS-NATIVE-INPUTS PASS seal=' + native.seal)
	}
	stage.recheck(framework)!
	stage.recheck(account)!
	println('MAPS-ACCOUNT-INPUTS PASS framework=' + profile.profile + ' framework_seal=' + framework.seal
		+ ' account_seal=' + account.seal + ' dependencies=' + dependencies.len.str())
}

fn main() {
	run(os.args) or { eprintln(err); exit(1) }
}

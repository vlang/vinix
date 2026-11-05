// SPDX-License-Identifier: GPL-2.0-or-later
// Parallel format-2 preparation and read-only admission. No guest owner.
module main

import os
import tests.packages.audiocontinue

fn continuation() ! {
	args := os.args[1..]
	// Leaf invoked only under the preparation engine's nativeguard. The
	// unchanged original checker remains responsible for complete bundle audit.
	if args.len == 4 && args[0] == '--kernel-audit' {
		audiocontinue.kernel_audit_leaf2(args[1], args[2], args[3])!
		return
	}
	if args.len != 3 || args[0] !in ['--prepare', '--verify', '--run-admission'] {
		return error('use --prepare PLAN SHA256 | --verify PREPARATION SHA256 | --run-admission PREPARATION SHA256')
	}
	if args[0] == '--prepare' {
		sha := audiocontinue.prepare2(args[1], args[2])!
		println('AUDIO FORMAT-2 PREPARATION PASS ' + sha)
		return
	}
	p := audiocontinue.validate_preparation2(args[1], args[2])!
	if args[0] == '--verify' {
		println('AUDIO FORMAT-2 PREPARATION CHECK PASS ' + args[2])
		return
	}
	plan := audiocontinue.load_plan2(p.plan_path, p.plan_sha256)!
	legacy := audiocontinue.load_legacy2(plan)!
	audiocontinue.check_budget2(plan, legacy, true)!
	println('AUDIO FORMAT-2 RUN BUDGET ADMISSION PASS; no run claimed or launched')
}

fn main() {
	continuation() or { eprintln('audio-portal-continuation: ' + err.msg()); exit(1) }
}

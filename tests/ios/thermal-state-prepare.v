// SPDX-License-Identifier: GPL-2.0-or-later
// Prepare fresh host and guest runs from the sealed launch-resource checkpoint.
module main

import crypto.sha256
import os

fn capture(out string, label string, args []string) ! {
	mut process := os.new_process(args[0])
	process.set_args(args[1..])
	process.set_redirect_stdio_merged()
	process.run()
	output := process.stdout_slurp()
	process.wait()
	code := process.code
	process.close()
	os.write_file(out + '/' + label + '.log', 'COMMAND: ' + args.map(os.quoted_path(it)).join(' ') + '\n' + output)!
	os.write_file(out + '/' + label + '.status.txt', code.str() + '\n')!
	if code != 0 { return error(label + ' failed: ' + output) }
	println(label + ': PASS')
}

fn main() {
	if os.args.len != 3 { panic('usage: thermal-state-prepare EXTERNAL_OUT PRIOR_STORYBOARD_BUNDLE') }
	root := os.real_path(os.getwd())
	out := os.real_path(os.args[1])
	prior := os.real_path(os.args[2])
	if !os.is_dir(out) || out == root || out.starts_with(root + '/') || os.exists(out + '/manifest.sha256') {
		panic('output must be an existing, external, unsealed checkpoint')
	}
	if sha256.hexhash(os.read_file(prior + '/manifest.sha256')!) != '3ae5be94ecc0c7664a0c41ecdef94fac56e660e7319596ae8824a028a8816619' {
		panic('unexpected prior checkpoint manifest')
	}
	capture(out, 'prior-check', [prior + '/compiled-storyboard-evidence', 'check', prior])!
	if !os.is_dir(out + '/application') { os.cp_all(prior + '/application', out + '/application', false)! }
	os.write_file(out + '/provenance.txt', 'Application and five original IPA launch resources copied from ' + prior + '/application.\nPrior manifest SHA-256: 3ae5be94ecc0c7664a0c41ecdef94fac56e660e7319596ae8824a028a8816619\nFresh host and guest tests; advertising skipped by diagnostic probe.\nNSProcessInfo thermalState uses the documented nominal fallback without a Darwin thermal-awareness provider.\nASan leak detection disabled; ASan/UBSan errors remain fatal.\n')!
	os.mkdir_all(out + '/tmp')!
	os.setenv('TMPDIR', out + '/tmp', true)
	os.setenv('V_RESOURCE_PATH', root + '/build/ios/fortnite/ns-calendar-checks/toolchain', true)
	os.setenv('V_MACOS_V3_NO_FALLBACK', '1', true)
	os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	os.setenv('VINIX_IOS_CHECK_NAME', 'notification-center-checks', true)
	v := root + '/build/ios/fortnite/ns-calendar-checks/toolchain/v'
	for tool in ['notification-checks', 'notification-vm', 'application-badge-run', 'compiled-storyboard-input-inventory', 'thermal-state-evidence'] {
		name := if tool == 'application-badge-run' { 'checkpoint-run' }
			else if tool == 'compiled-storyboard-input-inventory' { 'inventory-inputs' } else { tool }
		capture(out, 'tool-' + name, [v, '-nocache', '-prod', '-gc', 'none', '-cc', 'clang', '-path',
			'@vlib|' + root + '/compat/ios|' + root + '/tests/ios|@vmodules', '-o', out + '/' + name,
			root + '/tests/ios/' + tool + '.v'])!
	}
}

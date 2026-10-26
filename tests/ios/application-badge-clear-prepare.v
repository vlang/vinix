// SPDX-License-Identifier: GPL-2.0-or-later
// Prepare a fresh, external checkpoint without altering historical evidence.
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
	if os.args.len != 3 { panic('usage: application-badge-clear-prepare EXTERNAL_OUT PRIOR_BADGE_BUNDLE | --finish-tools EXTERNAL_OUT') }
	root := os.real_path(os.getwd())
	finish := os.args[1] == '--finish-tools'
	out := os.real_path(os.abs_path(os.args[if finish { 2 } else { 1 }]))
	if out == root || out.starts_with(root + '/') { panic('output must be external') }
	if finish {
		if !os.is_dir(out) || os.exists(out + '/manifest.sha256') { panic('finishing requires an existing, unsealed bundle') }
	} else {
		if os.exists(out) { panic('output must be fresh') }
		prior := os.real_path(os.args[2])
		manifest := os.read_file(prior + '/manifest.sha256')!
		if sha256.hexhash(manifest) != 'c03b2a1725ee064cbf84f516723f1fa209915038bca24cc23e88acac13fdbca5' {
			panic('unexpected prior badge checkpoint manifest')
		}
		os.mkdir_all(out + '/tmp')!
		for name in ['host-window', 'host-storyboard', 'host-alert-catalyst', 'application'] {
			os.cp_all(prior + '/' + name, out + '/' + name, false)!
		}
		// Retain the original window checkpoint attribution for the unchanged fixtures.
		os.cp(prior + '/inherited-artifacts.txt', out + '/inherited-artifacts.txt')!
	}
	os.setenv('TMPDIR', out + '/tmp', true)
	os.setenv('V_RESOURCE_PATH', root + '/build/ios/fortnite/ns-calendar-checks/toolchain', true)
	os.setenv('V_MACOS_V3_NO_FALLBACK', '1', true)
	os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	v := root + '/build/ios/fortnite/ns-calendar-checks/toolchain/v'
	// The checker records the observed application boundary after the probe.
	selected := if finish { ['image-initializers-input-inventory', 'application-badge-clear-evidence'] }
		else { ['notification-checks', 'notification-vm', 'application-badge-run', 'image-initializers-input-inventory'] }
	for tool in selected {
		name := if tool == 'image-initializers-input-inventory' { 'inventory-inputs' } else { tool }
		capture(out, 'tool-' + name, [v, '-nocache', '-prod', '-gc', 'none', '-cc', 'clang',
			'-path', '@vlib|' + root + '/compat/ios|' + root + '/tests/ios|@vmodules',
			'-o', out + '/' + name, root + '/tests/ios/' + tool + '.v'])!
	}
}

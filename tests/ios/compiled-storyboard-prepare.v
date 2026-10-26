// SPDX-License-Identifier: GPL-2.0-or-later
// Finish a fresh checkpoint without importing historical test results.
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
	if os.args.len != 4 { panic('usage: compiled-storyboard-prepare EXTERNAL_OUT PRIOR_BADGE_CLEAR_BUNDLE RESOURCE_APP') }
	root := os.real_path(os.getwd())
	out := os.real_path(os.args[1])
	prior := os.real_path(os.args[2])
	resources := os.real_path(os.args[3])
	if !os.is_dir(out) || out == root || out.starts_with(root + '/') || os.exists(out + '/manifest.sha256') {
		panic('output must be an existing, external, unsealed checkpoint')
	}
	if sha256.hexhash(os.read_file(prior + '/manifest.sha256')!) != 'a3abbb60855bf8871a1462fd2866296ed2e20cda126e882fee8a14f8ba21b454' {
		panic('unexpected prior checkpoint manifest')
	}
	if !os.is_dir(out + '/application') { os.cp_all(prior + '/application', out + '/application', false)! }
	for path in ['Info.plist', 'LaunchScreen.storyboardc/Info.plist', 'LaunchScreen.storyboardc/LaunchScreen.nib',
		'LaunchScreen.storyboardc/01J-lp-oVM-view-Ze5-6b-2t3.nib', 'LaunchScreenIOS.png'] {
		os.mkdir_all(os.dir(out + '/application/' + path))!
		os.cp(resources + '/' + path, out + '/application/' + path)!
	}
	os.write_file(out + '/resource-provenance.txt', 'Executable/frameworks copied from the previously sealed application-badge-clear-20261026 application.\nPrior manifest SHA-256: a3abbb60855bf8871a1462fd2866296ed2e20cda126e882fee8a14f8ba21b454\nFive launch resources extracted from com.epicgames.FortniteGame_42.30.1_und3fined(1).ipa.\nResource source: ' + resources + '\nAll test runs in this checkpoint are fresh; host-initial contains exploratory failures superseded by host.\nASan leak detection disabled; ASan/UBSan errors remain fatal.\n')!
	os.mkdir_all(out + '/tmp')!
	os.setenv('TMPDIR', out + '/tmp', true)
	os.setenv('V_RESOURCE_PATH', root + '/build/ios/fortnite/ns-calendar-checks/toolchain', true)
	os.setenv('V_MACOS_V3_NO_FALLBACK', '1', true)
	os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	os.setenv('VINIX_IOS_CHECK_NAME', 'notification-center-checks', true)
	os.setenv('ASAN_OPTIONS', 'detect_leaks=0:halt_on_error=1', true)
	os.setenv('UBSAN_OPTIONS', 'halt_on_error=1', true)
	v := root + '/build/ios/fortnite/ns-calendar-checks/toolchain/v'
	common := [v, '-nocache', '-prod', '-gc', 'none', '-cc', 'clang', '-path',
		'@vlib|' + root + '/compat/ios|' + root + '/tests/ios|@vmodules']
	for tool in ['notification-checks', 'notification-vm', 'application-badge-run',
		'compiled-storyboard-input-inventory', 'compiled-storyboard-evidence', 'nib-archive-checks'] {
		name := if tool == 'application-badge-run' { 'checkpoint-run' }
			else if tool == 'compiled-storyboard-input-inventory' { 'inventory-inputs' } else { tool }
		mut args := common.clone()
		if tool == 'nib-archive-checks' { args << ['-cflags', '-fsanitize=address,undefined', '-ldflags', '-fsanitize=address,undefined'] }
		args << ['-o', out + '/' + name, root + '/tests/ios/' + tool + '.v']
		capture(out, 'tool-' + name, args)!
	}
	capture(out, 'nib-archive-checks', [out + '/nib-archive-checks'])!
	capture(out, 'nib-real-resources', [out + '/nib-archive-checks', out + '/application/LaunchScreen.storyboardc/LaunchScreen.nib',
		out + '/application/LaunchScreen.storyboardc/01J-lp-oVM-view-Ze5-6b-2t3.nib'])!
	capture(out, 'build-storyboard', [out + '/notification-vm', 'build-storyboard', out])!
	capture(out, 'storyboard', [out + '/notification-vm', 'storyboard', out])!
}

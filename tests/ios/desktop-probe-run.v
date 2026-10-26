// SPDX-License-Identifier: GPL-2.0-or-later
// Prepare and run a bounded, compositor-free desktop connection for Fortnite.
module main

import crypto.sha256
import os

const prior_manifest = 'd815747b8f635da1853425374b47f7f61015de03d941959c8bd6b03ea357d53e'
const reused_targets = ['application-badge-checks', 'string-float-checks', 'string-cstring-checks',
	'bundle-receipt-checks', 'cf-string-output-checks', 'search-path-checks', 'home-directory-checks',
	'inline-pthread-self-checks', 'dictionary-snapshot-checks', 'block-byref-checks',
	'processinfo-checks', 'vm-probe-checks', 'run-ios-gles']

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
	if os.args.len < 3 || os.args[1] !in ['prepare', 'tools', 'build', 'host', 'probe'] {
		panic('usage: desktop-probe-run prepare|tools OUT PRIOR_THERMAL_BUNDLE | build|host|probe OUT')
	}
	root := os.real_path(os.getwd())
	out := os.abs_path(os.args[2])
	if out == root || out.starts_with(root + '/') || os.exists(out + '/manifest.sha256') {
		panic('output must be external and unsealed')
	}
	os.mkdir_all(out + '/tmp')!
	os.setenv('TMPDIR', out + '/tmp', true)
	os.setenv('V_RESOURCE_PATH', root + '/build/ios/fortnite/ns-calendar-checks/toolchain', true)
	os.setenv('V_MACOS_V3_NO_FALLBACK', '1', true)
	os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	os.setenv('VINIX_IOS_CHECK_NAME', 'notification-center-checks', true)
	os.setenv('ASAN_OPTIONS', 'detect_leaks=0:halt_on_error=1', true)
	os.setenv('UBSAN_OPTIONS', 'halt_on_error=1', true)
	v := root + '/build/ios/fortnite/ns-calendar-checks/toolchain/v'
	if os.args[1] in ['prepare', 'tools'] {
		if os.args.len != 4 { panic('prepare/tools requires prior bundle') }
		prior := os.real_path(os.args[3])
		if sha256.hexhash(os.read_file(prior + '/manifest.sha256')!) != prior_manifest {
			panic('unexpected prior checkpoint')
		}
		os.cp(prior + '/manifest.sha256', out + '/prior-manifest.sha256')!
		if os.args[1] == 'tools' {
			for tool in ['desktop-probe-run', 'desktop-probe-evidence'] {
				// Optimize streaming hashes without disabling V assertions with -prod.
				capture(out, 'tool-' + tool, [v, '-nocache', '-gc', 'none', '-cc', 'clang',
					'-cflags', '-O2', '-o', out + '/' + tool, root + '/tests/ios/' + tool + '.v'])!
			}
			return
		}
		capture(out, 'prior-check', [prior + '/thermal-state-evidence', 'check', prior])!
		if !os.exists(out + '/application') {
			capture(out, 'clone-application', ['/bin/cp', '-cR', prior + '/application', out + '/application'])!
		}
		mut reused := []string{}
		for target in reused_targets {
			for suffix in ['', '.c'] {
				os.cp(prior + '/' + target + suffix, out + '/' + target + suffix)!
				reused << target + suffix
			}
		}
		os.write_file(out + '/reused-files.txt', reused.join('\n') + '\n')!
		os.write_file(out + '/provenance.txt', 'Prior bundle: ' + prior + '\nPrior manifest SHA-256: ' + prior_manifest +
			'\nApplication and reused-files.txt targets preserved from source 8f700726447c1f901faff30071069a621152b86f.\nFresh supervisor and UIKit window builds; advertising skipped.\nVAPP peer has no compositor; a view-tree image is not a rendered game frame.\nASan leak detection disabled; ASan/UBSan errors remain fatal.\n')!
		for tool in ['notification-checks', 'notification-vm', 'compiled-storyboard-input-inventory'] {
			name := if tool == 'compiled-storyboard-input-inventory' { 'inventory-inputs' } else { tool }
			capture(out, 'tool-' + name, [v, '-nocache', '-prod', '-gc', 'none', '-cc', 'clang', '-path',
				'@vlib|' + root + '/compat/ios|' + root + '/tests/ios|@vmodules', '-o', out + '/' + name,
				root + '/tests/ios/' + tool + '.v'])!
		}
	} else if os.args[1] == 'build' {
		for mode in ['build-init', 'build-window'] {
			capture(out, mode, [out + '/notification-vm', mode, out])!
		}
	} else if os.args[1] == 'host' {
		// Assertions must remain enabled in both the peer checks and UIKit fixture.
		capture(out, 'peer-build', [v, '-nocache', '-gc', 'none', '-cc', 'clang',
			'-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer',
			'-ldflags', '-fsanitize=address,undefined', '-path', '@vlib|' + root + '/tests/ios|@vmodules',
			'-o', out + '/desktop-peer-checks', root + '/tests/ios/desktop-peer-checks.v'])!
		capture(out, 'window-host', [out + '/notification-checks', 'window-host', out + '/host'])!
		capture(out, 'peer-host', [out + '/desktop-peer-checks', out + '/host/NotificationChecks.app/Contents/MacOS/center-host'])!
		os.setenv('SWIFT_DETERMINISTIC_HASHING', '1', true)
		capture(out, 'peer-host-deterministic', [out + '/desktop-peer-checks', out + '/host/NotificationChecks.app/Contents/MacOS/center-host'])!
	} else {
		os.setenv('VINIX_IOS_PROBE_MEMORY_MAX', '2147483648', true)
		os.setenv('VINIX_IOS_VM_GZIP_LEVEL', '9', true)
		os.setenv('VINIX_IOS_PROBE_DESKTOP', '1', true)
		os.setenv('VINIX_IOS_STORYBOARD_BUNDLE', out + '/application', true)
		capture(out, 'probe-no-ads', [out + '/notification-vm', 'probe-no-ads', out])!
	}
}

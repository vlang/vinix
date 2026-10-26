// SPDX-License-Identifier: GPL-2.0-or-later
// Preserve the main-selector checkpoint and probe UIView tag lookup.
module main

import crypto.sha256
import os

const prior_manifest = '8897bae68e6d221efa13011a41d46463115a29849f5385f85a443955c2218b41'
const reused_targets = ['application-badge-checks', 'window-checks',
	'string-float-checks', 'string-cstring-checks', 'bundle-receipt-checks',
	'cf-string-output-checks', 'search-path-checks', 'home-directory-checks',
	'inline-pthread-self-checks', 'dictionary-snapshot-checks', 'block-byref-checks',
	'processinfo-checks', 'vm-probe-checks', 'main-selector-checks']

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
	if code != 0 { return error(label + ' failed; see ' + out + '/' + label + '.log') }
	println(label + ': PASS')
}

fn audit(root string, out string, v string, revision string) ! {
	if revision.len != 40 || revision.bytes().any(!it.is_hex_digit()) { return error('audit requires a full source revision') }
	audit_head := os.exec(['git', 'rev-parse', 'HEAD'])
	if audit_head.exit_code != 0 { return error(audit_head.output) }
	audit_revision := audit_head.output.trim_space()
	os.write_file(out + '/audit-revision.txt', audit_revision + '\n')!
	for name in ['compiled-storyboard-input-inventory', 'view-tag-evidence', 'view-tag-run'] {
		path := 'tests/ios/' + name + '.v'
		source := os.exec(['git', 'show', audit_revision + ':' + path])
		if source.exit_code != 0 { return error(source.output) }
		target := out + '/audit-source/' + path
		os.mkdir_all(os.dir(target))!
		os.write_file(target, source.output)!
		binary := if name == 'compiled-storyboard-input-inventory' { 'audit-inventory-inputs' } else { name }
		label := if name == 'compiled-storyboard-input-inventory' { 'audit-inventory-build' }
			else if name == 'view-tag-evidence' { 'audit-checker-build' } else { 'audit-driver-build' }
		capture(out, label, [v, '-nocache', '-gc', 'none', '-cc', 'clang', '-cflags', '-O2',
			'-o', out + '/' + binary, target])!
	}
	capture(out, 'audit-inventory', [out + '/audit-inventory-inputs', root, out, revision])!
}

fn main() {
	if os.args.len < 3 || os.args[1] !in ['prepare', 'fixture', 'build', 'probe', 'host', 'audit'] {
		panic('usage: view-tag-run prepare OUT PRIOR | fixture|build|probe|host OUT | audit OUT REVISION')
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
	if os.args[1] == 'audit' {
		if os.args.len != 4 { panic('audit requires source revision') }
		audit(root, out, v, os.args[3])!
	} else if os.args[1] == 'prepare' {
		if os.args.len != 4 { panic('prepare requires the prior main-selector bundle') }
		if os.exists(out + '/prior-manifest.sha256') { panic('already prepared') }
		prior := os.real_path(os.args[3])
		if sha256.hexhash(os.read_file(prior + '/manifest.sha256')!) != prior_manifest { panic('unexpected prior checkpoint') }
		capture(out, 'prior-check', [prior + '/main-selector-evidence', 'check', prior])!
		os.cp(prior + '/manifest.sha256', out + '/prior-manifest.sha256')!
		os.write_file(out + '/prior-bundle.txt', prior + '\n')!
		capture(out, 'clone-application', ['/bin/cp', '-cR', prior + '/application', out + '/application'])!
		mut reused := []string{}
		for target in reused_targets {
			for suffix in ['', '.c'] {
				os.cp(prior + '/' + target + suffix, out + '/' + target + suffix)!
				reused << target + suffix
			}
		}
		os.write_file(out + '/reused-files.txt', reused.join('\n') + '\n')!
		os.write_file(out + '/provenance.txt', 'Prior bundle: ' + prior + '\nPrior manifest SHA-256: ' + prior_manifest +
			'\nApplication and 14 fixtures reused; view-tag fixture, supervisor and runner rebuilt.\nAdvertising skipped; desktop protocol is compositor-free. No rendered frame claim.\n')!
		for tool in ['notification-checks', 'notification-vm', 'compiled-storyboard-input-inventory'] {
			name := if tool == 'compiled-storyboard-input-inventory' { 'inventory-inputs' } else { tool }
			capture(out, 'tool-' + name, [v, '-nocache', '-gc', 'none', '-cc', 'clang', '-cflags', '-O2', '-path',
				'@vlib|' + root + '/compat/ios|' + root + '/tests/ios|@vmodules', '-o', out + '/' + name,
				root + '/tests/ios/' + tool + '.v'])!
		}
	} else if os.args[1] == 'fixture' {
		capture(out, 'build-view-tag', [out + '/notification-vm', 'build-view-tag', out])!
		capture(out, 'build-init', [out + '/notification-vm', 'build-init', out])!
	} else if os.args[1] == 'build' {
		capture(out, 'build-run-ios-gles', [out + '/notification-vm', 'build-run-ios-gles', out])!
	} else if os.args[1] == 'host' {
		capture(out, 'view-tag-host', [out + '/notification-checks', 'view-tag-host', out + '/host'])!
	} else {
		os.setenv('VINIX_IOS_PROBE_MEMORY_MAX', '2147483648', true)
		os.setenv('VINIX_IOS_VM_GZIP_LEVEL', '9', true)
		os.setenv('VINIX_IOS_PROBE_DESKTOP', '1', true)
		os.setenv('VINIX_IOS_STORYBOARD_BUNDLE', out + '/application', true)
		capture(out, 'probe-no-ads', [out + '/notification-vm', 'probe-no-ads', out])!
	}
}

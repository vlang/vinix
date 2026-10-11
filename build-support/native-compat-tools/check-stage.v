// SPDX-License-Identifier: GPL-2.0-or-later
module main

import fixturehost
import hosttest
import os
import policyhost

fn check(ok bool, message string) ! { if !ok { return error(message) } }

fn owners() ![]string {
	mut result := os.ls('/tmp')!.filter(it.starts_with('vinix-compat-project-') || it.starts_with('vinix-security-tools-') || it.starts_with('vinix-volume-tool-'))
	result.sort()
	return result
}

fn qualify(binary string) ! {
	work := hosttest.work_dir('', 'vinix-stage-controller-check-')!
	defer { hosttest.remove_work_dir(work) or { eprintln(err.msg()) } }
	mut env := policyhost.environment()
	env['ASAN_OPTIONS'] = 'detect_leaks=0'
	env['VINIX_FAULT_MACHINE'] = 'aarch64-linux-musl'
	for family in ['security-compile', 'x11-compile', 'security-stage', 'volume-stage', 'volume-host',
		'volume-guest', 'mac-host', 'sandbox-host', 'audit-host', 'xinput-test', 'xinput-guest',
		'wine-guest'] {
		help := fixturehost.capture_both_preferred([binary, family, '--help'], env, policyhost.caller_arch())!
		check(help.status == 0 && help.stdout.contains('Usage:'), family + ' help failed')!
		bad := fixturehost.capture_both_preferred([binary, family, '--unknown'], env, policyhost.caller_arch())!
		check(bad.status == 2, family + ' accepted unknown option')!
	}
	os.mkdir(work + '/staging')!
	os.mkdir_all(work + '/staging/usr/bin')!
	os.mkdir_all(work + '/staging/usr/sbin')!
	for name in ['usr/bin/vinix-sandbox', 'usr/sbin/vinix-volume'] {
		os.write_file(work + '/staging/' + name, 'preserve')!
	}
	for family in ['security-stage', 'volume-stage'] {
		mismatch := fixturehost.capture_both_preferred([binary, family, '--arch', 'x86_64', '--staging',
			work + '/staging', '--cc', hosttest.shell_quote(os.executable()) + ' --compiler'], env, policyhost.caller_arch())!
		check(mismatch.status == 2, 'Compiler mismatch accepted')!
		invalid := fixturehost.capture_both_preferred([binary, family, '--arch', 'aarch64', '--staging',
			'/', '--cc', 'false'], env, policyhost.caller_arch())!
		check(invalid.status == 2, 'Root staging path accepted')!
	}
	before := owners()!
	for family in ['security-stage', 'volume-stage'] {
		for _ in 0 .. 6 {
			failed := fixturehost.capture_both_preferred([binary, family, '--arch', 'aarch64',
				'--staging', work + '/staging', '--cc',
				hosttest.shell_quote(os.executable()) + ' --compiler'], env, policyhost.caller_arch())!
			check(failed.status == 1 && owners()! == before, 'Failed stage retained a private compiler owner')!
		}
	}
	for name in ['usr/bin/vinix-sandbox', 'usr/sbin/vinix-volume'] {
		check(os.read_file(work + '/staging/' + name)! == 'preserve', 'Failed compile replaced installed utility')!
	}
	os.mkdir(work + '/keep')!
	os.write_file(work + '/keep/sentinel', 'keep')!
	for family, option in {
		'volume-guest': '--state-dir'
		'xinput-test':  '--state-dir'
		'mac-host':     '--keep-dir'
		'sandbox-host': '--keep-dir'
		'audit-host':   '--keep-dir'
	} {
		result := fixturehost.capture_both_preferred([binary, family, option, work + '/keep'], env, policyhost.caller_arch())!
		check(result.status == 1 && os.read_file(work + '/keep/sentinel')! == 'keep', 'Existing workspace overwritten')!
	}
	println('Twelve native CLIs, compiler/root rejection, retained workspaces and twelve failed-stage owner retirements PASS')
}

fn main() {
	if os.args.len > 1 && os.args[1] == '--compiler' {
		if os.args.contains('-dumpmachine') {
			println(os.getenv('VINIX_FAULT_MACHINE'))
			return
		}
		exit(77)
	}
	if os.args.len != 2 {
		eprintln('Usage: check-stage.v CONTROLLER')
		exit(2)
	}
	qualify(os.args[1]) or {
		eprintln(err.msg())
		exit(1)
	}
}

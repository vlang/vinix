// SPDX-License-Identifier: GPL-2.0-or-later
module main

import fixturehost
import hosttest
import os
import policyhost

fn owners() ![]string {
	mut entries := os.ls('/tmp')!.filter(it.starts_with('vinix-process-smp-') || it.starts_with('vinix-v-module-'))
	entries.sort()
	return entries
}

fn qualify(binary string) ! {
	work := hosttest.work_dir('', 'vinix-process-cli-check-')!
	defer { hosttest.remove_work_dir(work) or { eprintln(err.msg()) } }
	mut env := policyhost.environment()
	env['CC'] = 'false'
	env['CC_AMD64'] = 'false'
	env['ASAN_OPTIONS'] = 'detect_leaks=0'
	env['V'] = os.getenv_opt('V') or { '/tmp/vinix-native-v-compiler/v' }
	env['VEXE'] = env['V']
	kernel := os.getenv_opt('VINIX_PROCESS_TEST_ARM_KERNEL') or { '/tmp/vinix-volume-guest-arm-final/kernel' }
	for family in ['process-smp', 'scheduler-qos', 'tlb', 'memory-retention'] {
		for option in [['--smp', '1'], ['--memory', '0'], ['--timeout', 'bad'], ['--expect', '']] {
			if family == 'memory-retention' && option[0] == '--expect' { continue }
			result := fixturehost.capture_both_preferred([binary, family, '--arch', 'aarch64',
				'--kernel-dir', kernel, ...option], env, policyhost.caller_arch())!
			if result.status != 2 { return error('Invalid process option accepted: ' + family + ' ' + option.str()) }
		}
	}
	before := owners()!
	for family in ['process-smp', 'scheduler-qos', 'tlb', 'memory-retention'] {
		for _ in 0 .. 3 {
			result := fixturehost.capture_both_preferred([binary, family, '--arch', 'aarch64',
				'--kernel-dir', kernel, '--build-only'], env, policyhost.caller_arch())!
			if result.status != 1 || owners()! != before { return error('Failed compile retained a private process/module owner') }
		}
	}
	os.mkdir(work + '/existing')!
	os.write_file(work + '/existing/sentinel', 'preserve')!
	// The shared process runner deliberately permits an existing evidence
	// directory. A failed rebuild must keep unrelated caller files intact.
	result := fixturehost.capture_both_preferred([binary, 'process-smp', '--arch', 'aarch64', '--kernel-dir',
		kernel, '--state-dir', work + '/existing', '--build-only'], env, policyhost.caller_arch())!
	if result.status != 1 || os.read_file(work + '/existing/sentinel')! != 'preserve' { return error('Existing process evidence changed') }
	for family in ['listen-backlog', 'resource-open', 'proc-thread-lock', 'proc-map-lookup', 'aarch64-sigreturn'] {
		mut argv := [binary, family, '--state-dir', work + '/existing', '--build-only', '--kernel-dir', kernel]
		if family != 'aarch64-sigreturn' { argv << ['--arch', 'aarch64'] }
		if family in ['resource-open', 'proc-thread-lock', 'proc-map-lookup'] { argv << ['--guest-state-dir', work + '/unused'] }
		rejected := fixturehost.capture_both_preferred(argv, env, policyhost.caller_arch())!
		if rejected.status == 0 || os.read_file(work + '/existing/sentinel')! != 'preserve' { return error('Independent workspace overwritten') }
	}
	println('Original process option policy, independent/reusable evidence directories and twelve failed compiler owner retirements PASS')
}

fn main() {
	if os.args.len != 2 { eprintln('Usage: check-process-cli.v CONTROLLER'); exit(2) }
	qualify(os.args[1]) or { eprintln(err.msg()); exit(1) }
}

// SPDX-License-Identifier: GPL-2.0-or-later
module main

import fixturehost
import hosttest
import json2
import os
import policyhost

fn strings(value json2.Any) []string { return value.as_array().map(it.str()) }

fn checked(binary string, profile string, cache string) ! {
	mut env := policyhost.environment()
	env['ASAN_OPTIONS'] = 'detect_leaks=0'
	for family in ['kernel-stack-guards', 'cpu-mitigations', 'smt-policy', 'acpi-sync'] {
		for pair in [['--help', '0'], ['--unknown', '2']] {
			result := fixturehost.capture_both_preferred([binary, family, pair[0]], env, policyhost.caller_arch())!
			if result.status.str() != pair[1] { return error('CLI policy differs: ' + family) }
		}
	}
	for mode in ['guard-arm', 'guard-x86', 'mitigation', 'segments', 'smt'] {
		arm := mode == 'guard-arm'
		arch := if arm { 'aarch64' } else { 'x86_64' }
		kernel := cache + if arm { '/kernel-arm' } else { '/kernel-x86' }
		work := cache + '/optin-' + profile + '-' + mode
		family := if mode.starts_with('guard') { 'kernel-stack-guards' } else if mode == 'smt' { 'smt-policy' } else { 'cpu-mitigations' }
		mut argv := [binary, family, '--state-dir', work, '--build-only']
		if mode.starts_with('guard') { argv << ['--arch', if arm { 'aarch64' } else { 'amd64' }, '--kernel', kernel] }
		if mode == 'segments' { argv << '--segments' }
		env['VINIX_AMD64_KERNEL'] = kernel + '/bin/vinix'
		result := fixturehost.capture_both_preferred(argv, env, policyhost.caller_arch())!
		os.write_file(work + '.log', result.stdout + result.stderr)!
		if result.status != 0 { return error('Native target build failed: ' + mode + '\n' + result.stderr) }
		data := hosttest.decode_json(os.read_file(work + '/inputs.json')!)!.as_map()
		init := work + if mode == 'smt' { '/rootfs/sbin/init' } else { '/init' }
		header := os.read_bytes(init)!
		if header.len < 64 || header[..6] != [u8(0x7f), `E`, `L`, `F`, 2, 1] || int(header[18]) + (int(header[19]) << 8) != if arm { 183 } else { 62 } { return error('Invalid target ELF') }
		if os.read_bytes(work + '/kernel/bin/vinix')! != os.read_bytes(kernel + '/bin/vinix')! { return error('Kernel snapshot differs') }
		mut recipe := strings(data['compile_command'] or { return error('Missing recipe') })
		if mode != 'smt' {
			source := hosttest.root() + '/tests/' + family + '/' + if mode == 'segments' { 'segments.c' } else { 'guest.c' }
			mut expected := []string{}
			if arm {
				sdk := hosttest.root() + '/build-aarch64-userland/sysroot'
				expected = [os.getenv_opt('CC') or { 'clang' }, '--target=aarch64-linux-musl', '--sysroot=' + sdk, '-static', '-O2', '-fno-stack-protector', '-Wall', '-Wextra', '-Werror', source, '-L' + sdk + '/lib', '-fuse-ld=lld', '-o', init]
			} else {
				expected = [os.getenv_opt('CC_AMD64') or { 'x86_64-linux-musl-gcc' }, '-static', '-O2', '-Wall', '-Wextra', '-Werror']
				if mode in ['mitigation', 'segments'] { expected << '-pthread' }
				if mode == 'segments' { expected << '-I' + work + '/segment-fixtures' }
				expected << source
				if mode in ['mitigation', 'segments'] { expected << hosttest.root() + '/tests/cpu-mitigations/probe.S' }
				if mode == 'segments' {
					for name in ['signalfixture', 'touchfixture', 'restartfixture', 'nanosleepfixture', 'blockedfixture', 'pollfixture', 'epollfixture', 'intfixture'] { expected << work + '/' + name + '.o' }
				}
				expected << ['-o', init]
			}
			if recipe != expected { return error('Original compiler recipe differs: ' + mode) }
			if (data['source_sha256'] or { return error('Missing source hash') }).str() != hosttest.sha(source)! { return error('Guest source hash differs') }
		}
		recipe[recipe.len - 1] = init + '-original-recipe'
		fixturehost.inherited_command_environment_preferred(recipe, env, policyhost.caller_arch())!
		if header != os.read_bytes(init + '-original-recipe')! { return error('Original compile replay bytes differ') }
		if mode == 'smt' {
			for enabled in ['0', '1'] {
				unpack := work + '/unpack-' + enabled
				os.mkdir(unpack)!
				fixturehost.inherited_command_environment_preferred(['tar', '-xf', work + '/policy-' + enabled + '/initramfs.tar', '-C', unpack], env, policyhost.caller_arch())!
				if os.read_file(unpack + '/smt-request')! != enabled || os.read_bytes(unpack + '/sbin/init')! != header { return error('SMT archive policy differs') }
			}
		}
		println('Original recipe/ELF/kernel/archive PASS: ' + profile + ' ' + mode + ' ' + arch)
	}
	for argv in [[binary, 'cpu-mitigations', '--arch', 'aarch64'], [binary, 'cpu-mitigations', '--smp', '0'],
		[binary, 'acpi-sync', '--kernel-dir', hosttest.root() + '/kernel', '--arch', 'aarch64', '--v', os.getenv('V'), '--state-dir', cache + '/forbidden-' + profile]] {
		result := fixturehost.capture_both_preferred(argv, env, policyhost.caller_arch())!
		if result.status != 2 { return error('Invalid architecture/topology/worktree was accepted') }
	}
	if os.exists(cache + '/forbidden-' + profile) { return error('ACPI guard wrote into rejected state directory') }
	// A real Git worktree exercises build argument/environment/log ownership.
	// The native test executable stands in for make and fails before any boot.
	worktree := cache + '/acpi-worktree-' + profile
	fixturehost.inherited_command_environment_preferred(['git', '-C', hosttest.root(), 'worktree', 'add', '--detach', '--no-checkout', worktree, 'HEAD'], env, policyhost.caller_arch())!
	defer { fixturehost.inherited_command_environment_preferred(['git', '-C', hosttest.root(), 'worktree', 'remove', '--force', worktree], env, policyhost.caller_arch()) or { eprintln(err.msg()) } }
	os.mkdir(worktree + '/kernel')!
	bin := cache + '/acpi-make-' + profile
	os.mkdir(bin)!
	os.symlink(os.executable(), bin + '/make')!
	for arch in ['aarch64', 'x86_64'] {
		state := cache + '/acpi-build-failure-' + profile + '-' + arch
		mut build_env := env.clone()
		build_env['PATH'] = bin + ':' + env['PATH']
		result := fixturehost.capture_both_preferred([binary, 'acpi-sync', '--kernel-dir', worktree + '/kernel',
			'--arch', arch, '--v', os.getenv('V'), '--state-dir', state], build_env, policyhost.caller_arch())!
		if result.status != 1 || !result.stderr.contains('ACPI kernel build failed') || os.exists(state + '/guest') { return error('Failed build launched guest or lost error') }
		log := os.read_file(state + '/build.log')!
		for expected in ['-j4', 'ACPI_SYNC_TEST=1', 'STACK_GUARD_TEST=0', 'VEXE=' + os.getenv('V'), 'ARCH=' + arch, 'build stderr retained'] {
			if !log.contains(expected) { return error('Build argument/environment/log differs: ' + expected) }
		}
	}
	println('CLI errors, real worktree guard and ARM/x86 failed-build logs PASS: ' + profile)
}

fn main() {
	if os.args.len == 2 && os.args[1] == '--fronts' {
		for family in ['kernel-stack-guards', 'cpu-mitigations', 'smt-policy', 'acpi-sync'] {
			result := fixturehost.capture_in_preferred([hosttest.root() + '/tests/' + family + '/run', '--help'],
				'', policyhost.environment(), false, '/tmp', false, policyhost.caller_arch()) or { panic(err) }
			assert result.contains('Usage:')
			println('Cold native front outside checkout PASS: ' + family)
		}
		return
	}
	if os.base(os.args[0]) == 'make' {
		println(os.args[1..].join('\n'))
		println('VEXE=' + os.getenv('VEXE'))
		eprintln('build stderr retained')
		exit(37)
	}
	if os.args.len != 4 { eprintln('Usage: check-optin.v CONTROLLER PROFILE CACHE'); exit(2) }
	checked(os.args[1], os.args[2], os.args[3]) or { eprintln(err.msg()); exit(1) }
}

// SPDX-License-Identifier: GPL-2.0-or-later
module compathost

import guesthost
import hosttest
import json2
import os
import strconv

struct OptinPolicy {
	pass string
	expected []string
	failures []string
}

fn stack_guard_policy(arch string, runtime bool, overflow bool) OptinPolicy {
	if overflow {
		pass := 'STACK-GUARD FATAL ' + if arch == 'aarch64' { 'emergency-stack exhaustion' } else { 'kernel-stack exhaustion' }
		return OptinPolicy{pass: pass, expected: ['STACK-GUARD state sp=0x', pass],
			failures: ['STACK-GUARD GUEST: PASS', 'STACK-GUARD GUEST: FAIL']}
	}
	pass := 'STACK-GUARD GUEST: PASS'
	features := if runtime { []string{} } else {
		['STACK-GUARD PASS actual read/write faults, stack exhaustion',
		 'STACK-GUARD PASS 32 unpublished thread allocation/rollback/retirement cycles']
	}
	return OptinPolicy{pass: pass, expected: [...features, pass],
		failures: ['STACK-GUARD GUEST: FAIL', 'FATAL EXCEPTION', 'KERNEL PANIC']}
}

fn mitigation_policy(segments bool) OptinPolicy {
	pass := 'CPU MITIGATION GUEST: PASS'
	features := if segments { ['QEMU CORE PASS: x86-64 TLS descriptors, LDT and 32-bit code'] } else {
		['CPU MITIGATION PASS: syscall register preservation',
		 'CPU MITIGATION PASS: faulting DS and ES syscall restores recover',
		 'CPU MITIGATION PASS: timer interrupts and signed signal returns',
		 'CPU MITIGATION PASS: threads, CPU migration and process switches']
	}
	return OptinPolicy{pass: pass, expected: [...features, pass],
		failures: ['CPU MITIGATION FAIL', 'QEMU CORE FAIL', 'FATAL EXCEPTION', 'KERNEL PANIC']}
}

fn environment_timeout(fallback int) !int {
	value := strconv.atoi(os.getenv_opt('VINIX_QEMU_TIMEOUT') or { fallback.str() }) or {
		return error_with_code('VINIX_QEMU_TIMEOUT must be an integer', 2)
	}
	if value <= 0 { return error_with_code('VINIX_QEMU_TIMEOUT must be positive', 2) }
	return value
}

fn snapshot_kernel_input(work string, source string, arch string) !string {
	input := resolve(source)!
	if !os.is_file(input) { return snapshot_kernel(work, input, arch)! }
	target := work + '/kernel/bin/vinix'
	os.mkdir_all(os.dir(target))!
	hosttest.module_copy_file_preserving_stat(input, target)!
	elf_arch(target, arch)!
	return work + '/kernel'
}

// Preserve the imported x86 driver's acceleration, network/capture, firmware
// override, serial framing and topology. The native monitor aids retirement.
fn optin_launch(command []string, arch string, work string, cpu string, topology string, firmware_name string) []string {
	mut argv := command.clone()
	for index, value in argv {
		if value == '-m' && arch == 'aarch64' { argv[index + 1] = '2048' }
		if arch == 'x86_64' {
			if value == '-accel' { argv[index + 1] = os.getenv_opt('VINIX_QEMU_ACCEL') or { 'tcg' } }
			if value == '-cpu' { argv[index + 1] = cpu }
			if value == '-smp' { argv[index + 1] = topology }
			if value == '-serial' { argv[index + 1] = 'stdio' }
			if value == '-drive' {
				if firmware := os.getenv_opt(firmware_name) {
					argv[index + 1] = 'if=pflash,format=raw,unit=0,readonly=on,file=' + firmware
				} else if firmware_name != 'VINIX_OVMF_CODE' {
					argv[index + 1] = 'if=pflash,format=raw,unit=0,readonly=on,file=' + os.dir(os.dir(argv[0])) + '/share/qemu/edk2-x86_64-code.fd'
				}
			}
		}
	}
	if arch == 'x86_64' {
		argv << ['-netdev', 'user,id=net0', '-device', 'e1000,netdev=net0,mac=52:54:00:12:34:56',
			'-object', 'filter-dump,id=vinixdump,netdev=net0,file=' + work + '/unused.pcap']
	}
	return argv
}

fn optin_guest_command(args []string, family string) !int {
	guards := family == 'kernel-stack-guards'
	mut options := [hosttest.Option{ name: '--arch', value: true, choices: ['aarch64', 'amd64'] },
		hosttest.Option{ name: '--state-dir', value: true }, hosttest.Option{ name: '--build-only' }]
	if guards {
		options << [hosttest.Option{ name: '--repo', value: true }, hosttest.Option{ name: '--kernel', value: true },
			hosttest.Option{ name: '--runtime-only' }, hosttest.Option{ name: '--expect-overflow' }]
	} else {
		options << [hosttest.Option{ name: '--segments' }, hosttest.Option{ name: '--cpu', value: true },
			hosttest.Option{ name: '--smp', value: true }]
	}
	parsed := hosttest.parse_arguments(args, options, 0, 'Usage: run [--arch aarch64|amd64] [--state-dir FRESH-DIR] [--build-only]',
		if guards { 'Stack guards: --kernel DIR|ELF [--repo DIR] [--runtime-only] [--expect-overflow]' } else {
			'CPU mitigations: [--segments] [--cpu MODEL] [--smp N]; x86 only.'
		}) or { return error_with_code(err.msg(), 2) }
	if guards { needed(parsed, ['--kernel'])! }
	arch_arg := parsed.options['--arch'] or { if guards { 'aarch64' } else { 'amd64' } }
	if !guards && arch_arg != 'amd64' { return error_with_code('The executable CPU instruction guest is x86-64 only.', 2) }
	arch := if arch_arg == 'amd64' { 'x86_64' } else { 'aarch64' }
	timeout := environment_timeout(300)!
	smp := if guards { 2 } else { positive_option(parsed, '--smp', 2)! }
	repo := resolve(if guards { parsed.options['--repo'] or { root() } } else { os.getenv_opt('VINIX_VM_RUNNER_ROOT') or { root() } })!
	work := hosttest.work_dir(parsed.options['--state-dir'] or { '' }, 'vinix-' + family + '-')!
	defer { if '--state-dir' !in parsed.options { retire(work) } }
	private_kernel := snapshot_kernel_input(work, if guards { parsed.options['--kernel'] } else {
		os.getenv_opt('VINIX_AMD64_KERNEL') or { root() + '/kernel/bin/vinix' }
	}, arch)!
	source := root() + '/tests/' + family + '/' + if !guards && '--segments' in parsed.options { 'segments.c' } else { 'guest.c' }
	init := work + '/init'
	mut compile := []string{}
	if arch == 'aarch64' {
		sdk := repo + '/build-aarch64-userland/sysroot'
		compile = [os.getenv_opt('CC') or { 'clang' }, '--target=aarch64-linux-musl', '--sysroot=' + sdk,
			'-static', '-O2', '-fno-stack-protector', '-Wall', '-Wextra', '-Werror', source,
			'-L' + sdk + '/lib', '-fuse-ld=lld', '-o', init]
	} else {
		compile = [os.getenv_opt('CC_AMD64') or { 'x86_64-linux-musl-gcc' }, '-static', '-O2', '-Wall', '-Wextra', '-Werror']
		if !guards { compile << '-pthread' }
		mut segment_objects := []string{}
		if !guards && '--segments' in parsed.options {
			// qemu-core's maintained probe now calls eight V fixture bodies.
			// Supply the same generated APIs/objects as its native run.sh.
			segment_objects = mitigation_segment_objects(work, compile[0])!
			compile << '-I' + work + '/segment-fixtures'
		}
		compile << source
		if !guards { compile << root() + '/tests/cpu-mitigations/probe.S' }
		compile << segment_objects
		compile << ['-o', init]
	}
	run(compile)!
	elf_arch(init, arch)!
	for name in ['root', 'sbin', 'proc', 'sys', 'dev'] { os.mkdir_all(work + '/rootfs/' + name)! }
	hosttest.module_copy_file_preserving_stat(init, work + '/rootfs/sbin/init')!
	archive := native_archive(work)!
	policy := if guards { stack_guard_policy(arch, '--runtime-only' in parsed.options, '--expect-overflow' in parsed.options) } else { mitigation_policy('--segments' in parsed.options) }
	mut receipt := { 'arch': json2.Any(arch), 'family': json2.Any(family), 'timeout': json2.Any(timeout),
		'compile_command': json2.Any(hosttest.strings(compile)), 'source_sha256': json2.Any(hosttest.sha(source)!),
		'init_sha256': json2.Any(hosttest.sha(init)!), 'kernel_sha256': json2.Any(hosttest.sha(private_kernel + '/bin/vinix')!),
		'expected': json2.Any(hosttest.strings(policy.expected)), 'failures': json2.Any(hosttest.strings(policy.failures)) }
	if !guards { receipt['probe_sha256'] = hosttest.sha(root() + '/tests/cpu-mitigations/probe.S')! }
	hosttest.write_json(work + '/inputs.json', receipt)!
	if '--build-only' in parsed.options { return 0 }
	configured := guesthost.launch_from(init, archive, work, private_kernel, arch, false, repo)!
	base_argv := optin_launch(configured.command, arch, work, parsed.options['--cpu'] or { 'max' }, smp.str(), 'VINIX_OVMF_CODE_AMD64')
	argv := if arch == 'aarch64' { guesthost.arm_home_launch(base_argv, work, repo)! } else { base_argv }
	receipt['command'] = hosttest.strings(argv)
	hosttest.write_json(work + '/inputs.json', receipt)!
	return guesthost.boot_abi(argv, configured.env, work, arch, policy.expected, policy.pass, policy.failures, timeout, true)!
}

fn mitigation_segment_objects(work string, compiler string) ![]string {
	stage := work + '/segment-fixtures'
	run([root() + '/tests/qemu-core/compile-fixtures', stage, '--arch', 'amd64'])!
	mut objects := []string{}
	for name in ['signalfixture', 'touchfixture', 'restartfixture', 'nanosleepfixture', 'blockedfixture', 'pollfixture', 'epollfixture', 'intfixture'] {
		object := work + '/' + name + '.o'
		run([compiler, '-O2', '-Wall', '-Wextra', '-Werror', '-Wno-unused-function', '-Wno-unused-variable',
			'-Wno-unused-parameter', '-fno-strict-aliasing', '-I' + stage + '/' + name, '-c', stage + '/' + name + '.c', '-o', object])!
		objects << object
	}
	return objects
}

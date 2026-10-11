// SPDX-License-Identifier: GPL-2.0-or-later
module guesthost

import hosttest
import json2
import os
import policyhost

pub fn churn_features(mode string) ![]string {
	names := match mode {
		'exec' { ['true', 'sleep', 'curl', 'awk'] }
		'slabinfo' { ['slabinfo'] }
		'waits' { ['idle_control', 'nanosleep', 'clock_nanosleep', 'fork_reap'] }
		'directories' { ['mkdir_tmpfs', 'mkdir_ext2'] }
		'pipes' { ['pipe'] }
		'sampling' { ['sampling'] }
		'select' { ['select_ready', 'pselect_ready'] }
		else { return error('Unknown churn mode') }
	}
	count := if mode == 'directories' { 200 } else { 300 }
	return names.map('CHURN MEASURE program=' + it + ' cohort=3 runs=' + count.str())
}

pub fn churn_command(arguments []string) int {
	guard := policyhost.own_commands()
	defer { guard.close() }
	result := churn_checked(arguments) or { return serial_report(err) }
	return result
}

fn churn_checked(arguments []string) !int {
	parsed := parse(arguments, [hosttest.Option{ name: '--arch', value: true, choices: ['aarch64', 'amd64'] },
		hosttest.Option{ name: '--mode', value: true, choices: ['exec', 'slabinfo', 'waits', 'directories', 'pipes', 'sampling', 'select'] },
		hosttest.Option{ name: '--runner-root', value: true }, hosttest.Option{ name: '--kernel', value: true },
		hosttest.Option{ name: '--image', value: true }, hosttest.Option{ name: '--module-iso', value: true },
		hosttest.Option{ name: '--timeout', value: true }, hosttest.Option{ name: '--state-dir', value: true },
		hosttest.Option{ name: '--build-only' }], []string{},
		'Usage: run [--arch aarch64|amd64] [--mode exec|slabinfo|waits|directories|pipes|sampling|select] [--runner-root DIR] [--kernel FILE|DIR] [--image TAR] [--module-iso ISO] [--timeout SECONDS] [--state-dir FRESH] [--build-only]') or {
		return SerialArgumentError{err.msg()}
	}
	arch := if parsed.value('--arch', 'aarch64') == 'aarch64' { 'aarch64' } else { 'x86_64' }
	mode := parsed.value('--mode', 'exec')
	timeout := serial_timeout(parsed, 1800)!
	if mode in ['exec', 'directories'] && arch != 'aarch64' {
		return SerialArgumentError{mode + ' cohorts require the ARM desktop/module or persistent ext2 runner'}
	}
	if parsed.has('--build-only') && !parsed.has('--state-dir') {
		return SerialArgumentError{'--build-only needs --state-dir to retain artifacts'}
	}
	repo := resolve(parsed.value('--runner-root', os.getenv_opt('VINIX_VM_RUNNER_ROOT') or { root() }))!
	mut base_archive := resolve(parsed.value('--image', repo + '/build-support/init-aarch64/initramfs-desktop.tar'))!
	module_iso := if mode == 'exec' && parsed.has('--module-iso') { resolve(parsed.value('--module-iso', ''))! } else { '' }
	if mode == 'exec' && (!os.is_file(base_archive) || module_iso == '' || !os.is_file(module_iso)) {
		return SerialArgumentError{'exec cohorts require a populated desktop image and its module ISO'}
	}
	mut kernel := resolve(parsed.value('--kernel', os.getenv_opt('VINIX_KERNEL_DIR') or { root() + '/kernel' }))!
	if os.is_dir(kernel) { kernel += '/bin/vinix' }
	if !parsed.has('--build-only') { abi_validate_elf(kernel, arch)! }
	for key, value in {'VINIX_KERNEL_DIR': os.dir(os.dir(kernel)), 'VINIX_QEMU_RT_NO_BUILD': '1',
		'VINIX_QEMU_BASE_ARCHIVE': '', 'VINIX_QEMU_MODULE_MANIFEST': '', 'VINIX_QEMU_EXTRA_MODULES': '',
		'VINIX_QEMU_ROOT_DISK': '0', 'VINIX_QEMU_PACKAGE_PERSIST': '0', 'VINIX_QEMU_HOST_SOURCE': '0',
		'VINIX_QEMU_AUDIO': 'off'} { os.setenv(key, value, true) }
	if mode == 'exec' {
		os.setenv('VINIX_QEMU_MODULE_ISO', module_iso, true)
		os.setenv('VINIX_INITRAMFS_COMPRESSED', '0', true)
	} else {
		os.unsetenv('VINIX_QEMU_MODULE_ISO')
		os.unsetenv('VINIX_INITRAMFS_COMPRESSED')
	}
	keep := parsed.has('--state-dir')
	state_arg := parsed.value('--state-dir', '.')
	work := hosttest.work_dir(if keep { if state_arg == '' { '.' } else { state_arg } } else { '' }, 'vinix-process-churn-')!
	defer { if !keep { hosttest.remove_work_dir(work) or { eprintln(err.msg()) } } }
	sdk := os.getenv_opt('VINIX_AARCH64_SYSROOT') or { repo + '/build-aarch64-userland/sysroot' }
	mut compiler := if arch == 'aarch64' {
		['clang', '--target=aarch64-linux-musl', '--sysroot=' + sdk, '-L' + sdk + '/lib', '-fuse-ld=lld']
	} else { [os.getenv_opt('CC_AMD64') or { 'x86_64-linux-musl-gcc' }] }
	if mode != 'exec' { compiler << '-DCHURN_' + mode.to_upper() + '_ONLY' }
	compiler << ['-static', '-O2', '-Wall', '-Wextra', '-Werror', '-fno-stack-protector',
		root() + '/tests/process-churn/guest.c', '-o', work + '/init']
	run(compiler)!
	if mode != 'exec' {
		for name in ['root', 'sbin', 'proc', 'dev', 'tmp'] { mkdir_literal(work + '/rootfs/' + name)! }
		hosttest.module_copy_file_preserving_stat(work + '/init', work + '/rootfs/sbin/init')!
		base_archive = archive_tree(work + '/rootfs', work + '/initramfs.tar')!
	}
	expected := [...churn_features(mode)!, 'PROCESS CHURN: DONE failures=0']
	mut receipt := {
		'mode': json2.Any(mode)
		'arch': json2.Any(arch)
		'memory_mb': json2.Any(if arch == 'x86_64' { 1024 } else if mode == 'exec' { 12288 } else { 2048 })
		'compile_command': json2.Any(compiler.map(json2.Any(it)))
		'guest_sha256': json2.Any(digest(work + '/init')!)
		'base_archive': json2.Any(base_archive)
		'module_iso': json2.Any(module_iso)
		'expected': json2.Any(expected.map(json2.Any(it)))
		'kernel_rebuilt_by_runner': json2.Any(false)
	}
	os.write_file(work + '/inputs.json', json2.encode(json2.Any(receipt), prettify: true) + '\n')!
	println('Process churn artifacts: ' + work)
	if parsed.has('--build-only') { return 0 }
	mkdir_literal(work + '/kernel/bin')!
	os.cp(kernel, work + '/kernel/bin/vinix')!
	mkdir_literal(work + '/vm')!
	mut command := []string{}
	mut env := policyhost.environment()
	if arch == 'aarch64' {
		configured := serial_arm_launch(work + '/init', base_archive, work + '/vm', work + '/kernel', repo,
			if mode == 'exec' { 12288 } else { 2048 }, module_iso)!
		command = configured.command
		env = configured.env
	} else {
		configured := launch_from(work + '/init', base_archive, work + '/vm', work + '/kernel', arch, false, repo)!
		qemu := configured.command[0]
		firmware := os.getenv_opt('VINIX_OVMF_CODE_AMD64') or { os.dir(os.dir(qemu)) + '/share/qemu/edk2-x86_64-code.fd' }
		command = serial_x86_command(work + '/vm/test.iso', qemu, firmware, work + '/unused.pcap')
		env = configured.env
	}
	receipt['kernel_sha256'] = json2.Any(digest(work + '/kernel/bin/vinix')!)
	receipt['command'] = json2.Any(command.map(json2.Any(it)))
	os.write_file(work + '/inputs.json', json2.encode(json2.Any(receipt), prettify: true) + '\n')!
	policyhost.command_checkpoint()!
	return boot_abi_from(command, env, work + '/vm', arch, expected, 'PROCESS CHURN: DONE failures=0',
		['PROCESS CHURN: FAIL', 'FATAL EXCEPTION', 'KERNEL PANIC'], timeout, true, repo)!
}

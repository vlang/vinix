// SPDX-License-Identifier: GPL-2.0-or-later
module systemhost

import guesthost
import hosttest
import os

pub fn security_pass(family string) string {
	return match family {
		'security' { 'VINIX OPENBSD SECURITY: PASS' }
		'mount' { 'VINIX MOUNT POLICY: PASS' }
		else { 'VINIX IPV6: PASS' }
	}
}

pub fn security_failures(family string) []string {
	return match family {
		'security' {
			['VINIX OPENBSD SECURITY: FAIL', 'OPENBSD SECURITY FAIL line', 'FATAL EXCEPTION',
				'KERNEL PANIC']
		}
		'mount' {
			['VINIX MOUNT POLICY: FAIL', 'MOUNT POLICY FAIL line', 'FATAL EXCEPTION', 'KERNEL PANIC']
		}
		else { ['VINIX IPV6: FAIL', 'KERNEL PANIC', 'FATAL EXCEPTION'] }
	}
}

pub fn security_verdict(text string, family string, arch string, finished bool) []string {
	mut failures := []string{}
	for marker in [...features(family), security_pass(family)] {
		if text.count(marker) != 1 { failures << 'missing expected result: ' + marker }
	}
	if family == 'security' && arch == 'aarch64' && !text.contains(': pledge "rpath", syscall ') {
		failures << 'missing expected result: : pledge "rpath", syscall '
	}
	for marker in security_failures(family) {
		if text.contains(marker) { failures << 'observed failure: ' + marker }
	}
	if !finished { failures << 'the test did not finish before the timeout' }
	return failures
}

fn security_x86(iso string, qemu_arg string, firmware_arg string, capture_path string) !guesthost.Launch {
	qemu := os.find_abs_path_of_executable(qemu_arg)!
	firmware := if firmware_arg != '' {
		resolve(firmware_arg)!
	} else {
		os.getenv_opt('VINIX_OVMF_CODE') or { os.dir(os.dir(qemu)) + '/share/qemu/edk2-x86_64-code.fd' }
	}
	return guesthost.Launch{
		command: [qemu, '-machine', 'q35,smm=off', '-accel',
			os.getenv_opt('VINIX_QEMU_ACCEL') or { 'tcg' }, '-cpu', 'max', '-m', '1024', '-smp',
			'2', '-drive', 'if=pflash,format=raw,unit=0,readonly=on,file=' + firmware, '-cdrom',
			iso, '-netdev', 'user,id=net0', '-device', 'e1000,netdev=net0,mac=52:54:00:12:34:56',
			'-object', 'filter-dump,id=vinixdump,netdev=net0,file=' + capture_path, '-display',
			'none', '-monitor', 'none', '-serial', 'stdio', '-no-reboot']
		env:     policy_environment()
	}
}

fn security(family string, arguments []string) !int {
	mut args := arguments.clone()
	if args.len > 1 && args[0] == '--build-fixture' && !args[1].starts_with('-') {
		arch := args[1]
		args.delete(1)
		args << ['--arch', arch]
	}
	options := parse(args, [
		hosttest.Option{ name: '--arch', value: true, choices: ['aarch64', 'amd64'] },
		hosttest.Option{ name: '--init', value: true },
		hosttest.Option{ name: '--initramfs', value: true },
		hosttest.Option{ name: '--state-dir', value: true },
		hosttest.Option{ name: '--iso', value: true },
		hosttest.Option{ name: '--qemu', value: true },
		hosttest.Option{ name: '--firmware', value: true },
		hosttest.Option{ name: '--timeout', value: true },
		hosttest.Option{ name: '--capture', value: true },
		hosttest.Option{ name: '--kernel-dir', value: true },
		hosttest.Option{ name: '--build-fixture' },
		hosttest.Option{ name: '--build-only' },
	], [],
		'Usage: run_vm --arch aarch64|amd64 --capture PCAP [--init ELF --initramfs TAR --state-dir DIR] [--iso ISO --qemu PATH --firmware PATH] [--timeout 600] [--kernel-dir DIR]\n       run.sh [aarch64|amd64] [--state-dir DIR] [--build-only]')!
	build := options.has('--build-fixture')
	if !build { required(options, ['--arch', '--capture'])! }
	arch := options.value('--arch', 'aarch64')
	if !build && arch == 'aarch64' { required(options, ['--init', '--initramfs', '--state-dir'])! }
	if !build && arch == 'amd64' { required(options, ['--iso'])! }
	seconds := if build { env_timeout(options, 600)! } else { positive(options, '--timeout', 600)! }
	state := state_dir(options, 'vinix-' + family + '-')!
	defer { private_cleanup(state, options) }
	capture_path := if options.has('--capture') {
		resolve(options.value('--capture', ''))!
	} else {
		state + '/net.pcap'
	}
	runner := resolve(os.getenv_opt(if family == 'ipv6' {
		'VINIX_QEMU_RUNNER_ROOT'
	} else {
		'VINIX_VM_RUNNER_ROOT'
	}) or { root() })!
	mut init := ''
	mut archive := ''
	mut kernel := ''
	if build {
		source := root() + '/tests/' + match family {
			'security' { 'openbsd-security' }
			'mount' { 'mount-policy' }
			else { 'ipv6-multicast' }
		} + '/test.c'
		init = state + '/init'
		extra := if arch == 'amd64' || family == 'ipv6' { ['-pthread'] } else { []string{} }
		run([...flags(arch), ...extra, source, '-o', init])!
		archive = archive_root(if arch == 'amd64' { init } else { '' }, state,
			if arch == 'amd64' { ['root', 'sbin', 'tmp', 'dev'] } else { ['root', 'sbin', 'tmp'] })!
	} else if arch == 'aarch64' {
		init = resolve(options.value('--init', ''))!
		archive = resolve(options.value('--initramfs', ''))!
	}
	configured := if arch == 'aarch64' {
		kernel = snapshot(state, kernel_source(options, arch), arch)!
		base := guesthost.serial_arm_launch(init, archive, state, kernel, runner, 2048, '')!
		mut argv := base.command.clone()
		argv << ['-object', 'filter-dump,id=vinixdump,netdev=net0,file=' + capture_path]
		guesthost.Launch{argv, base.env}
	} else if build {
		kernel = snapshot(state, options.value('--kernel-dir', os.getenv_opt('VINIX_AMD64_KERNEL') or {
			root() + '/build-amd64-kernel/bin/vinix'
		}), arch)!
		guesthost.launch_from(init, archive, state, kernel, 'x86_64', false, runner)!
		security_x86(state + '/test.iso', options.value('--qemu', os.getenv_opt('VINIX_QEMU_X86_64') or { 'qemu-system-x86_64' }), options.value('--firmware', ''), capture_path)!
	} else {
		security_x86(resolve(options.value('--iso', ''))!, options.value('--qemu', 'qemu-system-x86_64'), options.value('--firmware', ''), capture_path)!
	}
	if kernel != '' { receipt(state, configured, kernel, init, archive, seconds)! }
	if options.has('--build-only') {
		println('Prepared ' + family + ' ' + arch + ': ' + state)
		return 0
	}
	mut echo := &Echo{}
	if family == 'ipv6' { echo = start_echo('[::1]:39066')! }
	defer { if family == 'ipv6' { echo.close() } }
	println('==> Booting the ' + arch + ' ' + family + ' test')
	result := guesthost.boot_session(configured.command, configured.env, state, guesthost.SessionPolicy{
		pass:      security_pass(family)
		failures:  security_failures(family)
		lookback:  131072
		settle:    2
		term_wait: 3
		kill_wait: 3
	}, seconds, true)!
	mut failures := security_verdict(result.text, family, arch, result.finished)
	if result.text.contains('OPENBSD SECURITY WIRE: sent') {
		if !os.exists(capture_path) {
			failures << 'QEMU wrote no packet capture'
		} else {
			frames := capture_frames(capture_path)!
			failures << if family == 'ipv6' {
				ipv6_packets(frames)
			} else {
				security_packets(frames)
			}
		}
	}
	if family == 'ipv6' && os.exists(capture_path) {
		failures << ipv6_packets(capture_frames(capture_path)!)
		if os.getenv('VINIX_TEST_CAPTURE') != '' {
			os.cp(capture_path, os.getenv('VINIX_TEST_CAPTURE'))!
		}
	}
	for failure in failures { eprintln('ERROR: ' + failure) }
	if failures.len != 0 { return 1 }
	println('==> ' + arch + ' ' + family + ' test passed')
	return 0
}

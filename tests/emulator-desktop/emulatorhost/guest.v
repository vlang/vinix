// SPDX-License-Identifier: GPL-2.0-or-later
module emulatorhost

import guesthost
import hosttest
import os
import policyhost

pub fn features(kind string, supplied bool) []string {
	mut result := [label(kind) + ' PASS: native emulator boots ' + if kind == 'n64' { 'Nintendo 64' } else { 'PlayStation' } + ' code and publishes real frames',
		label(kind) + ' PASS: controller input changes the emulated game']
	if kind == 'n64' { result << ['N64 PASS: analog stick reaches the emulated controller',
		'N64 PASS: batched arrow and WASD input stays running and moves the game'] }
	result << [label(kind) + ' PASS: pause freezes emulation and resume produces new frames',
		label(kind) + ' PASS: reset restarts the game and close releases the native surface',
		label(kind) + if kind == 'n64' { ' PASS: cartridge SRAM survives a fresh emulator process' } else { ' PASS: memory card survives a fresh emulator process' }]
	if kind != 'ps1' { result << label(kind) + ' PASS: rejected content preserves the running game and pause state' }
	if kind == 'n64' { result << ['N64 PASS: byte-swapped and word-swapped ROM formats boot real code',
		'N64 PASS: stalled boot code hits its instruction limit and recovers'] }
	if supplied { result << label(kind) + ' PASS: supplied game rendered and shut down cleanly' }
	result << 'VINIX ' + label(kind) + ' GUEST: PASS'
	return result
}

pub fn run_command(kind string, args []string) int {
	guard := policyhost.own_commands()
	defer { guard.close() }
	return guest_checked(kind, args) or { return report(err) }
}

fn guest_checked(kind string, args []string) !int {
	mut specs := [hosttest.Option{ name: '--no-build' }, hosttest.Option{ name: '--game', value: true },
		hosttest.Option{ name: '--timeout', value: true }, hosttest.Option{ name: '--log', value: true }]
	if kind != 'n64' { specs << hosttest.Option{ name: '--bios', value: true } }
	if kind != 'ps1' { specs << hosttest.Option{ name: '--prebuilt-init', value: true } }
	options := parse(args, specs, 'Usage: ' + kind + '/run [--no-build] [--game FILE] [--timeout SECONDS] [--log FILE]' +
		if kind != 'n64' { ' [--bios FILE]' } else { '' } + if kind != 'ps1' { ' [--prebuilt-init ELF]' } else { '' })!
	seconds := timeout(options, if kind == 'ps1' { 300 } else { 600 })!
	for option in ['--game', '--bios', '--prebuilt-init'] {
		if options.has(option) && !os.is_file(options.value(option, '')) { return error_with_code(option + ' must name an existing file', 2) }
	}
	build := build_dir(kind)!
	if !options.has('--no-build') { run(['bash', guesthost.root() + '/scripts/build-' + kind + '-aarch64.sh'])! }
	frontend := build + '/staging/usr/bin/vinix-' + kind
	demo := build + '/staging/usr/share/games/' + kind + '/' + demo_name(kind)
	for path in [frontend, demo] { if !os.is_file(path) { return error_with_code('missing ' + label(kind) + ' build input: ' + path + '; run scripts/build-' + kind + '-aarch64.sh', 2) } }
	sysroot := sdk(kind)
	for path in ['include', 'lib/crt1.o', 'lib/libc.a'] {
		if !os.exists(sysroot + '/' + path) { return error_with_code('missing ARM64 musl sysroot input: ' + sysroot + '/' + path, 2) }
	}
	log_path := hosttest.module_resolve(options.value('--log', build + '/qemu.log'))!
	mkdir(os.dir(log_path))!
	work := hosttest.work_dir('', 'vinix-' + kind + '-vm-')!
	defer { hosttest.remove_work_dir(work) or { eprintln(err.msg()) } }
	rootfs := work + '/rootfs'
	for name in ['root', 'sbin', 'proc', 'sys', 'dev', 'tmp', 'opt/' + kind] { mkdir(rootfs + '/' + name)! }
	stage_tree(build + '/staging', rootfs)!
	if kind == 'n64' {
		half, word, stalled := n64_variants(os.read_bytes(demo)!)!
		os.write_file_array(rootfs + '/opt/n64/paddle.v64', half)!
		os.write_file_array(rootfs + '/opt/n64/paddle.n64', word)!
		os.write_file_array(rootfs + '/opt/n64/budget.z64', stalled)!
	}
	if options.has('--bios') {
		source := options.value('--bios', '')
		bios := rootfs + '/opt/' + kind + '/data/bios'
		mkdir(bios)!
		hosttest.module_copy_file_preserving_stat(source, bios + '/' + if kind == 'ps2' { 'ps2.bin' } else { os.file_name(source) })!
	}
	if options.has('--game') {
		source := options.value('--game', '')
		path := 'opt/' + kind + '/game/' + os.file_name(source)
		stage_game(kind, source, rootfs + '/' + path)!
		os.write_file(rootfs + '/opt/' + kind + '/game-path', '/' + path + '\n')!
	}
	init := compile_guest(kind, work, sysroot, options.value('--prebuilt-init', ''))!
	archive := guesthost.archive_tree(rootfs, work + '/initramfs.tar')!
	runner := hosttest.module_resolve(os.getenv_opt('VINIX_VM_RUNNER_ROOT') or { guesthost.root() })!
	state := work + '/vm'
	previous_network := os.getenv_opt('VINIX_QEMU_NETWORK')
	os.setenv('VINIX_QEMU_NETWORK', '0', true)
	defer { if value := previous_network { os.setenv('VINIX_QEMU_NETWORK', value, true) } else { os.unsetenv('VINIX_QEMU_NETWORK') } }
	configured := guesthost.serial_arm_launch(init, archive, state,
		hosttest.module_resolve(os.getenv_opt('VINIX_KERNEL_DIR') or { runner + '/kernel' })!, runner, 2048, '')!
	heading := '==> Starting AArch64 QEMU boot for the real-time regression\n'
	os.write_file(log_path, heading)!
	print(heading); flush_stdout()
	policyhost.command_checkpoint()!
	result := guesthost.boot_abi_logged(configured.command, configured.env, state, 'aarch64', features(kind, options.has('--game')),
		'VINIX ' + label(kind) + ' GUEST: PASS', [label(kind) + ' FAIL:', 'FATAL EXCEPTION', 'KERNEL PANIC'], seconds, true, runner, log_path)!
	if result == 0 {
		message := '==> AArch64 QEMU real-time regression passed\n'
		mut log := os.open_append(log_path)!; log.write_string(message)!; log.close()
		print(message)
	}
	println('VM transcript: ' + log_path)
	return result
}

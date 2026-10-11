// SPDX-License-Identifier: GPL-2.0-or-later
module systemhost

import diskhost
import guesthost
import hosttest
import os

pub fn swap_header() []u8 {
	mut bytes := []u8{len: 4096}
	for index, value in [u32(1), u32(65535), u32(0)] {
		for offset in 0 .. 4 { bytes[1024 + index * 4 + offset] = u8(value >> u32(offset * 8)) }
	}
	for index, byte in 'SWAPSPACE2'.bytes() { bytes[4086 + index] = byte }
	return bytes
}

fn paging(args []string) !int {
	options := parse(args, [
		hosttest.Option{ name: '--arch', value: true, choices: ['aarch64', 'x86_64'] },
		hosttest.Option{ name: '--kernel-dir', value: true },
		hosttest.Option{ name: '--state-dir', value: true },
		hosttest.Option{ name: '--timeout', value: true },
		hosttest.Option{ name: '--memory', value: true },
		hosttest.Option{ name: '--pressure' },
		hosttest.Option{ name: '--build-only' },
	], [],
		'Usage: run --arch aarch64|x86_64 [--kernel-dir DIR] [--state-dir DIR] [--timeout 240] [--memory 1024] [--pressure] [--build-only]')!
	required(options, ['--arch'])!
	arch := options.value('--arch', '')
	seconds := positive(options, '--timeout', 240)!
	memory := positive(options, '--memory', 1024)!
	state := state_dir(options, 'vinix-paging-')!
	defer { private_cleanup(state, options) }
	kernel := snapshot(state, kernel_source(options, arch), arch)!
	extra := if arch == 'aarch64' { ['-fno-stack-protector'] } else { []string{} }
	compile := [...flags(arch), ...extra, '-pthread']
	guesthost.compile_module(root() + '/tests/kernel-gaps/serialcore', state + '/serial.o', arch, compile)!
	init := state + '/init'
	run([...compile, state + '/serial.o', root() + '/tests/paging/guest.c', '-o', init])!
	diskhost.mkdir(state + '/rootfs')!
	if options.has('--pressure') {
		os.write_file(state + '/rootfs/paging-pressure', '')!
	} else if os.exists(state + '/rootfs/paging-pressure') {
		os.rm(state + '/rootfs/paging-pressure')!
	}
	archive := archive_root(init, state, ['sbin', 'dev', 'proc', 'sys', 'tmp', 'root'])!
	disk := state + '/swap.img'
	diskhost.sparse_file(disk, 256 * 1024 * 1024)!
	mut output := os.open_file(disk, 'r+')!
	written := output.write(swap_header())!
	output.close()
	if written != 4096 { return error('Short swap header write') }
	configured := guesthost.launch(init, archive, state, kernel, arch, true)!
	mut argv := configured.command.clone()
	argv[argv.index('-m') + 1] = memory.str()
	if arch == 'aarch64' {
		arm_config(state, root(), 'vinix.qemu_platform=1 ' + os.getenv('VINIX_CMDLINE'))!
		argv << ['-drive', 'if=none,format=raw,file=' + disk + ',id=paging-swap', '-device',
			'virtio-blk-device,drive=paging-swap']
	} else {
		argv << ['-drive', 'if=ide,format=raw,file=' + disk, '-object',
			'rng-random,filename=/dev/urandom,id=paging-rng', '-device', 'virtio-rng-pci,rng=paging-rng']
	}
	receipt(state, guesthost.Launch{argv, configured.env}, kernel, init, archive, seconds)!
	println('Guest artifacts: ' + state)
	if options.has('--build-only') { return 0 }
	return guesthost.boot(argv, configured.env, state, [
		'PAGING encrypted-disk-swapoff PASS',
		'PAGING PASS',
	],
		['PAGING FAIL', 'FATAL EXCEPTION', 'KERNEL PANIC'], seconds, true)!
}

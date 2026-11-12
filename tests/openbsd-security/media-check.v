// SPDX-License-Identifier: GPL-2.0-or-later
// The unchanged security fixture and verdicts, using the hardware harness's
// FAT boot medium on ARM instead of the legacy El Torito ISO.
module main

import hwhost
import os

fn run() ! {
	if os.args.len != 7 {
		return error('usage: media-check ARCH OUTPUT KERNEL SYSROOT GCC_RUNTIME CLANG (V=<compiler>)')
	}
	arch := os.args[1]
	if arch !in ['aarch64', 'x86_64'] { return error('invalid architecture') }
	root := os.real_path(os.dir(@FILE) + '/../..')
	work := os.abs_path(os.args[2])
	if os.exists(work) { return error('output must be fresh') }
	os.mkdir_all(work)!
	hwhost.run_tool([os.args[6], '--target=' + arch + '-linux-musl', '--sysroot=' + os.args[4],
		'--gcc-install-dir=' + os.args[5], '-fuse-ld=lld', '-static', '-O2', '-Wall', '-Wextra',
		'-Werror', '-pthread', os.dir(@FILE) + '/test.c', '-o', work + '/init'],
		map[string]string{}, work + '/cc.log', 300)!
	host := hwhost.find_host(root, arch, '')!
	outcome := hwhost.run_scenario(host, hwhost.Scenario{
		name:         'openbsd-security'
		arches:       [arch]
		required:     ['VINIX OPENBSD SECURITY: PASS']
		forbidden:    ['VINIX OPENBSD SECURITY: FAIL', 'OPENBSD SECURITY FAIL line']
		qemu:         ['-netdev', 'user,id=net0', '-object',
			'filter-dump,id=vinixdump,netdev=net0,file={state}/net.pcap']
		qemu_aarch64: ['-device', 'virtio-net-device,netdev=net0,mac=52:54:00:12:34:56']
		qemu_x86_64:  ['-device', 'e1000,netdev=net0,mac=52:54:00:12:34:56']
		ending:       .running
	}, hwhost.Run{
		kernel:  os.real_path(os.args[3])
		guest:   work + '/init'
		state:   work + '/boot'
		timeout: 600
		keep:    true
	})
	if !outcome.passed { return error(outcome.reason) }
	// Keep the two harnesses in separate processes: guesthost's legacy global
	// `interrupted` conflicts with hwhost.interrupted in the current compiler.
	v := os.getenv_opt('V') or { return error('set V to the V compiler') }
	hwhost.run_tool([v, '-cc', os.args[6], 'run',
		root + '/tests/native-system-tools/security-verdict.v',
		if arch == 'x86_64' { 'amd64' } else { arch }, work + '/boot/serial.log',
		work + '/boot/net.pcap'], map[string]string{}, work + '/verdict.log', 300)!
	println('OPENBSD SECURITY MEDIA PASS ' + arch)
}

fn main() {
	run() or {
		eprintln(err)
		exit(1)
	}
}

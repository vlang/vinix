// SPDX-License-Identifier: GPL-2.0-or-later
// A/B check for the ARM translated-fork regression: one boot runs the same
// 32-fork probe through the stock translator with W+X allowed, then through
// the forced split RW/RX translator as root and as uid 1000.
module main

import hwhost
import os

const clang = '/opt/homebrew/opt/llvm/bin/clang'

fn run() ! {
	if os.args.len !in [3, 4] {
		return error('usage: check OUTPUT KERNEL [REBUILT_TRANSLATOR] (V=<compiler>)')
	}
	root := os.real_path(os.dir(@FILE) + '/../../..')
	work := os.abs_path(os.args[1])
	kernel := os.real_path(os.args[2])
	v := os.getenv_opt('V') or { return error('set V to the V compiler') }
	if os.exists(work) { return error('output already exists: ' + work) }
	os.mkdir_all(work + '/extras')!
	// The probe and split RW/RX translator retained by the original regression.
	retained := root + '/build/package-wine-translation-fork-qualified-1/extras'
	os.cp(retained + '/qemu-x86_64', work + '/extras/qemu-x86_64')!
	os.cp(retained + '/fork-probe', work + '/extras/fork-probe')!
	os.cp(root + '/build-aarch64-x86-translation/staging/usr/bin/qemu-x86_64',
		work + '/extras/qemu-stock')!
	for name in ['qemu-x86_64', 'fork-probe', 'qemu-stock'] {
		os.chmod(work + '/extras/' + name, 0o755)!
	}
	// A source-built translator (build-support/dota2/qemu, splitwx-fork.patch).
	if os.args.len == 4 {
		os.cp(os.real_path(os.args[3]), work + '/extras/qemu-rebuilt')!
		os.chmod(work + '/extras/qemu-rebuilt', 0o755)!
	}
	cfile := work + '/guest.c'
	hwhost.run_tool([v, '-prod', '-backend', 'c', '-os', 'linux', '-arch', 'arm64', '-gc',
		'none', '-manualfree', '-d', 'no_backtrace', '-d', 'no_segfault_handler', '-o', cfile,
		os.dir(@FILE) + '/guest'], map[string]string{}, work + '/v.log', 300)!
	sysroot := root + '/build-aarch64-x11/sysroot'
	gcc := root + '/build-aarch64-userland/staging/usr/lib/gcc/aarch64-alpine-linux-musl/14.2.0'
	hwhost.run_tool([clang, '--target=aarch64-linux-musl', '--sysroot=' + sysroot,
		'--gcc-install-dir=' + gcc, '-fuse-ld=/opt/homebrew/bin/ld.lld', '-static', '-O2',
		'-w', '-D_GNU_SOURCE', '-fno-stack-protector', cfile, '-lm', '-lpthread', '-o',
		work + '/guest-bin'], map[string]string{}, work + '/cc.log', 300)!
	host := hwhost.find_host(root, 'aarch64', '')!
	os.setenv('VINIX_LIMINE_BOOTAA64', hwhost.shared_path(root,
		'boot-image/limine-bin/BOOTAA64.EFI'), true)
	outcome := hwhost.run_scenario(host, hwhost.Scenario{
		name: 'forkwx', arches: ['aarch64'], required: ['FORKWX DONE'], ending: .running
	}, hwhost.Run{kernel: kernel, guest: work + '/guest-bin', extras: work + '/extras',
		state: work + '/boot', timeout: 240, keep: true})
	if !outcome.passed { return error('boot did not finish: ' + outcome.reason) }
	serial := os.read_file(work + '/boot/serial.log')!
	for line in serial.split_into_lines() {
		if line.starts_with('FORKWX RESULT') { println(line) }
	}
}

fn main() { run() or { eprintln(err); exit(1) } }

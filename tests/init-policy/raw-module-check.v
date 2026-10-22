// SPDX-License-Identifier: GPL-2.0-only
// Run build-only policy artifacts on a frozen kernel without gzip support.
module main

import guesthost
import os
import policyhost

fn command(argv []string) ! {
	mut child := os.new_process(argv[0])
	defer { child.close() }
	child.set_args(argv[1..])
	child.wait()
	if child.code != 0 { return error('raw module ISO remap failed') }
}

fn check() ! {
	if os.args.len != 4 {
		return error('usage: raw-module-check BUILD_ONLY_STATE KERNEL_DIR NEW_RUN')
	}
	guard := policyhost.own_commands()
	defer { guard.close() }
	artifacts := os.real_path(os.args[1])
	kernel := os.real_path(os.args[2])
	work := os.abs_path(os.args[3])
	if os.exists(work) || os.is_link(work) { return error('run path must be new') }
	os.mkdir(work)!
	for policy in ['shell', 'full', 'desktop'] {
		state := work + '/' + policy
		os.mkdir(state)!
		binary := artifacts + '/' + policy + '/policy-init'
		archive := artifacts + '/' + policy + '/initramfs.tar'
		configured := guesthost.launch(binary, archive, state, kernel, 'aarch64', true)!
		// The production ISO builder keeps its current gzip policy. Replace
		// only this disposable fixture's module with the admitted raw archive.
		staging := state + '/iso-root'
		command(['xorriso', '-osirrox', 'on', '-indev', state + '/test.iso', '-extract', '/', staging])!
		os.chmod(staging, 0o700)!
		os.chmod(staging + '/boot', 0o700)!
		config := staging + '/boot/limine.conf'
		os.chmod(config, 0o600)!
		compressed := os.read_file(config)!
		if compressed.count('/boot/initramfs.tar.gz') != 1 {
			return error('expected exactly one compressed initramfs module in the fixture ISO')
		}
		os.write_file(config, compressed.replace('/boot/initramfs.tar.gz', '/boot/initramfs.tar'))!
		os.cp(archive, staging + '/boot/initramfs.tar')!
		patched := state + '/raw-module.iso'
		command(['xorriso', '-as', 'mkisofs', '-R', '-r', '-J', '--efi-boot', 'boot/limine-uefi-cd.bin',
			'-efi-boot-part', '--efi-boot-image', '--protective-msdos-label', staging, '-o', patched])!
		os.mv(patched, state + '/test.iso')!
		expected := match policy {
			'shell' { ['Hello from userland!', 'Vinix 0.1.0 aarch64', 'SHELL INIT GUEST: PASS'] }
			'full' { ['FULL INIT GUEST: PASS'] }
			else {
				['DESKTOP RELOAD FORWARDED: PASS', 'DESKTOP RESTART: PASS', 'DESKTOP INIT GUEST: PASS']
			}
		}
		if guesthost.boot_from(configured.command, configured.env, state, expected,
			['INIT GUEST FAIL:', 'KERNEL PANIC', 'FATAL EXCEPTION'], 90, true, guesthost.root())! != 0 {
			return error('raw-module init policy guest failed: ' + policy)
		}
	}
	println('ALL RAW-MODULE INIT POLICY GUESTS: PASS')
}

fn main() {
	check() or {
		eprintln(err)
		exit(1)
	}
}

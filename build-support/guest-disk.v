// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import cachecli
import imagehost
import os

fn run() ! {
	args := cachecli.arguments(os.args[1..], [], [], [], 0, 2, 'Create a raw AArch64 UEFI guest image.\nUsage: build-vinix-guest-disk.sh [OUTPUT [INITRAMFS]]') or { return error_with_code(err.msg(), 2) }
	root := os.real_path(os.dir(@FILE) + '/..')
	output := if args.positional.len > 0 {
		args.positional[0]
	} else {
		root + '/build-aarch64-qemu-system/vinix-guest.img'
	}
	initramfs := if args.positional.len > 1 {
		args.positional[1]
	} else {
		root + '/build-support/init-aarch64/initramfs.tar'
	}
	size := imagehost.build(root, output, initramfs, os.environ())!
	println('wrote ${output} (${size} MiB)')
}

fn main() {
	guard := cachecli.own_commands()
	defer { guard.close() }
	run() or {
		eprintln(err)
		exit(if cachecli.cancelled() {
			cachecli.interrupt_status()
		} else if err.code() == 2 {
			2
		} else {
			1
		})
	}
}

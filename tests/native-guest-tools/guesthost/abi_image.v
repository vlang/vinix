// SPDX-License-Identifier: GPL-2.0-or-later
module guesthost

import os

fn abi_home_volume(state string) ! {
	disk := state + '/root.ext2'
	os.write_file(disk, '')!
	if unsafe { C.truncate(disk.str, i64(64 * 1024 * 1024)) } < 0 { return posix_error() }
	mut formatter := os.getenv('VINIX_MKE2FS')
	if formatter == '' {
		for candidate in ['mke2fs', 'mkfs.ext2', '/opt/homebrew/opt/e2fsprogs/sbin/mke2fs',
			'/usr/local/opt/e2fsprogs/sbin/mke2fs'] {
			formatter = os.find_abs_path_of_executable(candidate) or { continue }
			break
		}
	}
	if formatter == '' { return error('mke2fs is required for the private ARM ext2 home') }
	run([formatter, '-q', '-F', '-t', 'ext2', '-b', '4096', '-I', '128', '-O',
		'filetype,sparse_super,^has_journal,^resize_inode,^dir_index,^extent,^64bit,^metadata_csum',
		disk])!
}

fn abi_arm_config(state string, runner_root string) ! {
	// The generic ISO builder does not forward VINIX_CMDLINE on ARM. Replace
	// only the private ISO's config, retaining its UEFI El Torito/GPT metadata.
	cmdline := 'vinix.qemu_persist=1' + if os.getenv('VINIX_CMDLINE') != '' {
		' ' + os.getenv('VINIX_CMDLINE')
	} else {
		''
	}
	if cmdline.contains('\n') || cmdline.contains('\r') {
		return error('Kernel command line must fit one line')
	}
	config := state + '/limine.conf'
	text := os.read_file(runner_root + '/build-support/limine.conf')!
	os.write_file(config, text + '    cmdline: ' + cmdline + '\n')!
	patched := state + '/test-configured.iso'
	run(['xorriso', '-indev', state + '/test.iso', '-outdev', patched, '-map', config,
		'/boot/limine.conf', '-boot_image', 'any', 'replay'])!
	os.mv(patched, state + '/test.iso')!
}

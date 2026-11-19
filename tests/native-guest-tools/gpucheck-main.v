// SPDX-License-Identifier: GPL-2.0-or-later
// Boot tests/gpucheck/guest.c on aarch64 with tools/gpucheck in /sbin and the
// root that tests/omarchy-mesa/stage.v staged as a read-only ext2 disk.
module main

import guesthost
import os

const usage = 'usage: gpucheck --kernel-dir DIR --root STAGED_ROOT --state NEW_DIR [--timeout SECONDS]'

fn mke2fs() !string {
	for candidate in [os.getenv('VINIX_MKE2FS'), '/opt/homebrew/opt/e2fsprogs/sbin/mke2fs',
		'/usr/local/opt/e2fsprogs/sbin/mke2fs', '/usr/sbin/mke2fs', '/sbin/mke2fs'] {
		if candidate != '' && os.is_executable(candidate) {
			return candidate
		}
	}
	return os.find_abs_path_of_executable('mke2fs') or { error('e2fsprogs mke2fs is required') }
}

fn tree_bytes(path string) u64 {
	mut total := u64(0)
	os.walk_with_context(path, &total, fn (context voidptr, file string) {
		if !os.is_link(file) {
			unsafe {
				*(&u64(context)) += u64(os.file_size(file))
			}
		}
	})
	return total
}

fn run() !int {
	mut kernel_dir := ''
	mut staged := ''
	mut state := ''
	mut timeout := 900
	mut index := 1
	for index < os.args.len {
		if index + 1 >= os.args.len {
			return error(usage)
		}
		value := os.args[index + 1]
		match os.args[index] {
			'--kernel-dir' { kernel_dir = os.real_path(value) }
			'--root' { staged = os.real_path(value) }
			'--state' { state = value }
			'--timeout' { timeout = value.int() }
			else { return error(usage) }
		}
		index += 2
	}
	if kernel_dir == '' || staged == '' || state == '' || timeout <= 0 {
		return error(usage)
	}
	if !os.is_file(staged + '/usr/bin/vulkaninfo') {
		return error('${staged} is not a root staged by tests/omarchy-mesa/stage.v')
	}
	if os.exists(state) {
		return error('${state} already exists; give a new directory')
	}
	os.mkdir_all(state)!
	state_dir := os.real_path(state)
	repo := os.real_path(os.join_path(os.dir(@FILE), '..', '..'))

	// gpucheck goes into the initramfs beside the test init.
	os.mkdir_all(state_dir + '/rootfs/sbin')!
	vexe := os.getenv_opt('VEXE') or { 'v' }
	// GPUCHECK_SOURCE builds another gpucheck.v, for negative controls.
	mut build_args := [vexe, 'run', repo + '/tools/gpucheck/build.v', state_dir + '/rootfs/sbin/gpucheck']
	if source := os.getenv_opt('GPUCHECK_SOURCE') {
		build_args << os.real_path(source)
	}
	build := os.exec(build_args)
	if build.exit_code != 0 {
		return error('building gpucheck: ' + build.output)
	}

	// The same features as the QEMU data disks (build-support/qemu-storage.sh).
	disk := state_dir + '/root.ext2'
	size_mib := tree_bytes(staged) * 13 / 10 / 1048576 + 256
	os.write_file(disk, '')!
	os.truncate(disk, size_mib * 1048576)!
	format := os.exec([mke2fs()!, '-q', '-F', '-t', 'ext2', '-b', '4096', '-I', '128', '-O',
		'filetype,sparse_super,^has_journal,^resize_inode,^dir_index,^extent,^64bit,^metadata_csum',
		'-L', 'omarchy-mesa', '-d', staged, disk])
	if format.exit_code != 0 {
		return error('mke2fs: ' + format.output)
	}

	init := guesthost.compile_init(repo + '/tests/gpucheck/guest.c', state_dir, 'aarch64', false)!
	archive := guesthost.image(init, state_dir)!
	launch := guesthost.launch(init, archive, state_dir, kernel_dir, 'aarch64', true)!
	mut command := launch.command.clone()
	memory := command.index('-m')
	if memory >= 0 {
		command[memory + 1] = '3072'
	}
	command << ['-drive', 'if=none,format=raw,readonly=on,file=' + disk + ',id=omarchy-root', '-device',
		'virtio-blk-device,drive=omarchy-root']
	positive, negative := guesthost.verdict_policy(['GPUCHECK QEMU PASS'], ['GPUCHECK QEMU INCOMPLETE'],
		false)
	println('Guest artifacts: ' + state_dir)
	return guesthost.boot_from_cancelled(command, launch.env, state_dir, positive, negative,
		timeout, true, '', unsafe { nil })!
}

fn main() {
	code := run() or {
		eprintln('gpucheck: ${err.msg()}')
		exit(2)
	}
	exit(code)
}

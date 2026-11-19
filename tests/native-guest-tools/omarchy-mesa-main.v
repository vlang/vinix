// SPDX-License-Identifier: GPL-2.0-or-later
// Boot a guest init on aarch64 with a Mesa root as a read-only ext2 disk:
// tests/omarchy-mesa/guest.c with the root tests/omarchy-mesa/stage.v staged,
// by default, or another guest and root, such as tests/vinix-mesa's.
module main

import guesthost
import os

const usage = 'usage: omarchy-mesa --kernel-dir DIR --root STAGED_ROOT --state NEW_DIR [--timeout SECONDS] [--guest SOURCE] [--marker PREFIX]'

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
	mut source := os.real_path(os.join_path(os.dir(@FILE), '..', 'omarchy-mesa', 'guest.c'))
	// The guest prints PREFIX PASS, or PREFIX INCOMPLETE.
	mut marker := 'OMARCHY-MESA'
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
			'--guest' { source = os.real_path(value) }
			'--marker' { marker = value }
			else { return error(usage) }
		}
		index += 2
	}
	if kernel_dir == '' || staged == '' || state == '' || timeout <= 0 {
		return error(usage)
	}
	if !os.is_file(staged + '/usr/bin/vulkaninfo') {
		return error('${staged} is not a Mesa root with its test clients')
	}
	if os.exists(state) {
		return error('${state} already exists; give a new directory')
	}
	os.mkdir_all(state)!
	state_dir := os.real_path(state)

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
	println('Root disk: ${disk} (${size_mib} MiB)')

	init := guesthost.compile_init(source, state_dir, 'aarch64', false)!
	archive := guesthost.image(init, state_dir)!
	launch := guesthost.launch(init, archive, state_dir, kernel_dir, 'aarch64', true)!
	mut command := launch.command.clone()
	// Mesa, LLVM and the page cache that holds them need more than the
	// harness's 1 GiB.
	memory := command.index('-m')
	if memory >= 0 {
		command[memory + 1] = '3072'
	}
	command << ['-drive', 'if=none,format=raw,readonly=on,file=' + disk + ',id=omarchy-root', '-device',
		'virtio-blk-device,drive=omarchy-root']
	positive, negative := guesthost.verdict_policy(['${marker} PASS'], ['${marker} INCOMPLETE'], false)
	println('Guest artifacts: ' + state_dir)
	return guesthost.boot_from_cancelled(command, launch.env, state_dir, positive, negative,
		timeout, true, '', unsafe { nil })!
}

fn main() {
	code := run() or {
		eprintln('omarchy-mesa: ${err.msg()}')
		exit(2)
	}
	exit(code)
}

// SPDX-License-Identifier: GPL-2.0-or-later
module imagehost

import cachecli
import cachekey
import math
import os
import sourcecommand
import strconv

#include <stdio.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>

fn C.mkstemp(&u8) i32
fn C.fchmod(i32, u32) i32
fn C.umask(u32) u32
fn C.link(&char, &char) i32

pub const limine_config = 'timeout: 0\nverbose: yes\n\n/Vinix\n    protocol: limine\n    kernel_path: boot():/boot/vinix\n    module_path: boot():/boot/initramfs.tar\n    cmdline: vinix.qemu_platform=1\n    kaslr: no\n'

pub fn human_size(text string) !string {
	mut number := strconv.atof64(text)!
	if !math.is_finite(number) || number < 0 { return error('expected a finite nonnegative size') }
	for unit in ['bytes', 'KiB', 'MiB', 'GiB'] {
		if number < 1024 || unit == 'GiB' {
			mut buffer := [512]u8{}
			count := unsafe {
				C.snprintf(&char(&buffer[0]), usize(buffer.len), if unit == 'bytes' {
					c'%.0f'
				} else {
					c'%.1f'
				}, number)
			}
			if count < 0 || count >= buffer.len { return error('size formatting failed') }
			return buffer[..count].bytestr() + ' ' + unit
		}
		number /= 1024
	}
	return error('size formatting failed')
}

pub fn image_size(payloads []u64) !u64 {
	mut total := u64(128 * 1024 * 1024 + 1024 * 1024 - 1)
	for size in payloads {
		if size > u64(0x7fffffffffffffff) - total {
			return error('guest image payload size overflows')
		}
		total += size
	}
	return if total / (1024 * 1024) < 128 { u64(128) } else { total / (1024 * 1024) }
}

fn mkdir(path string) ! {
	if os.is_dir(path) { return }
	previous := os.dir(path)
	if previous != path { mkdir(previous)! }
	os.mkdir(path)!
}

pub fn command(argv []string, environment map[string]string) ! {
	result := sourcecommand.run_preferred(argv, environment, cachecli.cancelled, '')!
	if result.status != 0 {
		return error('guest image command failed (${result.status}): ' + argv[0])
	}
}

pub fn build(root string, output string, initramfs string, environment map[string]string) !u64 {
	if output == '' || output.contains('\x00') { return error('invalid image output') }
	if os.exists(output) || os.is_link(output) { return error('image already exists: ' + output) }
	kernel := root + '/kernel/bin/vinix'
	limine := root + '/boot-image/limine-bin/BOOTAA64.EFI'
	for input in [initramfs, kernel, limine] {
		state := os.stat(input) or { return error('missing guest image input: ' + input) }
		if state.get_filetype() != .regular { return error('missing guest image input: ' + input) }
	}
	mut tools := map[string]string{}
	for name in ['mformat', 'mmd', 'mcopy'] {
		path := cachekey.which(name, environment)!
		if path == '' { return error('missing image build tool: ' + name) }
		tools[name] = path
	}
	size := image_size([os.stat(initramfs)!.size, os.stat(kernel)!.size])!
	if size > u64(0x7fffffffffffffff) / (1024 * 1024) { return error('guest image size overflows') }
	mkdir(os.dir(output))!
	work := sourcecommand.temporary('vinix-guest-disk')!
	defer {
		os.rm(work + '/limine.conf') or {}
		os.rmdir(work) or {}
	}
	os.write_file(work + '/limine.conf', limine_config)!
	mut pattern := (output + '.partial.XXXXXX\x00').bytes()
	fd := C.mkstemp(pattern.data)
	if fd < 0 { return os.error_posix() }
	image := pattern.bytestr().all_before('\x00')
	mut closed := false
	defer {
		if !closed { C.close(fd) }
		os.rm(image) or {}
	}
	if C.ftruncate(fd, size * 1024 * 1024) != 0 { return os.error_posix() }
	// This CLI is single threaded. Restore umask before spawning any SDK tool.
	mask := C.umask(0)
	C.umask(mask)
	if C.fchmod(fd, 0o666 & ~mask) != 0 { return os.error_posix() }
	closed = true
	if C.close(fd) != 0 { return os.error_posix() }
	command([tools['mformat'], '-F', '-i', image, '::'], environment)!
	command([tools['mmd'], '-i', image, '::/EFI', '::/EFI/BOOT', '::/boot'], environment)!
	for source, destination in {
		limine:                '::/EFI/BOOT/BOOTAA64.EFI'
		work + '/limine.conf': '::/boot/limine.conf'
		kernel:                '::/boot/vinix'
		initramfs:             '::/boot/initramfs.tar'
	} {
		command([tools['mcopy'], '-i', image, source, destination], environment)!
	}
	cachecli.checkpoint()!
	// Same-filesystem publication refuses an output created during the build.
	if C.link(image.str, output.str) != 0 { return os.error_posix() }
	return size
}

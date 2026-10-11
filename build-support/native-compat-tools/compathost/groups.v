// SPDX-License-Identifier: GPL-2.0-or-later
module compathost

import guesthost
import hosttest
import json2
import os

#include <unistd.h>
fn C.truncate(&char, i64) i32

fn groups_swap_header(size i64) ![]u8 {
	if size < 8192 || size % 4096 != 0 || size / 4096 - 1 > i64(0xffffffff) { return error('Invalid version-one 4 KiB swap size') }
	mut bytes := []u8{len: 4096}
	fields := [u32(1), u32(size / 4096 - 1), u32(0)]!
	for index, value in fields {
		for offset in 0 .. 4 { bytes[1024 + index * 4 + offset] = u8(value >> (8 * offset)) }
	}
	for index, byte in 'SWAPSPACE2'.bytes() { bytes[4086 + index] = byte }
	return bytes
}

fn groups_launch(command []string, arch string, disk string, memory int, smp int) []string {
	mut argv := configure_process_launch(command, arch, memory, smp, 'max')
	if arch == 'aarch64' {
		// ARM probes VirtIO MMIO slots in reverse registration order. The
		// unchanged fixture selects /dev/vda, so register swap after the ISO.
		argv << ['-drive', 'if=none,format=raw,file=' + disk + ',id=paging-swap',
			'-device', 'virtio-blk-device,drive=paging-swap']
	} else {
		argv << ['-drive', 'if=ide,format=raw,file=' + disk, '-object',
			'rng-random,filename=/dev/urandom,id=paging-rng', '-device', 'virtio-rng-pci,rng=paging-rng']
	}
	return argv
}

fn groups_command(args []string) !int {
	parsed := hosttest.parse_arguments(args, [hosttest.Option{ name: '--arch', value: true, choices: ['aarch64', 'x86_64'] },
		hosttest.Option{ name: '--kernel-dir', value: true }, hosttest.Option{ name: '--state-dir', value: true },
		hosttest.Option{ name: '--timeout', value: true }, hosttest.Option{ name: '--memory', value: true },
		hosttest.Option{ name: '--smp', value: true }, hosttest.Option{ name: '--build-only' }], 0,
		'Usage: run --arch aarch64|x86_64 [--kernel-dir DIR] [--state-dir DIR] [--timeout SECONDS] [--memory MIB] [--smp N] [--build-only]',
		'Exercise the unchanged resource-group fixture with a disposable encrypted-swap disk.') or { return error_with_code(err.msg(), 2) }
	needed(parsed, ['--arch'])!
	arch := parsed.options['--arch']
	timeout := positive_option(parsed, '--timeout', 240)!
	memory := positive_option(parsed, '--memory', 1024)!
	smp := positive_option(parsed, '--smp', 4)!
	// Original default and explicit evidence directories remain available.
	work := if '--state-dir' in parsed.options { resolve(parsed.options['--state-dir'])! } else { hosttest.work_dir('', 'vinix-resource-groups-')! }
	os.mkdir_all(work)!
	kernel := resolve(parsed.options['--kernel-dir'] or { root() + '/kernel' })!
	if !os.is_file(kernel + '/bin/vinix') { return error_with_code('build the requested kernel first', 2) }
	private_kernel := snapshot_kernel(work, kernel, arch)!
	mut cc := []string{}
	if arch == 'aarch64' {
		sdk := os.getenv_opt('VINIX_AARCH64_SYSROOT') or { root() + '/build-aarch64-userland/sysroot' }
		cc = [os.getenv_opt('CC') or { 'clang' }, '--target=aarch64-linux-musl', '--sysroot=' + sdk,
			'-L' + sdk + '/lib', '-fuse-ld=lld', '-fno-stack-protector']
	} else { cc = [os.getenv_opt('CC_AMD64') or { 'x86_64-linux-musl-gcc' }] }
	flags := [...cc, '-static', '-pthread', '-O2', '-Wall', '-Wextra', '-Werror']
	guesthost.compile_module(root() + '/tests/kernel-gaps/serialcore', work + '/serial.o', arch, flags)!
	source := root() + '/tests/resource-groups/guest.c'
	init := work + '/init'
	compile := [...flags, work + '/serial.o', source, '-o', init]
	run(compile)!
	elf_arch(init, arch)!
	for name in ['sbin', 'dev', 'proc', 'sys', 'tmp', 'root'] { os.mkdir_all(work + '/rootfs/' + name)! }
	hosttest.module_copy_file_preserving_stat(init, work + '/rootfs/sbin/init')!
	archive := native_archive(work)!
	disk := work + '/swap.img'
	size := i64(256 * 1024 * 1024)
	header := groups_swap_header(size)!
	os.write_file_array(disk, header)!
	if unsafe { C.truncate(disk.str, size) } < 0 { return error('Cannot size the dedicated swap image: ' + os.get_error_msg(int(C.errno))) }
	mut receipt := { 'arch': json2.Any(arch), 'compile_command': json2.Any(hosttest.strings(compile)),
		'source_sha256': json2.Any(hosttest.sha(source)!), 'init_sha256': json2.Any(hosttest.sha(init)!),
		'kernel_sha256': json2.Any(hosttest.sha(private_kernel + '/bin/vinix')!), 'archive_sha256': json2.Any(hosttest.sha(archive)!),
		'swap_header_sha256': json2.Any(hosttest.text_sha(header.bytestr())), 'swap_size': json2.Any(size),
		'timeout': json2.Any(timeout), 'memory': json2.Any(memory), 'smp': json2.Any(smp) }
	hosttest.write_json(work + '/inputs.json', receipt)!
	if '--build-only' in parsed.options { return 0 }
	configured := guesthost.launch(init, archive, work, private_kernel, arch, true)!
	argv := groups_launch(configured.command, arch, disk, memory, smp)
	receipt['command'] = hosttest.strings(argv)
	hosttest.write_json(work + '/inputs.json', receipt)!
	println('Guest artifacts: ' + work)
	return guesthost.boot(argv, configured.env, work, ['CGROUP PASS'], ['CGROUP FAIL', 'FATAL EXCEPTION', 'KERNEL PANIC'], timeout, true)!
}

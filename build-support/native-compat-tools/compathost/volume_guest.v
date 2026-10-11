// SPDX-License-Identifier: GPL-2.0-or-later
module compathost

import guesthost
import hosttest
import json2
import os
import strconv

fn volume_disk(path string, arch string) ! {
	mut file := os.create(path)!
	defer { file.close() }
	file.seek(16 * 1024 * 1024 - 1, .start)!
	file.write([u8(0)])!
	for offset, value in {
		1024 * 1024 - 512: u8(0xa1)
		1536 * 1024:       u8(0xa2)
	} {
		file.seek(offset, .start)!
		file.write([]u8{len: 512, init: value})!
	}
	if arch == 'x86_64' {
		// One 1 MiB type-83 MBR partition at 12 MiB, exactly as before.
		file.seek(446, .start)!
		file.write([u8(0), 0, 0, 0, 0x83, 0, 0, 0, 0, 0x60, 0, 0, 0, 8, 0, 0])!
		file.seek(510, .start)!
		file.write([u8(0x55), 0xaa])!
	}
}

fn volume_disk_check(path string) ! {
	data := os.read_bytes(path)!
	for offset, value in {
		1024 * 1024 - 512:      u8(0xa1)
		1536 * 1024:            u8(0xa2)
		1024 * 1024:            u8(0x73)
		4 * 1024 * 1024:        u8(0x95)
		4 * 1024 * 1024 + 8192: u8(0x95)
	} {
		length := if value == 0x95 { 4096 } else { 512 }
		if offset + length > data.len || data[offset..offset + length] != []u8{len: length, init: value} {
			return error('Physical volume sentinel/data differs at offset ' + offset.str())
		}
	}
}

fn volume_guest(args []string) !int {
	parsed := hosttest.parse_arguments(args, [
		hosttest.Option{ name: '--arch', value: true, choices: ['aarch64', 'amd64'] },
		hosttest.Option{ name: '--state-dir', value: true },
		hosttest.Option{ name: '--kernel-dir', value: true },
		hosttest.Option{ name: '--build-only' },
	], 0, 'Usage: run [--arch aarch64|amd64] [--state-dir FRESH-DIR] [--kernel-dir DIR] [--build-only]',
		'Exercise block volumes and inspect the disposable disk after a power cut.') or { return error_with_code(err.msg(), 2) }
	arch := if parsed.options['--arch'] == 'amd64' { 'x86_64' } else { 'aarch64' }
	timeout := strconv.atoi(os.getenv_opt('VINIX_QEMU_TIMEOUT') or { '300' }) or { return error_with_code('Invalid VINIX_QEMU_TIMEOUT', 2) }
	if timeout <= 0 { return error_with_code('Timeout must be positive', 2) }
	work := hosttest.work_dir(parsed.options['--state-dir'], 'vinix-volume-')!
	defer { if '--state-dir' !in parsed.options { retire(work) } }
	cc, link := target_compiler(arch)!
	init := work + '/init'
	run([...cc, '-static', '-O2', '-Wall', '-Wextra', '-Werror', '-fno-stack-protector', '-pthread',
		root() + '/tests/storage-volumes/guest.c', ...link, '-o', init])!
	rootfs := work + '/root'
	for name in ['dev', 'proc', 'tmp', 'run', 'sbin', 'root'] { os.mkdir_all(rootfs + '/' + name)! }
	os.cp(init, rootfs + '/sbin/init')!
	os.chmod(rootfs + '/sbin/init', 0o755)!
	stage_command(['--arch', arch, '--staging', rootfs, '--cc',
		[...cc, ...link].map(hosttest.shell_quote(it)).join(' ')], false)!
	archive := guest_archive(work)!
	disk := work + '/volume.raw'
	volume_disk(disk, arch)!
	source_kernel := if '--kernel-dir' in parsed.options {
		resolve(parsed.options['--kernel-dir'])! + '/bin/vinix'
	} else if arch == 'aarch64' {
		resolve(os.getenv_opt('VINIX_KERNEL_DIR') or { root() + '/kernel' })! + '/bin/vinix'
	} else {
		resolve(os.getenv_opt('VINIX_AMD64_KERNEL') or { root() + '/build-amd64-kernel/bin/vinix' })!
	}
	os.mkdir_all(work + '/kernel/bin')!
	hosttest.module_copy_file_preserving_stat(source_kernel, work + '/kernel/bin/vinix')!
	elf_arch(work + '/kernel/bin/vinix', arch)!
	mut receipt := {
		'arch':                json2.Any(arch)
		'kernel_sha256':       json2.Any(hosttest.sha(work + '/kernel/bin/vinix')!)
		'guest_source_sha256': json2.Any(hosttest.sha(root() + '/tests/storage-volumes/guest.c')!)
		'init_sha256':         json2.Any(hosttest.sha(init)!)
		'utility_sha256':      json2.Any(hosttest.sha(rootfs + '/usr/sbin/vinix-volume')!)
		'disk_size':           json2.Any(16 * 1024 * 1024)
		'power_cut':           json2.Any(true)
	}
	hosttest.write_json(work + '/inputs.json', receipt)!
	if '--build-only' in parsed.options { return 0 }
	configured := guesthost.launch_from(init, archive, work, work + '/kernel', arch, true,
		os.getenv_opt('VINIX_VM_RUNNER_ROOT') or { root() })!
	mut argv := configured.command.clone()
	mut env := configured.env.clone()
	// A short private link also protects QEMU's comma-separated drive syntax.
	drive_owner := hosttest.work_dir('', 'vinix-volume-drive-')!
	defer { retire(drive_owner) }
	short := drive_owner + '/disk.raw'
	os.symlink(disk, short)!
	if arch == 'aarch64' {
		// VirtIO MMIO discovery visits the last attached block device first.
		// Keep the writable management disk at vda, as in the old launcher.
		argv << ['-drive', 'if=none,format=raw,file=' + short + ',id=volume-test,discard=unmap',
			'-device', 'virtio-blk-device,drive=volume-test']
	} else {
		argv << ['-drive', 'if=ide,format=raw,file=' + short + ',cache=writeback,discard=unmap']
		if firmware := os.getenv_opt('VINIX_OVMF_CODE_AMD64') {
			for index, argument in argv {
				if argument.starts_with('if=pflash,') {
					argv[index] = 'if=pflash,format=raw,unit=0,readonly=on,file=' + firmware
				}
			}
		}
		if accel := os.getenv_opt('VINIX_QEMU_ACCEL') {
			for index, argument in argv { if argument == '-accel' { argv[index + 1] = accel } }
		}
	}
	env['VINIX_QEMU_NETWORK'] = '0'
	receipt['command'] = hosttest.strings(argv)
	receipt['archive_sha256'] = hosttest.sha(archive)!
	receipt['iso_sha256'] = hosttest.sha(work + '/test.iso')!
	hosttest.write_json(work + '/inputs.json', receipt)!
	result := guesthost.boot_volume(argv, env, work, timeout, true)!
	if result != 0 { return result }
	volume_disk_check(disk)!
	println('PASS ' + if arch == 'aarch64' { 'aarch64' } else { 'amd64' } + ': volumes, discard, CLI, alias/bounds, growth, removal races, 200-cycle retention and physical sentinels')
	return 0
}

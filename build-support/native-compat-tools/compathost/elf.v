// SPDX-License-Identifier: GPL-2.0-or-later
module compathost

import guesthost
import hosttest
import json2
import os
import encoding.binary

fn elf_fixed_executable(path string) ! {
	data := os.read_bytes(path)!
	if data.len < 64 || binary.little_endian_u16(data[16..]) != 2 {
		return error('Direct-loader fixture must be ET_EXEC')
	}
	offset := binary.little_endian_u64(data[32..])
	size := u64(binary.little_endian_u16(data[54..]))
	count := u64(binary.little_endian_u16(data[56..]))
	if size != 56 || offset > u64(data.len) || count > (u64(data.len) - offset) / size {
		return error('Invalid direct-loader program headers')
	}
	for index := u64(0); index < count; index++ {
		at := int(offset + index * size)
		if binary.little_endian_u32(data[at..]) == 1 {
			if binary.little_endian_u64(data[at + 16..]) != 0x400000 {
				return error('Direct-loader fixture must start at 0x400000')
			}
			return
		}
	}
	return error('Direct-loader fixture has no LOAD segment')
}

fn elf_guest_command(args []string) !int {
	parsed := hosttest.parse_arguments(args, [hosttest.Option{ name: '--arch', value: true, choices: ['aarch64', 'x86_64'] },
		hosttest.Option{ name: '--kernel-dir', value: true }, hosttest.Option{ name: '--state-dir', value: true },
		hosttest.Option{ name: '--source', value: true }, hosttest.Option{ name: '--build-only' }], 0,
		'Usage: run --arch aarch64|x86_64 --kernel-dir DIR [--state-dir FRESH-DIR] [--source C] [--build-only]',
		'Boot the real ELF loader with both textrel encodings and a genuine dynamic PIE.') or { return error_with_code(err.msg(), 2) }
	needed(parsed, ['--arch', '--kernel-dir'])!
	arch := parsed.options['--arch']
	if '--source' in parsed.options && !os.is_file(parsed.options['--source']) { return error_with_code('--source must name an existing C control', 2) }
	// Like the original mkdtemp runner, default evidence remains available.
	work := if '--state-dir' in parsed.options { resolve(parsed.options['--state-dir'])! } else { hosttest.work_dir('', 'vinix-elf-text-vm-')! }
	rootfs := work + '/rootfs'
	for name in ['sbin', 'lib', 'tmp', 'dev', 'proc', 'sys', 'root'] { os.mkdir_all(rootfs + '/' + name)! }
	repo := resolve(os.getenv_opt('VINIX_VM_RUNNER_ROOT') or { root() })!
	mut cc := []string{}
	mut sdk := ''
	mut loader := ''
	loader_name := if arch == 'aarch64' { 'ld-musl-aarch64.so.1' } else { 'ld-musl-x86_64.so.1' }
	if arch == 'aarch64' {
		sdk = os.getenv_opt('VINIX_AARCH64_SYSROOT') or { repo + '/build-aarch64-userland/sysroot' }
		loader = os.getenv_opt('VINIX_AARCH64_LOADER') or { repo + '/build-aarch64-userland/staging/lib/' + loader_name }
		cc = [...compiler_prefix('CC', 'clang')!, '--target=aarch64-linux-musl', '--sysroot=' + sdk, '-fuse-ld=lld', '-fno-stack-protector']
	} else { cc = compiler_prefix('CC_AMD64', 'x86_64-linux-musl-gcc')! }
	flags := [...cc, '-O2', '-Wall', '-Wextra', '-Werror']
	guesthost.compile_module(root() + '/tests/kernel-gaps/serialcore', work + '/serial.o', arch, flags)!
	source := if '--source' in parsed.options { resolve(parsed.options['--source'])! } else { work + '/fixture.o' }
	if '--source' !in parsed.options { guesthost.compile_module(root() + '/tests/elf-text/textfixture', source, arch, flags)! }
	static_recipe := [...flags, '-static', work + '/serial.o', source,
		...if arch == 'aarch64' { ['-L' + sdk + '/lib'] } else { []string{} }, '-o', rootfs + '/sbin/init']
	run(static_recipe)!
	mut pie_recipe := [...flags, '-fPIE', '-pie']
	if arch == 'aarch64' {
		pie_recipe << ['-nostdlib', sdk + '/lib/Scrt1.o', sdk + '/lib/crti.o', work + '/serial.o', source,
			loader, sdk + '/lib/crtn.o', '-Wl,--dynamic-linker=/lib/' + loader_name]
	} else {
		pie_recipe << [work + '/serial.o', source]
		loader = output([...cc, '-print-file-name=libc.so'])!.trim_space()
	}
	pie_recipe << ['-o', rootfs + '/elf-pie']
	run(pie_recipe)!
	mut recipes := [static_recipe, pie_recipe]
	maintained_fixture := '--source' !in parsed.options
	if maintained_fixture {
		mut exec_recipe := [...flags, '-no-pie']
		if arch == 'aarch64' {
			exec_recipe << ['-nostdlib', sdk + '/lib/crt1.o', sdk + '/lib/crti.o', work + '/serial.o', source,
				loader, sdk + '/lib/crtn.o', '-Wl,--dynamic-linker=/lib/' + loader_name, '-Wl,--image-base=0x400000']
		} else {
			exec_recipe << [work + '/serial.o', source, '-Wl,-Ttext-segment=0x400000']
		}
		exec_recipe << ['-o', rootfs + '/elf-exec']
		run(exec_recipe)!
		elf_arch(rootfs + '/elf-exec', arch)!
		elf_fixed_executable(rootfs + '/elf-exec')!
		recipes << exec_recipe
	}
	elf_arch(rootfs + '/sbin/init', arch)!
	elf_arch(rootfs + '/elf-pie', arch)!
	elf_arch(loader, arch)!
	hosttest.module_copy_file_preserving_stat(loader, rootfs + '/lib/' + loader_name)!
	os.symlink(loader_name, rootfs + '/lib/libc.so')!
	archive := native_archive(work)!
	private_kernel := snapshot_kernel(work, parsed.options['--kernel-dir'], arch)!
	hosttest.write_json(work + '/inputs.json', { 'arch': json2.Any(arch),
		'commands': string_rows(recipes), 'loader_sha256': json2.Any(hosttest.sha(loader)!),
		'init_sha256': json2.Any(hosttest.sha(rootfs + '/sbin/init')!), 'pie_sha256': json2.Any(hosttest.sha(rootfs + '/elf-pie')!),
		'exec_sha256': if maintained_fixture { json2.Any(hosttest.sha(rootfs + '/elf-exec')!) } else { json2.Any(json2.Null{}) },
		'kernel_sha256': json2.Any(hosttest.sha(private_kernel + '/bin/vinix')!), 'archive_sha256': json2.Any(hosttest.sha(archive)!) })!
	if '--build-only' in parsed.options { return 0 }
	// ISO builders consume this command line before QEMU starts.
	previous_cmdline := os.getenv_opt('VINIX_CMDLINE')
	os.setenv('VINIX_CMDLINE', 'vinix.user_access=strict', true)
	defer { if previous := previous_cmdline { os.setenv('VINIX_CMDLINE', previous, true) } else { os.unsetenv('VINIX_CMDLINE') } }
	configured := guesthost.launch_from(rootfs + '/sbin/init', archive, work, private_kernel, arch, true, repo)!
	mut expected := ['ELF TEXT PASS: ordinary and both textrel encodings', 'ELF TEXT PASS: PIE and interpreter boot']
	if maintained_fixture { expected << 'ELF TEXT PASS: direct musl ET_EXEC at 0x400000' }
	return guesthost.boot(configured.command, configured.env, work, expected,
		['ELF TEXT FAIL', 'FATAL EXCEPTION', 'KERNEL PANIC'], 240, true)!
}

// SPDX-License-Identifier: GPL-2.0-or-later
module xtcontroller

import cachecli
import cachekey
import encoding.binary
import gamehost
import generators
import json2
import os
import sourcecommand
import strconv

pub fn command(argv []string, environment map[string]string) ! {
	result := sourcecommand.run_preferred(argv, environment, cachecli.cancelled, '')!
	if result.status != 0 { return error('ext2 command failed (${result.status}): ' + argv[0]) }
}

pub fn output(argv []string, environment map[string]string) !string {
	result := sourcecommand.capture_stdout_preferred(argv, environment, -1, 32 * 1024 * 1024, cachecli.cancelled, '')!
	if result.status != 0 {
		return error('ext2 command failed (${result.status}): ' + argv[0] + ': ' + result.stdout)
	}
	return result.stdout
}

pub struct Options {
pub:
	arch     string = 'aarch64'
	kernel   string
	source   string
	prebuilt string
	state    string
	acl      bool
	timeout  int = 240
}

pub fn options(root string, argv []string) !Options {
	args := cachecli.arguments(argv, ['--arch', '--kernel-dir', '--source', '--prebuilt-fixture',
		'--state-dir', '--timeout'], [], ['--acl-fixture'], 0, 0, 'Boot one native ext2 guest, check xattr ABI/leaks, reboot and inspect its disk.\nUsage: run [--arch aarch64|x86_64 --kernel-dir PATH --source FILE --prebuilt-fixture ELF --state-dir PATH --acl-fixture --timeout 240]') or { return error_with_code(err.msg(), 2) }
	arch := args.value('--arch', 'aarch64')
	if arch !in ['aarch64', 'x86_64'] { return error_with_code('invalid guest architecture', 2) }
	timeout := int(strconv.common_parse_int(args.value('--timeout', '240'), 10, 32, true, true) or { return error_with_code('invalid timeout', 2) })
	if timeout <= 0 { return error_with_code('timeout must be positive', 2) }
	return Options{ arch: arch, kernel: args.value('--kernel-dir', root + '/kernel'), source: args.value('--source', ''), prebuilt: args.value('--prebuilt-fixture', ''), state: args.value('--state-dir', ''), acl: '--acl-fixture' in args.options, timeout: timeout }
}

fn record(path string, evidence map[string]json2.Any) ! {
	os.write_file(path, json2.encode(json2.Any(evidence), prettify: true) + '\n')!
}

pub fn run(root string, options Options) ! {
	state := cachekey.resolve_path(if options.state == '' {
		sourcecommand.temporary('vinix-ext2-xattr-')!
	} else {
		options.state
	})!
	gamehost.mkdir(state)!
	if os.exists(state + '/root.ext2') {
		return error_with_code('Use a fresh state directory; an existing marker could skip the first boot checks', 2)
	}
	kernel_dir := cachekey.resolve_path(options.kernel)!
	kernel := kernel_dir + '/bin/vinix'
	if !os.is_file(kernel) {
		return error_with_code('Build the requested kernel first: ' + kernel, 2)
	}
	mut header_file := os.open(kernel)!
	mut header := []u8{len: 20}
	read := header_file.read(mut header) or {
		header_file.close()
		return error_with_code('short kernel ELF header', 2)
	}
	header_file.close()
	if read != 20 { return error_with_code('short kernel ELF header', 2) }
	if header.len < 20 || binary.little_endian_u16_at(header, 18) != if options.arch == 'aarch64' {
		u16(183)
	} else {
		u16(62)
	} {
		return error_with_code('Kernel ELF architecture does not match --arch', 2)
	}
	tested_kernel := state + '/kernel/bin/vinix'
	gamehost.copy_file(kernel, tested_kernel)!
	if os.is_file(kernel_dir + '/obj/blob.c') {
		gamehost.copy_file(kernel_dir + '/obj/blob.c', state + '/generated.c')!
	}
	parent := gamehost.parent(kernel_dir)
	listed := output(['git', '-C', parent, 'ls-files', '--cached', '--others', '--exclude-standard',
		'--', 'kernel'], os.environ())!.split_into_lines().sorted()
	mut hashes := map[string]json2.Any{}
	for name in listed {
		if name in hashes { continue }
		if os.is_file(parent + '/' + name) {
			hashes[name] = json2.Any(gamehost.digest(parent + '/' + name)!)
		}
	}
	module_path := root + '/tests/ext2-xattr/xattrfixture'
	fixture_source := if options.source == '' {
		module_path + '/core.v'
	} else {
		cachekey.resolve_path(options.source)!
	}
	mut evidence := {
		'arch':                  json2.Any(options.arch)
		'kernel_sha256':         json2.Any(gamehost.digest(tested_kernel)!)
		'test_sha256':           json2.Any(gamehost.digest(fixture_source)!)
		'kernel_sources_sha256': json2.Any(hashes)
	}
	if options.source == '' {
		mut fixtures := map[string]json2.Any{}
		for name in os.ls(module_path)!.sorted() {
			if os.is_file(module_path + '/' + name) {
				fixtures[name] = json2.Any(gamehost.digest(module_path + '/' + name)!)
			}
		}
		evidence['fixture_sources_sha256'] = json2.Any(fixtures)
	}
	record(state + '/evidence.json', evidence)!
	env := os.environ()
	sdk := env['VINIX_AARCH64_SYSROOT'] or { root + '/build-aarch64-userland/sysroot' }
	cc := if options.arch == 'aarch64' {
		[env['CC'] or { 'clang' }, '--target=aarch64-linux-musl', '--sysroot=' + sdk,
			'-L' + sdk + '/lib', '-fuse-ld=lld']
	} else {
		[env['CC_AMD64'] or { 'x86_64-linux-musl-gcc' }]
	}
	serial := generators.compile_fixture(root + '/tests/kernel-gaps/serialcore', state + '/serial.o', options.arch, [
		...cc,
		'-O2',
		'-Wall',
		'-Wextra',
		'-Werror',
	])!
	flags := [...cc, '-static', '-pthread', '-O2', '-fno-stack-protector', '-Wall', '-Wextra',
		'-Werror']
	if options.prebuilt != '' {
		gamehost.copy_file(cachekey.resolve_path(options.prebuilt)!, state + '/init')!
	} else {
		fixture := if options.source != '' {
			fixture_source
		} else {
			generators.compile_fixture(module_path, state + '/fixture.o', options.arch, flags)!
		}
		command([...flags, fixture, serial, '-o', state + '/init'], env)!
	}
	evidence['fixture_elf_sha256'] = json2.Any(gamehost.digest(state + '/init')!)
	evidence['prebuilt_fixture'] = json2.Any(options.prebuilt != '')
	evidence['fixture_source_relationship'] = json2.Any(if options.prebuilt != '' {
		'prebuilt payload; source provenance supplied independently'
	} else {
		'compiled from recorded source'
	})
	record(state + '/evidence.json', evidence)!
	rootfs := state + '/rootfs'
	for name in ['root', 'sbin', 'tmp', 'dev', 'proc', 'sys', 'run'] {
		gamehost.mkdir(rootfs + '/' + name)!
	}
	gamehost.copy_file(state + '/init', rootfs + '/sbin/init')!
	gamehost.archive(rootfs, state + '/initramfs.tar')!
	mut environment := env.clone()
	for key, value in {
		'VINIX_KERNEL_DIR':           state + '/kernel'
		'VINIX_INITRAMFS':            state + '/initramfs.tar'
		'VINIX_BOOT_DISK':            state + '/boot.img'
		'VINIX_EFIVARS':              state + '/efivars.fd'
		'VINIX_QEMU_PACKAGE_STORE':   state + '/packages.tar'
		'VINIX_QEMU_HOST_SOURCE':     '0'
		'VINIX_QEMU_PERSIST_DISK':    state + '/root.ext2'
		'VINIX_QEMU_PERSIST_SIZE_MB': '64'
		'VINIX_QEMU_AUDIO':           'off'
		'VINIX_QEMU_EXTRA':           '-qmp unix:' + state + '/qmp.sock,server=on,wait=off'
	} {
		environment[key] = value
	}
	environment.delete('VINIX_QEMU_PERSIST')
	$if !macos {
		if 'USE_TCG' !in environment { environment['USE_TCG'] = '1' }
	}
	println('Guest artifacts: ' + state)
	e2fsck := env['E2FSCK'] or {
		found := cachekey.which('e2fsck', env)!
		if found == '' { '/opt/homebrew/opt/e2fsprogs/sbin/e2fsck' } else { found }
	}
	debugfs := env['DEBUGFS'] or {
		found := cachekey.which('debugfs', env)!
		if found == '' { '/opt/homebrew/opt/e2fsprogs/sbin/debugfs' } else { found }
	}
	mut launch := []string{}
	mut marker := '/xattr-marker'
	if options.arch == 'aarch64' {
		if options.acl { seed_disk(rootfs, state, debugfs, false, true)! }
		launch = [root + '/scripts/run-aarch64.sh', '--no-build', '--serial', '--mem=1024',
			'--guest-init=' + state + '/init']
	} else {
		cache := root + '/build-amd64-iso/limine'
		if os.is_dir(cache) { gamehost.copy_tree(cache, state + '/iso-build/limine', true)! }
		for key, value in {
			'VINIX_AMD64_KERNEL':        tested_kernel
			'VINIX_AMD64_INITRAMFS':     state + '/initramfs.tar'
			'VINIX_AMD64_ISO':           state + '/test.iso'
			'VINIX_AMD64_ISO_BUILD_DIR': state + '/iso-build'
		} {
			environment[key] = value
		}
		command([root + '/build-support/build-amd64-iso.sh'], environment)!
		os.write_file(rootfs + '/.vinix-image-id', gamehost.digest(state + '/initramfs.tar')![..16] + '\n')!
		seed_disk(rootfs, state, debugfs, true, options.acl)!
		qemu := cachekey.which(env['VINIX_QEMU_X86_64'] or { 'qemu-system-x86_64' }, env)!
		if qemu == '' { return error_with_code('qemu-system-x86_64 is missing', 2) }
		firmware := env['VINIX_OVMF_CODE'] or { os.dir(os.dir(qemu)) + '/share/qemu/edk2-x86_64-code.fd' }
		launch = [qemu, '-machine', 'q35,smm=off', '-accel', 'tcg', '-cpu', 'max', '-m', '1024',
			'-smp', '2', '-drive', 'if=pflash,format=raw,unit=0,readonly=on,file=' + firmware,
			'-cdrom', state + '/test.iso', '-drive',
			'if=ide,format=raw,file=' + state + '/root.ext2,cache=writeback', '-display', 'none',
			'-monitor', 'none', '-qmp', 'unix:' + state + '/qmp.sock,server=on,wait=off', '-serial',
			'mon:stdio']
		marker = '/root/xattr-marker'
	}
	result := boot(launch, environment, state, options.timeout)!
	text := gamehost.decode_utf8(os.read_bytes(state + '/serial.log')!)
	if result != 0 || text.count('XATTR: START') != 2 || !text.contains('XATTR: REBOOT') {
		return error('Native xattr reboot test failed')
	}
	command([e2fsck, '-fn', state + '/root.ext2'], env)!
	attributes := output([debugfs, '-R', 'ea_list ' + marker, state + '/root.ext2'], env)!
	println(attributes)
	if !['user.binary', 'trusted.secret', 'security.test'].all(attributes.contains(it)) {
		return error('Host ext2 tools could not read the persisted attributes')
	}
	println('Native ABI, retained allocations, reboot persistence and host ext2 validation passed.')
}

fn seed_disk(rootfs string, state string, debugfs string, x86 bool, acl bool) ! {
	seed := if x86 { rootfs } else { state + '/acl-seed' }
	if !x86 { gamehost.mkdir(seed)! }
	base := seed + if x86 { '/root' } else { '' }
	// The x86 root is always created on ext2; ACL fixtures are opt-in.
	if acl {
		os.write_file(base + '/acl-corrupt', 'corrupt ACL fixture\n')!
		os.write_file(base + '/acl-inconsistent', 'inconsistent ACL fixture\n')!
		gamehost.mkdir(base + '/acl-corrupt-dir')!
	}
	disk := state + '/root.ext2'
	mut file := os.create(disk)!
	if C.ftruncate(file.fd, 64 * 1024 * 1024) != 0 {
		file.close()
		return os.error_posix()
	}
	file.close()
	command([os.dir(debugfs) + '/mke2fs', '-q', '-F', '-t', 'ext2', '-b', '4096', '-I', '128',
		'-O',
		'filetype,sparse_super,^has_journal,^resize_inode,^dir_index,^extent,^64bit,^metadata_csum',
		'-d', seed, disk], os.environ())!
	if acl {
		value := state + '/invalid-acl.bin'
		prefix := if x86 { '/root' } else { '' }
		for name in ['/acl-corrupt', '/acl-corrupt-dir'] {
			corrupt_acl(debugfs, disk, prefix + name, value)!
		}
		seed_acl(debugfs, disk, prefix + '/acl-inconsistent', value)!
		command([debugfs, '-w', '-R', 'set_inode_field ' + prefix + '/acl-inconsistent mode 0100600',
			disk], os.environ())!
	}
}

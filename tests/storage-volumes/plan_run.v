// SPDX-License-Identifier: GPL-2.0-or-later
// Native V qualification controller. QEMU runs directly; no Python transport.
module main

import os
import time
import encoding.hex
import bootcapture

#include <signal.h>
fn C.kill(i32, i32) i32
fn C.ftruncate(i32, u64) i32

// os.truncate opens with O_TRUNC. Keep the existing prefix of this disposable
// backing file by resizing its retained writable descriptor instead.
fn shrink_disk(path string, length u64) ! {
	mut disk := os.open_file(path, 'r+')!
	defer { disk.close() }
	if C.ftruncate(disk.fd, length) != 0 { return error('Cannot contract disposable backing disk') }
}

fn command(args []string) !string {
	result := os.exec(args)
	if result.exit_code != 0 { return error('Command failed: ${args[0]}\n${result.output}') }
	return result.output
}

fn generate(root string, source string, output string, arch string) ! {
	command(['sh', root + '/build-support/run-v-tool.sh', root + '/tests/linuxkpi/generate_module.v',
		source, output, '--arch', if arch == 'aarch64' { 'arm64' } else { 'amd64' }])!
}

fn check_generated(path string) ! {
	text := os.read_file(path)!
	for symbol in ['memdup(', 'malloc(', 'calloc(', 'realloc(', 'new_array', 'v_fixed_index('] {
		if text.contains(symbol) { return error('Unexpected allocation/runtime dependency ${symbol} in ${path}') }
	}
}

fn host(root string, work string) ! {
	v := os.getenv_opt('V') or { @VEXE }
	os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true)
	for entry in ['plan_test', 'plan_bundle_test', 'plan_growth_test', 'plan_check_test', 'plan_edit_test', 'plan_disks_test', 'plan_space_test', 'plan_capacity_test', 'plan_pool_test', 'plan_pool_growth_test', 'plan_pool_batch_test', 'plan_lock_test', 'plan_pool_grow_batch_test', 'plan_pool_expand_batch_test', 'plan_capacity_batch_test', 'plan_pool_members_batch_test', 'plan_pool_order_test', 'plan_remove_batch_test', 'plan_enroll_batch_test', 'plan_forget_batch_test', 'plan_add_batch_test', 'plan_grow_batch_test', 'plan_pool_contract_batch_test', 'plan_pool_resize_batch_test', 'plan_capacity_contract_batch_test', 'plan_multi_pool_batch_test', 'plan_multi_pool_grow_batch_test', 'data_manifest_test'] {
		binary := work + '/' + entry
		command([v, '-enable-globals', '-cc', 'clang', '-d', 'volume_library', '-cflags',
			'-I' + root + '/tools/volumes/volumecli -fsanitize=address,undefined', '-ldflags',
			'-fsanitize=address,undefined', '-o', binary, root + '/tools/volumes/volumecli/' + entry + '.v'])!
		print(command([binary])!)
		println('PASS ' + entry + ': ASan/UBSan')
	}
	bundle_publication_tests(root, work, v)!
	growth_io_tests(root, work, v)!
	capacity_io_tests(root, work, v)!
	capacity_batch_io_tests(root, work, v)!
	data_io_tests(root, work, v)!
	for arch in ['aarch64', 'x86_64'] {
		path := work + '/volume-' + arch + '.c'
		generate(root, root + '/tools/volumes/volumecli', path, arch)!
		check_generated(path)!
	}
	init_policy(root, work)!
	println('PASS host: plan format, identity, corruption, bounded plan sets, atomic publication and sanitizers')
}

fn data_io_tests(root string, work string, v string) ! {
	fixture := work + '/dataio'
	os.mkdir(fixture)!
	for file in os.ls(root + '/tools/volumes/volumecli')! {
		if !file.ends_with('.v') || file.ends_with('_test.v') { continue }
		mut source := os.read_file(root + '/tools/volumes/volumecli/' + file)!
		if file == 'data_io.v' {
			for name in ['open', 'close', 'pread'] { source = source.replace('C.' + name + '(', 'data_mock_' + name + '(') }
		}
		if file == 'plan_io.v' {
			for name in ['ioctl', 'pread'] { source = source.replace('C.' + name + '(', 'data_mock_' + name + '(').replace('fn data_mock_' + name + '(', 'fn C.' + name + '(') }
			start := source.index('fn publish_bytes(') or { return error('Missing shared publisher') }
			end := source.index('\nfn volume_path(') or { return error('Missing publisher boundary') }
			mut publisher := source[start..end]
			for name in ['write', 'fsync', 'close', 'renameat'] { publisher = publisher.replace('C.' + name + '(', 'data_publish_' + name + '(') }
			source = source[..start] + publisher + source[end..]
		}
		os.write_file(fixture + '/' + file, source)!
	}
	os.cp(root + '/tests/storage-volumes/data_io_test.v', fixture + '/data_io_test.v')!
	binary := work + '/data-io-test'
	command([v, '-enable-globals', '-cc', 'clang', '-d', 'volume_library', '-cflags',
		'-I' + root + '/tools/volumes/volumecli -fsanitize=address,undefined', '-ldflags',
		'-fsanitize=address,undefined', '-o', binary, fixture + '/data_io_test.v'])!
	print(command([binary])!)
	println('PASS data checksums: all-device pinning/rechecks, streaming short reads, later corruption, atomic publication and output failures under ASan/UBSan')
}

fn capacity_batch_io_tests(root string, work string, v string) ! {
	fixture := work + '/capacitybatchio'
	os.mkdir(fixture)!
	for file in os.ls(root + '/tools/volumes/volumecli')! {
		if !file.ends_with('.v') || file.ends_with('_test.v') { continue }
		mut source := os.read_file(root + '/tools/volumes/volumecli/' + file)!
		if file in ['plan_capacity_batch.v', 'plan_capacity_contract_batch.v'] {
			for name in ['open', 'close'] { source = source.replace('C.' + name + '(', 'capacity_batch_mock_' + name + '(') }
		}
		if file == 'plan_io.v' {
			for name in ['ioctl', 'pread'] {
				source = source.replace('C.' + name + '(', 'capacity_batch_mock_' + name + '(')
					.replace('fn capacity_batch_mock_' + name + '(', 'fn C.' + name + '(')
			}
			start := source.index('fn publish_bytes(') or { return error('Missing shared publisher') }
			end := source.index('\nfn volume_path(') or { return error('Missing publisher boundary') }
			mut publisher := source[start..end]
			for name in ['write', 'fsync', 'close', 'renameat'] {
				publisher = publisher.replace('C.' + name + '(', 'capacity_batch_publish_' + name + '(')
			}
			source = source[..start] + publisher + source[end..]
		}
		os.write_file(fixture + '/' + file, source)!
	}
	os.cp(root + '/tests/storage-volumes/capacity_batch_io_test.v', fixture + '/capacity_batch_io_test.v')!
	binary := work + '/capacity-batch-io-test'
	command([v, '-enable-globals', '-cc', 'clang', '-d', 'volume_library', '-cflags',
		'-I' + root + '/tools/volumes/volumecli -fsanitize=address,undefined', '-ldflags',
		'-fsanitize=address,undefined', '-o', binary, fixture + '/capacity_batch_io_test.v'])!
	print(command([binary])!)
	println('PASS capacity batches: all-device pinning/rechecks, complete rollback, previews, publication faults and output failure under ASan/UBSan')
}

// Keep filesystem reads/publication real, replacing only the physical device
// boundary and the shared publisher's synchronous fault-injection boundary.
fn capacity_io_tests(root string, work string, v string) ! {
	fixture := work + '/capacityio'
	os.mkdir(fixture)!
	for file in os.ls(root + '/tools/volumes/volumecli')! {
		if !file.ends_with('.v') || file.ends_with('_test.v') { continue }
		mut source := os.read_file(root + '/tools/volumes/volumecli/' + file)!
		if file == 'plan_capacity.v' {
			for name in ['open', 'close'] { source = source.replace('C.' + name + '(', 'capacity_mock_' + name + '(') }
		}
		if file == 'plan_io.v' {
			for name in ['ioctl', 'pread'] {
				source = source.replace('C.' + name + '(', 'capacity_mock_' + name + '(')
					.replace('fn capacity_mock_' + name + '(', 'fn C.' + name + '(')
			}
			start := source.index('fn publish_bytes(') or { return error('Missing shared publisher') }
			end := source.index('\nfn volume_path(') or { return error('Missing publisher boundary') }
			mut publisher := source[start..end]
			for name in ['write', 'fsync', 'close', 'renameat'] {
				publisher = publisher.replace('C.' + name + '(', 'capacity_publish_' + name + '(')
			}
			source = source[..start] + publisher + source[end..]
		}
		os.write_file(fixture + '/' + file, source)!
	}
	os.cp(root + '/tests/storage-volumes/capacity_io_test.v', fixture + '/capacity_io_test.v')!
	binary := work + '/capacity-io-test'
	command([v, '-enable-globals', '-cc', 'clang', '-d', 'volume_library', '-cflags',
		'-I' + root + '/tools/volumes/volumecli -fsanitize=address,undefined', '-ldflags',
		'-fsanitize=address,undefined', '-o', binary, fixture + '/capacity_io_test.v'])!
	print(command([binary])!)
	println('PASS physical capacity adoption: pinned read-only probes, identity/geometry changes, atomic publication, durable no-op and output failure under ASan/UBSan')
}

fn growth_io_tests(root string, work string, v string) ! {
	fixture := work + '/growthio'
	os.mkdir(fixture)!
	for file in os.ls(root + '/tools/volumes/volumecli')! {
		if !file.ends_with('.v') || file.ends_with('_test.v') { continue }
		mut source := os.read_file(root + '/tools/volumes/volumecli/' + file)!
		if file == 'plan_io.v' {
			for name in ['open', 'close', 'ioctl', 'pread'] {
				source = source.replace('C.' + name + '(', 'growth_mock_' + name + '(')
					.replace('fn growth_mock_' + name + '(', 'fn C.' + name + '(')
			}
		}
		if file == 'plan_set.v' {
			source = source.replace('discover_disk(', 'growth_mock_discover(')
				.replace('C.close(', 'growth_mock_close(')
		}
		os.write_file(fixture + '/' + file, source)!
	}
	os.cp(root + '/tests/storage-volumes/growth_io_test.v', fixture + '/growth_io_test.v')!
	binary := work + '/growth-io-test'
	command([v, '-enable-globals', '-cc', 'clang', '-d', 'volume_library', '-cflags',
		'-I' + root + '/tools/volumes/volumecli -fsanitize=address,undefined', '-ldflags',
		'-fsanitize=address,undefined', '-o', binary, fixture + '/growth_io_test.v'])!
	print(command([binary])!)
	println('PASS growth replay: preflight, generation/geometry recheck, failures, cleanup and resumable application under ASan/UBSan')
}

// Replace only the shared publisher's synchronous syscall boundary. The
// production encoder, cleanup and publication ordering are compiled unchanged.
fn bundle_publication_tests(root string, work string, v string) ! {
	fixture := work + '/bundleio'
	os.mkdir(fixture)!
	for file in os.ls(root + '/tools/volumes/volumecli')! {
		if !file.ends_with('.v') || file.ends_with('_test.v') { continue }
		mut source := os.read_file(root + '/tools/volumes/volumecli/' + file)!
		if file == 'plan_enroll_batch.v' {
			for name in ['open', 'close', 'fstat', 'pread'] { source = source.replace('C.' + name + '(', 'enrollment_mock_' + name + '(') }
		}
		if file == 'plan_io.v' {
			start := source.index('fn publish_bytes(') or { return error('Missing shared publisher') }
			end := source.index('\nfn volume_path(') or { return error('Missing publisher boundary') }
			mut publisher := source[start..end]
			for name in ['write', 'fsync', 'close', 'renameat'] {
				publisher = publisher.replace('C.' + name + '(', 'bundle_mock_' + name + '(')
			}
			source = source[..start] + publisher + source[end..]
		}
		os.write_file(fixture + '/' + file, source)!
	}
	os.cp(root + '/tests/storage-volumes/bundle_io_test.v', fixture + '/bundle_io_test.v')!
	binary := work + '/bundle-io-test'
	command([v, '-enable-globals', '-cc', 'clang', '-d', 'volume_library', '-cflags',
		'-I' + root + '/tools/volumes/volumecli -fsanitize=address,undefined', '-ldflags',
		'-fsanitize=address,undefined', '-o', binary, fixture + '/bundle_io_test.v'])!
	print(command([binary])!)
	println('PASS bundle publication: interruption, short writes, file/directory flush, close and rename faults under ASan/UBSan')
}

fn init_policy(root string, work string) ! {
	generate(root, root + '/tests/init-policy/hostfixture', work + '/init-fixture.c', 'aarch64')!
	for variant in ['normal', 'echo'] {
		mut args := ['sh', root + '/build-support/run-v-tool.sh', root + '/build-support/init-aarch64/compile_init.v',
			'desktop', work + '/init-policy-' + variant + '.c', '--host']
		if variant == 'echo' { args << '--busybox-echo-test' }
		command(args)!
		check_generated(work + '/init-policy-' + variant + '.c')!
		binary := work + '/init-host-' + variant
		command(['clang', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-Wno-unused-function',
			'-Wno-unused-parameter', '-Wno-unused-label', '-D_GNU_SOURCE', '-DVINIX_INIT_HOST_TEST',
			'-fsanitize=address,undefined', '-I', root + '/build-support/init-aarch64',
			'-I', root + '/tests/init-policy/hostfixture', work + '/init-policy-' + variant + '.c',
			work + '/init-fixture.c', '-o', binary])!
		print(command(if variant == 'echo' { [binary, 'echo'] } else { [binary] })!)
	}
}

fn write_disk(path string, wrong bool) ! {
	mut file := os.create(path)!
	defer { file.close() }
	file.seek(16 * 1024 * 1024 - 1, .start)!
	file.write([u8(0)])!
	mut sector := [512]u8{}
	sector[440] = if wrong { 0x79 } else { 0x78 }; sector[441] = 0x56; sector[442] = 0x34; sector[443] = 0x12
	sector[510] = 0x55; sector[511] = 0xaa
	// An unformatted partition must not be mistaken for its whole parent.
	sector[450] = 0x83; sector[455] = 0x40; sector[459] = 8
	file.seek(0, .start)!
	file.write(sector[..])!
}

fn nvme_disk(path string, identity u8) ! {
	write_disk(path, false)!
	mut file := os.open_file(path, 'r+')!
	defer { file.close() }
	file.seek(440, .start)!
	file.write([identity])!
}

fn plan_filesystem(work string) ! {
	tool := os.find_abs_path_of_executable('mke2fs') or {
		'/opt/homebrew/opt/e2fsprogs/sbin/mke2fs'
	}
	command([tool, '-q', '-F', '-t', 'ext2', '-b', '4096', '-I', '128', '-m', '0',
		'-d', work + '/seed', work + '/config.ext2', '2048'])!
	debugfs := os.join_path(os.dir(tool), 'debugfs')
	for path in ['/etc', '/etc/vinix'] {
		command([debugfs, '-w', '-R', 'set_inode_field ' + path + ' uid 0', work + '/config.ext2'])!
	}
}

fn compile_guest(root string, work string, arch string, nvme bool) ! {
	source := work + '/guest.c'
	if nvme {
		command(['sh', root + '/build-support/run-v-tool.sh', root + '/tests/linuxkpi/generate_module.v',
			root + '/tests/storage-volumes/planguest', source, '--arch', 'amd64', '-d', 'nvme_health_test'])!
	} else { generate(root, root + '/tests/storage-volumes/planguest', source, arch)! }
	check_generated(source)!
	cc := if arch == 'aarch64' { 'aarch64-linux-musl-gcc' } else { 'x86_64-linux-musl-gcc' }
	command([cc, '-static', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror',
		'-Wno-unused-function', '-Wno-unused-parameter', '-Wno-unused-label', '-D_GNU_SOURCE',
		'-DVINIX_V_RUNTIME', '-I', root + '/tools/volumes/volumecli', source, '-o', work + '/init'])!
	os.mkdir_all(work + '/seed/sbin')!
	for name in ['dev', 'proc', 'tmp', 'root', 'run', 'sys'] { os.mkdir_all(work + '/seed/' + name)! }
	os.write_file(work + '/seed/.vinix-image-id', 'volume-plan-fixture\n')!
	os.cp(work + '/init', work + '/seed/sbin/init')!
	os.chmod(work + '/seed/sbin/init', 0o755)!
	print(command(['sh', root + '/build-support/run-v-tool.sh', root + '/build-support/storage-tools/stage.v',
		'--arch', if arch == 'aarch64' { 'aarch64' } else { 'x86_64' }, '--staging', work + '/seed'])!)
	os.mkdir_all(work + '/seed/etc/vinix')!
	os.write_file(work + '/seed/etc/vinix/volumes.vmap', 'deliberately invalid boot plan\n')!
	os.mkdir_all(work + '/seed/usr/bin')!
	os.cp(work + '/init', work + '/seed/usr/bin/vinix-desktop')!
	os.chmod(work + '/seed/usr/bin/vinix-desktop', 0o755)!
	if arch == 'aarch64' {
		command(['sh', root + '/build-support/run-v-tool.sh', root + '/build-support/init-aarch64/compile_init.v',
			'desktop', work + '/boot-init.c'])!
		check_generated(work + '/boot-init.c')!
		command(['clang', '--target=aarch64-linux-none', '-nostdlib', '-ffreestanding', '-O2',
			'-fno-stack-protector', '-fno-builtin', '-ffunction-sections', '-fdata-sections', '-c',
			'-I', root + '/build-support/init-aarch64', work + '/boot-init.c', '-o', work + '/boot-init.o'])!
		command(['clang', '--target=aarch64-linux-none', '-c', root + '/build-support/init-aarch64/syscall_abi.S', '-o', work + '/boot-abi.o'])!
		command(['ld.lld', '-m', 'aarch64elf', '--nostdlib', '-static', '--gc-sections',
			work + '/boot-init.o', work + '/boot-abi.o', '-o', work + '/seed/sbin/init'])!
	} else {
		cached := os.getenv_opt('VINIX_AMD64_USERLAND_ROOT') or { root + '/build-amd64-userland/staging' }
		os.mkdir_all(work + '/seed/bin')!; os.mkdir_all(work + '/seed/lib')!
		for path in ['bin/busybox', 'lib/ld-musl-x86_64.so.1'] { os.cp(cached + '/' + path, work + '/seed/' + path)! }
		os.symlink('busybox', work + '/seed/bin/sh')!
		// The V console adapter execs the unchanged packaged init as PID 1.
		os.mkdir_all(work + '/seed/usr/libexec')!
		os.cp(root + '/build-support/init-amd64/desktop-init', work + '/seed/usr/libexec/volume-test-init')!
	}
	os.chmod(work + '/seed/sbin/init', 0o755)!
}

fn pack(work string) ! {
	command(['tar', '--format=ustar', '-cf', work + '/initramfs.tar', '-C', work + '/seed', '.'])!
}

fn amd64_boot(root string, work string, kernel string, second bool, nvme bool) ![]string {
	iso := work + '/iso'
	os.mkdir_all(iso + '/boot')!
	os.mkdir_all(iso + '/EFI/BOOT')!
	os.cp(kernel, iso + '/boot/vinix')!
	os.cp(work + '/initramfs.tar', iso + '/boot/initramfs.tar')!
	os.cp(root + '/build-amd64-iso/limine/BOOTX64.EFI', iso + '/EFI/BOOT/BOOTX64.EFI')!
	os.cp(root + '/build-amd64-iso/limine/limine-uefi-cd.bin', iso + '/boot/limine-uefi-cd.bin')!
	os.write_file(iso + '/boot/limine.conf', os.read_file(root + '/build-support/limine.conf')! + '\n    cmdline: vinix.disk=auto\n')!
	command(['xorriso', '-as', 'mkisofs', '-iso-level', '3', '-R', '-r', '-J',
		'-e', 'boot/limine-uefi-cd.bin', '-no-emul-boot', iso, '-o', work + '/test.iso'])!
	qemu := os.find_abs_path_of_executable('qemu-system-x86_64')!
	firmware := os.getenv_opt('VINIX_OVMF_CODE_AMD64') or {
		os.dir(os.dir(os.real_path(qemu))) + '/share/qemu/edk2-x86_64-code.fd'
	}
	first_disk := work + if second { '/wrong.raw' } else { '/volume.raw' }
	second_disk := work + if second { '/volume.raw' } else { '/wrong.raw' }
	mut args := [qemu, '-machine', 'q35,smm=off', '-accel', 'tcg', '-cpu', 'max', '-m', '1024', '-smp', '2',
		'-drive', 'if=pflash,format=raw,unit=0,readonly=on,file=' + firmware,
		'-cdrom', work + '/test.iso', '-drive', 'if=ide,format=raw,cache=writeback,file=' + first_disk,
		'-drive', 'if=ide,format=raw,cache=writeback,file=' + second_disk,
		'-drive', 'if=ide,format=raw,cache=writeback,file=' + work + '/config.ext2',
		'-display', 'none', '-monitor', 'none', '-serial', 'stdio', '-nic', 'none', '-no-reboot']
	if nvme {
		args << ['-drive','if=none,format=raw,id=nvme-health,file=' + work + '/nvme.raw',
			'-device','nvme,drive=nvme-health,serial=VINIXHEALTH',
			'-drive','if=none,format=raw,id=nvme-warning,file=' + work + '/nvme-warning.raw',
			'-device','nvme,drive=nvme-warning,serial=VINIXWARNING,smart_critical_warning=8']
	}
	return args
}

fn arm_boot(root string, work string, kernel string, second bool) ![]string {
	boot_image := work + '/boot.img'
	if !os.exists(boot_image) {
		mut file := os.create(boot_image)!
		file.seek(64 * 1024 * 1024 - 1, .start)!; file.write([u8(0)])!; file.close()
		command(['mformat', '-F', '-i', boot_image, '::'])!
		for directory in ['::/EFI', '::/EFI/BOOT', '::/boot'] { command(['mmd', '-i', boot_image, directory])! }
		command(['mcopy', '-i', boot_image, root + '/boot-image/limine-bin/BOOTAA64.EFI', '::/EFI/BOOT/BOOTAA64.EFI'])!
	}
	os.write_file(work + '/limine.conf', os.read_file(root + '/build-support/limine.conf')! + '\n    cmdline: vinix.qemu_platform=1 vinix.qemu_persist=1 vinix.qemu_root=1\n')!
	for pair in [[kernel, '::/boot/vinix'], [work + '/initramfs.tar', '::/boot/initramfs.tar'], [work + '/limine.conf', '::/boot/limine.conf']] {
		command(['mcopy', '-o', '-i', boot_image, pair[0], pair[1]])!
	}
	qemu := os.find_abs_path_of_executable('qemu-system-aarch64')!
	share := os.dir(os.dir(os.real_path(qemu))) + '/share/qemu'
	os.cp(share + '/edk2-arm-vars.fd', work + '/vars.fd')!
	firmware := os.getenv_opt('VINIX_OVMF_CODE') or { root + '/boot-image/edk2-aarch64-code-2048x1536.fd' }
	first_disk := work + if second { '/wrong.raw' } else { '/volume.raw' }
	second_disk := work + if second { '/volume.raw' } else { '/wrong.raw' }
	return [qemu, '-machine', 'virt,gic-version=3', '-accel', if os.user_os() == 'macos' { 'hvf' } else { 'tcg' },
		'-cpu', if os.user_os() == 'macos' { 'host' } else { 'max' }, '-m', '1024', '-smp', '2',
		'-drive', 'if=pflash,format=raw,readonly=on,file=' + firmware,
		'-drive', 'if=pflash,format=raw,file=' + work + '/vars.fd', '-drive', 'format=raw,file=' + boot_image,
		'-drive', 'if=none,format=raw,id=config,file=' + work + '/config.ext2', '-device', 'virtio-blk-device,drive=config',
		'-drive', 'if=none,format=raw,id=wrong,file=' + second_disk, '-device', 'virtio-blk-device,drive=wrong',
		'-drive', 'if=none,format=raw,id=plan,file=' + first_disk, '-device', 'virtio-blk-device,drive=plan',
		'-device', 'virtio-keyboard-device', '-device', 'ramfb', '-display', 'none', '-monitor', 'none',
		'-serial', 'stdio', '-nic', 'none', '-no-reboot']
}

fn boot(args []string, log string) !string {
	mut capture := os.create(log)!
	defer { capture.close() }
	mut process := os.new_process(args[0])
	process.set_args(args[1..]); process.set_redirect_stdio(); process.run()
	if process.pid <= 0 { return error('Cannot start QEMU') }
	defer {
		if process.is_alive() { unsafe { C.kill(i32(process.pid), 9) }; process.wait() }
		process.close()
	}
	mut markers := bootcapture.Capture{}
	started := time.sys_mono_now()
	for process.is_alive() && time.sys_mono_now() - started < u64(1800 * time.second) {
		stdout := process.stdout_read()
		if stdout != '' { capture.write_string(stdout)!; markers.observe(stdout) }
		unsafe { stdout.free() }
		stderr := process.stderr_read()
		if stderr != '' { capture.write_string(stderr)!; markers.observe(stderr) }
		unsafe { stderr.free() }
		if markers.done { break }
		if markers.failed {
			// Let the kernel finish its diagnostic before terminating QEMU.
			time.sleep(time.second)
			break
		}
		time.sleep(10 * time.millisecond)
	}
	stdout := process.stdout_read()
	capture.write_string(stdout)!
	markers.observe(stdout)
	unsafe { stdout.free() }
	stderr := process.stderr_read()
	capture.write_string(stderr)!
	markers.observe(stderr)
	unsafe { stderr.free() }
	capture.flush()
	transcript := os.read_file(log)!
	if !transcript.contains('PLAN DONE') || markers.failed {
		return error('Guest qualification failed: see ${log}')
	}
	return transcript
}

fn guest(root string, work string, arch string, kernel string, nvme bool) ! {
	if kernel == '' || !os.is_file(kernel) { return error('Select an existing kernel with --kernel') }
	if work.contains(',') { return error('Work directory cannot contain QEMU option separators') }
	compile_guest(root, work, arch, nvme)!
	if nvme {
		nvme_disk(work + '/nvme.raw',0x81)!
		nvme_disk(work + '/nvme-warning.raw',0x82)!
	}
	write_disk(work + '/volume.raw', false)!
	write_disk(work + '/wrong.raw', true)!
	plan_filesystem(work)!
	pack(work)!
	args := if arch == 'aarch64' { arm_boot(root, work, kernel, false)! } else { amd64_boot(root, work, kernel, false, nvme)! }
	first := boot(args, work + '/first-boot.log')!
	if !first.contains('init: volume restore failed; continuing') { return error('Production init did not report its invalid boot plan and continue') }
	if !first.contains('PLAN SET PREFLIGHT PASSED') { return error('Missing multi-disk plan-set qualification') }
	if !first.contains('PLAN BUNDLE PASSED:') { return error('Missing atomic multi-disk bundle qualification') }
	if !first.contains('PLAN GROWTH PASSED:') { return error('Missing planned capacity growth qualification') }
	if !first.contains('PLAN CHECK PASSED:') { return error('Missing read-only bundle check qualification') }
	if !first.contains('PLAN EDIT PASSED:') { return error('Missing offline mapping edit qualification') }
	if !first.contains('PLAN DISKS PASSED:') { return error('Missing offline disk membership qualification') }
	if !first.contains('PLAN SPACE PASSED:') { return error('Missing bounded extent allocation qualification') }
	if !first.contains('PLAN POOLS PASSED:') { return error('Missing persistent allocation pool qualification') }
	if !first.contains('PLAN POOL GROWTH PASSED:') { return error('Missing pool expansion and bounded growth qualification') }
	if !first.contains('PLAN POOL BATCH PASSED:') { return error('Missing atomic pool batch qualification') }
	if !first.contains('PLAN POOL GROWTH BATCH PASSED:') { return error('Missing atomic pool growth batch qualification') }
	if !first.contains('PLAN POOL EXPANSION BATCH PASSED:') { return error('Missing atomic pool expansion batch qualification') }
	if !first.contains('PLAN CAPACITY BATCH PASSED:') { return error('Missing atomic physical capacity batch qualification') }
	if !first.contains('PLAN POOL MEMBERSHIP BATCH PASSED:') { return error('Missing atomic pool membership batch qualification') }
	if !first.contains('PLAN POOL PRIORITY PASSED:') { return error('Missing pool allocation priority qualification') }
	if !first.contains('PLAN REMOVAL BATCH PASSED:') { return error('Missing atomic mapping removal batch qualification') }
	if !first.contains('PLAN ENROLLMENT BATCH PASSED:') { return error('Missing atomic disk enrollment batch qualification') }
	if !first.contains('PLAN FORGET BATCH PASSED:') { return error('Missing atomic identity disk forget qualification') }
	if !first.contains('PLAN ADDITION BATCH PASSED:') { return error('Missing atomic explicit mapping addition qualification') }
	if !first.contains('PLAN EXPLICIT GROWTH BATCH PASSED:') { return error('Missing atomic explicit mapping growth qualification') }
	if !first.contains('PLAN POOL CONTRACTION BATCH PASSED:') { return error('Missing atomic pool contraction qualification') }
	if !first.contains('PLAN POOL RESIZE BATCH PASSED:') { return error('Missing atomic cross-pool resize qualification') }
	if !first.contains('PLAN CAPACITY CONTRACTION BATCH PASSED:') { return error('Missing identity-based physical contraction qualification') }
	if !first.contains('PLAN MULTI POOL BATCH PASSED:') { return error('Missing atomic multi-pool allocation qualification') }
	if !first.contains('PLAN MULTI POOL GROWTH PASSED:') { return error('Missing atomic multi-pool growth qualification') }
	if !first.contains('PLAN LOCK PASSED:') { return error('Missing saved-plan locking qualification') }
	if !first.contains('PLAN DATA PASSED:') { return error('Missing data checksum and corruption qualification') }
	if !first.contains('HEALTH QUERY PASSED') { return error('Missing physical health ABI qualification') }
	if !first.contains('STORAGE MONITOR PASSED:') { return error('Missing periodic storage monitor qualification') }
	if nvme && !first.contains('NVME HEALTH PASSED') { return error('Missing NVMe health ABI qualification') }
	if nvme && !first.contains('NVME MONITOR PASSED:') { return error('Missing NVMe monitor qualification') }
	mut encoded := ''
	for line in first.split_into_lines() { if line.starts_with('PLAN FILE ') { encoded = line.all_after('PLAN FILE ').trim_space() } }
	if encoded.len < 256 || encoded.len > 4224 { return error('Missing saved plan bytes in first boot') }
	os.write_file_array(work + '/saved-plan.vmap', hex.decode(encoded)!)!
	// The phase marker and plan stay on the guest's filesystem. No host copy
	// supplies either file to the second boot.
	second_args := if arch == 'aarch64' { arm_boot(root, work, kernel, true)! } else { amd64_boot(root, work, kernel, true, nvme)! }
	second := boot(second_args, work + '/second-boot.log')!
	if !second.contains('PLAN BOOT RESTORED') { return error('Production init did not restore before the application started') }
	if !second.contains('PLAN POOL BOOT PRESERVED') { return error('Pool configuration did not survive reordered boot') }
	if !second.contains('PLAN DATA BOOT VERIFIED') { return error('Data manifest did not verify across reordered boot') }
	// Enlarge the existing disposable backing file without changing its MBR or
	// prior bytes. The saved bundle and all guest files remain guest-produced.
	mut disk := os.open_file(work + '/volume.raw', 'r+')!
	disk.seek(24 * 1024 * 1024 - 1, .start)!
	disk.write([u8(0)])!
	disk.close()
	third := boot(second_args, work + '/capacity-boot.log')!
	if !third.contains('init: volume restore failed; continuing') || !third.contains('PLAN CAPACITY PASSED:') {
		return error('Missing rejection of old geometry or explicit physical capacity adoption')
	}
	fourth := boot(second_args, work + '/capacity-restored-boot.log')!
	if !fourth.contains('PLAN CAPACITY BOOT RESTORED:') || fourth.contains('init: volume restore failed; continuing') {
		return error('Production init did not restore the adopted physical capacity')
	}
	if !fourth.contains('PLAN POOL BOOT PRESERVED') { return error('Pool configuration did not survive capacity adoption and boot') }
	if !fourth.contains('PLAN POOL GROWTH BOOT PRESERVED') { return error('Expanded tail pool did not survive boot') }
	if !fourth.contains('PLAN POOL BATCH BOOT PRESERVED') { return error('Mixed batch tail mapping did not survive boot') }
	if !fourth.contains('PLAN POOL GROWTH BATCH BOOT PRESERVED') { return error('Growth batch tail mapping did not survive boot') }
	if !fourth.contains('PLAN POOL EXPANSION BATCH BOOT PRESERVED') { return error('Expansion batch tail region did not survive boot') }
	if !fourth.contains('PLAN CAPACITY BATCH BOOT PRESERVED') { return error('Capacity batch geometry did not survive boot') }
	if !fourth.contains('PLAN POOL MEMBERSHIP BATCH BOOT PRESERVED') { return error('Membership batch priority and desired state did not survive boot') }
	if !fourth.contains('PLAN POOL PRIORITY BOOT PRESERVED') { return error('Pool allocation priority did not survive boot') }
	if !third.contains('PLAN REMOVAL BATCH SAVED:') || !fourth.contains('PLAN REMOVAL BATCH BOOT PRESERVED') { return error('Desired mapping removals did not survive boot') }
	if !third.contains('PLAN ENROLLMENT BATCH SAVED:') || !fourth.contains('PLAN ENROLLMENT BATCH BOOT PRESERVED') { return error('Disk enrollment batch did not survive boot') }
	if !third.contains('PLAN FORGET BATCH SAVED:') || !fourth.contains('PLAN FORGET BATCH BOOT PRESERVED') { return error('Disk forget compaction did not survive boot') }
	if !third.contains('PLAN ADDITION BATCH SAVED:') || !fourth.contains('PLAN ADDITION BATCH BOOT PRESERVED') { return error('Explicit mapping additions did not survive boot') }
	if !third.contains('PLAN EXPLICIT GROWTH BATCH SAVED:') || !fourth.contains('PLAN EXPLICIT GROWTH BATCH BOOT PRESERVED') { return error('Explicit mapping growth did not survive boot') }
	if !third.contains('PLAN POOL CONTRACTION BATCH SAVED:') || !fourth.contains('PLAN POOL CONTRACTION BATCH BOOT PRESERVED') { return error('Pool contraction did not survive boot') }
	if !third.contains('PLAN POOL RESIZE BATCH SAVED:') || !fourth.contains('PLAN POOL RESIZE BATCH BOOT PRESERVED') { return error('Cross-pool resize did not survive boot') }
	if !fourth.contains('PLAN CAPACITY CONTRACTION PREPARED:') { return error('Missing bounded contraction candidate') }
	// Preserve the completed growth qualification before shrinking only the
	// disposable physical backing. Guest plans stay on their own filesystem.
	os.cp(work + '/config.ext2', work + '/expanded-config.ext2')!
	os.cp(work + '/volume.raw', work + '/volume-grown.raw')!
	shrink_disk(work + '/volume.raw', 20 * 1024 * 1024)!
	fifth := boot(second_args, work + '/capacity-contracted-boot.log')!
	if !fifth.contains('init: volume restore failed; continuing') || !fifth.contains('PLAN CAPACITY CONTRACTION SAVED:') {
		return error('Missing old-geometry rejection or verified physical contraction')
	}
	sixth := boot(second_args, work + '/capacity-contract-restored-boot.log')!
	if sixth.contains('init: volume restore failed; continuing') || !sixth.contains('PLAN CAPACITY CONTRACT BOOT RESTORED:')
		|| !sixth.contains('PLAN CAPACITY CONTRACTION BOOT PRESERVED') {
		return error('Production init did not restore contracted geometry and preserved mappings')
	}
	if !sixth.contains('PLAN MULTI POOL BATCH SAVED:') { return error('Missing persistent multi-pool placements') }
	// Retain the completed six-boot evidence before new rows become the boot plan.
	os.cp(work + '/config.ext2', work + '/contracted-config.ext2')!
	seventh := boot(second_args, work + '/multi-pool-restored-boot.log')!
	if seventh.contains('init: volume restore failed; continuing') || !seventh.contains('PLAN MULTI POOL BATCH BOOT PRESERVED') {
		return error('Production init did not restore the complete multi-pool allocation')
	}
	if !seventh.contains('PLAN MULTI POOL GROWTH SAVED:') { return error('Missing persistent multi-pool growth') }
	os.cp(work + '/config.ext2', work + '/multi-pool-config.ext2')!
	eighth := boot(second_args, work + '/multi-growth-restored-boot.log')!
	if eighth.contains('init: volume restore failed; continuing') || !eighth.contains('PLAN MULTI POOL GROWTH BOOT PRESERVED') {
		return error('Production init did not restore complete multi-pool growth')
	}
	if !eighth.contains('PLAN DATA SAVED:') { return error('Missing persisted nine-mapping checksum manifest') }
	os.cp(work + '/config.ext2', work + '/data-config.ext2')!
	ninth := boot(second_args, work + '/data-restored-boot.log')!
	if ninth.contains('init: volume restore failed; continuing') || !ninth.contains('PLAN DATA BOOT PRESERVED') { return error('Data checksum verification failed after production boot') }
	println('PASS ${arch}: SHA-256 data manifests, atomic multi-pool allocation/growth, physical capacity/pool batches, previews/retries, saved-plan locks, complete preflight, nine-boot persistence and 200-cycle retention')
}

fn main() {
	mut options := map[string]string{}
	mut is_host := false
	mut nvme := false
	mut index := 1
	for index < os.args.len {
		name := os.args[index]
		if name == '--host' { is_host = true; index++; continue }
		if name == '--nvme' { nvme = true; index++; continue }
		if name !in ['--arch', '--work', '--kernel'] || index + 1 >= os.args.len || name in options {
			eprintln('Usage: plan_run.v --work NEW_DIRECTORY [--host | --arch amd64|aarch64 --kernel KERNEL [--nvme]]'); exit(2)
		}
		options[name] = os.args[index + 1]; index += 2
	}
	work := os.abs_path(options['--work'])
	if options['--work'] == '' || os.exists(work) || (!is_host && options['--arch'] !in ['amd64', 'aarch64'])
		|| (nvme && (is_host || options['--arch'] != 'amd64')) {
		eprintln('Select a new private work directory and supported architecture'); exit(2)
	}
	os.mkdir(work) or { eprintln(err); exit(1) }
	root := os.dir(os.dir(os.dir(@FILE)))
	if is_host { host(root, work) or { eprintln(err); exit(1) } }
	else { guest(root, work, options['--arch'], os.real_path(options['--kernel']), nvme) or { eprintln(err); exit(1) } }
}

// SPDX-License-Identifier: GPL-2.0-or-later
// Native V qualification controller. QEMU runs directly; no Python transport.
module main

import os
import time
import encoding.hex

#include <signal.h>
fn C.kill(i32, i32) i32

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
	binary := work + '/plan-host'
	command([v, '-enable-globals', '-cc', 'clang', '-d', 'volume_library', '-cflags',
		'-I' + root + '/tools/volumes/volumecli -fsanitize=address,undefined', '-ldflags',
		'-fsanitize=address,undefined', '-o', binary, root + '/tools/volumes/volumecli/plan_test.v'])!
	os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true)
	print(command([binary])!)
	generate(root, root + '/tools/volumes/volumecli', work + '/volume.c', 'x86_64')!
	check_generated(work + '/volume.c')!
	init_policy(root, work)!
	println('PASS host: plan format, identity, corruption, bounds, atomic publication and sanitizers')
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

fn compile_guest(root string, work string, arch string) ! {
	source := work + '/guest.c'
	generate(root, root + '/tests/storage-volumes/planguest', source, arch)!
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

fn amd64_boot(root string, work string, kernel string, second bool) ![]string {
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
	return [qemu, '-machine', 'q35,smm=off', '-accel', 'tcg', '-cpu', 'max', '-m', '1024', '-smp', '2',
		'-drive', 'if=pflash,format=raw,unit=0,readonly=on,file=' + firmware,
		'-cdrom', work + '/test.iso', '-drive', 'if=ide,format=raw,cache=writeback,file=' + first_disk,
		'-drive', 'if=ide,format=raw,cache=writeback,file=' + second_disk,
		'-drive', 'if=ide,format=raw,cache=writeback,file=' + work + '/config.ext2',
		'-display', 'none', '-monitor', 'none', '-serial', 'stdio', '-nic', 'none', '-no-reboot']
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
	mut transcript := ''
	started := time.sys_mono_now()
	for process.is_alive() && time.sys_mono_now() - started < u64(600 * time.second) {
		chunk := process.stdout_read() + process.stderr_read()
		if chunk != '' { capture.write_string(chunk)!; transcript += chunk }
		if transcript.contains('PLAN DONE\n') || transcript.contains('PLAN DONE\r') { break }
		if transcript.contains('PLAN FAIL') || transcript.contains('KERNEL PANIC') || transcript.contains('FATAL EXCEPTION') { break }
		time.sleep(10 * time.millisecond)
	}
	last := process.stdout_read() + process.stderr_read()
	capture.write_string(last)!
	transcript += last
	if !transcript.contains('PLAN DONE') || transcript.contains('PLAN FAIL') || transcript.contains('KERNEL PANIC') {
		return error('Guest qualification failed: see ${log}')
	}
	return transcript
}

fn guest(root string, work string, arch string, kernel string) ! {
	if kernel == '' || !os.is_file(kernel) { return error('Select an existing kernel with --kernel') }
	if work.contains(',') { return error('Work directory cannot contain QEMU option separators') }
	compile_guest(root, work, arch)!
	write_disk(work + '/volume.raw', false)!
	write_disk(work + '/wrong.raw', true)!
	plan_filesystem(work)!
	pack(work)!
	args := if arch == 'aarch64' { arm_boot(root, work, kernel, false)! } else { amd64_boot(root, work, kernel, false)! }
	first := boot(args, work + '/first-boot.log')!
	if !first.contains('init: volume restore failed; continuing') { return error('Production init did not report its invalid boot plan and continue') }
	mut encoded := ''
	for line in first.split_into_lines() { if line.starts_with('PLAN FILE ') { encoded = line.all_after('PLAN FILE ').trim_space() } }
	if encoded.len < 256 || encoded.len > 4224 { return error('Missing saved plan bytes in first boot') }
	os.write_file_array(work + '/saved-plan.vmap', hex.decode(encoded)!)!
	// The phase marker and plan stay on the guest's filesystem. No host copy
	// supplies either file to the second boot.
	second_args := if arch == 'aarch64' { arm_boot(root, work, kernel, true)! } else { amd64_boot(root, work, kernel, true)! }
	second := boot(second_args, work + '/second-boot.log')!
	if !second.contains('PLAN BOOT RESTORED') { return error('Production init did not restore before the application started') }
	println('PASS ${arch}: discovery, ambiguity and trust rejection, production init restore after device reorder, 200-cycle retention and reboot data')
}

fn main() {
	mut options := map[string]string{}
	mut is_host := false
	mut index := 1
	for index < os.args.len {
		name := os.args[index]
		if name == '--host' { is_host = true; index++; continue }
		if name !in ['--arch', '--work', '--kernel'] || index + 1 >= os.args.len || name in options {
			eprintln('Usage: plan_run.v --work NEW_DIRECTORY [--host | --arch amd64|aarch64 --kernel KERNEL]'); exit(2)
		}
		options[name] = os.args[index + 1]; index += 2
	}
	work := os.abs_path(options['--work'])
	if options['--work'] == '' || os.exists(work) || (!is_host && options['--arch'] !in ['amd64', 'aarch64']) {
		eprintln('Select a new private work directory and supported architecture'); exit(2)
	}
	os.mkdir(work) or { eprintln(err); exit(1) }
	root := os.dir(os.dir(os.dir(@FILE)))
	if is_host { host(root, work) or { eprintln(err); exit(1) } }
	else { guest(root, work, options['--arch'], os.real_path(options['--kernel'])) or { eprintln(err); exit(1) } }
}

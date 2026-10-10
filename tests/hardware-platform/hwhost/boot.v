// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// What a scenario boots: the guest program, the initramfs it is the only
// program in, and the medium the firmware loads the kernel from.
//
// The kernel is an input and is never built here. Everything else is made
// from scratch for each boot and is small: a static binary, a tar archive of
// it, and a FAT image (AArch64) or an ISO (x86-64) holding Limine, the kernel
// and that archive.
module hwhost

import os

const tool_seconds = 300

// The guest is one V program for every scenario, compiled once per run. V
// writes C, and the musl cross compiler of the architecture links it
// statically: the initramfs has no libraries and no other files.
pub fn build_guest(host Host, directory string) !string {
	os.mkdir_all(directory)!
	source := os.join_path(host.root, 'tests', 'hardware-platform', 'guest')
	c_file := os.join_path(directory, 'init.c')
	binary := os.join_path(directory, 'init')
	log := os.join_path(directory, 'build.log')
	v_arch := if host.arch == 'aarch64' { 'arm64' } else { 'amd64' }
	// No collector and no backtraces: PID 1 of a test kernel should need as
	// little of that kernel as it can, and what it allocates dies with it.
	run_tool([host.v, '-os', 'linux', '-arch', v_arch, '-gc', 'none', '-d', 'no_backtrace', '-o',
		c_file, source], map[string]string{}, log, tool_seconds)!
	if host.arch == 'aarch64' {
		sysroot := environment_or('VINIX_AARCH64_SYSROOT', shared_path(host.root, os.join_path('build-aarch64-userland',
			'sysroot')))
		if !os.is_dir(sysroot) {
			return error('no AArch64 musl sysroot at ${sysroot}; set VINIX_AARCH64_SYSROOT')
		}
		run_tool([environment_or('CC_AARCH64', 'clang'), '--target=aarch64-linux-musl',
			'--sysroot=' + sysroot, '-static', '-O1', '-w', '-fno-stack-protector',
			'-L' + os.join_path(sysroot, 'lib'), '-fuse-ld=lld', '-o', binary, c_file, '-lm',
			'-lpthread'], map[string]string{}, log, tool_seconds)!
	} else {
		run_tool([environment_or('CC_AMD64', 'x86_64-linux-musl-gcc'), '-static', '-O1', '-w',
			'-o', binary, c_file, '-lm', '-lpthread'], map[string]string{}, log, tool_seconds)!
	}
	return binary
}

// The root file system: the guest as /sbin/init, the name of the scenario it
// is to run, and the empty directories the kernel mounts things on.
pub fn build_initramfs(guest string, scenario string, state string) !string {
	rootfs := os.join_path(state, 'rootfs')
	for directory in ['sbin', 'etc', 'dev', 'proc', 'sys', 'tmp', 'root'] {
		os.mkdir_all(os.join_path(rootfs, directory))!
	}
	init := os.join_path(rootfs, 'sbin', 'init')
	os.cp(guest, init)!
	os.chmod(init, 0o755)!
	os.write_file(os.join_path(rootfs, 'etc', 'hwtest-scenario'), scenario + '\n')!
	archive := os.join_path(state, 'initramfs.tar')
	// The kernel unpacks plain USTAR. COPYFILE_DISABLE keeps macOS tar from
	// adding a ._ file of extended attributes beside each real one.
	run_tool(['tar', '--format=ustar', '-cf', archive, '-C', rootfs, '.'], {
		'COPYFILE_DISABLE': '1'
	}, os.join_path(state, 'image.log'), tool_seconds)!
	return archive
}

// An AArch64 machine boots from a FAT volume: the firmware runs Limine from
// the removable-media path, and Limine reads its configuration, the kernel
// and the initramfs from the same volume. Returns the QEMU arguments that
// attach the firmware and the volume.
fn boot_media_aarch64(host Host, kernel string, initramfs string, cmdline string, state string) ![]string {
	loader := environment_or('VINIX_LIMINE_BOOTAA64', shared_path(host.root, os.join_path('boot-image',
		'limine-bin', 'BOOTAA64.EFI')))
	if !os.is_file(loader) {
		return error('no Limine for AArch64 at ${loader}; set VINIX_LIMINE_BOOTAA64')
	}
	base := os.read_file(os.join_path(host.root, 'build-support', 'limine.conf'))!
	// vinix.qemu_platform=1 tells the kernel there is no device tree to find
	// Apple hardware in. The entry is the file's last, so its options go at
	// the end.
	config := os.join_path(state, 'limine.conf')
	os.write_file(config, base.trim_right('\n') +
		'\n    cmdline: ${('vinix.qemu_platform=1 ' + cmdline).trim_space()}\n')!
	image := os.join_path(state, 'boot.img')
	os.write_file(image, '')!
	os.truncate(image, u64(64) << 20)!
	log := os.join_path(state, 'image.log')
	run_tool(['mformat', '-F', '-i', image, '::'], map[string]string{}, log, tool_seconds)!
	run_tool(['mmd', '-i', image, '::/EFI', '::/EFI/BOOT', '::/boot'], map[string]string{}, log, tool_seconds)!
	for pair in [[loader, '::/EFI/BOOT/BOOTAA64.EFI'], [config, '::/boot/limine.conf'],
		[kernel, '::/boot/vinix'], [initramfs, '::/boot/initramfs.tar']] {
		run_tool(['mcopy', '-i', image, pair[0], pair[1]], map[string]string{}, log, tool_seconds)!
	}
	// The firmware writes its variables: each boot gets its own copy, so one
	// boot's leftovers are not the next one's boot order.
	variables := os.join_path(state, 'vars.fd')
	os.cp(host.firmware_vars, variables)!
	return ['-drive', 'if=pflash,format=raw,readonly=on,file=' + host.firmware, '-drive',
		'if=pflash,format=raw,file=' + variables, '-drive', 'format=raw,file=' + image]
}

// An x86-64 machine boots from the same ISO a release is: the repository's
// script assembles it around the kernel and initramfs it is given. Limine's
// own files are downloaded once into the checkout's ISO build directory and
// shared from there, so a boot needs no network.
fn boot_media_x86_64(host Host, kernel string, initramfs string, cmdline string, state string) ![]string {
	build := os.join_path(state, 'iso')
	os.mkdir_all(build)!
	cache := environment_or('VINIX_AMD64_LIMINE_DIR', shared_path(host.root, os.join_path('build-amd64-iso',
		'limine')))
	os.mkdir_all(cache)!
	os.symlink(cache, os.join_path(build, 'limine'))!
	iso := os.join_path(state, 'test.iso')
	run_tool([os.join_path(host.root, 'build-support', 'build-amd64-iso.sh')], {
		'VINIX_AMD64_KERNEL':        kernel
		'VINIX_AMD64_INITRAMFS':     initramfs
		'VINIX_AMD64_ISO':           iso
		'VINIX_AMD64_ISO_BUILD_DIR': build
		'VINIX_CMDLINE':             cmdline
	}, os.join_path(state, 'image.log'), tool_seconds)!
	return ['-drive', 'if=pflash,format=raw,unit=0,readonly=on,file=' + host.firmware, '-cdrom',
		iso]
}

pub fn boot_media(host Host, kernel string, initramfs string, cmdline string, state string) ![]string {
	if host.arch == 'aarch64' {
		return boot_media_aarch64(host, kernel, initramfs, cmdline, state)
	}
	return boot_media_x86_64(host, kernel, initramfs, cmdline, state)
}

// A raw disk of the given size: a hole, apart from what its header says.
//
// The size is set first and the header written into it. os.truncate() empties
// the file before it sizes it, so the other order leaves a blank disk -- the
// one kind the kernel's installer takes for its own.
pub fn create_disk(disk Disk, state string) ! {
	path := os.join_path(state, disk.name)
	os.write_file(path, '')!
	os.truncate(path, u64(disk.size_mib) << 20)!
	if disk.header == '' {
		return
	}
	mut file := os.open_file(path, 'r+')!
	defer {
		file.close()
	}
	file.write_to(0, disk.header.bytes())!
}

// Whether a disk still starts with what it was created with. A disk that
// does not was formatted or installed onto while the machine ran, and
// whatever the scenario then measured, it was not the disk it asked for.
pub fn check_disk_header(disk Disk, state string) ! {
	if disk.header == '' {
		return
	}
	mut file := os.open(os.join_path(state, disk.name)) or {
		return error('cannot read ${disk.name}: ${err.msg()}')
	}
	defer {
		file.close()
	}
	mut found := []u8{len: disk.header.len}
	count := file.read_from(0, mut found) or { 0 }
	if count != disk.header.len || found.bytestr() != disk.header {
		return error('${disk.name} no longer starts with "${disk.header}": the machine overwrote the start of the disk')
	}
}

// The bytes a guest writes for a pattern; guest/support.v has the same.
pub fn pattern_bytes(seed u8, length int) []u8 {
	mut bytes := []u8{len: length}
	for i in 0 .. length {
		bytes[i] = u8(int(seed) + i * 7)
	}
	return bytes
}

// Whether the guest's pattern reached the disk file. Run after QEMU has
// exited, which is when it has written out what the guest synced.
pub fn check_pattern(pattern DiskPattern, state string) ! {
	path := os.join_path(state, pattern.disk)
	mut file := os.open(path) or { return error('cannot read ${pattern.disk}: ${err.msg()}') }
	defer {
		file.close()
	}
	mut found := []u8{len: pattern.length}
	count := file.read_from(pattern.offset, mut found) or { 0 }
	place := '${pattern.disk} at offset ${pattern.offset}'
	if count != pattern.length {
		return error('${place}: read ${count} of ${pattern.length} bytes')
	}
	expected := pattern_bytes(pattern.seed, pattern.length)
	for i in 0 .. pattern.length {
		if found[i] != expected[i] {
			return error('${place}: byte ${i} is 0x${found[i].hex()}, the guest was to write 0x${expected[i].hex()}')
		}
	}
}

// The files of a state directory that are worth their size only while the
// machine runs. The logs stay.
pub fn remove_images(scenario Scenario, state string) {
	for name in ['rootfs', 'iso'] {
		remove_tree(os.join_path(state, name))
	}
	mut files := ['initramfs.tar', 'boot.img', 'vars.fd', 'test.iso', 'limine.conf', 'qmp.sock']
	files << scenario.disks.map(it.name)
	for name in files {
		os.rm(os.join_path(state, name)) or {}
	}
}

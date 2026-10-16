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
// statically: the initramfs has no libraries. `source` is a V file or a
// directory of them, built into `directory`/`name`; a suite's other
// programs are built the same way.
pub fn build_program(host Host, source string, directory string, name string, module_paths []string) !string {
	return build_program_with_flags(host, source, directory, name, module_paths, [])
}

fn build_program_with_flags(host Host, source string, directory string, name string, module_paths []string, flags []string) !string {
	os.mkdir_all(directory)!
	c_file := os.join_path(directory, name + '.c')
	binary := os.join_path(directory, name)
	log := os.join_path(directory, 'build.log')
	v_arch := if host.arch == 'aarch64' { 'arm64' } else { 'amd64' }
	// No collector and no backtraces: PID 1 of a test kernel should need as
	// little of that kernel as it can, and what it allocates dies with it.
	// Keep native C signal-handler glue out of these plain static fixtures too.
	mut compile := [host.v, '-os', 'linux', '-arch', v_arch, '-gc', 'none', '-d', 'no_backtrace',
		'-d', 'no_segfault_handler']
	compile << flags
	if module_paths.len > 0 {
		// Modules a suite's programs share with the tools they test.
		mut lookup := ['@vlib', '@vmodules']
		for path in module_paths {
			lookup << os.join_path(host.root, path)
		}
		compile << ['-path', lookup.join('|')]
	}
	compile << ['-o', c_file, source]
	run_tool(compile, map[string]string{}, log, tool_seconds)!
	if host.arch == 'aarch64' {
		sysroot := environment_or('VINIX_AARCH64_SYSROOT', shared_path(host.root, os.join_path('build-aarch64-userland',
			'sysroot')))
		if !os.is_dir(sysroot) {
			return error('no AArch64 musl sysroot at ${sysroot}; set VINIX_AARCH64_SYSROOT')
		}
		run_tool([environment_or('CC_AARCH64', 'clang'), '--target=aarch64-linux-musl',
			'--sysroot=' + sysroot, '-static', '-O1', '-w', '-D_GNU_SOURCE', '-fno-stack-protector',
			'-L' + os.join_path(sysroot, 'lib'), '-fuse-ld=lld', '-o', binary, c_file, '-lm',
			'-lpthread'], map[string]string{}, log, tool_seconds)!
	} else {
		// -fpermissive: V's own library passes an i64 where C wants an int
		// pointer (os.Process and waitpid), which gcc 14 refuses outright and
		// clang, above, only warns about.
		run_tool([environment_or('CC_AMD64', 'x86_64-linux-musl-gcc'), '-static', '-O1', '-w',
			'-fpermissive', '-D_GNU_SOURCE', '-o', binary, c_file, '-lm', '-lpthread'], map[string]string{}, log, tool_seconds)!
	}
	return binary
}

// The root file system: the guest as /sbin/init, the name of the scenario it
// is to run, and the empty directories the kernel mounts things on.
pub fn build_initramfs(guest string, scenario string, state string, extras string) !string {
	rootfs := os.join_path(state, 'rootfs')
	if extras != '' {
		// What the suite adds, first: the directories below are then only
		// made where it did not bring them. cp -p, because the modes are
		// part of what it adds: a /tmp anyone may write, a file only root
		// may read.
		os.mkdir_all(rootfs)!
		run_tool(['cp', '-Rp', extras + '/.', rootfs], map[string]string{}, os.join_path(state,
			'image.log'), tool_seconds)!
	}
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

fn boot_fat_size(files []u64) !u64 {
	mut payload := u64(0)
	for size in files {
		if size >= u64(4) << 30 || payload > (u64(16) << 30) - size {
			return error('boot inputs exceed FAT file/volume size limits')
		}
		payload += size
	}
	// Budget FAT tables, directory/cluster rounding and free space. The old
	// fixed 64 MiB image could not hold a larger catalog plus its kernel.
	required := payload + payload / 8 + (u64(8) << 20)
	mut image := u64(64) << 20
	for image < required { image *= 2 }
	return image
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
	os.truncate(image, boot_fat_size([os.file_size(loader), os.file_size(config), os.file_size(kernel), os.file_size(initramfs)])!)!
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
	// Made once: a scenario that boots again with another command line
	// comes through here again.
	link := os.join_path(build, 'limine')
	if !os.is_link(link) {
		os.symlink(cache, link)!
	}
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
	if disk.image != '' {
		if disk.header != '' || disk.prefill.len != 0 || os.is_link(disk.image)
			|| !os.is_file(disk.image) || os.file_size(disk.image) != u64(disk.size_mib) << 20 {
			return error('prepared disk image must be a regular file of the declared size, without header/prefill: ${disk.image}')
		}
		os.cp(disk.image, path)!
		return
	}
	os.write_file(path, '')!
	os.truncate(path, u64(disk.size_mib) << 20)!
	if disk.header == '' && disk.prefill.len == 0 {
		return
	}
	mut file := os.open_file(path, 'r+')!
	defer {
		file.close()
	}
	for fill in disk.prefill {
		file.write_to(fill.offset, pattern_bytes(fill.seed, fill.length))!
	}
	if disk.header == '' {
		return
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

// What a disk's file holds when the controller has made it, byte for byte.
pub fn disk_contents(disk Disk) []u8 {
	if disk.image != '' { return os.read_bytes(disk.image) or { []u8{} } }
	mut bytes := []u8{len: disk.size_mib << 20}
	for fill in disk.prefill {
		pattern := pattern_bytes(fill.seed, fill.length)
		for i in 0 .. fill.length {
			bytes[int(fill.offset) + i] = pattern[i]
		}
	}
	for i in 0 .. disk.header.len {
		bytes[i] = disk.header[i]
	}
	return bytes
}

// Whether a disk that was to be left alone was: every byte as it was made.
// For a machine that must not have written to any disk at all, which no
// account of the guest's own can show.
pub fn check_disk_untouched(disk Disk, state string) ! {
	if !disk.untouched {
		return
	}
	found := os.read_bytes(os.join_path(state, disk.name)) or {
		return error('cannot read ${disk.name}: ${err.msg()}')
	}
	expected := disk_contents(disk)
	if found.len != expected.len {
		return error('${disk.name} is ${found.len} bytes long, and was made ${expected.len}')
	}
	for i in 0 .. expected.len {
		if found[i] != expected[i] {
			return error('${disk.name} was written to: byte ${i} is 0x${found[i].hex()}, and was 0x${expected[i].hex()} when the machine was started')
		}
	}
}

// Overwrite part of a disk's file, the machine being off.
pub fn apply_damage(damage DiskDamage, state string) ! {
	mut file := os.open_file(os.join_path(state, damage.disk), 'r+') or {
		return error('cannot damage ${damage.disk}: ${err.msg()}')
	}
	defer {
		file.close()
	}
	file.write_to(damage.offset, []u8{len: damage.length, init: damage.fill})!
}

// Whether a disk's file holds what the scenario says it must at the end.
pub fn check_disk_bytes(wanted DiskBytes, state string) ! {
	mut file := os.open(os.join_path(state, wanted.disk)) or {
		return error('cannot read ${wanted.disk}: ${err.msg()}')
	}
	defer {
		file.close()
	}
	expected := if wanted.text != '' { wanted.text.bytes() } else { []u8{len: wanted.zeros} }
	mut found := []u8{len: expected.len}
	count := file.read_from(wanted.offset, mut found) or { 0 }
	place := '${wanted.disk} at offset ${wanted.offset}'
	if count != expected.len {
		return error('${place}: read ${count} of ${expected.len} bytes')
	}
	for i in 0 .. expected.len {
		if found[i] != expected[i] {
			what := if wanted.text != '' {
				'"${wanted.text}"'
			} else {
				'${wanted.zeros} zero bytes'
			}
			return error('${place}: byte ${i} is 0x${found[i].hex()}; ${what} were to be there')
		}
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
	files << scenario.tables.map(it + '.aml')
	files << scenario.files.map(it.path)
	for name in files {
		os.rm(os.join_path(state, name)) or {}
	}
}

// What the machine wrote into `writing.file` must be exactly its text.
pub fn check_writing(writing Writing, state string) ! {
	path := os.join_path(state, writing.file)
	found := os.read_file(path) or { return error('${path} was not written: ${err.msg()}') }
	if found != writing.text {
		return error('${path} holds "${found}", not "${writing.text}"')
	}
}

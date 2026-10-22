// SPDX-License-Identifier: GPL-2.0-or-later
// UEFI fixture media for frozen kernels which predate gzip initramfs support.
module plainiso

import json2
import os

pub fn source() string { return $embed_file('iso.v').to_string() }

pub fn configuration() string {
	return 'timeout: 0\nverbose: yes\n\n/Vinix\n    protocol: limine\n    kernel_path: boot():/boot/vinix\n    module_path: boot():/boot/initramfs.tar\n    resolution: 1024x768x32\n    kaslr: no\n'
}

pub fn inputs(root string) !map[string]string {
	loader := if os.getenv('VINIX_PLAIN_ISO_LIMINE') != '' {
		os.abs_path(os.getenv('VINIX_PLAIN_ISO_LIMINE'))
	} else { root + '/build-amd64-iso/limine/limine-binary-12.9.3' }
	return {
		'iso-xorriso': os.find_abs_path_of_executable('xorriso')!
		'iso-BOOTX64.EFI': loader + '/BOOTX64.EFI'
		'iso-limine-uefi-cd.bin': loader + '/limine-uefi-cd.bin'
	}
}

// hwhost invokes its root's image builder. Give only that step an isolated
// root and dispatch back into the admitted controller, leaving production
// image scripts and their gzip policy untouched.
pub fn prepare(root string, work string) !string {
	tools := inputs(root)!
	path := work + '/image-builder'
	os.mkdir_all(path + '/build-support')!
	os.symlink(os.executable(), path + '/build-support/build-amd64-iso.sh')!
	os.setenv('VINIX_TEST_PLAIN_ISO', '1', true)
	os.setenv('VINIX_TEST_PLAIN_ISO_XORRISO', tools['iso-xorriso'], true)
	os.setenv('VINIX_TEST_PLAIN_ISO_LOADER', os.dir(tools['iso-BOOTX64.EFI']), true)
	return path
}

pub fn requested() bool {
	return os.getenv('VINIX_TEST_PLAIN_ISO') == '1' && os.getenv('VINIX_AMD64_INITRAMFS') != ''
}

pub fn build() ! {
	build_directory := os.getenv('VINIX_AMD64_ISO_BUILD_DIR')
	output := os.getenv('VINIX_AMD64_ISO')
	loader := os.getenv('VINIX_TEST_PLAIN_ISO_LOADER')
	if build_directory == '' || output == '' || loader == '' { return error('missing plain ISO fixture inputs') }
	staging := build_directory + '/iso-root'
	os.mkdir_all(staging + '/boot')!
	os.mkdir_all(staging + '/EFI/BOOT')!
	os.cp(os.getenv('VINIX_AMD64_KERNEL'), staging + '/boot/vinix')!
	os.cp(os.getenv('VINIX_AMD64_INITRAMFS'), staging + '/boot/initramfs.tar')!
	os.cp(loader + '/BOOTX64.EFI', staging + '/EFI/BOOT/BOOTX64.EFI')!
	os.cp(loader + '/limine-uefi-cd.bin', staging + '/boot/limine-uefi-cd.bin')!
	os.write_file(staging + '/boot/limine.conf', configuration() +
		'    cmdline: vinix.disk=auto ' + os.getenv('VINIX_CMDLINE') + '\n')!
	program := os.getenv('VINIX_TEST_PLAIN_ISO_XORRISO')
	image_arguments := ['-as', 'mkisofs', '-iso-level', '3', '-R', '-r', '-J',
		'--efi-boot', 'boot/limine-uefi-cd.bin', '-efi-boot-part', '--efi-boot-image',
		'--protective-msdos-label', staging, '-o', output]
	mut command := [program]
	command << image_arguments
	os.write_file(os.dir(output) + '/image-commands.json', json2.encode(command))!
	mut child := os.new_process(program)
	defer { child.close() }
	child.set_args(image_arguments)
	child.run()
	child.wait()
	if child.code != 0 { return error('plain fixture ISO assembly failed') }
}

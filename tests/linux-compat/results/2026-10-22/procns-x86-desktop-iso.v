module main
import os

fn main() {
	area := '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022'
	limine := area + '/launch-root/build-amd64-iso/limine'
	iso := os.getenv('VINIX_AMD64_ISO')
	archive := os.getenv('VINIX_AMD64_INITRAMFS')
	kernel := os.getenv('VINIX_AMD64_KERNEL')
	config := area + '/desktop-x86-launch/build-support/limine.conf'
	for path in [kernel, archive, config, limine + '/limine-uefi-cd.bin', limine + '/BOOTX64.EFI'] {
		if !os.is_file(path) { panic('missing ISO input: ' + path) }
	}
	if iso == '' || os.exists(iso) { panic('fresh output ISO required') }
	mut child := os.new_process(os.find_abs_path_of_executable('xorriso')!)
	child.set_args(['-as', 'mkisofs', '-iso-level', '3', '-R', '-r', '-J',
		'--efi-boot', 'boot/limine-uefi-cd.bin', '--efi-boot-part', '--efi-boot-image', '--protective-msdos-label',
		'-graft-points', '/boot/vinix=' + kernel, '/boot/initramfs.tar=' + archive,
		'/boot/limine.conf=' + config, '/boot/limine-uefi-cd.bin=' + limine + '/limine-uefi-cd.bin',
		'/EFI/BOOT/BOOTX64.EFI=' + limine + '/BOOTX64.EFI', '-o', iso])
	child.run()
	child.wait()
	status := child.code
	child.close()
	if status != 0 { exit(status) }
}

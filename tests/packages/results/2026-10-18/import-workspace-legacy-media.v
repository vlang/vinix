// Qualification adapter for the pinned kernel predating gzip initramfs support.
// The production image builder and kernel remain untouched.
module main
import crypto.sha256
import os

fn run(arguments []string) ! {
	println(arguments.join(' '))
	mut child := os.new_process(arguments[0]); child.set_args(arguments[1..]); child.set_redirect_stdio_merged()
	child.run(); output := child.stdout_slurp(); child.wait(); code := child.code; child.close(); print(output)
	if code != 0 { return error('legacy qualification image command failed') }
}

fn build() ! {
	kernel := os.getenv('VINIX_AMD64_KERNEL'); archive := os.getenv('VINIX_AMD64_INITRAMFS')
	output := os.getenv('VINIX_AMD64_ISO'); directory := os.getenv('VINIX_AMD64_ISO_BUILD_DIR')
	assert os.is_file(kernel) && os.is_file(archive) && !os.exists(output)
	assert sha256.sum(os.read_bytes(kernel)!).hex() == 'a989a9b1aff3db4260fe435336d3fba6120450992a96ab0fccbab27c38dce5b1'
	root := directory + '/legacy-plain-ustar'; assert !os.exists(root)
	os.mkdir_all(root + '/boot')!; os.mkdir_all(root + '/EFI/BOOT')!
	os.cp(kernel, root + '/boot/vinix')!; os.cp(archive, root + '/boot/initramfs.tar')!
	assert os.read_bytes(archive)![257..262].bytestr() == 'ustar'
	base := os.read_file(os.getenv('VINIX_WORKSPACE_LEGACY_CONFIG'))!
	assert base.contains('module_path: boot():/boot/initramfs.tar') && !base.contains('initramfs.tar.gz')
	os.write_file(root + '/boot/limine.conf', base.trim_right('\n') + '\n    cmdline: ' + os.getenv('VINIX_CMDLINE') + '\n')!
	loader := os.getenv('VINIX_WORKSPACE_LEGACY_LIMINE'); assert os.is_dir(loader)
	for name in ['limine-uefi-cd.bin', 'limine-bios-cd.bin', 'limine-bios.sys']! { os.cp(loader + '/' + name, root + '/boot/' + name)! }
	os.cp(loader + '/BOOTX64.EFI', root + '/EFI/BOOT/BOOTX64.EFI')!
	println('IMPORT WORKSPACE pinned pre-gzip kernel uses unchanged plain USTAR qualification media')
	run(['xorriso', '-as', 'mkisofs', '-iso-level', '3', '-R', '-r', '-J', '-b', 'boot/limine-bios-cd.bin',
		'-no-emul-boot', '-boot-load-size', '4', '-boot-info-table', '--efi-boot', 'boot/limine-uefi-cd.bin',
		'-efi-boot-part', '--efi-boot-image', '--protective-msdos-label', root, '-o', output])!
	run([loader + '/limine', 'bios-install', output])!
}

fn main() { build() or { eprintln(err); exit(1) } }

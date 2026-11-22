// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import compress.gzip
import disklayout

fn main() {
	if os.args.len != 6 {
		eprintln('usage: boottemplate ISO_ROOT BOOT_EFI LIMINE_TOOL LIMINE_BIOS_SYS CMDLINE')
		exit(2)
	}
	build(os.args[1], os.args[2], os.args[3], os.args[4], os.args[5]) or {
		eprintln('boottemplate: ${err}')
		exit(1)
	}
}

fn build(root string, efi string, limine string, bios_sys string, extra string) ! {
	if extra.contains('\n') || extra.contains('\r') {
		return error('the kernel command line must be a single line')
	}
	stage := os.dir(root)
	disk := os.join_path(stage, 'installer.raw')
	config := os.join_path(stage, 'limine.conf')
	boot := os.join_path(root, 'boot')
	args := if extra == '' { '' } else { ' ${extra}' }
	options := '    protocol: limine\n    kernel_path: boot():/boot/vinix\n    resolution: 1024x768x32\n    kaslr: no\n'
	os.write_file(config, 'timeout: 0\nverbose: yes\n\n/Vinix\n${options}    cmdline: vinix.disk=installed${args}\n')!

	seed_gpt(disk)!
	esp := '${disk}@@${disklayout.esp_start * disklayout.sector_bytes}'
	sectors := disklayout.root_start - disklayout.esp_start
	run(['mformat', '-i', esp, '-F', '-T', sectors.str(), '::'])!
	run(['mmd', '-i', esp, '::/EFI', '::/EFI/BOOT', '::/boot'])!
	run(['mcopy', '-i', esp, efi, '::/EFI/BOOT/${os.file_name(efi)}'])!
	run(['mcopy', '-i', esp, os.join_path(boot, 'vinix'), '::/boot/vinix'])!
	run(['mcopy', '-i', esp, config, '::/limine.conf'])!
	if limine != '' {
		run(['mcopy', '-i', esp, bios_sys, '::/limine-bios.sys'])!
		run([limine, 'bios-install', disk, '1'])!
	}
	// Only the boot regions are consumed by the kernel. The real disk gets
	// its own GPT, with its actual capacity and freshly generated identities.
	boot_bytes := int(disklayout.root_start * disklayout.sector_bytes)
	mut template := os.open(disk)!
	defer { template.close() }
	data := template.read_bytes(boot_bytes)
	if data.len != boot_bytes {
		return error('could not read the disk boot region')
	}
	compressed := gzip.compress(data)!
	os.write_file_array(os.join_path(boot, 'install-disk.gz'), compressed)!

	live := '${options}    module_path: boot():/boot/initramfs.tar.gz\n'
	install := '    module_path: boot():/boot/install-disk.gz\n    module_cmdline: vinix-install-disk\n'
	os.write_file(os.join_path(boot, 'limine.conf'), 'timeout: 8\nserial: yes\nverbose: yes\n\n' +
		'/Try Vinix\n${live}    cmdline: vinix.disk=live${args}\n\n' +
		'/Install Vinix on an empty disk\n${live}${install}    cmdline: vinix.disk=install${args}\n\n' +
		'/Boot or update a legacy Vinix disk\n${live}    cmdline: vinix.disk=legacy${args}\n')!
}

fn run(args []string) ! {
	executable := os.find_abs_path_of_executable(args[0])!
	mut process := os.new_process(executable)
	defer { process.close() }
	process.set_args(args[1..])
	process.run()
	process.wait()
	if process.code != 0 {
		return error('${args[0]} exited with status ${process.code}')
	}
}

fn seed_gpt(path string) ! {
	mut disk := os.create(path)!
	defer { disk.close() }
	sectors := disklayout.min_disk_bytes / disklayout.sector_bytes
	id := disklayout.Identity{
		disk: disklayout.Guid{ low: 1 }
		bios: disklayout.Guid{ low: 2 }
		esp:  disklayout.Guid{ low: 3 }
		root: disklayout.Guid{ low: 4 }
	}
	table := &disklayout.Table{}
	disklayout.entries(table, sectors, id, true)
	mbr := disklayout.protective_mbr(sectors)
	unsafe { disk.write_full_buffer(&mbr[0], uint(disklayout.sector_bytes))! }
	for backup in [false, true]! {
		hdr := disklayout.header(table, sectors, id.disk, backup)
		disk.seek(i64(disklayout.header_lba(sectors, backup) * disklayout.sector_bytes), .start)!
		unsafe { disk.write_full_buffer(&hdr, uint(sizeof(disklayout.Header)))! }
		disk.seek(i64(disklayout.table_lba(sectors, backup) * disklayout.sector_bytes), .start)!
		unsafe { disk.write_full_buffer(table, uint(sizeof(disklayout.Table)))! }
	}
}

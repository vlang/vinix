// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

fn tar_octal(mut block []u8, at int, length int, value u32) {
	mut number := value
	for i := length - 2; i >= 0; i-- {
		block[at + i] = `0` + u8(number & 7)
		number >>= 3
	}
}

fn tar_entry(mut archive []u8, name string, contents []u8, directory bool) {
	mut header := []u8{len: 512}
	copy(mut header[..name.len], name.bytes())
	tar_octal(mut header, 100, 8, if directory { u32(0o755) } else { u32(0o644) })
	tar_octal(mut header, 124, 12, u32(contents.len))
	header[156] = if directory { `5` } else { `0` }
	copy(mut header[257..263], 'ustar\x00'.bytes())
	copy(mut header[263..265], '00'.bytes())
	for i in 148 .. 156 { header[i] = ` ` }
	mut sum := u32(0)
	for byte in header { sum += byte }
	tar_octal(mut header, 148, 8, sum)
	archive << header
	archive << contents
	padding := (512 - contents.len % 512) % 512
	archive << []u8{len: padding}
}

fn tar_link(mut archive []u8, name string, target string) {
	mut header := []u8{}
	tar_entry(mut header, name, []u8{}, false)
	header[156] = `1`
	copy(mut header[157..157 + target.len], target.bytes())
	tar_octal(mut header, 100, 8, 0o755)
	for i in 148 .. 156 { header[i] = ` ` }
	mut sum := u32(0)
	for byte in header { sum += byte }
	tar_octal(mut header, 148, 8, sum)
	archive << header
}

fn make_ramfs(output string) ! {
	mut archive := []u8{}
	tar_entry(mut archive, 'bin/', []u8{}, true)
	tar_entry(mut archive, 'etc/', []u8{}, true)
	init := os.getenv_opt('VINIX_PPC_INIT') or { output + '/init-ppc.elf' }
	desktop := os.file_name(init) == 'vinix-desktop' || os.getenv('VINIX_PPC_DESKTOP_APPS') == '1'
	if desktop { os.cp(output + '/init-ppc.elf', output + '/shell-ppc.elf')! }
	if init != output + '/init-ppc.elf' { os.cp(init, output + '/init-ppc.elf')! }
	tar_entry(mut archive, 'bin/init', os.read_bytes(output + '/init-ppc.elf')!, false)
	if desktop {
		tar_entry(mut archive, 'bin/sh', os.read_bytes(output + '/shell-ppc.elf')!, false)
		tar_entry(mut archive, 'usr/', []u8{}, true)
		tar_entry(mut archive, 'usr/bin/', []u8{}, true)
		// The installed desktop is a multicall binary. Immutable executable
		// bytes occur once in the archive, with the same per-app names used by
		// the other architectures. Standalone programs need their own port.
		root := os.real_path(@VMODROOT + '/../..')
		for block in os.read_file(root + '/desktop/app.v')!.split('AppFactory{') {
			entry := block.all_before('},')
			if entry.contains('standalone:') { continue }
			for line in entry.split_into_lines() {
				if !line.trim_space().starts_with('process_name:') { continue }
				name := line.all_after(':').trim_space().trim("'")
				if name.starts_with('vinix-') && !name.contains('/') {
					tar_link(mut archive, 'usr/bin/' + name, 'bin/init')
				}
			}
		}
	}
	tar_entry(mut archive, 'etc/motd', 'Vinix PowerPC development system\nProtected userspace, read-only boot filesystem, serial console.\n'.bytes(), false)
	tar_entry(mut archive, 'README', 'This is the initial PPC32 userspace. Desktop, disks and networking are still being ported.\n'.bytes(), false)
	archive << []u8{len: 1024}
	os.write_file_array(output + '/ramfs.tar', archive)!
}

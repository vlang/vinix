// SPDX-License-Identifier: GPL-2.0-or-later
module main

import encoding.binary
import os

const sector_size = 2048

fn both16(mut data []u8, at int, value u16) {
	binary.little_endian_put_u16(mut data[at..at + 2], value)
	binary.big_endian_put_u16(mut data[at + 2..at + 4], value)
}

fn both32(mut data []u8, at int, value u32) {
	binary.little_endian_put_u32(mut data[at..at + 4], value)
	binary.big_endian_put_u32(mut data[at + 4..at + 8], value)
}

fn iso_text(mut data []u8, at int, size int, value string) {
	for i in 0 .. size { data[at + i] = if i < value.len { value[i] } else { ` ` } }
}

fn directory_record(mut image []u8, at int, extent u32, size u32, flags u8, name []u8) int {
	length := (33 + name.len + 1) & ~1
	image[at] = u8(length)
	both32(mut image, at + 2, extent)
	both32(mut image, at + 10, size)
	// A fixed recording date keeps rebuilds reproducible.
	image[at + 18] = 100
	image[at + 19] = 1
	image[at + 20] = 1
	image[at + 25] = flags
	both16(mut image, at + 28, 1)
	image[at + 32] = u8(name.len)
	copy(mut image[at + 33..at + 33 + name.len], name)
	return length
}

// Write an ordinary ISO9660 volume. Open Firmware loads the ELF by its path;
// PC El Torito boot records and UEFI executables have no role here.
fn make_iso(output string) ! {
	loader := os.read_bytes(output + '/vinix-of.elf')!
	probe := os.read_bytes(output + '/handoff-probe.elf')!
	if loader.len == 0 || loader.len > 16 * 1024 * 1024 { return error('Invalid loader size') }
	if probe.len == 0 || probe.len > 16 * 1024 * 1024 { return error('Invalid probe size') }
	probe_block := 21 + (loader.len + sector_size - 1) / sector_size
	blocks := probe_block + (probe.len + sector_size - 1) / sector_size
	mut image := []u8{len: blocks * sector_size}
	pvd := 16 * sector_size
	image[pvd] = 1
	iso_text(mut image, pvd + 1, 5, 'CD001')
	image[pvd + 6] = 1
	iso_text(mut image, pvd + 8, 32, 'VINIX')
	iso_text(mut image, pvd + 40, 32, 'VINIX_PPC_BOOT')
	both32(mut image, pvd + 80, u32(blocks))
	both16(mut image, pvd + 120, 1)
	both16(mut image, pvd + 124, 1)
	both16(mut image, pvd + 128, sector_size)
	both32(mut image, pvd + 132, 10)
	binary.little_endian_put_u32(mut image[pvd + 140..pvd + 144], 18)
	binary.big_endian_put_u32(mut image[pvd + 148..pvd + 152], 19)
	directory_record(mut image, pvd + 156, 20, sector_size, 2, [u8(0)])
	iso_text(mut image, pvd + 190, 128, 'VINIX_PPC_BOOT')
	iso_text(mut image, pvd + 318, 128, 'VINIX')
	iso_text(mut image, pvd + 446, 128, 'VINIX V IMAGE BUILDER')
	iso_text(mut image, pvd + 574, 128, 'VINIX POWERPC OPEN FIRMWARE')
	for at in [813, 830, 847, 864] { iso_text(mut image, pvd + at, 16, '0000000000000000') }
	image[pvd + 881] = 1
	end := 17 * sector_size
	image[end] = 255
	iso_text(mut image, end + 1, 5, 'CD001')
	image[end + 6] = 1
	for block in [18, 19] {
		at := block * sector_size
		image[at] = 1
		if block == 18 {
			binary.little_endian_put_u32(mut image[at + 2..at + 6], 20)
			binary.little_endian_put_u16(mut image[at + 6..at + 8], 1)
		} else {
			binary.big_endian_put_u32(mut image[at + 2..at + 6], 20)
			binary.big_endian_put_u16(mut image[at + 6..at + 8], 1)
		}
	}
	mut at := 20 * sector_size
	at += directory_record(mut image, at, 20, sector_size, 2, [u8(0)])
	at += directory_record(mut image, at, 20, sector_size, 2, [u8(1)])
	at += directory_record(mut image, at, 21, u32(loader.len), 0, 'BOOT.ELF;1'.bytes())
	directory_record(mut image, at, u32(probe_block), u32(probe.len), 0, 'PROBE.ELF;1'.bytes())
	copy(mut image[21 * sector_size..21 * sector_size + loader.len], loader)
	copy(mut image[probe_block * sector_size..probe_block * sector_size + probe.len], probe)
	os.write_file_array(output + '/vinix-ppc-boot.iso', image)!
}

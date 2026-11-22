// SPDX-License-Identifier: GPL-2.0-or-later
module main

import disklayout
import os

fn main() {
	if os.args.len != 2 {
		eprintln('usage: check ISO_INSTALL_TARGET')
		exit(2)
	}
	check(os.args[1]) or {
		eprintln(err)
		exit(1)
	}
	println('complete GPT and Vinix system partition')
}

fn check(path string) ! {
	mut disk := os.open(path)!
	defer { disk.close() }
	bytes := os.file_size(path)
	sector := disklayout.sector_bytes
	if bytes < disklayout.min_disk_bytes || bytes % sector != 0 {
		return error('invalid installation disk size')
	}
	sectors := bytes / sector
	mbr := disk.read_bytes_at(512, 0)
	if mbr.len != 512 || mbr[450] != 0xee || mbr[510] != 0x55 || mbr[511] != 0xaa {
		return error('missing protective MBR')
	}
	mut identity := disklayout.Identity{}
	for backup in [false, true]! {
		hdr := disk.read_raw_at[disklayout.Header](disklayout.header_lba(sectors, backup) * sector)!
		table := disk.read_raw_at[disklayout.Table](disklayout.table_lba(sectors, backup) * sector)!
		state := disklayout.inspect(hdr, &table, sectors, backup) or {
			return error('invalid GPT copy (backup=${backup})')
		}
		if state.pending || (backup && (!state.id.disk.matches(identity.disk)
			|| !state.id.esp.matches(identity.esp) || !state.id.root.matches(identity.root))) {
			return error('unfinished installation or a mismatched GPT copy')
		}
		identity = state.id
	}
	esp := disk.read_bytes_at(8, disklayout.esp_start * sector + 82)
	if esp.bytestr() != 'FAT32   ' {
		return error('missing FAT32 boot partition')
	}
	magic := disk.read_bytes_at(2, disklayout.root_start * sector + 0x438)
	if magic != [u8(0x56), 0x4a] {
		return error('missing journaled Vinix filesystem')
	}
}

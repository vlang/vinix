// SPDX-License-Identifier: GPL-2.0-or-later
module disklayout

fn test_gpt_encoding_and_validation() {
	assert sizeof(Header) == sector_bytes
	assert sizeof(Table) == table_sectors * sector_bytes
	assert crc32(unsafe { &u8(c'123456789') }, 9) == 0xcbf43926
	sectors := min_disk_bytes / sector_bytes
	id := Identity{ disk: Guid{ low: 1 }, bios: Guid{ low: 2 }, esp: Guid{ low: 3 }, root: Guid{ low: 4 } }
	table := &Table{}
	for pending in [false, true]! {
		entries(table, sectors, id, pending)
		for backup in [false, true]! {
			hdr := header(table, sectors, id.disk, backup)
			result := inspect(hdr, table, sectors, backup) or { panic('valid table rejected') }
			assert result.pending == pending
			assert result.id.disk.matches(id.disk)
			assert result.id.esp.matches(id.esp)
			assert result.id.root.matches(id.root)
			assert inspect(hdr, table, sectors, !backup) == none
			assert inspect(hdr, table, sectors + 1, backup) == none
		}
	}
	hdr := header(table, sectors, id.disk, false)
	unsafe { table.entries[root_index].first += 1 }
	assert inspect(hdr, table, sectors, false) == none
	assert inspect(header(table, sectors, id.disk, false), table, sectors, false) == none
}

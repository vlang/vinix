// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

import os

fn sample_plan() Plan {
	mut plan := Plan{count: 2, key: DiskKey{bytes: 16 * 1024 * 1024, sector: 512, kind: 1}}
	plan.key.id[0] = 0x34
	plan.key.id[1] = 0x12
	plan.rows[0] = Request{slot: 2, offset: 1024 * 1024, length: 4096}
	plan.rows[1] = Request{slot: 5, offset: 2 * 1024 * 1024, length: 8192, flags: 1}
	return plan
}

fn repair_checksum(mut data [2112]u8, size int) { put_le(&data[0], 36, 4, crc32(&data[0], size, 36)) }

fn test_plan_roundtrip_and_every_truncated_prefix_fails() {
	plan := sample_plan()
	mut bytes := [2112]u8{}
	size := encode_plan(&plan, &bytes[0])
	assert size == 128
	assert bytes[..8].bytestr() == 'VINIXVM1'
	mut decoded := Plan{}
	assert decode_plan(&bytes[0], size, mut decoded)
	assert key_matches(&plan.key, &decoded.key) && decoded.count == 2
	assert decoded.rows[0].slot == 2 && decoded.rows[0].offset == 1048576
	assert decoded.rows[1].flags == 1 && decoded.rows[1].length == 8192
	for shorter in 0 .. size { assert !decode_plan(&bytes[0], shorter, mut decoded) }
	assert !decode_plan(&bytes[0], size + 1, mut decoded)
	for index in 0 .. size {
		for bit in 0 .. 8 {
			bytes[index] ^= u8(1 << bit)
			assert !decode_plan(&bytes[0], size, mut decoded)
			bytes[index] ^= u8(1 << bit)
		}
	}
}

fn test_checksummed_invalid_fields_cannot_bypass_validation() {
	plan := sample_plan()
	// Unknown version, excessive count, zero signature, reserved header,
	// duplicate slot, overlapping ranges, overflow, unsupported flags.
	locations := [8, 12, 40, 56, 100, 104, 112, 120]!
	values := [u64(2), 65, 0, 1, 2, 1048576, u64(-1), 2]!
	widths := [4, 4, 16, 8, 4, 8, 8, 8]!
	for i, location in locations {
		mut bytes := [2112]u8{}
		size := encode_plan(&plan, &bytes[0])
		if widths[i] == 16 { for j in 0 .. 16 { bytes[location + j] = 0 } }
		else { put_le(&bytes[0], location, widths[i], values[i]) }
		repair_checksum(mut bytes, size)
		mut decoded := Plan{}
		assert !decode_plan(&bytes[0], size, mut decoded)
	}
	mut invalid := sample_plan()
	invalid.rows[0].offset = 1
	assert !plan_valid(&invalid)
	invalid = sample_plan(); invalid.rows[0].length = 0
	assert !plan_valid(&invalid)
	invalid = sample_plan(); invalid.key.id[8] = 1
	assert !plan_valid(&invalid)
}

fn test_empty_and_maximum_plans_are_bounded() {
	mut plan := sample_plan()
	plan.count = 0
	mut bytes := [2112]u8{}
	assert encode_plan(&plan, &bytes[0]) == 64
	plan.count = 64
	for i := 0; i < 64; i++ { plan.rows[i] = Request{slot: u32(i), offset: u64(i * 512), length: 512} }
	assert encode_plan(&plan, &bytes[0]) == 2112
	mut decoded := Plan{}
	assert decode_plan(&bytes[0], 2112, mut decoded) && decoded.count == 64
	plan.count = 65
	assert !plan_valid(&plan)
}

fn test_mbr_and_gpt_identity_reject_missing_corrupt_or_changed_metadata() {
	mut sectors := [1024]u8{}
	put_le(&sectors[0], 440, 4, 0x12345678)
	put_le(&sectors[0], 510, 2, 0xaa55)
	mut mbr := DiskKey{}
	assert identify_disk(&sectors[0], 1024, 16 * 1024 * 1024, 512, mut mbr)
	assert mbr.kind == 1 && mbr.id[0] == 0x78
	mut changed := mbr
	changed.id[0] = 0x99; assert !key_matches(&mbr, &changed)
	changed = mbr; changed.bytes *= 2; assert !key_matches(&mbr, &changed)
	sectors[450] = 0xee
	assert !identify_disk(&sectors[0], 1024, mbr.bytes, 512, mut changed)
	put_le(&sectors[0], 512, 8, 0x5452415020494645)
	put_le(&sectors[0], 520, 4, 0x10000)
	put_le(&sectors[0], 524, 4, 92)
	put_le(&sectors[0], 536, 8, 1)
	sectors[568] = 0xad
	put_le(&sectors[0], 528, 4, crc32(&sectors[512], 92, 16))
	assert identify_disk(&sectors[0], 1024, mbr.bytes, 512, mut changed)
	assert changed.kind == 2 && changed.id[0] == 0xad
	sectors[568] ^= 1
	assert !identify_disk(&sectors[0], 1024, mbr.bytes, 512, mut changed)
	put_le(&sectors[0], 524, 4, 513)
	assert !identify_disk(&sectors[0], 1024, mbr.bytes, 512, mut changed)
}

fn test_gpt_identity_and_plan_with_4096_byte_sectors() {
	mut sectors := [8192]u8{}
	put_le(&sectors[0], 4096, 8, 0x5452415020494645)
	put_le(&sectors[0], 4104, 4, 0x10000)
	put_le(&sectors[0], 4108, 4, 92)
	put_le(&sectors[0], 4120, 8, 1)
	sectors[4152] = 0x7c
	put_le(&sectors[0], 4112, 4, crc32(&sectors[4096], 92, 16))
	mut key := DiskKey{}
	assert identify_disk(&sectors[0], 8192, 16 * 1024 * 1024, 4096, mut key)
	mut plan := sample_plan()
	plan.key = key
	mut bytes := [2112]u8{}
	mut decoded := Plan{}
	assert encode_plan(&plan, &bytes[0]) == 128
	assert decode_plan(&bytes[0], 128, mut decoded) && key_matches(&key, &decoded.key)
	plan.rows[0].offset += 512
	assert !plan_valid(&plan)
	key.sector = 8192
	assert !key_valid(&key)
}

fn test_plan_publication_preserves_previous_file_on_failure_and_rejects_links() {
	work := os.join_path(os.temp_dir(), 'vinix-plan-test-${os.getpid()}')
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	path := os.join_path(work, 'saved.vmap')
	plan := sample_plan()
	assert publish_plan(path.str, &plan)
	original := os.read_bytes(path)!
	mut decoded := Plan{}
	assert load_plan(path.str, mut decoded) && decoded.count == 2
	mut bad := plan
	bad.count = 65
	assert !publish_plan(path.str, &bad)
	assert os.read_bytes(path)! == original
	assert !publish_plan(os.join_path(work, 'missing/plan').str, &plan)
	assert os.ls(work)!.len == 1
	link := os.join_path(work, 'link')
	os.symlink(path, link)!
	assert !load_plan(link.str, mut decoded)
	assert !load_plan(work.str, mut decoded)
	os.write_file(path, 'bad')!
	assert !load_plan(path.str, mut decoded)
	assert publish_plan(path.str, &plan)
	assert os.read_bytes(path)! == original
	// Rename failure also removes the temporary and preserves existing entries.
	target_directory := os.join_path(work, 'directory')
	os.mkdir(target_directory)!
	assert !publish_plan(target_directory.str, &plan)
	assert os.is_dir(target_directory) && os.read_bytes(path)! == original
	assert os.ls(work)!.len == 3
}

fn test_discovery_ignores_regular_files_and_symlinks_and_rejects_invalid_plans() {
	work := os.join_path(os.temp_dir(), 'vinix-discovery-test-${os.getpid()}')
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	path := os.join_path(work, 'raw')
	os.write_file(path, 'not a block device')!
	os.symlink(path, os.join_path(work, 'disk-link'))!
	os.mkdir(os.join_path(work, 'subdirectory'))!
	mut name := [256]char{}
	plan := sample_plan()
	assert discover_disk(&plan, work.str, false, &name[0]) == -1
	link := work + '-link'
	os.symlink(work, link)!
	defer { os.rm(link) or {} }
	assert discover_disk(&plan, link.str, false, &name[0]) == -1
	mut invalid := plan; invalid.key.sector = 0
	assert discover_disk(&invalid, work.str, true, &name[0]) == -1
	assert os.read_file(path)! == 'not a block device'
}

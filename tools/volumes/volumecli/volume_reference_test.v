// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

fn test_reference_comparison_complete_validation_exact_metadata_and_transactional_outputs() {
	for sector in [u64(512), u64(4096)] { for kind in [u32(1), u32(2)] { for flags in [u64(0), u64(1)] {
		mut disk := DiskKey{bytes: u64(-1) - (sector - 1), sector: sector, kind: kind}; disk.id[0] = 1; if kind == 2 { disk.id[15] = 0x83 }
		row := Request{slot: 63, offset: 8192, length: 73728, flags: flags}; digest := [32]u8{init: u8(index * 7 + 11)}
		mut reference := [128]u8{}; assert encode_volume_ciphertext(&disk, &row, &digest[0], &reference[0])
		mut output_disk := DiskKey{}; mut output_row := Request{}; mut changed := true
		assert compare_volume_references(&reference[0], 128, &reference[0], 128, mut output_disk, mut output_row, unsafe { &changed })
		assert output_disk == disk && output_row == row && !changed
		for at in 80 .. 112 {
			mut other := reference; other[at] ^= 1; put_le(&other[0], 124, 4, crc32(&other[0], 128, 124))
			assert compare_volume_references(&reference[0], 128, &other[0], 128, mut output_disk, mut output_row, unsafe { &changed }) && changed
			assert compare_volume_references(&other[0], 128, &reference[0], 128, mut output_disk, mut output_row, unsafe { &changed }) && changed
		}
		output_disk = DiskKey{bytes: 17}; output_row = Request{slot: 7}; changed = true
		for side in 0 .. 2 { for at in 0 .. 128 {
			mut bad := reference; bad[at] ^= 1
			assert !compare_volume_references(unsafe { if side == 0 { &bad[0] } else { &reference[0] } }, 128,
				unsafe { if side == 1 { &bad[0] } else { &reference[0] } }, 128, mut output_disk, mut output_row, unsafe { &changed })
			assert output_disk == DiskKey{bytes: 17} && output_row == Request{slot: 7} && changed
		} }
		for size in [0, 127, 129] {
			assert !compare_volume_references(unsafe { nil }, size, &reference[0], 128, mut output_disk, mut output_row, unsafe { &changed })
			assert !compare_volume_references(&reference[0], 128, unsafe { nil }, size, mut output_disk, mut output_row, unsafe { &changed })
			assert output_disk == DiskKey{bytes: 17} && output_row == Request{slot: 7} && changed
		}
		for at in [16, 36, 40, 48, 56, 64] {
			mut other := reference
			if at == 16 { put_le(&other[0], 16, 8, disk.bytes - sector) }
			else if at == 40 { put_le(&other[0], 40, 8, row.offset + sector) }
			else if at == 48 { put_le(&other[0], 48, 8, row.length + sector) }
			else { other[at] ^= if at == 64 { u8(2) } else { u8(1) } }
			put_le(&other[0], 124, 4, crc32(&other[0], 128, 124))
			mut valid_disk := DiskKey{}; mut valid_row := Request{}
			assert volume_ciphertext_reference_geometry(&other[0], mut valid_disk, mut valid_row)
			assert !compare_volume_references(&reference[0], 128, &other[0], 128, mut output_disk, mut output_row, unsafe { &changed })
			assert output_disk == DiskKey{bytes: 17} && output_row == Request{slot: 7} && changed
		}
	} } }
}

fn test_reference_query_commands_reject_bad_arity_and_empty_paths_before_io() {
	unsafe {
		mut args := [&char(c'vinix-volume'), &char(c'show-volume-reference'), &char(c'/unused'), &char(c'/unused'), &char(nil)]!
		for count in [2, 4] { assert run(count, &args[0]) == 2 }; args[2] = &char(c''); assert run(3, &args[0]) == 2
		args[1] = &char(c'compare-volume-references'); args[2] = &char(c'/unused')
		for count in [2, 3, 5] { assert run(count, &args[0]) == 2 }
		for at in [2, 3] { args[at] = &char(c''); assert run(4, &args[0]) == 2; args[at] = &char(c'/unused') }
	}
}

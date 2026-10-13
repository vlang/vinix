// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

fn test_scrub_comparison_complete_reports_exact_reference_and_transactional_outputs() {
	for sector in [u64(512), u64(4096)] { for kind in [u32(1), u32(2)] { for flags in [u64(0), u64(1)] {
		mut disk := DiskKey{bytes: u64(-1) - (sector - 1), sector: sector, kind: kind}; disk.id[0] = 1; if kind == 2 { disk.id[15] = 0x83 }
		row := Request{slot: 63, offset: 8192, length: 73728, flags: flags}; expected := [32]u8{init: u8(index * 7 + 11)}
		mut reference := [128]u8{}; assert encode_volume_ciphertext(&disk, &row, &expected[0], &reference[0])
		mut records := [3][224]u8{}
		for i in 0 .. 3 { mut actual := expected; if i > 0 { actual[31] ^= u8(i) }; assert encode_volume_ciphertext_scrub(&reference[0], &actual[0], &records[i][0]) }
		for i in 0 .. 3 { for j in 0 .. 3 {
			mut output_disk := DiskKey{}; mut output_row := Request{}; mut changed := false
			assert compare_volume_ciphertext_scrubs(&records[i][0], 224, &records[j][0], 224, mut output_disk, mut output_row, unsafe { &changed })
			assert output_disk == disk && output_row == row && changed == (i != j)
		} }
		mut output_disk := DiskKey{bytes: 17}; mut output_row := Request{slot: 7}; mut changed := true
		for side in 0 .. 2 { for at in 0 .. 224 {
			mut bad := records[0]; bad[at] ^= 1
			assert !compare_volume_ciphertext_scrubs(unsafe { if side == 0 { &bad[0] } else { &records[0][0] } }, 224,
				unsafe { if side == 1 { &bad[0] } else { &records[0][0] } }, 224, mut output_disk, mut output_row, unsafe { &changed })
			assert output_disk == DiskKey{bytes: 17} && output_row == Request{slot: 7} && changed
		} }
		for size in [0, 223, 225] {
			assert !compare_volume_ciphertext_scrubs(&records[0][0], size, &records[0][0], 224, mut output_disk, mut output_row, unsafe { &changed })
			assert !compare_volume_ciphertext_scrubs(&records[0][0], 224, &records[0][0], size, mut output_disk, mut output_row, unsafe { &changed })
		}
		// Both reports are valid independently. Re-encoding repairs every CRC and
		// fingerprint, so refusal proves exact-reference binding rather than damage.
		for at in [16, 36, 40, 48, 56, 64, 80] {
			mut other := reference; other[at] ^= if at in [16, 40, 48] { u8(0x20) } else if at == 64 { u8(2) } else { u8(1) }
			put_le(&other[0], 124, 4, crc32(&other[0], 128, 124)); mut report := [224]u8{}
			// Geometry changes must remain canonical; adjust full-width capacity and
			// aligned ranges explicitly rather than assuming each bit flip is valid.
			if at == 16 { put_le(&other[0], 16, 8, disk.bytes - sector) }
			if at == 40 { put_le(&other[0], 40, 8, row.offset + sector) }
			if at == 48 { put_le(&other[0], 48, 8, row.length + sector) }
			put_le(&other[0], 124, 4, crc32(&other[0], 128, 124))
			assert encode_volume_ciphertext_scrub(&other[0], &expected[0], &report[0])
			assert !compare_volume_ciphertext_scrubs(&records[0][0], 224, &report[0], 224, mut output_disk, mut output_row, unsafe { &changed })
			assert output_disk == DiskKey{bytes: 17} && output_row == Request{slot: 7} && changed
		}
	} } }
}

fn test_scrub_comparison_rejects_invalid_arity_and_empty_paths_before_io() {
	unsafe {
		mut args := [&char(c'vinix-volume'), &char(c'compare-volume-scrubs'), &char(c'/unused'), &char(c'/unused'), &char(nil)]!
		for count in [2, 3, 5] { assert run(count, &args[0]) == 2 }
		for at in [2, 3] { args[at] = &char(c''); assert run(4, &args[0]) == 2; args[at] = &char(c'/unused') }
	}
}

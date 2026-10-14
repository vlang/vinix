// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

import crypto.sha256
import encoding.hex

fn cipher_binding_expected(reference []u8, report []u8, disk DiskKey, row Request) string {
	changed := report[16] != 0
	identity := if disk.kind == 1 { 'mbr:00000001' } else { 'gpt:00000001-0000-0000-0000-000000000083' }
	return 'format=VINIXCS1 operation=verified-ciphertext-scrub-reference mappings=1 matched=${int(!changed)} changed=${int(changed)} algorithm=sha256 reference_sha256=' + hex.encode(sha256.sum(reference)) + ' report_sha256=' + hex.encode(sha256.sum(report)) + '\n' +
		'disk_bytes=${disk.bytes} sector=${disk.sector} identity=${identity} slot=${row.slot} offset=${row.offset} bytes=${row.length} readonly=${row.flags} result=${if changed { 'changed' } else { 'match' }} expected_sha256=' + hex.encode(reference[80..112]) + ' actual_sha256=' + hex.encode(report[160..192]) + '\n'
}

fn test_cipher_binding_eight_profiles_every_observed_digest_byte_exact_complete_view_and_failure_transaction() {
	for sector in [u64(512), u64(4096)] { for kind in [u32(1), u32(2)] { for flags in [u64(0), u64(1)] {
		mut disk := DiskKey{bytes: u64(-1) & ~(sector - 1), sector: sector, kind: kind}; disk.id[0] = 1; if kind == 2 { disk.id[15] = 0x83 }
		row := Request{slot: 63, offset: 8192, length: 73728, flags: flags}; digest := [32]u8{init: u8(index * 7 + 11)}
		mut reference := [128]u8{}; assert encode_volume_ciphertext(&disk, &row, &digest[0], &reference[0])
		for changed in [false, true] { for byte in 0 .. 32 {
			mut actual := digest; if changed { actual[byte] ^= 1 }; mut report := [224]u8{}; assert encode_volume_ciphertext_scrub(&reference[0], &actual[0], &report[0])
			mut out_disk := DiskKey{bytes: 17}; mut out_row := Request{slot: 7}
			assert volume_scrub_reference_matches(&reference[0], 128, &report[0], 224, mut out_disk, mut out_row) && out_disk == disk && out_row == row
			mut output := [2048]char{init: char(91)}; size := encode_volume_scrub_reference(&reference[0], &report[0], &output[0]); expected := cipher_binding_expected(reference[..], report[..], disk, row)
			assert size == expected.len && unsafe { tos(&u8(&output[0]), size) } == expected && output[size] == 0 && output[size + 1] == char(91)
		} }
		mut report := [224]u8{}; mut observed := digest; observed[31] ^= 1; assert encode_volume_ciphertext_scrub(&reference[0], &observed[0], &report[0])
		mut out_disk := DiskKey{bytes: 17}; mut out_row := Request{slot: 7}
		for side in 0 .. 2 { for at in 0 .. if side == 0 { 128 } else { 224 } {
			mut wrong_ref := reference; mut wrong_report := report; if side == 0 { wrong_ref[at] ^= 1 } else { wrong_report[at] ^= 1 }
			assert !volume_scrub_reference_matches(&wrong_ref[0], 128, &wrong_report[0], 224, mut out_disk, mut out_row)
			assert out_disk == DiskKey{bytes: 17} && out_row == Request{slot: 7}
			mut output := [2048]char{init: char(91)}; saved := output; assert encode_volume_scrub_reference(&wrong_ref[0], &wrong_report[0], &output[0]) == 0 && output == saved
		} }
		for size in [-1, 0, 127, 129] { assert !volume_scrub_reference_matches(unsafe { nil }, size, &report[0], 224, mut out_disk, mut out_row) }
		for size in [-1, 0, 223, 225] { assert !volume_scrub_reference_matches(&reference[0], 128, unsafe { nil }, size, mut out_disk, mut out_row) }
		// Fully valid different records still fail exact reference binding.
		for at in [16, 36, 40, 48, 56, 64, 80, 111] {
			mut other := reference
			if at == 16 { put_le(&other[0], 16, 8, disk.bytes - sector) }
			else if at == 40 { put_le(&other[0], 40, 8, row.offset + sector) }
			else if at == 48 { put_le(&other[0], 48, 8, row.length + sector) }
			else { other[at] ^= if at == 64 { u8(2) } else { u8(1) } }
			put_le(&other[0], 124, 4, crc32(&other[0], 128, 124)); mut valid_disk := DiskKey{}; mut valid_row := Request{}
			assert volume_ciphertext_reference_geometry(&other[0], mut valid_disk, mut valid_row)
			assert !volume_scrub_reference_matches(&other[0], 128, &report[0], 224, mut out_disk, mut out_row) && out_disk == DiskKey{bytes: 17} && out_row == Request{slot: 7}
			mut other_report := [224]u8{}; assert encode_volume_ciphertext_scrub(&other[0], &observed[0], &other_report[0])
			assert !volume_scrub_reference_matches(&reference[0], 128, &other_report[0], 224, mut out_disk, mut out_row) && out_disk == DiskKey{bytes: 17} && out_row == Request{slot: 7}
		}
		for byte in 80 .. 112 { mut other := reference; other[byte] ^= 1; put_le(&other[0], 124, 4, crc32(&other[0], 128, 124)); assert !volume_scrub_reference_matches(&other[0], 128, &report[0], 224, mut out_disk, mut out_row) }
	} } }
}

fn test_cipher_binding_native_sector_changes_high_signed_offsets_and_cli_syntax() {
	mut disk := DiskKey{bytes: 1048576, sector: 512, kind: 1}; disk.id[0] = 1; row := Request{slot: 63, offset: 8192, length: 73728, flags: 1}; digest := [32]u8{}
	mut reference := [128]u8{}; mut other := [128]u8{}; mut report := [224]u8{}; mut out_disk := DiskKey{bytes: 17}; mut out_row := Request{slot: 7}
	assert encode_volume_ciphertext(&disk, &row, &digest[0], &reference[0]) && encode_volume_ciphertext_scrub(&reference[0], &digest[0], &report[0]); disk.sector = 4096
	assert encode_volume_ciphertext(&disk, &row, &digest[0], &other[0]) && !volume_scrub_reference_matches(&other[0], 128, &report[0], 224, mut out_disk, mut out_row)
	disk.bytes = u64(-1) & ~u64(4095); high := Request{slot: 63, offset: (u64(0x7fffffffffffffff) & ~u64(4095)) - 4096, length: 4096, flags: 1}
	assert encode_volume_ciphertext(&disk, &high, &digest[0], &reference[0]) && encode_volume_ciphertext_scrub(&reference[0], &digest[0], &report[0])
	mut text := [2048]char{}; size := encode_volume_scrub_reference(&reference[0], &report[0], &text[0]); assert size > 0 && unsafe { tos(&u8(&text[0]), size) } == cipher_binding_expected(reference[..], report[..], disk, high)
	unsafe { mut args := [&char(c'vinix-volume'), &char(c'verify-volume-scrub-reference'), &char(c'/missing-reference'), &char(c'/missing-report'), &char(c'extra'), &char(nil)]!; for count in [2, 3, 5, 6] { assert run(count, &args[0]) == 2 }; for i in [2, 3] { saved := args[i]; args[i] = &char(c''); assert run(4, &args[0]) == 2; args[i] = saved }; assert run(4, &args[0]) == 1 }
}

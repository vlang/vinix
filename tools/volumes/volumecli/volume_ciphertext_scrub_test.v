// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

import crypto.sha256
import hash.crc32 as standard_crc

fn test_ciphertext_scrub_codec_exact_public_finding_fingerprint_and_transactional_decode() {
	for sector in [u64(512), u64(4096)] { for kind in [u32(1), u32(2)] { for flags in [u64(0), u64(1)] {
		mut disk := DiskKey{bytes: u64(-1) - (sector - 1), sector: sector, kind: kind}; disk.id[0] = 1; if kind == 2 { disk.id[15] = 0x83 }
		row := Request{slot: 63, offset: 8192, length: 73728, flags: flags}
		digest := [32]u8{init: u8(index * 11 + 7)}; mut reference := [128]u8{}
		assert encode_volume_ciphertext(&disk, &row, &digest[0], &reference[0])
		for changed in [false, true] {
			mut observed := digest; if changed { observed[0] ^= 1 }; mut bytes := [224]u8{}
			assert encode_volume_ciphertext_scrub(&reference[0], &observed[0], &bytes[0])
			mut expected := [224]u8{}
			for i, byte in 'VINIXCS1'.bytes() { expected[i] = byte }
			put_le(&expected[0], 8, 4, 1); put_le(&expected[0], 12, 4, 224)
			put_le(&expected[0], 16, 4, u64(changed)); put_le(&expected[0], 20, 4, 1)
			fingerprint := sha256.sum(reference[..])
			for i in 0 .. 128 { expected[32 + i] = reference[i] }
			for i in 0 .. 32 { expected[160 + i] = observed[i]; expected[192 + i] = fingerprint[i] }
			put_le(&expected[0], 28, 4, u64(standard_crc.sum(expected[..])))
			assert bytes == expected
			mut output_disk := DiskKey{}; mut output_row := Request{}
			assert decode_volume_ciphertext_scrub(&bytes[0], 224, mut output_disk, mut output_row)
			assert output_disk == disk && output_row == row
			for size in [0, 223, 225] { assert !decode_volume_ciphertext_scrub(&bytes[0], size, mut output_disk, mut output_row); assert output_disk == disk && output_row == row }
			for at in 0 .. 224 {
				mut bad := bytes; bad[at] ^= 1
				assert !decode_volume_ciphertext_scrub(&bad[0], 224, mut output_disk, mut output_row); assert output_disk == disk && output_row == row
				put_le(&bad[0], 28, 4, crc32(&bad[0], 224, 28))
				valid := (at >= 28 && at < 32) || (changed && at > 160 && at < 192)
				assert decode_volume_ciphertext_scrub(&bad[0], 224, mut output_disk, mut output_row) == valid
				assert output_disk == disk && output_row == row
			}
			mut invalid := reference; invalid[112] = 1; put_le(&invalid[0], 124, 4, crc32(&invalid[0], 128, 124))
			mut untouched := bytes; assert !encode_volume_ciphertext_scrub(&invalid[0], &observed[0], &untouched[0]) && untouched == bytes
			for fault in 0 .. 4 {
				mut bad := bytes
				if fault == 0 { bad[144] = 1 }
				else if fault == 1 { put_le(&bad[32], 24, 8, 1024) }
				else if fault == 2 { put_le(&bad[32], 48, 8, data_sha_max_bytes + 1) }
				else { put_le(&bad[32], 40, 8, u64(0x7fffffffffffffff) - (sector - 1)) }
				put_le(&bad[32], 124, 4, crc32(&bad[32], 128, 124))
				fresh := sha256.sum(bad[32..160]); for i in 0 .. 32 { bad[192 + i] = fresh[i] }
				put_le(&bad[0], 28, 4, crc32(&bad[0], 224, 28))
				assert !decode_volume_ciphertext_scrub(&bad[0], 224, mut output_disk, mut output_row) && output_disk == disk && output_row == row
			}
		}
	} } }
}

fn test_ciphertext_scrub_and_offline_show_reject_bad_arity_and_empty_paths_before_io() {
	unsafe {
		for verb in [&char(c'scrub-volume'), &char(c'scrub-recovery-volume')]! {
			mut args := [&char(c'vinix-volume'), verb, &char(c'/unused'), &char(c'/unused'), &char(c'/unused'), &char(c'/unused'), &char(c'/unused'), &char(nil)]!
			for count in [2, 3, 4, 5, 6, 8] { assert run(count, &args[0]) == 2 }
			for at in [2, 3, 4, 5, 6] { args[at] = &char(c''); assert run(7, &args[0]) == 2; args[at] = &char(c'/unused') }
		}
		mut show := [&char(c'vinix-volume'), &char(c'show-volume-scrub'), &char(c'/unused'), &char(nil)]!
		assert run(2, &show[0]) == 2 && run(4, &show[0]) == 2; show[2] = &char(c''); assert run(3, &show[0]) == 2
	}
}

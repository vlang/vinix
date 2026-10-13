// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

fn test_ciphertext_reference_exact_geometry_crc_reserved_and_signed_ranges() {
	for sector in [u64(512), u64(4096)] {
		for kind in [u32(1), u32(2)] {
			for flags in [u64(0), u64(1)] {
				mut disk := DiskKey{bytes: u64(-1) - (sector - 1), sector: sector, kind: kind}; disk.id[0] = 1; if kind == 2 { disk.id[15] = 0x83 }
				row := Request{slot: 63, offset: 8192, length: 73728, flags: flags}
				digest := [32]u8{init: u8(index * 11 + 7)}; mut bytes := [128]u8{}
				assert encode_volume_ciphertext(&disk, &row, &digest[0], &bytes[0])
				assert get_le(&bytes[0], 0, 8) == 0x31484358494e4956 && get_le(&bytes[0], 16, 8) == disk.bytes
				assert bytes[80..112] == digest[..] && volume_ciphertext_matches(&bytes[0], 128, &disk, &row)
				for size in [0, 127, 129] { assert !volume_ciphertext_matches(&bytes[0], size, &disk, &row) }
				for at in 0 .. 128 {
					mut bad := bytes; bad[at] ^= 1
					assert !volume_ciphertext_matches(&bad[0], 128, &disk, &row)
					put_le(&bad[0], 124, 4, crc32(&bad[0], 128, 124))
					assert volume_ciphertext_matches(&bad[0], 128, &disk, &row) == ((at >= 80 && at < 112) || at >= 124)
				}
				mut wrong := row
				wrong.offset = u64(0x8000000000000000); assert !volume_ciphertext_range(&disk, &wrong)
				wrong = row; wrong.length = u64(0x8000000000000000); assert !volume_ciphertext_range(&disk, &wrong)
				wrong = row; wrong.slot = 64; assert !volume_ciphertext_range(&disk, &wrong)
				wrong = row; wrong.length++; assert !volume_ciphertext_range(&disk, &wrong)
				wrong = row; wrong.length = data_sha_max_bytes - (sector - 1)
				assert volume_ciphertext_range(&disk, &wrong)
				wrong.length += sector; assert !volume_ciphertext_range(&disk, &wrong)
				wrong = row; wrong.offset = u64(0x7fffffffffffffff) - (sector - 1)
				assert !volume_ciphertext_range(&disk, &wrong)
			}
		}
	}
}

fn test_ciphertext_commands_reject_invalid_syntax_before_io() {
	unsafe {
		for verb in [&char(c'hash-volume'), &char(c'verify-volume'), &char(c'hash-recovery-volume'), &char(c'verify-recovery-volume')]! {
			mut args := [&char(c'vinix-volume'), verb, &char(c'/unused'), &char(c'/unused'), &char(c'/unused'), &char(c'/unused'), &char(nil)]!
			for count in [2, 3, 4, 5, 7] { assert run(count, &args[0]) == 2 }
			for at in [2, 3, 4, 5] { args[at] = &char(c''); assert run(6, &args[0]) == 2; args[at] = &char(c'/unused') }
		}
	}
}

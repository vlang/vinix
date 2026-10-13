// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

fn test_encrypted_growth_preserves_identity_offsets_modes_and_keys_at_native_sector_bounds() {
	mut password := [12]u8{init: u8(index * 13)}; mut random := [28]u8{init: u8(index * 11 + 3)}
	mut wrapping := [64]u8{}; assert sealed_derive(&password[0], 12, &random[0], &wrapping[0])
	for sector in [u64(512), u64(4096)] {
		for kind in [u32(1), u32(2)] {
			for flags in [u64(0), u64(1)] {
				mut saved := DiskKey{bytes: 16777216, sector: sector, kind: kind}; saved.id[0] = 1; if kind == 2 { saved.id[15] = 0x83 }
				request := EncryptedRequest{data: Request{slot: 63, offset: sector * 2, length: 4096, flags: flags}, key: [64]u8{init: u8(index * 13 + 7)}}
				for capacity in [u64(16777216), u64(25165824), u64(-1) - (sector - 1)] {
					mut observed := saved; observed.bytes = capacity
					for length in [u64(4096), u64(8192), capacity - request.data.offset] {
						assert volume_seal_growth(&saved, &observed, &request.data, length)
						mut next := request; next.data.length = length
						mut envelope := [320]u8{}; mut decoded_disk := DiskKey{}; mut decoded := EncryptedRequest{}
						assert encode_volume_seal(&observed, &next, &wrapping[0], &random[0], &envelope[0])
						assert decode_volume_seal(&envelope[0], 320, &wrapping[0], mut decoded_disk, mut decoded)
						assert decoded_disk == observed && decoded == next && decoded.key == request.key
					}
					for length in [u64(0), u64(512), u64(4095), u64(8193), capacity, u64(-1)] { assert !volume_seal_growth(&saved, &observed, &request.data, length) }
				}
				mut bad := saved; bad.bytes -= sector; assert !volume_seal_growth(&saved, &bad, &request.data, 8192)
				bad = saved; bad.sector = if sector == 512 { 4096 } else { 512 }; assert !volume_seal_growth(&saved, &bad, &request.data, 8192)
				bad = saved; bad.kind = if kind == 1 { 2 } else { 1 }; assert !volume_seal_growth(&saved, &bad, &request.data, 8192)
				for i in 0 .. 16 { bad = saved; bad.id[i] ^= 1; assert !volume_seal_growth(&saved, &bad, &request.data, 8192) }
			}
		}
	}
}

fn test_encrypted_growth_cli_rejects_invalid_sizes_paths_and_arity_before_io() {
	unsafe {
		mut args := [&char(c'vinix-volume'), &char(c'plan-grow-volume'), &char(c'/unused'), &char(c'/unused'), &char(c'/unused'), &char(c'8192'), &char(c'/unused'), &char(nil)]!
		for count in [2, 3, 4, 5, 6, 8] { assert run(count, &args[0]) == 2 }
		for at in [2, 3, 4, 6] { args[at] = &char(c''); assert run(7, &args[0]) == 2; args[at] = &char(c'/unused') }
		for value in [c'', c'0', c'-1', c'0x2000', c'8192x', c'18446744073709551616'] { args[5] = &char(value); assert run(7, &args[0]) == 2 }
	}
}

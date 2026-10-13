// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

import crypto.hmac
import crypto.sha256

fn test_volume_seal_binds_complete_disk_geometry_mode_and_key_before_releasing_any_output() {
	mut wrapping := [64]u8{}; mut random := [28]u8{}
	mut request := EncryptedRequest{data: Request{slot: 60, offset: 1048576, length: 8192}}
	for i in 0 .. 64 { wrapping[i] = u8(i * 29 + 41); request.key[i] = u8(i * 13 + 7) }
	for i in 0 .. 28 { random[i] = u8(i * 11 + 3) }
	mut bytes := [320]u8{}
	for kind in [u32(1), u32(2)] {
		for sector in [u64(512), u64(4096)] {
			for mode in [u64(0), u64(1)] {
				mut disk := DiskKey{bytes: 16777216, sector: sector, kind: kind}; disk.id[0] = 0x78
				if kind == 2 { disk.id[15] = 0x83 }
				request.data.flags = mode
				assert encode_volume_seal(&disk, &request, &wrapping[0], &random[0], &bytes[0]) && volume_seal_header(&bytes[0], 320)
				mut transcript := wrapping[..32].clone(); transcript << bytes[..288]
				assert bytes[288..] == hmac.new(wrapping[32..], transcript, sha256.sum256, 64)
				mut decoded_disk := DiskKey{}; mut decoded := EncryptedRequest{}
				assert decode_volume_seal(&bytes[0], 320, &wrapping[0], mut decoded_disk, mut decoded)
				assert decoded_disk == disk && decoded == request
			}
		}
	}
	sentinel_disk := DiskKey{bytes: 7, sector: 13, kind: 19, id: [16]u8{init: 0xa1}}
	sentinel := EncryptedRequest{data: Request{slot: 63, offset: 17, length: 31, flags: 8}, key: [64]u8{init: 0xa1}}
	mut decoded_disk := sentinel_disk; mut decoded := sentinel
	for bit in 0 .. 2560 {
		mut corrupt := bytes; corrupt[bit / 8] ^= u8(1 << (bit % 8))
		assert !decode_volume_seal(&corrupt[0], 320, &wrapping[0], mut decoded_disk, mut decoded)
		assert decoded_disk == sentinel_disk && decoded == sentinel
	}
	for bit in 0 .. 512 {
		mut wrong := wrapping; wrong[bit / 8] ^= u8(1 << (bit % 8))
		assert !decode_volume_seal(&bytes[0], 320, &wrong[0], mut decoded_disk, mut decoded)
		assert decoded_disk == sentinel_disk && decoded == sentinel
	}
	for size in -1 .. 322 { if size != 320 { assert !decode_volume_seal(&bytes[0], size, &wrapping[0], mut decoded_disk, mut decoded) } }
	// Even a valid tag cannot authorize unsupported or invalid geometry.
	for pair in [[88, 8, 1024], [96, 4, 0], [120, 4, 0], [124, 4, 64], [136, 8, 0], [144, 8, 2], [152, 8, 1], [256, 8, 1]] {
		mut bad := bytes; mut tag := [32]u8{}
		put_le(&bad[0], pair[0], pair[1], u64(pair[2]))
		assert volume_seal_tag(&wrapping[0], &bad[0], unsafe { &tag })
		for i in 0 .. 32 { bad[i + 288] = tag[i] }
		assert !decode_volume_seal(&bad[0], 320, &wrapping[0], mut decoded_disk, mut decoded)
		assert decoded_disk == sentinel_disk && decoded == sentinel
	}
	for same_as_wrapping in [false, true] {
		mut bad := bytes; mut tag := [32]u8{}
		for i in 0 .. 64 { bad[i + 192] = if same_as_wrapping { wrapping[i] } else { u8(7) } }
		recovery_chacha(&wrapping[0], &bad[56], &bad[192])
		assert volume_seal_tag(&wrapping[0], &bad[0], unsafe { &tag })
		for i in 0 .. 32 { bad[i + 288] = tag[i] }
		assert !decode_volume_seal(&bad[0], 320, &wrapping[0], mut decoded_disk, mut decoded)
		assert decoded_disk == sentinel_disk && decoded == sentinel
	}
}

fn test_volume_seal_geometry_bounds_and_failed_encoder_preserve_output() {
	mut disk := DiskKey{bytes: 16777216, sector: 512, kind: 1}; disk.id[0] = 1
	mut request := EncryptedRequest{data: Request{slot: 5, offset: 1024, length: 4096}}
	mut wrapping := [64]u8{}; mut random := [28]u8{}; mut output := [320]u8{init: 0xa1}
	for i in 0 .. 64 { wrapping[i] = u8(i * 29 + 41); request.key[i] = u8(i * 13 + 7) }
	for value in [u64(0), u64(511), u64(1024), u64(2048), u64(-1)] {
		mut bad := disk; bad.sector = value
		assert !encode_volume_seal(&bad, &request, &wrapping[0], &random[0], &output[0])
	}
	for offset in [u64(1), u64(16777217), u64(-1)] {
		mut bad := request; bad.data.offset = offset
		assert !encode_volume_seal(&disk, &bad, &wrapping[0], &random[0], &output[0])
	}
	for length in [u64(0), u64(513), u64(16777216), u64(-1)] {
		mut bad := request; bad.data.length = length
		assert !encode_volume_seal(&disk, &bad, &wrapping[0], &random[0], &output[0])
	}
	for value in output { assert value == 0xa1 }
}

fn test_volume_seal_commands_reject_syntax_before_input_or_device_access() {
	unsafe {
		mut args := [&char(c'vinix-volume'), &char(c'seal-volume'), &char(c'/unused'), &char(c'0'), &char(c'0'), &char(c'512'), &char(c'/unused'), &char(c'/unused'), &char(c'/unused'), &char(c'ro'), &char(nil)]!
		assert run(8, &args[0]) == 2 && run(11, &args[0]) == 2
		args[3] = &char(c'64'); assert run(9, &args[0]) == 2; args[3] = &char(c'0')
		args[5] = &char(c'0'); assert run(9, &args[0]) == 2; args[5] = &char(c'512')
		args[9] = &char(c'rw'); assert run(10, &args[0]) == 2
		for at in [2, 6, 7, 8] { args[at] = &char(c''); assert run(9, &args[0]) == 2; args[at] = &char(c'/unused') }
		args[1] = &char(c'open-volume'); args[3] = &char(c'/unused'); args[4] = &char(c'/unused')
		assert run(4, &args[0]) == 2 && run(7, &args[0]) == 2
		args[5] = &char(c'rw'); assert run(6, &args[0]) == 2
		for at in 2 .. 5 { args[at] = &char(c''); assert run(5, &args[0]) == 2; args[at] = &char(c'/unused') }
		args[1] = &char(c'unseal-volume-key'); assert run(4, &args[0]) == 2 && run(6, &args[0]) == 2
		for at in 2 .. 5 { args[at] = &char(c''); assert run(5, &args[0]) == 2; args[at] = &char(c'/unused') }
	}
}

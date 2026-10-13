// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

import os
import encoding.hex
import crypto.hmac
import crypto.sha256

fn test_volume_recovery_independent_crypto_exact_metadata_and_format_domains() {
	work := os.join_path(os.temp_dir(), 'vinix-volume-recovery-oracle-${os.getpid()}')
	os.mkdir(work)!; defer { os.rmdir_all(work) or {} }
	for sector in [u64(512), u64(4096)] {
		for kind in [u32(1), u32(2)] {
			for readonly in [u64(0), u64(1)] {
				mut disk := DiskKey{bytes: u64(-1) & ~u64(4095), sector: sector, kind: kind}; disk.id[0] = 0x87
				if kind == 2 { disk.id[15] = 0xa1 }
				request := EncryptedRequest{data: Request{slot: 63, offset: disk.bytes - 8192, length: 4096, flags: readonly}, key: [64]u8{init: u8(index * 13 + 7)}}
				mut recovery := [64]u8{init: u8(index * 29 + 41)}; nonce := [12]u8{init: u8(index * 11 + 3)}
				mut envelope := [320]u8{init: 0xc5}
				assert encode_volume_recovery(&disk, &request, &recovery[0], &nonce[0], &envelope[0])
				assert volume_recovery_header(&envelope[0], 320) && !volume_seal_header(&envelope[0], 320)
				message := recovery[..32].clone(); mut authenticated := message.clone(); authenticated << envelope[..288]
				assert envelope[288..] == hmac.new(recovery[32..], authenticated, sha256.sum256, 64)
				mut iv := []u8{len: 16}; iv[0] = 1; for i in 0 .. 12 { iv[i + 4] = nonce[i] }
				os.write_file_array(work + '/cipher', envelope[192..256])!
				result := os.exec(['openssl', 'enc', '-chacha20', '-K', hex.encode(recovery[..32]), '-iv', hex.encode(iv), '-in', work + '/cipher', '-out', work + '/key'])
				assert result.exit_code == 0, result.output
				assert os.read_bytes(work + '/key')! == request.key[..]
				mut observed := DiskKey{}; mut opened := EncryptedRequest{}
				assert decode_volume_recovery(&envelope[0], 320, &recovery[0], mut observed, mut opened)
				assert observed == disk && opened == request
				mut sealed := [320]u8{}; random := [28]u8{init: u8(index * 17 + 5)}
				assert encode_volume_seal(&observed, &opened, &recovery[0], &random[0], &sealed[0])
				assert !volume_recovery_header(&sealed[0], 320)
			}
		}
	}
}

fn test_volume_recovery_every_byte_and_both_recovery_halves_authenticate_before_release() {
	mut disk := DiskKey{bytes: 16777216, sector: 512, kind: 1}; disk.id[0] = 1
	request := EncryptedRequest{data: Request{slot: 5, offset: 1024, length: 4096, flags: 1}, key: [64]u8{init: u8(index * 13 + 7)}}
	recovery := [64]u8{init: u8(index * 29 + 41)}; nonce := [12]u8{init: u8(index + 3)}
	mut envelope := [320]u8{}; assert encode_volume_recovery(&disk, &request, &recovery[0], &nonce[0], &envelope[0])
	for at in 0 .. 320 {
		for bit in 0 .. 8 {
			mut damaged := envelope; damaged[at] ^= u8(1 << bit)
			mut observed := DiskKey{bytes: 123}; mut opened := EncryptedRequest{key: [64]u8{init: 0xc5}}
			before_disk := observed; before_request := opened
			assert !decode_volume_recovery(&damaged[0], 320, &recovery[0], mut observed, mut opened)
			assert observed == before_disk && opened == before_request
		}
	}
	for at in 0 .. 64 {
		mut wrong := recovery; wrong[at] ^= 1
		mut observed := DiskKey{}; mut opened := EncryptedRequest{key: [64]u8{init: 0xc5}}; before := opened
		assert !decode_volume_recovery(&envelope[0], 320, &wrong[0], mut observed, mut opened)
		assert opened == before && observed == DiskKey{}
	}
	for size in [0, 319, 321] { assert !volume_recovery_header(&envelope[0], size) }
	for variant in 0 .. 4 {
		mut output := [320]u8{init: 0xc5}; before := output
		mut invalid_disk := disk; mut invalid_request := request; mut invalid_recovery := recovery
		match variant {
			0 { invalid_request.data.length = u64(-1) }
			1 { invalid_disk.id[0] = 0 }
			2 { invalid_recovery = request.key }
			else { for i in 0 .. 32 { invalid_recovery[i + 32] = invalid_recovery[i] } }
		}
		assert !encode_volume_recovery(&invalid_disk, &invalid_request, &invalid_recovery[0], &nonce[0], &output[0]) && output == before
	}
}

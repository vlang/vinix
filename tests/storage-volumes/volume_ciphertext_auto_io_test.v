// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

import os

fn ciphertext_auto_check(input string, credential string, reference string, recovery bool, verify bool, physical int, mode int, fault int, sector u64, kind u32, expected i32) string {
	recovery_io = RecoveryIO{mode: fault}; volume_recovery_io = VolumeRecoveryIO{}
	recovery_growth_io = RecoveryGrowthIO{physical: physical, bytes: 16777216, sector: sector, kind: kind, readonly: true}
	ciphertext_io = CiphertextIO{mode: mode, verify: verify}; auto_scrub_calls = 0
	output := os.dir(input) + '/capture'; assert C.fflush(C.stdout) == 0
	saved := C.dup(1); fd := C.open(output.str, C.O_WRONLY | C.O_CREAT | C.O_TRUNC, u32(0o600))
	assert saved >= 0 && fd >= 0 && C.dup2(fd, 1) == 1 && C.close(fd) == 0
	unsafe {
		verb := if verify { if recovery { &char(c'verify-recovery-volume-auto') } else { &char(c'verify-volume-auto') } }
			else { if recovery { &char(c'hash-recovery-volume-auto') } else { &char(c'hash-volume-auto') } }
		args := [&char(c'vinix-volume'), verb, input.str, credential.str, reference.str, &char(nil)]!
		assert run(5, &args[0]) == expected
	}
	assert C.fflush(C.stdout) == 0 && C.dup2(saved, 1) == 1 && C.close(saved) == 0
	assert recovery_io.opened == recovery_io.closed && recovery_io.volume_wipes == 1 && !recovery_io.locked && !recovery_growth_io.parent_live && recovery_io.random == -1
	if verify { assert recovery_io.directory == -1 && recovery_io.writes == 0 && recovery_io.links == 0 && recovery_io.unlinks == 0 }
	text := os.read_file(output) or { panic(err) }; os.rm(output) or { panic(err) }
	if expected != 0 && fault !in [21, 33] { assert !text.contains('operation=') && !text.contains('sha256=') }; return text
}

fn test_automatic_ciphertext_creation_verification_erasure_pin_continuity_and_faults() {
	ciphertext_model = true; recovery_growth_model = true
	defer { ciphertext_model = false; recovery_growth_model = false; auto_scrub_refused = false; auto_scrub_pin_fault = 0 }
	work := os.join_path(os.temp_dir(), 'vinix-ciphertext-auto-${os.getpid()}'); os.mkdir(work)!; os.chmod(work, 0o700)!; defer { os.rmdir_all(work) or {} }
	input := work + '/input'; credential := work + '/credential'; reference := work + '/reference'
	wrapping := [64]u8{init: u8(index * 29 + 41)}; random := [28]u8{init: u8(index * 11 + 3)}; mut source := [320]u8{}
	data := []u8{len: 73728, init: ciphertext_pattern(u64(index) + 8192)}; digest := sha256.sum(data)
	for recovery in [false, true] { for sector in [u64(512), u64(4096)] { for kind in [u32(1), u32(2)] { for flags in [u64(0), u64(1)] {
		key := if recovery { wrapping[..] } else { [u8(0), 10, 0xe2, 0x82, 0xac, 0xff] }; os.write_file_array(credential, key)!; os.chmod(credential, 0o600)!
		mut disk := DiskKey{bytes: 16777216, sector: sector, kind: kind}; disk.id[0] = 1; if kind == 2 { disk.id[15] = 0x83 }
		request := EncryptedRequest{data: Request{slot: 63, offset: 8192, length: 73728, flags: flags}, key: [64]u8{init: u8(index * 13 + 7)}}
		assert if recovery { encode_volume_recovery(&disk, &request, &wrapping[0], &random[0], &source[0]) } else { encode_volume_seal(&disk, &request, &wrapping[0], &random[0], &source[0]) }
		os.write_file_array(input, source[..])!; os.chmod(input, 0o600)!; mut record := [128]u8{}
		assert encode_volume_ciphertext(&disk, &request.data, &digest[0], &record[0])
		for verify in [false, true] {
			if verify { os.write_file_array(reference, record[..])!; os.chmod(reference, 0o600)! }
			identity := if kind == 1 { 'mbr:00000001' } else { 'gpt:00000001-0000-0000-0000-000000000083' }
			expected := 'operation=${if verify { 'verified' } else { 'recorded' }}-ciphertext format=${if recovery { 'recovery' } else { 'volume' }} algorithm=sha256\ndisk_bytes=16777216 sector=${sector} identity=${identity} slot=63 offset=8192 bytes=73728 readonly=${flags} sha256=' + hex.encode(digest[..]) + '\n'
			assert ciphertext_auto_check(input, credential, reference, recovery, verify, 0, 0, 0, sector, kind, 0) == expected
			assert auto_scrub_calls == 1 && recovery_growth_io.parent_opens == 1 && ciphertext_io.delivered == 73728 && os.read_bytes(reference)! == record[..]
			if !verify { os.rm(reference)! }
			for physical in 0 .. 30 {
				ciphertext_auto_check(input, credential, reference, recovery, verify, physical, 0, 0, sector, kind, if physical <= 1 { 0 } else { 1 })
				if !verify && os.exists(reference) { os.rm(reference)! }
			}
			for mode in 0 .. 12 {
				code := if mode in [0, 1] || (!verify && mode in [6, 7]) || (verify && mode == 11) { 0 } else { 1 }
				ciphertext_auto_check(input, credential, reference, recovery, verify, 0, mode, 0, sector, kind, code)
				if mode in [6, 7] { assert ciphertext_io.delivered == 73728 }
				if !verify && mode in [6, 7] {
					mut altered := data.clone(); altered[if mode == 6 { 0 } else { 65536 }] ^= 1
					observed := sha256.sum(altered); mut expected_record := [128]u8{}
					assert encode_volume_ciphertext(&disk, &request.data, &observed[0], &expected_record[0]) && os.read_bytes(reference)! == expected_record[..]
				}
				if !verify && os.exists(reference) { os.rm(reference)! }
			}
			for fault in [0, 1, 2, 3, 4, 5, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 32, 33] {
				code := if fault <= 1 || (verify && fault >= 9 && fault <= 20) { 0 } else { 1 }
				ciphertext_auto_check(input, credential, reference, recovery, verify, 0, 0, fault, sector, kind, code)
				if !verify && os.exists(reference) { assert os.read_bytes(reference)! == record[..]; os.rm(reference)! }
			}
			for fault in [1, 2] { auto_scrub_pin_fault = fault; ciphertext_auto_check(input, credential, reference, recovery, verify, 0, 0, 0, sector, kind, 1); assert auto_scrub_calls == 1 }; auto_scrub_pin_fault = 0
			auto_scrub_refused = true; ciphertext_auto_check(input, credential, reference, recovery, verify, 0, 0, 0, sector, kind, 1); assert auto_scrub_calls == 1 && recovery_growth_io.parent_opens == 0; auto_scrub_refused = false
			if verify { os.rm(reference)! }
		}
		os.write_file_array(reference, record[..])!; os.chmod(reference, 0o600)!
		for at in [0, 16, 32, 36, 40, 48, 56, 64, 112] {
			mut bad := record; bad[at] ^= 1; put_le(&bad[0], 124, 4, crc32(&bad[0], 128, 124)); os.write_file_array(reference, bad[..])!
			ciphertext_auto_check(input, credential, reference, recovery, true, 0, 0, 0, sector, kind, 1); assert auto_scrub_calls == 0
		}; os.write_file_array(reference, record[..])!
		mut different := record; different[80] ^= 1; put_le(&different[0], 124, 4, crc32(&different[0], 128, 124)); os.write_file_array(reference, different[..])!
		ciphertext_auto_check(input, credential, reference, recovery, true, 0, 0, 0, sector, kind, 1); assert auto_scrub_calls == 1 && ciphertext_io.delivered == 73728; os.write_file_array(reference, record[..])!
		for path in [input, credential, reference] {
			os.chmod(path, 0o644)!; ciphertext_auto_check(input, credential, reference, recovery, true, 0, 0, 0, sector, kind, 1); assert auto_scrub_calls == 0; os.chmod(path, 0o600)!
			os.mv(path, path + '.saved')!; os.symlink(path + '.saved', path)!; ciphertext_auto_check(input, credential, reference, recovery, true, 0, 0, 0, sector, kind, 1); assert auto_scrub_calls == 0; os.rm(path)!; os.mv(path + '.saved', path)!
		}
		for destination in [input, credential, reference] { ciphertext_auto_check(input, credential, destination, recovery, false, 0, 0, 0, sector, kind, 1) }
		mut wrong := key.clone(); wrong[if recovery { 0 } else { 5 }] ^= 1; os.write_file_array(credential, wrong)!
		for verify in [false, true] { ciphertext_auto_check(input, credential, reference, recovery, verify, 0, 0, 0, sector, kind, 1); assert auto_scrub_calls == 0 }; os.write_file_array(credential, key)!
		if !recovery { for fault in [23, 24, 25] { ciphertext_auto_check(input, credential, reference, recovery, true, 0, 0, fault, sector, kind, 1); assert auto_scrub_calls == 0 } }
		assert os.read_bytes(input)! == source[..] && os.read_bytes(credential)! == key && os.read_bytes(reference)! == record[..]; os.rm(reference)!
	} } } }
}

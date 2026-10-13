// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module volumecli

import os

__global volume_scrub_model bool
__global volume_scrub_offline bool

fn volume_scrub_report_ready() {
	if volume_scrub_offline {
		assert !recovery_growth_io.parent_live && recovery_growth_io.parent_opens == 0 && recovery_growth_io.statuses == 0
		assert recovery_io.directory == -1 && !recovery_io.locked && recovery_io.writes == 0 && recovery_io.links == 0 && recovery_io.unlinks == 0
	} else { ciphertext_report_ready() }
}

fn volume_scrub_mock_report(bytes &u8, disk &DiskKey, row &Request) bool {
	volume_scrub_report_ready()
	if recovery_io.mode == 32 { return false }
	return show_volume_ciphertext_scrub(bytes, disk, row)
}

fn volume_scrub_expected(reference []u8, sector u64, kind u32, flags u64, mode int) string {
	mut data := []u8{len: 73728, init: ciphertext_pattern(u64(index) + 8192)}
	if mode == 6 { data[0] ^= 1 }; if mode == 7 { data[65536] ^= 1 }
	digest := sha256.sum(data); changed := mode in [6, 7]
	identity := if kind == 1 { 'mbr:00000001' } else { 'gpt:00000001-0000-0000-0000-000000000083' }
	return 'format=VINIXCS1 operation=scrubbed-ciphertext mappings=1 matched=${int(!changed)} changed=${int(changed)} algorithm=sha256 reference_sha256=' + hex.encode(sha256.sum(reference)[..])
		+ '\ndisk_bytes=16777216 sector=${sector} identity=${identity} slot=63 offset=8192 bytes=73728 readonly=${flags} result=${if changed { 'changed' } else { 'match' }} expected_sha256=' + hex.encode(reference[80..112]) + ' actual_sha256=' + hex.encode(digest[..]) + '\n'
}

fn volume_scrub_check(input string, credential string, reference string, report string, recovery bool, offline bool, physical int, data_mode int, fault int, sector u64, kind u32, expected i32) string {
	recovery_io = RecoveryIO{mode: fault}; volume_recovery_io = VolumeRecoveryIO{}
	recovery_growth_io = RecoveryGrowthIO{physical: physical, bytes: 16777216, sector: sector, kind: kind, readonly: true}
	ciphertext_io = CiphertextIO{mode: data_mode}; volume_scrub_offline = offline
	output := os.dir(input) + '/capture'; assert C.fflush(C.stdout) == 0
	saved := C.dup(1); fd := C.open(output.str, C.O_WRONLY | C.O_CREAT | C.O_TRUNC, u32(0o600))
	assert saved >= 0 && fd >= 0 && C.dup2(fd, 1) == 1 && C.close(fd) == 0
	unsafe {
		if offline { args := [&char(c'vinix-volume'), &char(c'show-volume-scrub'), report.str, &char(nil)]!; assert run(3, &args[0]) == expected }
		else {
			args := [&char(c'vinix-volume'), if recovery { &char(c'scrub-recovery-volume') } else { &char(c'scrub-volume') }, &char(c'/recovery-growth-parent'), input.str, credential.str, reference.str, report.str, &char(nil)]!
			assert run(7, &args[0]) == expected
		}
	}
	assert C.fflush(C.stdout) == 0 && C.dup2(saved, 1) == 1 && C.close(saved) == 0
	assert recovery_io.opened == recovery_io.closed && recovery_io.volume_wipes == if offline { 0 } else { 1 }
	assert !recovery_io.locked && !recovery_growth_io.parent_live && recovery_io.random == -1
	assert volume_recovery_io.derives <= if recovery || offline { 0 } else { 1 }
	text := os.read_file(output) or { panic(err) }; os.rm(output) or { panic(err) }
	if expected == 1 && fault !in [21, 33] { assert !text.contains('operation=') && !text.contains('actual_sha256=') }
	return text
}

fn test_ciphertext_scrub_complete_clean_changed_reports_operational_precedence_and_offline_private_view() {
	volume_scrub_model = true; ciphertext_model = true; recovery_growth_model = true
	defer { volume_scrub_model = false; volume_scrub_offline = false; ciphertext_model = false; recovery_growth_model = false }
	work := os.join_path(os.temp_dir(), 'vinix-ciphertext-scrub-${os.getpid()}'); os.mkdir(work)!; os.chmod(work, 0o700)!; defer { os.rmdir_all(work) or {} }
	input := work + '/input'; credential := work + '/credential'; reference := work + '/reference'; report := work + '/report'
	wrapping := [64]u8{init: u8(index * 29 + 41)}; random := [28]u8{init: u8(index * 11 + 3)}; mut source := [320]u8{}
	data := []u8{len: 73728, init: ciphertext_pattern(u64(index) + 8192)}; digest := sha256.sum(data)
	for recovery in [false, true] { for sector in [u64(512), u64(4096)] { for kind in [u32(1), u32(2)] { for flags in [u64(0), u64(1)] {
		key_bytes := if recovery { wrapping[..] } else { [u8(0), 10, 0xe2, 0x82, 0xac, 0xff] }; os.write_file_array(credential, key_bytes)!; os.chmod(credential, 0o600)!
		mut disk := DiskKey{bytes: 16777216, sector: sector, kind: kind}; disk.id[0] = 1; if kind == 2 { disk.id[15] = 0x83 }
		request := EncryptedRequest{data: Request{slot: 63, offset: 8192, length: 73728, flags: flags}, key: [64]u8{init: u8(index * 13 + 7)}}
		assert if recovery { encode_volume_recovery(&disk, &request, &wrapping[0], &random[0], &source[0]) } else { encode_volume_seal(&disk, &request, &wrapping[0], &random[0], &source[0]) }
		os.write_file_array(input, source[..])!; os.chmod(input, 0o600)!
		mut saved := [128]u8{}; assert encode_volume_ciphertext(&disk, &request.data, &digest[0], &saved[0]); os.write_file_array(reference, saved[..])!; os.chmod(reference, 0o600)!
		for mode in [0, 1, 6, 7] {
			expected := volume_scrub_expected(saved[..], sector, kind, flags, mode)
			assert volume_scrub_check(input, credential, reference, report, recovery, false, 0, mode, 0, sector, kind, if mode >= 6 { 2 } else { 0 }) == expected
			assert ciphertext_io.delivered == 73728 && recovery_growth_io.statuses == 5
			bytes := os.read_bytes(report)!; assert bytes.len == 224 && os.stat(report)!.mode & 0o777 == 0o600
			assert volume_scrub_check(input, credential, reference, report, recovery, true, 0, 0, 0, sector, kind, 0) == expected
			assert volume_scrub_check(input, credential, reference, report, recovery, false, 0, mode, 0, sector, kind, 1) == '' && os.read_bytes(report)! == bytes
			for fault in [21, 32, 33] { volume_scrub_check(input, credential, reference, report, recovery, true, 0, 0, fault, sector, kind, 1); assert os.read_bytes(report)! == bytes }
			os.rm(report)!
		}
		for physical in 0 .. 30 {
			volume_scrub_check(input, credential, reference, report, recovery, false, physical, 0, 0, sector, kind, if physical <= 1 { 0 } else { 1 })
			assert os.exists(report) == (physical <= 1); if os.exists(report) { os.rm(report)! }
		}
		for mode in [2, 3, 4, 5, 8, 9, 10, 11] {
			volume_scrub_check(input, credential, reference, report, recovery, false, 0, mode, 0, sector, kind, 1); assert !os.exists(report)
			os.write_file(report, 'preserve prior report')!; volume_scrub_check(input, credential, reference, report, recovery, false, 0, mode, 0, sector, kind, 1)
			assert os.read_file(report)! == 'preserve prior report'; os.rm(report)!
		}
		for changed in [false, true] { for fault in [0, 1, 2, 3, 4, 5, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 32, 33] {
			volume_scrub_check(input, credential, reference, report, recovery, false, 0, if changed { 6 } else { 0 }, fault, sector, kind,
				if fault <= 1 { if changed { 2 } else { 0 } } else { 1 })
			assert os.exists(report) == (fault <= 1 || fault in [19, 20, 21, 32, 33])
			if os.exists(report) { assert volume_scrub_check(input, credential, reference, report, recovery, true, 0, 0, 0, sector, kind, 0) == volume_scrub_expected(saved[..], sector, kind, flags, if changed { 6 } else { 0 }); os.rm(report)! }
			assert os.ls(work)!.all(!it.starts_with('.vinix-key-'))
		} }
		for path in [input, credential, reference] {
			os.chmod(path, 0o644)!; volume_scrub_check(input, credential, reference, report, recovery, false, 0, 0, 0, sector, kind, 1); assert recovery_growth_io.parent_opens == 0; os.chmod(path, 0o600)!
			os.mv(path, path + '.saved')!; os.symlink(path + '.saved', path)!
			volume_scrub_check(input, credential, reference, report, recovery, false, 0, 0, 0, sector, kind, 1); assert recovery_growth_io.parent_opens == 0; os.rm(path)!; os.mv(path + '.saved', path)!
			original := os.read_bytes(path)!
			for length in if path == credential && !recovery { [0, 1025] } else { [original.len - 1, original.len + 1] } {
				mut bad := []u8{len: length}; copy(mut bad, original); os.write_file_array(path, bad)!
				volume_scrub_check(input, credential, reference, report, recovery, false, 0, 0, 0, sector, kind, 1); assert recovery_growth_io.parent_opens == 0
			}; os.write_file_array(path, original)!
		}
		for destination in [input, credential, reference, work + '/link'] {
			if destination.ends_with('/link') { os.symlink(work + '/absent', destination)! }
			volume_scrub_check(input, credential, reference, destination, recovery, false, 0, 6, 0, sector, kind, 1)
		}
		os.rm(work + '/link')!
		if !recovery { for fault in [23, 24, 25] { volume_scrub_check(input, credential, reference, report, recovery, false, 0, 0, fault, sector, kind, 1); assert recovery_growth_io.parent_opens == 0 } }
		for at in [0, 24, 104, 192, 288] {
			mut bad := source; bad[at] ^= 1; os.write_file_array(input, bad[..])!
			volume_scrub_check(input, credential, reference, report, recovery, false, 0, 0, 0, sector, kind, 1); assert recovery_growth_io.parent_opens == 0
		}; os.write_file_array(input, source[..])!
		mut wrong_credential := key_bytes.clone(); wrong_credential[if recovery { 0 } else { 5 }] ^= 1; os.write_file_array(credential, wrong_credential)!
		volume_scrub_check(input, credential, reference, report, recovery, false, 0, 0, 0, sector, kind, 1); assert recovery_growth_io.parent_opens == 0; os.write_file_array(credential, key_bytes)!
		for at in [0, 16, 32, 36, 40, 48, 56, 64, 112] {
			mut bad := saved; bad[at] ^= 1; put_le(&bad[0], 124, 4, crc32(&bad[0], 128, 124)); os.write_file_array(reference, bad[..])!
			volume_scrub_check(input, credential, reference, report, recovery, false, 0, 0, 0, sector, kind, 1); assert recovery_growth_io.parent_opens == 0
		}
		os.write_file_array(reference, saved[..])!
		volume_scrub_check(input, credential, reference, report, recovery, false, 0, 6, 0, sector, kind, 2); original := os.read_bytes(report)!
		for at in [0, 16, 20, 24, 32, 192] {
			mut bad := original.clone(); bad[at] ^= 1; put_le(bad.data, 28, 4, crc32(bad.data, 224, 28)); os.write_file_array(report, bad)!
			volume_scrub_check(input, credential, reference, report, recovery, true, 0, 0, 0, sector, kind, 1)
		}
		mut inconsistent := original.clone(); for i in 0 .. 32 { inconsistent[160 + i] = saved[80 + i] }
		put_le(inconsistent.data, 28, 4, crc32(inconsistent.data, 224, 28)); os.write_file_array(report, inconsistent)!
		volume_scrub_check(input, credential, reference, report, recovery, true, 0, 0, 0, sector, kind, 1)
		os.write_file_array(report, original)!
		for length in [223, 225] { mut bad := []u8{len: length}; copy(mut bad, original); os.write_file_array(report, bad)!; volume_scrub_check(input, credential, reference, report, recovery, true, 0, 0, 0, sector, kind, 1) }
		os.write_file_array(report, original)!; os.chmod(report, 0o644)!; volume_scrub_check(input, credential, reference, report, recovery, true, 0, 0, 0, sector, kind, 1); os.chmod(report, 0o600)!
		os.mv(report, report + '.saved')!; os.symlink(report + '.saved', report)!; volume_scrub_check(input, credential, reference, report, recovery, true, 0, 0, 0, sector, kind, 1); os.rm(report)!; os.mv(report + '.saved', report)!
		assert os.read_bytes(input)! == source[..] && os.read_bytes(credential)! == key_bytes && os.read_bytes(reference)! == saved[..] && os.read_bytes(report)! == original
		os.rm(report)!
	} } } }
}

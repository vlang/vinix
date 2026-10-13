// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module volumecli

import os

__global auto_scrub_calls int
__global auto_scrub_refused bool
__global auto_scrub_pin_fault int

// The discovery boundary is injected here; the separate existing discovery
// model executes the complete real bounded scan, alias and ambiguity paths.
fn auto_scrub_mock_discover(disk &DiskKey, directory &char, writable bool, name &char, mut status Status) i32 {
	recovery_growth_erased(); auto_scrub_calls++
	assert C.strcmp(directory, c'/dev') == 0 && !writable && disk.bytes == 16777216
	if auto_scrub_refused { return -1 }
	status = Status{version: 1, bytes: disk.bytes, sector: disk.sector, disk_id: 7, flags: 5}
	if auto_scrub_pin_fault == 1 { status.disk_id++ }; if auto_scrub_pin_fault == 2 { status.flags ^= 1 }
	return recovery_mock_open(c'/recovery-growth-parent', C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK)
}

fn auto_scrub_check(input string, credential string, reference string, report string, recovery bool, mode int, fault int, sector u64, kind u32, expected i32) string {
	recovery_io = RecoveryIO{mode: fault}; volume_recovery_io = VolumeRecoveryIO{}
	recovery_growth_io = RecoveryGrowthIO{bytes: 16777216, sector: sector, kind: kind, readonly: true}; ciphertext_io = CiphertextIO{mode: mode}
	auto_scrub_calls = 0; output := os.dir(input) + '/capture'; assert C.fflush(C.stdout) == 0
	saved := C.dup(1); fd := C.open(output.str, C.O_WRONLY | C.O_CREAT | C.O_TRUNC, u32(0o600))
	assert saved >= 0 && fd >= 0 && C.dup2(fd, 1) == 1 && C.close(fd) == 0
	unsafe {
		args := [&char(c'vinix-volume'), if recovery { &char(c'scrub-recovery-volume-auto') } else { &char(c'scrub-volume-auto') }, input.str, credential.str, reference.str, report.str, &char(nil)]!
		assert run(6, &args[0]) == expected
	}
	assert C.fflush(C.stdout) == 0 && C.dup2(saved, 1) == 1 && C.close(saved) == 0
	assert recovery_io.opened == recovery_io.closed && recovery_io.volume_wipes == 1 && !recovery_io.locked && !recovery_growth_io.parent_live
	text := os.read_file(output) or { panic(err) }; os.rm(output) or { panic(err) }; return text
}

fn test_automatic_scrub_authentication_reference_before_discovery_and_pinned_complete_scan() {
	volume_scrub_model = true; ciphertext_model = true; recovery_growth_model = true
	defer { volume_scrub_model = false; ciphertext_model = false; recovery_growth_model = false; auto_scrub_refused = false }
	work := os.join_path(os.temp_dir(), 'vinix-auto-scrub-${os.getpid()}'); os.mkdir(work)!; os.chmod(work, 0o700)!; defer { os.rmdir_all(work) or {} }
	input := work + '/input'; credential := work + '/credential'; reference := work + '/reference'; report := work + '/report'
	wrapping := [64]u8{init: u8(index * 29 + 41)}; random := [28]u8{init: u8(index * 11 + 3)}; mut source := [320]u8{}
	data := []u8{len: 73728, init: ciphertext_pattern(u64(index) + 8192)}; digest := sha256.sum(data)
	for recovery in [false, true] { for sector in [u64(512), u64(4096)] { for kind in [u32(1), u32(2)] { for flags in [u64(0), u64(1)] {
		key := if recovery { wrapping[..] } else { [u8(0), 10, 0xe2, 0x82, 0xac, 0xff] }; os.write_file_array(credential, key)!; os.chmod(credential, 0o600)!
		mut disk := DiskKey{bytes: 16777216, sector: sector, kind: kind}; disk.id[0] = 1; if kind == 2 { disk.id[15] = 0x83 }
		request := EncryptedRequest{data: Request{slot: 63, offset: 8192, length: 73728, flags: flags}, key: [64]u8{init: u8(index * 13 + 7)}}
		assert if recovery { encode_volume_recovery(&disk, &request, &wrapping[0], &random[0], &source[0]) } else { encode_volume_seal(&disk, &request, &wrapping[0], &random[0], &source[0]) }
		os.write_file_array(input, source[..])!; os.chmod(input, 0o600)!; mut saved := [128]u8{}
		assert encode_volume_ciphertext(&disk, &request.data, &digest[0], &saved[0]); os.write_file_array(reference, saved[..])!; os.chmod(reference, 0o600)!
		for mode in [0, 1, 6, 7] {
			assert auto_scrub_check(input, credential, reference, report, recovery, mode, 0, sector, kind, if mode >= 6 { 2 } else { 0 }) == volume_scrub_expected(saved[..], sector, kind, flags, mode)
			assert auto_scrub_calls == 1 && recovery_growth_io.parent_opens == 1 && recovery_growth_io.statuses == 5 && ciphertext_io.delivered == 73728
			bytes := os.read_bytes(report)!; assert volume_scrub_check(input, credential, reference, report, recovery, true, 0, 0, 0, sector, kind, 0) == volume_scrub_expected(saved[..], sector, kind, flags, mode)
			volume_scrub_offline = false; os.rm(report)!
			for fault in [2, 3, 4, 5, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 32, 33] {
				auto_scrub_check(input, credential, reference, report, recovery, mode, fault, sector, kind, 1)
				if os.exists(report) { assert os.read_bytes(report)! == bytes; os.rm(report)! }
			}
		}
		for mode in [2, 3, 4, 5, 8, 9, 10, 11] { auto_scrub_check(input, credential, reference, report, recovery, mode, 0, sector, kind, 1); assert auto_scrub_calls == 1 && !os.exists(report) }
		auto_scrub_refused = true; auto_scrub_check(input, credential, reference, report, recovery, 0, 0, sector, kind, 1); assert auto_scrub_calls == 1 && recovery_growth_io.parent_opens == 0; auto_scrub_refused = false
		for fault in [1, 2] { auto_scrub_pin_fault = fault; auto_scrub_check(input, credential, reference, report, recovery, 0, 0, sector, kind, 1); assert auto_scrub_calls == 1 && !os.exists(report) }; auto_scrub_pin_fault = 0
		for path in [input, credential, reference] {
			os.chmod(path, 0o644)!; auto_scrub_check(input, credential, reference, report, recovery, 0, 0, sector, kind, 1); assert auto_scrub_calls == 0; os.chmod(path, 0o600)!
		}
		mut bad := saved; bad[56] ^= 1; put_le(&bad[0], 124, 4, crc32(&bad[0], 128, 124)); os.write_file_array(reference, bad[..])!
		auto_scrub_check(input, credential, reference, report, recovery, 0, 0, sector, kind, 1); assert auto_scrub_calls == 0; os.write_file_array(reference, saved[..])!
		mut wrong := key.clone(); wrong[if recovery { 0 } else { 5 }] ^= 1; os.write_file_array(credential, wrong)!
		auto_scrub_check(input, credential, reference, report, recovery, 0, 0, sector, kind, 1); assert auto_scrub_calls == 0; os.write_file_array(credential, key)!
		if !recovery { for fault in [23, 24, 25] { auto_scrub_check(input, credential, reference, report, recovery, 0, fault, sector, kind, 1); assert auto_scrub_calls == 0 } }
		assert os.read_bytes(input)! == source[..] && os.read_bytes(reference)! == saved[..]
	} } } }
}

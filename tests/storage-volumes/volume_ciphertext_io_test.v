// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module volumecli

import os
import crypto.sha256
import encoding.hex

struct CiphertextIO {
mut:
	mode int
	verify bool
	reads int
	delivered u64
	interrupted bool
}
__global ciphertext_model bool
__global ciphertext_io CiphertextIO

fn ciphertext_report_ready() {
	recovery_growth_erased()
	assert recovery_growth_io.parent_live && recovery_growth_io.statuses == if ciphertext_io.verify { 4 } else { 5 }
	assert recovery_io.locked == !ciphertext_io.verify
}

fn ciphertext_mock_report(disk &DiskKey, row &Request, digest &u8, recovery bool, verify bool) bool {
	ciphertext_report_ready(); assert verify == ciphertext_io.verify
	if recovery_io.mode == 32 { return false }
	return show_volume_ciphertext(disk, row, digest, recovery, verify)
}

fn ciphertext_dispatch_ioctl(fd i32, number u64, output voidptr) i32 {
	result := recovery_growth_mock_ioctl(fd, number, output)
	if ciphertext_model && result == 0 && ((recovery_growth_io.statuses == 4 && ciphertext_io.mode in [8, 9, 10])
		|| (recovery_growth_io.statuses == 5 && ciphertext_io.mode == 11)) {
		unsafe {
			status := &Status(output)
			if ciphertext_io.mode == 9 { status.bytes += status.sector }
			else if ciphertext_io.mode == 10 { status.flags ^= 1 }
			else { status.disk_id++ }
		}
	}
	return result
}

fn ciphertext_pattern(offset u64) u8 { return u8(offset * 13 + (offset >> 7)) }

fn ciphertext_dispatch_pread(fd i32, output voidptr, size usize, offset i64) i64 {
	if !ciphertext_model || offset == 0 { return recovery_growth_mock_pread(fd, output, size, offset) }
	recovery_growth_erased()
	assert fd == 900 && recovery_growth_io.parent_live && recovery_growth_io.statuses == 3
	sector := recovery_growth_io.sector
	assert offset >= 8192 && size > 0 && size <= 65536 && u64(offset) % sector == 0 && u64(size) % sector == 0
	ciphertext_io.reads++; mode := ciphertext_io.mode
	if mode == 1 && !ciphertext_io.interrupted { ciphertext_io.interrupted = true; unsafe { C.errno = C.EINTR }; return -1 }
	if mode == 2 { return 0 }
	if mode == 3 { unsafe { C.errno = C.EIO }; return -1 }
	if mode == 4 { return i64(size + 1) }
	if mode == 5 { return i64(size - 1) }
	delivered := if mode == 1 && size > usize(sector) { usize(sector) } else { size }
	unsafe {
		for i in 0 .. int(delivered) { (&u8(output))[i] = ciphertext_pattern(u64(offset) + u64(i)) }
		if (mode == 6 && offset == 8192) || (mode == 7 && offset == 73728) { (&u8(output))[0] ^= 1 }
	}
	ciphertext_io.delivered += u64(delivered); return i64(delivered)
}

fn ciphertext_check(input string, credential string, reference string, recovery bool, verify bool, physical int, data_mode int, fault int, sector u64, kind u32, physical_readonly bool, expected i32) string {
	recovery_io = RecoveryIO{mode: fault}; volume_recovery_io = VolumeRecoveryIO{}
	recovery_growth_io = RecoveryGrowthIO{physical: physical, bytes: 16777216, sector: sector, kind: kind, readonly: physical_readonly}
	ciphertext_io = CiphertextIO{mode: data_mode, verify: verify}
	output := os.dir(input) + '/capture'; assert C.fflush(C.stdout) == 0
	saved := C.dup(1); fd := C.open(output.str, C.O_WRONLY | C.O_CREAT | C.O_TRUNC, u32(0o600))
	assert saved >= 0 && fd >= 0 && C.dup2(fd, 1) == 1 && C.close(fd) == 0
	unsafe {
		verb := if verify { if recovery { &char(c'verify-recovery-volume') } else { &char(c'verify-volume') } }
			else { if recovery { &char(c'hash-recovery-volume') } else { &char(c'hash-volume') } }
		args := [&char(c'vinix-volume'), verb, &char(c'/recovery-growth-parent'), input.str, credential.str, reference.str, &char(nil)]!
		assert run(6, &args[0]) == expected
	}
	assert C.fflush(C.stdout) == 0 && C.dup2(saved, 1) == 1 && C.close(saved) == 0
	assert recovery_io.opened == recovery_io.closed && recovery_io.volume_wipes == 1 && !recovery_io.locked && !recovery_growth_io.parent_live
	assert recovery_io.random == -1 && volume_recovery_io.derives <= if recovery { 0 } else { 1 }
	if expected == 0 { assert volume_recovery_io.derives == if recovery { 0 } else { 1 } }
	if verify { assert recovery_io.directory == -1 && recovery_io.writes == 0 && recovery_io.links == 0 && recovery_io.unlinks == 0 }
	text := os.read_file(output) or { panic(err) }; os.rm(output) or { panic(err) }
	if expected != 0 && fault !in [21, 33] { assert !text.contains('operation=') && !text.contains('sha256=') }
	return text
}

fn test_ciphertext_authentication_streaming_reference_geometry_corruption_and_publication_cleanup() {
	ciphertext_model = true; recovery_growth_model = true
	defer { ciphertext_model = false; recovery_growth_model = false }
	work := os.join_path(os.temp_dir(), 'vinix-ciphertext-${os.getpid()}'); os.mkdir(work)!; os.chmod(work, 0o700)!; defer { os.rmdir_all(work) or {} }
	input := work + '/input'; credential := work + '/credential'; reference := work + '/reference'
	wrapping := [64]u8{init: u8(index * 29 + 41)}; random := [28]u8{init: u8(index * 11 + 3)}; mut source := [320]u8{}
	data := []u8{len: 73728, init: ciphertext_pattern(u64(index) + 8192)}; sum := sha256.sum(data)
	for recovery in [false, true] { for sector in [u64(512), u64(4096)] { for kind in [u32(1), u32(2)] { for flags in [u64(0), u64(1)] {
		key_bytes := if recovery { wrapping[..] } else { [u8(0), 10, 0xe2, 0x82, 0xac, 0xff] }; os.write_file_array(credential, key_bytes)!; os.chmod(credential, 0o600)!
		mut disk := DiskKey{bytes: 16777216, sector: sector, kind: kind}; disk.id[0] = 1; if kind == 2 { disk.id[15] = 0x83 }
		request := EncryptedRequest{data: Request{slot: 63, offset: 8192, length: 73728, flags: flags}, key: [64]u8{init: u8(index * 13 + 7)}}
		assert if recovery { encode_volume_recovery(&disk, &request, &wrapping[0], &random[0], &source[0]) } else { encode_volume_seal(&disk, &request, &wrapping[0], &random[0], &source[0]) }
		os.write_file_array(input, source[..])!; os.chmod(input, 0o600)!
		mut record := [128]u8{}; assert encode_volume_ciphertext(&disk, &request.data, &sum[0], &record[0])
		for verify in [false, true] {
			if verify { os.write_file_array(reference, record[..])!; os.chmod(reference, 0o600)! }
			text := ciphertext_check(input, credential, reference, recovery, verify, 0, 0, 0, sector, kind, flags == 0, 0)
			identity := if kind == 1 { 'mbr:00000001' } else { 'gpt:00000001-0000-0000-0000-000000000083' }
			assert text == 'operation=${if verify { 'verified' } else { 'recorded' }}-ciphertext format=${if recovery { 'recovery' } else { 'volume' }} algorithm=sha256\ndisk_bytes=16777216 sector=${sector} identity=${identity} slot=63 offset=8192 bytes=73728 readonly=${flags} sha256=' + hex.encode(sum[..]) + '\n'
			assert os.read_bytes(reference)! == record[..] && ciphertext_io.delivered == 73728
			if !verify { os.rm(reference)! }
			for physical in 0 .. 30 {
				ciphertext_check(input, credential, reference, recovery, verify, physical, 0, 0, sector, kind, false, if physical <= 1 { 0 } else { 1 })
				if !verify && os.exists(reference) { os.rm(reference)! }
			}
			for mode in 0 .. 12 {
				status := if mode in [0, 1] || (!verify && mode in [6, 7]) || (verify && mode == 11) { 0 } else { 1 }
				ciphertext_check(input, credential, reference, recovery, verify, 0, mode, 0, sector, kind, false, status)
				if !verify && os.exists(reference) { os.rm(reference)! }
			}
			for fault in [0, 1, 2, 3, 4, 5, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 32, 33] {
				status := if fault <= 1 || (verify && fault >= 9 && fault <= 20) { 0 } else { 1 }
				ciphertext_check(input, credential, reference, recovery, verify, 0, 0, fault, sector, kind, false, status)
				if !verify && os.exists(reference) { assert os.read_bytes(reference)! == record[..]; os.rm(reference)! }
				assert os.ls(work)!.all(!it.starts_with('.vinix-key-'))
			}
			if verify { os.rm(reference)! }
		}
		os.write_file_array(reference, record[..])!; os.chmod(reference, 0o600)!
		for at in [0, 16, 32, 36, 40, 48, 56, 64, 112] {
			mut bad := record; bad[at] ^= 1; put_le(&bad[0], 124, 4, crc32(&bad[0], 128, 124)); os.write_file_array(reference, bad[..])!
			ciphertext_check(input, credential, reference, recovery, true, 0, 0, 0, sector, kind, false, 1); assert recovery_growth_io.parent_opens == 0
		}
		mut bad := record; bad[80] ^= 1; put_le(&bad[0], 124, 4, crc32(&bad[0], 128, 124)); os.write_file_array(reference, bad[..])!
		ciphertext_check(input, credential, reference, recovery, true, 0, 0, 0, sector, kind, false, 1); assert ciphertext_io.delivered == 73728
		os.write_file_array(reference, record[..])!
		for path in [input, credential, reference] {
			os.chmod(path, 0o644)!; ciphertext_check(input, credential, reference, recovery, true, 0, 0, 0, sector, kind, false, 1); assert recovery_growth_io.parent_opens == 0; os.chmod(path, 0o600)!
			os.mv(path, path + '.saved')!; os.symlink(path + '.saved', path)!
			ciphertext_check(input, credential, reference, recovery, true, 0, 0, 0, sector, kind, false, 1); assert recovery_growth_io.parent_opens == 0
			os.rm(path)!; os.mv(path + '.saved', path)!
			original := os.read_bytes(path)!
			for length in if path == credential && !recovery { [0, 1025] } else { [original.len - 1, original.len + 1] } {
				mut wrong_size := []u8{len: length}; copy(mut wrong_size, original); os.write_file_array(path, wrong_size)!
				ciphertext_check(input, credential, reference, recovery, true, 0, 0, 0, sector, kind, false, 1); assert recovery_growth_io.parent_opens == 0
			}
			os.write_file_array(path, original)!
		}
		for destination in [input, credential, reference] { ciphertext_check(input, credential, destination, recovery, false, 0, 0, 0, sector, kind, false, 1) }
		if !recovery { for fault in [23, 24, 25] {
			ciphertext_check(input, credential, reference, false, true, 0, 0, fault, sector, kind, false, 1); assert recovery_growth_io.parent_opens == 0
		} }
		for at in [0, 24, 104, 192, 288] {
			mut damaged := source; damaged[at] ^= 1; os.write_file_array(input, damaged[..])!
			ciphertext_check(input, credential, reference, recovery, true, 0, 0, 0, sector, kind, false, 1); assert recovery_growth_io.parent_opens == 0
		}
		os.write_file_array(input, source[..])!
		if recovery {
			mut wrong_key := wrapping; wrong_key[0] ^= 1; os.write_file_array(credential, wrong_key[..])!
			ciphertext_check(input, credential, reference, true, true, 0, 0, 0, sector, kind, false, 1); assert recovery_growth_io.parent_opens == 0
			os.write_file_array(credential, key_bytes)!
		} else {
			mut wrong_password := key_bytes.clone(); wrong_password[5] ^= 1; os.write_file_array(credential, wrong_password)!
			ciphertext_check(input, credential, reference, false, true, 0, 0, 0, sector, kind, false, 1); assert recovery_growth_io.parent_opens == 0
			os.write_file_array(credential, key_bytes)!
		}
		assert os.read_bytes(input)! == source[..] && os.read_bytes(credential)! == key_bytes && os.read_bytes(reference)! == record[..]
		os.rm(reference)!
	} } } }
}

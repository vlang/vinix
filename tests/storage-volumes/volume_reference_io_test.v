// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

import os

fn volume_reference_mock_report(before &u8, after &u8, disk &DiskKey, row &Request, changed bool) bool {
	volume_scrub_report_ready()
	if recovery_io.mode == 32 { return false }
	return show_volume_reference(before, after, disk, row, changed)
}

fn volume_reference_check(before string, after string, fault int, expected i32) string {
	recovery_io = RecoveryIO{mode: fault}; volume_recovery_io = VolumeRecoveryIO{}; recovery_growth_io = RecoveryGrowthIO{}
	output := os.dir(before) + '/capture'; assert C.fflush(C.stdout) == 0
	saved := C.dup(1); fd := C.open(output.str, C.O_WRONLY | C.O_CREAT | C.O_TRUNC, u32(0o600))
	assert saved >= 0 && fd >= 0 && C.dup2(fd, 1) == 1 && C.close(fd) == 0
	unsafe {
		args := [&char(c'vinix-volume'), if after == '' { &char(c'show-volume-reference') } else { &char(c'compare-volume-references') }, before.str, after.str, &char(nil)]!
		assert run(if after == '' { 3 } else { 4 }, &args[0]) == expected
	}
	assert C.fflush(C.stdout) == 0 && C.dup2(saved, 1) == 1 && C.close(saved) == 0
	volume_scrub_report_ready()
	assert recovery_io.opened == recovery_io.closed && recovery_io.volume_wipes == 0 && recovery_io.random == -1 && volume_recovery_io.derives == 0
	text := os.read_file(output) or { panic(err) }; os.rm(output) or { panic(err) }
	if expected == 1 && fault !in [21, 33] { assert !text.contains('operation=') }; return text
}

fn test_reference_queries_private_complete_inputs_no_devices_and_exact_full_width_output() {
	volume_scrub_model = true; volume_scrub_offline = true; ciphertext_model = true
	defer { volume_scrub_model = false; volume_scrub_offline = false; ciphertext_model = false }
	work := os.join_path(os.temp_dir(), 'vinix-reference-${os.getpid()}'); os.mkdir(work)!; os.chmod(work, 0o700)!; defer { os.rmdir_all(work) or {} }
	before := work + '/before'; after := work + '/after'
	for sector in [u64(512), u64(4096)] { for kind in [u32(1), u32(2)] { for flags in [u64(0), u64(1)] {
		mut disk := DiskKey{bytes: u64(-1) - (sector - 1), sector: sector, kind: kind}; disk.id[0] = 1; if kind == 2 { disk.id[15] = 0x83 }
		row := Request{slot: 63, offset: 8192, length: 73728, flags: flags}; digest := [32]u8{init: u8(index * 7 + 11)}; mut records := [3][128]u8{}
		for i in 0 .. 3 { mut actual := digest; if i > 0 { actual[31] ^= u8(i) }; assert encode_volume_ciphertext(&disk, &row, &actual[0], &records[i][0]) }
		identity := if kind == 1 { 'mbr:00000001' } else { 'gpt:00000001-0000-0000-0000-000000000083' }
		geometry := 'disk_bytes=${disk.bytes} sector=${sector} identity=${identity} slot=63 offset=8192 bytes=73728 readonly=${flags}'
		for i in 0 .. 3 { for j in 0 .. 3 {
			os.write_file_array(before, records[i][..])!; os.write_file_array(after, records[j][..])!; os.chmod(before, 0o600)!; os.chmod(after, 0o600)!
			old_hash := hex.encode(sha256.sum(records[i][..])[..]); new_hash := hex.encode(sha256.sum(records[j][..])[..])
			old_digest := hex.encode(records[i][80..112]); new_digest := hex.encode(records[j][80..112])
			expected := 'format=VINIXCH1 operation=compared-ciphertext-references mappings=1 stable=${int(i == j)} changed=${int(i != j)} algorithm=sha256 before_reference_sha256=${old_hash} after_reference_sha256=${new_hash}\n' + geometry + ' result=${if i == j { 'stable' } else { 'changed' }} before_sha256=${old_digest} after_sha256=${new_digest}\n'
			shown := 'format=VINIXCH1 operation=show-ciphertext-reference mappings=1 algorithm=sha256 reference_sha256=${old_hash}\n' + geometry + ' sha256=${old_digest}\n'
			for fault in [0, 1, 2, 3, 4, 5, 21, 22, 32, 33] {
				shown_text := volume_reference_check(before, '', fault, if fault <= 1 { 0 } else { 1 })
				if fault <= 1 { assert shown_text == shown }
				text := volume_reference_check(before, after, fault, if fault <= 1 { if i == j { 0 } else { 2 } } else { 1 })
				if fault <= 1 { assert text == expected }
				assert os.read_bytes(before)! == records[i][..] && os.read_bytes(after)! == records[j][..]
			}
			if i == j { assert volume_reference_check(before, before, 0, 0) == expected }
		} }
		for path in [before, after] {
			os.write_file_array(before, records[0][..])!; os.write_file_array(after, records[1][..])!; original := os.read_bytes(path)!
			os.chmod(path, 0o644)!; volume_reference_check(before, after, 0, 1); volume_reference_check(path, '', 0, 1); os.chmod(path, 0o600)!
			for length in [0, 127, 129] { mut bad := []u8{len: length}; copy(mut bad, original); os.write_file_array(path, bad)!; volume_reference_check(before, after, 0, 1); volume_reference_check(path, '', 0, 1) }; os.write_file_array(path, original)!
			for at in [0, 8, 12, 24, 32, 36, 40, 48, 56, 68, 112] { mut bad := original.clone(); bad[at] ^= if at == 48 { u8(0xff) } else { u8(1) }; if at == 32 { bad[at] = 3 }; put_le(bad.data, 124, 4, crc32(bad.data, 128, 124)); os.write_file_array(path, bad)!; volume_reference_check(before, after, 0, 1) }; os.write_file_array(path, original)!
			os.mv(path, path + '.saved')!; os.symlink(path + '.saved', path)!; volume_reference_check(before, after, 0, 1); volume_reference_check(path, '', 0, 1); os.rm(path)!; os.mv(path + '.saved', path)!
			os.mv(path, path + '.saved')!; os.symlink(work + '/absent', path)!; volume_reference_check(before, after, 0, 1); os.rm(path)!
			os.mkdir(path)!; volume_reference_check(before, after, 0, 1); volume_reference_check(path, '', 0, 1); os.rmdir(path)!
			assert C.mkfifo(path.str, 0o600) == 0; volume_reference_check(before, after, 0, 1); volume_reference_check(path, '', 0, 1); os.rm(path)!; os.mv(path + '.saved', path)!
			os.mv(path, path + '.saved')!; volume_reference_check(before, after, 0, 1); os.mv(path + '.saved', path)!
			assert os.read_bytes(path)! == original
		}
		os.write_file_array(after, records[0][..])!; os.link(before, work + '/alias')!
		assert volume_reference_check(before, work + '/alias', 0, 0).contains('stable=1 changed=0'); os.rm(work + '/alias')!
	} } }
}

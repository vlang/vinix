// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module volumecli

import os

fn C.dup(i32) i32
fn C.dup2(i32, i32) i32
__global growth_preview_model bool

fn growth_preview_report(disk &DiskKey, row &Request, saved_capacity u64, saved_length u64, recovery bool) bool {
	recovery_growth_erased(); assert growth_preview_model && recovery_growth_io.parent_live && recovery_growth_io.statuses == 3
	if recovery_io.mode == 32 { return false }
	return show_volume_growth_preview(disk, row, saved_capacity, saved_length, recovery)
}

fn growth_preview_mock_ferror(stream voidptr) i32 {
	if (growth_preview_model || ciphertext_model) && recovery_io.mode == 33 { return 1 }
	return C.ferror(stream)
}

fn growth_preview_check(input string, credential string, capacity u64, length u64, recovery bool, physical int, fault int, sector u64, kind u32, physical_readonly bool, expected i32) string {
	recovery_io = RecoveryIO{mode: fault}; volume_recovery_io = VolumeRecoveryIO{}
	recovery_growth_io = RecoveryGrowthIO{physical: physical, bytes: capacity, sector: sector, kind: kind, readonly: physical_readonly}
	output := os.dir(input) + '/capture'
	assert C.fflush(C.stdout) == 0
	saved := C.dup(1); fd := C.open(output.str, C.O_WRONLY | C.O_CREAT | C.O_TRUNC, u32(0o600))
	assert saved >= 0 && fd >= 0 && C.dup2(fd, 1) == 1 && C.close(fd) == 0
	if capacity == 0 || length == 0 { assert preview_volume_growth(c'/recovery-growth-parent', input.str, credential.str, capacity, length, recovery) == expected }
	else {
		capacity_text := capacity.str(); length_text := length.str()
		unsafe {
			args := [&char(c'vinix-volume'), if recovery { &char(c'plan-preview-grow-recovery-volume') } else { &char(c'plan-preview-grow-volume') }, &char(c'/recovery-growth-parent'), input.str, credential.str, capacity_text.str, length_text.str, &char(nil)]!
			assert run(7, &args[0]) == expected
		}
	}
	assert C.fflush(C.stdout) == 0 && C.dup2(saved, 1) == 1 && C.close(saved) == 0
	assert recovery_io.opened == recovery_io.closed && recovery_io.volume_wipes == 1 && !recovery_io.locked && !recovery_growth_io.parent_live
	assert recovery_io.directory == -1 && recovery_io.random == -1 && recovery_io.writes == 0 && recovery_io.links == 0 && recovery_io.unlinks == 0
	assert volume_recovery_io.derives <= if recovery { 0 } else { 1 }
	text := os.read_file(output) or { panic(err) }; os.rm(output) or { panic(err) }
	if expected != 0 && fault !in [21, 33] { assert !text.contains('operation=') && !text.contains('slot=') && !text.contains('planned_disk_bytes=') }
	return text
}

fn test_growth_previews_authenticate_before_pinned_readonly_probes_report_exact_geometry_and_never_publish() {
	growth_preview_model = true; recovery_growth_model = true
	defer { growth_preview_model = false; recovery_growth_model = false }
	work := os.join_path(os.temp_dir(), 'vinix-growth-preview-${os.getpid()}')
	os.mkdir(work)!; os.chmod(work, 0o700)!; defer { os.rmdir_all(work) or {} }
	input := work + '/input'; credential := work + '/credential'
	wrapping := [64]u8{init: u8(index * 29 + 41)}; random := [28]u8{init: u8(index * 11 + 3)}; mut source := [320]u8{}
	for recovery in [false, true] {
		key_bytes := if recovery { wrapping[..] } else { [u8(0), 10, 0xe2, 0x82, 0xac, 0xff] }
		os.write_file_array(credential, key_bytes)!; os.chmod(credential, 0o600)!
		for sector in [u64(512), u64(4096)] {
			for kind in [u32(1), u32(2)] {
				for flags in [u64(0), u64(1)] {
					mut disk := DiskKey{bytes: 16777216, sector: sector, kind: kind}; disk.id[0] = 1; if kind == 2 { disk.id[15] = 0x83 }
					request := EncryptedRequest{data: Request{slot: 63, offset: sector * 2, length: 4096, flags: flags}, key: [64]u8{init: u8(index * 13 + 7)}}
					assert if recovery { encode_volume_recovery(&disk, &request, &wrapping[0], &random[0], &source[0]) } else { encode_volume_seal(&disk, &request, &wrapping[0], &random[0], &source[0]) }
					os.write_file_array(input, source[..])!; os.chmod(input, 0o600)!
					identity := if kind == 1 { 'mbr:00000001' } else { 'gpt:00000001-0000-0000-0000-000000000083' }
					for capacity in [u64(16777216), u64(33554432), u64(-1) - (sector - 1)] {
						limit := u64(0x7fffffffffffffff) - (sector - 1)
						maximum := if capacity - request.data.offset > limit { limit } else { capacity - request.data.offset }
						for length in [u64(4096), u64(8192), maximum] {
							text := growth_preview_check(input, credential, capacity, length, recovery, 0, 0, sector, kind, flags == 0, 0)
							domain := if recovery { 'recovery' } else { 'volume' }; capacity_action := if capacity == disk.bytes { 'keep' } else { 'grow' }; extent_action := if length == request.data.length { 'keep' } else { 'grow' }
							assert text == 'operation=checked-growth format=${domain}\ncurrent_disk_bytes=16777216 planned_disk_bytes=${capacity} sector=${sector} identity=${identity} capacity_action=${capacity_action}\nslot=63 offset=${sector * 2} current_bytes=4096 planned_bytes=${length} readonly=${flags} extent_action=${extent_action}\n'
							assert recovery_growth_io.statuses == 3 && recovery_growth_io.parent_opens == 1
						}
					}
					for mode in 0 .. 30 { growth_preview_check(input, credential, 16777216, 8192, recovery, mode, 0, sector, kind, false, if mode <= 1 { 0 } else { 1 }) }
					for fault in [0, 1, 2, 3, 4, 5, 21, 22, 32, 33] { growth_preview_check(input, credential, 16777216, 8192, recovery, 0, fault, sector, kind, false, if fault <= 1 { 0 } else { 1 }) }
					if !recovery { for fault in [23, 24, 25] { growth_preview_check(input, credential, 16777216, 8192, false, 0, fault, sector, kind, false, 1); assert recovery_growth_io.parent_opens == 0 } }
					for length in [u64(0), u64(512), u64(4095), u64(8193), u64(16777216), u64(-1)] {
						growth_preview_check(input, credential, 16777216, length, recovery, 0, 0, sector, kind, false, 1); assert recovery_growth_io.parent_opens == 0
					}
					for capacity in [u64(0), u64(16777216) - sector, u64(16777217), u64(-1)] {
						growth_preview_check(input, credential, capacity, 8192, recovery, 0, 0, sector, kind, false, 1); assert recovery_growth_io.parent_opens == 0
					}
					growth_preview_check(input, credential, u64(-1) - (sector - 1), u64(0x8000000000000000), recovery, 0, 0, sector, kind, false, 1); assert recovery_growth_io.parent_opens == 0
					for at in [0, 24, 104, 192, 288] {
						mut bad := source; bad[at] ^= 1; os.write_file_array(input, bad[..])!
						growth_preview_check(input, credential, 16777216, 8192, recovery, 0, 0, sector, kind, false, 1); assert recovery_growth_io.parent_opens == 0
					}
					os.write_file_array(input, source[..])!
					for path in [input, credential] {
						original := os.read_bytes(path)!
						os.chmod(path, 0o644)!; growth_preview_check(input, credential, 16777216, 8192, recovery, 0, 0, sector, kind, false, 1); assert recovery_growth_io.parent_opens == 0; os.chmod(path, 0o600)!
						for length in if path == credential && !recovery { [0, 1025] } else { [original.len - 1, original.len + 1] } {
							mut bad := []u8{len: length}; copy(mut bad, original); os.write_file_array(path, bad)!
							growth_preview_check(input, credential, 16777216, 8192, recovery, 0, 0, sector, kind, false, 1); assert recovery_growth_io.parent_opens == 0
						}
						os.write_file_array(path, original)!; os.mv(path, path + '.saved')!; os.symlink(path + '.saved', path)!
						growth_preview_check(input, credential, 16777216, 8192, recovery, 0, 0, sector, kind, false, 1); assert recovery_growth_io.parent_opens == 0
						os.rm(path)!; os.mv(path + '.saved', path)!
					}
					assert os.read_bytes(input)! == source[..] && os.read_bytes(credential)! == key_bytes && os.ls(work)!.len == 2
				}
			}
		}
	}
}

// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module volumecli

import os

struct RecoveryRewrapIO {
mut:
	work &VolumeSealFiles = unsafe { nil }
	stage int
	fd i32 = -1
	stats int
	reads int
	new_opens int
}
__global recovery_rewrap_io RecoveryRewrapIO
__global recovery_rewrap_model bool

fn recovery_rewrap_record(work &VolumeSealFiles) { recovery_rewrap_io.work = work }

fn recovery_rewrap_before_open(path &char, flags i32) bool {
	work := recovery_rewrap_io.work; assert work != unsafe { nil }
	recovery_rewrap_io.stage = 0
	if unsafe { C.strstr(path, c'/newkey') != nil } {
		recovery_rewrap_io.stage = 2; recovery_rewrap_io.new_opens++
		for byte in work.wrapping { assert byte == 0 }
		if recovery_io.mode == 23 { unsafe { C.errno = C.EACCES }; return false }
	}
	if flags & C.O_DIRECTORY != 0 {
		for byte in work.wrapping { assert byte == 0 }
		for byte in work.request.key { assert byte == 0 }
		for byte in work.password { assert byte == 0 }
	}
	if unsafe { C.strstr(path, c'/dev/') != nil } { assert C.strcmp(path, c'/dev/urandom') == 0 }
	return true
}

fn recovery_rewrap_check(input string, old string, next string, output string, mode int, expected i32) {
	recovery_io = RecoveryIO{mode: mode}; recovery_rewrap_io = RecoveryRewrapIO{}
	unsafe {
		args := [&char(c'vinix-volume'), &char(c'rewrap-recovery-volume'), input.str, old.str, next.str, output.str, &char(nil)]!
		assert run(6, &args[0]) == expected
	}
	assert recovery_io.opened == recovery_io.closed && recovery_io.volume_wipes == 1 && !recovery_io.locked
	assert volume_recovery_io.derives == 0
}

fn test_recovery_rewrap_authentication_erasure_stages_exact_metadata_and_private_publication() {
	recovery_rewrap_model = true; defer { recovery_rewrap_model = false }
	volume_recovery_io = VolumeRecoveryIO{}
	work := os.join_path(os.temp_dir(), 'vinix-recovery-rewrap-${os.getpid()}')
	os.mkdir(work)!; os.chmod(work, 0o700)!; defer { os.rmdir_all(work) or {} }
	input := work + '/backup'; old := work + '/oldkey'; next := work + '/newkey'; output := work + '/output'
	old_key := [64]u8{init: u8(index * 29 + 41)}; new_key := [64]u8{init: u8(index * 37 + 23)}
	random := [28]u8{init: u8(index * 11 + 3)}; mut source := [320]u8{}
	os.write_file_array(old, old_key[..])!; os.write_file_array(next, new_key[..])!
	os.chmod(old, 0o600)!; os.chmod(next, 0o600)!
	for sector in [u64(512), u64(4096)] {
		for kind in [u32(1), u32(2)] {
			for flags in [u64(0), u64(1)] {
				mut disk := DiskKey{bytes: 16777216, sector: sector, kind: kind}; disk.id[0] = 1; if kind == 2 { disk.id[15] = 0x83 }
				request := EncryptedRequest{data: Request{slot: 63, offset: sector * 2, length: 4096, flags: flags}, key: [64]u8{init: u8(index * 13 + 7)}}
				assert encode_volume_recovery(&disk, &request, &old_key[0], &random[0], &source[0])
				os.write_file_array(input, source[..])!; os.chmod(input, 0o600)!
				for mode in 0 .. 31 {
					recovery_rewrap_check(input, old, next, output, mode, if mode in [0, 1, 30] { 0 } else { 1 })
					assert os.exists(output) == (mode in [0, 1, 19, 20, 21, 30])
					if os.exists(output) {
						volume_recovery_check_output(output, &disk, &request, true, &new_key[0])!
						bytes := os.read_bytes(output)!
						assert bytes[80..192] == source[80..192] && bytes[56..68] != source[56..68]
						mut observed := DiskKey{}; mut decoded := EncryptedRequest{}
						assert !decode_volume_recovery(bytes.data, 320, &old_key[0], mut observed, mut decoded)
						os.rm(output)!
					}
					assert os.read_bytes(input)! == source[..] && os.ls(work)!.all(!it.starts_with('.vinix-key-'))
				}
				for destination in [input, old, next, work + '/link'] {
					if destination.ends_with('/link') { os.symlink(work + '/absent', destination)! }
					recovery_rewrap_check(input, old, next, destination, 0, 1)
				}
				os.rm(work + '/link')!
				// Same-credential refresh still produces a fresh authenticated backup.
				recovery_rewrap_check(input, old, old, output, 0, 0)
				volume_recovery_check_output(output, &disk, &request, true, &old_key[0])!; os.rm(output)!
			}
		}
	}
	for at in [0, 24, 104, 192, 288] {
		mut bad := source; bad[at] ^= 1; os.write_file_array(input, bad[..])!
		recovery_rewrap_check(input, old, next, output, 0, 1)
		assert recovery_rewrap_io.new_opens == 0 && recovery_io.directory == -1 && !os.exists(output)
	}
	os.write_file_array(input, source[..])!
	for at in [0, 32] {
		mut bad := old_key; bad[at] ^= 1; os.write_file_array(old, bad[..])!
		recovery_rewrap_check(input, old, next, output, 0, 1)
		assert recovery_rewrap_io.new_opens == 0 && recovery_io.directory == -1
	}
	os.write_file_array(old, old_key[..])!
	for bad in [[64]u8{init: 7}, [64]u8{init: u8(index * 13 + 7)}] {
		os.write_file_array(next, bad[..])!; recovery_rewrap_check(input, old, next, output, 0, 1)
		assert recovery_io.directory == -1 && !os.exists(output)
	}
	os.write_file_array(next, new_key[..])!
	for path in [input, old, next] {
		original := os.read_bytes(path)!
		os.chmod(path, 0o644)!; recovery_rewrap_check(input, old, next, output, 0, 1); os.chmod(path, 0o600)!
		for length in [original.len - 1, original.len + 1] {
			mut bytes := []u8{len: length}; copy(mut bytes, original); os.write_file_array(path, bytes)!
			recovery_rewrap_check(input, old, next, output, 0, 1)
		}
		os.write_file_array(path, original)!
		os.mv(path, path + '.saved')!; os.symlink(path + '.saved', path)!; recovery_rewrap_check(input, old, next, output, 0, 1)
		os.rm(path)!; os.mkdir(path)!; recovery_rewrap_check(input, old, next, output, 0, 1)
		os.rmdir(path)!; recovery_rewrap_check(input, old, next, output, 0, 1); os.mv(path + '.saved', path)!
		assert recovery_io.directory == -1 && !os.exists(output)
	}
	assert os.read_bytes(input)! == source[..] && os.read_bytes(old)! == old_key[..] && os.read_bytes(next)! == new_key[..]
}

// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

import os

fn recovery_unlock_check(backup string, key string, directory string, sector u64, flags u64, force bool, mode int, expected i32) {
	volume_discovery_io = VolumeDiscoveryIO{recovery: true, directory: directory, sector: sector, flags: flags | u64(force), mode: mode, goal_derives: 0}
	unsafe {
		args := [&char(c'vinix-volume'), &char(c'open-recovery-volume-auto'), backup.str, key.str, &char(c'ro'), &char(nil)]!
		assert run(if force { 5 } else { 4 }, &args[0]) == expected
	}
	assert volume_discovery_io.derives == 0 && volume_discovery_io.wipes == 1
	assert volume_discovery_io.opened == volume_discovery_io.closed && volume_discovery_io.live.all(!it)
	assert volume_discovery_io.imports == if expected == 0 || mode in [20, 21] { 1 } else { 0 }
}

fn test_recovery_unlock_authenticates_before_discovery_erases_credentials_and_preserves_modes() {
	work := os.join_path(os.temp_dir(), 'vinix-recovery-unlock-${os.getpid()}')
	os.mkdir(work)!; os.chmod(work, 0o700)!; os.mkdir(work + '/dev')!; defer { os.rmdir_all(work) or {} }
	backup := work + '/backup'; key := work + '/key'; directory := work + '/dev'
	mut recovery := [64]u8{init: u8(index * 29 + 41)}; random := [28]u8{init: u8(index * 11 + 3)}; mut source := [320]u8{}
	os.write_file_array(key, recovery[..])!; os.chmod(key, 0o600)!
	for sector in [u64(512), u64(4096)] {
		for kind in [u32(1), u32(2)] {
			for flags in [u64(0), u64(1)] {
				mut disk := DiskKey{bytes: 16777216, sector: sector, kind: kind}; disk.id[0] = 1; if kind == 2 { disk.id[15] = 0x83 }
				request := EncryptedRequest{data: Request{slot: 5, offset: sector * 2, length: 4096, flags: flags}, key: [64]u8{init: u8(index * 13 + 7)}}
				assert encode_volume_recovery(&disk, &request, &recovery[0], &random[0], &source[0])
				os.write_file_array(backup, source[..])!; os.chmod(backup, 0o600)!
				volume_discovery_fixture(directory, 0, sector, kind)!
				for force in [false, true] {
					for mode in 0 .. 32 {
						if mode in [1, 2, 23] || (mode in [15, 16] && (flags == 1 || force)) { continue }
						recovery_unlock_check(backup, key, directory, sector, flags, force, mode, if mode in [0, 14, 27] { 0 } else { 1 })
						if mode in [24, 25, 26, 28, 29, 30, 31] { assert volume_discovery_io.scans == 0 }
					}
				}
				for index in [1, 3, 4, 5, 6] { volume_discovery_fixture(directory, index, sector, kind)! }
				os.symlink(directory + '/0', directory + '/link')!; os.write_file(directory + '/regular', 'ignored')!
				recovery_unlock_check(backup, key, directory, sector, flags, false, 0, 0)
				volume_discovery_fixture(directory, 2, sector, kind)!
				recovery_unlock_check(backup, key, directory, sector, flags, false, 0, 1)
				for file in os.ls(directory)! { os.rm(directory + '/' + file)! }
				recovery_unlock_check(backup, key, directory, sector, flags, false, 0, 1)
			}
		}
	}
	// Headers fail before the key is opened; authenticated fields and tag fail
	// before any device scan. No source, credential or configuration is written.
	for at in [0, 24, 124, 104, 192, 288] {
		mut bad := source; bad[at] ^= if at == 124 { u8(0x80) } else { u8(1) }; os.write_file_array(backup, bad[..])!
		recovery_unlock_check(backup, key, directory, 4096, 1, false, 0, 1)
		assert volume_discovery_io.scans == 0 && volume_discovery_io.key_opens == if at in [0, 24, 124] { 0 } else { 1 }
	}
	os.write_file_array(backup, source[..])!
	for at in [0, 32] {
		recovery[at] ^= 1; os.write_file_array(key, recovery[..])!
		recovery_unlock_check(backup, key, directory, 4096, 1, false, 0, 1); assert volume_discovery_io.scans == 0
		recovery[at] ^= 1; os.write_file_array(key, recovery[..])!
	}
	for path in [backup, key] {
		original := os.read_bytes(path)!
		os.chmod(path, 0o644)!
		recovery_unlock_check(backup, key, directory, 4096, 1, false, 0, 1); assert volume_discovery_io.scans == 0
		os.chmod(path, 0o600)!
		for length in [original.len - 1, original.len + 1] {
			mut bytes := []u8{len: length}; copy(mut bytes, original)
			os.write_file_array(path, bytes)!
			recovery_unlock_check(backup, key, directory, 4096, 1, false, 0, 1); assert volume_discovery_io.scans == 0
		}
		os.write_file_array(path, original)!
		os.mv(path, path + '.saved')!; os.symlink(path + '.saved', path)!
		recovery_unlock_check(backup, key, directory, 4096, 1, false, 0, 1); assert volume_discovery_io.scans == 0
		os.rm(path)!; os.mkdir(path)!
		recovery_unlock_check(backup, key, directory, 4096, 1, false, 0, 1); assert volume_discovery_io.scans == 0
		os.rmdir(path)!
		recovery_unlock_check(backup, key, directory, 4096, 1, false, 0, 1); assert volume_discovery_io.scans == 0
		os.mv(path + '.saved', path)!
	}
	for i in 0 .. 4097 { os.write_file(directory + '/entry-' + i.str(), '')! }
	recovery_unlock_check(backup, key, directory, 4096, 1, false, 0, 1)
	assert volume_discovery_io.scans == 1 && os.read_bytes(backup)! == source[..] && os.read_bytes(key)! == recovery[..]
	assert os.ls(work)!.len == 3
}

// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

import os

fn C.dup(i32) i32
fn C.dup2(i32, i32) i32

fn recovery_inspect_record(work &VolumeSealFiles) {
	if volume_discovery_io.inspect { volume_discovery_io.inspect_work = work }
}

fn recovery_inspect_erased() {
	work := volume_discovery_io.inspect_work; assert work != unsafe { nil }
	unsafe {
		for i in 0 .. 64 { assert work.wrapping[i] == 0 && work.request.key[i] == 0 }
		for i in 0 .. 1024 { assert work.password[i] == 0 }
	}
}

fn recovery_inspect_mock_report(disk &DiskKey, row &Request, name &char, online bool) bool {
	recovery_inspect_erased(); volume_discovery_io.reports++
	assert volume_discovery_io.scans == int(online) && volume_discovery_io.imports == 0
	if online {
		mut pinned := 0
		for i in 0 .. 4096 {
			if volume_discovery_io.live[i] && volume_discovery_io.indices[i] >= 0 {
				pinned++; assert volume_discovery_io.statuses[volume_discovery_io.indices[i]] == 3
			}
		}
		assert pinned == 1
	}
	if volume_discovery_io.mode == 32 { return false }
	return if volume_discovery_io.seal_inspect { show_sealed_volume(disk, row, name, online) } else { show_recovery_volume(disk, row, name, online) }
}

fn recovery_inspect_mock_ferror(stream voidptr) i32 {
	if volume_discovery_io.inspect && volume_discovery_io.mode == 33 { return 1 }
	return C.ferror(stream)
}

fn recovery_inspect_check(backup string, key string, directory string, sector u64, flags u64, online bool, mode int, expected i32) string {
	volume_discovery_io = VolumeDiscoveryIO{recovery: true, inspect: true, directory: directory, sector: sector, flags: flags, mode: mode, goal_derives: 0}
	output := os.dir(backup) + '/output'
	assert C.fflush(C.stdout) == 0
	saved := C.dup(1); target := C.open(output.str, C.O_WRONLY | C.O_CREAT | C.O_TRUNC, u32(0o600))
	assert saved >= 0 && target >= 0 && C.dup2(target, 1) == 1 && C.close(target) == 0
	unsafe {
		args := [&char(c'vinix-volume'), if online { &char(c'discover-recovery-volume') } else { &char(c'show-recovery-volume') }, backup.str, key.str, &char(nil)]!
		assert run(4, &args[0]) == expected
	}
	assert C.fflush(C.stdout) == 0 && C.dup2(saved, 1) == 1 && C.close(saved) == 0
	assert volume_discovery_io.derives == 0 && volume_discovery_io.imports == 0 && volume_discovery_io.wipes == 1
	assert volume_discovery_io.opened == volume_discovery_io.closed && volume_discovery_io.live.all(!it)
	result := os.read_file(output) or { panic(err) }; os.rm(output) or { panic(err) }
	if expected == 1 && mode !in [21, 33] { assert !result.contains('operation=') && !result.contains('disk_bytes=') && !result.contains('slot=') }
	return result
}

fn test_recovery_inspection_reports_only_authenticated_metadata_and_discovers_without_import_or_writable_open() {
	work := os.join_path(os.temp_dir(), 'vinix-recovery-inspect-${os.getpid()}')
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
				identity := if kind == 1 { 'mbr:00000001' } else { 'gpt:00000001-0000-0000-0000-000000000083' }
				metadata := 'disk_bytes=16777216 sector=${sector} identity=${identity}\nslot=5 offset=${sector * 2} bytes=4096 readonly=${flags}\n'
				for online in [false, true] {
					prefix := if online { 'operation=discovered-recovery device=/dev/0\n' } else { 'operation=authenticated-recovery\n' }
					assert recovery_inspect_check(backup, key, directory, sector, flags, online, 0, 0) == prefix + metadata
					for mode in [21, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33] {
						recovery_inspect_check(backup, key, directory, sector, flags, online, mode, if mode == 27 { 0 } else { 1 })
						if mode in [24, 25, 26, 28, 29, 30, 31] { assert volume_discovery_io.scans == 0 && volume_discovery_io.reports == 0 }
					}
				}
				for mode in 3 .. 23 {
					recovery_inspect_check(backup, key, directory, sector, flags, true, mode, if mode in [14, 15, 20] { 0 } else { 1 })
				}
				assert recovery_inspect_check(backup, key, directory, sector, flags, true, 34, 0).ends_with(metadata)
				for index in [1, 3, 4, 5, 6] { volume_discovery_fixture(directory, index, sector, kind)! }
				os.symlink(directory + '/0', directory + '/link')!; os.write_file(directory + '/regular', 'ignored')!
				// Enumeration order chooses either physical alias; disk_id proves sameness.
				recovery_inspect_check(backup, key, directory, sector, flags, true, 0, 0)
				volume_discovery_fixture(directory, 2, sector, kind)!
				recovery_inspect_check(backup, key, directory, sector, flags, true, 0, 1)
				for file in os.ls(directory)! { os.rm(directory + '/' + file)! }
				recovery_inspect_check(backup, key, directory, sector, flags, true, 0, 1)
				assert recovery_inspect_check(backup, key, directory, sector, flags, false, 0, 0) == 'operation=authenticated-recovery\n' + metadata
			}
		}
	}
	for at in [0, 24, 124, 104, 192, 288] {
		mut bad := source; bad[at] ^= if at == 124 { u8(0x80) } else { u8(1) }; os.write_file_array(backup, bad[..])!
		for online in [false, true] {
			recovery_inspect_check(backup, key, directory, 4096, 1, online, 0, 1)
			assert volume_discovery_io.scans == 0 && volume_discovery_io.reports == 0
			assert volume_discovery_io.key_opens == if at in [0, 24, 124] { 0 } else { 1 }
		}
	}
	os.write_file_array(backup, source[..])!
	for at in [0, 32] {
		recovery[at] ^= 1; os.write_file_array(key, recovery[..])!
		for online in [false, true] { recovery_inspect_check(backup, key, directory, 4096, 1, online, 0, 1); assert volume_discovery_io.scans == 0 && volume_discovery_io.reports == 0 }
		recovery[at] ^= 1; os.write_file_array(key, recovery[..])!
	}
	for path in [backup, key] {
		original := os.read_bytes(path)!
		os.chmod(path, 0o644)!
		for online in [false, true] { recovery_inspect_check(backup, key, directory, 4096, 1, online, 0, 1); assert volume_discovery_io.scans == 0 }
		os.chmod(path, 0o600)!
		for length in [original.len - 1, original.len + 1] {
			mut bytes := []u8{len: length}; copy(mut bytes, original); os.write_file_array(path, bytes)!
			for online in [false, true] { recovery_inspect_check(backup, key, directory, 4096, 1, online, 0, 1); assert volume_discovery_io.scans == 0 }
		}
		os.write_file_array(path, original)!
		os.mv(path, path + '.saved')!; os.symlink(path + '.saved', path)!
		for online in [false, true] { recovery_inspect_check(backup, key, directory, 4096, 1, online, 0, 1); assert volume_discovery_io.scans == 0 }
		os.rm(path)!; os.mkdir(path)!
		for online in [false, true] { recovery_inspect_check(backup, key, directory, 4096, 1, online, 0, 1); assert volume_discovery_io.scans == 0 }
		os.rmdir(path)!; os.mv(path + '.saved', path)!
	}
	for i in 0 .. 4097 { os.write_file(directory + '/entry-' + i.str(), '')! }
	recovery_inspect_check(backup, key, directory, 4096, 1, true, 0, 1)
	assert os.read_bytes(backup)! == source[..] && os.read_bytes(key)! == recovery[..] && os.ls(work)!.len == 3
	// Offline inspection retains full-width capacity and extent fields.
	mut disk := DiskKey{bytes: u64(0xfffffffffffff000), sector: 4096, kind: 1}; disk.id[0] = 1
	request := EncryptedRequest{data: Request{slot: 63, offset: 4096, length: u64(0x8000000000000000), flags: 1}, key: [64]u8{init: u8(index * 13 + 7)}}
	assert encode_volume_recovery(&disk, &request, &recovery[0], &random[0], &source[0]); os.write_file_array(backup, source[..])!
	assert recovery_inspect_check(backup, key, directory, 4096, 1, false, 0, 0) == 'operation=authenticated-recovery\ndisk_bytes=18446744073709547520 sector=4096 identity=mbr:00000001\nslot=63 offset=4096 bytes=9223372036854775808 readonly=1\n'
}

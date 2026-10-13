// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module volumecli

import os

struct RecoveryGrowthIO {
mut:
	work &VolumeSealFiles = unsafe { nil }
	physical int
	bytes u64 = 16777216
	sector u64 = 512
	kind u32 = 1
	readonly bool
	parent_opens int
	parent_live bool
	statuses int
	reads int
}
__global recovery_growth_io RecoveryGrowthIO
__global recovery_growth_model bool

fn recovery_growth_record(work &VolumeSealFiles) { recovery_growth_io.work = work }

fn recovery_growth_erased() {
	work := recovery_growth_io.work; assert work != unsafe { nil }
	for byte in work.wrapping { assert byte == 0 }
	for byte in work.request.key { assert byte == 0 }
	for byte in work.password { assert byte == 0 }
}

fn recovery_growth_before_open(path &char, flags i32) {
	if C.strcmp(path, c'/recovery-growth-parent') == 0 {
		recovery_growth_erased()
		assert flags == C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK
	}
	if flags & C.O_DIRECTORY != 0 { recovery_growth_erased(); assert recovery_growth_io.parent_live && recovery_growth_io.statuses == 2 }
}

fn recovery_growth_mock_ioctl(fd i32, number u64, output voidptr) i32 {
	assert recovery_growth_model && fd == 900 && recovery_growth_io.parent_live && number == 0x56560004
	recovery_growth_erased(); recovery_growth_io.statuses++
	mode := recovery_growth_io.physical; count := recovery_growth_io.statuses
	if mode == 8 { unsafe { C.errno = C.EIO }; return -1 }
	mut status := Status{version: 1, bytes: recovery_growth_io.bytes, sector: recovery_growth_io.sector,
		flags: 4 | u64(recovery_growth_io.readonly), disk_id: 7, slot: u64(-1)}
	match mode {
		4 { status.flags |= 2 }
		5 { status.flags |= 16; status.start = 512 }
		6 { status.flags |= 8 }
		7 { status.sector = 1024 }
		10 { status.bytes -= status.sector }
		12 { if count == 2 { status.disk_id++ } }
		14 { if count == 2 { status.sector = if status.sector == 512 { 4096 } else { 512 } } }
		15 { if count == 2 { status.bytes -= status.sector } }
		16 { if count == 2 { status.flags ^= 1 } }
		17 { if count == 2 { status.flags |= 2 } }
		21 { status.version = 2 }
		22 { if count == 3 { status.disk_id++ } }
		24 { if count == 3 { status.sector = if status.sector == 512 { 4096 } else { 512 } } }
		25 { if count == 3 { status.bytes -= status.sector } }
		26 { if count == 3 { status.flags ^= 1 } }
		27 { if count == 3 { status.flags |= 2 } }
		else {}
	}
	unsafe { *(&Status(output)) = status }; return 0
}

fn recovery_growth_mock_pread(fd i32, output voidptr, size usize, offset i64) i64 {
	assert recovery_growth_model && fd == 900 && recovery_growth_io.parent_live && offset == 0 && size >= 1024 && size <= 8192
	recovery_growth_erased(); recovery_growth_io.reads++
	mode := recovery_growth_io.physical; count := recovery_growth_io.statuses
	if mode == 1 && recovery_growth_io.reads == 1 { unsafe { C.errno = C.EINTR }; return -1 }
	if mode == 9 || (mode == 18 && count == 2) || (mode == 28 && count == 3) { return i64(size - 1) }
	if (mode == 19 && count == 2) || (mode == 29 && count == 3) { unsafe { C.errno = C.EIO }; return -1 }
	unsafe { for i in 0 .. int(size) { (&u8(output))[i] = 0 } }
	identity := if mode == 2 { u64(0) } else if mode == 3 || (mode == 13 && count == 2) || (mode == 23 && count == 3) { u64(2) } else { u64(1) }
	put_le(&u8(output), 440, 4, identity); put_le(&u8(output), 510, 2, 0xaa55)
	if recovery_growth_io.kind == 2 {
		put_le(&u8(output), 450, 1, 0xee)
		header := unsafe { &u8(output) + int(size / 2) }
		put_le(header, 0, 8, 0x5452415020494645); put_le(header, 8, 4, 0x10000); put_le(header, 12, 4, 92); put_le(header, 24, 8, 1)
		put_le(header, 56, 1, identity); if identity != 0 { put_le(header, 71, 1, 0x83) }
		put_le(header, 16, 4, crc32(header, 92, 16)); if mode == 20 { put_le(header, 16, 4, 0) }
	} else if mode == 20 { put_le(&u8(output), 510, 2, 0) }
	return i64(size)
}

fn recovery_growth_check(input string, key string, output string, capacity u64, length u64, physical int, publication int, sector u64, kind u32, readonly bool, expected i32) {
	recovery_io = RecoveryIO{mode: publication}
	recovery_growth_io = RecoveryGrowthIO{physical: physical, bytes: capacity, sector: sector, kind: kind, readonly: readonly}
	if capacity == 0 || length == 0 {
		assert plan_grow_volume_recovery(c'/recovery-growth-parent', input.str, key.str, capacity, length, output.str) == expected
	} else {
		capacity_text := capacity.str(); length_text := length.str()
		unsafe {
			args := [&char(c'vinix-volume'), &char(c'plan-grow-recovery-volume'), &char(c'/recovery-growth-parent'), input.str, key.str, capacity_text.str, length_text.str, output.str, &char(nil)]!
			assert run(8, &args[0]) == expected
		}
	}
	assert recovery_io.opened == recovery_io.closed && recovery_io.volume_wipes == 1 && !recovery_io.locked && !recovery_growth_io.parent_live
	assert volume_recovery_io.derives == 0
}

fn test_recovery_growth_authentication_geometry_erasure_pinned_rechecks_and_publication() {
	recovery_growth_model = true; defer { recovery_growth_model = false }; volume_recovery_io = VolumeRecoveryIO{}
	work := os.join_path(os.temp_dir(), 'vinix-recovery-growth-${os.getpid()}')
	os.mkdir(work)!; os.chmod(work, 0o700)!; defer { os.rmdir_all(work) or {} }
	input := work + '/backup'; key := work + '/key'; output := work + '/output'
	credential := [64]u8{init: u8(index * 29 + 41)}; random := [28]u8{init: u8(index * 11 + 3)}; mut source := [320]u8{}
	os.write_file_array(key, credential[..])!; os.chmod(key, 0o600)!
	for sector in [u64(512), u64(4096)] {
		for kind in [u32(1), u32(2)] {
			for flags in [u64(0), u64(1)] {
				mut disk := DiskKey{bytes: 16777216, sector: sector, kind: kind}; disk.id[0] = 1; if kind == 2 { disk.id[15] = 0x83 }
				request := EncryptedRequest{data: Request{slot: 63, offset: sector * 2, length: 4096, flags: flags}, key: [64]u8{init: u8(index * 13 + 7)}}
				assert encode_volume_recovery(&disk, &request, &credential[0], &random[0], &source[0])
				os.write_file_array(input, source[..])!; os.chmod(input, 0o600)!
				for capacity in [u64(16777216), u64(33554432), u64(-1) - (sector - 1)] {
					limit := u64(0x7fffffffffffffff) - (sector - 1)
					maximum := if capacity - request.data.offset > limit { limit } else { capacity - request.data.offset }
					for length in [u64(4096), u64(8192), maximum] {
						recovery_growth_check(input, key, output, capacity, length, 0, 0, sector, kind, flags == 1, 0)
						mut next := disk; next.bytes = capacity; mut expected := request; expected.data.length = length
						volume_recovery_check_output(output, &next, &expected, true, &credential[0])!
						assert recovery_growth_io.statuses == 3 && recovery_growth_io.parent_opens == 1
						bytes := os.read_bytes(output)!; assert bytes[56..68] != source[56..68]
						os.rm(output)!
					}
				}
				for mode in 0 .. 30 {
					recovery_growth_check(input, key, output, 16777216, 8192, mode, 0, sector, kind, flags == 1, if mode <= 1 { 0 } else { 1 })
					assert os.exists(output) == (mode <= 1); if os.exists(output) { os.rm(output)! }
				}
				for mode in 0 .. 23 {
					recovery_growth_check(input, key, output, 16777216, 8192, 0, mode, sector, kind, flags == 1, if mode <= 1 { 0 } else { 1 })
					assert os.exists(output) == (mode <= 1 || mode in [19, 20, 21])
					if os.exists(output) { mut next := request; next.data.length = 8192; volume_recovery_check_output(output, &disk, &next, true, &credential[0])!; os.rm(output)! }
					assert os.ls(work)!.all(!it.starts_with('.vinix-key-'))
				}
				for length in [u64(0), u64(512), u64(4095), u64(8193), u64(16777216), u64(-1)] {
					recovery_growth_check(input, key, output, 16777216, length, 0, 0, sector, kind, false, 1); assert recovery_growth_io.parent_opens == 0 && !os.exists(output)
				}
				for capacity in [u64(0), u64(16777216) - sector, u64(16777217), u64(-1)] {
					recovery_growth_check(input, key, output, capacity, 8192, 0, 0, sector, kind, false, 1); assert recovery_growth_io.parent_opens == 0 && !os.exists(output)
				}
				recovery_growth_check(input, key, output, u64(-1) - (sector - 1), u64(0x8000000000000000), 0, 0, sector, kind, false, 1)
				assert recovery_growth_io.parent_opens == 0 && !os.exists(output)
				for destination in [input, key, work + '/link'] {
					if destination.ends_with('/link') { os.symlink(work + '/absent', destination)! }
					recovery_growth_check(input, key, destination, 16777216, 8192, 0, 0, sector, kind, false, 1)
				}
				os.rm(work + '/link')!; assert os.read_bytes(input)! == source[..]
			}
		}
	}
	for at in [0, 24, 104, 192, 288] {
		mut bad := source; bad[at] ^= 1; os.write_file_array(input, bad[..])!
		recovery_growth_check(input, key, output, 16777216, 8192, 0, 0, 4096, 2, false, 1)
		assert recovery_growth_io.parent_opens == 0 && recovery_io.directory == -1 && !os.exists(output)
	}
	os.write_file_array(input, source[..])!
	for at in [0, 32] {
		mut bad := credential; bad[at] ^= 1; os.write_file_array(key, bad[..])!
		recovery_growth_check(input, key, output, 16777216, 8192, 0, 0, 4096, 2, false, 1)
		assert recovery_growth_io.parent_opens == 0 && recovery_io.directory == -1
	}
	os.write_file_array(key, credential[..])!
	for path in [input, key] {
		os.chmod(path, 0o644)!; recovery_growth_check(input, key, output, 16777216, 8192, 0, 0, 4096, 2, false, 1)
		assert recovery_growth_io.parent_opens == 0 && !os.exists(output); os.chmod(path, 0o600)!
	}
	assert os.read_bytes(input)! == source[..] && os.read_bytes(key)! == credential[..]
}

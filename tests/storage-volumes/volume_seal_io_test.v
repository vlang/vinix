// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module volumecli

import os

struct VolumeSealIO {
mut:
	mode int
	publication int
	creating bool
	rewrapping bool
	growing bool
	physical_bytes u64 = 16777216
	grow_password_size int = 6
	new_input &char = unsafe { nil }
	new_opens int
	password_wipes int
	wrapping_wipes int
	password_buffer &u8 = unsafe { nil }
	wrapping_buffer &u8 = unsafe { nil }
	sector u64 = 512
	kind u32 = 1
	expected_flags u64
	opened int
	closed int
	parent_opens int
	parent_flags i32
	statuses int
	disk_reads int
	imports int
	derives int
	wipes int
	writes int
	unlinks int
	directory i32 = -1
	temporary i32 = -1
	locked bool
}
__global volume_seal_io VolumeSealIO

fn volume_seal_mock_open(path &char, flags i32) i32 {
	assert flags & C.O_CLOEXEC != 0 && flags & C.O_NOFOLLOW != 0
	if volume_seal_io.growing {
		if C.strcmp(path, c'/volume-seal-parent') == 0 {
			assert volume_seal_io.derives == 1 && volume_seal_io.wrapping_wipes == 1
		}
		if flags & C.O_DIRECTORY != 0 {
			assert volume_seal_io.derives == 2 && volume_seal_io.password_wipes == 1 && volume_seal_io.wrapping_wipes == 2
		}
		if volume_seal_io.mode == 28 && C.strcmp(path, c'/dev/urandom') == 0 { unsafe { C.errno = C.EIO }; return -1 }
	}
	if volume_seal_io.rewrapping {
		assert C.strcmp(path, c'/volume-seal-parent') != 0
		if C.strcmp(path, volume_seal_io.new_input) == 0 {
			assert volume_seal_io.derives == 1 && volume_seal_io.password_wipes == 1 && volume_seal_io.wrapping_wipes == 1
			volume_seal_io.new_opens++
		}
		if flags & C.O_DIRECTORY != 0 { assert volume_seal_io.derives == 2 }
		if volume_seal_io.mode == 28 && C.strcmp(path, c'/dev/urandom') == 0 { unsafe { C.errno = C.EIO }; return -1 }
	}
	if C.strcmp(path, c'/volume-seal-parent') == 0 {
		assert flags & C.O_NONBLOCK != 0
		assert volume_seal_io.derives == if volume_seal_io.creating { 0 } else { 1 }
		assert flags & C.O_ACCMODE == if volume_seal_io.creating || volume_seal_io.growing || volume_seal_io.expected_flags == 1 { C.O_RDONLY } else { C.O_RDWR }
		volume_seal_io.parent_opens++; volume_seal_io.parent_flags = flags
		if volume_seal_io.mode == 11 { unsafe { C.errno = C.EACCES }; return -1 }
		volume_seal_io.opened++; return 900
	}
	fd := C.open(path, flags)
	if fd >= 0 { volume_seal_io.opened++; if flags & C.O_DIRECTORY != 0 { volume_seal_io.directory = fd } }
	return fd
}

fn volume_seal_mock_close(fd i32) i32 {
	volume_seal_io.closed++
	result := if fd == 900 { i32(0) } else { C.close(fd) }
	if fd == volume_seal_io.directory { volume_seal_io.locked = false }
	if fd == volume_seal_io.temporary && volume_seal_io.publication == 9 { unsafe { C.errno = C.EIO }; return -1 }
	return result
}

fn volume_seal_mock_ioctl(fd i32, number u64, output voidptr) i32 {
	assert !volume_seal_io.rewrapping
	assert fd == 900
	if number == 0x56560006 {
		assert !volume_seal_io.growing
		assert !volume_seal_io.creating && volume_seal_io.statuses == 2
		request := unsafe { &EncryptedRequest(output) }
		assert request.data.version == 1 && request.data.slot == 5 && request.data.offset == volume_seal_io.sector * 2 && request.data.length == 4096
		assert request.data.flags == volume_seal_io.expected_flags
		for i in 0 .. 64 { assert request.key[i] == u8(i * 13 + 7) }
		volume_seal_io.imports++
		if volume_seal_io.mode == 24 { unsafe { C.errno = C.EBUSY }; return -1 }
		return 0
	}
	assert number == 0x56560004
	volume_seal_io.statuses++
	if volume_seal_io.mode == 8 { unsafe { C.errno = C.EIO }; return -1 }
	mut status := Status{version: 1, bytes: volume_seal_io.physical_bytes, sector: volume_seal_io.sector, flags: 4, disk_id: 7, slot: u64(-1)}
	match volume_seal_io.mode {
		4 { status.flags |= 2 }
		5 { status.flags |= 16; status.start = 512 }
		6 { status.flags |= 8 }
		7 { status.sector = 1024 }
		12 { if volume_seal_io.statuses == 2 { status.disk_id++ } }
		14 { if volume_seal_io.statuses == 2 { status.sector = if status.sector == 512 { 4096 } else { 512 } } }
		15 { if volume_seal_io.statuses == 2 { status.bytes += status.sector } }
		16 { if volume_seal_io.statuses == 2 { status.flags |= 1 } }
		17 { if volume_seal_io.statuses == 2 { status.flags |= 2 } }
		29 { if volume_seal_io.statuses == 3 { status.disk_id++ } }
		31 { if volume_seal_io.statuses == 3 { status.bytes += status.sector } }
		32 { if volume_seal_io.statuses == 3 { status.flags |= 1 } }
		33 { if volume_seal_io.statuses == 3 { status.flags |= 2 } }
		36 { status.bytes -= status.sector }
		37 { status.sector = if status.sector == 512 { 4096 } else { 512 } }
		else {}
	}
	unsafe { *(&Status(output)) = status }
	return 0
}

fn volume_seal_mock_pread(fd i32, output voidptr, size usize, offset i64) i64 {
	assert fd == 900 && offset == 0 && size >= 1024 && size <= 8192
	volume_seal_io.disk_reads++
	if volume_seal_io.mode == 1 && volume_seal_io.disk_reads == 1 { unsafe { C.errno = C.EINTR }; return -1 }
	if volume_seal_io.mode == 9 || (volume_seal_io.mode == 18 && volume_seal_io.statuses == 2) || (volume_seal_io.mode == 34 && volume_seal_io.statuses == 3) { return i64(size - 1) }
	if (volume_seal_io.mode == 19 && volume_seal_io.statuses == 2) || (volume_seal_io.mode == 35 && volume_seal_io.statuses == 3) { unsafe { C.errno = C.EIO }; return -1 }
	unsafe { for i in 0 .. int(size) { (&u8(output))[i] = 0 } }
	identity := if volume_seal_io.mode == 2 { u64(0) } else if volume_seal_io.mode == 3 || (volume_seal_io.mode == 13 && volume_seal_io.statuses == 2) || (volume_seal_io.mode == 30 && volume_seal_io.statuses == 3) { u64(2) } else { u64(1) }
	put_le(&u8(output), 440, 4, identity); put_le(&u8(output), 510, 2, 0xaa55)
	if volume_seal_io.kind == 2 {
		put_le(&u8(output), 450, 1, 0xee)
		header := unsafe { &u8(output) + int(size / 2) }
		put_le(header, 0, 8, 0x5452415020494645); put_le(header, 8, 4, 0x10000); put_le(header, 12, 4, 92); put_le(header, 24, 8, 1)
		put_le(header, 56, 1, identity)
		if identity != 0 { put_le(header, 71, 1, 0x83) }
		put_le(header, 16, 4, crc32(header, 92, 16))
		if volume_seal_io.mode == 20 { put_le(header, 16, 4, 0) }
	} else if volume_seal_io.mode == 20 { put_le(&u8(output), 510, 2, 0) }
	return i64(size)
}

fn volume_seal_mock_derive(password &u8, size int, salt &u8, output &u8) bool {
	assert size > 0 && size <= 1024
	volume_seal_io.derives++
	if volume_seal_io.growing {
		assert size == volume_seal_io.grow_password_size
		unsafe {
			if size == 6 {
				expected := [u8(0), u8(10), u8(0xe2), u8(0x82), u8(0xac), u8(0xff)]!
				for i in 0 .. 6 { assert password[i] == expected[i] }
				for i in 6 .. 1024 { assert password[i] == 0 }
			} else { assert size == 1024; for i in 0 .. 1024 { assert password[i] == u8(i * 11 + 1) } }
			for i in 0 .. 64 { assert output[i] == 0 }
			if volume_seal_io.derives == 1 { volume_seal_io.password_buffer = password; volume_seal_io.wrapping_buffer = output }
			else {
				assert volume_seal_io.derives == 2 && volume_seal_io.statuses == 2 && volume_seal_io.wrapping_wipes == 1
				if volume_seal_io.mode == 25 { return false }
				for i in 0 .. 64 { output[i] = if volume_seal_io.mode == 26 { u8(7) } else if volume_seal_io.mode == 27 { u8(i * 13 + 7) } else { u8(i * 17 + 29) } }
				return true
			}
		}
	}
	if volume_seal_io.rewrapping {
		unsafe {
			for i in 0 .. 64 { assert output[i] == 0 }
			if volume_seal_io.derives == 1 {
				volume_seal_io.password_buffer = password; volume_seal_io.wrapping_buffer = output
				assert size == 1024
				for i in 0 .. size { assert password[i] == u8(i * 11 + 1) }
			} else {
				assert volume_seal_io.derives == 2 && size == 6 && volume_seal_io.new_opens == 1
				expected := [u8(0), u8(10), u8(0xe2), u8(0x82), u8(0xac), u8(0xff)]!
				for i in 0 .. 6 { assert password[i] == expected[i] }
				for i in 6 .. 1024 { assert password[i] == 0 }
				if volume_seal_io.mode == 25 { return false }
				for i in 0 .. 64 { output[i] = if volume_seal_io.mode == 26 { u8(7) } else if volume_seal_io.mode == 27 { u8(i * 13 + 7) } else { u8(i * 17 + 29) } }
				return true
			}
		}
	}
	if volume_seal_io.mode == 21 { return false }
	unsafe { for i in 0 .. 64 { output[i] = u8(i * 29 + 41) }; if volume_seal_io.mode == 22 { output[0] ^= 1 } }
	return true
}

fn volume_seal_mock_erase(pointer voidptr, size usize) {
	erase_key(pointer, size)
	unsafe { for i in usize(0) .. size { assert (&u8(pointer))[i] == 0 } }
	if size == sizeof(VolumeSealFiles) { volume_seal_io.wipes++ }
	if volume_seal_io.rewrapping || volume_seal_io.growing {
		if size == 1024 && pointer == voidptr(volume_seal_io.password_buffer) { volume_seal_io.password_wipes++ }
		if size == 64 && pointer == voidptr(volume_seal_io.wrapping_buffer) { volume_seal_io.wrapping_wipes++ }
	}
}

fn test_volume_growth_authenticates_before_readonly_parent_preserves_key_and_publishes_only_verified_growth() {
	work := os.join_path(os.temp_dir(), 'vinix-volume-growth-io-${os.getpid()}')
	os.mkdir(work)!; os.chmod(work, 0o700)!; defer { os.rmdir_all(work) or {} }
	password := [u8(0), u8(10), u8(0xe2), u8(0x82), u8(0xac), u8(0xff)]
	os.write_file_array(work + '/pass', password)!; os.chmod(work + '/pass', 0o600)!
	mut wrapping := [64]u8{init: u8(index * 29 + 41)}; mut fresh := [64]u8{init: u8(index * 17 + 29)}
	mut random := [28]u8{init: u8(index * 11 + 3)}; mut source := [320]u8{}
	for sector in [u64(512), u64(4096)] {
		for kind in [u32(1), u32(2)] {
			for flags in [u64(0), u64(1)] {
				mut disk := DiskKey{bytes: 16777216, sector: sector, kind: kind}; disk.id[0] = 1; if kind == 2 { disk.id[15] = 0x83 }
				request := EncryptedRequest{data: Request{slot: 5, offset: sector * 2, length: 4096, flags: flags}, key: [64]u8{init: u8(index * 13 + 7)}}
				assert encode_volume_seal(&disk, &request, &wrapping[0], &random[0], &source[0])
				os.write_file_array(work + '/source', source[..])!; os.chmod(work + '/source', 0o600)!
				for capacity in [u64(16777216), u64(25165824)] {
					for length in [u64(4096), u64(8192), capacity - request.data.offset] {
						volume_seal_io = VolumeSealIO{growing: true, sector: sector, kind: kind, physical_bytes: capacity}
						assert plan_grow_volume_seal(c'/volume-seal-parent', (work + '/source').str, (work + '/pass').str, length, (work + '/result').str) == 0
						assert volume_seal_io.opened == volume_seal_io.closed && volume_seal_io.wipes == 1 && volume_seal_io.imports == 0
						assert volume_seal_io.derives == 2 && volume_seal_io.statuses == 3 && volume_seal_io.parent_opens == 1 && !volume_seal_io.locked
						result := os.read_bytes(work + '/result')!; mut next_disk := DiskKey{}; mut next := EncryptedRequest{}
						assert decode_volume_seal(&result[0], 320, &fresh[0], mut next_disk, mut next)
						mut expected_disk := disk; expected_disk.bytes = capacity; mut expected := request; expected.data.length = length
						assert next_disk == expected_disk && next == expected
						assert result[40..56] != source[40..56] && result[56..68] != source[56..68]
						assert os.read_bytes(work + '/source')! == source[..] && os.read_bytes(work + '/pass')! == password
						os.rm(work + '/result')!
					}
				}
			}
		}
	}
	// Reset to a 512-byte MBR fixture for all failure boundaries.
	mut disk := DiskKey{bytes: 16777216, sector: 512, kind: 1}; disk.id[0] = 1
	request := EncryptedRequest{data: Request{slot: 5, offset: 1024, length: 4096}, key: [64]u8{init: u8(index * 13 + 7)}}
	assert encode_volume_seal(&disk, &request, &wrapping[0], &random[0], &source[0])
	os.write_file_array(work + '/source', source[..])!
	for mode in [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37] {
		volume_seal_io = VolumeSealIO{growing: true, mode: mode}
		assert plan_grow_volume_seal(c'/volume-seal-parent', (work + '/source').str, (work + '/pass').str, 8192, (work + '/result').str) == if mode <= 1 { 0 } else { 1 }
		assert volume_seal_io.opened == volume_seal_io.closed && volume_seal_io.wipes == 1 && volume_seal_io.imports == 0 && !volume_seal_io.locked
		if mode in [21, 22] { assert volume_seal_io.parent_opens == 0 }
		assert os.exists(work + '/result') == (mode <= 1); if os.exists(work + '/result') { os.rm(work + '/result')! }
	}
	for length in [u64(0), u64(512), u64(4095), u64(8193), u64(16777216), u64(-1)] {
		volume_seal_io = VolumeSealIO{growing: true}
		assert plan_grow_volume_seal(c'/volume-seal-parent', (work + '/source').str, (work + '/pass').str, length, (work + '/result').str) == 1
		assert volume_seal_io.opened == volume_seal_io.closed && volume_seal_io.wipes == 1 && volume_seal_io.imports == 0 && !os.exists(work + '/result')
		if length < 4096 { assert volume_seal_io.parent_opens == 0 }
	}
	for publication in 0 .. 11 {
		volume_seal_io = VolumeSealIO{growing: true, publication: publication}
		assert plan_grow_volume_seal(c'/volume-seal-parent', (work + '/source').str, (work + '/pass').str, 8192, (work + '/result').str) == if publication in [0, 10] { 0 } else { 1 }
		assert volume_seal_io.opened == volume_seal_io.closed && volume_seal_io.wipes == 1 && volume_seal_io.imports == 0 && !volume_seal_io.locked
		if os.exists(work + '/result') {
			result := os.read_bytes(work + '/result')!; mut next_disk := DiskKey{}; mut next := EncryptedRequest{}
			assert decode_volume_seal(&result[0], 320, &fresh[0], mut next_disk, mut next) && next.key == request.key && next.data.length == 8192
			os.rm(work + '/result')!
		}
		assert os.ls(work)!.all(!it.starts_with('.vinix-key-'))
	}
	os.write_file_array(work + '/pass', []u8{len: 1024, init: u8(index * 11 + 1)})!
	volume_seal_io = VolumeSealIO{growing: true, grow_password_size: 1024}
	assert plan_grow_volume_seal(c'/volume-seal-parent', (work + '/source').str, (work + '/pass').str, 8192, (work + '/result').str) == 0
	assert volume_seal_io.opened == volume_seal_io.closed && volume_seal_io.wipes == 1 && volume_seal_io.imports == 0
	os.rm(work + '/result')!; os.write_file_array(work + '/pass', password)!
	for at in [0, 68, 144, 192, 288] {
		mut bad := source; bad[at] ^= 1; os.write_file_array(work + '/bad', bad[..])!; os.chmod(work + '/bad', 0o600)!
		volume_seal_io = VolumeSealIO{growing: true}
		assert plan_grow_volume_seal(c'/volume-seal-parent', (work + '/bad').str, (work + '/pass').str, 8192, (work + '/result').str) == 1
		assert volume_seal_io.opened == volume_seal_io.closed && volume_seal_io.wipes == 1 && volume_seal_io.parent_opens == 0 && !os.exists(work + '/result')
	}
	os.symlink(work + '/source', work + '/link')!; os.link(work + '/source', work + '/alias')!
	assert os.exec(['mkfifo', work + '/fifo']).exit_code == 0; os.mkdir(work + '/dir')!
	for name in ['source', 'pass', 'link', 'alias', 'fifo', 'dir'] {
		volume_seal_io = VolumeSealIO{growing: true}
		assert plan_grow_volume_seal(c'/volume-seal-parent', (work + '/source').str, (work + '/pass').str, 8192, (work + '/' + name).str) == 1
		assert volume_seal_io.opened == volume_seal_io.closed && volume_seal_io.wipes == 1 && volume_seal_io.imports == 0
	}
	assert os.read_bytes(work + '/source')! == source[..] && os.read_bytes(work + '/pass')! == password
}

fn test_volume_rewrap_authenticates_before_new_input_preserves_metadata_and_erases_each_stage() {
	work := os.join_path(os.temp_dir(), 'vinix-volume-rewrap-io-${os.getpid()}')
	os.mkdir(work)!; os.chmod(work, 0o700)!; defer { os.rmdir_all(work) or {} }
	old := []u8{len: 1024, init: u8(index * 11 + 1)}
	next := [u8(0), u8(10), u8(0xe2), u8(0x82), u8(0xac), u8(0xff)]
	os.write_file_array(work + '/old', old)!; os.chmod(work + '/old', 0o600)!
	os.write_file_array(work + '/next', next)!; os.chmod(work + '/next', 0o600)!
	mut wrapping := [64]u8{}; mut fresh := [64]u8{}; mut random := [28]u8{init: u8(index * 11 + 3)}; mut source := [320]u8{}
	mut request := EncryptedRequest{data: Request{slot: 5, length: 4096}}
	for i in 0 .. 64 { wrapping[i] = u8(i * 29 + 41); fresh[i] = u8(i * 17 + 29); request.key[i] = u8(i * 13 + 7) }
	for sector in [u64(512), u64(4096)] {
		for kind in [u32(1), u32(2)] {
			for mode in [u64(0), u64(1)] {
				mut disk := DiskKey{bytes: 16777216, sector: sector, kind: kind}; disk.id[0] = 1
				if kind == 2 { disk.id[15] = 0x83 }; request.data.offset = sector * 2; request.data.flags = mode
				assert encode_volume_seal(&disk, &request, &wrapping[0], &random[0], &source[0])
				os.write_file_array(work + '/source', source[..])!; os.chmod(work + '/source', 0o600)!
				volume_seal_io = VolumeSealIO{rewrapping: true, new_input: (work + '/next').str}
				assert rewrap_volume_seal((work + '/source').str, (work + '/old').str, (work + '/next').str, (work + '/result').str) == 0
				assert volume_seal_io.opened == volume_seal_io.closed && volume_seal_io.wipes == 1 && volume_seal_io.new_opens == 1
				assert volume_seal_io.parent_opens == 0 && volume_seal_io.imports == 0 && volume_seal_io.derives == 2 && !volume_seal_io.locked
				result := os.read_bytes(work + '/result')!; mut decoded_disk := DiskKey{}; mut decoded := EncryptedRequest{}
				assert decode_volume_seal(&result[0], 320, &fresh[0], mut decoded_disk, mut decoded)
				assert decoded_disk == disk && decoded == request && os.read_bytes(work + '/source')! == source[..]
				os.rm(work + '/result')!
			}
		}
	}
	for mode in [21, 22, 25, 26, 27, 28] {
		volume_seal_io = VolumeSealIO{rewrapping: true, new_input: (work + '/next').str, mode: mode}
		assert rewrap_volume_seal((work + '/source').str, (work + '/old').str, (work + '/next').str, (work + '/result').str) == 1
		assert volume_seal_io.opened == volume_seal_io.closed && volume_seal_io.wipes == 1 && volume_seal_io.parent_opens == 0 && volume_seal_io.imports == 0
		assert volume_seal_io.new_opens == if mode in [21, 22] { 0 } else { 1 }
		assert !os.exists(work + '/result') && os.read_bytes(work + '/source')! == source[..]
	}
	os.write_file(work + '/empty', '')!; os.chmod(work + '/empty', 0o600)!
	os.write_file_array(work + '/long', []u8{len: 1025, init: 7})!; os.chmod(work + '/long', 0o600)!
	os.write_file_array(work + '/public', next)!; os.chmod(work + '/public', 0o644)!
	os.symlink(work + '/next', work + '/link')!; os.mkdir(work + '/dir')!
	assert os.exec(['mkfifo', work + '/fifo']).exit_code == 0
	for name in ['absent', 'empty', 'long', 'public', 'link', 'dir', 'fifo'] {
		input := work + '/' + name
		volume_seal_io = VolumeSealIO{rewrapping: true, new_input: input.str}
		assert rewrap_volume_seal((work + '/source').str, (work + '/old').str, input.str, (work + '/result').str) == 1
		assert volume_seal_io.opened == volume_seal_io.closed && volume_seal_io.wipes == 1 && volume_seal_io.new_opens == 1 && volume_seal_io.derives == 1
		assert volume_seal_io.parent_opens == 0 && volume_seal_io.imports == 0 && !os.exists(work + '/result')
	}
	for at in [0, 24, 88, 152, 192, 288] {
		mut bad := source; bad[at] ^= 1
		os.write_file_array(work + '/bad', bad[..])!; os.chmod(work + '/bad', 0o600)!
		volume_seal_io = VolumeSealIO{rewrapping: true, new_input: (work + '/next').str}
		assert rewrap_volume_seal((work + '/bad').str, (work + '/old').str, (work + '/next').str, (work + '/result').str) == 1
		assert volume_seal_io.new_opens == 0 && volume_seal_io.opened == volume_seal_io.closed && volume_seal_io.wipes == 1 && !os.exists(work + '/result')
	}
	for publication in 0 .. 11 {
		volume_seal_io = VolumeSealIO{rewrapping: true, new_input: (work + '/next').str, publication: publication}
		assert rewrap_volume_seal((work + '/source').str, (work + '/old').str, (work + '/next').str, (work + '/result').str) == if publication in [0, 10] { 0 } else { 1 }
		assert volume_seal_io.opened == volume_seal_io.closed && volume_seal_io.wipes == 1 && volume_seal_io.parent_opens == 0 && volume_seal_io.imports == 0 && !volume_seal_io.locked
		assert os.exists(work + '/result') == (publication in [0, 6, 7, 8, 10])
		if os.exists(work + '/result') {
			result := os.read_bytes(work + '/result')!; mut disk := DiskKey{}; mut decoded := EncryptedRequest{}
			assert decode_volume_seal(&result[0], 320, &fresh[0], mut disk, mut decoded) && decoded == request
			os.rm(work + '/result')!
		}
		assert os.ls(work)!.all(!it.starts_with('.vinix-key-'))
	}
	assert os.read_bytes(work + '/source')! == source[..] && os.read_bytes(work + '/old')! == old && os.read_bytes(work + '/next')! == next
}

fn volume_seal_mock_flock(fd i32, flags i32) i32 {
	assert fd == volume_seal_io.directory && flags == C.LOCK_EX | C.LOCK_NB
	if volume_seal_io.publication == 1 { unsafe { C.errno = C.EWOULDBLOCK }; return -1 }
	result := C.flock(fd, flags); if result == 0 { volume_seal_io.locked = true }; return result
}

fn volume_seal_mock_openat(fd i32, name &char, flags i32, mode u32) i32 {
	assert volume_seal_io.locked && fd == volume_seal_io.directory && mode == 0o600
	assert flags & (C.O_CREAT | C.O_EXCL | C.O_NOFOLLOW | C.O_CLOEXEC) == C.O_CREAT | C.O_EXCL | C.O_NOFOLLOW | C.O_CLOEXEC
	if volume_seal_io.publication == 2 { unsafe { C.errno = C.EACCES }; return -1 }
	opened := C.openat(fd, name, flags, mode)
	if opened >= 0 { volume_seal_io.temporary = opened; volume_seal_io.opened++ }
	return opened
}

fn volume_seal_mock_write(fd i32, data voidptr, size usize) i64 {
	assert volume_seal_io.locked && fd == volume_seal_io.temporary
	volume_seal_io.writes++
	if volume_seal_io.publication == 10 && volume_seal_io.writes == 1 { unsafe { C.errno = C.EINTR }; return -1 }
	if volume_seal_io.publication == 3 { return 0 }
	return C.write(fd, data, if size > 7 { usize(7) } else { size })
}

fn volume_seal_mock_fsync(fd i32) i32 {
	assert volume_seal_io.locked
	if (volume_seal_io.publication == 4 && fd == volume_seal_io.temporary) || (volume_seal_io.publication == 7 && fd == volume_seal_io.directory) { unsafe { C.errno = C.EIO }; return -1 }
	return C.fsync(fd)
}

fn volume_seal_mock_linkat(old i32, source &char, next i32, destination &char, flags i32) i32 {
	assert volume_seal_io.locked && old == volume_seal_io.directory && next == old && flags == 0
	if volume_seal_io.publication == 5 { unsafe { C.errno = C.EIO }; return -1 }
	return C.linkat(old, source, next, destination, flags)
}

fn volume_seal_mock_unlinkat(fd i32, path &char, flags i32) i32 {
	assert volume_seal_io.locked && fd == volume_seal_io.directory && flags == 0
	volume_seal_io.unlinks++
	if volume_seal_io.publication == 6 && volume_seal_io.unlinks == 1 { unsafe { C.errno = C.EIO }; return -1 }
	return C.unlinkat(fd, path, flags)
}

fn volume_seal_mock_fflush(stream voidptr) i32 {
	assert volume_seal_io.locked || volume_seal_io.imports > 0
	if volume_seal_io.publication == 8 { unsafe { C.errno = C.EIO }; return -1 }
	return C.fflush(stream)
}

fn test_volume_config_pinned_identity_geometry_rechecks_modes_authentication_and_publication_faults() {
	work := os.join_path(os.temp_dir(), 'vinix-volume-seal-io-${os.getpid()}')
	os.mkdir(work)!; os.chmod(work, 0o700)!; defer { os.rmdir_all(work) or {} }
	key := []u8{len: 64, init: u8(index * 13 + 7)}
	os.write_file_array(work + '/key', key)!; os.chmod(work + '/key', 0o600)!
	os.write_file(work + '/pass', 'private volume configuration fixture')!; os.chmod(work + '/pass', 0o600)!
	for sector in [u64(512), u64(4096)] {
		for kind in [u32(1), u32(2)] {
			for mode in [u64(0), u64(1)] {
				request := Request{slot: 5, offset: 1024, length: 4096, flags: mode}
				// Native 4096-byte sectors need a correspondingly aligned start.
				mut data := request; data.offset = sector * 2
				volume_seal_io = VolumeSealIO{creating: true, sector: sector, kind: kind}
				assert seal_volume_file(c'/volume-seal-parent', (work + '/key').str, (work + '/pass').str, (work + '/config').str, &data) == 0
				assert volume_seal_io.opened == volume_seal_io.closed && volume_seal_io.wipes == 1 && volume_seal_io.statuses == 2 && volume_seal_io.imports == 0
				for readonly in [false, true] {
					volume_seal_io = VolumeSealIO{sector: sector, kind: kind, expected_flags: mode | u64(readonly)}
					assert open_volume_seal(c'/volume-seal-parent', (work + '/config').str, (work + '/pass').str, readonly) == 0
					assert volume_seal_io.opened == volume_seal_io.closed && volume_seal_io.wipes == 1 && volume_seal_io.imports == 1
				}
				volume_seal_io = VolumeSealIO{}
				assert unseal_volume_key((work + '/config').str, (work + '/pass').str, (work + '/recovered').str) == 0
				assert volume_seal_io.opened == volume_seal_io.closed && volume_seal_io.wipes == 1 && volume_seal_io.parent_opens == 0 && os.read_bytes(work + '/recovered')! == key
				os.rm(work + '/recovered')!; os.rm(work + '/config')!
			}
		}
	}
	data := Request{slot: 5, offset: 1024, length: 4096}
	volume_seal_io = VolumeSealIO{creating: true}
	assert seal_volume_file(c'/volume-seal-parent', (work + '/key').str, (work + '/pass').str, (work + '/config').str, &data) == 0
	config := os.read_bytes(work + '/config')!
	for mode in [0, 1, 2, 4, 5, 6, 7, 8, 9, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21] {
		volume_seal_io = VolumeSealIO{creating: true, mode: mode}
		assert seal_volume_file(c'/volume-seal-parent', (work + '/key').str, (work + '/pass').str, (work + '/output').str, &data) == if mode <= 1 { 0 } else { 1 }
		assert volume_seal_io.opened == volume_seal_io.closed && volume_seal_io.wipes == 1 && volume_seal_io.imports == 0
		assert os.exists(work + '/output') == (mode <= 1)
		if os.exists(work + '/output') { os.rm(work + '/output')! }
	}
	for readonly in [false, true] {
		for mode in [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 24] {
			volume_seal_io = VolumeSealIO{mode: mode, expected_flags: u64(readonly)}
			assert open_volume_seal(c'/volume-seal-parent', (work + '/config').str, (work + '/pass').str, readonly) == if mode <= 1 { 0 } else { 1 }
			assert volume_seal_io.opened == volume_seal_io.closed && volume_seal_io.wipes == 1
			assert volume_seal_io.imports == if mode <= 1 || mode == 24 { 1 } else { 0 }
			if mode in [21, 22] { assert volume_seal_io.parent_opens == 0 }
		}
	}
	for at in [0, 8, 12, 16, 20, 24, 32, 36, 68, 80, 88, 96, 100, 120, 128, 136, 144, 152, 256] {
		mut bad := config.clone(); bad[at] ^= if at == 144 { u8(2) } else { u8(1) }
		os.write_file_array(work + '/bad', bad)!; os.chmod(work + '/bad', 0o600)!
		volume_seal_io = VolumeSealIO{}
		assert open_volume_seal(c'/volume-seal-parent', (work + '/bad').str, (work + '/pass').str, false) == 1
		assert volume_seal_io.derives == 0 && volume_seal_io.parent_opens == 0 && volume_seal_io.wipes == 1 && volume_seal_io.opened == volume_seal_io.closed
	}
	for exporting in [false, true] {
		for publication in 0 .. 11 {
			volume_seal_io = VolumeSealIO{creating: !exporting, publication: publication}
			result := if exporting { unseal_volume_key((work + '/config').str, (work + '/pass').str, (work + '/output').str) }
				else { seal_volume_file(c'/volume-seal-parent', (work + '/key').str, (work + '/pass').str, (work + '/output').str, &data) }
			assert result == if publication in [0, 10] { 0 } else { 1 }
			assert volume_seal_io.opened == volume_seal_io.closed && volume_seal_io.wipes == 1 && !volume_seal_io.locked && volume_seal_io.imports == 0
			assert os.exists(work + '/output') == (publication in [0, 6, 7, 8, 10])
			if os.exists(work + '/output') {
				assert os.file_size(work + '/output') == if exporting { u64(64) } else { u64(320) }
				if exporting { assert os.read_bytes(work + '/output')! == key }
				os.rm(work + '/output')!
			}
			assert os.ls(work)!.all(!it.starts_with('.vinix-key-'))
		}
	}
	assert os.read_bytes(work + '/config')! == config && os.read_bytes(work + '/key')! == key
}

// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module volumecli

import os

struct VolumeDiscoveryIO {
mut:
	directory string
	mode int
	sector u64 = 512
	flags u64
	opened int
	closed int
	scans int
	derives int
	imports int
	wipes int
	stream_fd i32 = -1
	indices [4096]int
	live [4096]bool
	statuses [7]int
	reads int
	password &u8 = unsafe { nil }
	wrapping &u8 = unsafe { nil }
	boot bool
	etc string
	input_reads int
	config_stats int
	etc_stats int
	vinix_stats int
}
__global volume_discovery_io VolumeDiscoveryIO

fn volume_discovery_track(fd i32, index int) i32 {
	if fd >= 0 { assert fd < 4096; volume_discovery_io.live[fd] = true; volume_discovery_io.indices[fd] = index; volume_discovery_io.opened++ }
	return fd
}

fn volume_discovery_mock_open(path &char, flags i32) i32 {
	if volume_discovery_io.boot && C.strcmp(path, c'/etc') == 0 {
		assert flags == C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC
		if volume_discovery_io.mode in [100, 101] { unsafe { C.errno = if volume_discovery_io.mode == 101 { C.ENOENT } else { C.EACCES } }; return -1 }
		return volume_discovery_track(C.open(volume_discovery_io.etc.str, flags), -2)
	}
	if C.strcmp(path, c'/dev') == 0 {
		assert volume_discovery_io.derives == 1
		unsafe {
			for i in 0 .. 1024 { assert volume_discovery_io.password[i] == 0 }
			for i in 0 .. 64 { assert volume_discovery_io.wrapping[i] == 0 }
		}
		volume_discovery_io.scans++
		assert flags == C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC
		if volume_discovery_io.mode == 3 { unsafe { C.errno = C.EACCES }; return -1 }
		fd := volume_discovery_track(C.open(volume_discovery_io.directory.str, flags), -1)
		volume_discovery_io.stream_fd = fd; return fd
	}
	return volume_discovery_track(C.open(path, flags), -1)
}

fn volume_discovery_mock_close(fd i32) i32 {
	assert fd >= 0 && fd < 4096 && volume_discovery_io.live[fd]
	volume_discovery_io.live[fd] = false; volume_discovery_io.closed++
	return C.close(fd)
}

fn volume_discovery_mock_fdopendir(fd i32) &C.DIR {
	if volume_discovery_io.mode == 4 { unsafe { C.errno = C.EIO }; return unsafe { nil } }
	return C.fdopendir(fd)
}

fn volume_discovery_mock_closedir(stream &C.DIR) i32 {
	fd := volume_discovery_io.stream_fd; assert volume_discovery_io.live[fd]
	volume_discovery_io.live[fd] = false; volume_discovery_io.closed++
	return C.closedir(stream)
}

fn volume_discovery_mock_readdir(stream &C.DIR) &C.dirent {
	entry := C.readdir(stream)
	if entry == unsafe { nil } && volume_discovery_io.mode == 5 { unsafe { C.errno = C.EIO } }
	return entry
}

fn volume_discovery_mock_fstatat(fd i32, name &char, info &C.stat, flags i32) i32 {
	if volume_discovery_io.mode == 6 { unsafe { C.errno = C.EIO }; return -1 }
	result := C.fstatat(fd, name, info, flags)
	if result == 0 && unsafe { name[0] >= `0` && name[0] <= `6` } { unsafe { info.st_mode = C.S_IFBLK | 0o600 } }
	return result
}

fn volume_discovery_mock_openat(fd i32, name &char, flags i32) i32 {
	if volume_discovery_io.boot && volume_discovery_io.indices[fd] < -1 {
		if C.strcmp(name, c'vinix') == 0 {
			assert volume_discovery_io.indices[fd] == -2 && flags == C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC
			if volume_discovery_io.mode in [102, 103] { unsafe { C.errno = if volume_discovery_io.mode == 102 { C.ENOENT } else { C.EACCES } }; return -1 }
			return volume_discovery_track(C.openat(fd, name, flags), -3)
		}
		assert volume_discovery_io.indices[fd] == -3
		if C.strcmp(name, c'volumes.d') == 0 { return volume_discovery_track(C.openat(fd, name, flags), -1) }
		assert flags == C.O_RDONLY | C.O_NOFOLLOW | C.O_NONBLOCK | C.O_CLOEXEC
		index := if C.strcmp(name, c'boot-volume.vcrypt') == 0 { -4 } else if C.strcmp(name, c'boot-volume.pass') == 0 { -5 } else { -1 }
		if index == -5 && volume_discovery_io.mode == 110 { unsafe { C.errno = C.EIO }; return -1 }
		return volume_discovery_track(C.openat(fd, name, flags), index)
	}
	assert flags & (C.O_NOFOLLOW | C.O_NONBLOCK | C.O_CLOEXEC) == C.O_NOFOLLOW | C.O_NONBLOCK | C.O_CLOEXEC
	if volume_discovery_io.mode == 7 || (volume_discovery_io.mode == 15 && flags & C.O_ACCMODE == C.O_RDWR) { unsafe { C.errno = C.EIO }; return -1 }
	index := unsafe { int(name[0]) - int(`0`) }; assert index >= 0 && index < 7
	return volume_discovery_track(C.openat(fd, name, flags), index)
}

fn volume_discovery_mock_fstat(fd i32, info &C.stat) i32 {
	if volume_discovery_io.mode == 22 && volume_discovery_io.indices[fd] >= 0 { unsafe { C.errno = C.EIO }; return -1 }
	result := C.fstat(fd, info)
	if result == 0 && volume_discovery_io.boot {
		unsafe { info.st_uid = 0 }
		index := volume_discovery_io.indices[fd]
		if index == -2 { volume_discovery_io.etc_stats++ }
		if index == -3 { volume_discovery_io.vinix_stats++ }
		if index == -4 { volume_discovery_io.config_stats++ }
		unsafe {
			if (index == -2 && volume_discovery_io.mode == 104) || (index == -4 && volume_discovery_io.mode == 106)
				|| (index == -5 && volume_discovery_io.mode == 108) { info.st_uid = 1 }
			if (index == -3 && volume_discovery_io.mode == 105) || (index == -4 && volume_discovery_io.mode == 107)
				|| (index == -5 && volume_discovery_io.mode == 109) { info.st_mode |= 0o022 }
			if index == -4 && volume_discovery_io.mode == 115 && volume_discovery_io.config_stats == 2 { info.st_uid = 1 }
			if index == -2 && volume_discovery_io.mode == 116 && volume_discovery_io.etc_stats == 2 { info.st_mode |= 0o002 }
			if index == -3 && volume_discovery_io.mode == 118 && volume_discovery_io.vinix_stats == 3 { info.st_mode |= 0o002 }
		}
	}
	if result == 0 && volume_discovery_io.indices[fd] >= 0 && volume_discovery_io.mode != 8 { unsafe { info.st_mode = C.S_IFBLK | 0o600 } }
	return result
}

fn volume_discovery_mock_geteuid() u32 {
	return if volume_discovery_io.boot { if volume_discovery_io.mode == 117 { u32(1) } else { u32(0) } } else { C.geteuid() }
}

fn volume_discovery_mock_read(fd i32, output voidptr, size usize) i64 {
	if volume_discovery_io.boot {
		volume_discovery_io.input_reads++
		if volume_discovery_io.mode == 112 && volume_discovery_io.indices[fd] == -4 { return 0 }
		if volume_discovery_io.mode == 113 && volume_discovery_io.input_reads == 1 { unsafe { C.errno = C.EINTR }; return -1 }
		if volume_discovery_io.mode == 114 && volume_discovery_io.indices[fd] == -5 { unsafe { C.errno = C.EIO }; return -1 }
	}
	return C.read(fd, output, size)
}

fn volume_discovery_mock_ioctl(fd i32, number u64, output voidptr) i32 {
	index := volume_discovery_io.indices[fd]; assert index >= 0 && index < 7
	if number == 0x56560006 {
		assert volume_discovery_io.statuses[index] == if volume_discovery_io.flags == 0 { 4 } else { 3 }
		request := unsafe { &EncryptedRequest(output) }
		assert request.data == Request{slot: 5, offset: volume_discovery_io.sector * 2, length: 4096, flags: volume_discovery_io.flags}
		unsafe { for i in 0 .. 64 { assert request.key[i] == u8(i * 13 + 7) } }
		volume_discovery_io.imports++
		if volume_discovery_io.mode == 20 { unsafe { C.errno = C.EBUSY }; return -1 }
		return 0
	}
	assert number == 0x56560004
	volume_discovery_io.statuses[index]++
	count := volume_discovery_io.statuses[index]
	if volume_discovery_io.mode in [9, 12] || index == 6 { unsafe { C.errno = if volume_discovery_io.mode == 9 { C.EIO } else { C.ENOTTY } }; return -1 }
	mut status := Status{version: 1, bytes: 16777216, sector: volume_discovery_io.sector, flags: 4, disk_id: if index <= 1 { u64(7) } else { u64(8) }, slot: u64(-1)}
	if index == 4 { status.flags |= 16; status.start = 512 }; if index == 5 { status.flags |= 8 }
	first_final := if volume_discovery_io.flags == 0 { 3 } else { 2 }
	match volume_discovery_io.mode {
		10 { status.flags |= 2 }
		11 { status.bytes += status.sector }
		16 { if count == 2 { status.disk_id++ } }
		17 { if count == first_final { status.disk_id++ } }
		18 { if count == first_final + 1 { status.bytes += status.sector } }
		19 { if count == first_final { status.flags |= 1 } }
		else {}
	}
	unsafe { *(&Status(output)) = status }; return 0
}

fn volume_discovery_mock_pread(fd i32, output voidptr, size usize, offset i64) i64 {
	volume_discovery_io.reads++
	if volume_discovery_io.mode == 14 && volume_discovery_io.reads == 1 { unsafe { C.errno = C.EINTR }; return -1 }
	if volume_discovery_io.mode == 13 { return i64(size - 1) }
	return C.pread(fd, output, size, offset)
}

fn volume_discovery_mock_derive(password &u8, size int, salt &u8, output &u8) bool {
	assert size == 6; volume_discovery_io.derives++
	volume_discovery_io.password = password; volume_discovery_io.wrapping = output
	if volume_discovery_io.boot {
		expected := [u8(0), 10, 0xe2, 0x82, 0xac, 0xff]!
		unsafe { for i in 0 .. 6 { assert password[i] == expected[i] }; for i in 6 .. 1024 { assert password[i] == 0 } }
		if volume_discovery_io.mode == 119 {
			os.mv(volume_discovery_io.etc + '/vinix', volume_discovery_io.etc + '/pinned') or { panic(err) }
			os.mkdir(volume_discovery_io.etc + '/vinix') or { panic(err) }
			os.write_file(volume_discovery_io.etc + '/vinix/boot-volume.vcrypt', 'replacement ignored') or { panic(err) }
			os.write_file(volume_discovery_io.etc + '/vinix/boot-volume.pass', 'replacement ignored') or { panic(err) }
		}
	}
	if volume_discovery_io.mode == 2 { return false }
	unsafe { for i in 0 .. 64 { output[i] = u8(i * 29 + 41) }; if volume_discovery_io.mode == 1 { output[0] ^= 1 } }
	return true
}

fn volume_boot_check(etc string, directory string, flags u64, mode int, restore bool, expected i32) {
	volume_discovery_io = VolumeDiscoveryIO{boot: true, etc: etc, directory: directory, flags: flags, mode: mode}
	assert (if restore { boot_restore() } else { boot_unlock_volume() }) == expected
	assert volume_discovery_io.opened == volume_discovery_io.closed && volume_discovery_io.live.all(!it)
	assert volume_discovery_io.wipes == if mode in [100, 101, 102, 103] { 0 } else { 1 }
	assert volume_discovery_io.imports == if mode in [20, 21] || (expected == 0 && volume_discovery_io.scans > 0) { 1 } else { 0 }
}

fn test_opt_in_boot_unlock_pins_root_directories_private_inputs_and_preserves_failures() {
	work := os.join_path(os.temp_dir(), 'vinix-volume-boot-${os.getpid()}')
	os.mkdir_all(work + '/etc/vinix')!; os.mkdir(work + '/dev')!; defer { os.rmdir_all(work) or {} }
	os.chmod(work + '/etc', 0o755)!; os.chmod(work + '/etc/vinix', 0o700)!
	config := work + '/etc/vinix/boot-volume.vcrypt'; password := work + '/etc/vinix/boot-volume.pass'
	mut wrapping := [64]u8{init: u8(index * 29 + 41)}; mut random := [28]u8{init: u8(index * 11 + 3)}; mut source := [320]u8{}
	mut disk := DiskKey{bytes: 16777216, sector: 512, kind: 1}; disk.id[0] = 1
	volume_discovery_fixture(work + '/dev', 0, 512, 1)!
	for flags in [u64(0), u64(1)] {
		request := EncryptedRequest{data: Request{slot: 5, offset: 1024, length: 4096, flags: flags}, key: [64]u8{init: u8(index * 13 + 7)}}
		assert encode_volume_seal(&disk, &request, &wrapping[0], &random[0], &source[0])
		os.write_file_array(config, source[..])!; os.chmod(config, 0o600)!
		os.write_file_array(password, [u8(0), 10, 0xe2, 0x82, 0xac, 0xff])!; os.chmod(password, 0o600)!
		for restore in [false, true] {
			for mode in [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 17, 18, 19, 20, 21, 22,
				100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 112, 113, 114, 115, 116, 117] {
				volume_boot_check(work + '/etc', work + '/dev', flags, mode, restore, if mode in [0, 14, 101, 102, 113] { 0 } else { 1 })
				if mode in [1, 2, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 112, 114, 115, 116, 117] { assert volume_discovery_io.scans == 0 }
			}
		}
		volume_boot_check(work + '/etc', work + '/dev', flags, 118, true, 1); assert volume_discovery_io.scans == 0
		for at in [0, 68, 144, 192, 288] {
			mut bad := source; bad[at] ^= 1; os.write_file_array(config, bad[..])!
			volume_boot_check(work + '/etc', work + '/dev', flags, 0, false, 1); assert volume_discovery_io.scans == 0
		}
		os.write_file_array(config, source[..])!
	}
	for input in [config, password] {
		os.chmod(input, 0o644)!; volume_boot_check(work + '/etc', work + '/dev', 1, 0, false, 1); assert volume_discovery_io.scans == 0; os.chmod(input, 0o600)!
		os.mv(input, input + '.original')!; os.symlink(input + '.original', input)!
		volume_boot_check(work + '/etc', work + '/dev', 1, 0, false, 1); assert volume_discovery_io.scans == 0
		os.rm(input)!; os.mv(input + '.original', input)!
	}
	for restore in [false, true] {
		volume_boot_check(work + '/etc', work + '/dev', 1, 119, restore, 0)
		assert os.read_bytes(work + '/etc/pinned/boot-volume.vcrypt')! == source[..]
		assert os.read_file(config)! == 'replacement ignored'
		os.rmdir_all(work + '/etc/vinix')!; os.mv(work + '/etc/pinned', work + '/etc/vinix')!
	}
	os.rm(password)!; volume_boot_check(work + '/etc', work + '/dev', 1, 0, false, 1); assert volume_discovery_io.scans == 0
	os.write_file_array(password, [u8(0), 10, 0xe2, 0x82, 0xac, 0xff])!; os.chmod(password, 0o600)!
	mut plain := Plan{key: disk, count: 1}; plain.rows[0] = Request{slot: 5, offset: 8192, length: 4096}
	mut bytes := [2112]u8{}; size := encode_plan(&plain, &bytes[0]); assert size > 0
	os.write_file_array(work + '/etc/vinix/volumes.vmap', bytes[..size])!; os.chmod(work + '/etc/vinix/volumes.vmap', 0o600)!
	volume_boot_check(work + '/etc', work + '/dev', 1, 0, true, 1); assert volume_discovery_io.scans == 0 && volume_discovery_io.derives == 1
	plain.rows[0] = Request{slot: 1, offset: 2048, length: 512}; assert encode_plan(&plain, &bytes[0]) == size
	os.write_file_array(work + '/etc/vinix/volumes.vmap', bytes[..size])!
	volume_boot_check(work + '/etc', work + '/dev', 1, 0, true, 1); assert volume_discovery_io.scans == 0
	os.rm(work + '/etc/vinix/volumes.vmap')!
	os.rm(config)!
	for restore in [false, true] { volume_boot_check(work + '/etc', work + '/dev', 1, 0, restore, 0); assert volume_discovery_io.scans == 0 && volume_discovery_io.derives == 0 }
	assert os.read_bytes(password)! == [u8(0), 10, 0xe2, 0x82, 0xac, 0xff]
}

fn volume_discovery_mock_erase(pointer voidptr, size usize) {
	erase_key(pointer, size)
	unsafe { for i in usize(0) .. size { assert (&u8(pointer))[i] == 0 } }
	if size == sizeof(VolumeSealFiles) { volume_discovery_io.wipes++ }
}

fn volume_discovery_mock_fflush(stream voidptr) i32 {
	if volume_discovery_io.mode == 21 { unsafe { C.errno = C.EIO }; return -1 }
	return C.fflush(stream)
}

fn volume_discovery_fixture(directory string, index int, sector u64, kind u32) ! {
	mut bytes := [8192]u8{}
	identity := if index == 3 { u64(2) } else { u64(1) }
	put_le(&bytes[0], 440, 4, identity); put_le(&bytes[0], 510, 2, 0xaa55)
	if kind == 2 {
		put_le(&bytes[0], 450, 1, 0xee)
		header := unsafe { &bytes[0] + int(sector) }
		put_le(header, 0, 8, 0x5452415020494645); put_le(header, 8, 4, 0x10000); put_le(header, 12, 4, 92); put_le(header, 24, 8, 1)
		put_le(header, 56, 1, identity); put_le(header, 71, 1, 0x83); put_le(header, 16, 4, crc32(header, 92, 16))
	}
	os.write_file_array(directory + '/' + index.str(), bytes[..])!
}

fn volume_discovery_check(config string, password string, directory string, sector u64, flags u64, force bool, mode int, expected i32) {
	volume_discovery_io = VolumeDiscoveryIO{directory: directory, sector: sector, flags: flags | u64(force), mode: mode}
	assert open_volume_seal_auto(config.str, password.str, force) == expected
	assert volume_discovery_io.opened == volume_discovery_io.closed && volume_discovery_io.wipes == 1
	assert volume_discovery_io.live.all(!it)
	if mode in [1, 2] { assert volume_discovery_io.scans == 0 }
	assert volume_discovery_io.imports == if expected == 0 || mode in [20, 21] { 1 } else { 0 }
}

fn test_authenticated_auto_unlock_discovery_uniqueness_modes_rechecks_and_cleanup() {
	work := os.join_path(os.temp_dir(), 'vinix-volume-discovery-${os.getpid()}')
	os.mkdir(work)!; os.chmod(work, 0o700)!; os.mkdir(work + '/dev')!; defer { os.rmdir_all(work) or {} }
	password := work + '/pass'; config := work + '/config'; directory := work + '/dev'
	os.write_file_array(password, [u8(0), 10, 0xe2, 0x82, 0xac, 0xff])!; os.chmod(password, 0o600)!
	mut wrapping := [64]u8{init: u8(index * 29 + 41)}; mut random := [28]u8{init: u8(index * 11 + 3)}; mut source := [320]u8{}
	for sector in [u64(512), u64(4096)] {
		for kind in [u32(1), u32(2)] {
			for flags in [u64(0), u64(1)] {
				mut disk := DiskKey{bytes: 16777216, sector: sector, kind: kind}; disk.id[0] = 1; if kind == 2 { disk.id[15] = 0x83 }
				mut request := EncryptedRequest{data: Request{slot: 5, offset: sector * 2, length: 4096, flags: flags}, key: [64]u8{init: u8(index * 13 + 7)}}
				assert encode_volume_seal(&disk, &request, &wrapping[0], &random[0], &source[0])
				os.write_file_array(config, source[..])!; os.chmod(config, 0o600)!
				volume_discovery_fixture(directory, 0, sector, kind)!
				for force in [false, true] {
					for mode in 0 .. 23 {
						if mode in [15, 16] && (flags == 1 || force) { continue }
						volume_discovery_check(config, password, directory, sector, flags, force, mode, if mode in [0, 14] { 0 } else { 1 })
					}
				}
				for index in [1, 3, 4, 5, 6] { volume_discovery_fixture(directory, index, sector, kind)! }
				os.symlink(directory + '/0', directory + '/link')!; os.write_file(directory + '/regular', 'ignored')!
				volume_discovery_check(config, password, directory, sector, flags, false, 0, 0)
				volume_discovery_fixture(directory, 2, sector, kind)!
				volume_discovery_check(config, password, directory, sector, flags, false, 0, 1)
				for file in os.ls(directory)! { os.rm(directory + '/' + file)! }
				volume_discovery_check(config, password, directory, sector, flags, false, 0, 1)
			}
		}
	}
	for at in [0, 68, 144, 192, 288] {
		mut bad := source; bad[at] ^= 1; os.write_file_array(config, bad[..])!
		volume_discovery_check(config, password, directory, 4096, 1, false, 0, 1)
		assert volume_discovery_io.scans == 0
	}
	os.write_file_array(config, source[..])!
	for i in 0 .. 4097 { os.write_file(directory + '/entry-' + i.str(), '')! }
	volume_discovery_check(config, password, directory, 4096, 1, false, 0, 1)
	assert volume_discovery_io.scans == 1 && os.read_bytes(config)! == source[..]
	assert os.read_bytes(password)! == [u8(0), 10, 0xe2, 0x82, 0xac, 0xff]
}

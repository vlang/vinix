// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module volumecli

import os

struct VolumeSealIO {
mut:
	mode int
	publication int
	creating bool
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
	if C.strcmp(path, c'/volume-seal-parent') == 0 {
		assert flags & C.O_NONBLOCK != 0
		assert volume_seal_io.derives == if volume_seal_io.creating { 0 } else { 1 }
		assert flags & C.O_ACCMODE == if volume_seal_io.creating || volume_seal_io.expected_flags == 1 { C.O_RDONLY } else { C.O_RDWR }
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
	assert fd == 900
	if number == 0x56560006 {
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
	mut status := Status{version: 1, bytes: 16777216, sector: volume_seal_io.sector, flags: 4, disk_id: 7, slot: u64(-1)}
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
		else {}
	}
	unsafe { *(&Status(output)) = status }
	return 0
}

fn volume_seal_mock_pread(fd i32, output voidptr, size usize, offset i64) i64 {
	assert fd == 900 && offset == 0 && size >= 1024 && size <= 8192
	volume_seal_io.disk_reads++
	if volume_seal_io.mode == 1 && volume_seal_io.disk_reads == 1 { unsafe { C.errno = C.EINTR }; return -1 }
	if volume_seal_io.mode == 9 || (volume_seal_io.mode == 18 && volume_seal_io.statuses == 2) { return i64(size - 1) }
	if volume_seal_io.mode == 19 && volume_seal_io.statuses == 2 { unsafe { C.errno = C.EIO }; return -1 }
	unsafe { for i in 0 .. int(size) { (&u8(output))[i] = 0 } }
	identity := if volume_seal_io.mode == 2 { u64(0) } else if volume_seal_io.mode == 3 || (volume_seal_io.mode == 13 && volume_seal_io.statuses == 2) { u64(2) } else { u64(1) }
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
	if volume_seal_io.mode == 21 { return false }
	unsafe { for i in 0 .. 64 { output[i] = u8(i * 29 + 41) }; if volume_seal_io.mode == 22 { output[0] ^= 1 } }
	return true
}

fn volume_seal_mock_erase(pointer voidptr, size usize) {
	erase_key(pointer, size)
	unsafe { for i in usize(0) .. size { assert (&u8(pointer))[i] == 0 } }
	if size == sizeof(VolumeSealFiles) { volume_seal_io.wipes++ }
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

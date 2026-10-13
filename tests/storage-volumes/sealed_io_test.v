// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module volumecli

import os

struct SealedIO {
mut:
	mode int
	opened int
	closed int
	reads int
	writes int
	stats int
	unlinks int
	links int
	wipes int
	directory i32 = -1
	temporary i32 = -1
	random i32 = -1
	locked bool
	parent_flags i32
	derive_calls int
	ioctls int
	maps int
	unmaps int
	vector_wipes int
	core_wipes int
}
__global sealed_io SealedIO

fn sealed_mock_open(path &char, flags i32) i32 {
	assert flags & C.O_CLOEXEC != 0 && flags & C.O_NOFOLLOW != 0
	if C.strcmp(path, c'/dev/urandom') == 0 && sealed_io.mode == 6 { unsafe { C.errno = C.EACCES }; return -1 }
	if C.strcmp(path, c'/sealed-parent') == 0 { sealed_io.parent_flags = flags; if sealed_io.mode == 26 { unsafe { C.errno = C.EACCES }; return -1 }; sealed_io.opened++; return 900 }
	fd := C.open(path, flags)
	if fd >= 0 {
		sealed_io.opened++
		if flags & C.O_DIRECTORY != 0 { sealed_io.directory = fd }
		if C.strcmp(path, c'/dev/urandom') == 0 { sealed_io.random = fd }
	}
	return fd
}
fn sealed_mock_close(fd i32) i32 {
	sealed_io.closed++
	result := if fd == 900 { i32(0) } else { C.close(fd) }
	if fd == sealed_io.temporary && sealed_io.mode == 17 { unsafe { C.errno = C.EIO }; return -1 }
	if fd == sealed_io.directory { sealed_io.locked = false }
	return result
}
fn sealed_mock_fstat(fd i32, info &C.stat) i32 {
	if sealed_io.mode == 22 { unsafe { C.errno = C.EIO }; return -1 }
	result := C.fstat(fd, info); sealed_io.stats++
	if result == 0 {
		unsafe {
			if sealed_io.mode == 4 && sealed_io.stats == 1 { info.st_uid = C.geteuid() + 1 }
			if sealed_io.mode == 5 && sealed_io.stats == 2 { info.st_mode |= 0o004 }
			if fd == sealed_io.random && sealed_io.mode == 7 { info.st_mode = C.S_IFREG | 0o600 }
			if fd == sealed_io.directory && sealed_io.mode == 9 { info.st_uid = C.geteuid() + 1 }
			if fd == sealed_io.directory && sealed_io.mode == 10 { info.st_mode |= 0o002 }
		}
	}
	return result
}
fn sealed_mock_read(fd i32, buffer voidptr, size usize) i64 {
	sealed_io.reads++
	if sealed_io.mode == 1 && sealed_io.reads == 1 { unsafe { C.errno = C.EINTR }; return -1 }
	if sealed_io.mode == 2 && sealed_io.reads == 2 { return 0 }
	if sealed_io.mode == 3 && size == 1 { unsafe { *(&u8(buffer)) = 9 }; return 1 }
	if fd == sealed_io.random && sealed_io.mode == 8 { return 0 }
	return C.read(fd, buffer, if size > 7 { usize(7) } else { size })
}
fn sealed_mock_flock(fd i32, flags i32) i32 {
	assert fd == sealed_io.directory && flags == C.LOCK_EX | C.LOCK_NB
	if sealed_io.mode == 11 { unsafe { C.errno = C.EWOULDBLOCK }; return -1 }
	result := C.flock(fd, flags); if result == 0 { sealed_io.locked = true }; return result
}
fn sealed_mock_openat(fd i32, name &char, flags i32, mode u32) i32 {
	assert sealed_io.locked && fd == sealed_io.directory && mode == 0o600
	assert flags & (C.O_CREAT | C.O_EXCL | C.O_NOFOLLOW | C.O_CLOEXEC) == C.O_CREAT | C.O_EXCL | C.O_NOFOLLOW | C.O_CLOEXEC
	if sealed_io.mode == 12 { unsafe { C.errno = C.EACCES }; return -1 }
	opened := C.openat(fd, name, flags, mode)
	if opened >= 0 { sealed_io.temporary = opened; sealed_io.opened++ }
	return opened
}
fn sealed_mock_fchmod(fd i32, mode u32) i32 {
	assert fd == sealed_io.temporary && mode == 0o600
	if sealed_io.mode == 13 { unsafe { C.errno = C.EPERM }; return -1 }
	return C.fchmod(fd, mode)
}
fn sealed_mock_write(fd i32, bytes voidptr, size usize) i64 {
	assert sealed_io.locked && fd == sealed_io.temporary
	sealed_io.writes++
	if sealed_io.mode == 1 && sealed_io.writes == 1 { unsafe { C.errno = C.EINTR }; return -1 }
	if sealed_io.mode == 14 && sealed_io.writes == 2 { unsafe { C.errno = C.EIO }; return -1 }
	if sealed_io.mode == 15 { return 0 }
	return C.write(fd, bytes, if size > 7 { usize(7) } else { size })
}
fn sealed_mock_fsync(fd i32) i32 {
	assert sealed_io.locked
	if (fd == sealed_io.temporary && sealed_io.mode == 16) || (fd == sealed_io.directory && sealed_io.mode == 20) {
		unsafe { C.errno = C.EIO }; return -1
	}
	return C.fsync(fd)
}
fn sealed_mock_linkat(old i32, source &char, new i32, destination &char, flags i32) i32 {
	assert sealed_io.locked && old == sealed_io.directory && new == old && flags == 0
	sealed_io.links++
	if sealed_io.mode == 18 { unsafe { C.errno = C.EIO }; return -1 }
	return C.linkat(old, source, new, destination, flags)
}
fn sealed_mock_unlinkat(fd i32, name &char, flags i32) i32 {
	assert sealed_io.locked && fd == sealed_io.directory && flags == 0
	sealed_io.unlinks++
	if sealed_io.mode == 19 && sealed_io.unlinks == 1 { unsafe { C.errno = C.EIO }; return -1 }
	return C.unlinkat(fd, name, flags)
}
fn sealed_mock_fflush(stream voidptr) i32 {
	assert sealed_io.locked || sealed_io.ioctls > 0
	if sealed_io.mode == 21 { unsafe { C.errno = C.EIO }; return -1 }
	return C.fflush(stream)
}
fn sealed_mock_erase(pointer voidptr, size usize) {
	erase_key(pointer, size)
	unsafe { for i in usize(0) .. size { assert (&u8(pointer))[i] == 0 } }
	if size == sizeof(SealedFiles) { sealed_io.wipes++ }
	if size == sizeof(ScryptWork) { sealed_io.core_wipes++ }
	if size == sealed_scrypt_memory { sealed_io.vector_wipes++ }
}

fn sealed_mock_derive(password &u8, size int, salt &u8, output &u8) bool {
	assert size > 0 && size <= 1024
	sealed_io.derive_calls++
	if sealed_io.mode == 23 { return false }
	unsafe { for i in 0 .. 64 { output[i] = u8(i * 29 + 41) }; if sealed_io.mode == 24 { output[0] ^= 1 } }
	return true
}
fn sealed_mock_ioctl(fd i32, number u64, pointer voidptr) i32 {
	assert fd == 900 && number == 0x56560006
	request := unsafe { &EncryptedRequest(pointer) }
	assert request.data.version == 1 && request.data.slot == 5 && request.data.offset == 1024 && request.data.length == 4096
	assert request.data.flags == u64(sealed_io.parent_flags & C.O_ACCMODE == C.O_RDONLY)
	for i in 0 .. 64 { assert request.key[i] == u8(i * 13 + 7) }
	sealed_io.ioctls++
	if sealed_io.mode == 25 { unsafe { C.errno = C.EBUSY }; return -1 }
	return 0
}
fn sealed_mock_mmap(hint voidptr, size usize, protection i32, flags i32, fd i32, offset i64) voidptr {
	assert hint == unsafe { nil } && size == sealed_scrypt_memory && fd == -1 && offset == 0
	assert protection == C.PROT_READ | C.PROT_WRITE && flags == C.MAP_PRIVATE | C.MAP_ANONYMOUS
	sealed_io.maps++
	if sealed_io.mode == 30 { unsafe { C.errno = C.ENOMEM }; return unsafe { voidptr(C.MAP_FAILED) } }
	return C.mmap(hint, size, protection, flags, fd, offset)
}
fn sealed_mock_munmap(pointer voidptr, size usize) i32 {
	assert size == sealed_scrypt_memory && sealed_io.vector_wipes == 1
	unsafe { for i in usize(0) .. size { assert (&u8(pointer))[i] == 0 } }
	sealed_io.unmaps++
	if sealed_io.mode == 33 && sealed_io.unmaps == 1 { unsafe { C.errno = C.EINTR }; return -1 }
	result := C.munmap(pointer, size)
	if sealed_io.mode == 32 { assert result == 0; unsafe { C.errno = C.EIO }; return -1 }
	return result
}

fn test_sealed_io_faults_preserve_destinations_close_descriptors_and_erase_credentials() {
	work := os.join_path(os.temp_dir(), 'vinix-sealed-io-${os.getpid()}')
	os.mkdir(work)!; os.chmod(work, 0o700)!; defer { os.rmdir_all(work) or {} }
	key := []u8{len: 64, init: u8(index * 13 + 7)}
	os.write_file_array(work + '/key', key)!; os.chmod(work + '/key', 0o600)!
	os.write_file(work + '/pass', 'private fixture passphrase')!; os.chmod(work + '/pass', 0o600)!
	sealed_io = SealedIO{}
	assert sealed_key_file((work + '/key').str, (work + '/pass').str, (work + '/valid').str, true) == 0
	for seal in [true, false] {
		for mode in 0 .. 25 {
			if (!seal && mode in [6, 7, 8]) || (seal && mode == 24) { continue }
			sealed_io = SealedIO{mode: mode}
			input := work + if seal { '/key' } else { '/valid' }; destination := work + '/output'
			assert sealed_key_file(input.str, (work + '/pass').str, destination.str, seal) == if mode <= 1 { 0 } else { 1 }
			assert sealed_io.opened == sealed_io.closed && sealed_io.wipes == 1 && !sealed_io.locked
			assert os.exists(destination) == (mode <= 1 || mode in [19, 20, 21])
			if os.exists(destination) {
				assert os.file_size(destination) == if seal { u64(192) } else { u64(64) }
				if !seal { assert os.read_bytes(destination)! == key }
				os.rm(destination)!
			}
			assert os.ls(work)!.all(!it.starts_with('.vinix-key-'))
		}
	}
	for readonly in [false, true] {
		for mode in [0, 1, 2, 3, 4, 5, 22, 23, 24, 25, 26] {
			sealed_io = SealedIO{mode: mode}
			request := Request{slot: 5, offset: 1024, length: 4096, flags: u64(readonly)}
			assert open_sealed_volume(c'/sealed-parent', (work + '/valid').str, (work + '/pass').str, &request) == if mode <= 1 { 0 } else { 1 }
			assert sealed_io.opened == sealed_io.closed && sealed_io.wipes == 1 && !sealed_io.locked
			assert sealed_io.ioctls == if mode <= 1 || mode == 25 { 1 } else { 0 }
			if mode > 1 && mode !in [25, 26] { assert sealed_io.parent_flags == 0 }
		}
	}
	// A valid-sized malicious work profile never reaches KDF or parent opening.
	valid := os.read_bytes(work + '/valid')!
	for at in [0, 8, 12, 16, 20, 24, 31, 32, 36, 68, 95] {
		mut bad := valid.clone(); bad[at] ^= 1
		os.write_file_array(work + '/bad', bad)!; os.chmod(work + '/bad', 0o600)!
		sealed_io = SealedIO{}
		request := Request{slot: 5, offset: 1024, length: 4096}
		assert open_sealed_volume(c'/sealed-parent', (work + '/bad').str, (work + '/pass').str, &request) == 1
		assert sealed_io.derive_calls == 0 && sealed_io.ioctls == 0 && sealed_io.parent_flags == 0 && sealed_io.wipes == 1 && sealed_io.opened == sealed_io.closed
	}
	for attempt in 0 .. 64 { os.write_file(work + '/.vinix-key-${os.getpid()}-${attempt}', 'keep unrelated temporary')! }
	sealed_io = SealedIO{}
	assert sealed_key_file((work + '/valid').str, (work + '/pass').str, (work + '/output').str, false) == 1
	assert sealed_io.opened == sealed_io.closed && sealed_io.wipes == 1 && sealed_io.unlinks == 0
	for attempt in 0 .. 64 { assert os.read_file(work + '/.vinix-key-${os.getpid()}-${attempt}')! == 'keep unrelated temporary' }
}

fn test_scrypt_mapping_refusal_erasure_release_failure_and_eintr_do_not_release_candidate_keys() {
	mut salt := [16]u8{init: 7}; mut output := [66]u8{init: 0xa1}
	sealed_io = SealedIO{}
	assert !sealed_derive(c'fixture password', 0, &salt[0], &output[1])
	assert !sealed_derive(c'fixture password', 1025, &salt[0], &output[1])
	assert sealed_io.maps == 0
	for mode in 30 .. 34 {
		sealed_io = SealedIO{mode: mode}; output = [66]u8{init: 0xa1}
		assert sealed_derive(c'fixture password', 16, &salt[0], &output[1]) == (mode in [31, 33])
		assert sealed_io.maps == 1
		assert sealed_io.unmaps == if mode == 30 { 0 } else if mode == 33 { 2 } else { 1 }
		assert sealed_io.vector_wipes == if mode == 30 { 0 } else { 1 }
		assert sealed_io.core_wipes == if mode == 30 { 0 } else { 1 }
		assert output[0] == 0xa1 && output[65] == 0xa1
		if mode in [30, 32] { for value in output { assert value == 0xa1 } }
	}
}

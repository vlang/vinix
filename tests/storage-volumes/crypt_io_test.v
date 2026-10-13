// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module volumecli

import os

struct CryptIO {
mut:
	mode int
	opened int
	closed int
	reads int
	ioctls int
	wipes int
	parent_flags i32
}
__global crypt_io CryptIO

fn crypt_mock_open(path &char, flags i32) i32 {
	assert flags & C.O_CLOEXEC != 0 && flags & C.O_NOFOLLOW != 0 && flags & C.O_NONBLOCK != 0
	if C.strcmp(path, c'/crypt-parent') == 0 {
		crypt_io.parent_flags = flags
		if crypt_io.mode == 4 { unsafe { C.errno = C.EACCES }; return -1 }
		crypt_io.opened++; return 900
	}
	fd := C.open(path, flags)
	if fd >= 0 { crypt_io.opened++ }
	return fd
}
fn crypt_mock_close(fd i32) i32 {
	crypt_io.closed++
	return if fd == 900 { i32(0) } else { C.close(fd) }
}
fn crypt_mock_fstat(fd i32, info &C.stat) i32 {
	result := C.fstat(fd, info)
	if result == 0 && crypt_io.mode == 6 { unsafe { info.st_uid = C.geteuid() + 1 } }
	return result
}
fn crypt_mock_read(fd i32, buffer voidptr, size usize) i64 {
	crypt_io.reads++
	if crypt_io.mode == 1 && crypt_io.reads == 1 { unsafe { C.errno = C.EINTR }; return -1 }
	if crypt_io.mode == 2 && crypt_io.reads == 2 { return 0 }
	if crypt_io.mode == 3 && size == 1 { unsafe { *(&u8(buffer)) = 9 }; return 1 }
	length := if size > 7 { usize(7) } else { size }
	return C.read(fd, buffer, length)
}
fn crypt_mock_ioctl(fd i32, number u64, pointer voidptr) i32 {
	assert fd == 900 && number == 0x56560006
	request := unsafe { &EncryptedRequest(pointer) }
	assert request.data.version == 1 && request.data.slot == 5 && request.data.offset == 1024 && request.data.length == 4096
	assert request.data.flags == u64(crypt_io.parent_flags & C.O_ACCMODE == C.O_RDONLY)
	for i in 0 .. 64 { assert request.key[i] == u8(i * 13 + 7) }
	crypt_io.ioctls++
	if crypt_io.mode == 5 { unsafe { C.errno = C.EBUSY }; return -1 }
	return 0
}
fn crypt_mock_bzero(pointer voidptr, size usize) {
	erase_key(pointer, size)
	unsafe { for i in usize(0) .. size { assert (&u8(pointer))[i] == 0 } }
	if size == sizeof(EncryptedRequest) { crypt_io.wipes++ }
}

fn test_encrypted_open_short_reads_interruptions_errors_and_full_request_erasure() {
	path := os.join_path(os.temp_dir(), 'vinix-crypt-io-${os.getpid()}')
	mut key := []u8{len: 64}
	for i in 0 .. 64 { key[i] = u8(i * 13 + 7) }
	os.write_file_array(path, key)!
	os.chmod(path, 0o600)!
	defer { os.rm(path) or {} }
	for mode in 0 .. 7 {
		for readonly in [false, true] {
			crypt_io = CryptIO{mode: mode}
			request := Request{slot: 5, offset: 1024, length: 4096, flags: u64(readonly)}
			assert open_encrypted_volume(c'/crypt-parent', path.str, &request) == if mode <= 1 { 0 } else { 1 }
			assert crypt_io.opened == crypt_io.closed && crypt_io.wipes == 1
			assert crypt_io.ioctls == if mode <= 1 || mode == 5 { 1 } else { 0 }
		}
	}
}

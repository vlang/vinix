// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module volumecli

import os

struct RecoveryIO {
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
	volume_wipes int
	directory i32 = -1
	temporary i32 = -1
	random i32 = -1
	locked bool
}
__global recovery_io RecoveryIO

fn recovery_mock_open(path &char, flags i32) i32 {
	assert flags & C.O_CLOEXEC != 0 && flags & C.O_NOFOLLOW != 0
	if recovery_rewrap_model && !recovery_rewrap_before_open(path, flags) { return -1 }
	if volume_recovery_model && (flags & C.O_DIRECTORY != 0 || (volume_recovery_io.derives > 0 && unsafe { C.strstr(path, c'/recovery') != nil })) {
		volume_recovery_assert_erased()
	}
	if C.strcmp(path, c'/dev/urandom') == 0 && recovery_io.mode == 6 { unsafe { C.errno = C.EACCES }; return -1 }
	fd := C.open(path, flags)
	if recovery_rewrap_model { recovery_rewrap_io.fd = fd }
	if fd >= 0 {
		recovery_io.opened++
		if flags & C.O_DIRECTORY != 0 { recovery_io.directory = fd }
		if C.strcmp(path, c'/dev/urandom') == 0 { recovery_io.random = fd }
	}
	return fd
}
fn recovery_mock_close(fd i32) i32 {
	recovery_io.closed++
	result := C.close(fd)
	if fd == recovery_io.temporary && recovery_io.mode == 17 { unsafe { C.errno = C.EIO }; return -1 }
	if fd == recovery_io.directory { recovery_io.locked = false }
	return result
}
fn recovery_mock_fstat(fd i32, info &C.stat) i32 {
	if recovery_rewrap_model && recovery_rewrap_io.stage == 2 { recovery_rewrap_io.stats++ }
	if recovery_io.mode == 22 { unsafe { C.errno = C.EIO }; return -1 }
	result := C.fstat(fd, info); recovery_io.stats++
	if result == 0 && recovery_rewrap_model && recovery_rewrap_io.stage == 2 {
		unsafe {
			if recovery_io.mode == 24 { info.st_uid++ }
			if recovery_io.mode == 28 && recovery_rewrap_io.stats == 2 { info.st_mode |= 0o004 }
			if recovery_io.mode == 29 && recovery_rewrap_io.stats == 2 { info.st_size++ }
		}
	}
	if result == 0 {
		unsafe {
			if recovery_io.mode == 4 && recovery_io.stats == 1 { info.st_uid = C.geteuid() + 1 }
			if recovery_io.mode == 5 && recovery_io.stats == 2 { info.st_mode |= 0o004 }
			if fd == recovery_io.random && recovery_io.mode == 7 { info.st_mode = C.S_IFREG | 0o600 }
			if fd == recovery_io.directory && recovery_io.mode == 9 { info.st_uid = C.geteuid() + 1 }
			if fd == recovery_io.directory && recovery_io.mode == 10 { info.st_mode |= 0o002 }
		}
	}
	return result
}
fn recovery_mock_read(fd i32, buffer voidptr, size usize) i64 {
	if recovery_rewrap_model && recovery_rewrap_io.stage == 2 {
		recovery_rewrap_io.reads++
		if recovery_io.mode == 25 { unsafe { C.errno = C.EIO }; return -1 }
		if recovery_io.mode == 26 { return 0 }
		if recovery_io.mode == 27 && size == 1 { unsafe { *(&u8(buffer)) = 9 }; return 1 }
		if recovery_io.mode == 30 && recovery_rewrap_io.reads == 1 { unsafe { C.errno = C.EINTR }; return -1 }
	}
	recovery_io.reads++
	if recovery_io.mode == 1 && recovery_io.reads == 1 { unsafe { C.errno = C.EINTR }; return -1 }
	if recovery_io.mode == 2 && recovery_io.reads == 2 { return 0 }
	if recovery_io.mode == 3 && size == 1 { unsafe { *(&u8(buffer)) = 9 }; return 1 }
	if fd == recovery_io.random && recovery_io.mode == 8 { return 0 }
	return C.read(fd, buffer, if size > 7 { usize(7) } else { size })
}
fn recovery_mock_flock(fd i32, flags i32) i32 {
	assert fd == recovery_io.directory && flags == C.LOCK_EX | C.LOCK_NB
	if recovery_io.mode == 11 { unsafe { C.errno = C.EWOULDBLOCK }; return -1 }
	result := C.flock(fd, flags); if result == 0 { recovery_io.locked = true }; return result
}
fn recovery_mock_openat(fd i32, name &char, flags i32, mode u32) i32 {
	assert recovery_io.locked && fd == recovery_io.directory && mode == 0o600
	assert flags & (C.O_CREAT | C.O_EXCL | C.O_NOFOLLOW | C.O_CLOEXEC) == C.O_CREAT | C.O_EXCL | C.O_NOFOLLOW | C.O_CLOEXEC
	if recovery_io.mode == 12 { unsafe { C.errno = C.EACCES }; return -1 }
	opened := C.openat(fd, name, flags, mode)
	if opened >= 0 { recovery_io.temporary = opened; recovery_io.opened++ }
	return opened
}
fn recovery_mock_fchmod(fd i32, mode u32) i32 {
	assert fd == recovery_io.temporary && mode == 0o600
	if recovery_io.mode == 13 { unsafe { C.errno = C.EPERM }; return -1 }
	return C.fchmod(fd, mode)
}
fn recovery_mock_write(fd i32, bytes voidptr, size usize) i64 {
	assert recovery_io.locked && fd == recovery_io.temporary
	recovery_io.writes++
	if recovery_io.mode == 1 && recovery_io.writes == 1 { unsafe { C.errno = C.EINTR }; return -1 }
	if recovery_io.mode == 14 && recovery_io.writes == 2 { unsafe { C.errno = C.EIO }; return -1 }
	if recovery_io.mode == 15 { return 0 }
	return C.write(fd, bytes, if size > 7 { usize(7) } else { size })
}
fn recovery_mock_fsync(fd i32) i32 {
	assert recovery_io.locked
	if (fd == recovery_io.temporary && recovery_io.mode == 16) || (fd == recovery_io.directory && recovery_io.mode == 20) {
		unsafe { C.errno = C.EIO }; return -1
	}
	return C.fsync(fd)
}
fn recovery_mock_linkat(old i32, source &char, new i32, destination &char, flags i32) i32 {
	assert recovery_io.locked && old == recovery_io.directory && new == old && flags == 0
	recovery_io.links++
	if recovery_io.mode == 18 { unsafe { C.errno = C.EIO }; return -1 }
	return C.linkat(old, source, new, destination, flags)
}
fn recovery_mock_unlinkat(fd i32, name &char, flags i32) i32 {
	assert recovery_io.locked && fd == recovery_io.directory && flags == 0
	recovery_io.unlinks++
	if recovery_io.mode == 19 && recovery_io.unlinks == 1 { unsafe { C.errno = C.EIO }; return -1 }
	return C.unlinkat(fd, name, flags)
}
fn recovery_mock_fflush(stream voidptr) i32 {
	assert recovery_io.locked
	if recovery_io.mode == 21 { unsafe { C.errno = C.EIO }; return -1 }
	return C.fflush(stream)
}
fn recovery_mock_erase(pointer voidptr, size usize) {
	erase_key(pointer, size)
	unsafe { for i in usize(0) .. size { assert (&u8(pointer))[i] == 0 } }
	if size == sizeof(RecoveryFiles) { recovery_io.wipes++ }
	if size == sizeof(VolumeSealFiles) { recovery_io.volume_wipes++ }
}

fn test_recovery_all_io_failures_balance_descriptors_erase_keys_and_preserve_publication() {
	work := os.join_path(os.temp_dir(), 'vinix-recovery-io-${os.getpid()}')
	os.mkdir(work)!; os.chmod(work, 0o700)!; defer { os.rmdir_all(work) or {} }
	key := []u8{len: 64, init: u8(index * 13 + 7)}
	recovery := []u8{len: 64, init: u8(index * 29 + 41)}
	os.write_file_array(work + '/key', key)!; os.chmod(work + '/key', 0o600)!
	os.write_file_array(work + '/recovery', recovery)!; os.chmod(work + '/recovery', 0o600)!
	recovery_io = RecoveryIO{}
	assert recovery_key_file((work + '/key').str, (work + '/recovery').str, (work + '/valid').str, true) == 0
	for backup in [true, false] {
		for mode in 0 .. 23 {
			if !backup && mode in [6, 7, 8] { continue }
			recovery_io = RecoveryIO{mode: mode}
			input := work + if backup { '/key' } else { '/valid' }; destination := work + '/output'
			assert recovery_key_file(input.str, (work + '/recovery').str, destination.str, backup) == if mode <= 1 { 0 } else { 1 }
			assert recovery_io.opened == recovery_io.closed && recovery_io.wipes == 1 && !recovery_io.locked
			assert os.exists(destination) == (mode <= 1 || mode in [19, 20, 21])
			if os.exists(destination) {
				assert os.file_size(destination) == if backup { u64(160) } else { u64(64) }
				if !backup { assert os.read_bytes(destination)! == key }
				os.rm(destination)!
			}
			assert os.ls(work)!.all(!it.starts_with('.vinix-key-'))
		}
	}
	// Existing temporary names belong to somebody else. Only the file created
	// by this invocation may be linked or removed, even on failed publication.
	collision := work + '/.vinix-key-${os.getpid()}-0'
	os.write_file(collision, 'keep this unrelated file')!
	for mode in [0, 18] {
		recovery_io = RecoveryIO{mode: mode}
		assert recovery_key_file((work + '/key').str, (work + '/recovery').str, (work + '/output').str, true) == if mode == 0 { 0 } else { 1 }
		assert os.read_file(collision)! == 'keep this unrelated file'
		assert recovery_io.opened == recovery_io.closed && recovery_io.wipes == 1
		if os.exists(work + '/output') { os.rm(work + '/output')! }
	}
	for attempt in 1 .. 64 { os.write_file(work + '/.vinix-key-${os.getpid()}-${attempt}', 'keep this unrelated file')! }
	recovery_io = RecoveryIO{}
	assert recovery_key_file((work + '/key').str, (work + '/recovery').str, (work + '/output').str, true) == 1
	assert recovery_io.opened == recovery_io.closed && recovery_io.wipes == 1 && recovery_io.links == 0 && recovery_io.unlinks == 0
	for attempt in 0 .. 64 { assert os.read_file(work + '/.vinix-key-${os.getpid()}-${attempt}')! == 'keep this unrelated file' }
}

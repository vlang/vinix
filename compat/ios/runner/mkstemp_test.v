// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

fn C.mkstemp(&u8) i32
fn C.umask(u32) u32

type TempTestCall = fn (&char) i32

fn temp_test_call(native bool, path &char) i32 {
	$if macos { if native { return C.mkstemp(unsafe { &u8(path) }) } }
	call := unsafe { TempTestCall(voidptr(runtime_symbol('/usr/lib/libSystem.B.dylib', '_mkstemp') or { panic(err) })) }
	return call(path)
}

fn temp_test_file(native bool, path string, mode u32) string {
	mut bytes := ('GUARD' + path + '\x00TAIL').bytes()
	darwin_set_errno(83)
	fd := temp_test_call(native, unsafe { &char(&bytes[5]) })
	saved := unsafe { *C.ios_errno_address() }
	assert fd >= 0 && (saved == 83 || saved == 17), 'fd=${fd} errno=${saved}'
	assert bytes[..5].bytestr() == 'GUARD' && bytes[bytes.len-5..].bytestr() == '\x00TAIL'
	name := unsafe { tos_clone(&bytes[5]) }
	mut suffix := path.len
	for suffix > 0 && path[suffix - 1] == `X` { suffix-- }
	assert name.len == path.len && name[..suffix] == path[..suffix]
	for value in name[suffix..].bytes() { assert (value >= `0` && value <= `9`) || (value >= `A` && value <= `Z`) || (value >= `a` && value <= `z`) }
	assert C.fcntl(fd, C.F_GETFL, usize(0)) & C.O_ACCMODE == C.O_RDWR
	assert C.fcntl(fd, C.F_GETFD, usize(0)) == 0
	mut fields := [20]u64{}
	assert C.ios_stat_info(unsafe { nil }, fd, 2, unsafe { &fields[0] }) == 0
	assert fields[1] & 0o777 == mode && fields[15] == 0
	assert C.write(fd, c'contents', 8) == 8 && C.lseek(fd, 0, 0) == 0
	mut content := [8]u8{}
	assert C.read(fd, unsafe { &content[0] }, 8) == 8
	assert unsafe { C.memcmp(voidptr(&content[0]), c'contents', 8) } == 0
	assert C.unlink(name.str) == 0
	// Unlink does not close the returned descriptor.
	assert C.lseek(fd, 0, 0) == 0 && C.read(fd, unsafe { &content[0] }, 8) == 8
	assert C.close(fd) == 0
	return name
}

fn temp_test_failure(native bool, path string, expected i32) {
	mut bytes := ('GUARD' + path + '\x00TAIL').bytes()
	darwin_set_errno(83)
	assert temp_test_call(native, unsafe { &char(&bytes[5]) }) == -1, path
	assert unsafe { *C.ios_errno_address() } == expected, path
	assert bytes[..5].bytestr() == 'GUARD' && bytes[bytes.len-5..].bytestr() == '\x00TAIL'
	mut suffix := path.len
	for suffix > 0 && path[suffix - 1] == `X` { suffix-- }
	assert bytes[5..5+suffix].bytestr() == path[..suffix]
}

fn temp_test_profile(native bool) {
	dir := '/tmp/ios-mkstemp-' + os.getpid().str() + if native { '-native' } else { '-adapter' }
	os.mkdir(dir) or { panic(err) }
	defer { os.rmdir_all(dir) or { panic(err) } }
	mask := C.umask(0)
	defer { C.umask(mask) }
	for suffix in ['plain', 'X', 'XX', 'XXX', 'XXXX', 'XXXXX', 'XXXXXX', 'XXXXXXX', 'XXXXXXXXXXXX', 'XXsuff', 'XXXXXX.suffix']! {
		temp_test_file(native, dir + '/' + suffix, 0o600)
	}
	C.umask(0o777); temp_test_file(native, dir + '/maskedXXXXXX', 0); C.umask(0)
	os.write_file(dir + '/regular', 'retained') or { panic(err) }
	assert C.symlink(c'loop', (dir + '/loop').str) == 0
	assert C.symlink(c'absent', (dir + '/dangling').str) == 0
	assert C.symlink(dir.str, (dir + '/parent').str) == 0
	temp_test_file(native, dir + '/parent/parentXXXXXX', 0o600)
	for pair in [['', '22']!, [dir + '/missing/XXXXXX', '2']!, [dir + '/regular/XXXXXX', '20']!, [dir + '/loop/XXXXXX', '62']!, [dir + '/regular', '17']!, [dir + '/dangling', '17']!, [dir, '17']!] {
		temp_test_failure(native, pair[0], pair[1].i32())
	}
	// The adapter bounds names before touching Vinix's directory storage.
	temp_test_file(native, dir + '/' + 'a'.repeat(249) + 'XXXXXX', 0o600)
	temp_test_failure(native, dir + '/' + 'a'.repeat(250) + 'XXXXXX', 63)
	temp_test_failure(native, dir + '/' + 'a'.repeat(256) + 'XXXXXX', 63)
	assert os.ls(dir) or { panic(err) }.all(it.len <= 255)
	assert (os.read_file(dir + '/regular') or { panic(err) }) == 'retained'
	assert !os.exists(dir + '/absent')
	// A fully occupied short-name space must terminate with EEXIST without
	// truncating files or following a candidate symlink.
	for value in '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'.bytes() {
		path := dir + '/collision-' + value.ascii_str()
		if value == `0` { assert C.symlink(c'absent', path.str) == 0 }
		else { os.write_file(path, 'retained') or { panic(err) } }
	}
	temp_test_failure(native, dir + '/collision-X', 17)
	for value in '123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'.bytes() {
		assert (os.read_file(dir + '/collision-' + value.ascii_str()) or { panic(err) }) == 'retained'
	}
	assert !os.exists(dir + '/absent')
	assert C.unlink((dir + '/collision-1').str) == 0
	assert temp_test_file(native, dir + '/collision-X', 0o600) == dir + '/collision-1'
	// Native checks MAXPATHLEN before replacing the trailing run.
	for length in [1024, 1025]! {
		path := 'a'.repeat(length - 6) + 'XXXXXX'
		mut bytes := (path + '\x00TAIL').bytes()
		darwin_set_errno(83)
		assert temp_test_call(native, unsafe { &char(bytes.data) }) == -1 && unsafe { *C.ios_errno_address() } == 63
		assert bytes.bytestr() == path + '\x00TAIL'
	}
}

struct TempTestWorker { directory &char }
fn temp_test_worker(context voidptr) voidptr {
	state := unsafe { &TempTestWorker(context) }
	for _ in 0 .. 50 {
		mut path := [512]u8{}
		prefix := darwin_strlen(state.directory)
		unsafe {
			C.memcpy(voidptr(&path[0]), state.directory, prefix)
			C.memcpy(voidptr(&path[prefix]), c'/shared-XXXXXX', 14)
		}
		darwin_set_errno(177)
		fd := darwin_mkstemp(unsafe { &char(&path[0]) })
		assert fd >= 0 && unsafe { *C.ios_errno_address() } in [i32(177), 17]!
		assert C.write(fd, c'worker', 6) == 6 && C.close(fd) == 0
		// Retain every created name until all callers join: duplicate names
		// cannot be hidden by unlink/recreate between calls.
	}
	return unsafe { nil }
}

fn temp_test_threads() {
	dir := '/tmp/ios-mkstemp-workers-' + os.getpid().str()
	os.mkdir(dir) or { panic(err) }; defer { os.rmdir_all(dir) or { panic(err) } }
	mut state := TempTestWorker{ directory: dir.str }; mut handles := [8]u64{}
	for i in 0 .. 8 { assert C.pthread_create(unsafe { voidptr(&handles[i]) }, unsafe { nil }, unsafe { voidptr(temp_test_worker) }, unsafe { voidptr(&state) }) == 0 }
	for handle in handles { assert C.pthread_join(voidptr(handle), unsafe { nil }) == 0 }
	names := os.ls(dir) or { panic(err) }; assert names.len == 400
	for name in names { assert (os.read_file(dir + '/' + name) or { panic(err) }) == 'worker' }
}

fn test_mkstemp() {
	for _ in 0 .. 2 {
		system_data_start()!
		$if macos { temp_test_profile(true) }
		temp_test_profile(false); temp_test_threads()
		// Fortnite supplies a strdup buffer and keeps responsibility for it.
		pointer := darwin_strdup(c'/tmp/ios-fortnite-temp-XXXXXX')
		zone := darwin_zone_from_pointer(pointer); assert zone != unsafe { nil }
		fd := darwin_mkstemp(unsafe { &char(pointer) }); assert fd >= 0
		assert C.unlink(unsafe { &char(pointer) }) == 0 && C.close(fd) == 0
		assert darwin_zone_from_pointer(pointer) == zone; darwin_free(pointer)
		darwin_set_errno(83); assert darwin_mkstemp(unsafe { nil }) == -1 && unsafe { *C.ios_errno_address() } == 14
		mut rejected := false; runtime_symbol('/usr/lib/libobjc.A.dylib', '_mkstemp') or { rejected = true }; assert rejected
		system_data_stop()
	}
	println('IOS-MKSTEMP: native BSD templates, modes, flags, guarded mutation, collisions, symlinks, Darwin errors, unlink lifetime, eight callers, heap-owned template and two images')
}

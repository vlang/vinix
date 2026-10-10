// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

fn C.mkstemp(&u8) i32

fn file_times_test_stat(path string, access i64, modification i64) {
	mut fields := [20]u64{}
	assert C.ios_stat_info(path.str, -1, 0, unsafe { &fields[0] }) == 0
	assert i64(fields[7]) == access && fields[8] == 0
	assert i64(fields[9]) == modification && fields[10] == 0
}

fn file_times_test_set(path string, access i64, modification i64, saved i32) {
	mut input := [i64(0x5a5a5a5a5a5a5a5a), access, modification, 0x5a5a5a5a5a5a5a5a]!
	darwin_set_errno(saved)
	assert darwin_utime(path.str, unsafe { &DarwinFileTimes(&input[1]) }) == 0
	assert unsafe { *C.ios_errno_address() } == saved
	assert input[0] == 0x5a5a5a5a5a5a5a5a && input[3] == 0x5a5a5a5a5a5a5a5a
	assert input[1] == access && input[2] == modification
	file_times_test_stat(path, access, modification)
}

fn file_times_test_worker(index int) {
	mut template := ('/tmp/ios-file-times-XXXXXX' + '\x00').bytes()
	fd := C.mkstemp(template.data)
	assert fd >= 0
	path := unsafe { tos_clone(template.data) }
	link := path + '.link'
	loop := path + '.loop'
	defer {
		C.close(fd)
		C.unlink(link.str)
		C.unlink(loop.str)
		C.unlink(path.str)
	}
	assert C.write(fd, 'file timestamp contents'.str, 23) == 23
	for pair in [[i64(0), 0]!, [i64(-1), -2]!, [i64(-2208988800), -2208988799]!, [i64(2147483648), 4294967301]!] {
		file_times_test_set(path, pair[0], pair[1], i32(177 + index))
	}
	for iteration in 0 .. 50 {
		file_times_test_set(path, 1700000001 + iteration + index, 1700000101 + iteration + index, i32(177 + index))
	}
	// Timestamp changes follow the symlink to its real target.
	assert C.symlink(path.str, link.str) == 0
	file_times_test_set(link, 1700000301, 1700000302, 177)
	file_times_test_stat(path, 1700000301, 1700000302)
	mut input := [i64(0x5a5a5a5a5a5a5a5a), 1700000301, 1700000402, 0x5a5a5a5a5a5a5a5a]!
	assert C.symlink(loop.str, loop.str) == 0
	for bad, expected in { path + '.missing': i32(2), path + '/child': 20, loop: 62, '': 2 } {
		darwin_set_errno(177)
		assert darwin_utime(bad.str, unsafe { &DarwinFileTimes(&input[1]) }) == -1
		assert unsafe { *C.ios_errno_address() } == expected
	}
	darwin_set_errno(177)
	assert darwin_utime(unsafe { nil }, unsafe { &DarwinFileTimes(&input[1]) }) == -1
	assert unsafe { *C.ios_errno_address() } == 14
	assert input[0] == 0x5a5a5a5a5a5a5a5a && input[3] == 0x5a5a5a5a5a5a5a5a
	assert input[1] == 1700000301 && input[2] == 1700000402
	file_times_test_stat(path, 1700000301, 1700000302)
	before := C.time(unsafe { nil })
	darwin_set_errno(177)
	assert darwin_utime(path.str, unsafe { nil }) == 0
	assert unsafe { *C.ios_errno_address() } == 177
	after := C.time(unsafe { nil })
	mut fields := [20]u64{}
	assert C.ios_stat_info(path.str, -1, 0, unsafe { &fields[0] }) == 0
	assert i64(fields[7]) >= before && i64(fields[7]) <= after
	assert fields[7] == fields[9] && fields[8] == fields[10] && fields[8] < 1000000000
	assert (os.read_file(path) or { panic(err) }) == 'file timestamp contents'
}

fn test_darwin_file_times() {
	assert sizeof(DarwinFileTimes) == 16
	assert __offsetof(DarwinFileTimes, access) == 0 && __offsetof(DarwinFileTimes, modification) == 8
	for _ in 0 .. 2 {
		system_data_start()!
		mut workers := []thread{}
		for index in 0 .. 8 { workers << spawn file_times_test_worker(index) }
		workers.wait()
		system_data_stop()
	}
	assert (files_symbol('_utime') or { u64(0) }) != 0
	println('IOS-FILE-TIMES: real stat readback, signed 64-bit times, symlinks, set-to-now, guarded inputs, Darwin errors, eight workers and two teardowns')
}

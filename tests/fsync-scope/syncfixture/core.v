// SPDX-License-Identifier: GPL-2.0-or-later
// A failing real disk must not poison an unrelated tmpfs descriptor's sync.
@[translated]
@[has_globals]
module syncfixture

#include <fsync-native-abi.h>

@[typedef]
struct C.FILE {}
@[c_extern] __global C.stdout &C.FILE
@[c_extern] __global C.errno i32

fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.setbuf(&C.FILE, &char)
fn C.open(&char, i32, ...) i32
fn C.close(i32) i32
fn C.write(i32, voidptr, usize) isize
fn C.pread(i32, voidptr, usize, i64) isize
fn C.pwrite(i32, voidptr, usize, i64) isize
fn C.fsync(i32) i32
fn C.fdatasync(i32) i32
fn C.syscall(i64, ...) i64
fn C.pipe(&i32) i32
fn C.memset(voidptr, i32, usize) voidptr
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.memcmp(voidptr, voidptr, usize) i32
fn C.pause() i32

fn check(condition bool, line i32) bool {
	unsafe {
		if !condition {
			C.printf(c'FSYNC-SCOPE FAIL: line=%d errno=%d\n', line, C.errno)
		}
		return condition
	}
}

@[export: 'main']
pub fn entry() i32 {
	unsafe {
		C.setbuf(C.stdout, nil)
		C.puts(c'FSYNC-SCOPE START')
		payload := [39]char{}
		C.memcpy(&payload[0], c'a RAM file has no failing backing disk', sizeof(payload))
		ram := C.open(c'/tmp/sync-probe', C.O_CREAT | C.O_TRUNC | C.O_RDWR, 0o600)
		if !check(ram >= 0, 19) { return 1 }
		if !check(C.write(ram, &payload[0], sizeof(payload)) == isize(sizeof(payload)), 20) { return 1 }
		if !check(C.fsync(ram) == 0 && C.fdatasync(ram) == 0, 21) { return 1 }
		C.puts(c'FSYNC-SCOPE BASELINE-RAM-PASS')

		// Dirty disk pages stay retryable after the injected underlying I/O error.
		disk := C.open(c'/root/disk-probe.bin', C.O_RDWR)
		if !check(disk >= 0, 27) { return 1 }
		bytes := [8192]u8{}
		C.memset(&bytes[0], 0x5a, sizeof(bytes))
		if !check(C.pwrite(disk, &bytes[0], sizeof(bytes), 0) == isize(sizeof(bytes)), 30) { return 1 }
		C.errno = 0
		if !check(C.fsync(disk) == -1 && C.errno == C.EIO, 32) { return 1 }
		C.errno = 0
		if !check(C.syscall(C.SYS_syncfs, disk) == -1 && C.errno == C.EIO, 34) { return 1 }
		C.puts(c'FSYNC-SCOPE FAILING-DISK-CONFIRMED')

		C.errno = 0
		file_result := C.fsync(ram)
		file_error := C.errno
		C.errno = 0
		data_result := C.fdatasync(ram)
		data_error := C.errno
		C.printf(c'FSYNC-SCOPE RAM-AFTER-DISK: fsync=%d errno=%d fdatasync=%d errno=%d\n',
			file_result, file_error, data_result, data_error)
		if !check(file_result == 0 && data_result == 0, 43) { return 1 }

		observed := [39]char{}
		if !check(C.pread(ram, &observed[0], sizeof(observed), 0) == isize(sizeof(observed)), 46) { return 1 }
		if !check(C.memcmp(&observed[0], &payload[0], sizeof(payload)) == 0, 47) { return 1 }
		readonly := C.open(c'/tmp/sync-probe', C.O_RDONLY)
		if !check(readonly >= 0 && C.fsync(readonly) == 0 && C.fdatasync(readonly) == 0, 49) { return 1 }
		if !check(C.close(readonly) == 0, 50) { return 1 }
		directory := C.open(c'/tmp', C.O_RDONLY | C.O_DIRECTORY)
		if !check(directory >= 0 && C.fsync(directory) == 0 && C.close(directory) == 0, 52) { return 1 }
		path := C.open(c'/tmp/sync-probe', C.O_PATH)
		if !check(path >= 0, 54) { return 1 }
		C.errno = 0
		if !check(C.fsync(path) == -1 && C.errno == C.EBADF, 56) { return 1 }
		if !check(C.close(path) == 0, 57) { return 1 }
		C.errno = 0
		if !check(C.fsync(-1) == -1 && C.errno == C.EBADF, 59) { return 1 }
		stream := [2]i32{}
		if !check(C.pipe(&stream[0]) == 0, 61) { return 1 }
		C.errno = 0
		if !check(C.fsync(stream[0]) == -1 && C.errno == C.EINVAL, 63) { return 1 }
		if !check(C.close(stream[0]) == 0 && C.close(stream[1]) == 0, 64) { return 1 }

		// The failing descriptor keeps its original error and cached dirty bytes.
		C.errno = 0
		if !check(C.fdatasync(disk) == -1 && C.errno == C.EIO, 69) { return 1 }
		retained := [8192]u8{}
		if !check(C.pread(disk, &retained[0], sizeof(retained), 0) == isize(sizeof(retained)), 71) { return 1 }
		if !check(C.memcmp(&retained[0], &bytes[0], sizeof(bytes)) == 0, 72) { return 1 }
		if !check(C.close(disk) == 0 && C.close(ram) == 0, 73) { return 1 }
		C.puts(c'FSYNC-SCOPE PASS')
		for { C.pause() }
		return 0
	}
}

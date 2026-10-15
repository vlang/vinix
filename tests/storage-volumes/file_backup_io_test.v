// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli
import os

struct BackupFault {
mut:
	active bool
	operation int
	fail_at int
	counts [12]int
	opened int
	closed int
	short bool
	interrupted bool
	write_interrupted bool
	reuse bool
	temporary [64]char
	directory i32
	first_fd i32 = -1
	temporary_fd i32 = -1
}
__global backup_fault BackupFault

fn backup_fault_hit(operation int) bool {
	if !backup_fault.active { return false }
	backup_fault.counts[operation]++
	if backup_fault.operation == operation && backup_fault.fail_at == backup_fault.counts[operation] { unsafe { C.errno = C.EIO }; return true }
	return false
}
fn backup_fault_open(path &char, flags i32) i32 { fd := C.open(path, flags); if backup_fault.active && fd >= 0 { backup_fault.opened++ }; return fd }
fn backup_fault_openat(dir i32, path &char, flags i32, mode ...u32) i32 {
	fd := if mode.len == 0 { C.openat(dir, path, flags) } else { C.openat(dir, path, flags, mode[0]) }
	if backup_fault.active && fd >= 0 { backup_fault.opened++; if backup_fault.first_fd < 0 { backup_fault.first_fd = fd }; if flags & C.O_CREAT != 0 { backup_fault.temporary_fd = fd; backup_fault.directory = dir; unsafe { C.memcpy(&backup_fault.temporary[0], path, 64) } } }; return fd
}
fn backup_fault_close(fd i32) i32 { if backup_fault.active { backup_fault.closed++ }; result := C.close(fd); return if backup_fault_hit(7) { -1 } else { result } }
fn backup_fault_fstat(fd i32, info &C.stat) i32 {
	if backup_fault_hit(0) { return -1 }; result := C.fstat(fd, info)
	if backup_fault.active && result == 0 { unsafe {
		if backup_fault.operation == 9 && fd == backup_fault.temporary_fd { info.st_uid++ }
		if backup_fault.operation == 10 && fd == backup_fault.first_fd && backup_fault.counts[0] > 1 { info.st_size++ }
	} }; return result
}
fn backup_fault_pread(fd i32, data voidptr, size usize, offset i64) i64 {
	if backup_fault_hit(1) { return -1 }
	if backup_fault.active && backup_fault.short { if !backup_fault.interrupted { backup_fault.interrupted = true; unsafe { C.errno = C.EINTR }; return -1 }; return C.pread(fd, data, if size > 7 { usize(7) } else { size }, offset) }
	return C.pread(fd, data, size, offset)
}
fn backup_fault_pwrite(fd i32, data voidptr, size usize, offset i64) i64 {
	if backup_fault_hit(2) { return -1 }
	if backup_fault.active && backup_fault.short && !backup_fault.write_interrupted { backup_fault.write_interrupted = true; unsafe { C.errno = C.EINTR }; return -1 }
	return C.pwrite(fd, data, if backup_fault.active && backup_fault.short && size > 13 { usize(13) } else { size }, offset)
}
fn backup_fault_fsync(fd i32) i32 {
	if backup_fault.active { assert backup_fault.closed == if fd == backup_fault.temporary_fd { 0 } else { 1 } }
	failed := backup_fault_hit(3)
	if backup_fault.active && backup_fault.reuse && backup_fault.counts[3] == 2 {
		// A different creator reuses the retired name before final directory fsync.
		other := C.openat(backup_fault.directory, &backup_fault.temporary[0], C.O_WRONLY | C.O_CREAT | C.O_EXCL, u32(0o600)); assert other >= 0
		assert C.write(other, c'sentinel', 8) == 8 && C.close(other) == 0
	}
	return if failed { -1 } else { C.fsync(fd) }
}
fn backup_fault_linkat(left i32, first &char, right i32, second &char, flags i32) i32 { if backup_fault_hit(4) { return -1 }; return C.linkat(left, first, right, second, flags) }
fn backup_fault_unlinkat(dir i32, path &char, flags i32) i32 { if backup_fault_hit(5) { return -1 }; return C.unlinkat(dir, path, flags) }
fn backup_fault_fchmod(fd i32, mode u32) i32 { if backup_fault_hit(6) { return -1 }; return C.fchmod(fd, mode) }
fn backup_fault_futimens(fd i32, times &C.timespec) i32 { if backup_fault_hit(8) { return -1 }; return C.futimens(fd, times) }
fn backup_fault_fchown(fd i32, uid u32, gid u32) i32 { if backup_fault_hit(9) { return -1 }; return C.fchown(fd, uid, gid) }
fn backup_fault_finish(printed bool) i32 {
	if !backup_fault.active { return finish_bundle_report(printed) }
	assert backup_fault.active && backup_fault.opened - backup_fault.closed in [3, 5]
	return if backup_fault.operation == 11 { 1 } else { finish_bundle_report(printed) }
}

fn backup_fault_call(kind int, source string, full string, delta string, output string, operation int, at int, short bool, reuse bool) (i32, [12]int) {
	backup_fault = BackupFault{active: true, operation: operation, fail_at: at, short: short, reuse: reuse}
	result := match kind { 0 { backup_file(source.str, unsafe { nil }, output.str) } 1 { backup_file(source.str, full.str, output.str) } 2 { restore_file(full.str, unsafe { nil }, output.str) } else { restore_file(delta.str, full.str, output.str) } }
	assert backup_fault.opened == backup_fault.closed
	counts := backup_fault.counts; backup_fault.active = false; return result, counts
}

fn test_file_backup_real_io_failures_short_transfers_balanced_owners_and_reused_temp_name() {
	work := os.join_path(os.temp_dir(), 'vinix-backup-io-${os.getpid()}'); os.mkdir(work)!; defer { os.rmdir_all(work) or {} }
	source := work + '/source'; full := work + '/full'; delta := work + '/delta'; output := work + '/output'
	original := []u8{len: 65553, init: u8(index)}; os.write_file_array(source, original)!; assert backup_file(source.str, unsafe { nil }, full.str) == 0
	mut changed := original.clone(); changed[0] ^= 1; os.write_file_array(source, changed)!; assert backup_file(source.str, full.str, delta.str) == 0
	for kind in 0 .. 4 {
		result, counts := backup_fault_call(kind, source, full, delta, output, -1, 0, false, false); assert result == 0; expected := os.read_bytes(output)!; os.rm(output)!
		for operation in 0 .. 9 { for at in 1 .. counts[operation] + 1 {
			result2, _ := backup_fault_call(kind, source, full, delta, output, operation, at, false, false)
			// A late directory barrier or temporary cleanup error can leave the
			// complete published destination. It never replaces a prior file.
			if operation != 7 || at == 1 { assert result2 == 1 }
			if os.exists(output) { assert os.read_bytes(output)! == expected; os.rm(output)! }
			assert os.ls(work)!.all(!it.starts_with('.vinix-backup-'))
		} }
		result3, _ := backup_fault_call(kind, source, full, delta, output, -1, 0, true, false); assert result3 == 0 && os.read_bytes(output)! == expected; os.rm(output)!
		result4, _ := backup_fault_call(kind, source, full, delta, output, -1, 0, false, true); assert result4 == 0
		name := unsafe { cstring_to_vstring(&backup_fault.temporary[0]).clone() }; assert os.read_file(work + '/' + name)! == 'sentinel'; os.rm(work + '/' + name)!; os.rm(output)!
		result5, _ := backup_fault_call(kind, source, full, delta, output, 3, 2, false, true); assert result5 == 1 && os.read_bytes(output)! == expected
		name2 := unsafe { cstring_to_vstring(&backup_fault.temporary[0]).clone() }; assert os.read_file(work + '/' + name2)! == 'sentinel'; os.rm(work + '/' + name2)!; os.rm(output)!
		result6, _ := backup_fault_call(kind, source, full, delta, output, 10, 0, false, false); assert result6 == 1 && !os.exists(output)
		result7, _ := backup_fault_call(kind, source, full, delta, output, 11, 0, false, false); assert result7 == 1 && os.read_bytes(output)! == expected; os.rm(output)!
		if kind >= 2 { result8, _ := backup_fault_call(kind, source, full, delta, output, 9, 1, false, false); assert result8 == 1 && !os.exists(output) }
	}
	assert os.read_bytes(source)! == changed && os.read_bytes(full)!.len > 256 && os.read_bytes(delta)!.len > 256
}

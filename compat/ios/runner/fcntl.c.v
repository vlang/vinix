// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn C.fcntl(i32, i32, ...usize) i32
fn C.ios_fcntl()
fn C.fsync(i32) i32

fn darwin_fcntl_getfl(fd i32) i32 {
	status := i32(darwin_file_result(C.fcntl(fd, C.F_GETFL, usize(0))))
	if status < 0 { return status }
	$if linux {
		mut flags := status & 3
		if status & C.O_NONBLOCK != 0 { flags |= 4 }
		if status & C.O_APPEND != 0 { flags |= 8 }
		if status & C.O_ASYNC != 0 { flags |= 0x40 }
		if status & C.O_SYNC == C.O_SYNC { flags |= 0x80 }
		else if status & C.O_DSYNC != 0 { flags |= 0x400000 }
		// Creation and descriptor flags are absent from Darwin F_GETFL, even
		// if the native open-file description still records some of them.
		return flags
	}
	return status
}

fn darwin_fcntl_setfl(fd i32, flags i32) i32 {
	$if linux {
		status := i32(darwin_file_result(C.fcntl(fd, C.F_GETFL, usize(0))))
		if status < 0 { return status }
		// The guest does not implement asynchronous SIGIO delivery. The native
		// sync encoding also cannot preserve two independently reported Darwin
		// sync bits when both are requested; reject that combination explicitly.
		if flags & 0x40 != 0 || status & C.O_ASYNC != 0 || flags & 0x400080 == 0x400080 {
			darwin_set_errno(45)
			return -1
		}
		mut native := status & ~(C.O_NONBLOCK | C.O_APPEND | C.O_SYNC)
		if flags & 4 != 0 { native |= C.O_NONBLOCK }
		if flags & 8 != 0 { native |= C.O_APPEND }
		if flags & 0x80 != 0 { native |= C.O_SYNC }
		if flags & 0x400000 != 0 { native |= C.O_DSYNC }
		// Vinix F_SETFL changes these bits on the shared open-file description,
		// including O_SYNC/O_DSYNC, and keeps the original access mode.
		return i32(darwin_file_result(C.fcntl(fd, C.F_SETFL, usize(native))))
	}
	return i32(darwin_file_result(C.fcntl(fd, C.F_SETFL, usize(u32(flags)))))
}

@[export: 'ios_fcntl_stack']
fn darwin_fcntl(fd i32, command i32, stack u64) i32 {
	// Only commands with an argument read the Darwin variadic stack slot.
	// Getters and invalid commands are valid calls with no third argument.
	match command {
		0, 67 {
			minimum := i32(read32(stack))
			if darwin_file_result(C.fcntl(fd, C.F_GETFD, usize(0))) < 0 { return -1 }
			if minimum < 0 { darwin_set_errno(22); return -1 }
			$if linux {
				// The guest reports EMFILE for an out-of-range search floor.
				// Darwin reports EINVAL; exhaustion inside the range stays EMFILE.
				limit := C.sysconf(C._SC_OPEN_MAX)
				if limit > 0 && i64(minimum) >= limit { darwin_set_errno(22); return -1 }
			}
			native := if command == 67 { i32(C.F_DUPFD_CLOEXEC) } else { i32(C.F_DUPFD) }
			return i32(darwin_file_result(C.fcntl(fd, native, usize(u32(minimum)))))
		}
		1 { return i32(darwin_file_result(C.fcntl(fd, C.F_GETFD, usize(0)))) }
		2 { return i32(darwin_file_result(C.fcntl(fd, C.F_SETFD, usize(read32(stack) & 1)))) }
		3 { return darwin_fcntl_getfl(fd) }
		4 { return darwin_fcntl_setfl(fd, i32(read32(stack))) }
		else {
			if darwin_file_result(C.fcntl(fd, C.F_GETFD, usize(0))) < 0 { return -1 }
			unsupported := command in [i32(5), 6, 7, 8, 9, 10, 42, 43, 44, 45, 48, 49, 50, 51, 73, 74]!
			darwin_set_errno(if unsupported { 45 } else if command < 0 { 22 } else { 25 })
			return -1
		}
	}
}

fn darwin_fsync(fd i32) i32 { return i32(darwin_file_result(C.fsync(fd))) }

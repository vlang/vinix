// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	fn C.vm_read_overwrite(u32, u64, u64, u64, voidptr) i32
}
$if linux {
	fn C.process_vm_readv(i32, &C.iovec, usize, &C.iovec, usize, usize) isize
}

struct VmReadRanges {
mut:
	read_cursor u64
	read_end u64
	write_cursor u64
	write_end u64
	read_error i32
	write_error i32
}

// Only the address/permission prefix matters; long paths need no storage.
fn vm_read_map_line(data &u8, length int, mut ranges VmReadRanges) {
	mut at := 0
	mut bounds := [2]u64{}
	for part in 0 .. 2 {
		mut digits := 0
		mut value := u64(0)
		for at < length {
			byte := unsafe { data[at] }
			mut digit := u8(0)
			if byte >= `0` && byte <= `9` { digit = byte - `0` }
			else if byte >= `a` && byte <= `f` { digit = byte - `a` + 10 }
			else if byte >= `A` && byte <= `F` { digit = byte - `A` + 10 }
			else { break }
			if digits == 16 { return }
			value = (value << 4) | u64(digit)
			digits++; at++
		}
		if digits == 0 || at >= length || unsafe { data[at] } != if part == 0 { `-` } else { ` ` } { return }
		bounds[part] = value
		at++
	}
	if bounds[0] >= bounds[1] || length - at < 5 { return }
	unsafe {
		if (data[at] != `r` && data[at] != `-`) || (data[at + 1] != `w` && data[at + 1] != `-`)
			|| (data[at + 2] != `x` && data[at + 2] != `-`) || (data[at + 3] != `p` && data[at + 3] != `s`)
			|| data[at + 4] != ` ` { return }
		if ranges.read_error == 0 && ranges.read_cursor < ranges.read_end && bounds[0] <= ranges.read_cursor && ranges.read_cursor < bounds[1] {
			if data[at] == `r` { ranges.read_cursor = if bounds[1] < ranges.read_end { bounds[1] } else { ranges.read_end } }
			else { ranges.read_error = 2 }
		}
		if ranges.write_error == 0 && ranges.write_cursor < ranges.write_end && bounds[0] <= ranges.write_cursor && ranges.write_cursor < bounds[1] {
			if data[at + 1] == `w` { ranges.write_cursor = if bounds[1] < ranges.write_end { bounds[1] } else { ranges.write_end } }
			else { ranges.write_error = 2 }
		}
	}
}

fn vm_read_ranges(mut ranges VmReadRanges) i32 {
	fd := C.open(c'/proc/self/maps', C.O_RDONLY | C.O_CLOEXEC, 0)
	if fd < 0 { return 5 }
	defer { C.close(fd) }
	mut bytes := [4096]u8{}
	mut prefix := [64]u8{}
	mut length := 0
	for {
		count := C.read(fd, unsafe { &bytes[0] }, sizeof(bytes))
		if count < 0 {
			if unsafe { *C.ios_errno_address() } == C.EINTR { continue }
			return 5
		}
		if count == 0 {
			if length != 0 { vm_read_map_line(unsafe { &prefix[0] }, length, mut ranges) }
			if ranges.read_cursor != ranges.read_end && ranges.read_error == 0 { ranges.read_error = 1 }
			if ranges.write_cursor != ranges.write_end && ranges.write_error == 0 { ranges.write_error = 1 }
			return 0
		}
		for index in 0 .. int(count) {
			if bytes[index] == `\n` {
				vm_read_map_line(unsafe { &prefix[0] }, length, mut ranges)
				if ranges.read_error != 0 || (ranges.read_cursor == ranges.read_end
					&& (ranges.write_cursor == ranges.write_end || ranges.write_error != 0)) { return 0 }
				length = 0
			} else if length < prefix.len {
				prefix[length] = bytes[index]
				length++
			}
		}
	}
	return 5
}

fn darwin_vm_read_overwrite(task u32, source u64, size u64, destination u64, output voidptr) i32 {
	previous := unsafe { *C.ios_errno_address() }
	defer { darwin_set_errno(previous) }
	C.ios_mach_threads_lock()
	result := task_exception_destination(task)
	mut native_task := task
	$if macos {
		if system_data != unsafe { nil } && task == system_data.task_self { native_task = C.mach_task_self() }
	}
	C.ios_mach_threads_unlock()
	if result != 0 { return result }
	$if macos { return C.vm_read_overwrite(native_task, source, size, destination, output) }
	$if linux {
		if size == 0 {
			zero := u64(0)
			C.memcpy(output, unsafe { &zero }, 8)
			return 0
		}
		if source > ~u64(0) - size || destination > ~u64(0) - size || size > 0x7fffffffffffffff { return 1 }
		// Darwin's <=32 KiB kernel-buffer path reports invalid address without
		// a partial copy. Larger reads distinguish protection failures and can
		// copy a valid destination prefix, but still leave outsize unchanged.
		mut ranges := VmReadRanges{read_cursor: source, read_end: source + size,
			write_cursor: destination, write_end: destination + size}
		status := vm_read_ranges(mut ranges)
		if status != 0 { return status }
		if ranges.read_error != 0 { return if size <= 32768 { i32(1) } else { ranges.read_error } }
		if ranges.write_error != 0 && size <= 32768 { return 1 }
		write_size := if ranges.write_error == 0 { size } else { ranges.write_cursor - destination }
		if write_size == 0 { return ranges.write_error }
		mut small := [4096]u8{}
		mut snapshot := unsafe { voidptr(&small[0]) }
		if size > u64(small.len) {
			snapshot = C.mmap(unsafe { nil }, usize(size), C.PROT_READ | C.PROT_WRITE,
				C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
			if snapshot == unsafe { voidptr(-1) } { return 3 }
		}
		defer { if size > u64(small.len) { C.munmap(snapshot, usize(size)) } }
		local := C.iovec{snapshot, usize(size)}
		remote := C.iovec{voidptr(source), usize(size)}
		// Read the whole source before writing, including overlapping ranges.
		if C.process_vm_readv(C.getpid(), unsafe { &local }, 1, unsafe { &remote }, 1, 0) != isize(size) { return 1 }
		copy := C.iovec{snapshot, usize(write_size)}
		target := C.iovec{voidptr(destination), usize(write_size)}
		if C.process_vm_writev(C.getpid(), unsafe { &copy }, 1, unsafe { &target }, 1, 0) != isize(write_size) { return 1 }
		if ranges.write_error != 0 { return ranges.write_error }
		// MIG copies this output-only word last, even if it aliases copied data.
		C.memcpy(output, unsafe { &size }, 8)
		return 0
	}
	return 46
}

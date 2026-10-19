// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	fn C.vm_region_64(u32, voidptr, voidptr, i32, voidptr, voidptr, voidptr) i32
}

// Bounds suffice to distinguish end-of-map from unavailable region metadata.
// The /proc view does not expose all Mach basic/extended/top-info attributes.
fn vm_region_after(data &u8, length int, requested u64) bool {
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
			if digits == 16 { return false }
			value = (value << 4) | u64(digit)
			digits++; at++
		}
		if digits == 0 || at >= length || unsafe { data[at] } != if part == 0 { `-` } else { ` ` } { return false }
		bounds[part] = value
		at++
	}
	return bounds[0] < bounds[1] && requested < bounds[1]
}

fn vm_region_present(requested u64) i32 {
	fd := C.open(c'/proc/self/maps', C.O_RDONLY | C.O_CLOEXEC, 0)
	if fd < 0 { return 5 }
	defer { C.close(fd) }
	mut bytes := [4096]u8{}
	mut prefix := [40]u8{}
	mut length := 0
	for {
		count := C.read(fd, unsafe { &bytes[0] }, sizeof(bytes))
		if count < 0 {
			if unsafe { *C.ios_errno_address() } == C.EINTR { continue }
			return 5
		}
		if count == 0 { return if vm_region_after(unsafe { &prefix[0] }, length, requested) { i32(0) } else { i32(1) } }
		for index in 0 .. int(count) {
			if bytes[index] == `\n` {
				if vm_region_after(unsafe { &prefix[0] }, length, requested) { return 0 }
				length = 0
			} else if length < prefix.len {
				prefix[length] = bytes[index]
				length++
			}
		}
	}
	return 5
}

fn darwin_vm_region_64(task u32, address voidptr, size voidptr, flavor i32, info voidptr, count voidptr, object voidptr) i32 {
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
	$if macos { return C.vm_region_64(native_task, address, size, flavor, info, count, object) }
	$if linux {
		mut requested := u64(0)
		C.memcpy(unsafe { &requested }, address, 8)
		// Native lookup precedes flavor/count checks, including end-of-map.
		status := vm_region_present(requested)
		if status != 0 { return status }
		minimum := match flavor {
			9, 10, 13 { u32(9) }
			12 { u32(5) }
			else { return 4 }
		}
		mut capacity := u32(0)
		C.memcpy(unsafe { &capacity }, count, 4)
		if capacity < minimum { return 4 }
		// Do not synthesize tags, object identities, wire counts, inheritance
		// or residency statistics. Rejected queries leave every output intact.
		return 46
	}
	return 46
}

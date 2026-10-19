// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos { fn C.task_info(u32, i32, voidptr, voidptr) i32 }

struct TaskInfoMemory {
mut:
	virtual u64
	resident u64
	peak u64
	swap u64
	regions u32
	page u32
}

fn task_info_count(flavor i32, requested u32) u32 {
	if flavor == 20 { return if requested >= 12 { u32(12) } else { u32(0) } }
	if flavor == 22 {
		for count in [u32(93), 89, 87, 86, 84, 42, 38, 36]! { if requested >= count { return count } }
	}
	return 0
}

// A maps record can have an arbitrarily long pathname. Keep only its address
// prefix, across read boundaries, and consume the rest without allocating.
fn task_info_map_line(data &u8, length int, memory &TaskInfoMemory) bool {
	mut values := [2]u64{}; mut field := 0; mut digits := 0
	for i in 0 .. length {
		byte := unsafe { data[i] }
		if byte == `-` && field == 0 && digits > 0 { field = 1; digits = 0; continue }
		if byte == ` ` && field == 1 && digits > 0 {
			if values[1] <= values[0] || memory.regions == 0x7fffffff || memory.virtual > ~u64(0) - (values[1] - values[0]) { return false }
			unsafe { memory.virtual += values[1] - values[0]; memory.regions++ }
			return true
		}
		digit := if byte >= `0` && byte <= `9` { byte - `0` } else if byte >= `a` && byte <= `f` { byte - `a` + 10 } else { u8(255) }
		if digit == 255 || digits == 16 { return false }
		values[field] = values[field] * 16 + u64(digit); digits++
	}
	return false
}

fn task_info_maps(memory &TaskInfoMemory) bool {
	fd := C.open(c'/proc/self/maps', C.O_RDONLY | C.O_CLOEXEC, 0)
	if fd < 0 { return false }
	defer { C.close(fd) }
	mut bytes := [4096]u8{}; mut prefix := [40]u8{}; mut length := 0
	for {
		count := C.read(fd, unsafe { &bytes[0] }, bytes.len)
		if count < 0 { if unsafe { *C.ios_errno_address() } == C.EINTR { continue }; return false }
		if count == 0 { return length == 0 && memory.regions != 0 }
		for i in 0 .. int(count) {
			if bytes[i] == `\n` {
				if !task_info_map_line(unsafe { &prefix[0] }, length, memory) { return false }
				length = 0
			} else if length < prefix.len { prefix[length] = bytes[i]; length++ }
		}
	}
	return false
}

fn task_info_snapshot(memory &TaskInfoMemory) bool {
	mut bytes := [8192]u8{}
	length := proc_rusage_read(c'/proc/self/stat', unsafe { &bytes[0] }, bytes.len)
	if length < 0 { return false }
	pages := proc_rusage_stat_field(unsafe { &bytes[0] }, length, 24) or { return false }
	page := C.getpagesize()
	if page <= 0 || pages > ~u64(0) / u64(page) { return false }
	mut resident := pages * u64(page)
	if resident == 0 {
		fallback := proc_rusage_read(c'/proc/self/statm', unsafe { &bytes[0] }, bytes.len)
		if fallback < 0 || !proc_rusage_resident(unsafe { &bytes[0] }, fallback, u64(page), unsafe { &resident }) || resident == 0 { return false }
	}
	mut usage := C.rusage{}
	if C.getrusage(0, unsafe { &usage }) != 0 || usage.ru_maxrss < 0 || u64(usage.ru_maxrss) > ~u64(0) / 1024 { return false }
	mut fields := [3]u64{}
	status := proc_rusage_read(c'/proc/self/status', unsafe { &bytes[0] }, bytes.len)
	if status < 0 || !proc_rusage_fields(unsafe { &bytes[0] }, status, true, unsafe { &fields[0] }) { return false }
	if resident > ~u64(0) - fields[1] { return false }
	peak := u64(usage.ru_maxrss) * 1024
	unsafe { *memory = TaskInfoMemory{resident: resident, peak: if peak > resident { peak } else { resident }, swap: fields[1], page: u32(page)} }
	// Vinix's stat virtual-size field is not populated. maps has an immutable
	// snapshot per open file and works without walking resident page tables.
	return task_info_maps(memory)
}

fn task_info_pair(words &u32, index int, value u64) {
	unsafe { words[index] = u32(value); words[index + 1] = u32(value >> 32) }
}

fn task_info_pack(memory TaskInfoMemory, flavor i32, words &u32) {
	task_info_pair(words, 0, memory.virtual)
	if flavor == 20 {
		task_info_pair(words, 2, memory.resident); task_info_pair(words, 4, memory.peak)
		// Task policy is timesharing; no Mach task suspension is implemented.
		// Linux has no separate terminated-thread times, so those stay zero.
		unsafe { words[10] = 1 }
	} else {
		unsafe { words[2] = memory.regions; words[3] = memory.page }
		task_info_pair(words, 4, memory.resident); task_info_pair(words, 6, memory.peak)
		task_info_pair(words, 36, memory.resident + memory.swap)
		// Darwin's tagged/compressor ledgers, map bounds, remaining task limit
		// and their lifetime peaks have no equivalent in Vinix's accounting.
	}
}

fn darwin_task_info(task u32, flavor i32, output voidptr, count voidptr) i32 {
	previous := unsafe { *C.ios_errno_address() }
	defer { darwin_set_errno(previous) }
	// Native client marshalling reads the input count before resolving a port.
	mut requested := u32(0)
	C.memcpy(unsafe { voidptr(&requested) }, count, 4)
	C.ios_mach_threads_lock()
	result := task_exception_destination(task)
	mut destination := task
	$if macos { if system_data != unsafe { nil } && task == system_data.task_self { destination = C.mach_task_self() } }
	C.ios_mach_threads_unlock()
	if result != 0 { return result }
	$if macos { return C.task_info(destination, flavor, output, count) }
	$if linux {
		length := task_info_count(flavor, requested)
		if length == 0 { return 4 }
		mut memory := TaskInfoMemory{}
		if !task_info_snapshot(unsafe { &memory }) { return 5 }
		mut words := [93]u32{}
		task_info_pack(memory, flavor, unsafe { &words[0] })
		// The native reply copies the record before its count. All sources are
		// local, so unaligned and aliased count/output spans keep this order.
		C.memcpy(output, unsafe { voidptr(&words[0]) }, usize(length) * 4)
		C.memcpy(count, unsafe { voidptr(&length) }, 4)
		return 0
	}
}

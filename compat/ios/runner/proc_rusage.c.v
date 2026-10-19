// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#flag -lproc
	#include <libproc.h>
	#include <mach/mach_time.h>
	fn C.proc_pid_rusage(i32, i32, voidptr) i32
	fn C.mach_timebase_info(voidptr) i32
}

const proc_rusage_sizes = [u32(96), 144, 160, 232, 296, 304, 464]!

fn proc_rusage_scale(value u64, numerator u64, denominator u64) ?u64 {
	if numerator == 0 || denominator == 0 { return none }
	whole := value / denominator; fraction := value % denominator
	if whole > ~u64(0) / numerator || fraction > ~u64(0) / numerator { return none }
	base := whole * numerator; extra := fraction * numerator / denominator
	if base > ~u64(0) - extra { return none }
	return base + extra
}

fn proc_rusage_native(pid i32, flavor i32, output voidptr, previous i32) i32 {
	$if macos {
		if flavor < 0 || flavor >= proc_rusage_sizes.len || output == unsafe { nil } {
			return darwin_process_result(C.proc_pid_rusage(pid, flavor, output), previous)
		}
		mut words := [58]u64{}
		result := C.proc_pid_rusage(pid, flavor, unsafe { voidptr(&words[0]) })
		if result != 0 { return darwin_process_result(result, previous) }
		mut base := [2]u32{}
		if C.mach_timebase_info(unsafe { voidptr(&base[0]) }) != 0 { darwin_set_errno(5); return -1 }
		// Match the runner's nanosecond Mach clock/timebase. Energy, cycle,
		// instruction and byte fields keep their native units.
		for index in [2, 3, 10, 11, 12, 13, 17, 20, 21, 22, 23, 24, 25, 26, 27, 28, 36, 38, 39, 44, 45]! {
			if u32(index * 8) >= proc_rusage_sizes[flavor] { continue }
			words[index] = proc_rusage_scale(words[index], u64(base[0]), u64(base[1])) or { darwin_set_errno(84); return -1 }
		}
		unsafe { C.memcpy(output, voidptr(&words[0]), usize(proc_rusage_sizes[flavor])) }
		darwin_set_errno(previous); return 0
	}
	return -1
}

fn proc_rusage_token(data &u8, length int, offset int) (int, int) {
	mut start := offset
	for start < length && unsafe { data[start] } in [` `, `\t`, `\n`, `\r`]! { start++ }
	mut end := start
	for end < length && unsafe { data[end] } !in [` `, `\t`, `\n`, `\r`]! { end++ }
	return start, end
}

fn proc_rusage_resident(data &u8, length int, page u64, output &u64) bool {
	if page == 0 { return false }
	mut offset := 0; mut resident := u64(0)
	for index in 0 .. 7 {
		start, end := proc_rusage_token(data, length, offset)
		value := mach_host_amount(data, start, end, false) or { return false }
		if index == 1 { resident = value }
		offset = end
	}
	start, _ := proc_rusage_token(data, length, offset)
	if start != length || resident > ~u64(0) / page { return false }
	unsafe { *output = resident * page }
	return true
}

fn proc_rusage_stat_field(data &u8, length int, wanted int) ?u64 {
	if wanted < 4 { return none }
	// comm can contain spaces and parentheses. Its last ')' ends field 2.
	mut close := length - 1
	for close >= 0 && unsafe { data[close] } != `)` { close-- }
	if close < 0 { return none }
	mut offset := close + 1
	for field in 3 .. wanted + 1 {
		start, end := proc_rusage_token(data, length, offset)
		if start == end { return none }
		if field == wanted { return mach_host_amount(data, start, end, false) }
		offset = end
	}
	return none
}

fn proc_rusage_start(data &u8, length int, ticks u64, output &u64) bool {
	value := proc_rusage_stat_field(data, length, 22) or { return false }
	scaled := proc_rusage_scale(value, 1000000000, ticks) or { return false }
	unsafe { *output = scaled }; return true
}

// Missing platform counters have no Darwin equivalent and remain zero.
// A present but malformed/duplicate counter invalidates this snapshot.
fn proc_rusage_fields(data &u8, length int, status bool, output &u64) bool {
	if length < 0 { return false }
	mut values := [3]u64{}; mut present := u32(0); mut start := 0
	for end in 0 .. length + 1 {
		if end < length && unsafe { data[end] } != `\n` { continue }
		mut colon := start
		for colon < end && unsafe { data[colon] } != `:` { colon++ }
		mut field := -1
		if status {
			if proc_memory_matches(data, start, colon, 'VmLck') { field = 0 }
			if proc_memory_matches(data, start, colon, 'VmSwap') { field = 1 }
		} else {
			for index, name in ['read_bytes', 'write_bytes', 'wchar']! { if proc_memory_matches(data, start, colon, name) { field = index; break } }
		}
		if field >= 0 {
			if colon == end || present & (u32(1) << field) != 0 { return false }
			values[field] = mach_host_amount(data, colon + 1, end, status) or { return false }
			present |= u32(1) << field
		}
		start = end + 1
	}
	unsafe { C.memcpy(voidptr(output), voidptr(&values[0]), 24) }
	return true
}

fn proc_rusage_time(value C.timeval) ?u64 {
	seconds := i64(value.tv_sec); micros := i64(value.tv_usec)
	if seconds < 0 || micros < 0 || micros >= 1000000 { return none }
	if u64(seconds) > (~u64(0) - u64(micros) * 1000) / 1000000000 { return none }
	return u64(seconds) * 1000000000 + u64(micros) * 1000
}

fn proc_rusage_read(path &char, output &u8, capacity int) int {
	fd := C.open(path, C.O_RDONLY | C.O_CLOEXEC, 0)
	if fd < 0 { return -1 }
	defer { C.close(fd) }
	for {
		// These proc records fit in one bounded read. Vinix renders again
		// for each read: probing EOF can append another snapshot's suffix
		// when thread creation or accounting changes the record's length.
		count := C.read(fd, output, usize(capacity))
		if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }
		return if count >= 0 && count < capacity { int(count) } else { -1 }
	}
	return -1
}

fn proc_rusage_snapshot(words &u64) i32 {
	mut usage := C.rusage{}; mut children := C.rusage{}
	if C.getrusage(0, unsafe { &usage }) != 0 || C.getrusage(-1, unsafe { &children }) != 0 {
		darwin_set_errno(darwin_native_error(unsafe { *C.ios_errno_address() })); return -1
	}
	user := proc_rusage_time(usage.ru_utime) or { darwin_set_errno(84); return -1 }
	system := proc_rusage_time(usage.ru_stime) or { darwin_set_errno(84); return -1 }
	child_user := proc_rusage_time(children.ru_utime) or { darwin_set_errno(84); return -1 }
	child_system := proc_rusage_time(children.ru_stime) or { darwin_set_errno(84); return -1 }
	mut bytes := [8192]u8{}; mut resident := u64(0); mut started := u64(0)
	page := C.getpagesize(); ticks := C.sysconf(C._SC_CLK_TCK)
	if page <= 0 || ticks <= 0 { darwin_set_errno(45); return -1 }
	stat_length := proc_rusage_read(c'/proc/self/stat', unsafe { &bytes[0] }, bytes.len)
	if stat_length < 0 { darwin_set_errno(45); return -1 }
	if !proc_rusage_start(unsafe { &bytes[0] }, stat_length, u64(ticks), unsafe { &started }) { darwin_set_errno(5); return -1 }
	pages := proc_rusage_stat_field(unsafe { &bytes[0] }, stat_length, 24) or { darwin_set_errno(5); return -1 }
	if pages > ~u64(0) / u64(page) { darwin_set_errno(84); return -1 }
	resident = pages * u64(page)
	// stat's atomic RSS remains available while Vinix's statm mapping walk
	// cannot acquire the page-map lock. Use statm only as an older-kernel
	// fallback; an unavailable live counter must not become a zero footprint.
	if resident == 0 {
		length := proc_rusage_read(c'/proc/self/statm', unsafe { &bytes[0] }, bytes.len)
		if length < 0 || !proc_rusage_resident(unsafe { &bytes[0] }, length, u64(page), unsafe { &resident }) || resident == 0 { darwin_set_errno(35); return -1 }
	}
	mut status := [3]u64{}; mut io := [3]u64{}
	status_length := proc_rusage_read(c'/proc/self/status', unsafe { &bytes[0] }, bytes.len)
	if status_length >= 0 && !proc_rusage_fields(unsafe { &bytes[0] }, status_length, true, unsafe { &status[0] }) { darwin_set_errno(5); return -1 }
	io_length := proc_rusage_read(c'/proc/self/io', unsafe { &bytes[0] }, bytes.len)
	if io_length >= 0 && !proc_rusage_fields(unsafe { &bytes[0] }, io_length, false, unsafe { &io[0] }) { darwin_set_errno(5); return -1 }
	if resident > ~u64(0) - status[1] { darwin_set_errno(84); return -1 }
	footprint := resident + status[1]
	if usage.ru_maxrss < 0 || u64(usage.ru_maxrss) > ~u64(0) / 1024 { darwin_set_errno(84); return -1 }
	maximum := u64(usage.ru_maxrss) * 1024
	unsafe {
		words[2] = user; words[3] = system; words[6] = u64(usage.ru_majflt)
		words[7] = status[0]; words[8] = resident; words[9] = footprint; words[10] = started
		words[12] = child_user; words[13] = child_system; words[16] = u64(children.ru_majflt)
		words[18] = io[0]; words[19] = io[1]; words[29] = io[2]
		words[30] = if maximum > footprint { maximum } else { footprint }
	}
	return 0
}

fn darwin_proc_pid_rusage(pid i32, flavor i32, output voidptr) i32 {
	previous := unsafe { *C.ios_errno_address() }
	$if macos { return proc_rusage_native(pid, flavor, output, previous) }
	// Native validation resolves the process before checking flavor/buffer.
	if pid == 0 { darwin_set_errno(1); return -1 }
	if pid < 0 { darwin_set_errno(3); return -1 }
	if pid != C.getpid() {
		if C.kill(pid, 0) != 0 { darwin_set_errno(darwin_native_error(unsafe { *C.ios_errno_address() })); return -1 }
		darwin_set_errno(45); return -1 // Linux subset: the calling process only.
	}
	if flavor < 0 || flavor >= proc_rusage_sizes.len { darwin_set_errno(22); return -1 }
	if output == unsafe { nil } { darwin_set_errno(14); return -1 }
	mut words := [58]u64{}
	if proc_rusage_snapshot(unsafe { &words[0] }) != 0 { return -1 }
	unsafe { C.memcpy(output, voidptr(&words[0]), usize(proc_rusage_sizes[flavor])) }
	darwin_set_errno(previous)
	return 0
}

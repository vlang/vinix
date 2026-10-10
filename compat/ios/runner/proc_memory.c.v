// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn C.ios_native_proc_available_memory() usize

// Read a complete, bounded snapshot. Short reads and EINTR are normal; a
// truncated snapshot must never be interpreted as an unlimited budget.
fn proc_memory_read(path &char, output &u8, capacity int) int {
	fd := C.open(path, C.O_RDONLY | C.O_CLOEXEC, 0)
	if fd < 0 { return -1 }
	defer { C.close(fd) }
	mut length := 0
	for length < capacity {
		count := C.read(fd, unsafe { output + length }, usize(capacity - length))
		if count < 0 {
			if unsafe { *C.ios_errno_address() } == C.EINTR { continue }
			return -1
		}
		if count == 0 { return length }
		length += int(count)
	}
	mut extra := u8(0)
	for {
		count := C.read(fd, unsafe { &extra }, 1)
		if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }
		return if count == 0 { length } else { -1 }
	}
	return -1
}

fn proc_memory_matches(data &u8, start int, end int, value string) bool {
	return end - start == value.len && C.memcmp(unsafe { data + start }, value.str, usize(value.len)) == 0
}

// Only canonical absolute paths can be walked up to the visible hierarchy
// root. Reject namespace-relative '..', embedded NULs and empty components.
fn proc_memory_path_valid(data &u8, length int) bool {
	if length < 1 || unsafe { data[0] } != `/` { return false }
	mut start := 1
	unsafe {
		for i := 1; i <= length; i++ {
			if i < length && data[i] != `/` {
				if data[i] == 0 { return false }
				continue
			}
			if i == start { return length == 1 }
			if proc_memory_matches(data, start, i, '.') || proc_memory_matches(data, start, i, '..') { return false }
			start = i + 1
		}
	}
	return true
}

fn proc_memory_group(data &u8, length int, output &u8, capacity int) int {
	mut end := length
	unsafe {
		if end > 0 && data[end - 1] == `\n` { end-- }
		if end < 4 || data[0] != `0` || data[1] != `:` || data[2] != `:` { return -1 }
		// Hybrid/v1 controllers can enforce an additional, hidden budget.
		// A newline in a raw group name also makes membership ambiguous.
		for i in 3 .. end { if data[i] == `\n` { return -1 } }
		count := end - 3
		if count >= capacity || !proc_memory_path_valid(data + 3, count) { return -1 }
		C.memcpy(output, data + 3, usize(count))
		output[count] = 0
		return count
	}
}

fn proc_memory_token(data &u8, end int, offset int) (int, int, int) {
	mut start := offset
	unsafe {
		for start < end && data[start] == ` ` { start++ }
		mut finish := start
		for finish < end && data[finish] != ` ` { finish++ }
		return start, finish, finish
	}
}

fn proc_memory_mount_path(data &u8, start int, end int, output &u8, capacity int) int {
	mut count := 0
	mut i := start
	unsafe {
		for i < end {
			mut byte := data[i]
			if byte == `\\` {
				if i + 3 >= end { return -1 }
				match true {
					proc_memory_matches(data, i, i + 4, '\\040') { byte = ` ` }
					proc_memory_matches(data, i, i + 4, '\\011') { byte = `\t` }
					proc_memory_matches(data, i, i + 4, '\\012') { byte = `\n` }
					proc_memory_matches(data, i, i + 4, '\\134') { byte = `\\` }
					else { return -1 }
				}
				i += 3
			}
			if count + 1 >= capacity { return -1 }
			output[count] = byte
			count++
			i++
		}
		output[count] = 0
	}
	return if proc_memory_path_valid(output, count) { count } else { -1 }
}

fn proc_memory_mount(data &u8, length int, output &u8, capacity int) int {
	mut line := 0
	unsafe {
		for end := 0; end <= length; end++ {
			if end < length && data[end] != `\n` { continue }
			mut offset := line
			mut field := 0
			mut whole_root := false
			mut path_start := 0
			mut path_end := 0
			for offset < end {
				start, finish, next := proc_memory_token(data, end, offset)
				if start == finish { break }
				offset = next
				field++
				if field == 4 { whole_root = proc_memory_matches(data, start, finish, '/') }
				if field == 5 { path_start = start; path_end = finish }
				if field >= 7 && proc_memory_matches(data, start, finish, '-') {
					kind_start, kind_end, _ := proc_memory_token(data, end, offset)
					// A subtree-only mount hides ancestor limits. Without a view
					// of the whole hierarchy we cannot report usable headroom.
					if whole_root && proc_memory_matches(data, kind_start, kind_end, 'cgroup2') {
						return proc_memory_mount_path(data, path_start, path_end, output, capacity)
					}
					break
				}
			}
			line = end + 1
		}
	}
	return -1
}

// Explicit "max" uses the u64 ceiling sentinel. Malformed values fail instead
// of being interpreted as an unlimited budget.
fn proc_memory_amount(data &u8, length int) ?u64 {
	mut end := length
	unsafe {
		if end > 0 && data[end - 1] == `\n` { end-- }
		if proc_memory_matches(data, 0, end, 'max') { return ~u64(0) }
		if end == 0 { return none }
		mut value := u64(0)
		for i in 0 .. end {
			byte := data[i]
			if byte < `0` || byte > `9` { return none }
			digit := u64(byte - `0`)
			if value > (~u64(0) - digit) / 10 { return none }
			value = value * 10 + digit
		}
		return value
	}
}

fn proc_memory_value(path &u8, length int, name string) ?u64 {
	unsafe {
		C.memcpy(path + length, name.str, usize(name.len))
		path[length + name.len] = 0
	}
	mut bytes := [64]u8{}
	native_errno := C.ios_errno_address()
	unsafe { *native_errno = 0 }
	count := proc_memory_read(unsafe { &char(path) }, unsafe { &bytes[0] }, bytes.len)
	if count < 0 { return none }
	return proc_memory_amount(unsafe { &bytes[0] }, count)
}

fn proc_memory_native_budget() usize {
	// All snapshots/paths stay on the stack. Repeated queries own only their
	// native descriptors, each closed on every exit, with no cached budget.
	mut source := [65536]u8{}
	mut group := [4096]u8{}
	count := proc_memory_read(c'/proc/self/cgroup', unsafe { &source[0] }, source.len)
	if count < 0 { return 0 }
	group_length := proc_memory_group(unsafe { &source[0] }, count, unsafe { &group[0] }, group.len)
	if group_length < 0 { return 0 }
	mount_count := proc_memory_read(c'/proc/self/mountinfo', unsafe { &source[0] }, source.len)
	if mount_count < 0 { return 0 }
	mut path := [8224]u8{} // two bounded paths plus the control-file suffix
	mut root := proc_memory_mount(unsafe { &source[0] }, mount_count, unsafe { &path[0] }, 4096)
	if root < 0 { return 0 }
	if root == 1 { root = 0 }
	mut length := root
	if group_length > 1 {
		unsafe { C.memcpy(&path[length], &group[0], usize(group_length)) }
		length += group_length
	}
	mut remaining := ~u64(0)
	for {
		limit := proc_memory_value(unsafe { &path[0] }, length, '/memory.max') or {
			// Linux's root has no memory.max; a missing child/ancestor file
			// means the enforced budget cannot be determined safely.
			if length == root && unsafe { *C.ios_errno_address() } == C.ENOENT { break }
			return 0
		}
		if limit != ~u64(0) {
			used := proc_memory_value(unsafe { &path[0] }, length, '/memory.current') or { return 0 }
			if used == ~u64(0) { return 0 }
			headroom := if used >= limit { u64(0) } else { limit - used }
			if headroom < remaining { remaining = headroom }
		}
		if length == root { break }
		for length > root && path[length - 1] != `/` { length-- }
		if length > root { length-- }
	}
	return if remaining == ~u64(0) { usize(0) } else { usize(remaining) }
}

fn darwin_os_proc_available_memory() usize {
	previous := unsafe { *C.ios_errno_address() }
	defer { darwin_set_errno(previous) }
	$if macos { return C.ios_native_proc_available_memory() }
	$else { return proc_memory_native_budget() }
}

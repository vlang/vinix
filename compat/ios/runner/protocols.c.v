// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn C.getdelim(&&char, &usize, i32, voidptr) i64

fn system_protocol_space(value char) bool {
	return value == 32 || (value >= 9 && value <= 13)
}

// Tokens borrow spans of the line without modifying its separators. This
// permits a second pass to copy aliases after a matching record is found.
fn system_protocol_token(line &char, length usize, position &usize, size &usize) &char {
	unsafe {
		mut index := *position
		for index < length && system_protocol_space(line[index]) { index++ }
		if index == length || line[index] == 0 || line[index] == 35 { return nil }
		start := index
		for index < length && line[index] != 0 && line[index] != 35 && !system_protocol_space(line[index]) { index++ }
		*position = index
		*size = index - start
		return &line[start]
	}
}

fn system_protocol_token_equal(token &char, size usize, name &char) bool {
	return unsafe { C.strlen(name) == size && C.strncmp(token, name, size) == 0 }
}

fn system_protocol_token_copy(token &char, size usize) &char {
	buffer := unsafe { &char(C.malloc(size + 1)) }
	if buffer != unsafe { nil } { unsafe { C.memcpy(buffer, token, size); buffer[size] = 0 } }
	return buffer
}

// musl's protocol backend contains built-in names with no aliases and ignores
// /etc/protocols. Read the guest's real database to provide Darwin's alias
// lookup. Return 0 for a record, 1 for absence, -1 for a native I/O/allocation
// error. Output strings have their own allocations, independent of the file.
fn system_protocol_file(path &char, name &char, output &DarwinProtocol) i32 {
	file := C.fopen(path, c'r')
	if file == unsafe { nil } { return -1 }
	mut line := unsafe { &char(nil) }
	mut capacity := usize(0)
	defer {
		failure := unsafe { *C.ios_errno_address() }
		C.free(line)
		C.fclose(file)
		darwin_set_errno(failure)
	}
	for {
		darwin_set_errno(0)
		length := C.getdelim(&line, &capacity, 10, file)
		if length < 0 {
			if C.feof(file) != 0 { return 1 }
			if unsafe { *C.ios_errno_address() == 0 } { darwin_set_errno(5) }
			return -1
		}
		mut position := usize(0)
		mut size := usize(0)
		canonical := system_protocol_token(line, usize(length), &position, &size)
		if canonical == unsafe { nil } { continue }
		canonical_size := size
		mut matches := system_protocol_token_equal(canonical, size, name)
		number := system_protocol_token(line, usize(length), &position, &size)
		if number == unsafe { nil } || size == 0 { continue }
		mut value := u64(0)
		mut valid := true
		for index in usize(0) .. size {
			byte := unsafe { u8(number[index]) }
			if byte < 48 || byte > 57 { valid = false; break }
			value = value * 10 + u64(byte - 48)
			if value > 0x7fffffff { valid = false; break }
		}
		if !valid { continue }
		aliases_start := position
		mut count := usize(0)
		for {
			alias := system_protocol_token(line, usize(length), &position, &size)
			if alias == unsafe { nil } { break }
			if system_protocol_token_equal(alias, size, name) { matches = true }
			count++
		}
		if !matches { continue }
		mut protocol := DarwinProtocol{number: i32(value)}
		mut completed := false
		defer { if !completed { system_protocol_clear(mut protocol) } }
		protocol.name = system_protocol_token_copy(canonical, canonical_size)
		protocol.aliases = C.calloc(count + 1, sizeof(voidptr))
		if protocol.name == unsafe { nil } || protocol.aliases == unsafe { nil } {
			darwin_set_errno(12); return -1
		}
		position = aliases_start
		for index in usize(0) .. count {
			alias := system_protocol_token(line, usize(length), &position, &size)
			unsafe { protocol.aliases[index] = system_protocol_token_copy(alias, size) }
			if unsafe { protocol.aliases[index] == nil } { darwin_set_errno(12); return -1 }
		}
		unsafe { *output = protocol }
		completed = true
		return 0
	}
	return 1
}

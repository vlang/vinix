// SPDX-License-Identifier: GPL-2.0-or-later
// Console reads only bounded snapshots of ordinary files. It never reads a
// console device, FIFO, socket, or a synthetic kernel/crash stream.
module main

const console_tail_bytes = 128 * 1024

struct ConsoleSnapshot {
mut:
	text      string
	status    string
	limited   bool
	file_size u64
}

fn console_valid_path(path string) bool {
	if path.len == 0 || path.len > 4096 || path[0] != `/` { return false }
	for byte in path {
		if byte < 0x20 || byte == 0x7f { return false }
	}
	return true
}

fn console_read_snapshot(path string) ConsoleSnapshot {
	if !console_valid_path(path) { return ConsoleSnapshot{ status: 'console.invalid_path' } }
	// lstat rejects devices before open, while O_NONBLOCK and fstat protect
	// against a path replaced by a FIFO between those calls. Symlinks are
	// deliberately refused; callers can enter the regular target's path.
	mut before := C.stat{}
	if unsafe { C.lstat(&char(path.str), &before) } != 0 {
		return ConsoleSnapshot{
			status: if C.errno == C.ENOENT {
				'console.no_file'
			} else {
				'console.read_failed'
			}
		}
	}
	if u32(before.st_mode) & u32(C.S_IFMT) != u32(C.S_IFREG) {
		return ConsoleSnapshot{ status: 'console.not_regular' }
	}
	fd := C.open(&char(path.str), C.O_RDONLY | C.O_NONBLOCK | C.O_CLOEXEC | C.O_NOFOLLOW)
	if fd < 0 { return ConsoleSnapshot{ status: 'console.read_failed' } }
	defer { desktop_close(fd) }
	mut info := C.stat{}
	if unsafe { C.fstat(fd, &info) } != 0 || info.st_size < 0
		|| u32(info.st_mode) & u32(C.S_IFMT) != u32(C.S_IFREG) {
		return ConsoleSnapshot{ status: 'console.not_regular' }
	}
	file_size := u64(info.st_size)
	limited := file_size > u64(console_tail_bytes)
	offset := if limited { file_size - u64(console_tail_bytes) } else { u64(0) }
	if !desktop_seek_start(fd, offset) {
		return ConsoleSnapshot{ status: 'console.read_failed' }
	}
	wanted := int(file_size - offset)
	mut bytes := []u8{len: wanted}
	defer { unsafe { bytes.free() } }
	mut count := 0
	// A regular file can grow during reading; ignore those newer bytes until
	// the next snapshot. Truncation is a short snapshot, not stale output.
	for _ in 0 .. 64 {
		if count >= wanted { break }
		remaining := wanted - count
		chunk := if remaining > 4096 { 4096 } else { remaining }
		n := desktop_read(fd, unsafe { &u8(bytes.data) + count }, u64(chunk))
		if n < 0 {
			if C.errno == C.EINTR { continue }
			return ConsoleSnapshot{ status: 'console.read_failed' }
		}
		if n == 0 { break }
		count += int(n)
	}
	mut start := 0
	if limited {
		// Omit the partial first line when a complete following line exists.
		// A single huge line remains readable as a marked tail fragment.
		for index in 0 .. count {
			if bytes[index] == `\n` {
				if index + 1 < count { start = index + 1 }
				break
			}
		}
	}
	raw := if count > start { unsafe { tos(&u8(bytes.data) + start, count - start) } } else { '' }
	return ConsoleSnapshot{ text: console_sanitize(raw), limited: limited, file_size: file_size }
}

// Preserve complete valid UTF-8 and replace terminal controls/invalid bytes
// with visible question marks. CRLF is one newline; tabs become one space.
// Output cannot exceed the bounded input size.
fn console_sanitize(input string) string {
	mut bytes := []u8{cap: input.len}
	mut at := 0
	for at < input.len {
		lead := input[at]
		if lead == `\r` {
			bytes << `\n`
			at += if at + 1 < input.len && input[at + 1] == `\n` { 2 } else { 1 }
			continue
		}
		if lead == `\n` || lead == `\t` {
			bytes << if lead == `\t` { u8(` `) } else { lead }
			at++
			continue
		}
		length := editor_utf8_length(lead)
		mut valid := length > 0 && at + length <= input.len
		for index := 1; valid && index < length; index++ {
			valid = editor_utf8_follows(lead, index, input[at + index])
		}
		if !valid || lead < 0x20 || lead == 0x7f {
			bytes << `?`
			at++
		} else if length == 2 && lead == 0xc2 && input[at + 1] <= 0x9f {
			bytes << `?`
			at += 2
		} else {
			for index in 0 .. length { bytes << input[at + index] }
			at += length
		}
	}
	result := bytes.bytestr()
	unsafe { bytes.free() }
	return result
}

fn console_write_export(path string, data string) string {
	if !console_valid_path(path) { return 'console.invalid_path' }
	// Editor fields borrow a byte buffer that may retain a longer old suffix.
	// Give POSIX a terminated owned path rather than that borrowed view.
	terminated_path := path.clone()
	defer { unsafe { terminated_path.free() } }
	fd := C.open(&char(terminated_path.str), C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_NONBLOCK |
		C.O_CLOEXEC | C.O_NOFOLLOW, 0o600)
	if fd < 0 {
		return if C.errno == C.EEXIST { 'console.export_exists' } else { 'console.export_failed' }
	}
	written := desktop_write_all(fd, data.str, u64(data.len)) && desktop_preferences_fsync(fd)
	closed := desktop_close(fd) == 0
	if !written || !closed {
		// Only this newly created export is removed after an incomplete write.
		desktop_unlink(terminated_path)
		return 'console.export_failed'
	}
	return 'console.export_saved'
}

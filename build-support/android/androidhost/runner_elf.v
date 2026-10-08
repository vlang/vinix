module androidhost

import os
import encoding.hex

struct NeededSegment {
	kind    u32
	offset  u64
	address u64
	size    u64
}

fn needed_seek(mut file os.File, offset u64) ! {
	if offset > 0x7fffffffffffffff {
		return error("ValueError: cannot fit 'int' into an offset-sized integer")
	}
	if C.lseek(i32(file.fd), i64(offset), C.SEEK_SET) < 0 { return file_error('') }
}

fn needed_read(mut file os.File, count u64) ![]u8 {
	if count > 0x7fffffffffffffff {
		return error("OverflowError: cannot fit 'int' into an index-sized integer")
	}
	mut output := []u8{}
	mut buffer := [65536]u8{}
	mut remaining := count
	for remaining > 0 {
		wanted := if remaining > u64(buffer.len) { buffer.len } else { int(remaining) }
		n := C.read(i32(file.fd), &buffer[0], usize(wanted))
		if n < 0 {
			if C.errno == C.EINTR { continue }
			return file_error('')
		}
		if n == 0 { break }
		if u64(output.len) + u64(n) >= 0x7fffffff { return error('MemoryError') }
		output << buffer[..int(n)]
		remaining -= u64(n)
	}
	return output
}

fn needed_unpack(data []u8, offset u64, size u64) ! {
	if offset > 0x7fffffffffffffff {
		return error('OverflowError: Python int too large to convert to C ssize_t')
	}
	if offset > u64(data.len) || size > u64(data.len) - offset {
		return error('struct.error: unpack_from requires a buffer of at least ${offset + size} bytes for unpacking ${size} bytes at offset ${offset} (actual buffer size is ${data.len})')
	}
}

pub fn needed_libraries(path string) ![]string {
	if path.contains('\x00') { return error('ValueError: embedded null byte') }
	mut file := open_reader(path)!
	defer { file.close() }
	header := needed_read(mut file, 64)!
	if header.len < 64 || header[..6] != [u8(0x7f), `E`, `L`, `F`, 2, 1] { return []string{} }
	offset := elf_u64(header, 32)
	entry_size := u64(elf_u16(header, 54))
	count := u64(elf_u16(header, 56))
	needed_seek(mut file, offset)!
	raw := needed_read(mut file, entry_size * count)!
	mut segments := []NeededSegment{}
	for index := u64(0); index < count; index++ {
		at := index * entry_size
		needed_unpack(raw, at, 56)!
		segments << NeededSegment{elf_u32(raw, int(at)), elf_u64(raw, int(at) + 8), elf_u64(raw, int(at) + 16), elf_u64(raw, int(at) + 32)}
	}
	mut dynamic := NeededSegment{}
	mut has_dynamic := false
	for segment in segments {
		if segment.kind == 2 {
			dynamic = segment
			has_dynamic = true
			break
		}
	}
	if !has_dynamic { return []string{} }
	needed_seek(mut file, dynamic.offset)!
	table := needed_read(mut file, dynamic.size)!
	mut addresses := []u64{}
	mut string_address := u64(0)
	mut string_size := u64(0)
	mut has_address := false
	mut has_size := false
	for at := 0; table.len >= 16 && at <= table.len - 16; at += 16 {
		tag := elf_u64(table, at)
		value := elf_u64(table, at + 8)
		if tag == 1 { addresses << value }
		if tag == 5 && !has_address {
			string_address = value
			has_address = true
		}
		if tag == 10 && !has_size {
			string_size = value
			has_size = true
		}
	}
	if !has_address { return []string{} }
	mut load := NeededSegment{}
	mut has_load := false
	for segment in segments {
		if segment.kind == 1 && segment.address <= string_address && string_address - segment.address < segment.size {
			load = segment
			has_load = true
			break
		}
	}
	if !has_load { return error('StopIteration') }
	delta := string_address - load.address
	if load.offset > 0x7fffffffffffffff || delta > 0x7fffffffffffffff - load.offset {
		return error("ValueError: cannot fit 'int' into an offset-sized integer")
	}
	needed_seek(mut file, load.offset + delta)!
	strings := needed_read(mut file, string_size)!
	mut result := []string{}
	for address in addresses {
		if address >= u64(strings.len) {
			result << ''
			continue
		}
		start := int(address)
		mut end := start
		for end < strings.len && strings[end] != 0 { end++ }
		for index in start .. end {
			if strings[index] > 127 {
				return AsciiError{strings[start..end].clone(), index - start}
			}
		}
		result << strings[start..end].bytestr()
	}
	return result
}

struct RunnerFileError {
	original FileError
}

fn (e RunnerFileError) msg() string { return e.original.msg() }

fn (e RunnerFileError) code() int { return e.original.code() }

pub fn runner_file_query(row map[string]Value, operation string) !Value {
	path := hex.decode(text(row, 'path_hex')!)!.bytestr()
	result := if operation == 'runner_digest' {
		Value(digest(path) or {
			if err is FileError { return RunnerFileError{err} }
			return err
		})
	} else {
		Value((needed_libraries(path) or {
			if err is FileError { return RunnerFileError{err} }
			return err
		}).map(Value(it)))
	}
	return result
}

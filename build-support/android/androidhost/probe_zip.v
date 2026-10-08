module androidhost

import hash.crc32
import os

// Compression remains the system's unmodified zlib; archive policy is V.
#flag -lz
#include <zlib.h>

fn C.ftruncate(i32, u64) i32

@[typedef]
struct C.z_stream {
mut:
	next_in   &u8
	avail_in  u32
	next_out  &u8
	avail_out u32
	total_out u64
}

fn C.zlibVersion() &char
fn C.deflateInit2_(&C.z_stream, i32, i32, i32, i32, i32, &char, i32) i32
fn C.deflateBound(&C.z_stream, u64) u64
fn C.deflate(&C.z_stream, i32) i32
fn C.deflateEnd(&C.z_stream) i32
fn C.inflateInit2_(&C.z_stream, i32, &char, i32) i32
fn C.inflate(&C.z_stream, i32) i32
fn C.inflateEnd(&C.z_stream) i32

pub struct ZipError {
	message string
}

pub fn (e ZipError) msg() string { return e.message }

pub fn (e ZipError) code() int { return 0 }

fn zip_error(message string) IError { return ZipError{message} }

fn zip_deflate(input []u8) ![]u8 {
	mut stream := C.z_stream{}
	if C.deflateInit2_(&stream, 6, 8, -15, 8, 0, C.zlibVersion(), i32(sizeof(C.z_stream))) != 0 {
		return error('Cannot initialize ZIP compressor')
	}
	defer { C.deflateEnd(&stream) }
	capacity := C.deflateBound(&stream, u64(input.len))
	if capacity > 0x7fffffff { return error('ZIP payload is too large') }
	mut output := []u8{len: int(capacity)}
	stream.next_in = input.data
	stream.avail_in = u32(input.len)
	stream.next_out = output.data
	stream.avail_out = u32(output.len)
	if C.deflate(&stream, 4) != 1 { return error('Cannot compress ZIP payload') }
	return output[..int(stream.total_out)].clone()
}

fn zip_inflate(input []u8, size u64) ![]u8 {
	if size >= 0x7fffffff { return error('ZIP payload is too large') }
	mut stream := C.z_stream{}
	if C.inflateInit2_(&stream, -15, C.zlibVersion(), i32(sizeof(C.z_stream))) != 0 {
		return error('Cannot initialize ZIP decompressor')
	}
	defer { C.inflateEnd(&stream) }
	mut output := []u8{len: int(size) + 1}
	stream.next_in = input.data
	stream.avail_in = u32(input.len)
	stream.next_out = output.data
	stream.avail_out = u32(output.len)
	if C.inflate(&stream, 4) != 1 || stream.total_out != size {
		return zip_error('Invalid compressed ZIP payload')
	}
	return output[..int(size)].clone()
}

struct ZipEntry {
	name       string
	flags      u16
	method     u16
	checksum   u32
	compressed u64
	size       u64
	offset     u64
	central    []u8
}

struct ProbeZip {
	bytes   []u8
	entries []ZipEntry
	start   int
	comment []u8
}

struct ProbeAppend {
	new_archive bool
mut:
	archive ProbeZip
	stream  os.File
}

fn zip_bounds(bytes []u8, offset u64, size u64) bool {
	return offset <= u64(bytes.len) && size <= u64(bytes.len) - offset
}

fn parse_probe_zip(bytes []u8) !ProbeZip {
	if bytes.len < 22 { return zip_error('File is not a zip file') }
	mut end := bytes.len - 22
	minimum := if bytes.len > 65557 { bytes.len - 65557 } else { 0 }
	for end >= minimum {
		if elf_u32(bytes, end) == 0x06054b50 { break }
		end--
	}
	if end < minimum { return zip_error('File is not a zip file') }
	// ZipFile keeps the available suffix when the declared comment exceeds it.
	declared_comment := int(elf_u16(bytes, end + 20))
	comment_size := if declared_comment < bytes.len - end - 22 {
		declared_comment
	} else {
		bytes.len - end - 22
	}
	mut central_end := end
	mut central_size := u64(elf_u32(bytes, end + 12))
	mut stored_start := u64(elf_u32(bytes, end + 16))
	if end >= 76 && elf_u32(bytes, end - 20) == 0x07064b50 && elf_u32(bytes, end - 76) == 0x06064b50 {
		central_end -= 76
		central_size = elf_u64(bytes, end - 36)
		stored_start = elf_u64(bytes, end - 28)
	}
	if central_size > u64(central_end) { return zip_error('Bad offset for central directory') }
	start := central_end - int(central_size)
	if stored_start > u64(start) { return zip_error('Bad offset for central directory') }
	adjustment := u64(start) - stored_start
	mut cursor := start
	mut entries := []ZipEntry{}
	for cursor < central_end {
		if central_end - cursor < 46 { return zip_error('Truncated central directory') }
		if elf_u32(bytes, cursor) != 0x02014b50 {
			return zip_error('Bad magic number for central directory')
		}
		names := int(elf_u16(bytes, cursor + 28))
		extra := int(elf_u16(bytes, cursor + 30))
		comment := int(elf_u16(bytes, cursor + 32))
		length := 46 + names + extra + comment
		if length > central_end - cursor { return zip_error('Truncated central directory') }
		name := bytes[cursor + 46..cursor + 46 + names].bytestr()
		mut compressed := u64(elf_u32(bytes, cursor + 20))
		mut size := u64(elf_u32(bytes, cursor + 24))
		mut offset := u64(elf_u32(bytes, cursor + 42))
		mut extra_cursor := cursor + 46 + names
		extra_end := extra_cursor + extra
		for extra_cursor + 4 <= extra_end {
			kind := elf_u16(bytes, extra_cursor)
			field_size := int(elf_u16(bytes, extra_cursor + 2))
			extra_cursor += 4
			if field_size > extra_end - extra_cursor { return zip_error('Corrupt extra field') }
			if kind == 1 {
				mut at := extra_cursor
				for field_name in ['size', 'compressed', 'offset'] {
					needed := match field_name {
						'size' { size == 0xffffffff }
						'compressed' { compressed == 0xffffffff }
						else { offset == 0xffffffff }
					}
					if !needed { continue }
					if at + 8 > extra_cursor + field_size {
						return zip_error('Corrupt zip64 extra field')
					}
					value := elf_u64(bytes, at)
					match field_name {
						'size' { size = value }
						'compressed' { compressed = value }
						else { offset = value }
					}
					at += 8
				}
			}
			extra_cursor += field_size
		}
		if offset > ~u64(0) - adjustment { return zip_error('Bad offset for file header') }
		entries << ZipEntry{
			name:       name
			flags:      elf_u16(bytes, cursor + 8)
			method:     elf_u16(bytes, cursor + 10)
			checksum:   elf_u32(bytes, cursor + 16)
			compressed: compressed
			size:       size
			offset:     offset + adjustment
			central:    bytes[cursor..cursor + length].clone()
		}
		cursor += length
	}
	return ProbeZip{bytes.clone(), entries, start, bytes[end + 22..end + 22 + comment_size].clone()}
}

fn read_probe_zip(path string) !ProbeZip {
	return parse_probe_zip(probe_bytes(path)!)
}

fn probe_bytes(path string) ![]u8 {
	if path.contains('\x00') { return error('ValueError: embedded null byte') }
	mut stream := open_reader(path)!
	defer { stream.close() }
	mut state := C.stat{}
	if C.fstat(i32(stream.fd), &state) != 0 { return file_error('') }
	if state.st_size < 0 || u64(state.st_size) > 0x7fffffff {
		return error('ZIP archive is too large')
	}
	return read_part(mut stream, int(state.st_size), '')
}

fn (z ProbeZip) read_name(name string) ![]u8 {
	// ZipFile.read(name) uses the last occurrence of a duplicate name.
	mut selected := -1
	for i, entry in z.entries { if entry.name == name { selected = i } }
	if selected < 0 { return error('Missing ZIP entry ' + name) }
	entry := z.entries[selected]
	if !zip_bounds(z.bytes, entry.offset, 30) { return zip_error('Truncated file header') }
	offset := int(entry.offset)
	if elf_u32(z.bytes, offset) != 0x04034b50 {
		return zip_error('Bad magic number for file header')
	}
	start := entry.offset + 30 + u64(elf_u16(z.bytes, offset + 26)) + u64(elf_u16(z.bytes, offset + 28))
	if !zip_bounds(z.bytes, start, entry.compressed) { return zip_error('Truncated ZIP payload') }
	if entry.flags & 1 != 0 { return error('Encrypted ZIP payload is not supported') }
	compressed := z.bytes[int(start)..int(start + entry.compressed)]
	data := match entry.method {
		0 { compressed.clone() }
		8 { zip_inflate(compressed, entry.size)! }
		else { return error('Unsupported ZIP compression method') }
	}
	if crc32.sum(data) != entry.checksum { return zip_error("Bad CRC-32 for file '${name}'") }
	return data
}

fn put_zip16(mut bytes []u8, value u16) {
	bytes << u8(value)
	bytes << u8(value >> 8)
}

fn put_zip32(mut bytes []u8, value u32) {
	put_zip16(mut bytes, u16(value))
	put_zip16(mut bytes, u16(value >> 16))
}

fn put_zip64(mut bytes []u8, value u64) {
	put_zip32(mut bytes, u32(value))
	put_zip32(mut bytes, u32(value >> 32))
}

struct ProbePayload {
	name string
	data []u8
	mode u32 = 0o600
}

fn add_probe_entry(mut output []u8, item ProbePayload) ![]u8 {
	name := item.name.all_before('\x00')
	if name.len > 65535 || output.len >= 0x7fffffff || item.data.len >= 0x7fffffff {
		return error('ZIP payload is too large')
	}
	flags := u16(if name.bytes().any(it >= 128) { 0x800 } else { 0 })
	compressed := zip_deflate(item.data)!
	checksum := crc32.sum(item.data)
	offset := u32(output.len)
	put_zip32(mut output, 0x04034b50)
	for value in [u16(20), flags, 8, 0, 33] { put_zip16(mut output, value) }
	for value in [checksum, u32(compressed.len), u32(item.data.len)] {
		put_zip32(mut output, value)
	}
	put_zip16(mut output, u16(name.len))
	put_zip16(mut output, 0)
	output << name.bytes()
	output << compressed
	mut central := []u8{}
	put_zip32(mut central, 0x02014b50)
	for value in [u16(0x314), 20, flags, 8, 0, 33] { put_zip16(mut central, value) }
	for value in [checksum, u32(compressed.len), u32(item.data.len)] {
		put_zip32(mut central, value)
	}
	for value in [u16(name.len), 0, 0, 0, 0] { put_zip16(mut central, value) }
	put_zip32(mut central, item.mode << 16)
	put_zip32(mut central, offset)
	central << name.bytes()
	return central
}

fn finish_probe_zip(mut output []u8, central []u8, count int, comment []u8) ! {
	if u64(output.len) + u64(central.len) >= 0x7fffffff {
		return error('ZIP archive is too large')
	}
	start := u32(output.len)
	output << central
	if count > 65535 {
		zip64_start := u64(output.len)
		put_zip32(mut output, 0x06064b50)
		put_zip64(mut output, 44)
		put_zip16(mut output, 45)
		put_zip16(mut output, 45)
		put_zip32(mut output, 0)
		put_zip32(mut output, 0)
		put_zip64(mut output, u64(count))
		put_zip64(mut output, u64(count))
		put_zip64(mut output, u64(central.len))
		put_zip64(mut output, u64(start))
		put_zip32(mut output, 0x07064b50)
		put_zip32(mut output, 0)
		put_zip64(mut output, zip64_start)
		put_zip32(mut output, 1)
	}
	put_zip32(mut output, 0x06054b50)
	for value in [u16(0), 0, u16(if count > 65535 { 65535 } else { count }),
		u16(if count > 65535 { 65535 } else { count })] {
		put_zip16(mut output, value)
	}
	put_zip32(mut output, u32(central.len))
	put_zip32(mut output, start)
	put_zip16(mut output, u16(comment.len))
	output << comment
}

fn make_probe_zip(items []ProbePayload) ![]u8 {
	mut output := []u8{}
	mut central := []u8{}
	for item in items { central << add_probe_entry(mut output, item)! }
	finish_probe_zip(mut output, central, items.len, []u8{})!
	return output
}

fn write_probe_bytes(mut stream os.File, bytes []u8) ! {
	mut position := 0
	for position < bytes.len {
		n := C.write(i32(stream.fd), unsafe { &u8(bytes.data) + position }, usize(bytes.len - position))
		if n < 0 {
			if C.errno == C.EINTR { continue }
			return file_error('')
		}
		if n == 0 { return FileError{ message: os.get_error_msg(C.EIO), number: int(C.EIO) } }
		position += int(n)
	}
}

fn class_probe_zip(path string, root string, class string) ! {
	mut stream := os.create(path) or { return file_error(path) }
	defer { stream.close() }
	mut output := []u8{}
	mut central := []u8{}
	mut count := 0
	mut published := 0
	for name in probe_class_paths(root, class) {
		data := probe_bytes(name) or {
			finish_probe_zip(mut output, central, count, []u8{})!
			write_probe_bytes(mut stream, output[published..])!
			return err
		}
		central << add_probe_entry(mut output, ProbePayload{name[root.len + 1..], data, 0o600})!
		write_probe_bytes(mut stream, output[published..])!
		published = output.len
		count++
	}
	finish_probe_zip(mut output, central, count, []u8{})!
	write_probe_bytes(mut stream, output[published..])!
}

fn open_probe_append(path string) !ProbeAppend {
	mut stream := os.open_file(path, 'r+') or {
		failure := file_error(path)
		if failure.code() != int(C.ENOENT) { return failure }
		os.create(path) or { return file_error(path) }
	}
	mut state := C.stat{}
	if C.fstat(i32(stream.fd), &state) != 0 {
		failure := file_error('')
		stream.close()
		return failure
	}
	if state.st_size < 0 || u64(state.st_size) > 0x7fffffff {
		stream.close()
		return error('ZIP archive is too large')
	}
	bytes := read_part(mut stream, int(state.st_size), '') or {
		stream.close()
		return err
	}
	z := parse_probe_zip(bytes) or {
		if err !is ZipError {
			stream.close()
			return err
		}
		return ProbeAppend{ new_archive: true, archive: ProbeZip{bytes.clone(), []ZipEntry{}, bytes.len, []u8{}}, stream: stream }
	}
	return ProbeAppend{ new_archive: false, archive: z, stream: stream }
}

fn (mut a ProbeAppend) publish(item ?ProbePayload) ! {
	z := a.archive
	mut output := z.bytes[..z.start].clone()
	mut central := []u8{}
	for entry in z.entries { central << entry.central }
	mut count := z.entries.len
	if payload := item {
		central << add_probe_entry(mut output, payload)!
		count++
	}
	finish_probe_zip(mut output, central, count, z.comment)!
	if C.lseek(i32(a.stream.fd), i64(z.start), C.SEEK_SET) < 0 { return file_error('') }
	mut position := z.start
	for position < output.len {
		n := C.write(i32(a.stream.fd), unsafe { &u8(output.data) + position }, usize(output.len - position))
		if n < 0 {
			if C.errno == C.EINTR { continue }
			return file_error('')
		}
		if n == 0 { return FileError{ message: os.get_error_msg(C.EIO), number: int(C.EIO) } }
		position += int(n)
	}
	for C.ftruncate(i32(a.stream.fd), u64(output.len)) != 0 {
		if C.errno != C.EINTR { return file_error('') }
	}
	a.archive = parse_probe_zip(output)!
}

fn merge_probe_dex(dex ProbeZip, path string) ! {
	mut append := open_probe_append(path)!
	defer { append.stream.close() }
	if dex.entries.map(it.name) != ['classes.dex'] {
		if append.new_archive { append.publish(none)! }
		return ProbeExit{'fixture D8 archive contains unexpected entries'}
	}
	data := dex.read_name('classes.dex') or {
		if append.new_archive { append.publish(none)! }
		return err
	}
	append.publish(ProbePayload{'classes.dex', data, 0o600})!
}

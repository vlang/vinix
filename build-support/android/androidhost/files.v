module androidhost

import os
import crypto.sha256

#include <sys/stat.h>

fn C.fstat(i32, &C.stat) i32

pub struct FileError {
	message   string
	number    int
	filename  string
	filename2 string
}

pub fn (e FileError) msg() string { return e.message }

pub fn (e FileError) code() int { return e.number }

fn file_error(path string) IError {
	number := int(C.errno)
	return FileError{ message: os.get_error_msg(number), number: number, filename: path }
}

fn open_reader(path string) !os.File {
	mut stream := os.open(path) or { return file_error(path) }
	mut state := C.stat{}
	if C.fstat(i32(stream.fd), &state) != 0 {
		failure := file_error('')
		stream.close()
		return failure
	}
	if u32(state.st_mode) & u32(C.S_IFMT) == u32(C.S_IFDIR) {
		stream.close()
		return FileError{ message: os.get_error_msg(C.EISDIR), number: int(C.EISDIR), filename: path }
	}
	return stream
}

pub fn digest(path string) !string {
	if path.contains('\x00') { return error('ValueError: embedded null byte') }
	mut stream := open_reader(path)!
	defer { stream.close() }
	mut hash := sha256.new()
	mut buffer := []u8{len: 1024 * 1024}
	for {
		count := stream.read(mut buffer) or {
			if err is os.Eof { break }
			return file_error('')
		}
		if count == 0 { break }
		hash.write(buffer[..count])!
	}
	return hash.sum([]u8{}).hex()
}

pub fn relative(value Value) !string {
	if value !is string { return error('ART overlay path must be a string') }
	name := value as string
	parts := name.split('/')
	if name.contains('\x00') || parts.len < 2 || parts[0] != 'usr' || parts.any(it in ['', '.',
		'..']) {
		return error('unsafe ART overlay path: ${name}')
	}
	return name
}

fn read_part(mut stream os.File, count int, path string) ![]u8 {
	mut bytes := []u8{len: count}
	mut cursor := 0
	for cursor < count {
		n := stream.read_into_ptr(unsafe { &u8(bytes.data) + cursor }, count - cursor) or {
			if err is os.Eof { break }
			return file_error(path)
		}
		if n == 0 { break }
		cursor += n
	}
	return bytes[..cursor].clone()
}

fn elf_u16(bytes []u8, offset int) u16 { return u16(bytes[offset]) | u16(bytes[offset + 1]) << 8 }

fn elf_u32(bytes []u8, offset int) u32 {
	return u32(elf_u16(bytes, offset)) | u32(elf_u16(bytes, offset + 2)) << 16
}

fn elf_u64(bytes []u8, offset int) u64 {
	return u64(elf_u32(bytes, offset)) | u64(elf_u32(bytes, offset + 4)) << 32
}

// Keep the original bounded header reads rather than loading runtime libraries.
pub fn check_elf(path string, required bool) ! {
	if path.contains('\x00') { return error('ValueError: embedded null byte') }
	state := os.stat(path) or { return file_error(path) }
	size := state.size
	mut stream := open_reader(path)!
	defer { stream.close() }
	header := read_part(mut stream, 64, '')!
	if header.len < 4 || header[..4] != [u8(0x7f), `E`, `L`, `F`] {
		if required { return error('Android runtime payload is not an ELF: ${path}') }
		return
	}
	if header.len != 64 || header[..7] != [u8(0x7f), `E`, `L`, `F`, 2, 1, 1] || elf_u16(header, 18) != 183 || elf_u32(header, 20) != 1 {
		return error('ART overlay is not a native ARM64 ELF: ${path}')
	}
	offset := elf_u64(header, 32)
	entry_size := elf_u16(header, 54)
	count := elf_u16(header, 56)
	if entry_size != 56 || count == 0 || offset > size || u64(count) * entry_size > size - offset {
		return error('ART overlay has invalid ELF program headers: ${path}')
	}
	stream.seek(i64(offset), .start) or { return file_error('') }
	headers := read_part(mut stream, int(count) * int(entry_size), '')!
	mut loads := 0
	for index in 0 .. int(count) {
		start := index * 56
		if headers.len < start + 56 {
			return error('struct.error: unpack_from requires a buffer of at least ${start + 56} bytes for unpacking 56 bytes at offset ${start} (actual buffer size is ${headers.len})')
		}
		if elf_u32(headers, start) != 1 { continue }
		loads++
		file_offset := elf_u64(headers, start + 8)
		address := elf_u64(headers, start + 16)
		file_size := elf_u64(headers, start + 32)
		memory_size := elf_u64(headers, start + 40)
		if file_size > memory_size || file_offset > size || file_size > size - file_offset || memory_size > ~u64(0) - address || address % 16384 != file_offset % 16384 {
			return error('ART overlay ELF cannot load with 16 KiB pages: ${path}')
		}
	}
	if loads == 0 { return error('ART overlay ELF has no loadable segments: ${path}') }
}

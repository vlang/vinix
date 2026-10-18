// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

fn C.pread(int, voidptr, usize, i64) isize

fn profile_read_at(fd int, offset u64, mut bytes []u8) ! {
	mut done := 0
	for done < bytes.len {
		count := C.pread(fd, unsafe { &u8(bytes.data) + done }, usize(bytes.len - done), i64(offset + u64(done)))
		if count < 0 && C.errno == C.EINTR { continue }
		if count <= 0 { return error('cannot read executable profile headers') }
		done += int(count)
	}
}

fn profile_le(bytes []u8) u64 {
	mut value := u64(0)
	for i, byte in bytes { value |= u64(byte) << (8 * i) }
	return value
}

// Check the captured file's ELF64 target, file ranges and load/entry structure.
// This does not authenticate the application or qualify instructions/runtime ABI.
fn profile_elf(root int, path string, architecture string, kind string, require_executable bool) ! {
	if architecture !in ['aarch64', 'x86_64'] || kind !in ['static', 'pie', 'shared'] {
		return error('ELF profile has an unsupported architecture or image kind')
	}
	node := import_node(root, path)!
	defer { C.close(node.fd) }
	if node.mode & 0o170000 != 0o100000 || (require_executable && node.mode & 0o111 == 0)
		|| node.bytes < 64 || node.bytes > u64(512 * 1024 * 1024) {
		return error('ELF profile needs an ordinary executable: ${path}')
	}
	mut header := []u8{len: 64}
	defer { unsafe { header.free() } }
	profile_read_at(node.fd, 0, mut header)!
	machine := if architecture == 'aarch64' { u64(183) } else { u64(62) }
	image_type := profile_le(header[16..18])
	if header[..7] != [u8(127), `E`, `L`, `F`, 2, 1, 1] || profile_le(header[18..20]) != machine
		|| profile_le(header[20..24]) != 1 || image_type != if kind == 'static' { u64(2) } else { u64(3) } {
		return error('ELF profile has the wrong ELF target/type: ${architecture}/${path}')
	}
	offset := profile_le(header[32..40])
	width := profile_le(header[54..56])
	count := profile_le(header[56..58])
	if profile_le(header[52..54]) != 64 || width != 56 || count == 0 || count > 1024
		|| offset < 64 || offset > node.bytes || width * count > node.bytes - offset {
		return error('ELF profile has invalid program headers: ${path}')
	}
	entry := profile_le(header[24..32])
	mut program := []u8{len: 56}
	defer { unsafe { program.free() } }
	mut interpreter := false
	mut load := false
	mut executable_entry := false
	for i in 0 .. int(count) {
		profile_read_at(node.fd, offset + u64(i) * width, mut program)!
		type_ := profile_le(program[..4])
		// PT_NULL's remaining fields have no meaning.
		if type_ == 0 { continue }
		file_offset := profile_le(program[8..16])
		address := profile_le(program[16..24])
		file_size := profile_le(program[32..40])
		memory_size := profile_le(program[40..48])
		alignment := profile_le(program[48..56])
		if file_size > 0 && (file_offset > node.bytes || file_size > node.bytes - file_offset) {
			return error('ELF profile has a segment outside the file: ${path}')
		}
		if type_ == 1 {
			if memory_size < file_size || memory_size > ~u64(0) - address
				|| (alignment > 1 && (alignment & (alignment - 1) != 0 || address % alignment != file_offset % alignment)) {
				return error('ELF profile has an invalid load segment: ${path}')
			}
			if file_size > 0 { load = true }
			if profile_le(program[4..8]) & 1 != 0 && entry >= address && entry - address < file_size {
				executable_entry = true
			}
		} else if type_ == 3 {
			if interpreter || file_size < 2 || file_size > 4096 {
				return error('ELF profile has an invalid interpreter: ${path}')
			}
			mut name := []u8{len: int(file_size)}
			defer { unsafe { name.free() } }
			profile_read_at(node.fd, file_offset, mut name)!
			if name[0] != `/` || name.last() != 0 || name[..name.len - 1].contains(u8(0)) {
				return error('ELF profile needs an absolute NUL-terminated interpreter: ${path}')
			}
			interpreter = true
		}
	}
	if !load || (kind != 'shared' && (entry == 0 || !executable_entry)) {
		return error('ELF profile needs file-backed load segments and an executable entry: ${path}')
	}
	if interpreter != (kind == 'pie') { return error('ELF profile has an unexpected interpreter: ${path}') }
}

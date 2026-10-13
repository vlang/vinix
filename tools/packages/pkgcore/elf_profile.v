// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

fn C.pread(int, voidptr, usize, i64) isize

fn profile_read_at(fd int, offset u64, mut bytes []u8) ! {
	mut done := 0
	for done < bytes.len {
		count := C.pread(fd, unsafe { &u8(bytes.data) + done }, usize(bytes.len - done), i64(offset + u64(done)))
		if count < 0 && C.errno == C.EINTR { continue }
		if count <= 0 { return error('cannot read ELF profile executable headers') }
		done += int(count)
	}
}

fn profile_le(bytes []u8) u64 {
	mut value := u64(0)
	for i, byte in bytes { value |= u64(byte) << (8 * i) }
	return value
}

// The profile supports an ELF64 musl PIE CLI, shared loader/library and a static
// SDK runner on each host. This checks format/target, not every runtime ABI.
fn profile_elf(root int, path string, architecture string, kind string, require_executable bool) ! {
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
	if width < 56 || count == 0 || count > 1024 || offset > node.bytes || width * count > node.bytes - offset {
		return error('ELF profile has invalid program headers: ${path}')
	}
	mut program := []u8{len: 56}
	defer { unsafe { program.free() } }
	mut interpreter := false
	for i in 0 .. int(count) {
		profile_read_at(node.fd, offset + u64(i) * width, mut program)!
		if profile_le(program[..4]) == 3 { interpreter = true }
	}
	if interpreter != (kind == 'pie') { return error('ELF profile has an unexpected interpreter: ${path}') }
}

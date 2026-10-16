// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

// Structural Win64 application admission, not Authenticode verification or an
// assertion of Wine API/instruction support. PE machine and host are separate:
// the AArch64 runtime must supply its own explicit x86-64 translation closure.
fn profile_win64(root int, path string) ! {
	node := import_node(root, path)!
	defer { C.close(node.fd) }
	if node.mode & 0o170000 != 0o100000 || node.bytes < 64 || node.bytes > u64(512 * 1024 * 1024) {
		return error('Wine profile needs an ordinary Win64 executable of at most 512 MiB')
	}
	mut dos := []u8{len: 64}
	defer { unsafe { dos.free() } }
	profile_read_at(node.fd, 0, mut dos)!
	pe := profile_le(dos[60..64])
	if dos[..2] != [u8(`M`), `Z`] || pe < 64 || pe > node.bytes || node.bytes - pe < 24 {
		return error('Wine profile has invalid DOS/PE headers: ' + path)
	}
	mut header := []u8{len: 24}
	defer { unsafe { header.free() } }
	profile_read_at(node.fd, pe, mut header)!
	count := profile_le(header[6..8])
	width := profile_le(header[20..22])
	flags := profile_le(header[22..24])
	if header[..4] != [u8(`P`), `E`, 0, 0] || profile_le(header[4..6]) != 0x8664
		|| flags & 2 == 0 || flags & 0x2000 != 0 || count == 0 || count > 96
		|| width < 112 || width > 4096 || width > node.bytes - pe - 24 {
		return error('Wine profile requires an x86-64 PE32+ application, not a DLL: ' + path)
	}
	mut optional := []u8{len: 112}
	defer { unsafe { optional.free() } }
	profile_read_at(node.fd, pe + 24, mut optional)!
	entry := profile_le(optional[16..20])
	image_size := profile_le(optional[56..60])
	headers_size := profile_le(optional[60..64])
	subsystem := profile_le(optional[68..70])
	sections := pe + 24 + width
	if profile_le(optional[..2]) != 0x20b || subsystem !in [u64(2), 3] || entry == 0
		|| entry >= image_size || headers_size < sections || headers_size > node.bytes
		|| sections > node.bytes || count * 40 > node.bytes - sections
		|| sections + count * 40 > headers_size {
		return error('Wine profile has invalid Win64 optional headers: ' + path)
	}
	mut section := []u8{len: 40}
	defer { unsafe { section.free() } }
	mut executable_entry := false
	for index in 0 .. int(count) {
		profile_read_at(node.fd, sections + u64(index) * 40, mut section)!
		address := profile_le(section[12..16])
		size := profile_le(section[16..20])
		offset := profile_le(section[20..24])
		virtual_size := profile_le(section[8..12])
		mapped := if virtual_size > size { virtual_size } else { size }
		if address > image_size || mapped > image_size - address
			|| (size > 0 && (offset < headers_size || offset > node.bytes || size > node.bytes - offset)) {
			return error('Wine profile has an invalid Win64 section: ' + path)
		}
		if profile_le(section[36..40]) & 0x20000000 != 0 && entry >= address && entry - address < size {
			executable_entry = true
		}
	}
	if !executable_entry { return error('Wine profile needs a file-backed executable Win64 entrypoint: ' + path) }
}

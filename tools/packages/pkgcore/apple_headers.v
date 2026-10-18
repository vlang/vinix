// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

// Publisher admission for the qualified thin ARM64 iOS format. This bounded
// header/map check does not bind imports, verify Apple code signatures or
// establish runtime API compatibility. The runtime remains authoritative.
struct AppleSegment {
	address u64
	end u64
	fileoff u64
	filesize u64
	prot u64
}

fn profile_apple_image(root int, path string) ! {
	node := import_node(root, path)!
	defer { C.close(node.fd) }
	if node.mode & 0o170000 != 0o100000 || node.bytes < 32 || node.bytes > u64(512 * 1024 * 1024) {
		return error('Apple profile needs an ordinary Mach-O executable of at most 512 MiB')
	}
	mut header := []u8{len: 32}
	defer { unsafe { header.free() } }
	profile_read_at(node.fd, 0, mut header)!
	count := profile_le(header[16..20])
	size := profile_le(header[20..24])
	if profile_le(header[..4]) != 0xfeedfacf || profile_le(header[4..8]) != 0x100000c
		|| profile_le(header[8..12]) & 0xffffff != 0 || profile_le(header[12..16]) != 2
		|| profile_le(header[24..28]) & 0x200000 == 0 {
		return error('Apple profile requires a thin plain ARM64 position-independent Mach-O application')
	}
	if count == 0 || count > 4096 || size > 1024 * 1024 || size < count * 8 || size > node.bytes - 32 {
		return error('Apple profile has an invalid or oversized load-command area')
	}
	mut commands := []u8{len: int(size)}
	defer { unsafe { commands.free() } }
	profile_read_at(node.fd, 32, mut commands)!
	mut segments := []AppleSegment{cap: 128}
	defer { unsafe { segments.free() } }
	mut cursor := 0
	mut entry := u64(0)
	mut main := false
	mut platform := false
	for _ in 0 .. int(count) {
		if cursor > commands.len - 8 { return error('Apple profile has truncated load commands') }
		cmd := profile_le(commands[cursor..cursor + 4])
		width := profile_le(commands[cursor + 4..cursor + 8])
		if width < 8 || width % 8 != 0 || width > u64(commands.len - cursor) {
			return error('Apple profile has an invalid load-command size')
		}
		c := unsafe { commands[cursor..cursor + int(width)] }
		match cmd {
			0x19 { // LC_SEGMENT_64
				if width < 72 || profile_le(c[64..68]) > (width - 72) / 80 || segments.len >= 128 {
					return error('Apple profile has invalid or excessive segments/sections')
				}
				address := profile_le(c[24..32]); memory := profile_le(c[32..40])
				fileoff := profile_le(c[40..48]); filesize := profile_le(c[48..56])
				prot := profile_le(c[60..64]); maximum := profile_le(c[56..60])
				if address > ~u64(0) - memory || address + memory > ~u64(0) - 16383
					|| fileoff > node.bytes || filesize > node.bytes - fileoff || filesize > memory
					|| prot & ~u64(7) != 0 || prot & maximum != prot || prot & 6 == 6
					|| profile_le(c[68..72]) & ~u64(0x14) != 0 {
					return error('Apple profile has an invalid segment range, flags or protection')
				}
				for i in 0 .. int(profile_le(c[64..68])) {
					offset := 72 + i * 80
					start := profile_le(c[offset + 32..offset + 40])
					length := profile_le(c[offset + 40..offset + 48])
					if start < address || start > address + memory || length > address + memory - start {
						return error('Apple profile has a section outside its segment')
					}
				}
				if unsafe { C.memcmp(&c[8], c'__PAGEZERO\x00\x00\x00\x00\x00\x00', 16) } == 0 {
					if filesize != 0 || prot != 0 { return error('Apple profile has an invalid page-zero segment') }
				} else if memory > 0 {
					if address % 16384 != 0 { return error('Apple profile needs segments aligned for 4K and 16K hosts') }
					end := (address + memory + 16383) & ~u64(16383)
					for previous in segments {
						if address < previous.end && previous.address < end { return error('Apple profile has overlapping segments') }
					}
					segments << AppleSegment{ address: address, end: end, fileoff: fileoff, filesize: filesize, prot: prot }
				}
			}
			0x80000028 { // LC_MAIN
				if main || width != 24 || profile_le(c[16..24]) != 0 { return error('Apple profile needs one LC_MAIN without a custom stack') }
				entry = profile_le(c[8..16]); main = true
			}
			0x32 { // LC_BUILD_VERSION
				if platform || width < 24 || profile_le(c[8..12]) != 2 || profile_le(c[20..24]) != (width - 24) / 8 {
					return error('Apple profile requires one iOS deployment platform declaration')
				}
				platform = true
			}
			0x25 { // LC_VERSION_MIN_IPHONEOS
				if platform || width != 16 { return error('Apple profile has an invalid iOS minimum-version command') }
				platform = true
			}
			0x21, 0x2c { // LC_ENCRYPTION_INFO / LC_ENCRYPTION_INFO_64
				if width != 24 || profile_le(c[16..20]) != 0 { return error('Apple profile refuses encrypted Mach-O payloads') }
			}
			else {
				if cmd & 0x80000000 != 0 && cmd !in [u64(0x80000018), 0x8000001c, 0x80000022, 0x80000033, 0x80000034]! {
					return error('Apple profile has an unsupported required load command')
				}
			}
		}
		cursor += int(width)
	}
	if cursor != commands.len || !main || !platform || entry < 32 + size || entry % 4 != 0 || segments.len == 0 {
		return error('Apple profile needs complete iOS commands and an aligned code entrypoint')
	}
	mut first := ~u64(0); mut last := u64(0); mut backed := false
	for segment in segments {
		if segment.address < first { first = segment.address }
		if segment.end > last { last = segment.end }
		if segment.prot & 4 != 0 && entry >= segment.fileoff && entry - segment.fileoff < segment.filesize { backed = true }
	}
	if !backed || last - first > 512 * 1024 * 1024 { return error('Apple profile needs a file-backed executable entry and a bounded image span') }
}

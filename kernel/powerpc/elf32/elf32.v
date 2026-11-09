// SPDX-License-Identifier: GPL-2.0-or-later
module elf32

pub struct Segment {
pub mut:
	offset      u32
	address     u32
	file_size   u32
	memory_size u32
	flags       u32
}

pub struct Image {
pub mut:
	entry    u32
	base     u32
	end      u32
	count    u32
	phdr     u32
	phnum    u32
	segments [16]Segment
}

fn be16(data &u8, at u32) u16 {
	return unsafe { u16(data[at]) << 8 | u16(data[at + 1]) }
}

fn be32(data &u8, at u32) u32 {
	return unsafe { u32(data[at]) << 24 | u32(data[at + 1]) << 16 | u32(data[at + 2]) << 8 | u32(data[at + 3]) }
}

// Validate the entire image before claiming or writing any destination memory.
// Initial kernels use static ELF32 MSB ET_EXEC with identity load addresses.
// All parsing is allocation-free and independent of host width and byte order.
pub fn parse(data &u8, length u32, mut image Image) bool {
	return parse_image(data, length, false, mut image)
}

// Static libc initializes TLS itself from the program headers and aux vector.
// Firmware/kernel images retain the stricter no-TLS contract above.
pub fn parse_user(data &u8, length u32, mut image Image) bool {
	return parse_image(data, length, true, mut image)
}

fn parse_image(data &u8, length u32, user bool, mut image Image) bool {
	image = Image{}
	if length < 52 { return false }
	if be32(data, 0) != 0x7f454c46 || be16(data, 4) != 0x0102
		|| unsafe { data[6] } != 1 || be16(data, 16) != 2 || be16(data, 18) != 20
		|| be32(data, 20) != 1 || be32(data, 36) != 0 || be16(data, 40) != 52
		|| be16(data, 42) != 32 {
		return false
	}
	entry := be32(data, 24)
	table := be32(data, 28)
	count := u32(be16(data, 44))
	if count == 0 || count > 64 || table < 52 || table > length
		|| count > (length - table) / 32 || entry & 3 != 0 {
		return false
	}
	mut parsed := Image{ entry: entry, base: 0xffffffff }
	mut executable_entry := false
	for i := u32(0); i < count; i++ {
		at := table + i * 32
		kind := be32(data, at)
		if kind == 2 || kind == 3 || (kind == 7 && !user) { return false }
		if kind != 1 { continue }
		offset := be32(data, at + 4)
		address := be32(data, at + 8)
		physical := be32(data, at + 12)
		file_size := be32(data, at + 16)
		memory_size := be32(data, at + 20)
		flags := be32(data, at + 24)
		align := be32(data, at + 28)
		if file_size > memory_size || offset > length || file_size > length - offset
			|| address != physical || address < 0x10000 || address >= 0xfffff000
			|| memory_size > 0xfffff000 - address || flags & ~u32(7) != 0 {
			return false
		}
		if align > 1 && (align & (align - 1) != 0 || address % align != offset % align) {
			return false
		}
		if memory_size == 0 { continue }
		if parsed.count == 16 { return false }
		end := address + memory_size
		for j := u32(0); j < parsed.count; j++ {
			previous := parsed.segments[j]
			if address < previous.address + previous.memory_size && end > previous.address {
				return false
			}
		}
		parsed.segments[parsed.count] = Segment{offset, address, file_size, memory_size, flags}
		if table >= offset && table - offset <= file_size && count * 32 <= file_size - (table - offset) {
			parsed.phdr = address + table - offset
			parsed.phnum = count
		}
		parsed.count++
		if address < parsed.base { parsed.base = address }
		if end > parsed.end { parsed.end = end }
		if flags & 1 != 0 && file_size >= 4 && entry >= address && entry - address <= file_size - 4 {
			executable_entry = true
		}
	}
	if !executable_entry || parsed.count == 0 { return false }
	// A TLS template must be file-backed inside a readable load segment.
	mut tls_count := 0
	for i := u32(0); user && i < count; i++ {
		at := table + i * 32
		if be32(data, at) != 7 { continue }
		tls_count++
		offset := be32(data, at + 4)
		address := be32(data, at + 8)
		file_size := be32(data, at + 16)
		memory_size := be32(data, at + 20)
		align := be32(data, at + 28)
		if tls_count > 1 || parsed.phdr == 0 || file_size > memory_size
			|| memory_size > 0xfffff000 - address || address >= 0xfffff000
			|| align == 0 || align & (align - 1) != 0 { return false }
		mut covered := false
		for j := u32(0); j < parsed.count; j++ {
			segment := parsed.segments[j]
			if segment.flags & 4 != 0 && address >= segment.address
				&& address - segment.address <= segment.memory_size
				&& memory_size <= segment.memory_size - (address - segment.address)
				&& (file_size == 0 || (address - segment.address <= segment.file_size
				&& file_size <= segment.file_size - (address - segment.address)))
				&& offset >= segment.offset && offset - segment.offset == address - segment.address {
				covered = true
			}
		}
		if !covered { return false }
	}
	parsed.base &= ~u32(4095)
	parsed.end = (parsed.end + 4095) & ~u32(4095)
	image = parsed
	return true
}

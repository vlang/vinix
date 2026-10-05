// SPDX-License-Identifier: GPL-2.0-or-later
module macho

// No file structs are cast to pointers: Mach-O and universal headers have
// different byte orders, and a truncated file must never become a memory read.
struct Reader {
	data []u8
}

fn (r Reader) range(offset u64, size u64) ! {
	if offset > u64(r.data.len) || size > u64(r.data.len) - offset {
		return error('Mach-O: file range exceeds input')
	}
}

fn (r Reader) number(offset u64, size int, big bool) !u64 {
	r.range(offset, u64(size))!
	mut value := u64(0)
	for i in 0 .. size {
		index := if big { i } else { size - 1 - i }
		value = (value << 8) | u64(r.data[int(offset) + index])
	}
	return value
}

fn (r Reader) u16(offset u64) !u16 {
	return u16(r.number(offset, 2, false)!)
}

fn (r Reader) u32(offset u64) !u32 {
	return u32(r.number(offset, 4, false)!)
}

fn (r Reader) u64(offset u64) !u64 {
	return r.number(offset, 8, false)
}

fn (r Reader) string_at(offset u64, limit u64) !string {
	r.range(offset, limit)!
	for i in u64(0) .. limit {
		if r.data[int(offset + i)] == 0 {
			return r.data[int(offset)..int(offset + i)].bytestr()
		}
	}
	return error('Mach-O: unterminated string')
}

fn (r Reader) name(offset u64) !string {
	r.range(offset, 16)!
	mut length := 0
	for length < 16 && r.data[int(offset) + length] != 0 {
		length++
	}
	return r.data[int(offset)..int(offset) + length].bytestr()
}

fn checked_end(start u64, size u64) !u64 {
	if size > ~u64(0) - start {
		return error('Mach-O: address range overflows')
	}
	return start + size
}

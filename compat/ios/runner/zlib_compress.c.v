// SPDX-License-Identifier: GPL-2.0-or-later
module main

const zlib_length_base = [u16(3), 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23,
	27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]!
const zlib_length_extra = [u8(0), 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2,
	3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]!
const zlib_distance_base = [u16(1), 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97,
	129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289,
	16385, 24577]!

struct ZlibWriter {
mut:
	bytes &u8 = unsafe { nil }
	limit u64
	written u64
	bits u32
	bit_count u32
	full bool
}

fn (mut w ZlibWriter) byte(value u8) {
	if w.written >= w.limit { w.full = true; return }
	unsafe { w.bytes[w.written] = value }
	w.written++
}

fn (mut w ZlibWriter) write_bits(value u32, count u32) {
	if w.full { return }
	w.bits |= value << w.bit_count
	w.bit_count += count
	for w.bit_count >= 8 {
		w.byte(u8(w.bits))
		w.bits >>= 8
		w.bit_count -= 8
	}
}

fn zlib_reverse(value u32, count u32) u32 {
	mut reversed := u32(0)
	for i in 0 .. count { reversed = (reversed << 1) | ((value >> i) & 1) }
	return reversed
}

fn (mut w ZlibWriter) literal(symbol u32) {
	mut code := symbol + 0x30
	mut width := u32(8)
	if symbol >= 144 && symbol <= 255 { code = symbol - 144 + 0x190; width = 9 }
	else if symbol >= 256 && symbol <= 279 { code = symbol - 256; width = 7 }
	else if symbol >= 280 { code = symbol - 280 + 0xc0 }
	w.write_bits(zlib_reverse(code, width), width)
}

fn (mut w ZlibWriter) matched(length u32, distance u32) {
	mut li := 28
	for length < zlib_length_base[li] { li-- }
	w.literal(u32(257 + li))
	w.write_bits(length - zlib_length_base[li], zlib_length_extra[li])
	mut di := 29
	for distance < zlib_distance_base[di] { di-- }
	w.write_bits(zlib_reverse(u32(di), 5), 5)
	w.write_bits(distance - zlib_distance_base[di], if di < 4 { u32(0) } else { u32(di / 2 - 1) })
}

fn zlib_hash(bytes &u8, offset u64) u32 {
	word := unsafe { u32(bytes[offset]) | (u32(bytes[offset + 1]) << 8) | (u32(bytes[offset + 2]) << 16) }
	return (word * u32(2654435761)) >> 17
}

// The history occupies two fixed 32K tables, independent of the input length.
// Absolute positions make ring links unambiguous at window wrap boundaries.
fn zlib_fixed(mut w ZlibWriter, source &u8, count u64, history &u64, level i32) {
	heads := history
	previous := if history == unsafe { nil } { history } else { unsafe { history + 32768 } }
	chains := [u32(0), 4, 8, 16, 32, 64, 128, 256, 512, 1024]!
	nice := [u32(0), 8, 16, 32, 32, 64, 128, 128, 258, 258]!
	w.write_bits(3, 3) // BFINAL=1, BTYPE=01 (fixed Huffman).
	mut position := u64(0)
	for position < count && !w.full {
		mut best := u32(0)
		mut distance := u32(0)
		if count - position >= 3 {
			mut candidate := unsafe { heads[zlib_hash(source, position)] }
			maximum := u32(if count - position < 258 { count - position } else { u64(258) })
			mut attempts := chains[level]
			for candidate < position && position - candidate <= 32768 && attempts > 0 {
				mut length := u32(0)
				for length < maximum && unsafe { source[candidate + length] == source[position + length] } { length++ }
				if length > best {
					best = length
					distance = u32(position - candidate)
					if best >= nice[level] || best == maximum { break }
				}
				candidate = unsafe { previous[candidate & 32767] }
				attempts--
			}
		}
		consumed := if best >= 3 { best } else { u32(1) }
		if best >= 3 { w.matched(best, distance) } else { w.literal(unsafe { source[position] }) }
		if w.full { break }
		for i in 0 .. consumed {
			at := position + i
			if count - at < 3 { break }
			hash := zlib_hash(source, at)
			unsafe { previous[at & 32767] = heads[hash]; heads[hash] = at }
		}
		position += consumed
	}
	w.literal(256)
	if w.bit_count != 0 && !w.full { w.byte(u8(w.bits)); w.bits = 0; w.bit_count = 0 }
}

fn zlib_stored(mut w ZlibWriter, source &u8, count u64) {
	mut offset := u64(0)
	for !w.full {
		length := u32(if count - offset < 65535 { count - offset } else { u64(65535) })
		last := count - offset == length
		w.byte(if last { u8(1) } else { u8(0) })
		w.byte(u8(length)); w.byte(u8(length >> 8))
		w.byte(u8(~length)); w.byte(u8(~length >> 8))
		if w.full { return }
		copied := if u64(length) <= w.limit - w.written { u64(length) } else { w.limit - w.written }
		if copied != 0 { unsafe { C.memcpy(w.bytes + w.written, source + offset, usize(copied)) } }
		w.written += copied
		if copied != length { w.full = true; return }
		offset += length
		if last { break }
	}
}

fn zlib_header(mut w ZlibWriter, level i32) {
	flevel := if level <= 1 { u32(0) } else if level <= 5 { u32(1) } else if level == 6 { u32(2) } else { u32(3) }
	base := u32(0x7800) | (flevel << 6)
	header := base + (31 - base % 31) % 31
	w.byte(u8(header >> 8)); w.byte(u8(header))
}

// This expression intentionally retains Darwin unsigned-long wrapping.
fn zlib_compress_bound(count u64) u64 {
	return count + (count >> 12) + (count >> 14) + (count >> 25) + 13
}

fn zlib_trailer(mut writer ZlibWriter, source &u8, count u64) {
	// adler32's public length is 32-bit; compress2's source length is 64-bit.
	mut checksum := u64(1)
	mut offset := u64(0)
	for offset < count {
		chunk := u32(if count - offset > 0xffffffff { u64(0xffffffff) } else { count - offset })
		checksum = zlib_adler32(checksum, unsafe { source + offset }, chunk)
		offset += chunk
	}
	for shift in [u32(24), 16, 8, 0]! { writer.byte(u8(checksum >> shift)) }
}

// RFC 1950 output need not match another encoder byte for byte. Higher levels
// search longer LZ77 chains; a stored-block fallback guarantees compressBound.
// Only the history allocation is owned here, and every return frees it.
fn zlib_compress2(destination &u8, destination_length &u64, source &u8, count u64, requested_level i32) i32 {
	if destination_length == unsafe { nil } { return -2 }
	mut capacity := u64(0)
	unsafe { C.memcpy(&capacity, destination_length, 8) }
	mut written := u64(0)
	defer { unsafe { C.memcpy(destination_length, &written, 8) } }
	if requested_level < -1 || requested_level > 9 || destination == unsafe { nil }
		|| (source == unsafe { nil } && count != 0) { return -2 }
	if capacity == 0 { return -5 }
	level := if requested_level == -1 { i32(6) } else { requested_level }
	mut history := unsafe { &u64(nil) }
	if level != 0 && count >= 3 && capacity > 2 {
		history = unsafe { &u64(C.malloc(32768 * 8 * 2)) }
		if history == unsafe { nil } { return -4 }
		unsafe { C.memset(history, 0xff, 32768 * 8 * 2) }
	}
	defer { if history != unsafe { nil } { C.free(history) } }
	blocks := if count == 0 { u64(1) } else { count / 65535 + if count % 65535 == 0 { u64(0) } else { u64(1) } }
	overhead := blocks * 5 + 6
	stored_size := if count <= ~u64(0) - overhead { count + overhead } else { ~u64(0) }
	limit := if level != 0 && stored_size < capacity { stored_size } else { capacity }
	mut writer := ZlibWriter{bytes: destination, limit: limit}
	zlib_header(mut writer, level)
	if writer.written == writer.limit { writer.full = true }
	if !writer.full {
		if level == 0 { zlib_stored(mut writer, source, count) }
		else { zlib_fixed(mut writer, source, count, history, level) }
	}
	if !writer.full { zlib_trailer(mut writer, source, count) }
	if level != 0 && writer.full && capacity >= stored_size {
		writer = ZlibWriter{bytes: destination, limit: capacity}
		zlib_header(mut writer, level)
		zlib_stored(mut writer, source, count)
		if !writer.full { zlib_trailer(mut writer, source, count) }
	}
	written = writer.written
	return if writer.full { i32(-5) } else { i32(0) }
}

fn zlib_compress_symbol(symbol string) ?u64 {
	return match symbol {
		'_compress2' { u64(unsafe { voidptr(zlib_compress2) }) }
		'_compressBound' { u64(unsafe { voidptr(zlib_compress_bound) }) }
		else { return none }
	}
}

// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Darwin ARM64 zlib takes an unsigned-long seed, a borrowed byte buffer and a
// 32-bit length. Only the seed's low 32 bits participate. A null buffer resets
// the checksum to 1 regardless of length; a nonnull empty buffer normalizes
// both seed halves. No graphics backend or runtime-owned storage is needed.
fn zlib_adler32(seed u64, bytes &u8, length u32) u64 {
	if bytes == unsafe { nil } { return 1 }
	mut first := seed & 0xffff
	mut second := (seed >> 16) & 0xffff
	mut offset := u64(0)
	for offset < u64(length) {
		end := if u64(length) - offset > 5552 { offset + 5552 } else { u64(length) }
		for offset < end {
			first += unsafe { bytes[offset] }
			second += first
			offset++
		}
		first %= 65521
		second %= 65521
	}
	return ((second % 65521) << 16) | (first % 65521)
}

fn zlib_checksum_symbol(symbol string) ?u64 {
	if symbol == '_adler32' { return u64(unsafe { voidptr(zlib_adler32) }) }
	return none
}

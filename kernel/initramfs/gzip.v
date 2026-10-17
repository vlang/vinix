// SPDX-License-Identifier: GPL-2.0-or-later
module initramfs

// Release ISOs carry their image gzip-compressed, as Ubuntu, Debian and Arch
// carry their initramfs compressed: the bootloader reads a third of the bytes,
// and the kernel inflates them here, in one pass, into a buffer of the
// member's recorded size. RFC 1952 frames the RFC 1951 deflate data. Nothing
// in this file allocates; the caller provides the decoder and both buffers.

fn C.memcpy(voidptr, voidptr, usize) voidptr

const gzip_flag_hcrc = u8(0x02)
const gzip_flag_extra = u8(0x04)
const gzip_flag_name = u8(0x08)
const gzip_flag_comment = u8(0x10)
const gzip_flag_reserved = u8(0xe0)

const inflate_fast_bits = 9
const inflate_fast_size = 1 << inflate_fast_bits
const inflate_symbols = 288

const inflate_length_base = [u16(3), 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27,
	31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]!
const inflate_length_extra = [u8(0), 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3,
	3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]!
const inflate_distance_base = [u16(1), 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129,
	193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577]!
const inflate_distance_extra = [u8(0), 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7,
	8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]!
const inflate_code_length_order = [u8(16), 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13,
	2, 14, 1, 15]!

// What a gzip member says about itself before any of it is inflated.
pub struct GzipMember {
pub mut:
	// Offset of the deflate data from the start of the member.
	data_offset u64
	// The uncompressed size the trailer records (modulo 2^32).
	size u64
	crc  u32
	// The header's comment field, without its terminator; empty when absent.
	comment_offset u64
	comment_length u64
}

// A canonical Huffman code: a direct table for codes of up to
// inflate_fast_bits bits, and the canonical ranges for the longer ones.
struct InflateHuffman {
mut:
	// (length << inflate_fast_bits) | symbol, or 0 for a longer code.
	fast         [inflate_fast_size]u16
	first_code   [16]u16
	max_code     [17]int
	first_symbol [16]u16
	size         [inflate_symbols]u8
	value        [inflate_symbols]u16
}

// Decoder state. It is about 6 KiB: allocate it rather than keeping it on a
// kernel stack.
pub struct Inflater {
mut:
	input        &u8 = unsafe { nil }
	input_size   u64
	input_at     u64
	bits         u64
	bit_count    u32
	past_end     bool
	output       &u8 = unsafe { nil }
	output_size  u64
	output_at    u64
	literal      InflateHuffman
	distance     InflateHuffman
	code_length  InflateHuffman
	lengths      [320]u8
	crc_table    [256]u32
	crc_ready    bool
}

// Whether `data` begins a gzip member.
pub fn is_gzip(data &u8, size u64) bool {
	return size >= 18 && unsafe { data[0] == 0x1f && data[1] == 0x8b && data[2] == 8 }
}

// Read a member's header and trailer. Only a single-member file is accepted:
// the trailer is taken from the last eight bytes.
pub fn gzip_member(data &u8, size u64) ?GzipMember {
	if !is_gzip(data, size) {
		return none
	}
	flags := unsafe { data[3] }
	if flags & gzip_flag_reserved != 0 {
		return none
	}
	mut at := u64(10)
	mut member := GzipMember{}
	if flags & gzip_flag_extra != 0 {
		if at + 2 > size {
			return none
		}
		extra := u64(unsafe { data[at] }) | u64(unsafe { data[at + 1] }) << 8
		at += 2 + extra
	}
	if flags & gzip_flag_name != 0 {
		for at < size && unsafe { data[at] } != 0 {
			at++
		}
		at++
	}
	if flags & gzip_flag_comment != 0 {
		member.comment_offset = at
		for at < size && unsafe { data[at] } != 0 {
			at++
		}
		member.comment_length = at - member.comment_offset
		at++
	}
	if flags & gzip_flag_hcrc != 0 {
		at += 2
	}
	if at + 8 > size {
		return none
	}
	member.data_offset = at
	tail := size - 8
	member.crc = gzip_le32(data, tail)
	member.size = u64(gzip_le32(data, tail + 4))
	return member
}

fn gzip_le32(data &u8, at u64) u32 {
	return unsafe {
		u32(data[at]) | u32(data[at + 1]) << 8 | u32(data[at + 2]) << 16 | u32(data[at + 3]) << 24
	}
}

// Inflate the member in `data` into `output`, which must hold exactly
// `member.size` bytes, and check its length and CRC-32. Returns false for any
// malformed or mismatched stream.
pub fn (mut d Inflater) gunzip(data &u8, size u64, member GzipMember, output &u8) bool {
	d.input = unsafe { &u8(u64(data) + member.data_offset) }
	d.input_size = size - 8 - member.data_offset
	d.input_at = 0
	d.bits = 0
	d.bit_count = 0
	d.past_end = false
	d.output = unsafe { output }
	d.output_size = member.size
	d.output_at = 0
	if !d.inflate() || d.output_at != member.size {
		return false
	}
	return d.crc32(output, member.size) == member.crc
}

fn (mut d Inflater) inflate() bool {
	for {
		last := d.take(1)
		kind := d.take(2)
		match kind {
			0 {
				if !d.stored() {
					return false
				}
			}
			1 {
				if !d.fixed() || !d.codes() {
					return false
				}
			}
			2 {
				if !d.dynamic() || !d.codes() {
					return false
				}
			}
			else {
				return false
			}
		}
		if d.past_end {
			return false
		}
		if last == 1 {
			return true
		}
	}
	return false
}

@[inline]
fn (mut d Inflater) refill() {
	for d.bit_count <= 56 {
		if d.input_at < d.input_size {
			d.bits |= u64(unsafe { d.input[d.input_at] }) << d.bit_count
			d.input_at++
		} else {
			// The input ends; take() and decode() notice if a code needs more.
			return
		}
		d.bit_count += 8
	}
}

@[inline]
fn (mut d Inflater) take(count u32) u32 {
	if d.bit_count < count {
		d.refill()
		if d.bit_count < count {
			d.past_end = true
			return 0
		}
	}
	value := u32(d.bits & ((u64(1) << count) - 1))
	d.bits >>= count
	d.bit_count -= count
	return value
}

fn (mut d Inflater) stored() bool {
	// Drop to a byte boundary, then hand back the whole bytes the bit buffer
	// had read ahead.
	d.take(d.bit_count & 7)
	for d.bit_count >= 8 {
		d.bit_count -= 8
		d.input_at--
	}
	d.bits = 0
	d.bit_count = 0
	if d.input_at + 4 > d.input_size {
		return false
	}
	length := u64(unsafe { d.input[d.input_at] }) | u64(unsafe { d.input[d.input_at + 1] }) << 8
	inverse := u64(unsafe { d.input[d.input_at + 2] }) | u64(unsafe { d.input[d.input_at + 3] }) << 8
	d.input_at += 4
	if length != (~inverse & 0xffff) || d.input_at + length > d.input_size
		|| d.output_at + length > d.output_size {
		return false
	}
	unsafe {
		C.memcpy(&u8(u64(d.output) + d.output_at), &u8(u64(d.input) + d.input_at), usize(length))
	}
	d.input_at += length
	d.output_at += length
	return true
}

fn (mut d Inflater) fixed() bool {
	for i in 0 .. 144 {
		d.lengths[i] = 8
	}
	for i in 144 .. 256 {
		d.lengths[i] = 9
	}
	for i in 256 .. 280 {
		d.lengths[i] = 7
	}
	for i in 280 .. 288 {
		d.lengths[i] = 8
	}
	if !d.literal.build(&d.lengths[0], 288) {
		return false
	}
	for i in 0 .. 30 {
		d.lengths[i] = 5
	}
	return d.distance.build(&d.lengths[0], 30)
}

fn (mut d Inflater) dynamic() bool {
	literals := int(d.take(5)) + 257
	distances := int(d.take(5)) + 1
	code_lengths := int(d.take(4)) + 4
	if literals > 286 || distances > 30 {
		return false
	}
	for i in 0 .. 19 {
		d.lengths[i] = 0
	}
	for i in 0 .. code_lengths {
		d.lengths[inflate_code_length_order[i]] = u8(d.take(3))
	}
	if !d.code_length.build(&d.lengths[0], 19) {
		return false
	}
	total := literals + distances
	mut n := 0
	for n < total {
		symbol := d.decode(mut d.code_length)
		if symbol < 0 || d.past_end {
			return false
		}
		if symbol < 16 {
			d.lengths[n] = u8(symbol)
			n++
			continue
		}
		mut fill := u8(0)
		mut repeat := 0
		if symbol == 16 {
			if n == 0 {
				return false
			}
			fill = d.lengths[n - 1]
			repeat = int(d.take(2)) + 3
		} else if symbol == 17 {
			repeat = int(d.take(3)) + 3
		} else {
			repeat = int(d.take(7)) + 11
		}
		if n + repeat > total {
			return false
		}
		for _ in 0 .. repeat {
			d.lengths[n] = fill
			n++
		}
	}
	// The distance code lengths follow the literal ones in d.lengths.
	if !d.distance.build(&d.lengths[literals], distances) {
		return false
	}
	return d.literal.build(&d.lengths[0], literals)
}

fn (mut h InflateHuffman) build(lengths &u8, count int) bool {
	mut sizes := [17]int{}
	mut next_code := [16]int{}
	for i in 0 .. inflate_fast_size {
		h.fast[i] = 0
	}
	for i in 0 .. count {
		sizes[unsafe { lengths[i] }]++
	}
	sizes[0] = 0
	for i in 1 .. 16 {
		if sizes[i] > (1 << i) {
			return false
		}
	}
	mut code := 0
	mut symbols := 0
	for i in 1 .. 16 {
		next_code[i] = code
		h.first_code[i] = u16(code)
		h.first_symbol[i] = u16(symbols)
		code += sizes[i]
		if sizes[i] != 0 && code - 1 >= (1 << i) {
			return false
		}
		h.max_code[i] = code << (16 - i)
		code <<= 1
		symbols += sizes[i]
	}
	h.max_code[16] = 0x10000
	for i in 0 .. count {
		length := int(unsafe { lengths[i] })
		if length == 0 {
			continue
		}
		slot := next_code[length] - int(h.first_code[length]) + int(h.first_symbol[length])
		h.size[slot] = u8(length)
		h.value[slot] = u16(i)
		if length <= inflate_fast_bits {
			mut j := inflate_reverse(next_code[length], length)
			for j < inflate_fast_size {
				h.fast[j] = u16((length << inflate_fast_bits) | i)
				j += 1 << length
			}
		}
		next_code[length]++
	}
	return true
}

fn inflate_reverse(value int, bits int) int {
	mut reversed := u32(0)
	mut v := u32(value)
	for _ in 0 .. bits {
		reversed = (reversed << 1) | (v & 1)
		v >>= 1
	}
	return int(reversed)
}

@[inline]
fn (mut d Inflater) decode(mut h InflateHuffman) int {
	if d.bit_count < 16 {
		d.refill()
	}
	entry := h.fast[int(d.bits & u64(inflate_fast_size - 1))]
	if entry != 0 {
		length := u32(entry >> inflate_fast_bits)
		if length > d.bit_count {
			d.past_end = true
			return -1
		}
		d.bits >>= length
		d.bit_count -= length
		return int(entry & u16(inflate_fast_size - 1))
	}
	// Longer codes: compare the bit-reversed next 16 bits against each
	// length's canonical range.
	k := inflate_reverse(int(d.bits & 0xffff), 16)
	mut s := inflate_fast_bits + 1
	for s < 16 && k >= h.max_code[s] {
		s++
	}
	if s >= 16 || u32(s) > d.bit_count {
		return -1
	}
	slot := (k >> (16 - s)) - int(h.first_code[s]) + int(h.first_symbol[s])
	if slot < 0 || slot >= inflate_symbols || int(h.size[slot]) != s {
		return -1
	}
	d.bits >>= u32(s)
	d.bit_count -= u32(s)
	return int(h.value[slot])
}

fn (mut d Inflater) codes() bool {
	for {
		symbol := d.decode(mut d.literal)
		if symbol < 0 {
			return false
		}
		if symbol < 256 {
			if d.output_at >= d.output_size {
				return false
			}
			unsafe {
				d.output[d.output_at] = u8(symbol)
			}
			d.output_at++
			continue
		}
		if symbol == 256 {
			return !d.past_end
		}
		index := symbol - 257
		if index >= 29 {
			return false
		}
		mut length := u64(inflate_length_base[index])
		if inflate_length_extra[index] != 0 {
			length += u64(d.take(u32(inflate_length_extra[index])))
		}
		code := d.decode(mut d.distance)
		if code < 0 || code >= 30 {
			return false
		}
		mut distance := u64(inflate_distance_base[code])
		if inflate_distance_extra[code] != 0 {
			distance += u64(d.take(u32(inflate_distance_extra[code])))
		}
		if d.past_end || distance > d.output_at || d.output_at + length > d.output_size {
			return false
		}
		// The whole image is the window: copy from earlier output directly,
		// byte by byte where the copy overlaps what it writes.
		unsafe {
			mut to := &u8(u64(d.output) + d.output_at)
			from := &u8(u64(d.output) + d.output_at - distance)
			if distance >= length {
				C.memcpy(to, from, usize(length))
			} else {
				for i := u64(0); i < length; i++ {
					to[i] = from[i]
				}
			}
		}
		d.output_at += length
	}
	return false
}

fn (mut d Inflater) crc32(data &u8, size u64) u32 {
	if !d.crc_ready {
		for i in 0 .. 256 {
			mut c := u32(i)
			for _ in 0 .. 8 {
				c = if c & 1 != 0 { 0xedb88320 ^ (c >> 1) } else { c >> 1 }
			}
			d.crc_table[i] = c
		}
		d.crc_ready = true
	}
	mut crc := u32(0xffffffff)
	for i := u64(0); i < size; i++ {
		crc = d.crc_table[(crc ^ u32(unsafe { data[i] })) & 0xff] ^ (crc >> 8)
	}
	return crc ^ 0xffffffff
}

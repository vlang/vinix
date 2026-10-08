// SPDX-License-Identifier: GPL-2.0-or-later
module pager

// Bounded LZ block: literal tokens contain 1..128 bytes; match tokens contain
// a 3..130 byte copy and a little-endian distance. No allocation or slicing.
// The caller accepts a block only when it fits a small slab object.
pub fn compress(input &u8, length int, output &u8, capacity int) int {
	if length <= 0 || length > 16384 || capacity <= 0 { return 0 }
	mut positions := [1024]u16{}
	mut at := 0
	mut literal := 0
	mut written := 0
	for at + 3 < length {
		word := unsafe {
			u32(input[at]) | u32(input[at + 1]) << 8 |
				u32(input[at + 2]) << 16 | u32(input[at + 3]) << 24
		}
		index := int((word * u32(2654435761)) >> 22)
		previous := int(positions[index]) - 1
		positions[index] = u16(at + 1)
		mut matched := 0
		if previous >= 0 && previous < at {
			for matched < 130 && at + matched < length
				&& unsafe { input[previous + matched] == input[at + matched] } {
				matched++
			}
		}
		if matched < 4 {
			at++
			continue
		}
		written = emit_literals(input, literal, at, output, written, capacity)
		if written < 0 || written + 3 > capacity { return 0 }
		distance := at - previous
		unsafe {
			output[written] = u8(0x80 | (matched - 3))
			output[written + 1] = u8(distance)
			output[written + 2] = u8(distance >> 8)
		}
		written += 3
		at += matched
		literal = at
	}
	written = emit_literals(input, literal, length, output, written, capacity)
	return if written < 0 { 0 } else { written }
}

fn emit_literals(input &u8, begin int, end int, output &u8, initial int, capacity int) int {
	mut at := begin
	mut written := initial
	for at < end {
		count := if end - at > 128 { 128 } else { end - at }
		if written + count + 1 > capacity { return -1 }
		unsafe {
			output[written] = u8(count - 1)
			C.memcpy(&output[written + 1], &input[at], usize(count))
		}
		written += count + 1
		at += count
	}
	return written
}

pub fn decompress(input &u8, length int, output &u8, expected int) bool {
	mut at := 0
	mut written := 0
	for at < length {
		token := unsafe { input[at] }
		at++
		if token & 0x80 == 0 {
			count := int(token) + 1
			if count > length - at || count > expected - written { return false }
			unsafe { C.memcpy(&output[written], &input[at], usize(count)) }
			at += count
			written += count
		} else {
			count := int(token & 0x7f) + 3
			if length - at < 2 || count > expected - written { return false }
			distance := unsafe { int(input[at]) | int(input[at + 1]) << 8 }
			at += 2
			if distance == 0 || distance > written { return false }
			// Forward copying deliberately permits overlapping matches.
			for _ in 0 .. count {
				unsafe { output[written] = output[written - distance] }
				written++
			}
		}
	}
	return written == expected
}

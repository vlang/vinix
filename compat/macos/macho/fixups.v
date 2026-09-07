// SPDX-License-Identifier: GPL-2.0-or-later
module macho

pub enum FixupKind {
	rebase
	bind
}

pub struct Fixup {
pub:
	kind          FixupKind
	segment_index int
	offset        u64
	symbol        string
	addend        i64
}

const pointer_size = u64(8)
const opcode_mask = u8(0xf0)
const immediate_mask = u8(0x0f)

struct OpcodeReader {
	data []u8
mut:
	index int
}

fn (mut reader OpcodeReader) byte() !u8 {
	if reader.index >= reader.data.len {
		return error('truncated dyld opcode stream')
	}
	value := reader.data[reader.index]
	reader.index++
	return value
}

fn (mut reader OpcodeReader) uleb() !u64 {
	mut value := u64(0)
	mut shift := 0
	for count := 0; count < 10; count++ {
		byte := reader.byte()!
		payload := u64(byte & 0x7f)
		if shift == 63 && payload > 1 {
			return error('overflowing dyld ULEB128')
		}
		value |= payload << shift
		if byte & 0x80 == 0 {
			return value
		}
		shift += 7
	}
	return error('overflowing dyld ULEB128')
}

fn (mut reader OpcodeReader) sleb() !i64 {
	mut value := u64(0)
	mut shift := 0
	mut byte := u8(0)
	for count := 0; count < 10; count++ {
		byte = reader.byte()!
		payload := u64(byte & 0x7f)
		if shift == 63 && payload != 0 && payload != 1 {
			return error('overflowing dyld SLEB128')
		}
		value |= payload << shift
		shift += 7
		if byte & 0x80 == 0 {
			if shift < 64 && byte & 0x40 != 0 {
				value |= ~u64(0) << shift
			}
			return i64(value)
		}
	}
	return error('overflowing dyld SLEB128')
}

fn (mut reader OpcodeReader) string() !string {
	start := reader.index
	for reader.index < reader.data.len && reader.data[reader.index] != 0 {
		reader.index++
	}
	if reader.index >= reader.data.len {
		return error('unterminated dyld symbol')
	}
	value := reader.data[start..reader.index].bytestr()
	reader.index++
	return value
}

fn advance_offset(offset u64, amount u64) !u64 {
	// ld64 also uses a two's-complement ULEB value to move between adjacent
	// bind slots in descending address order (for example UINT64_MAX-15 means
	// minus 16). dyld performs wrapping pointer arithmetic here.
	if amount & (u64(1) << 63) != 0 {
		magnitude := (~amount) + 1
		if magnitude > offset {
			return error('underflowing dyld fixup offset')
		}
		return offset - magnitude
	}
	if amount > ~u64(0) - offset {
		return error('overflowing dyld fixup offset')
	}
	return offset + amount
}

fn validate_segment(index int, count int) ! {
	if index < 0 || index >= count {
		return error('dyld fixup names an invalid segment')
	}
}

pub fn decode_rebases(stream []u8, segment_count int) ![]Fixup {
	if stream.len == 0 {
		return []Fixup{}
	}
	mut reader := OpcodeReader{ data: stream }
	mut result := []Fixup{}
	mut segment := -1
	mut offset := u64(0)
	mut pointer_rebase := false
	for reader.index < stream.len {
		instruction := reader.byte()!
		opcode := instruction & opcode_mask
		immediate := instruction & immediate_mask
		match opcode {
			0x00 {
				return result
			}
			0x10 {
				if immediate != 1 {
					return error('unsupported non-pointer Mach-O rebase')
				}
				pointer_rebase = true
			}
			0x20 {
				segment = int(immediate)
				validate_segment(segment, segment_count)!
				offset = reader.uleb()!
			}
			0x30 {
				offset = advance_offset(offset, reader.uleb()!)!
			}
			0x40 {
				offset = advance_offset(offset, u64(immediate) * pointer_size)!
			}
			0x50 {
				offset = append_rebases(mut result, segment, offset, u64(immediate), 0, pointer_rebase)!
			}
			0x60 {
				count := reader.uleb()!
				offset = append_rebases(mut result, segment, offset, count, 0, pointer_rebase)!
			}
			0x70 {
				skip := reader.uleb()!
				offset = append_rebases(mut result, segment, offset, 1, skip, pointer_rebase)!
			}
			0x80 {
				count := reader.uleb()!
				skip := reader.uleb()!
				offset = append_rebases(mut result, segment, offset, count, skip, pointer_rebase)!
			}
			else {
				return error('unsupported Mach-O rebase opcode 0x${opcode:02x}')
			}
		}
	}
	return error('unterminated Mach-O rebase stream')
}

fn append_rebases(mut out []Fixup, segment int, start_offset u64, count u64, skip u64, pointer_rebase bool) !u64 {
	validate_segment(segment, 256)!
	if !pointer_rebase {
		return error('Mach-O rebase has no pointer type')
	}
	if count > 1_000_000 {
		return error('unreasonable Mach-O rebase count')
	}
	mut offset := start_offset
	for _ in u64(0) .. count {
		out << Fixup{ kind: .rebase, segment_index: segment, offset: offset }
		offset = advance_offset(offset, pointer_size + skip)!
	}
	return offset
}

// lazy controls the meaning of DONE: lazy-binding streams contain one DONE
// per symbol, whereas a normal bind stream ends at its first DONE.
pub fn decode_binds(stream []u8, segment_count int, lazy bool) ![]Fixup {
	if stream.len == 0 {
		return []Fixup{}
	}
	mut reader := OpcodeReader{ data: stream }
	mut result := []Fixup{}
	mut segment := -1
	mut offset := u64(0)
	mut symbol := ''
	mut addend := i64(0)
	// dyld initializes bind type to BIND_TYPE_POINTER; lazy streams commonly
	// omit an explicit SET_TYPE opcode for each one-symbol program.
	mut pointer_bind := true
	for reader.index < stream.len {
		instruction := reader.byte()!
		opcode := instruction & opcode_mask
		immediate := instruction & immediate_mask
		match opcode {
			0x00 {
				if !lazy {
					return result
				}
				segment = -1
				offset = 0
				symbol = ''
				addend = 0
				pointer_bind = true
			}
			0x10, 0x30 {} // Dylib ordinal; one-image Vinix runtime resolves by name.
			0x20 { reader.uleb()! }
			0x40 {
				symbol = reader.string()!
			}
			0x50 {
				if immediate != 1 {
					return error('unsupported non-pointer Mach-O bind')
				}
				pointer_bind = true
			}
			0x60 {
				addend = reader.sleb()!
			}
			0x70 {
				segment = int(immediate)
				validate_segment(segment, segment_count)!
				offset = reader.uleb()!
			}
			0x80 {
				offset = advance_offset(offset, reader.uleb()!)!
			}
			0x90 {
				offset = append_bind(mut result, segment, offset, symbol, addend, 0, pointer_bind)!
			}
			0xa0 {
				skip := reader.uleb()!
				offset = append_bind(mut result, segment, offset, symbol, addend, skip, pointer_bind)!
			}
			0xb0 {
				skip := u64(immediate) * pointer_size
				offset = append_bind(mut result, segment, offset, symbol, addend, skip, pointer_bind)!
			}
			0xc0 {
				count := reader.uleb()!
				skip := reader.uleb()!
				if count > 1_000_000 {
					return error('unreasonable Mach-O bind count')
				}
				for _ in u64(0) .. count {
					offset = append_bind(mut result, segment, offset, symbol, addend, skip, pointer_bind)!
				}
			}
			else {
				return error('unsupported Mach-O bind opcode 0x${opcode:02x}')
			}
		}
	}
	if lazy {
		return result
	}
	return error('unterminated Mach-O bind stream')
}

fn append_bind(mut out []Fixup, segment int, offset u64, symbol string, addend i64, skip u64, pointer_bind bool) !u64 {
	validate_segment(segment, 256)!
	if !pointer_bind || symbol == '' {
		return error('incomplete Mach-O bind state')
	}
	out << Fixup{
		kind: .bind
		segment_index: segment
		offset: offset
		symbol: symbol
		addend: addend
	}
	return advance_offset(offset, pointer_size + skip)!
}

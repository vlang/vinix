// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn be32(bytes []u8, at int) !u32 {
	if at < 0 || at > bytes.len - 4 { return error('Truncated big-endian word') }
	return u32(bytes[at]) << 24 | u32(bytes[at + 1]) << 16 | u32(bytes[at + 2]) << 8 | bytes[at + 3]
}

fn validate_tree(bytes []u8) !int {
	if bytes.len < 88 || be32(bytes, 0)! != 0xd00dfeed || be32(bytes, 4)! != u32(bytes.len)
		|| be32(bytes, 20)! != 17 || be32(bytes, 24)! > 17 {
		return error('Invalid FDT header')
	}
	structure := int(be32(bytes, 8)!)
	strings := int(be32(bytes, 12)!)
	string_size := int(be32(bytes, 32)!)
	structure_size := int(be32(bytes, 36)!)
	if structure < 88 || structure % 4 != 0 || structure > bytes.len || strings < structure
		|| strings > bytes.len || structure_size < 4 || structure_size > strings - structure
		|| string_size < 0 || string_size > bytes.len - strings {
		return error('Invalid FDT bounds')
	}
	mut pos := structure
	end := structure + structure_size
	mut depth := 0
	mut nodes := 0
	mut ended := false
	for pos < end {
		token := be32(bytes, pos)!
		pos += 4
		match token {
			1 {
				if ended || depth >= 64 || pos >= end { return error('Invalid FDT nesting') }
				if nodes == 0 && bytes[pos] != 0 { return error('FDT root must be unnamed') }
				for pos < end && bytes[pos] != 0 { pos++ }
				if pos == end { return error('Unterminated FDT node name') }
				pos = (pos + 4) & ~3
				depth++
				nodes++
			}
			2 {
				if depth <= 0 { return error('Unbalanced FDT end node') }
				depth--
				if depth == 0 { ended = true }
			}
			3 {
				if depth == 0 || pos > end - 8 { return error('FDT property outside node') }
				length := int(be32(bytes, pos)!)
				name := int(be32(bytes, pos + 4)!)
				pos += 8
				if length < 0 || length > end - pos || name < 0 || name >= string_size {
					return error('Invalid FDT property bounds')
				}
				mut name_end := strings + name
				for name_end < strings + string_size && bytes[name_end] != 0 { name_end++ }
				if name_end == strings + string_size {
					return error('Unterminated FDT property name')
				}
				pos = (pos + length + 3) & ~3
			}
			4 {}
			9 {
				if depth != 0 || !ended || pos != end { return error('Premature FDT end') }
				return nodes
			}
			else { return error('Unknown FDT token ${token}') }
		}
	}
	return error('Missing FDT end')
}

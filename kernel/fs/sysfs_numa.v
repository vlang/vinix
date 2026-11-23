// SPDX-License-Identifier: GPL-2.0-or-later
module fs

// Match Linux's kstrtou8 with base detection, a leading plus and an
// optional final newline. An empty string resets the weight as well.
fn parse_interleave_weight(data &u8, count u64) ?u8 {
	unsafe {
		mut length := u64(0)
		for length < count && data[length] != 0 { length++ }
		if length > 0 && data[length - 1] == `\n` { length-- }
		if length == 0 { return u8(0) }

		mut pos := if data[0] == `+` { u64(1) } else { u64(0) }
		if pos == length { return none }
		mut base := u32(10)
		if data[pos] == `0` {
			base = 8
			if pos + 1 < length && (data[pos + 1] | 0x20) == `x` {
				base = 16
				pos += 2
				if pos == length { return none }
			}
		}

		mut value := u32(0)
		for pos < length {
			c := data[pos]
			lower := c | 0x20
			digit := if c >= `0` && c <= `9` { u32(c - `0`) }
				else if lower >= `a` && lower <= `f` { u32(lower - `a`) + 10 }
				else { return none }
			if digit >= base { return none }
			value = value * base + digit
			if value > 255 { return none }
			pos++
		}
		return u8(value)
	}
}

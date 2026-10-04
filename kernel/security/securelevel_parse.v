// SPDX-License-Identifier: GPL-2.0-or-later
module security

pub const securelevel_cmdline_max = 65536
pub const securelevel_write_max = 64

fn securelevel_space(value u8) bool {
	return value == ` ` || value == `\t` || value == `\r` || value == `\n`
}

// Strict supported decimal values, with optional surrounding whitespace.
// Borrowed strings and indices avoid allocations on repeated policy writes.
pub fn parse_securelevel_value(text string) (int, bool) {
	mut first := 0
	mut last := text.len
	for first < last && securelevel_space(text[first]) { first++ }
	for last > first && securelevel_space(text[last - 1]) { last-- }
	if last - first == 1 && text[first] >= `0` && text[first] <= `2` {
		return int(text[first] - `0`), true
	}
	if last - first == 2 && text[first] == `-` && text[first + 1] == `1` {
		return -1, true
	}
	return 0, false
}

// -2 means no policy was specified. A substring in another option or its
// value does not select policy. Reject duplicate options, even equal ones,
// so boot configuration has one unambiguous authority.
pub fn parse_securelevel_boot(text string) (int, bool) {
	if text.len >= securelevel_cmdline_max { return 0, false }
	prefix := 'vinix.securelevel='
	mut level := -2
	mut first := 0
	for first < text.len {
		for first < text.len && securelevel_space(text[first]) { first++ }
		mut last := first
		for last < text.len && !securelevel_space(text[last]) { last++ }
		if last - first == prefix.len - 1 {
			mut bare_key := true
			for i in 0 .. prefix.len - 1 {
				if text[first + i] != prefix[i] {
					bare_key = false
					break
				}
			}
			if bare_key { return 0, false }
		}
		if last - first >= prefix.len {
			mut matches := true
			for i in 0 .. prefix.len {
				if text[first + i] != prefix[i] {
					matches = false
					break
				}
			}
			if matches {
				if level != -2 { return 0, false }
				value := unsafe { tos(text.str + first + prefix.len, last - first - prefix.len) }
				parsed, valid := parse_securelevel_value(value)
				if !valid { return 0, false }
				level = parsed
			}
		}
		first = last
	}
	return level, true
}

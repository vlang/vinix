// SPDX-License-Identifier: GPL-2.0-or-later
module ninep

pub struct Options {
pub mut:
	msize u32 = max_msize
}

// Bounded, allocation-free option parsing. Reject unknown options, empty
// tokens and duplicate transport/dialect/cache/msize settings. Policy flags
// are interpreted by mount.v, not silently turned into backend features.
pub fn parse_options(text string, out &Options) bool {
	if text.len > 4096 { return false }
	mut result := Options{}
	mut seen := u8(0)
	mut begin := 0
	for begin < text.len {
		mut end := begin
		for end < text.len && text[end] != `,` { end++ }
		if end == begin { return false }
		part := unsafe { text.str + begin }
		n := end - begin
		mut bit := u8(0)
		if matches(part, n, 'trans=virtio') {
			bit = 1
		} else if matches(part, n, 'version=9p2000.L') {
			bit = 2
		} else if matches(part, n, 'cache=none') {
			bit = 4
		} else if n > 6 && prefix(part, n, 'msize=') {
			bit = 8
			mut value := u32(0)
			for i in 6 .. n {
				c := unsafe { part[i] }
				if c < `0` || c > `9` || value > (max_msize - u32(c - `0`)) / 10 { return false }
				value = value * 10 + u32(c - `0`)
			}
			if value < min_msize || value > max_msize { return false }
			result.msize = value
		} else if !matches(part, n, 'ro') && !matches(part, n, 'rw')
			&& !matches(part, n, 'nosuid') && !matches(part, n, 'nodev')
			&& !matches(part, n, 'noexec') && !matches(part, n, 'relatime')
			&& !matches(part, n, 'noatime') && !matches(part, n, 'nodiratime')
			&& !matches(part, n, 'strictatime') && !matches(part, n, 'defaults') {
			return false
		}
		if bit != 0 && seen & bit != 0 { return false }
		seen |= bit
		begin = end + 1
		if end < text.len && begin == text.len { return false }
	}
	unsafe { *out = result }
	return true
}

fn matches(data &u8, length int, expected string) bool {
	return length == expected.len && prefix(data, length, expected)
}

fn prefix(data &u8, length int, expected string) bool {
	if length < expected.len { return false }
	for i in 0 .. expected.len { if unsafe { data[i] } != expected[i] { return false } }
	return true
}

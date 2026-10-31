// SPDX-License-Identifier: GPL-2.0-or-later
module smb2

pub struct Options {
pub mut:
	domain   string
	user     string
	password string
	guest    bool
	ro       bool
}

// Borrow substrings: mount owns no password copy. No split() allocations.
pub fn parse_options(text string, o &Options) bool {
	if text.len > 2048 { return false }
	unsafe {
		*o = Options{}
	}
	mut at := 0
	mut seen := u32(0)
	for at < text.len {
		start := at
		for at < text.len && text[at] != `,` {
			at++
		}
		end := at
		at++
		if start == end { return false }
		mut eq := start
		for eq < end && text[eq] != `=` {
			eq++
		}
		key := unsafe { tos(text.str + start, eq - start) }
		value := if eq < end { unsafe { tos(text.str + eq + 1, end - eq - 1) } } else { '' }
		mut bit := u32(0)
		match key {
			'domain' {
				bit = 1
				if value.len > 128 { return false }
				unsafe {
					o.domain = value
				}
			}
			'user' {
				bit = 2
				if value.len > 128 { return false }
				unsafe {
					o.user = value
				}
			}
			'password' {
				bit = 4
				if value.len > 256 { return false }
				unsafe {
					o.password = value
				}
			}
			'guest' {
				bit = 8
				if eq != end { return false }
				unsafe {
					o.guest = true
				}
			}
			'ro' {
				bit = 16
				if eq != end { return false }
				unsafe {
					o.ro = true
				}
			}
			'rw' {
				bit = 16
				if eq != end { return false }
			}
			else {
				return false
			}
		}

		if seen & bit != 0 { return false }
		seen |= bit
	}
	return o.guest || o.user.len > 0
}

// Numeric IPv4 only; direct TCP, never NetBIOS name service or port 139.
pub fn parse_source(source string, address &u32, share &string, host &string) bool {
	if source.len < 7 || source.len > 384 || !source.starts_with('//') { return false }
	mut slash := 2
	for slash < source.len && source[slash] != `/` {
		slash++
	}
	if slash == source.len || slash == source.len - 1 { return false }
	mut at := 2
	mut ip := u32(0)
	for part in 0 .. 4 {
		mut number := 0
		mut digits := 0
		for at < slash && source[at] >= `0` && source[at] <= `9` {
			number = number * 10 + int(source[at] - `0`)
			at++
			digits++
			if digits > 3 || number > 255 { return false }
		}
		if digits == 0 { return false }
		ip |= u32(number) << u32(part * 8)
		if part < 3 {
			if at >= slash || source[at] != `.` { return false }
			at++
		}
	}
	if at != slash { return false }
	for i in slash + 1 .. source.len {
		if source[i] == `/` || source[i] == `\\` || source[i] == 0 { return false }
	}
	unsafe {
		*address = ip
		*host = tos(source.str + 2, slash - 2)
		*share = tos(source.str + slash + 1, source.len - slash - 1)
	}
	return true
}

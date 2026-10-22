// SPDX-License-Identifier: GPL-2.0-or-later
module nfs

pub struct Options {
pub mut:
	ro bool
	soft bool
	rsize int = io_max
	wsize int = io_max
}

fn decimal(s string, limit u32) ?u32 {
	if s.len == 0 { return none }
	mut n := u32(0)
	for ch in s {
		if ch < `0` || ch > `9` { return none }
		d := u32(ch - `0`)
		if n > limit / 10 || (n == limit / 10 && d > limit % 10) { return none }
		n = n * 10 + d
	}
	return n
}

pub fn parse_options(s string, out &Options) bool {
	if s.len > 1024 || (s.len > 0 && s[s.len-1] == `,`) { return false }
	unsafe { *out = Options{} }
	mut at := 0
	mut seen := u32(0)
	for at < s.len {
		start := at
		for at < s.len && s[at] != `,` { at++ }
		end := at
		at++
		if start == end { return false }
		mut eq := start
		for eq < end && s[eq] != `=` { eq++ }
		key := unsafe { tos(s.str + start, eq-start) }
		v := unsafe { tos(s.str + if eq < end { eq+1 } else { end }, if eq < end { end-eq-1 } else { 0 }) }
		mut bit := u32(0)
		match key {
			'ro', 'rw' { bit = 1; if eq != end { return false }; unsafe { out.ro = key == 'ro' } }
			'soft', 'hard' { bit = 2; if eq != end { return false }; unsafe { out.soft = key == 'soft' } }
			'rsize', 'wsize' {
				bit = if key == 'rsize' { u32(4) } else { u32(8) }
				n := decimal(v, io_max) or { return false }
				if n < 512 { return false }
				unsafe { if bit == 4 { out.rsize = int(n) } else { out.wsize = int(n) } }
			}
			'vers', 'nfsvers' { bit = 16; if v != '3' { return false } }
			'proto' { bit = 32; if v != 'tcp' { return false } }
			'sec' { bit = 64; if v != 'sys' { return false } }
			else { return false }
		}
		if seen & bit != 0 { return false }
		seen |= bit
	}
	return true
}

// IPv4 numeric host:/absolute/export. Export is borrowed during mount only.
pub fn parse_source(s string, address &u32, path &string) bool {
	if s.len < 9 || s.len > 1040 { return false }
	mut at := 0
	mut ip := u32(0)
	for part in 0 .. 4 {
		start := at
		for at < s.len && s[at] >= `0` && s[at] <= `9` { at++ }
		if at-start > 3 { return false }
		n := decimal(unsafe { tos(s.str + start, at-start) }, 255) or { return false }
		ip |= n << u32(part*8)
		if at >= s.len || s[at] != if part == 3 { `:` } else { `.` } { return false }
		at++
	}
	if at >= s.len || s[at] != `/` || s.len-at > 1024 { return false }
	for i in at .. s.len { if s[i] == 0 { return false } }
	unsafe { *address = ip; *path = tos(s.str + at, s.len-at) }
	return true
}

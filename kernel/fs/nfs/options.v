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

pub const hosts_max = 16384
pub const host_max = 253
pub const hosts_line_max = 1024

// Borrowed strings; no allocation or DNS. Numeric-looking invalid IPv4 must
// not become a hostname that a hosts entry could accidentally authorize.
pub fn parse_host_source(s string, host &string, path &string) bool {
	if s.len < 4 || s.len > host_max + 1 + 1024 { return false }
	mut at := 0
	for at < s.len && s[at] != `:` { at++ }
	if at == 0 || at > host_max || at + 1 >= s.len || s[at+1] != `/` || s.len-at-1 > 1024 { return false }
	h := unsafe { tos(s.str, at) }
	if !host_name(h) { return false }
	for i in at+1 .. s.len { if s[i] == 0 || s[i] < 32 || s[i] == 127 { return false } }
	unsafe { *host = h; *path = tos(s.str + at+1, s.len-at-1) }
	return true
}

fn host_name(h string) bool {
	if h.len == 0 || h.len > host_max { return false }
	mut numeric := true
	mut label := 0
	for i, ch in h {
		if ch == `.` {
			if label == 0 || h[i-1] == `-` { return false }
			label = 0
			continue
		}
		if !((ch >= `a` && ch <= `z`) || (ch >= `A` && ch <= `Z`) || (ch >= `0` && ch <= `9`) || ch == `-`) { return false }
		if ch < `0` || ch > `9` { numeric = false }
		if label == 0 && ch == `-` { return false }
		label++
		if label > 63 { return false }
	}
	if label == 0 || h[h.len-1] == `-` { return false }
	if numeric { mut ip := u32(0); return parse_ipv4(h, unsafe { &ip }) }
	return true
}

pub fn parse_ipv4(s string, address &u32) bool {
	if s.len < 7 || s.len > 15 { return false }
	mut at := 0
	mut ip := u32(0)
	for part in 0 .. 4 {
		start := at
		for at < s.len && s[at] >= `0` && s[at] <= `9` { at++ }
		if at-start > 3 { return false }
		n := decimal(unsafe { tos(s.str + start, at-start) }, 255) or { return false }
		ip |= n << u32(part*8)
		if part < 3 {
			if at >= s.len || s[at] != `.` { return false }
			at++
		} else if at != s.len { return false }
	}
	unsafe { *address = ip }
	return true
}

// Compatibility numeric-only entry point for existing wire clients.
pub fn parse_source(s string, address &u32, path &string) bool {
	mut host := ''; mut export := ''
	if !parse_host_source(s, unsafe { &host }, unsafe { &export }) || !parse_ipv4(host, address) { return false }
	unsafe { *path = export }
	return true
}

// Exact, case-sensitive hosts aliases. Oversized lines/tokens fail closed;
// IPv6 and malformed addresses never resolve an IPv4 endpoint. Entire input
// is validated before returning, including text after a matching line.
pub fn resolve_hosts(text string, host string, address &u32) bool {
	if text.len > hosts_max || !host_name(host) { return false }
	mut at := 0
	mut found := false
	mut result := u32(0)
	for at < text.len {
		start := at
		for at < text.len && text[at] != `\n` { if text[at] == 0 { return false }; at++ }
		end := at; at++
		if end-start > hosts_line_max { return false }
		mut pos := start
		mut token := 0
		mut valid_ip := false
		mut ip := u32(0)
		for pos < end {
			for pos < end && (text[pos] == ` ` || text[pos] == `\t` || text[pos] == `\r`) { pos++ }
			if pos == end || text[pos] == `#` { break }
			ts := pos
			for pos < end && text[pos] != ` ` && text[pos] != `\t` && text[pos] != `\r` && text[pos] != `#` { pos++ }
			if pos-ts > host_max { return false }
			t := unsafe { tos(text.str + ts, pos-ts) }
			if token == 0 { valid_ip = parse_ipv4(t, unsafe { &ip }) }
			else if valid_ip && t == host {
				if found && result != ip { return false }
				found = true; result = ip
			}
			token++
		}
	}
	if !found { return false }
	unsafe { *address = result }
	return true
}

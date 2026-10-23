// SPDX-License-Identifier: GPL-2.0-or-later
module pkgprotocol

fn repository_hex(byte u8) bool {
	return (byte >= `0` && byte <= `9`) || (byte >= `a` && byte <= `f`)
		|| (byte >= `A` && byte <= `F`)
}

// valid_repository_url borrows its input without allocating or normalizing it.
// It admits bounded HTTPS base URLs without credentials, query or fragment,
// and absolute, literal file:// paths without empty, dot or parent components.
// HTTPS escaping and authority delimiters are checked here; address resolution,
// certificate verification and publisher authentication remain service duties.
// In particular, file paths are never percent-decoded or treated as shell text.
// HTTPS URLs have a 4096-byte limit; the literal file suffix keeps the service's
// existing 1024-byte relative-path limit (after the initial file:/// prefix).
pub fn valid_repository_url(url string) bool {
	if !printable(url, 4096) || url.contains('?') || url.contains('#') { return false }
	if url.starts_with('file:///') {
		if url.len <= 8 || url.len - 8 > 1024 { return false }
		mut start := 8
		for i in 8 .. url.len + 1 {
			if i < url.len && url[i] == `\\` { return false }
			if i == url.len || url[i] == `/` {
				length := i - start
				if length == 0 || (length == 1 && url[start] == `.`)
					|| (length == 2 && url[start] == `.` && url[start + 1] == `.`) {
					return false
				}
				start = i + 1
			}
		}
		return true
	}
	if !url.starts_with('https://') || url.len <= 8 { return false }
	mut end := url.len
	mut i := 8
	for i < url.len {
		byte := url[i]
		if byte <= 32 || byte == 127 || byte == `\\` { return false }
		if byte == `/` && end == url.len { end = i }
		if byte == `%` {
			if i + 2 >= url.len || !repository_hex(url[i + 1]) || !repository_hex(url[i + 2]) {
				return false
			}
			i += 2
		}
		i++
	}
	if end == 8 { return false }
	mut port := end
	if url[8] == `[` {
		mut close := 9
		for close < end && url[close] != `]` {
			if url[close] == `[` || url[close] == `@` { return false }
			close++
		}
		if close == 9 || close == end { return false }
		if close + 1 < end {
			if url[close + 1] != `:` { return false }
			port = close + 2
		}
	} else {
		for n in 8 .. end {
			if url[n] == `@` || url[n] == `[` || url[n] == `]` { return false }
			if url[n] == `:` { port = n + 1; break }
		}
		if port == 9 { return false } // Empty host before a port.
	}
	if port < end {
		mut number := 0
		for n in port .. end {
			if url[n] < `0` || url[n] > `9` { return false }
			number = number * 10 + int(url[n] - `0`)
			if number > 65535 { return false }
		}
	} else if url[end - 1] == `:` {
		return false
	}
	return true
}

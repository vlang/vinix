// SPDX-License-Identifier: GPL-2.0-or-later
module pkgprotocol

// Bare association names use RFC 6838 section 4.2's restricted names, including
// vendor facets and structured suffixes. Preserve the SDK's 128-byte total
// limit and literal case. Registration does not establish IANA registration.
pub fn valid_mime_association(value string) bool {
	if value.len < 3 || value.len > 128 { return false }
	mut slash := false
	mut first := true
	for byte in value {
		if byte == `/` {
			if slash || first { return false }
			slash = true
			first = true
			continue
		}
		alphanumeric := (byte >= `a` && byte <= `z`) || (byte >= `A` && byte <= `Z`)
			|| (byte >= `0` && byte <= `9`)
		if !alphanumeric && (first || byte !in [u8(`!`), `#`, `$`, `&`, `-`, `^`, `_`, `.`, `+`]!) {
			return false
		}
		first = false
	}
	return slash && !first
}

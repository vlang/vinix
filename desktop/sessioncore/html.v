// SPDX-License-Identifier: GPL-2.0-or-later
module sessioncore

// The rich record remains intact. Plain text clients receive readable text;
// tags and control bytes cannot become application keyboard commands.
pub fn html_text(html string) string {
	mut out := []u8{cap: html.len}
	mut in_tag := false
	for byte in html {
		if byte == `<` {
			in_tag = true
			continue
		}
		if byte == `>` && in_tag {
			in_tag = false
			continue
		}
		if !in_tag && (byte >= 32 || byte in [u8(9), 10, 13]) { out << byte }
	}
	raw := out.bytestr()
	unsafe { out.free() }
	mut decoded := raw
	for pair in [['&lt;', '<']!, ['&gt;', '>']!, ['&quot;', '"']!, ['&#39;', "'"]!, ['&nbsp;',
		' ']!, ['&amp;', '&']!]! {
		next := decoded.replace(pair[0], pair[1])
		unsafe { decoded.free() }
		decoded = next
	}
	return decoded
}

// SPDX-License-Identifier: GPL-2.0-or-later
module pkgprotocol

fn test_metadata_key_owned_unicode_escapes_bounds_and_trailing_refusal() {
	for text, expected in {'"firmware"': 'firmware', '"firm\\u0077are"': 'firmware',
		' "unicode-\\ud83d\\ude80" \n': 'unicode-🚀', '"quotes-\\\"-slash-\\\\-\\/"': 'quotes-"-slash-\\-/',
		'"\\b\\f\\n\\r\\t"': '\b\f\n\r\t', '""': ''} {
		key := decode_metadata_key(text)!
		assert key == expected
		unsafe { key.free() }
	}
	key := decode_metadata_key('"' + 'a'.repeat(32) + '"')!
	assert key.len == 32
	unsafe { key.free() }
	for invalid in ['null', '"unterminated', '"key":', '"key"{}', '"bad\\x20"',
		'"\\ud800"', '"\\udc00"', '"\\ud800\\u0061"', '"raw\x01"', '"\xff"',
		'"' + 'a'.repeat(33) + '"', '"' + '\\u0061'.repeat(33) + '"'] {
		if value := decode_metadata_key(invalid) { unsafe { value.free() }; assert false } else {
			message := err.msg(); unsafe { message.free(); err.free() }
		}
	}
}

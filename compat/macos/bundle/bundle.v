// SPDX-License-Identifier: GPL-2.0-or-later
// Minimal, bounds-checked XML property-list support for macOS app bundles.
module bundle

fn decode_xml_text(text string) !string {
	mut index := 0
	for index < text.len {
		relative := text[index..].index_u8(`&`)
		if relative < 0 {
			break
		}
		index += relative
		mut known := false
		for entity in ['&amp;', '&lt;', '&gt;', '&quot;', '&apos;'] {
			if text[index..].starts_with(entity) {
				index += entity.len
				known = true
				break
			}
		}
		if !known {
			return error('unsupported XML entity in Info.plist')
		}
	}
	mut out := text.replace('&amp;', '&').replace('&lt;', '<').replace('&gt;', '>')
	out = out.replace('&quot;', '"').replace('&apos;', "'")
	return out
}

pub fn executable_name(data []u8) !string {
	if data.len == 0 || data.len > 64 * 1024 {
		return error('invalid Info.plist size')
	}
	text := data.bytestr()
	key := '<key>CFBundleExecutable</key>'
	key_start := text.index(key) or { return error('Info.plist has no CFBundleExecutable') }
	after_key := key_start + key.len
	relative_start := text[after_key..].index('<string>') or {
		return error('CFBundleExecutable is not a string')
	}
	value_start := after_key + relative_start + '<string>'.len
	relative_end := text[value_start..].index('</string>') or {
		return error('unterminated CFBundleExecutable')
	}
	name := decode_xml_text(text[value_start..value_start + relative_end].trim_space())!
	if name == '' || name == '.' || name == '..' || name.contains('/') || name.contains('\x00') {
		return error('unsafe CFBundleExecutable')
	}
	return name
}

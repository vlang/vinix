// SPDX-License-Identifier: GPL-2.0-or-later
module main

import encoding.utf8

// The public class has only an isa (8 bytes on ARM64). Keep its buffer and
// provenance in allocation metadata, including for caller-owned object bytes.
const mutable_string_limit = u64(16777216)

fn mutable_string_family(cls u64) bool {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return false }
		if info.name == 'NSMutableString' { return true }
		current = info.parent
		if current == 0 { return false }
	}
	panic('iOS: cyclic mutable string superclass chain')
}

fn mutable_string_require_class(cls u64) {
	if mutable_string_family(cls) && cls != ios_runtime.names['NSMutableString'] {
		panic('iOS: mutable string subclass construction is not implemented')
	}
}

fn mutable_string_state(object u64) &ObjHeader {
	header := obj_header(object)
	if !header.mutable_string_owned || header.native_size < 8 || header.destroying || header.destroyed {
		panic('iOS: mutable string requires live owned storage')
	}
	return header
}

fn mutable_string_types(name string, meta bool, selector string) ?string {
	if !meta && name in ['NSString', 'NSMutableString']! && selector == 'lastPathComponent' { return '@16@0:8' }
	if !meta && name in ['NSString', 'NSMutableString']! && selector == 'stringByAppendingPathComponent:' { return '@24@0:8@16' }
	if !meta && name in ['NSString', 'NSMutableString']! && selector == 'cStringUsingEncoding:' { return 'r*24@0:8Q16' }
	if !meta && name in ['NSString', 'NSMutableString']! && selector == 'precomposedStringWithCanonicalMapping' { return '@16@0:8' }
	if !meta && name in ['NSString', 'NSMutableString']! && selector == 'floatValue' { return 'f16@0:8' }
	if meta && name in ['NSString', 'NSMutableString']! && selector == 'stringWithCString:encoding:' {
		return '@32@0:8r*16Q24'
	}
	if name == 'NSString' && !meta {
		return match selector {
			'description' { '@16@0:8' }
			'mutableCopy' { '@16@0:8' }
			'copyWithZone:', 'mutableCopyWithZone:' { '@24@0:8^{_NSZone=}16' }
			'lengthOfBytesUsingEncoding:' { 'Q24@0:8Q16' }
			'isEqualToString:' { 'B24@0:8@16' }
			'stringByAppendingString:' { '@24@0:8@16' }
			'rangeOfCharacterFromSet:' { '{_NSRange=QQ}24@0:8@16' }
			else { return none }
		}
	}
	if name != 'NSMutableString' { return none }
	if meta {
		return match selector {
			'new', 'string' { '@16@0:8' }
			'stringWithCapacity:' { '@24@0:8Q16' }
			'stringWithString:' { '@24@0:8@16' }
			'stringWithUTF8String:' { '@24@0:8r*16' }
			else { return none }
		}
	}
	return match selector {
		'init', 'copy', 'mutableCopy', 'description' { '@16@0:8' }
		'copyWithZone:', 'mutableCopyWithZone:' { '@24@0:8^{_NSZone=}16' }
		'initWithCapacity:' { '@24@0:8Q16' }
		'initWithString:' { '@24@0:8@16' }
		'initWithUTF8String:' { '@24@0:8r*16' }
		'initWithBytes:length:encoding:' { '@40@0:8r^v16Q24Q32' }
		'setString:', 'appendString:' { 'v24@0:8@16' }
		'insertString:atIndex:' { 'v32@0:8@16Q24' }
		'deleteCharactersInRange:' { 'v32@0:8{_NSRange=QQ}16' }
		'replaceCharactersInRange:withString:' { 'v40@0:8{_NSRange=QQ}16@32' }
		'UTF8String' { 'r*16@0:8' }
		'length' { 'Q16@0:8' }
		'lengthOfBytesUsingEncoding:' { 'Q24@0:8Q16' }
		'isEqualToString:' { 'B24@0:8@16' }
		'stringByAppendingString:' { '@24@0:8@16' }
		else { return none }
	}
}

fn mutable_string_unsupported(selector string) bool {
	return selector.contains('Format') || selector.contains('NoCopy') || selector.contains('ContentsOf')
		|| selector in ['initWithCoder:', 'encodeWithCoder:', 'supportsSecureCoding',
		'replaceOccurrencesOfString:withString:options:range:', 'applyTransform:reverse:range:updatedRange:',
		'initWithCharacters:length:', 'initWithCString:encoding:', 'stringWithCharacters:length:']!
}

// All text borrows in this module stay under the recursive runtime lock and
// never cross application callbacks. NSString subclass methods are not guessed.
fn mutable_string_source(object u64) string {
	if object == 0 { panic('iOS: mutable string source must not be nil') }
	return cf_string_compare_text(object) or { panic('iOS: mutable string source requires a live UTF8 string') }
}

fn mutable_string_commit(mut header ObjHeader, text string) {
	if u64(text.len) > mutable_string_limit { panic('iOS: mutable string exceeds the supported size') }
	buffer := &char(C.malloc(usize(text.len + 1)))
	if buffer == unsafe { nil } { panic('iOS: cannot allocate mutable string buffer') }
	if text.len != 0 { unsafe { C.memcpy(buffer, text.str, usize(text.len)) } }
	unsafe { *(&u8(voidptr(u64(buffer) + u64(text.len)))) = 0 }
	old := header.text
	header.text = buffer
	header.text_length = text.len
	header.mutable_string_initialized = true
	unsafe { C.free(old) }
}

fn mutable_string_initialize(object u64, text string) {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut header := mutable_string_state(object)
	if header.mutable_string_initialized { panic('iOS: mutable string designated reinitialization is not implemented') }
	mutable_string_commit(mut header, text)
}

fn mutable_string_units(text string) u64 {
	mut count := u64(0)
	for byte in text { if byte & 0xc0 != 0x80 { count += if byte >= 0xf0 { u64(2) } else { u64(1) } } }
	return count
}

fn mutable_string_offset(text string, index u64) int {
	mut unit := u64(0)
	mut offset := 0
	for offset < text.len {
		if unit == index { return offset }
		first := text[offset]
		width := if first < 0x80 { 1 } else if first < 0xe0 { 2 } else if first < 0xf0 { 3 } else { 4 }
		unit += if width == 4 { u64(2) } else { u64(1) }
		if unit > index { panic('iOS: mutable string range splits a surrogate pair') }
		offset += width
	}
	if unit != index { panic('iOS: mutable string range is out of bounds') }
	return offset
}

fn mutable_string_replace(object u64, location u64, length u64, replacement string) {
	mut header := mutable_string_state(object)
	if !header.mutable_string_initialized { panic('iOS: mutable string mutation requires initialization') }
	text := mutable_string_source(object)
	units := mutable_string_units(text)
	if location > units || length > units - location { panic('iOS: mutable string range is out of bounds') }
	start := mutable_string_offset(text, location)
	end := mutable_string_offset(text, location + length)
	new_length := u64(text.len - (end - start)) + u64(replacement.len)
	if new_length > mutable_string_limit { panic('iOS: mutable string exceeds the supported size') }
	buffer := &char(C.malloc(usize(new_length + 1)))
	if buffer == unsafe { nil } { panic('iOS: cannot allocate mutable string buffer') }
	unsafe {
		if start != 0 { C.memcpy(buffer, text.str, usize(start)) }
		if replacement.len != 0 { C.memcpy(buffer + start, replacement.str, usize(replacement.len)) }
		if end != text.len { C.memcpy(buffer + start + replacement.len, text.str + end, usize(text.len - end)) }
		*(&u8(voidptr(u64(buffer) + new_length))) = 0
	}
	old := header.text
	header.text = buffer
	header.text_length = int(new_length)
	unsafe { C.free(old) }
}

fn mutable_string_snapshot(object u64, mutable_copy bool) u64 {
	C.ios_objc_initialize_lock()
	// Allocation can call application +initialize/.cxx_construct methods.
	// Stabilize the bytes and drop the lock before invoking either allocator.
	text := mutable_string_source(object).clone()
	C.ios_objc_initialize_unlock()
	defer { unsafe { text.free() } }
	if !mutable_copy { return owned_string(text) }
	result := objc_allocate(ios_runtime.names['NSMutableString'])
	if result == 0 { return 0 }
	mutable_string_initialize(result, text)
	return result
}

fn mutable_string_append_snapshot(object u64, other u64) u64 {
	C.ios_objc_initialize_lock()
	left := mutable_string_source(object)
	right := mutable_string_source(other)
	if u64(left.len) + u64(right.len) > mutable_string_limit { panic('iOS: string append exceeds the supported size') }
	joined := left + right
	C.ios_objc_initialize_unlock()
	defer { unsafe { joined.free() } }
	return objc_autorelease(owned_string(joined))
}

fn mutable_string_cstring_snapshot(address u64) u64 {
	if address == 0 { panic('iOS: string UTF8 input must not be nil') }
	C.ios_objc_initialize_lock()
	length := u64(C.strnlen(unsafe { &char(address) }, usize(mutable_string_limit + 1)))
	if length > mutable_string_limit { panic('iOS: string exceeds the supported size') }
	text := unsafe { tos(&u8(voidptr(address)), int(length)) }.clone()
	C.ios_objc_initialize_unlock()
	defer { unsafe { text.free() } }
	return objc_autorelease(owned_string(text))
}

fn mutable_string_byte_length(object u64, encoding u64) u64 {
	text := mutable_string_source(object)
	if encoding == 4 { return u64(text.len) }
	if encoding != 1 { panic('iOS: string byte length encoding is not implemented') }
	for byte in text { if byte >= 128 { return 0 } }
	return u64(text.len)
}

fn mutable_string_encoded_cstring(cls u64, address u64, encoding u64) u64 {
	mutable_string_require_class(cls)
	if address == 0 { panic('iOS: string CString input must not be nil') }
	if encoding !in [u64(1), 4]! { panic('iOS: string CString encoding is not implemented') }
	C.ios_objc_initialize_lock()
	length := u64(C.strnlen(unsafe { &char(address) }, usize(mutable_string_limit + 1)))
	if length > mutable_string_limit { panic('iOS: string exceeds the supported size') }
	input := unsafe { tos(&u8(voidptr(address)), int(length)) }
	mut text := ''
	if encoding == 4 {
		// Foundation consumes one leading UTF8 byte order mark.
		start := if input.len >= 3 && input[0] == 0xef && input[1] == 0xbb && input[2] == 0xbf { 3 } else { 0 }
		if utf8.validate_str(input) {
			text = unsafe { tos(input.str + start, input.len - start) }.clone()
		} else {
			// Native Foundation replaces stray A9 bytes with U+FFFD, but
			// rejects other malformed sequences. Preserve valid multibyte runs.
			mut bytes := []u8{cap: input.len}
			bytes.flags |= .noslices
			mut offset := start
			mut valid := true
			for offset < input.len {
				first := input[offset]
				width := if first == 0xa9 { 1 } else if first < 0x80 { 1 } else if first < 0xe0 { 2 } else if first < 0xf0 { 3 } else { 4 }
				if offset + width > input.len || (first != 0xa9 && !utf8.validate(unsafe { input.str + offset }, width)) {
					valid = false
					break
				}
				size := if first == 0xa9 { 3 } else { width }
				if u64(bytes.len + size) > mutable_string_limit { panic('iOS: string exceeds the supported size') }
				if first == 0xa9 { bytes << u8(0xef); bytes << u8(0xbf); bytes << u8(0xbd) } else {
					for i in 0 .. width { bytes << input[offset + i] }
				}
				offset += width
			}
			if valid { text = bytes.bytestr() }
			unsafe { bytes.free() }
			if !valid {
				C.ios_objc_initialize_unlock()
				return 0
			}
		}
	} else {
		// This Foundation factory accepts high ASCII bytes as Latin1 codepoints.
		mut size := input.len
		for byte in input { if byte >= 0x80 { size++ } }
		if u64(size) > mutable_string_limit { panic('iOS: string exceeds the supported size') }
		mut bytes := []u8{cap: size}
		for byte in input {
			if byte < 0x80 { bytes << byte } else {
				bytes << u8(0xc0 | (byte >> 6))
				bytes << u8(0x80 | (byte & 0x3f))
			}
		}
		text = bytes.bytestr()
		unsafe { bytes.free() }
	}
	// Snapshot before allocation, which may invoke application callbacks.
	C.ios_objc_initialize_unlock()
	defer { unsafe { text.free() } }
	if cls == ios_runtime.names['NSString'] { return objc_autorelease(owned_string(text)) }
	result := objc_allocate(cls)
	if result == 0 { return 0 }
	mutable_string_initialize(result, text)
	return objc_autorelease(result)
}

fn mutable_string_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	meta := object in ios_runtime.classes
	if !meta && selector == 'lastPathComponent' && objc_is_kind(object, ios_runtime.names['NSString']) {
		frame.x[0] = ns_string_last_path_component(object)
		return true
	}
	if !meta && selector == 'stringByAppendingPathComponent:' && objc_is_kind(object, ios_runtime.names['NSString']) {
		frame.x[0] = ns_string_append_path_component(object, frame.x[2])
		return true
	}
	if !meta && selector == 'cStringUsingEncoding:' && objc_is_kind(object, ios_runtime.names['NSString']) {
		frame.x[0] = ns_string_cstring_output(object, frame.x[2])
		return true
	}
	if !meta && selector == 'precomposedStringWithCanonicalMapping' && objc_is_kind(object, ios_runtime.names['NSString']) {
		frame.x[0] = ns_string_precomposed(object)
		return true
	}
	if !meta && selector == 'floatValue' && objc_is_kind(object, ios_runtime.names['NSString']) {
		ns_string_float_return(object, mut frame)
		return true
	}
	family := mutable_string_family(if meta { object } else { read64(object) })
	if meta && (family || object == ios_runtime.names['NSString']) && selector == 'stringWithCString:encoding:' {
		frame.x[0] = mutable_string_encoded_cstring(object, frame.x[2], frame.x[3])
		return true
	}
	if !family {
		if meta && object == ios_runtime.names['NSString'] && selector == 'stringWithUTF8String:' {
			frame.x[0] = mutable_string_cstring_snapshot(frame.x[2])
			return true
		}
		if !meta && objc_is_kind(object, ios_runtime.names['NSString']) {
			if selector == 'description' { return true }
			if selector in ['copy', 'copyWithZone:']! || selector.starts_with('init') {
				C.ios_objc_initialize_lock()
				owned_mutable := if header := ios_runtime.objects[object] { header.mutable_string_owned } else { false }
				C.ios_objc_initialize_unlock()
				// Changing isa does not make the original mutable buffer immutable.
				if owned_mutable {
					if selector in ['copy', 'copyWithZone:']! { frame.x[0] = mutable_string_snapshot(object, false); return true }
					if selector.starts_with('init') { panic('iOS: mutable string initialization after isa replacement is not implemented') }
				}
			}
			if selector == 'copyWithZone:' { frame.x[0] = objc_retain(object); return true }
			if selector in ['mutableCopy', 'mutableCopyWithZone:']! { frame.x[0] = mutable_string_snapshot(object, true); return true }
			if selector == 'stringByAppendingString:' { frame.x[0] = mutable_string_append_snapshot(object, frame.x[2]); return true }
			if selector == 'isEqualToString:' {
				C.ios_objc_initialize_lock()
				frame.x[0] = u64(frame.x[2] != 0 && mutable_string_source(object) == mutable_string_source(frame.x[2]))
				C.ios_objc_initialize_unlock()
				return true
			}
			if selector == 'lengthOfBytesUsingEncoding:' {
				C.ios_objc_initialize_lock()
				frame.x[0] = mutable_string_byte_length(object, frame.x[2])
				C.ios_objc_initialize_unlock()
				return true
			}
		}
		return false
	}
	if mutable_string_unsupported(selector) { panic('iOS: mutable string operation is outside the supported profile') }
	if mutable_string_types('NSMutableString', meta, selector) == none { return false }
	if meta || selector.starts_with('init') {
		if selector == 'new' { frame.x[0] = objc_new(object); return true }
		C.ios_objc_initialize_lock()
		if !meta && mutable_string_state(object).mutable_string_initialized {
			if selector != 'init' { panic('iOS: mutable string designated reinitialization is not implemented') }
			C.ios_objc_initialize_unlock()
			frame.x[0] = object
			return true
		}
		if selector in ['stringWithCapacity:', 'initWithCapacity:']! && frame.x[2] > mutable_string_limit {
			panic('iOS: mutable string capacity exceeds the supported size')
		}
		mut text := ''
		mut valid := true
		if selector in ['stringWithString:', 'initWithString:']! { text = mutable_string_source(frame.x[2]) }
		if selector in ['stringWithUTF8String:', 'initWithUTF8String:']! {
			if frame.x[2] == 0 { panic('iOS: mutable string UTF8 input must not be nil') }
			length := u64(C.strnlen(unsafe { &char(frame.x[2]) }, usize(mutable_string_limit + 1)))
			if length > mutable_string_limit { panic('iOS: mutable string exceeds the supported size') }
			text = unsafe { tos(&u8(voidptr(frame.x[2])), int(length)) }
		}
		if selector == 'initWithBytes:length:encoding:' {
			if frame.x[3] > mutable_string_limit || (frame.x[3] != 0 && frame.x[2] == 0) { panic('iOS: invalid mutable string byte input') }
			if frame.x[4] !in [u64(1), 4]! { panic('iOS: mutable string input encoding is not implemented') }
			if frame.x[3] != 0 { text = unsafe { tos(&u8(voidptr(frame.x[2])), int(frame.x[3])) } }
			if frame.x[4] == 1 { for byte in text { if byte >= 128 { panic('iOS: mutable string non-ASCII byte input is not implemented') } } }
		}
		valid = valid && utf8.validate_str(text)
		// A factory's source can be another mutable object's UTF8String. Copy
		// before allocation: a constructor callback may mutate that object.
		stable := if valid { text.clone() } else { '' }
		C.ios_objc_initialize_unlock()
		defer { unsafe { stable.free() } }
		if !valid { if !meta { objc_release(object) }; frame.x[0] = 0; return true }
		result := if meta { objc_allocate(object) } else { object }
		if result == 0 { frame.x[0] = 0; return true }
		mutable_string_initialize(result, stable)
		frame.x[0] = if meta { objc_autorelease(result) } else { result }
		return true
	}
	if selector in ['copy', 'copyWithZone:', 'mutableCopy', 'mutableCopyWithZone:']! {
		mutable_string_state(object)
		frame.x[0] = mutable_string_snapshot(object, selector.starts_with('mutableCopy'))
		return true
	}
	if selector == 'stringByAppendingString:' { frame.x[0] = mutable_string_append_snapshot(object, frame.x[2]); return true }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mutable_string_state(object)
	match selector {
		'description' {}
		'UTF8String' { frame.x[0] = u64(mutable_string_source(object).str) }
		'length' { frame.x[0] = mutable_string_units(mutable_string_source(object)) }
		'lengthOfBytesUsingEncoding:' { frame.x[0] = mutable_string_byte_length(object, frame.x[2]) }
		'isEqualToString:' { frame.x[0] = u64(frame.x[2] != 0 && mutable_string_source(object) == mutable_string_source(frame.x[2])) }
		'setString:' { mutable_string_replace(object, 0, mutable_string_units(mutable_string_source(object)), mutable_string_source(frame.x[2])) }
		'appendString:' { mutable_string_replace(object, mutable_string_units(mutable_string_source(object)), 0, mutable_string_source(frame.x[2])) }
		'insertString:atIndex:' { mutable_string_replace(object, frame.x[3], 0, mutable_string_source(frame.x[2])) }
		'deleteCharactersInRange:' { mutable_string_replace(object, frame.x[2], frame.x[3], '') }
		'replaceCharactersInRange:withString:' { mutable_string_replace(object, frame.x[2], frame.x[3], mutable_string_source(frame.x[4])) }
		else { return false }
	}
	return true
}

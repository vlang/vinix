// SPDX-License-Identifier: GPL-2.0-or-later
module main

import math.bits

struct ValueLayout { size u64 alignment u64 }
struct ValueTypeReader {
	text string
mut:
	position int
}

fn value_encoding(pointer &char) string {
	if pointer == unsafe { nil } { panic('iOS: value type encoding must not be nil') }
	mut length := 0
	for length <= 512 && unsafe { pointer[length] } != 0 { length++ }
	if length == 0 || length > 512 { panic('iOS: value type encoding exceeds limit') }
	return unsafe { tos(&u8(pointer), length) }
}

fn (mut reader ValueTypeReader) quoted() {
	if reader.position >= reader.text.len || reader.text[reader.position] != `"` { return }
	reader.position++
	for reader.position < reader.text.len && reader.text[reader.position] != `"` { reader.position++ }
	if reader.position == reader.text.len { panic('iOS: unterminated quoted value field') }
	reader.position++
}

fn value_align(size u64, alignment u64) u64 { return (size + alignment - 1) & ~(alignment - 1) }

fn (mut reader ValueTypeReader) read(depth int) ValueLayout {
	if depth > 16 { panic('iOS: value type nesting exceeds limit') }
	for reader.position < reader.text.len && reader.text[reader.position] in [`r`, `n`, `N`, `o`, `O`, `R`, `V`] { reader.position++ }
	if reader.position == reader.text.len { panic('iOS: incomplete value type encoding') }
	code := reader.text[reader.position]
	reader.position++
	match code {
		`c`, `C`, `B` { return ValueLayout{1, 1} }
		`s`, `S` { return ValueLayout{2, 2} }
		`i`, `I`, `l`, `L`, `f` { return ValueLayout{4, 4} } // Native encoding l/L is legacy 32-bit.
		`q`, `Q`, `d`, `#`, `:`, `*` { return ValueLayout{8, 8} }
		`v`, `?` { return ValueLayout{0, 1} }
		`@` {
			if reader.position < reader.text.len && reader.text[reader.position] == `?` { reader.position++ }
			else { reader.quoted() }
			return ValueLayout{8, 8}
		}
		`^` { reader.read(depth + 1); return ValueLayout{8, 8} }
		`[` {
			mut count := u64(0)
			start := reader.position
			for reader.position < reader.text.len && reader.text[reader.position] >= `0` && reader.text[reader.position] <= `9` {
				count = count * 10 + u64(reader.text[reader.position] - `0`)
				if count > 1024 { panic('iOS: value array count exceeds limit') }
				reader.position++
			}
			if start == reader.position { panic('iOS: value array requires a count') }
			element := reader.read(depth + 1)
			if reader.position >= reader.text.len || reader.text[reader.position] != `]` { panic('iOS: unterminated value array') }
			reader.position++
			if element.size * count > 1048576 { panic('iOS: value byte count exceeds limit') }
			return ValueLayout{element.size * count, element.alignment}
		}
		`{`, `(` {
			close := if code == `{` { u8(`}`) } else { u8(`)`) }
			for reader.position < reader.text.len && reader.text[reader.position] != `=` && reader.text[reader.position] != close { reader.position++ }
			if reader.position == reader.text.len || reader.text[reader.position] != `=` { panic('iOS: opaque value aggregate is not implemented') }
			reader.position++
			mut size := u64(0)
			mut alignment := u64(1)
			mut fields := 0
			for reader.position < reader.text.len && reader.text[reader.position] != close {
				reader.quoted()
				field := reader.read(depth + 1)
				alignment = if field.alignment > alignment { field.alignment } else { alignment }
				size = if code == `{` { value_align(size, field.alignment) + field.size } else if field.size > size { field.size } else { size }
				fields++
				if fields > 128 || size > 1048576 { panic('iOS: value aggregate exceeds limit') }
			}
			if reader.position == reader.text.len { panic('iOS: unterminated value aggregate') }
			reader.position++
			return ValueLayout{value_align(size, alignment), alignment}
		}
		else { panic('iOS: value type encoding is not implemented') }
	}
}

fn ns_get_size_alignment(pointer &char, size &u64, alignment &u64) &char {
	mut reader := ValueTypeReader{text: value_encoding(pointer)}
	layout := reader.read(0)
	unsafe { if size != nil { *size = layout.size }; if alignment != nil { *alignment = layout.alignment } }
	return unsafe { pointer + reader.position }
}

fn value_initialize(object u64, bytes u64, pointer &char) u64 {
	mut header := obj_header(object)
	if !header.value_owned { panic('iOS: invalid value storage') }
	if header.value_initialized { panic('iOS: value reinitialization is not implemented') }
	types := value_encoding(pointer)
	mut reader := ValueTypeReader{text: types}
	layout := reader.read(0)
	if reader.position != types.len || layout.size == 0 || layout.size > 1048576 || bytes == 0 { panic('iOS: invalid value bytes or complete type encoding') }
	mut result := object
	if read64(object) == ios_runtime.names['NSValue'] {
		result = objc_allocate(ios_runtime.names['NSConcreteValue'])
		header = obj_header(result)
	}
	header.data = []u8{len: int(layout.size)}
	header.data.flags |= .noslices
	header.text = unsafe { &char(C.malloc(usize(types.len + 1))) }
	if header.text == unsafe { nil } { panic('iOS: cannot allocate value encoding') }
	header.text_length = types.len
	unsafe { C.memcpy(header.data.data, voidptr(bytes), usize(layout.size)); C.memcpy(header.text, types.str, usize(types.len)); header.text[types.len] = 0 }
	header.value_initialized = true
	// A designated class-cluster initializer consumes its placeholder.
	if result != object { objc_release(object) }
	return result
}

fn value_create(bytes u64, types &char) u64 { return value_initialize(objc_allocate(ios_runtime.names['NSConcreteValue']), bytes, types) }

fn value_equal(left u64, right u64) bool {
	if left == right { return true }
	if right == 0 || !objc_is_kind(left, ios_runtime.names['NSValue']) || !objc_is_kind(right, ios_runtime.names['NSValue']) { return false }
	a := obj_header(left)
	b := obj_header(right)
	if !a.value_initialized || !b.value_initialized { return false }
	return string_text(left) == string_text(right) && a.data.len == b.data.len && C.memcmp(a.data.data, b.data.data, usize(a.data.len)) == 0
}

fn value_types(name string, meta bool, selector string) ?string {
	if name == 'NSNumber' && !meta && selector in ['getValue:', 'getValue:size:', 'objCType'] {
		return match selector { 'objCType' { 'r*16@0:8' } 'getValue:' { 'v24@0:8^v16' } else { 'v32@0:8^v16Q24' } }
	}
	if name !in ['NSValue', 'NSConcreteValue'] { return none }
	if meta {
		return match selector {
			'valueWithBytes:objCType:', 'value:withObjCType:' { '@32@0:8r^v16r*24' }
			'valueWithPointer:' { '@24@0:8r^v16' }
			'valueWithNonretainedObject:' { '@24@0:8@16' }
			'valueWithRange:' { '@32@0:8{_NSRange=QQ}16' }
			'valueWithPoint:', 'valueWithCGPoint:' { '@32@0:8{CGPoint=dd}16' }
			'valueWithSize:', 'valueWithCGSize:' { '@32@0:8{CGSize=dd}16' }
			'valueWithRect:', 'valueWithCGRect:' { '@48@0:8{CGRect={CGPoint=dd}{CGSize=dd}}16' }
			'valueWithCGAffineTransform:' { '@64@0:8{CGAffineTransform=dddddd}16' }
			'valueWithUIEdgeInsets:' { '@48@0:8{UIEdgeInsets=dddd}16' }
			'valueWithEdgeInsets:' { '@48@0:8{NSEdgeInsets=dddd}16' }
			else { return none }
		}
	}
	return match selector {
		'init', 'copy', 'nonretainedObjectValue' { '@16@0:8' }
		'initWithBytes:objCType:' { '@32@0:8r^v16r*24' }
		'copyWithZone:' { '@24@0:8^{_NSZone=}16' }
		'objCType' { 'r*16@0:8' }
		'getValue:' { 'v24@0:8^v16' }
		'getValue:size:' { 'v32@0:8^v16Q24' }
		'pointerValue' { '^v16@0:8' }
		'isEqual:', 'isEqualToValue:' { 'B24@0:8@16' }
		'hash' { 'Q16@0:8' }
		'rangeValue' { '{_NSRange=QQ}16@0:8' }
		'pointValue', 'CGPointValue' { '{CGPoint=dd}16@0:8' }
		'sizeValue', 'CGSizeValue' { '{CGSize=dd}16@0:8' }
		'rectValue', 'CGRectValue' { '{CGRect={CGPoint=dd}{CGSize=dd}}16@0:8' }
		'CGAffineTransformValue' { '{CGAffineTransform=dddddd}16@0:8' }
		'UIEdgeInsetsValue' { '{UIEdgeInsets=dddd}16@0:8' }
		'edgeInsetsValue' { '{NSEdgeInsets=dddd}16@0:8' }
		else { return none }
	}
}

fn value_selector(object u64, selector string) bool {
	if info := ios_runtime.classes[object] { return value_types(info.name, true, selector) != none }
	if objc_is_kind(object, ios_runtime.names['NSNumber']) { return selector in ['objCType', 'getValue:', 'getValue:size:'] }
	return objc_is_kind(object, ios_runtime.names['NSValue']) && value_types('NSValue', false, selector) != none
}

fn value_number_encoding(header &ObjHeader) &char {
	if header.cf_boolean { return c'c' }
	if header.is_real { return c'd' }
	if header.unsigned_number { return c'Q' }
	return c'q'
}

fn value_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	if info := ios_runtime.classes[object] {
		if value_types(info.name, true, selector) == none { return false }
		mut raw := [6]u64{}
		mut types := unsafe { &char(c'^v') }
		mut pointer := u64(unsafe { &raw[0] })
		match selector {
			'valueWithBytes:objCType:', 'value:withObjCType:' { pointer = frame.x[2]; types = unsafe { &char(frame.x[3]) } }
			'valueWithPointer:', 'valueWithNonretainedObject:' { raw[0] = frame.x[2] }
			'valueWithRange:' { raw[0] = frame.x[2]; raw[1] = frame.x[3]; types = c'{_NSRange=QQ}' }
			'valueWithPoint:', 'valueWithCGPoint:', 'valueWithSize:', 'valueWithCGSize:' { raw[0] = frame.q[0]; raw[1] = frame.q[2]; types = if selector in ['valueWithPoint:', 'valueWithCGPoint:'] { c'{CGPoint=dd}' } else { c'{CGSize=dd}' } }
			'valueWithRect:', 'valueWithCGRect:', 'valueWithUIEdgeInsets:', 'valueWithEdgeInsets:' { for i in 0 .. 4 { raw[i] = frame.q[i * 2] }; types = match selector { 'valueWithUIEdgeInsets:' { c'{UIEdgeInsets=dddd}' } 'valueWithEdgeInsets:' { c'{NSEdgeInsets=dddd}' } else { c'{CGRect={CGPoint=dd}{CGSize=dd}}' } } }
			'valueWithCGAffineTransform:' { pointer = frame.x[2]; types = c'{CGAffineTransform=dddddd}' }
			else { return false }
		}
		frame.x[0] = objc_autorelease(value_create(pointer, unsafe { &char(types) }))
		return true
	}
	if !objc_is_kind(object, ios_runtime.names['NSValue']) { return false }
	if objc_is_kind(object, ios_runtime.names['NSNumber']) {
		if selector !in ['objCType', 'getValue:', 'getValue:size:'] { return false }
		header := obj_header(object)
		types := value_number_encoding(header)
		if selector == 'objCType' { frame.x[0] = u64(types); return true }
		count := if header.cf_boolean { u64(1) } else { u64(8) }
		if frame.x[2] == 0 || (selector == 'getValue:size:' && frame.x[3] != count) { panic('iOS: value destination size must match exactly') }
		raw := [if header.is_real { bits.f64_bits(header.real_number) } else { u64(header.number) }]!
		unsafe { C.memmove(voidptr(frame.x[2]), &raw[0], usize(count)) }
		return true
	}
	if value_types('NSValue', false, selector) == none { return false }
	if selector == 'init' { objc_release(object); frame.x[0] = 0; return true }
	if selector == 'initWithBytes:objCType:' { frame.x[0] = value_initialize(object, frame.x[2], unsafe { &char(frame.x[3]) }); return true }
	header := obj_header(object)
	if !header.value_initialized { panic('iOS: value is not initialized') }
	match selector {
		'copy', 'copyWithZone:' { frame.x[0] = objc_retain(object) }
		'objCType' { frame.x[0] = u64(header.text) }
		'getValue:', 'getValue:size:' { if frame.x[2] == 0 || (selector == 'getValue:size:' && frame.x[3] != u64(header.data.len)) { panic('iOS: value destination size must match exactly') }; unsafe { C.memmove(voidptr(frame.x[2]), header.data.data, usize(header.data.len)) } }
		'pointerValue', 'nonretainedObjectValue' { if string_text(object) != '^v' { panic('iOS: value accessor type does not match') }; frame.x[0] = read64(u64(header.data.data)) }
		'isEqual:', 'isEqualToValue:' { frame.x[0] = u64(value_equal(object, frame.x[2])) }
		'hash' { mut hash := u64(14695981039346656037); for byte in string_text(object) { hash = (hash ^ u64(byte)) * 1099511628211 }; for byte in header.data { hash = (hash ^ u64(byte)) * 1099511628211 }; frame.x[0] = hash }
		'rangeValue' { if string_text(object) != '{_NSRange=QQ}' { panic('iOS: value accessor type does not match') }; frame.x[0] = read64(u64(header.data.data)); frame.x[1] = read64(u64(header.data.data) + 8) }
		'pointValue', 'CGPointValue', 'sizeValue', 'CGSizeValue', 'rectValue', 'CGRectValue', 'UIEdgeInsetsValue', 'edgeInsetsValue' {
			types := match selector { 'pointValue', 'CGPointValue' { '{CGPoint=dd}' } 'sizeValue', 'CGSizeValue' { '{CGSize=dd}' } 'UIEdgeInsetsValue' { '{UIEdgeInsets=dddd}' } 'edgeInsetsValue' { '{NSEdgeInsets=dddd}' } else { '{CGRect={CGPoint=dd}{CGSize=dd}}' } }
			if string_text(object) != types { panic('iOS: value accessor type does not match') }
			for i in 0 .. header.data.len / 8 { frame.q[i * 2] = read64(u64(header.data.data) + u64(i) * 8); frame.q[i * 2 + 1] = 0 }
		}
		'CGAffineTransformValue' { if string_text(object) != '{CGAffineTransform=dddddd}' || frame.x[8] == 0 { panic('iOS: value indirect result is invalid') }; unsafe { C.memmove(voidptr(frame.x[8]), header.data.data, 48) } }
		else { return false }
	}
	return true
}

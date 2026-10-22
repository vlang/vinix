// SPDX-License-Identifier: GPL-2.0-or-later
module main

// The public Foundation object keeps its measured 40-byte layout. The engine
// and ownership flags live in allocation metadata, independent of later isa
// changes and of whether the object bytes belong to objc_constructInstance.
fn regular_expression_family(cls u64) bool {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return false }
		if info.name == 'NSRegularExpression' { return true }
		current = info.parent
		if current == 0 { return false }
	}
	panic('iOS: cyclic regular expression superclass chain')
}

fn regex_result_family(cls u64) bool {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return false }
		if info.name == 'NSTextCheckingResult' { return true }
		current = info.parent
		if current == 0 { return false }
	}
	panic('iOS: cyclic text checking result superclass chain')
}

fn regular_expression_require_class(cls u64) {
	if regular_expression_family(cls) && cls != ios_runtime.names['NSRegularExpression'] {
		panic('iOS: regular expression subclass construction is not implemented')
	}
	if regex_result_family(cls) && cls != ios_runtime.names['VinixRegularExpressionCheckingResult'] {
		panic('iOS: regular expression results require the matching APIs')
	}
}

fn regular_expression_metadata() {
	mut cls := ios_runtime.classes[ios_runtime.names['NSRegularExpression']] or { panic('iOS: missing regular expression class') }
	for i, name in ['_pattern', '_options', '_internal', '_checkout']! {
		cls.ivars[name] = &ObjIvar{name: name.clone(), types: ['@"NSString"', 'Q', '^v', 'i']![i].clone(), offset: i64(8 + i * 8), size: if i == 3 { u64(4) } else { u64(8) }}
	}
}

fn regular_expression_state(object u64) &ObjHeader {
	header := obj_header(object)
	if !header.regular_expression_owned || header.native_size < 40 || header.destroying || header.destroyed {
		panic('iOS: regular expression requires live owned storage')
	}
	return header
}

fn regex_result_state(object u64) &ObjHeader {
	header := obj_header(object)
	if !header.regex_result_owned || !header.valid || header.destroying || header.destroyed {
		panic('iOS: regular expression result requires initialized owned storage')
	}
	return header
}

fn regular_expression_types(name string, meta bool, selector string) ?string {
	if name == 'NSTextCheckingResult' || name == 'VinixRegularExpressionCheckingResult' {
		if meta { return none }
		return match selector {
			'copy', 'regularExpression' { '@16@0:8' }
			'copyWithZone:' { '@24@0:8^{_NSZone=}16' }
			'numberOfRanges', 'resultType' { 'Q16@0:8' }
			'range' { '{_NSRange=QQ}16@0:8' }
			'rangeAtIndex:' { '{_NSRange=QQ}24@0:8Q16' }
			else { return none }
		}
	}
	if name != 'NSRegularExpression' { return none }
	if meta {
		return match selector {
			'new' { '@16@0:8' }
			'regularExpressionWithPattern:options:error:' { '@40@0:8@16Q24^@32' }
			'escapedPatternForString:', 'escapedTemplateForString:' { '@24@0:8@16' }
			else { return none }
		}
	}
	return match selector {
		'init', 'copy', 'pattern' { '@16@0:8' }
		'copyWithZone:' { '@24@0:8^{_NSZone=}16' }
		'options', 'numberOfCaptureGroups' { 'Q16@0:8' }
		'initWithPattern:options:error:' { '@40@0:8@16Q24^@32' }
		'numberOfMatchesInString:options:range:' { 'Q48@0:8@16Q24{_NSRange=QQ}32' }
		'rangeOfFirstMatchInString:options:range:' { '{_NSRange=QQ}48@0:8@16Q24{_NSRange=QQ}32' }
		'firstMatchInString:options:range:', 'matchesInString:options:range:' { '@48@0:8@16Q24{_NSRange=QQ}32' }
		else { return none }
	}
}

fn regular_expression_unsupported(selector string) bool {
	return selector in ['mutableCopy', 'mutableCopyWithZone:', 'initWithCoder:', 'encodeWithCoder:', 'supportsSecureCoding',
		'isEqual:', 'hash', 'description', 'enumerateMatchesInString:options:range:usingBlock:',
		'replaceMatchesInString:options:range:withTemplate:', 'replacementStringForResult:inString:offset:template:',
		'stringByReplacingMatchesInString:options:range:withTemplate:', '_captureGroupNumberWithName:']!
}

fn regex_result_unsupported(selector string) bool {
	return selector in ['init', 'new', 'mutableCopy', 'mutableCopyWithZone:', 'initWithCoder:', 'encodeWithCoder:', 'supportsSecureCoding',
		'rangeWithName:', 'resultByAdjustingRangesWithOffset:', '_adjustRangesWithOffset:', 'description', 'isEqual:']!
}

fn regular_expression_selector(object u64, selector string) bool {
	meta := object in ios_runtime.classes
	cls := if meta { object } else { read64(object) }
	if regular_expression_family(cls) { return regular_expression_types('NSRegularExpression', meta, selector) != none }
	if regex_result_family(cls) { return regular_expression_types('NSTextCheckingResult', meta, selector) != none }
	return false
}

fn regular_expression_text(object u64, limit int) string {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	text := cf_string_compare_text(object) or { panic('iOS: regular expression requires a live valid UTF-8 NSString') }
	if text.len > limit { panic('iOS: regular expression string exceeds the supported limit') }
	return text
}

fn regular_expression_error(output u64, pattern u64) {
	if output == 0 { return }
	domain := owned_string('NSCocoaErrorDomain')
	info := objc_allocate(ios_runtime.names['NSDictionary'])
	mut header := obj_header(info)
	header.keys << owned_string('NSInvalidValue')
	array_append(mut header, pattern)
	result := ns_error_create(domain, 2048, info)
	objc_release(info)
	objc_release(domain)
	unsafe { *(&u64(output)) = objc_autorelease(result) }
}

fn regular_expression_initialize(object u64, pattern u64, options u64, output u64) u64 {
	// Application NSString copying can release another reference to the receiver.
	// Its metadata must survive until initialization has returned from callbacks.
	objc_retain(object)
	defer { objc_release(object) }
	C.ios_objc_initialize_lock()
	mut header := regular_expression_state(object)
	if header.regular_expression != unsafe { nil } || header.regular_expression_initializing {
		panic('iOS: regular expression designated reinitialization is not implemented')
	}
	header.regular_expression_initializing = true
	C.ios_objc_initialize_unlock()
	if options & ~u64(63) != 0 { panic('iOS: regular expression compilation options are not implemented') }
	regular_expression_text(pattern, 4096)
	// NSString copying may invoke an application implementation; never hold the
	// runtime lock across it. Keep its returned +1 even if the source mutates.
	owned_pattern := objc_copy_value(pattern, false)
	if C.ios_ref_change(unsafe { &header.refs }, 0) <= 1 {
		panic('iOS: regular expression pattern copy consumed initializer ownership')
	}
	text := regular_expression_text(owned_pattern, 4096)
	program := ns_regex_compile(text, options) or {
		if !err.msg().starts_with('invalid:') { panic('iOS: regular expression ' + err.msg()) }
		regular_expression_error(output, owned_pattern)
		objc_release(owned_pattern)
		objc_release(object)
		return 0
	}
	mut storage := unsafe { &NSRegexProgram(C.calloc(1, sizeof(NSRegexProgram))) }
	if storage == unsafe { nil } { panic('iOS: cannot allocate regular expression program') }
	unsafe { *storage = program }
	C.ios_objc_initialize_lock()
	header = regular_expression_state(object)
	header.fields[0] = owned_pattern
	header.regular_expression = storage
	header.regular_expression_initializing = false
	unsafe {
		*(&u64(object + 8)) = owned_pattern
		*(&u64(object + 16)) = options
		*(&u64(object + 24)) = u64(storage)
	}
	C.ios_objc_initialize_unlock()
	// Success deliberately leaves the caller's NSError slot unchanged.
	return object
}

fn regular_expression_escape(object u64, template bool) u64 {
	text := regular_expression_text(object, 65536)
	mut bytes := []u8{cap: text.len * 2}
	bytes.flags |= .noslices
	defer { unsafe { bytes.free() } }
	for ch in text {
		if ch == `\\` || ch == `$` || (!template && ch in [`.`, `*`, `+`, `?`, `^`, `|`, `(`, `)`, `[`, `{`, `}`, `/`]!) { bytes << u8(`\\`) }
		bytes << ch
	}
	return objc_autorelease(owned_string(if bytes.len == 0 { '' } else { unsafe { tos(bytes.data, bytes.len) } }))
}

fn regex_result_create(expression u64, ranges []NSRegexSpan) u64 {
	if ranges.len == 0 || ranges.len > 33 { panic('iOS: regular expression capture count exceeds the supported limit') }
	result := objc_allocate(ios_runtime.names['VinixRegularExpressionCheckingResult'])
	mut header := obj_header(result)
	header.fields[0] = objc_retain(expression)
	header.data = []u8{len: ranges.len * 16}
	for i, span in ranges {
		unsafe {
			*(&u64(&header.data[i * 16])) = span.location
			*(&u64(&header.data[i * 16 + 8])) = span.length
		}
	}
	header.valid = true
	return result
}

fn regular_expression_next_scalar(text string, location u64) u64 {
	mut offset := u64(0)
	mut i := 0
	for i < text.len {
		first := text[i]
		width := if first < 0x80 { 1 } else if first < 0xe0 { 2 } else if first < 0xf0 { 3 } else { 4 }
		offset += if width == 4 { u64(2) } else { u64(1) }
		if offset > location { return offset }
		i += width
	}
	return location + 1
}

fn regular_expression_query(object u64, selector string, mut frame RegisterFrame) {
	header := regular_expression_state(object)
	if frame.x[3] & ~u64(4) != 0 { panic('iOS: regular expression matching options are not implemented') }
	text := regular_expression_text(frame.x[2], 65536)
	location := frame.x[4]
	length := frame.x[5]
	if location > u64(0x7fffffffffffffff) || length > u64(65536) || location > u64(65536) - length { panic('iOS: regular expression range is outside the supported profile') }
	end := location + length
	mut unit := u64(0)
	mut start_boundary := location == 0
	mut end_boundary := end == 0
	mut byte := 0
	for byte < text.len {
		first := text[byte]
		width := if first < 0x80 { 1 } else if first < 0xe0 { 2 } else if first < 0xf0 { 3 } else { 4 }
		unit += if width == 4 { u64(2) } else { u64(1) }
		byte += width
		if unit == location { start_boundary = true }
		if unit == end { end_boundary = true }
	}
	if !start_boundary || !end_boundary { panic('iOS: regular expression range is out of bounds or bisects a UTF-16 surrogate pair') }
	all := selector == 'matchesInString:options:range:'
	count_only := selector == 'numberOfMatchesInString:options:range:'
	array := if all { objc_allocate(ios_runtime.names['NSArray']) } else { u64(0) }
	if header.regular_expression == unsafe { nil } {
		frame.x[0] = if all { objc_autorelease(array) } else if selector == 'rangeOfFirstMatchInString:options:range:' { u64(0x7fffffffffffffff) } else { u64(0) }
		if selector == 'rangeOfFirstMatchInString:options:range:' { frame.x[1] = 0 }
		return
	}
	mut cursor := location
	mut count := u64(0)
	mut steps := u64(0)
	for {
		mut result := ns_regex_search(header.regular_expression, text, location, length, cursor, frame.x[3] & 4 != 0) or { panic('iOS: regular expression ' + err.msg()) }
		steps += result.steps
		if steps > 4000000 { ns_regex_match_free(mut result); panic('iOS: regular expression query exceeds the supported work limit') }
		if !result.found {
			ns_regex_match_free(mut result)
			if !all && !count_only { frame.x[0] = if selector == 'rangeOfFirstMatchInString:options:range:' { u64(0x7fffffffffffffff) } else { u64(0) }; if selector == 'rangeOfFirstMatchInString:options:range:' { frame.x[1] = 0 } }
			break
		}
		span := result.ranges[0]
		count++
		if count > 4096 { ns_regex_match_free(mut result); panic('iOS: regular expression query exceeds the supported match count') }
		if all {
			value := regex_result_create(object, result.ranges)
			mut array_header := obj_header(array)
			array_append(mut array_header, value)
			objc_release(value)
		} else if !count_only {
			if selector == 'rangeOfFirstMatchInString:options:range:' { frame.x[0] = span.location; frame.x[1] = span.length }
			else { frame.x[0] = objc_autorelease(regex_result_create(object, result.ranges)) }
			ns_regex_match_free(mut result)
			return
		}
		ns_regex_match_free(mut result)
		if frame.x[3] & 4 != 0 && span.length == 0 { break }
		cursor = if span.length == 0 { regular_expression_next_scalar(text, span.location) } else { span.location + span.length }
		if cursor > end { break }
	}
	if all { frame.x[0] = objc_autorelease(array) }
	if count_only { frame.x[0] = count }
}

fn regular_expression_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	meta := object in ios_runtime.classes
	cls := if meta { object } else { read64(object) }
	if regex_result_family(cls) {
		if regex_result_unsupported(selector) { panic('iOS: regular expression result operation is not implemented') }
		if regular_expression_types('NSTextCheckingResult', meta, selector) == none { return false }
		header := regex_result_state(object)
		match selector {
			'copy', 'copyWithZone:' { frame.x[0] = objc_retain(object) }
			'regularExpression' { frame.x[0] = header.fields[0] }
			'resultType' { frame.x[0] = 1024 }
			'numberOfRanges' { frame.x[0] = u64(header.data.len / 16) }
			'range', 'rangeAtIndex:' {
				index := if selector == 'range' { u64(0) } else { frame.x[2] }
				if index >= u64(header.data.len / 16) { panic('iOS: regular expression result range index is out of bounds') }
				frame.x[0] = read64(u64(header.data.data) + index * 16)
				frame.x[1] = read64(u64(header.data.data) + index * 16 + 8)
			}
			else { return false }
		}
		return true
	}
	if !regular_expression_family(cls) { return false }
	if regular_expression_unsupported(selector) { panic('iOS: regular expression operation is not implemented') }
	if regular_expression_types('NSRegularExpression', meta, selector) == none { return false }
	if meta {
		match selector {
			'new' { frame.x[0] = objc_new(object) }
			'regularExpressionWithPattern:options:error:' { frame.x[0] = objc_autorelease(regular_expression_initialize(objc_allocate(object), frame.x[2], frame.x[3], frame.x[4])) }
			'escapedPatternForString:', 'escapedTemplateForString:' { frame.x[0] = regular_expression_escape(frame.x[2], selector == 'escapedTemplateForString:') }
			else { return false }
		}
		return true
	}
	if selector == 'initWithPattern:options:error:' { frame.x[0] = regular_expression_initialize(object, frame.x[2], frame.x[3], frame.x[4]); return true }
	header := regular_expression_state(object)
	match selector {
		'init' {}
		'copy', 'copyWithZone:' { frame.x[0] = objc_retain(object) }
		'pattern' { frame.x[0] = header.fields[0] }
		'options' { frame.x[0] = read64(object + 16) }
		'numberOfCaptureGroups' { frame.x[0] = if header.regular_expression == unsafe { nil } { u64(0) } else { u64(header.regular_expression.groups) } }
		'numberOfMatchesInString:options:range:', 'rangeOfFirstMatchInString:options:range:', 'firstMatchInString:options:range:', 'matchesInString:options:range:' { regular_expression_query(object, selector, mut frame) }
		else { return false }
	}
	return true
}

fn regular_expression_dispose(object u64, mut header ObjHeader) {
	if !header.regular_expression_owned { return }
	if header.regular_expression != unsafe { nil } {
		ns_regex_program_free(mut header.regular_expression)
		unsafe { C.free(header.regular_expression) }
		header.regular_expression = unsafe { nil }
	}
	// Generic field disposal releases the copied pattern after the engine.
	unsafe { C.memset(voidptr(object + 8), 0, 32) }
}

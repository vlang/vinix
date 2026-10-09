// SPDX-License-Identifier: GPL-2.0-or-later
module main

import time
import encoding.utf8

fn string_text(object u64) string {
	if object == 0 { return '' }
	if object in ios_runtime.constants {
		if text := ios_runtime.constant_utf8[object] { return text }
		return unsafe { tos(&u8(read64(object + 16)), int(read64(object + 24))) }
	}
	header := obj_header(object)
	if header.text == unsafe { nil } { return '' }
	return unsafe { tos(&u8(header.text), header.text_length) }
}

fn ns_string_from_class(cls u64) u64 {
	info := ios_runtime.classes[cls] or { panic('iOS: NSStringFromClass: unknown class') }
	return make_string(unsafe { &char(info.name.str) })
}

fn object_equal(left u64, right u64) bool {
	return cf_equal_depth(left, right, 0)
}

fn cf_equal_depth(left u64, right u64, depth int) bool {
	if left == right { return true }
	if left == 0 || right == 0 { return false }
	if depth > 64 { panic('iOS: cyclic or excessively nested CF equality') }
	for name in ['NSArray', 'NSDictionary', 'NSData', 'NSString', 'NSNumber']! {
		cls := ios_runtime.names[name]
		if !objc_is_kind(left, cls) { continue }
		if !objc_is_kind(right, cls) { return false }
		if name == 'NSString' { return string_text(left) == string_text(right) }
		a := obj_header(left)
		b := obj_header(right)
		if name == 'NSNumber' {
			if a.is_real || b.is_real { return (if a.is_real { a.real_number } else { f64(a.number) }) == (if b.is_real { b.real_number } else { f64(b.number) }) }
			return a.number == b.number
		}
		if name == 'NSData' {
			length := data_length(left)
			return length == data_length(right) && (length == 0 || C.memcmp(unsafe { voidptr(data_pointer(left)) }, unsafe { voidptr(data_pointer(right)) }, usize(length)) == 0)
		}
		if a.items.len != b.items.len || a.cf_raw_values != b.cf_raw_values || a.cf_raw_keys != b.cf_raw_keys { return false }
		for i, value in a.items {
			mut j := i
			if name == 'NSDictionary' {
				j = -1
				for k, key in b.keys {
					if (a.cf_raw_keys && key == a.keys[i]) || (!a.cf_raw_keys && cf_equal_depth(key, a.keys[i], depth + 1)) { j = k; break }
				}
				if j < 0 { return false }
			}
			if a.cf_raw_values { if value != b.items[j] { return false } }
			else if !cf_equal_depth(value, b.items[j], depth + 1) { return false }
		}
		return true
	}
	if read64(left) != read64(right) { return false }
	info := ios_runtime.classes[read64(left)] or { return false }
	name := info.name
	return match name {
		'VinixCFDate' { obj_header(left).real_number == obj_header(right).real_number }
		'VinixSecPolicy' { cf_equal_depth(obj_header(left).fields[0], obj_header(right).fields[0], depth + 1) }
		'VinixSecCertificate', 'VinixSecKey' {
			a := obj_header(left)
			b := obj_header(right)
			a.number == b.number && a.section == b.section && a.data.len == b.data.len &&
				(a.data.len == 0 || C.memcmp(a.data.data, b.data.data, usize(a.data.len)) == 0)
		}
		'NSIndexPath' {
			obj_header(left).number == obj_header(right).number && obj_header(left).section == obj_header(right).section
		}
		else { false }
	}
}

fn dictionary_index(header &ObjHeader, key u64) int {
	for i, candidate in header.keys {
		if (header.cf_raw_keys && candidate == key) || (!header.cf_raw_keys && object_equal(candidate, key)) { return i }
	}
	return -1
}

fn array_append(mut header ObjHeader, object u64) {
	if object == 0 { panic('iOS: nil inserted into collection') }
	header.items << if header.cf_raw_values { object } else { objc_retain(object) }
	header.mutation++
}

fn collection_remove(mut header ObjHeader, index int) {
	if index < 0 || index >= header.items.len { panic('iOS: collection index out of range') }
	value := header.items[index]
	header.items.delete(index)
	if header.keys.len > 0 {
		key := header.keys[index]
		header.keys.delete(index)
		if !header.cf_raw_keys { objc_release(key) }
	}
	header.mutation++
	if !header.cf_raw_values { objc_release(value) }
}

fn foundation_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	if selector == 'isKindOfClass:' {
		frame.x[0] = u64(objc_is_kind(object, frame.x[2]))
		return true
	}
	if selector == 'respondsToSelector:' {
		frame.x[0] = u64(objc_responds(object, unsafe { &char(frame.x[2]) }))
		return true
	}
	if selector == 'class' {
		frame.x[0] = objc_class(object)
		return true
	}
	if selector == 'copy' {
		frame.x[0] = if is_block(object) { block_copy(object) } else { objc_retain(object) }
		return true
	}
	if object in ios_runtime.classes {
		match selector {
			'array', 'arrayWithCapacity:', 'dictionary' {
				frame.x[0] = objc_autorelease(objc_allocate(object))
			}
			'arrayWithArray:' {
				array := objc_allocate(object)
				mut header := obj_header(array)
				for item in obj_header(frame.x[2]).items { array_append(mut header, item) }
				frame.x[0] = objc_autorelease(array)
			}
			'arrayWithObjects:count:' {
				if frame.x[3] > 65536 { panic('iOS: array literal exceeds limit') }
				array := objc_allocate(object)
				mut header := obj_header(array)
				for i := u64(0); i < frame.x[3]; i++ {
					array_append(mut header, read64(frame.x[2] + i * 8))
				}
				frame.x[0] = objc_autorelease(array)
			}
			'dictionaryWithObjects:forKeys:count:' {
				if frame.x[4] > 65536 { panic('iOS: dictionary literal exceeds limit') }
				dictionary := objc_allocate(object)
				mut header := obj_header(dictionary)
				for index := u64(0); index < frame.x[4]; index++ {
					value := read64(frame.x[2] + index * 8)
					key := read64(frame.x[3] + index * 8)
					if key == 0 || value == 0 { panic('iOS: nil dictionary entry') }
					position := dictionary_index(header, key)
					if position >= 0 { objc_store_strong(unsafe { &header.items[position] }, value) }
					else { header.keys << objc_retain(key); array_append(mut header, value) }
				}
				frame.x[0] = objc_autorelease(dictionary)
			}
			'indexPathForRow:inSection:' {
				path := objc_allocate(object)
				mut header := obj_header(path)
				header.number = i64(frame.x[2])
				header.section = i64(frame.x[3])
				frame.x[0] = objc_autorelease(path)
			}
			'numberWithInteger:' {
				number := objc_allocate(object)
				mut header := obj_header(number)
				header.number = i64(frame.x[2])
				frame.x[0] = objc_autorelease(number)
			}
			'stringWithFormat:' { frame.x[0] = ns_format(frame.x[2], frame.stack) }
			'scheduledTimerWithTimeInterval:target:selector:userInfo:repeats:' {
				timer := objc_allocate(object)
				mut header := obj_header(timer)
				header.valid = true
				header.deadline = time.sys_mono_now() + i64(frame_double(frame, 0) * 1e9)
				header.number = i64(frame_double(frame, 0) * 1e9)
				header.repeat = frame.x[5] != 0
				header.action = frame.x[3]
				header.fields[0] = objc_retain(frame.x[2])
				header.fields[1] = objc_retain(frame.x[4])
				ios_runtime.timers << objc_retain(timer)
				frame.x[0] = objc_autorelease(timer)
			}
			else { return false }
		}
		return true
	}
	if selector == 'UTF8String' {
		frame.x[0] = u64(string_text(object).str)
		return true
	}
	if selector == 'length' && objc_is_kind(object, ios_runtime.names['NSString']) {
		mut length := u64(0)
		for byte in string_text(object) {
			if byte & 0xc0 != 0x80 { length += if byte >= 0xf0 { u64(2) } else { u64(1) } }
		}
		frame.x[0] = length
		return true
	}
	if selector == 'isEqualToString:' {
		frame.x[0] = u64(frame.x[2] != 0 && string_text(object) == string_text(frame.x[2]))
		return true
	}
	if selector == 'stringByAppendingString:' {
		if frame.x[2] == 0 { panic('iOS: NSString append requires a string') }
		text := string_text(object) + string_text(frame.x[2])
		frame.x[0] = make_string(unsafe { &char(text.str) })
		unsafe { text.free() }
		return true
	}
	mut header := obj_header(object)
	if selector == 'initWithBytes:length:encoding:' && objc_is_kind(object, ios_runtime.names['NSString']) {
		if frame.x[3] > 16 * 1024 * 1024 { panic('iOS: NSString exceeds size limit') }
		text := unsafe { tos(&u8(frame.x[2]), int(frame.x[3])) }
		mut valid := true
		if frame.x[4] == 4 { valid = utf8.validate_str(text) }
		else if frame.x[4] == 1 { for byte in text { if byte >= 128 { valid = false; break } } }
		else { panic('iOS: NSString encoding is unsupported') }
		if !valid { objc_release(object); frame.x[0] = 0; return true }
		C.free(header.text)
		header.text = unsafe { &char(C.malloc(usize(text.len + 1))) }
		header.text_length = text.len
		if header.text == unsafe { nil } { panic('iOS: cannot allocate NSString') }
		unsafe { C.memcpy(header.text, text.str, usize(text.len)); header.text[text.len] = 0 }
		return true
	}
	if selector == 'initWithString:attributes:' && objc_is_kind(object, ios_runtime.names['NSAttributedString']) {
		if frame.x[2] == 0 { objc_release(object); frame.x[0] = 0; return true }
		store_field(object, 0, frame.x[2])
		store_field(object, 1, frame.x[3])
		return true
	}
	match selector {
		'boolValue' { frame.x[0] = u64(header.number != 0 || header.real_number != 0) }
		'integerValue', 'unsignedIntegerValue', 'intValue' { frame.x[0] = u64(if header.is_real { i64(header.real_number) } else { header.number }) }
		'doubleValue' { frame_float_return(mut frame, 0, if header.is_real { header.real_number } else { f64(header.number) }) }
		'row' { frame.x[0] = u64(header.number) }
		'section' { frame.x[0] = u64(header.section) }
		'stringValue' {
			mut buffer := [64]u8{}
			C.snprintf(unsafe { &char(&buffer[0]) }, 64, c'%lld', header.number)
			frame.x[0] = make_string(unsafe { &char(&buffer[0]) })
		}
		'count' { frame.x[0] = u64(header.items.len) }
		'firstObject' { frame.x[0] = if header.items.len == 0 { u64(0) } else { header.items[0] } }
		'objectAtIndex:', 'objectAtIndexedSubscript:' {
			index := frame.x[2]
			if index >= u64(header.items.len) { panic('iOS: array index out of range') }
			frame.x[0] = header.items[int(index)]
		}
		'setObject:atIndexedSubscript:' {
			if frame.x[3] >= u64(header.items.len) { panic('iOS: array index out of range') }
			objc_store_strong(unsafe { &header.items[int(frame.x[3])] }, frame.x[2])
			header.mutation++
		}
		'addObject:' { array_append(mut header, frame.x[2]) }
		'removeObjectAtIndex:' { collection_remove(mut header, int(frame.x[2])) }
		'objectForKey:', 'objectForKeyedSubscript:' {
			index := dictionary_index(header, frame.x[2])
			frame.x[0] = if index < 0 { u64(0) } else { header.items[index] }
		}
		'setObject:forKeyedSubscript:' {
			index := dictionary_index(header, frame.x[3])
			if frame.x[2] == 0 {
				if index >= 0 { collection_remove(mut header, index) }
			} else if index < 0 {
				header.keys << objc_retain(frame.x[3])
				array_append(mut header, frame.x[2])
			} else {
				objc_store_strong(unsafe { &header.items[index] }, frame.x[2])
				header.mutation++
			}
		}
		'removeObjectForKey:' {
			index := dictionary_index(header, frame.x[2])
			if index >= 0 { collection_remove(mut header, index) }
		}
		'removeAllObjects' {
			for header.items.len > 0 { collection_remove(mut header, header.items.len - 1) }
		}
		'countByEnumeratingWithState:objects:count:' {
			state := frame.x[2]
			start := read64(state)
			count := if start >= u64(header.items.len) {
				u64(0)
			} else {
				if frame.x[4] < u64(header.items.len) - start {
					frame.x[4]
				} else {
					u64(header.items.len) - start
				}
			}
			unsafe {
				*(&u64(state)) = start + count
				*(&u64(state + 8)) = frame.x[3]
				*(&u64(state + 16)) = u64(&header.mutation)
				for i := u64(0); i < count; i++ {
					*(&u64(frame.x[3] + i * 8)) = if header.keys.len > 0 {
						header.keys[int(start + i)]
					} else {
						header.items[int(start + i)]
					}
				}
			}
			frame.x[0] = count
		}
		'isValid' { frame.x[0] = u64(header.valid) }
		'invalidate' { timer_invalidate(object) }
		else { return false }
	}
	return true
}

// Darwin ARM64 puts anonymous arguments on the original stack. Preserve
// printf's flags/width/precision and native double layout; %@ remains an
// Objective-C string/object substitution rather than a libc conversion.
fn ns_format(format u64, stack u64) u64 {
	text := string_text(format)
	mut out := []u8{cap: text.len + 64}
	out.flags |= .noslices
	defer { unsafe { out.free() } }
	mut index := 0
	mut argument := stack
	for index < text.len {
		if text[index] != `%` { out << text[index]; index++; continue }
		start := index
		index++
		if index < text.len && text[index] == `%` { out << u8(`%`); index++; continue }
		for index < text.len && text[index] in [`#`, `0`, `-`, ` `, `+`, `.`, `1`, `2`, `3`, `4`, `5`, `6`, `7`, `8`, `9`, `h`, `l`, `z`, `t`, `j`] {
			index++
		}
		if index >= text.len { panic('iOS: incomplete NSString format') }
		if index - start > 64 { panic('iOS: NSString conversion is too long') }
		conversion := text[index]
		index++
		if conversion == `@` {
			if index - start != 2 { panic('iOS: NSString object formatting flags are not implemented') }
			rendered := string_text(read64(argument))
			unsafe { out.push_many(rendered.str, rendered.len) }
		} else {
			if conversion !in [`d`, `i`, `u`, `x`, `X`, `o`, `f`, `F`, `e`, `E`, `g`, `G`, `a`, `A`, `c`, `s`, `p`] {
				panic('iOS: unsupported NSString format')
			}
			mut specifier := [66]u8{}
			unsafe { C.memcpy(&specifier[0], text.str + start, usize(index - start)) }
			length := C.ios_vsnprintf(unsafe { nil }, 0, unsafe { &char(&specifier[0]) }, unsafe { voidptr(argument) })
			if length < 0 || length > 1024 * 1024 { panic('iOS: invalid or excessive NSString formatted output') }
			mut buffer := []u8{len: length + 1}
			result := C.ios_vsnprintf(unsafe { &char(buffer.data) }, usize(buffer.len), unsafe { &char(&specifier[0]) }, unsafe { voidptr(argument) })
			if result != length { panic('iOS: inconsistent NSString formatting') }
			unsafe { out.push_many(buffer.data, length); buffer.free() }
		}
		argument += 8
		if out.len > 1024 * 1024 { panic('iOS: NSString formatted output exceeds limits') }
	}
	out << u8(0)
	return make_string(unsafe { &char(out.data) })
}

fn timer_invalidate(timer u64) {
	mut header := obj_header(timer)
	header.valid = false
	store_field(timer, 0, 0)
	store_field(timer, 1, 0)
}

fn timers_fire() bool {
	mut changed := false
	mut i := 0
	mut remaining := ios_runtime.timers.len
	for remaining > 0 && i < ios_runtime.timers.len {
		remaining-- // Callbacks/repeats scheduled here belong to the next turn.
		timer := ios_runtime.timers[i]
		header := obj_header(timer)
		if header.valid && time.sys_mono_now() < header.deadline {
			i++
			continue
		}
		ios_runtime.timers.delete(i)
		if header.valid {
			target := objc_retain(header.fields[0])
			action := header.action
			if header.repeat {
				mut repeated := obj_header(timer)
				repeated.deadline = time.sys_mono_now() + header.number
				ios_runtime.timers << objc_retain(timer)
			} else {
				timer_invalidate(timer)
			}
			invoke_action(target, action, timer)
			objc_release(target)
			changed = true
		}
		objc_release(timer)
	}
	return changed
}

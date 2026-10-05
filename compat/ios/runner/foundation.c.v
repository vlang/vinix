// SPDX-License-Identifier: GPL-2.0-or-later
module main

import time

fn string_text(object u64) string {
	if object == 0 { return '' }
	if object in ios_runtime.constants {
		return unsafe { tos(&u8(read64(object + 16)), int(read64(object + 24))) }
	}
	return ctext(u64(obj_header(object).text))
}

fn ns_string_from_class(cls u64) u64 {
	info := ios_runtime.classes[cls] or { panic('iOS: NSStringFromClass: unknown class') }
	return make_string(unsafe { &char(info.name.str) })
}

fn object_equal(left u64, right u64) bool {
	if left == right { return true }
	if left == 0 || right == 0 || read64(left) != read64(right) { return false }
	info := ios_runtime.classes[read64(left)] or { return false }
	name := info.name
	return match name {
		'NSIndexPath' {
			obj_header(left).number == obj_header(right).number && obj_header(left).section == obj_header(right).section
		}
		'NSNumber' { obj_header(left).number == obj_header(right).number }
		'NSString' { string_text(left) == string_text(right) }
		else { false }
	}
}

fn dictionary_index(header &ObjHeader, key u64) int {
	for i, candidate in header.keys { if object_equal(candidate, key) { return i } }
	return -1
}

fn array_append(mut header ObjHeader, object u64) {
	if object == 0 { panic('iOS: nil inserted into collection') }
	header.items << objc_retain(object)
	header.mutation++
}

fn collection_remove(mut header ObjHeader, index int) {
	if index < 0 || index >= header.items.len { panic('iOS: collection index out of range') }
	value := header.items[index]
	header.items.delete(index)
	if header.keys.len > 0 {
		key := header.keys[index]
		header.keys.delete(index)
		objc_release(key)
	}
	header.mutation++
	objc_release(value)
}

fn foundation_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
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
	mut header := obj_header(object)
	match selector {
		'row' { frame.x[0] = u64(header.number) }
		'section' { frame.x[0] = u64(header.section) }
		'stringValue' {
			mut buffer := [64]u8{}
			C.snprintf(unsafe { &char(&buffer[0]) }, 64, c'%lld', header.number)
			frame.x[0] = make_string(unsafe { &char(&buffer[0]) })
		}
		'count' { frame.x[0] = u64(header.items.len) }
		'firstObject' { frame.x[0] = if header.items.len == 0 { u64(0) } else { header.items[0] } }
		'objectAtIndexedSubscript:' {
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
		'objectForKeyedSubscript:' {
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

// Darwin ARM64 puts the anonymous arguments of Objective-C variadic methods
// on the original stack. This subset accepts integer and object substitutions.
fn ns_format(format u64, stack u64) u64 {
	text := string_text(format)
	mut out := []u8{cap: text.len + 64}
	out.flags |= .noslices
	defer { unsafe { out.free() } }
	mut i := 0
	mut argument := stack
	for i < text.len {
		if text[i] != `%` {
			out << text[i]
			i++
			continue
		}
		i++
		if i < text.len && text[i] == `%` {
			out << u8(`%`)
			i++
			continue
		}
		mut wide := false
		for i < text.len && text[i] == `l` {
			wide = true
			i++
		}
		if i >= text.len { panic('iOS: incomplete NSString format') }
		value := read64(argument)
		argument += 8
		mut buffer := [64]u8{}
		mut rendered := ''
		match text[i] {
			`d`, `i` {
				number := if wide { i64(value) } else { i64(i32(value)) }
				C.snprintf(unsafe { &char(&buffer[0]) }, 64, c'%lld', number)
				rendered = ctext(u64(&buffer[0]))
			}
			`u` {
				number := if wide { value } else { u64(u32(value)) }
				C.snprintf(unsafe { &char(&buffer[0]) }, 64, c'%llu', number)
				rendered = ctext(u64(&buffer[0]))
			}
			`@` { rendered = string_text(value) }
			else { panic('iOS: unsupported NSString format') }
		}
		unsafe { out.push_many(rendered.str, rendered.len) }
		i++
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

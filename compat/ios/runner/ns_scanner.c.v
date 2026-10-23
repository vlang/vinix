// SPDX-License-Identifier: GPL-2.0-or-later
module main

// The public instance contains only an isa. Keep the input snapshot and cursor
// in owned sidecar storage; no source string is borrowed across constructors.
struct FoundationScanner {
mut:
	units          []u16
	location       int
	initialized    bool
	has_string     bool
	case_sensitive bool
	skip_enabled   bool = true
	skip           &u8  = unsafe { nil }
}

fn ns_scanner_family(cls u64) bool {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return false }
		if info.name == 'NSScanner' { return true }
		current = info.parent
		if current == 0 { return false }
	}
	panic('iOS: cyclic scanner superclass chain')
}

fn ns_scanner_require_class(cls u64) {
	if ns_scanner_family(cls) && cls != ios_runtime.names['NSScanner'] {
		panic('iOS: custom scanner subclass construction is not implemented')
	}
}

fn ns_scanner_install(cls u64, mut header ObjHeader) {
	if cls != ios_runtime.names['NSScanner'] { return }
	header.scanner = unsafe { &FoundationScanner(C.calloc(1, sizeof(FoundationScanner))) }
	if header.scanner == unsafe { nil } { panic('iOS: cannot allocate scanner state') }
	header.scanner.units = []u16{}
	header.scanner.units.flags |= .noslices
	header.scanner.skip = ns_character_set_bitmap()
	header.scanner.skip_enabled = true
	for scalar in [u32(9), 10, 11, 12, 13, 32, 0x85, 0xa0, 0x1680, 0x2028, 0x2029, 0x202f, 0x205f,
		0x3000]! {
		ns_character_set_set_range(header.scanner.skip, scalar, 1, true)
	}
	ns_character_set_set_range(header.scanner.skip, 0x2000, 12, true)
}

// Caller holds the runtime lock. An isa change never grants storage rights.
fn ns_scanner_storage(object u64, initialized bool) &FoundationScanner {
	header := obj_header(object)
	state := header.scanner
	if state == unsafe { nil } || state.skip == unsafe { nil } || header.destroying || header.destroyed
		|| C.ios_ref_change(unsafe { &header.refs }, 0) <= 0 || header.native_size < 8
		|| header.cls != header.allocation_cls || read64(object) != header.allocation_cls
		|| header.allocation_cls != ios_runtime.names['NSScanner'] {
		panic('iOS: NSScanner requires live owned scanner storage')
	}
	if initialized && !state.initialized { panic('iOS: scanner requires initialization') }
	return state
}

fn ns_scanner_dispose(mut header ObjHeader) {
	state := header.scanner
	header.scanner = unsafe { nil }
	if state != unsafe { nil } {
		unsafe { state.units.free() }
		C.free(state.skip)
		C.free(state)
	}
}

fn ns_scanner_snapshot(object u64) []u16 {
	if object == 0 { return []u16{} }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if header := ios_runtime.objects[object] {
		if header.destroying || header.cls != header.allocation_cls || read64(object) != header.allocation_cls
			|| header.allocation_cls !in [ios_runtime.names['NSString'],
				ios_runtime.names['NSMutableString']]!
			|| (header.mutable_string_owned && !header.mutable_string_initialized) {
			panic('iOS: scanner input requires a built-in initialized string')
		}
	}
	text := cf_string_compare_text(object) or { panic('iOS: scanner input requires a live UTF8 string') }
	if text.len > 65536 { panic('iOS: scanner string exceeds byte limit') }
	mut units := []u16{cap: text.len}
	units.flags |= .noslices
	mut cursor := CFStringCompareCursor{ text: text }
	for {
		unit := cursor.next()
		if unit == 0x10000 { break }
		units << u16(unit)
	}
	return units
}

fn ns_scanner_commit(object u64, units []u16) u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut state := ns_scanner_storage(object, false)
	if state.initialized || state.units.len != 0 {
		panic('iOS: scanner is already initialized or its constructor changed storage')
	}
	for unit in units { state.units << unit }
	state.initialized = true
	state.has_string = true
	return object
}

fn ns_scanner_default(object u64) u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut state := ns_scanner_storage(object, false)
	if state.initialized { panic('iOS: scanner is already initialized') }
	state.initialized = true
	state.skip_enabled = false
	return object
}

fn ns_scanner_initialize(object u64, input u64) u64 {
	units := ns_scanner_snapshot(input)
	defer { unsafe { units.free() } }
	return ns_scanner_commit(object, units)
}

fn ns_scanner_create(cls u64, input u64) u64 {
	ns_scanner_require_class(cls)
	if cls != ios_runtime.names['NSScanner'] { panic('iOS: scanner factory requires NSScanner') }
	units := ns_scanner_snapshot(input)
	defer { unsafe { units.free() } }
	object := objc_allocate(cls)
	if object == 0 { return 0 }
	return ns_scanner_commit(object, units)
}

// All helpers below run under the runtime lock. Snapshot returned values before
// allocating Objective-C objects, whose constructors can reenter or retire us.
fn ns_scanner_text(units []u16, start int, end int) string {
	mut bytes := []u8{cap: (end - start) * 3}
	bytes.flags |= .noslices
	defer { unsafe { bytes.free() } }
	mut i := start
	for i < end {
		mut scalar := u32(units[i])
		i++
		if scalar >= 0xd800 && scalar <= 0xdbff {
			if i == end || units[i] < 0xdc00 || units[i] > 0xdfff {
				panic('iOS: scanner result splits a surrogate pair')
			}
			scalar = 0x10000 + ((scalar - 0xd800) << 10) + u32(units[i]) - 0xdc00
			i++
		} else if scalar >= 0xdc00 && scalar <= 0xdfff {
			panic('iOS: scanner result splits a surrogate pair')
		}
		if scalar < 0x80 {
			bytes << u8(scalar)
		} else if scalar < 0x800 {
			bytes << u8(0xc0 | scalar >> 6)
			bytes << u8(0x80 | scalar & 63)
		} else if scalar < 0x10000 {
			bytes << u8(0xe0 | scalar >> 12)
			bytes << u8(0x80 | scalar >> 6 & 63)
			bytes << u8(0x80 | scalar & 63)
		} else {
			bytes << u8(0xf0 | scalar >> 18)
			bytes << u8(0x80 | scalar >> 12 & 63)
			bytes << u8(0x80 | scalar >> 6 & 63)
			bytes << u8(0x80 | scalar & 63)
		}
	}
	return bytes.bytestr()
}

fn ns_scanner_member(bits &u8, scalar u32) bool {
	return unsafe { bits[scalar >> 3] & u8(1 << (scalar & 7)) != 0 }
}

fn ns_scanner_start(state &FoundationScanner) int {
	return ns_scanner_skip(state, state.location)
}

fn ns_scanner_skip(state &FoundationScanner, position int) int {
	mut start := position
	if state.skip_enabled {
		for start < state.units.len {
			mut scalar := u32(state.units[start])
			mut width := 1
			if scalar >= 0xd800 && scalar <= 0xdbff {
				scalar = 0x10000 + ((scalar - 0xd800) << 10) + u32(state.units[start + 1]) - 0xdc00
				width = 2
			}
			if !ns_scanner_member(state.skip, scalar) { break }
			start += width
		}
	}
	return start
}

fn ns_scanner_ascii(units []u16) {
	for unit in units {
		if unit > 127 {
			panic('iOS: non-ASCII numeric or string-pattern scanner input is not implemented')
		}
	}
}

fn ns_scanner_boundary(units []u16, location int) {
	if location > 0 && location < units.len && units[location] >= 0xdc00 && units[location] <= 0xdfff {
		panic('iOS: scanner location splits a surrogate pair')
	}
}

fn ns_scanner_copy(object u64) u64 {
	C.ios_objc_initialize_lock()
	state := ns_scanner_storage(object, true)
	mut units := []u16{cap: state.units.len}
	units.flags |= .noslices
	for unit in state.units { units << unit }
	location := state.location
	case_sensitive := state.case_sensitive
	skip_enabled := state.skip_enabled
	bits := ns_character_set_bitmap()
	C.memcpy(bits, state.skip, ns_character_set_bytes)
	C.ios_objc_initialize_unlock()
	defer {
		unsafe { units.free() }
		C.free(bits)
	}
	result := objc_allocate(ios_runtime.names['NSScanner'])
	if result == 0 { return 0 }
	ns_scanner_commit(result, units)
	C.ios_objc_initialize_lock()
	mut target := ns_scanner_storage(result, true)
	target.location = location
	target.case_sensitive = case_sensitive
	target.skip_enabled = skip_enabled
	C.memcpy(target.skip, bits, ns_character_set_bytes)
	C.ios_objc_initialize_unlock()
	return result
}

fn ns_scanner_number(object u64, selector string, output u64) bool {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut state := ns_scanner_storage(object, true)
	ns_scanner_ascii(state.units)
	mut cursor := ns_scanner_start(state)
	hex := selector.starts_with('scanHex')
	mut negative := false
	if !hex && cursor < state.units.len && state.units[cursor] in [u16(43), 45]! {
		negative = state.units[cursor] == 45
		cursor = ns_scanner_skip(state, cursor + 1)
	}
	if hex && cursor + 2 < state.units.len && state.units[cursor] == 48 && state.units[cursor + 1] in [
		u16(88),
		120,
	]!
		&& ns_scanner_digit(state.units[cursor + 2], true) >= 0 {
		cursor += 2
	}
	start := cursor
	width32 := selector in ['scanInt:', 'scanHexInt:']!
	limit := if hex {
		if width32 { u64(0xffffffff) } else { ~u64(0) }
	} else if width32 {
		if negative { u64(0x80000000) } else { u64(0x7fffffff) }
	} else {
		if negative { u64(0x8000000000000000) } else { u64(0x7fffffffffffffff) }
	}
	base := if hex { u64(16) } else { u64(10) }
	mut value := u64(0)
	for cursor < state.units.len {
		digit := ns_scanner_digit(state.units[cursor], hex)
		if digit < 0 { break }
		if value > (limit - u64(digit)) / base {
			value = limit
		} else {
			value = value * base + u64(digit)
		}
		cursor++
	}
	if cursor == start { return false }
	if negative { value = u64(0) - value }
	state.location = cursor
	if output != 0 {
		if width32 {
			narrow := u32(value)
			C.memcpy(unsafe { voidptr(output) }, &narrow, 4)
		} else {
			C.memcpy(unsafe { voidptr(output) }, &value, 8)
		}
	}
	return true
}

fn ns_scanner_digit(unit u16, hex bool) int {
	if unit >= 48 && unit <= 57 { return int(unit - 48) }
	if hex && unit >= 65 && unit <= 70 { return int(unit - 65) + 10 }
	if hex && unit >= 97 && unit <= 102 { return int(unit - 97) + 10 }
	return -1
}

fn ns_scanner_fold(unit u16, sensitive bool) u16 {
	return if !sensitive && unit >= 65 && unit <= 90 { unit + 32 } else { unit }
}

fn ns_scanner_matches(units []u16, position int, pattern []u16, sensitive bool) bool {
	if pattern.len > units.len - position { return false }
	for i, unit in pattern {
		if ns_scanner_fold(units[position + i], sensitive) != ns_scanner_fold(unit, sensitive) {
			return false
		}
	}
	return true
}

fn ns_scanner_scan_text(object u64, selector string, input u64, output u64) bool {
	if input == 0 { panic('iOS: scanner requires a non-nil target string or character set') }
	C.ios_objc_initialize_lock()
	mut state := ns_scanner_storage(object, true)
	set_scan := selector in ['scanCharactersFromSet:intoString:',
		'scanUpToCharactersFromSet:intoString:']!
	start := ns_scanner_start(state)
	mut end := start
	if set_scan {
		for unit in state.units {
			if unit >= 0xd800 && unit <= 0xdfff {
				panic('iOS: supplementary character set scanning is not implemented')
			}
		}
		set := ns_character_set_storage(input, true)
		up_to := selector == 'scanUpToCharactersFromSet:intoString:'
		for end < state.units.len && ns_scanner_member(set.bits, u32(state.units[end])) != up_to {
			end++
		}
	} else {
		pattern := ns_scanner_snapshot(input)
		defer { unsafe { pattern.free() } }
		// Foundation matches canonical Unicode equivalents even in sensitive
		// mode. Reject that domain instead of silently using literal UTF16.
		ns_scanner_ascii(state.units)
		ns_scanner_ascii(pattern)
		if selector == 'scanString:intoString:' {
			if pattern.len != 0 && ns_scanner_matches(state.units, start, pattern, state.case_sensitive) {
				end = start + pattern.len
			}
		} else {
			for end < state.units.len && (pattern.len == 0 || !ns_scanner_matches(state.units, end, pattern, state.case_sensitive)) {
				end++
			}
		}
	}
	if end == start {
		C.ios_objc_initialize_unlock()
		return false
	}
	ns_scanner_boundary(state.units, start)
	ns_scanner_boundary(state.units, end)
	// Build output bytes before committing; after unlocking, never borrow state.
	text := if output != 0 { ns_scanner_text(state.units, start, end) } else { '' }
	state.location = end
	C.ios_objc_initialize_unlock()
	defer { if output != 0 { unsafe { text.free() } } }
	if output != 0 {
		result := objc_autorelease(owned_string(text))
		C.memcpy(unsafe { voidptr(output) }, &result, 8)
	}
	return true
}

fn ns_scanner_types(name string, meta bool, selector string) ?string {
	if name != 'NSScanner' { return none }
	if meta { return if selector == 'scannerWithString:' { '@24@0:8@16' } else { none } }
	return match selector {
		'initWithString:' { '@24@0:8@16' }
		'init', 'string', 'charactersToBeSkipped', 'locale', 'copy' { '@16@0:8' }
		'copyWithZone:' { '@24@0:8^{_NSZone=}16' }
		'scanLocation' { 'Q16@0:8' }
		'setScanLocation:' { 'v24@0:8Q16' }
		'isAtEnd', 'caseSensitive' { 'B16@0:8' }
		'setCaseSensitive:' { 'v20@0:8B16' }
		'setCharactersToBeSkipped:', 'setLocale:' { 'v24@0:8@16' }
		'scanInteger:', 'scanLongLong:' { 'B24@0:8^q16' }
		'scanInt:' { 'B24@0:8^i16' }
		'scanHexInt:' { 'B24@0:8^I16' }
		'scanHexLongLong:' { 'B24@0:8^Q16' }
		'scanString:intoString:', 'scanUpToString:intoString:', 'scanCharactersFromSet:intoString:',
		'scanUpToCharactersFromSet:intoString:' {
			'B32@0:8@16^@24'
		}
		else { return none }
	}
}

fn ns_scanner_unsupported(selector string) bool {
	return selector in ['localizedScannerWithString:', 'scanFloat:', 'scanDouble:', 'scanHexFloat:',
		'scanHexDouble:', 'scanUnsignedLongLong:', 'mutableCopy', 'mutableCopyWithZone:',
		'initWithCoder:', 'encodeWithCoder:', 'isEqual:', 'hash', 'description', 'debugDescription']!
}

fn ns_scanner_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	meta := object in ios_runtime.classes
	cls := if meta { object } else { read64(object) }
	mut owned := ns_scanner_family(cls)
	if !meta {
		C.ios_objc_initialize_lock()
		if header := ios_runtime.objects[object] {
			owned = owned || header.scanner != unsafe { nil }
		}
		C.ios_objc_initialize_unlock()
	}
	if !owned { return false }
	if ns_scanner_unsupported(selector) { panic('iOS: scanner option is not implemented') }
	if ns_scanner_types('NSScanner', meta, selector) == none { return false }
	if meta {
		frame.x[0] = objc_autorelease(ns_scanner_create(cls, frame.x[2]))
		return true
	}
	if selector == 'init' {
		frame.x[0] = ns_scanner_default(object)
		return true
	}
	if selector == 'initWithString:' {
		frame.x[0] = ns_scanner_initialize(object, frame.x[2])
		return true
	}
	if selector in ['copy', 'copyWithZone:']! {
		if selector == 'copyWithZone:' && frame.x[2] != 0 {
			panic('iOS: scanner copy zones are not implemented')
		}
		frame.x[0] = ns_scanner_copy(object)
		return true
	}
	if selector.starts_with('scan') && selector.ends_with('intoString:') {
		frame.x[0] = u64(ns_scanner_scan_text(object, selector, frame.x[2], frame.x[3]))
		return true
	}
	if selector in ['scanInteger:', 'scanInt:', 'scanLongLong:', 'scanHexInt:', 'scanHexLongLong:']! {
		frame.x[0] = u64(ns_scanner_number(object, selector, frame.x[2]))
		return true
	}
	C.ios_objc_initialize_lock()
	mut state := ns_scanner_storage(object, true)
	match selector {
		'string' {
			if !state.has_string {
				C.ios_objc_initialize_unlock()
				frame.x[0] = 0
				return true
			}
			text := ns_scanner_text(state.units, 0, state.units.len)
			C.ios_objc_initialize_unlock()
			defer { unsafe { text.free() } }
			frame.x[0] = objc_autorelease(owned_string(text))
			return true
		}
		'charactersToBeSkipped' {
			if !state.skip_enabled {
				frame.x[0] = 0
			} else {
				bits := ns_character_set_bitmap()
				C.memcpy(bits, state.skip, ns_character_set_bytes)
				C.ios_objc_initialize_unlock()
				defer { C.free(bits) }
				frame.x[0] = objc_autorelease(ns_character_set_create(ios_runtime.names['NSCharacterSet'], bits))
				return true
			}
		}
		'setCharactersToBeSkipped:' {
			if frame.x[2] == 0 {
				state.skip_enabled = false
			} else {
				source := ns_character_set_storage(frame.x[2], true)
				C.memcpy(state.skip, source.bits, ns_character_set_bytes)
				state.skip_enabled = true
			}
			frame.x[0] = 0
		}
		'scanLocation' { frame.x[0] = u64(state.location) }
		'setScanLocation:' {
			if frame.x[2] > u64(state.units.len) {
				panic('iOS: scanner location exceeds string length')
			}
			ns_scanner_boundary(state.units, int(frame.x[2]))
			state.location = int(frame.x[2])
			frame.x[0] = 0
		}
		'caseSensitive' { frame.x[0] = u64(state.case_sensitive) }
		'setCaseSensitive:' {
			state.case_sensitive = u8(frame.x[2]) != 0
			frame.x[0] = 0
		}
		'locale' { frame.x[0] = 0 }
		'setLocale:' {
			if frame.x[2] != 0 { panic('iOS: scanner locale is not implemented') }
			frame.x[0] = 0
		}
		'isAtEnd' { frame.x[0] = u64(ns_scanner_start(state) == state.units.len) }
		else {
			C.ios_objc_initialize_unlock()
			return false
		}
	}
	C.ios_objc_initialize_unlock()
	return true
}

// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Public objects contain only an isa. The owned bitmap covers all 17 Unicode
// planes, including surrogate code points. String input is bounded to BMP UTF-8
// because the measured Foundation build folds mixed supplementary strings.
struct FoundationCharacterSet {
mut:
	bits        &u8 = unsafe { nil }
	initialized bool
}

const ns_character_set_limit = u32(0x110000)
const ns_character_set_bytes = 139264

fn ns_character_set_family(cls u64) bool {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return false }
		if info.name == 'NSCharacterSet' { return true }
		current = info.parent
		if current == 0 { return false }
	}
	panic('iOS: cyclic character set superclass chain')
}

fn ns_character_set_require_class(cls u64) {
	if ns_character_set_family(cls) && cls !in [ios_runtime.names['NSCharacterSet'],
		ios_runtime.names['NSMutableCharacterSet']]! {
		panic('iOS: custom character set subclass construction is not implemented')
	}
}

fn ns_character_set_bitmap() &u8 {
	bits := &u8(C.calloc(1, ns_character_set_bytes))
	if bits == unsafe { nil } { panic('iOS: cannot allocate character set bitmap') }
	return bits
}

fn ns_character_set_install(cls u64, mut header ObjHeader) {
	if cls !in [ios_runtime.names['NSCharacterSet'], ios_runtime.names['NSMutableCharacterSet']]! {
		return
	}
	header.character_set = unsafe { &FoundationCharacterSet(C.calloc(1, sizeof(FoundationCharacterSet))) }
	if header.character_set == unsafe { nil } { panic('iOS: cannot allocate character set state') }
	header.character_set.bits = ns_character_set_bitmap()
}

// The runtime lock protects both provenance and the bitmap. Dispatch also
// recognizes the original sidecar after an isa replacement.
fn ns_character_set_storage(object u64, initialized bool) &FoundationCharacterSet {
	header := obj_header(object)
	state := header.character_set
	if state == unsafe { nil } || state.bits == unsafe { nil } || header.destroying || header.destroyed
		|| C.ios_ref_change(unsafe { &header.refs }, 0) <= 0 || header.native_size < 8
		|| header.cls != header.allocation_cls || read64(object) != header.allocation_cls
		|| header.allocation_cls !in [ios_runtime.names['NSCharacterSet'],
			ios_runtime.names['NSMutableCharacterSet']]! {
		panic('iOS: NSCharacterSet requires live owned character set storage')
	}
	if initialized && !state.initialized { panic('iOS: character set requires initialization') }
	return state
}

fn ns_character_set_dispose(mut header ObjHeader) {
	state := header.character_set
	header.character_set = unsafe { nil }
	if state != unsafe { nil } {
		C.free(state.bits)
		C.free(state)
	}
}

fn ns_character_set_set_range(bits &u8, start u32, length u32, add bool) {
	if start > ns_character_set_limit || length > ns_character_set_limit - start {
		panic('iOS: character set data exceeds Unicode domain')
	}
	for scalar := start; scalar < start + length; scalar++ {
		mask := u8(1 << (scalar & 7))
		unsafe {
			if add { bits[scalar >> 3] |= mask } else { bits[scalar >> 3] &= ~mask }
		}
	}
}

// Caller holds the lock; no application code runs while these bytes are read.
// Consume scalar values directly, without allocating a temporary rune array.
fn ns_character_set_string(bits &u8, object u64, add bool) {
	if header := ios_runtime.objects[object] {
		if header.destroying || header.cls != header.allocation_cls || read64(object) != header.allocation_cls
			|| header.allocation_cls !in [ios_runtime.names['NSString'],
				ios_runtime.names['NSMutableString']]!
			|| (header.mutable_string_owned && !header.mutable_string_initialized) {
			panic('iOS: character set input requires a built-in initialized string')
		}
	}
	text := cf_string_compare_text(object) or { panic('iOS: character set input requires a live UTF8 string') }
	if text.len > 65536 { panic('iOS: character set string exceeds byte limit') }
	// Reject before changing any bits, including a supplementary suffix.
	for byte in text {
		if byte >= 0xf0 {
			panic('iOS: supplementary character set string input is not implemented')
		}
	}
	mut offset := 0
	for offset < text.len {
		first := text[offset]
		offset++
		width := if first < 0x80 {
			1
		} else if first < 0xe0 {
			2
		} else if first < 0xf0 {
			3
		} else {
			4
		}
		mut scalar := u32(first & if width == 1 {
			u8(0x7f)
		} else if width == 2 {
			u8(0x1f)
		} else if width == 3 {
			u8(0x0f)
		} else {
			u8(7)
		})
		for _ in 1 .. width {
			scalar = scalar << 6 | u32(text[offset] & 0x3f)
			offset++
		}
		ns_character_set_set_range(bits, scalar, 1, add)
	}
}

fn ns_character_set_initialize(object u64) u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut state := ns_character_set_storage(object, false)
	if state.initialized { panic('iOS: character set is already initialized') }
	state.initialized = true
	return object
}

// Snapshot bitmaps before allocation, which can invoke app constructors. The
// caller owns bits; no source object or sidecar is borrowed across callbacks.
fn ns_character_set_create(cls u64, bits &u8) u64 {
	ns_character_set_require_class(cls)
	if cls !in [ios_runtime.names['NSCharacterSet'], ios_runtime.names['NSMutableCharacterSet']]! {
		panic('iOS: character set factory requires a built-in class')
	}
	result := objc_allocate(cls)
	if result == 0 { return 0 }
	C.ios_objc_initialize_lock()
	mut state := ns_character_set_storage(result, false)
	if state.initialized { panic('iOS: character set constructor changed its storage') }
	C.memcpy(state.bits, bits, ns_character_set_bytes)
	state.initialized = true
	C.ios_objc_initialize_unlock()
	return result
}

fn ns_character_set_copy(object u64, mutable bool, inverted bool) u64 {
	C.ios_objc_initialize_lock()
	state := ns_character_set_storage(object, true)
	if !mutable && !inverted && read64(object) == ios_runtime.names['NSCharacterSet'] {
		objc_retain(object)
		C.ios_objc_initialize_unlock()
		return object
	}
	bits := ns_character_set_bitmap()
	C.memcpy(bits, state.bits, ns_character_set_bytes)
	C.ios_objc_initialize_unlock()
	defer { C.free(bits) }
	if inverted {
		for i in 0 .. ns_character_set_bytes {
			unsafe { bits[i] = ~bits[i] }
		}
	}
	return ns_character_set_create(ios_runtime.names[if mutable {
		'NSMutableCharacterSet'
	} else {
		'NSCharacterSet'
	}], bits)
}

fn ns_character_set_predefined(selector string) bool {
	return selector in ['alphanumericCharacterSet', 'decimalDigitCharacterSet', 'whitespaceCharacterSet',
		'URLQueryAllowedCharacterSet', 'URLHostAllowedCharacterSet', 'URLPathAllowedCharacterSet',
		'illegalCharacterSet', 'controlCharacterSet']!
}

fn ns_character_set_types(name string, meta bool, selector string) ?string {
	if name !in ['NSCharacterSet', 'NSMutableCharacterSet']! { return none }
	if meta {
		if ns_character_set_predefined(selector) { return '@16@0:8' }
		if selector == 'characterSetWithCharactersInString:' { return '@24@0:8@16' }
		return none
	}
	if name == 'NSMutableCharacterSet' {
		if selector in ['addCharactersInString:', 'removeCharactersInString:',
			'formUnionWithCharacterSet:']! {
			return 'v24@0:8@16'
		}
	}
	return match selector {
		'init', 'copy', 'mutableCopy', 'invertedSet' { '@16@0:8' }
		'copyWithZone:', 'mutableCopyWithZone:' { '@24@0:8^{_NSZone=}16' }
		'characterIsMember:' { 'B20@0:8S16' }
		'longCharacterIsMember:' { 'B20@0:8I16' }
		'isSupersetOfSet:' { 'B24@0:8@16' }
		else { return none }
	}
}

fn ns_character_set_unsupported(selector string) bool {
	return selector in ['initWithCharactersInString:', 'characterSetWithRange:',
		'characterSetWithBitmapRepresentation:', 'characterSetWithContentsOfFile:', 'initWithCoder:',
		'encodeWithCoder:', 'supportsSecureCoding', 'bitmapRepresentation', 'hasMemberInPlane:',
		'letterCharacterSet', 'lowercaseLetterCharacterSet', 'uppercaseLetterCharacterSet',
		'capitalizedLetterCharacterSet', 'nonBaseCharacterSet', 'decomposableCharacterSet',
		'whitespaceAndNewlineCharacterSet', 'newlineCharacterSet', 'punctuationCharacterSet',
		'symbolCharacterSet', 'URLUserAllowedCharacterSet', 'URLPasswordAllowedCharacterSet',
		'URLFragmentAllowedCharacterSet', 'addCharactersInRange:', 'removeCharactersInRange:',
		'formIntersectionWithCharacterSet:', 'invert', 'isEqual:', 'hash', 'description',
		'debugDescription']!
}

fn ns_character_set_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	meta := object in ios_runtime.classes
	cls := if meta { object } else { read64(object) }
	mut owned := ns_character_set_family(cls)
	if !meta {
		C.ios_objc_initialize_lock()
		if header := ios_runtime.objects[object] {
			owned = owned || header.character_set != unsafe { nil }
		}
		C.ios_objc_initialize_unlock()
	}
	if !owned { return false }
	if ns_character_set_unsupported(selector) {
		panic('iOS: character set option is not implemented')
	}
	mutable := cls == ios_runtime.names['NSMutableCharacterSet']
	if !mutable && selector in ['addCharactersInString:', 'removeCharactersInString:',
		'formUnionWithCharacterSet:']! {
		panic('iOS: character set mutation requires NSMutableCharacterSet')
	}
	if ns_character_set_types(if mutable { 'NSMutableCharacterSet' } else { 'NSCharacterSet' }, meta, selector) == none {
		return false
	}
	if meta {
		ns_character_set_require_class(cls)
		bits := ns_character_set_bitmap()
		defer { C.free(bits) }
		if selector == 'characterSetWithCharactersInString:' {
			C.ios_objc_initialize_lock()
			ns_character_set_string(bits, frame.x[2], true)
			C.ios_objc_initialize_unlock()
		} else if !ns_character_set_predefined_fill(selector, bits) {
			panic('iOS: missing character set data')
		}
		// Foundation's URL factories return immutable sets even when inherited
		// through NSMutableCharacterSet; other supported factories honor cls.
		factory_cls := if selector.starts_with('URL') {
			ios_runtime.names['NSCharacterSet']
		} else {
			cls
		}
		frame.x[0] = objc_autorelease(ns_character_set_create(factory_cls, bits))
		return true
	}
	if selector in ['copy', 'copyWithZone:', 'mutableCopy', 'mutableCopyWithZone:', 'invertedSet']! {
		if selector.ends_with('WithZone:') && frame.x[2] != 0 {
			panic('iOS: character set copy zones are not implemented')
		}
		result := ns_character_set_copy(object, selector.starts_with('mutableCopy'), selector == 'invertedSet')
		frame.x[0] = if selector == 'invertedSet' { objc_autorelease(result) } else { result }
		return true
	}
	if selector == 'init' {
		frame.x[0] = ns_character_set_initialize(object)
		return true
	}
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	state := ns_character_set_storage(object, true)
	match selector {
		'characterIsMember:', 'longCharacterIsMember:' {
			scalar := if selector == 'characterIsMember:' {
				u32(u16(frame.x[2]))
			} else {
				u32(frame.x[2])
			}
			if scalar >= ns_character_set_limit {
				panic('iOS: character set membership exceeds Unicode domain')
			}
			frame.x[0] = unsafe { u64(state.bits[scalar >> 3] & u8(1 << (scalar & 7)) != 0) }
		}
		'addCharactersInString:', 'removeCharactersInString:' {
			ns_character_set_string(state.bits, frame.x[2], selector == 'addCharactersInString:')
			frame.x[0] = 0
		}
		'formUnionWithCharacterSet:', 'isSupersetOfSet:' {
			other := ns_character_set_storage(frame.x[2], true)
			mut superset := true
			for i in 0 .. ns_character_set_bytes {
				unsafe {
					if selector == 'formUnionWithCharacterSet:' {
						state.bits[i] |= other.bits[i]
					} else if other.bits[i] & ~state.bits[i] != 0 {
						superset = false
						break
					}
				}
			}
			frame.x[0] = if selector == 'isSupersetOfSet:' { u64(superset) } else { u64(0) }
		}
		else { return false }
	}
	return true
}

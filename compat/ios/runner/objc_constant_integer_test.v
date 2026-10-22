// SPDX-License-Identifier: GPL-2.0-or-later
module main

import macho
import os
import crypto.sha256
import math.bits

$if macos {
	#flag -framework Foundation
	#include <objc/runtime.h>
	#include <CoreFoundation/CFString.h>
	#include <CoreFoundation/CFNumber.h>
}
#include <dlfcn.h>
fn C.dlopen(&char, int) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.dlclose(voidptr) int
fn C.sel_registerName(&char) voidptr
fn C.class_getSuperclass(voidptr) voidptr
fn C.class_getInstanceSize(voidptr) usize
fn C.CFNumberCreate(voidptr, i64, voidptr) voidptr
fn C.CFNumberGetTypeID() u64
fn C.CFGetTypeID(voidptr) u64
fn C.CFEqual(voidptr, voidptr) bool
fn C.CFHash(voidptr) u64
fn C.CFRelease(voidptr)
fn C.CFRetain(voidptr) voidptr
fn C.dup2(i32, i32) i32
type ConstantIntegerSend = fn (u64, u64, u64, u64) u64
type ConstantIntegerJsonSend = fn (u64, u64, u64, u64, u64) u64
type ConstantIntegerDouble = fn (u64, u64) f64
type ConstantIntegerFloat = fn (u64, u64) f32
type ConstantIntegerPush = fn () u64
type ConstantIntegerPop = fn (u64)

struct ConstantIntegerApi {
	native bool
	send u64
	push u64
	pop u64
	number_class u64
	json_class u64
}
fn (api ConstantIntegerApi) message(object u64, selector &char, a u64, b u64) u64 {
	$if macos {
		if api.native {
			return unsafe { ConstantIntegerSend(voidptr(api.send))(object, u64(C.sel_registerName(selector)), a, b) }
		}
	}
	mut frame := RegisterFrame{}
	frame.x[0] = object; frame.x[1] = u64(selector); frame.x[2] = a; frame.x[3] = b
	assert objc_dispatch(mut frame, 0) == 0
	return frame.x[0]
}
fn (api ConstantIntegerApi) double(object u64) f64 {
	$if macos { if api.native { return unsafe { ConstantIntegerDouble(voidptr(api.send))(object, u64(C.sel_registerName(c'doubleValue'))) } } }
	mut frame := RegisterFrame{}
	frame.x[0] = object; frame.x[1] = u64(c'doubleValue')
	assert objc_dispatch(mut frame, 0) == 0
	return frame_double(frame, 0)
}
fn (api ConstantIntegerApi) float(object u64) f32 {
	$if macos { if api.native { return unsafe { ConstantIntegerFloat(voidptr(api.send))(object, u64(C.sel_registerName(c'floatValue'))) } } }
	mut frame := RegisterFrame{}
	frame.x[0] = object; frame.x[1] = u64(c'floatValue')
	assert objc_dispatch(mut frame, 0) == 0
	return bits.f32_from_bits(u32(frame.q[0]))
}
fn (api ConstantIntegerApi) equal(left u64, right u64) bool {
	$if macos { if api.native { return C.CFEqual(voidptr(left), voidptr(right)) } }
	return object_equal(left, right)
}
fn (api ConstantIntegerApi) hash(object u64) u64 {
	$if macos { if api.native { return C.CFHash(voidptr(object)) } }
	return cf_hash(object)
}
fn (api ConstantIntegerApi) signed(value i64) u64 {
	$if macos { if api.native { return u64(C.CFNumberCreate(unsafe { nil }, 4, unsafe { &value })) } }
	return cf_number_create(0, 4, u64(unsafe { &value }))
}
fn (api ConstantIntegerApi) unsigned(value u64) u64 {
	$if macos { if api.native { return api.retain(api.message(api.number_class, c'numberWithUnsignedLongLong:', value, 0)) } }
	object := objc_allocate(ios_runtime.names['NSNumber'])
	mut header := obj_header(object)
	header.number = i64(value); header.unsigned_number = true
	return object
}
fn (api ConstantIntegerApi) release(object u64) {
	$if macos { if api.native { C.CFRelease(voidptr(object)); return } }
	objc_release(object)
}
fn (api ConstantIntegerApi) retain(object u64) u64 {
	$if macos { if api.native { return u64(C.CFRetain(voidptr(object))) } }
	return objc_retain(object)
}
fn (api ConstantIntegerApi) pool() u64 {
	$if macos { if api.native { return unsafe { ConstantIntegerPush(voidptr(api.push))() } } }
	return objc_pool_push()
}
fn (api ConstantIntegerApi) drain(pool u64) {
	$if macos { if api.native { unsafe { ConstantIntegerPop(voidptr(api.pop))(pool) }; return } }
	objc_pool_pop(pool)
}

fn (api ConstantIntegerApi) text_and_json(object u64, expected string) {
	for selector in [c'stringValue', c'description']! {
		text := api.message(object, selector, 0, 0)
		assert ctext(api.message(text, c'UTF8String', 0, 0)) == expected
	}
	$if macos {
		if api.native {
			mut error_out := u64(0)
			data := unsafe { ConstantIntegerJsonSend(voidptr(api.send))(api.json_class, u64(C.sel_registerName(c'dataWithJSONObject:options:error:')), object, 4, u64(&error_out)) }
			assert data != 0 && error_out == 0
			bytes := api.message(data, c'bytes', 0, 0)
			length := api.message(data, c'length', 0, 0)
			assert unsafe { tos(&u8(bytes), int(length)) } == expected
			return
		}
	}
	data := json_write(object, 4) or { panic(err) }
	bytes := obj_header(data).data
	assert unsafe { tos(bytes.data, bytes.len) } == expected
	objc_release(data)
}

fn constant_integer_values() [12]i64 {
	return [i64(0), 1, -1, 127, 128, -129, 32767, 32768, -32769, 2147483648, 9223372036854775807, i64(-9223372036854775807) - 1]!
}

fn constant_integer_width(encoding string) int {
	return match encoding { 'c', 'C', 'B' { 1 } 's', 'S' { 2 } 'i', 'I' { 4 } else { 8 } }
}

fn constant_integer_cases(api ConstantIntegerApi, object u64, value i64, encoding string) {
	pool := api.pool()
	// ARM64 returns narrow signed getters through w0, with zeroed upper x0.
	assert api.message(object, c'charValue', 0, 0) == u64(u32(i32(i8(value))))
	assert api.message(object, c'shortValue', 0, 0) == u64(u32(i32(i16(value))))
	assert api.message(object, c'intValue', 0, 0) == u64(u32(value))
	assert i8(api.message(object, c'charValue', 0, 0)) == i8(value)
	assert u8(api.message(object, c'unsignedCharValue', 0, 0)) == u8(value)
	assert i16(api.message(object, c'shortValue', 0, 0)) == i16(value)
	assert u16(api.message(object, c'unsignedShortValue', 0, 0)) == u16(value)
	assert i32(api.message(object, c'intValue', 0, 0)) == i32(value)
	assert u32(api.message(object, c'unsignedIntValue', 0, 0)) == u32(value)
	for selector in [c'longValue', c'unsignedLongValue', c'longLongValue', c'unsignedLongLongValue', c'integerValue', c'unsignedIntegerValue']! {
		assert api.message(object, selector, 0, 0) == u64(value)
	}
	assert api.message(object, c'boolValue', 0, 0) == u64(value != 0)
	assert api.double(object) == f64(value) && api.float(object) == f32(value)
	types := api.message(object, c'objCType', 0, 0)
	assert types == read64(object + 8) && ctext(types) == encoding
	count := constant_integer_width(encoding)
	for selector in [c'getValue:', c'getValue:size:']! {
		mut output := [18]u8{init: 0xa5}
		api.message(object, selector, u64(unsafe { &output[1] }), u64(count))
		assert output[0] == 0xa5
		for i in 0 .. count { assert output[i + 1] == u8(u64(value) >> (i * 8)) }
		for i in count + 1 .. output.len { assert output[i] == 0xa5 }
	}
	for selector in [c'copy', c'copyWithZone:']! { assert api.message(object, selector, 0, 0) == object; api.release(object) }
	equal := api.signed(value)
	unsigned_source := encoding == 'Q' && value < 0
	expected_text := if unsigned_source { u64(value).str() } else { value.str() }
	api.text_and_json(object, expected_text)
	unsafe { expected_text.free() }
	assert api.equal(object, equal) == !unsigned_source && api.equal(equal, object) == !unsigned_source
	if !unsigned_source { assert api.hash(object) == api.hash(equal) }
	assert api.message(object, c'isEqualToNumber:', equal, 0) == u64(!unsigned_source)
	api.release(equal)
	unsigned := api.unsigned(u64(value))
	assert api.equal(object, unsigned) == (value >= 0 || unsigned_source)
	assert api.equal(unsigned, object) == (value >= 0 || unsigned_source)
	if value >= 0 || unsigned_source { assert api.hash(unsigned) == api.hash(object) }
	api.release(unsigned)
	assert api.message(object, c'isEqual:', 0, 0) == 0
	assert api.message(object, c'retainCount', 0, 0) == ~u64(0)
	assert api.message(object, c'_tryRetain', 0, 0) == 1 && api.message(object, c'_isDeallocating', 0, 0) == 0
	for _ in 0 .. 20 { assert api.retain(object) == object; api.release(object); assert api.message(object, c'retain', 0, 0) == object; api.release(object); api.release(object) }
	assert api.message(object, c'autorelease', 0, 0) == object
	api.drain(pool)
	assert api.message(object, c'longLongValue', 0, 0) == u64(value)
}

fn constant_integer_encodings() [11]&char {
	return [c'c', c'C', c's', c'S', c'i', c'I', c'l', c'L', c'q', c'Q', c'B']!
}
fn constant_integer_encoded_values() [11]i64 {
	return [i64(-128), 255, -32768, 65535, -2147483648, 4294967295, -4294967296, 4294967296, -1, -1, 1]!
}

fn constant_integer_raw_unsigned_cases(api ConstantIntegerApi, object u64, encoding string) {
	pool := api.pool()
	// Apple's source width affects raw copying, but full-width getters retain
	// all bits. Only Q gives negative stored bits unsigned numeric equality.
	assert api.message(object, c'longLongValue', 0, 0) == ~u64(0)
	assert api.message(object, c'unsignedLongLongValue', 0, 0) == ~u64(0)
	assert api.message(object, c'charValue', 0, 0) == 0xffffffff
	assert api.message(object, c'shortValue', 0, 0) == 0xffffffff
	assert api.message(object, c'intValue', 0, 0) == 0xffffffff
	assert api.double(object) == -1 && api.float(object) == -1
	expected := match encoding { 'C' { '255' } 'S' { '65535' } 'I' { '4294967295' } 'L', 'Q' { '18446744073709551615' } else { '-1' } }
	api.text_and_json(object, expected)
	mut output := [10]u8{init: 0xa5}
	count := constant_integer_width(encoding)
	api.message(object, c'getValue:size:', u64(unsafe { &output[1] }), u64(count))
	assert output[0] == 0xa5
	for i in 1 .. count + 1 { assert output[i] == 0xff }
	for i in count + 1 .. output.len { assert output[i] == 0xa5 }
	signed := api.signed(-1)
	unsigned := api.unsigned(~u64(0))
	assert api.equal(object, signed) == (encoding != 'Q') && api.equal(signed, object) == (encoding != 'Q')
	assert api.equal(object, unsigned) == (encoding == 'Q') && api.equal(unsigned, object) == (encoding == 'Q')
	// Native C/S/I/L can violate equal-number hash consistency for these raw
	// noncanonical records; this case checks their measured equality only.
	api.release(signed); api.release(unsigned)
	api.drain(pool)
}

fn test_constant_integer_native_layout_and_methods() {
	$if macos {
		foundation := C.dlopen(c'/System/Library/Frameworks/Foundation.framework/Foundation', 2)
		objc := C.dlopen(c'/usr/lib/libobjc.A.dylib', 2)
		assert foundation != unsafe { nil } && objc != unsafe { nil }
		cls := u64(C.dlsym(foundation, c'OBJC_CLASS_$_NSConstantIntegerNumber'))
		assert cls != 0 && C.class_getInstanceSize(voidptr(cls)) == 24
		assert C.class_getSuperclass(voidptr(cls)) == C.dlsym(foundation, c'OBJC_CLASS_$_NSNumber')
		api := ConstantIntegerApi{native: true, send: u64(C.dlsym(objc, c'objc_msgSend')), push: u64(C.dlsym(objc, c'objc_autoreleasePoolPush')), pop: u64(C.dlsym(objc, c'objc_autoreleasePoolPop')), number_class: u64(C.dlsym(foundation, c'OBJC_CLASS_$_NSNumber')), json_class: u64(C.dlsym(foundation, c'OBJC_CLASS_$_NSJSONSerialization'))}
		assert api.send != 0 && api.push != 0 && api.pop != 0 && api.number_class != 0 && api.json_class != 0
		for value in constant_integer_values() {
			mut record := [cls, u64(c'q'), u64(value)]!
			object := u64(unsafe { &record[0] })
			assert C.CFGetTypeID(voidptr(object)) == C.CFNumberGetTypeID()
			constant_integer_cases(api, object, value, 'q')
			assert record[0] == cls && record[1] == u64(c'q') && record[2] == u64(value)
		}
		encodings := constant_integer_encodings()
		for i, value in constant_integer_encoded_values() {
			mut record := [cls, u64(encodings[i]), u64(value)]!
			constant_integer_cases(api, u64(unsafe { &record[0] }), value, ctext(u64(encodings[i])))
			assert record[0] == cls && record[1] == u64(encodings[i]) && record[2] == u64(value)
		}
		for encoding in encodings {
			mut record := [cls, u64(encoding), ~u64(0)]!
			constant_integer_raw_unsigned_cases(api, u64(unsafe { &record[0] }), ctext(u64(encoding)))
		}
		assert C.dlclose(objc) == 0 && C.dlclose(foundation) == 0
		println('IOS-CONSTANT-INTEGER-NATIVE: twenty-four-byte encoding/value record, signed-width accessors, float/double ABI, all eleven scalar encodings, exact guarded getValue writes, source-width description/JSON, unsigned Q equality, CF hash consistency and immortal copies passed')
	}
}

fn test_constant_integer_raw_encoding_equality_and_getters() {
	objc_start()
	page := u64(C.getpagesize())
	base := u64(C.mmap(unsafe { nil }, usize(page), C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert base != u64(-1)
	encodings := constant_integer_encodings()
	for i, encoding in encodings {
		object := base + u64(i) * 24
		text := base + 512 + u64(i) * 4
		unsafe {
			C.memcpy(voidptr(text), encoding, 2)
			*(&u64(object)) = ios_runtime.names['NSConstantIntegerNumber']
			*(&u64(object + 8)) = text
			*(&u64(object + 16)) = ~u64(0)
		}
	}
	m := ObjMetadata{image: macho.Image{segments: [macho.Segment{name: '__DATA_CONST', address: 0x1000, size: page, filesize: page, prot: 1, sections: [macho.Section{name: '__objc_intobj', address: 0x1000, size: 11 * 24}]}]}, layout: macho.Layout{base: 0x1000, size: page}, base: base}
	assert C.mprotect(voidptr(base), usize(page), C.PROT_READ) == 0
	m.constant_integers() or { panic(err) }
	for i, encoding in encodings { constant_integer_raw_unsigned_cases(ConstantIntegerApi{}, base + u64(i) * 24, ctext(u64(encoding))) }
	objc_stop()
	assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 && ios_runtime.image_integers == 0
	assert C.munmap(voidptr(base), usize(page)) == 0
	println('IOS-CONSTANT-INTEGER-RAW: all-bits-set records preserve full signed getters, exact source-width bytes, description/JSON and Q-only unsigned equality across eleven encodings')
}

fn constant_integer_fixture(base u64, page u64) ObjMetadata {
	encodings := constant_integer_encodings()
	for i, value in constant_integer_values() {
		object := base + u64(i) * 24
		unsafe {
			*(&u64(object)) = ios_runtime.names['NSConstantIntegerNumber']
			*(&u64(object + 8)) = base + 1100
			*(&u64(object + 16)) = u64(value)
		}
	}
	for i, value in constant_integer_encoded_values() {
		object := base + u64(i + 12) * 24
		encoding := base + 1120 + u64(i) * 4
		unsafe {
			C.memcpy(voidptr(encoding), encodings[i], 2)
			*(&u64(object)) = ios_runtime.names['NSConstantIntegerNumber']
			*(&u64(object + 8)) = encoding
			*(&u64(object + 16)) = u64(value)
		}
	}
	unsafe {
		C.memcpy(voidptr(base + 1100), c'q', 2)
		*(&u64(base + 640)) = ios_runtime.names['NSConstantArray']
		*(&u64(base + 648)) = 3
		*(&u64(base + 656)) = base + 736
		*(&u64(base + 680)) = ios_runtime.names['NSConstantDictionary']
		*(&u64(base + 688)) = 1
		*(&u64(base + 696)) = 1
		*(&u64(base + 704)) = base + 760
		*(&u64(base + 712)) = base + 768
		*(&u64(base + 736)) = base
		*(&u64(base + 744)) = base + 24
		*(&u64(base + 752)) = base + 528
		*(&u64(base + 760)) = base + 800
		*(&u64(base + 768)) = base + 504
		*(&u64(base + 800)) = ios_runtime.names['NSString']
		*(&u64(base + 808)) = 0x7c8
		*(&u64(base + 816)) = base + 1024
		*(&u64(base + 824)) = 7
		C.memcpy(voidptr(base + 1024), c'integer', 8)
	}
	return ObjMetadata{
		image: macho.Image{segments: [macho.Segment{name: '__DATA_CONST', address: 0x1000, size: page, filesize: page, prot: 1, sections: [macho.Section{name: '__objc_intobj', address: 0x1000, size: 23 * 24}, macho.Section{name: '__objc_arrayobj', address: 0x1280, size: 24}, macho.Section{name: '__objc_dictobj', address: 0x12a8, size: 40}, macho.Section{name: '__cfstring', address: 0x1320, size: 32}]}]}
		layout: macho.Layout{base: 0x1000, size: page}
		base: base
	}
}

fn constant_integer_register(m ObjMetadata) {
	for i in 0 .. 20 {
		match i % 3 {
			0 { m.constant_integers() or { panic(err) } }
			1 { m.constant_arrays() or { panic(err) } }
			else { m.constant_dictionaries() or { panic(err) } }
		}
	}
}
fn constant_integer_reject_bad_destinations_and_destruction(object u64) {
	for operation in 0 .. 11 {
		mut descriptors := [2]i32{}
		assert C.pipe(unsafe { &descriptors[0] }) == 0
		pid := C.ios_fork()
		assert pid >= 0
		if pid == 0 {
			C.close(descriptors[0])
			assert C.dup2(descriptors[1], 2) == 2
			C.close(descriptors[1])
			mut output := [16]u8{}
			match operation {
				0 { objc_destruct_instance(object) }
				1 { ConstantIntegerApi{}.message(object, c'getValue:', 0, 0) }
				2, 3, 4 { ConstantIntegerApi{}.message(object, c'getValue:size:', u64(unsafe { &output[0] }), [u64(0), 0, 0, 7, 16]![operation]) }
				5 { ConstantIntegerApi{}.message(object, c'init', 0, 0) }
				6 { ConstantIntegerApi{}.message(object, c'setValue:forKey:', object, object) }
				7 { ConstantIntegerApi{}.message(object, c'addObject:', object, 0) }
				8 { ConstantIntegerApi{}.message(object, c'setObject:forKeyedSubscript:', object, object) }
				9 { ConstantIntegerApi{}.message(object, c'removeAllObjects', 0, 0) }
				else { ConstantIntegerApi{}.message(object, c'isEqualToNumber:', 0, 0) }
			}
			C._exit(0)
		}
		C.close(descriptors[1])
		mut bytes := [16384]u8{}
		mut length := 0
		for {
			assert length < bytes.len
			count := C.read(descriptors[0], unsafe { &bytes[length] }, usize(bytes.len - length))
			if count == 0 { break }
			if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }
			assert count > 0
			length += int(count)
		}
		C.close(descriptors[0])
		mut status := i32(0)
		assert C.ios_waitpid(pid, &status, 0) == pid && status == 256
		output := unsafe { tos(&bytes[0], length) }
		assert output.contains('iOS:') && !output.contains('runtime error:') && !output.contains('AddressSanitizer')
		expected := if operation == 0 { 'cannot destruct image integer storage' } else if operation < 5 { 'destination' } else if operation == 5 { 'cannot initialize image integer storage' } else if operation == 10 { 'comparison requires a number' } else { 'immutable image integer' }
		assert output.contains(expected), output
	}
}
fn test_constant_integer_readonly_image_registration_and_lifetimes() {
	for _ in 0 .. 2 {
		objc_start()
		page := u64(C.getpagesize())
		base := u64(C.mmap(unsafe { nil }, usize(page), C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
		assert base != u64(-1)
		m := constant_integer_fixture(base, page)
		m.constant_string(base + 800) or { panic(err) }
		ios_runtime.constants[base + 800] = true
		mut snapshot := []u8{len: int(page)}
		unsafe { C.memcpy(snapshot.data, voidptr(base), usize(page)) }
		assert C.mprotect(voidptr(base), usize(page), C.PROT_READ) == 0
		mut workers := []thread{}
		for _ in 0 .. 8 { workers << spawn constant_integer_register(m) }
		workers.wait()
		unsafe { workers.free() }
		objc_register_image(m.image, m.layout, base) or { panic(err) }
		assert ios_runtime.live == 25 && ios_runtime.objects.len == 25
		cls := runtime_symbol('/System/Library/Frameworks/Foundation.framework/Foundation', '_OBJC_CLASS_$_NSConstantIntegerNumber') or { panic(err) }
		assert cls == ios_runtime.names['NSConstantIntegerNumber'] && objc_class_size(cls) == 24
		assert runtime_symbol('/usr/lib/libobjc.A.dylib', '_OBJC_METACLASS_$_NSConstantIntegerNumber') or { panic(err) } == read64(cls)
		for i, pair in [[c'_encoding', c'r*']!, [c'_value', c'q']!]! {
			ivar := objc_find_ivar(cls, pair[0]); assert ivar != 0 && objc_ivar_offset(ivar) == i64((i + 1) * 8)
			assert ctext(u64(objc_ivar_types(ivar))) == ctext(u64(pair[1]))
		}
		assert objc_is_kind(base, ios_runtime.names['NSNumber']) && objc_is_kind(base, ios_runtime.names['NSValue'])
		assert cf_type_id(base) == cf_number_id()
		assert cf_array_value(base + 640, 0) == base && cf_array_value(base + 640, 2) == base + 528
		assert cf_dictionary_value(base + 680, base + 800) == base + 504
		for _ in 0 .. 3 {
			for i, value in constant_integer_values() { constant_integer_cases(ConstantIntegerApi{}, base + u64(i) * 24, value, 'q') }
			encodings := constant_integer_encodings()
			for i, value in constant_integer_encoded_values() { constant_integer_cases(ConstantIntegerApi{}, base + u64(i + 12) * 24, value, ctext(u64(encodings[i]))) }
			assert ios_runtime.live == 25
		}
		constant_integer_reject_bad_destinations_and_destruction(base)
		assert C.memcmp(voidptr(base), snapshot.data, usize(page)) == 0
		for i in 0 .. 23 { assert obj_header(base + u64(i) * 24).refs == 1 && obj_header(base + u64(i) * 24).image_integer }
		// Runtime pool owners must drain while borrowed numeric metadata is live.
		objc_autorelease(base + 24)
		array := objc_allocate(ios_runtime.names['NSArray']); array_append(mut obj_header(array), base + 24)
		objc_autorelease(array)
		objc_stop()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 && ios_runtime.image_integers == 0 && ios_runtime.image_arrays == 0 && ios_runtime.image_dictionaries == 0
		assert C.memcmp(voidptr(base), snapshot.data, usize(page)) == 0
		unsafe { snapshot.free() }
		assert C.munmap(voidptr(base), usize(page)) == 0
	}
	println('IOS-CONSTANT-INTEGER: read-only registration, twelve signed boundaries and eleven encodings, native number/accessor/getValue/copy behavior, numeric collection members, eight concurrent mixed registrations, unchanged bytes and two drained lifetimes passed')
}

fn test_constant_integer_invalid_records_do_not_publish_any_family() {
	objc_start()
	page := u64(C.getpagesize())
	base := u64(C.calloc(1, usize(page)))
	assert base != 0
	owned := objc_allocate(ios_runtime.names['NSObject'])
	for trial in 0 .. 16 {
		m := constant_integer_fixture(base, page)
		ios_runtime.constants[base + 800] = true
		bad := base + 528 // Every earlier integer must remain unpublished.
		unsafe {
			C.memcpy(voidptr(base + 1180), c'z', 2)
			C.memcpy(voidptr(base + 1184), c'qq', 3)
			C.memcpy(voidptr(base + 1188), c'rq', 3)
			match trial {
				0 { *(&u64(bad)) = 1 }
				1 { *(&u64(bad + 8)) = 0 }
				2 { *(&u64(bad + 8)) = 1 }
				3 { *(&u64(bad + 8)) = base + page }
				4 { *(&u64(bad + 8)) = base + page - 1; *(&u8(base + page - 1)) = `q` }
				5 { *(&u64(bad + 8)) = base + 1180 }
				6 { *(&u64(bad + 8)) = base + 1184 }
				7 { *(&u64(bad + 8)) = base + 1188 }
				8 { *(&u64(base + 640)) = 1 }
				9 { *(&u64(base + 744)) = base + 1 }
				10 { *(&u64(base + 744)) = owned }
				11 { *(&u64(base + 688)) = 0 }
				12 { *(&u64(base + 768)) = base + 8 }
				13 { *(&u64(base + 768)) = owned }
				14 { *(&u64(bad + 8)) = owned }
				15 { *(&u64(bad)) = ios_runtime.names['NSNumber'] }
				else {}
			}
		}
		mut rejected := false
		m.constant_integers() or { assert err.msg().contains('integer') || err.msg().contains('array') || err.msg().contains('dictionary') || err.msg().contains('metadata'); rejected = true }
		assert rejected && ios_runtime.live == 1 && ios_runtime.objects.len == 1 && obj_header(owned).refs == 1
		assert ios_runtime.image_integers == 0 && ios_runtime.image_arrays == 0 && ios_runtime.image_dictionaries == 0
	}
	for test in [[u64(0x1000), 23]!, [u64(0x1000), 25]!, [u64(0x1000), 24 * 4097]!, [u64(0x1001), 24]!, [0x1000 + page - 8, u64(24)]!]! {
		m := ObjMetadata{image: macho.Image{segments: [macho.Segment{name: '__DATA', address: 0x1000, size: page, filesize: page, prot: 1, sections: [macho.Section{name: '__objc_intobj', address: test[0], size: test[1]}]}]}, layout: macho.Layout{base: 0x1000, size: page}, base: base}
		mut rejected := false
		m.constant_integers() or { rejected = true }
		assert rejected && ios_runtime.live == 1 && ios_runtime.objects.len == 1 && ios_runtime.image_integers == 0 && ios_runtime.image_arrays == 0 && ios_runtime.image_dictionaries == 0
	}
	objc_release(owned)
	objc_stop()
	C.free(voidptr(base))
	println('IOS-CONSTANT-INTEGER-INVALID: malformed class/encoding pointers, unsupported or incomplete encodings, section alignment/bounds and later array/dictionary failures reject all three metadata families atomically')
}

fn test_constant_integer_conflicting_registration_preserves_original_metadata() {
	objc_start()
	page := u64(C.getpagesize())
	base := u64(C.calloc(1, usize(page)))
	assert base != 0
	m := constant_integer_fixture(base, page)
	ios_runtime.constants[base + 800] = true
	m.constant_integers() or { panic(err) }
	assert ios_runtime.live == 25
	bad := base + 528
	for operation in 0 .. 2 {
		unsafe {
			if operation == 0 { *(&u64(bad + 16)) = 2 }
			else { C.memcpy(voidptr(base + 1160), c'C', 2) }
		}
		mut rejected := false
		m.constant_integers() or { assert err.msg().contains('registration'); rejected = true }
		assert rejected && ios_runtime.live == 25 && ios_runtime.objects.len == 25
		assert obj_header(bad).number == 1 && ConstantIntegerApi{}.message(bad, c'longLongValue', 0, 0) == 1
		unsafe { *(&u64(bad + 16)) = 1; C.memcpy(voidptr(base + 1160), c'B', 2) }
	}
	m.constant_integers() or { panic(err) }
	objc_stop()
	assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 && ios_runtime.image_integers == 0 && ios_runtime.image_arrays == 0 && ios_runtime.image_dictionaries == 0
	C.free(voidptr(base))
	println('IOS-CONSTANT-INTEGER-CONFLICT: changed value and source encoding reject re-registration without replacing published numeric metadata')
}

fn constant_integer_fixture_resolve(_ string, symbol string) !u64 {
	if symbol == '_OBJC_CLASS_$_NSConstantIntegerNumber' { return ios_runtime.names['NSConstantIntegerNumber'] }
	if symbol == '_OBJC_CLASS_$_NSConstantArray' { return ios_runtime.names['NSConstantArray'] }
	if symbol == '_OBJC_CLASS_$_NSConstantDictionary' { return ios_runtime.names['NSConstantDictionary'] }
	if symbol == '___CFConstantStringClassReference' { return ios_runtime.names['NSString'] }
	// Only constant metadata is inspected; app code and other fixups stay unused.
	return 0
}
fn test_constant_integer_records_from_supplied_image() {
	path := os.getenv('VINIX_IOS_CONSTANT_INTEGER_IMAGE')
	if path == '' { return }
	data := os.read_bytes(path) or { panic(err) }
	defer { unsafe { data.free() } }
	image := macho.parse(data) or { panic(err) }
	page := u64(C.getpagesize())
	layout := image.layout(page) or { panic(err) }
	objc_start()
	base := u64(C.mmap(unsafe { nil }, usize(layout.size), C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert base != u64(-1)
	for segment in image.segments {
		if segment.filesize != 0 { unsafe { C.memcpy(voidptr(base + segment.address - layout.base), &data[int(segment.fileoff)], usize(segment.filesize)) } }
	}
	fixups := image.plan_fixups(layout, base, constant_integer_fixture_resolve) or { panic(err) }
	for fixup in fixups { unsafe { *(&u64(base + fixup.offset)) = fixup.value } }
	unsafe { fixups.free() }
	m := ObjMetadata{image: image, layout: layout, base: base}
	for segment in image.segments {
		for section in segment.sections {
			if section.name != '__cfstring' { continue }
			assert section.size % 32 == 0
			for offset := u64(0); offset < section.size; offset += 32 {
				object := base + section.address - layout.base + offset
				m.constant_string(object) or { panic(err) }
				ios_runtime.constants[object] = true
			}
		}
	}
	assert C.mprotect(voidptr(base), usize(layout.size), C.PROT_READ) == 0
	m.constant_integers() or { panic(err) }
	mut count := 0
	mut collections := u64(0)
	for segment in image.segments {
		for section in segment.sections {
			if section.name == '__objc_arrayobj' { collections += section.size / 24 }
			if section.name == '__objc_dictobj' { collections += section.size / 40 }
			if section.name != '__objc_intobj' { continue }
			for offset := u64(0); offset < section.size; offset += 24 {
				object := base + section.address - layout.base + offset
				header := obj_header(object)
				assert header.image_integer && header.number == i64(read64(object + 16))
				assert ctext(read64(object + 8)) == ['I', 'i']![count]
				assert read64(object + 16) == [u64(0x42475241), 1]![count]
				constant_integer_cases(ConstantIntegerApi{}, object, i64(read64(object + 16)), ctext(read64(object + 8)))
				count++
			}
		}
	}
	assert count == 2 && ios_runtime.live == 2 + i64(collections)
	objc_stop()
	assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 && ios_runtime.image_integers == 0 && ios_runtime.image_arrays == 0 && ios_runtime.image_dictionaries == 0
	assert C.munmap(voidptr(base), usize(layout.size)) == 0
	println('IOS-CONSTANT-INTEGER-IMAGE: ${count} actual read-only image records rebased, registered, numerically checked and retired; input SHA256=${sha256.sum(data).hex()}; no app code executed')
}

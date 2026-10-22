// SPDX-License-Identifier: GPL-2.0-or-later
module main

import macho
import os
import crypto.sha256

$if macos {
	#flag -framework Foundation
	#include <objc/runtime.h>
	#include <CoreFoundation/CFString.h>
	#include <CoreFoundation/CFArray.h>
}
#include <dlfcn.h>
fn C.dlopen(&char, int) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.dlclose(voidptr) int
fn C.sel_registerName(&char) voidptr
fn C.class_getSuperclass(voidptr) voidptr
fn C.class_getInstanceSize(voidptr) usize
fn C.CFStringCreateMutable(voidptr, i64) voidptr
fn C.CFStringAppendCString(voidptr, &char, u32)
fn C.CFArrayCreate(voidptr, &voidptr, i64, voidptr) voidptr
fn C.CFArrayGetCount(voidptr) i64
fn C.CFArrayGetValueAtIndex(voidptr, i64) voidptr
fn C.CFArrayGetTypeID() u64
fn C.CFGetTypeID(voidptr) u64
fn C.CFEqual(voidptr, voidptr) bool
fn C.CFHash(voidptr) u64
fn C.CFRelease(voidptr)
fn C.CFRetain(voidptr) voidptr
fn C.CFGetRetainCount(voidptr) i64
fn C.dup2(i32, i32) i32
type ConstantArraySend = fn (u64, u64, u64, u64, u64) u64
type ConstantArrayPush = fn () u64
type ConstantArrayPop = fn (u64)

struct ConstantArrayApi {
	native bool
	send u64
	push u64
	pop u64
	callbacks u64
}
fn (api ConstantArrayApi) message(object u64, selector &char, a u64, b u64, c u64) u64 {
	$if macos {
		if api.native {
			return unsafe { ConstantArraySend(voidptr(api.send))(object, u64(C.sel_registerName(selector)), a, b, c) }
		}
	}
	mut frame := RegisterFrame{}
	frame.x[0] = object; frame.x[1] = u64(selector)
	frame.x[2] = a; frame.x[3] = b; frame.x[4] = c
	assert objc_dispatch(mut frame, 0) == 0
	return frame.x[0]
}
fn (api ConstantArrayApi) count(object u64) i64 {
	$if macos { if api.native { return C.CFArrayGetCount(voidptr(object)) } }
	return cf_array_count(object)
}
fn (api ConstantArrayApi) value(object u64, index i64) u64 {
	$if macos { if api.native { return u64(C.CFArrayGetValueAtIndex(voidptr(object), index)) } }
	return cf_array_value(object, index)
}
fn (api ConstantArrayApi) equal(left u64, right u64) bool {
	$if macos { if api.native { return C.CFEqual(voidptr(left), voidptr(right)) } }
	return object_equal(left, right)
}
fn (api ConstantArrayApi) hash(object u64) u64 {
	$if macos { if api.native { return C.CFHash(voidptr(object)) } }
	return cf_hash(object)
}
fn (api ConstantArrayApi) text(value &char) u64 {
	$if macos {
		if api.native {
			object := C.CFStringCreateMutable(unsafe { nil }, 0)
			C.CFStringAppendCString(object, value, 0x08000100)
			return u64(object)
		}
	}
	return owned_string(ctext(u64(value)))
}
fn (api ConstantArrayApi) array(values [3]u64) u64 {
	$if macos { if api.native { return u64(C.CFArrayCreate(unsafe { nil }, unsafe { &voidptr(&values[0]) }, 3, voidptr(api.callbacks))) } }
	return cf_array_create(0, u64(unsafe { &values[0] }), 3, cf_callbacks_constant('_kCFTypeArrayCallBacks'))
}
fn (api ConstantArrayApi) release(object u64) {
	$if macos { if api.native { C.CFRelease(voidptr(object)); return } }
	objc_release(object)
}
fn (api ConstantArrayApi) retain(object u64) u64 {
	$if macos { if api.native { return u64(C.CFRetain(voidptr(object))) } }
	return objc_retain(object)
}
fn (api ConstantArrayApi) pool() u64 {
	$if macos { if api.native { return unsafe { ConstantArrayPush(voidptr(api.push))() } } }
	return objc_pool_push()
}
fn (api ConstantArrayApi) drain(pool u64) {
	$if macos { if api.native { unsafe { ConstantArrayPop(voidptr(api.pop))(pool) }; return } }
	objc_pool_pop(pool)
}

fn constant_array_cases(api ConstantArrayApi, object u64, values [3]u64) {
	pool := api.pool()
	assert api.count(object) == 3 && api.message(object, c'count', 0, 0, 0) == 3
	assert api.message(object, c'firstObject', 0, 0, 0) == values[0]
	assert api.message(object, c'lastObject', 0, 0, 0) == values[2]
	for i, value in values {
		assert api.value(object, i) == value
		assert api.message(object, c'objectAtIndex:', u64(i), 0, 0) == value
		assert api.message(object, c'objectAtIndexedSubscript:', u64(i), 0, 0) == value
	}
	// An NSRange occupies x3/x4 on Darwin ARM64; sentinels cover exact writes.
	for range in [[u64(0), 0]!, [u64(0), 3]!, [u64(1), 2]!, [u64(3), 0]!]! {
		mut output := [u64(0xfeed), 0xfeed, 0xfeed, 0xcafe]!
		api.message(object, c'getObjects:range:', u64(unsafe { &output[0] }), range[0], range[1])
		for i in 0 .. 3 { assert output[i] == if u64(i) < range[1] { values[int(range[0]) + i] } else { u64(0xfeed) } }
		assert output[3] == 0xcafe
	}
	for batch in [u64(1), 2, 5]! {
		mut state := [8]u64{}
		mut buffer := [u64(0), 0, 0, 0xcafe]!
		mut index := 0
		for _ in 0 .. 5 {
			count := api.message(object, c'countByEnumeratingWithState:objects:count:', u64(unsafe { &state[0] }), u64(unsafe { &buffer[0] }), batch)
			assert count <= batch && count <= 3 && buffer[3] == 0xcafe
			if count == 0 { break }
			assert state[1] != 0 && state[2] != 0
			for i := u64(0); i < count; i++ { assert read64(state[1] + i * 8) == values[index]; index++ }
		}
		assert index == 3
	}
	for selector in [c'copy', c'copyWithZone:']! { assert api.message(object, selector, 0, 0, 0) == object; api.release(object) }
	for selector in [c'mutableCopy', c'mutableCopyWithZone:']! {
		copy := api.message(object, selector, 0, 0, 0)
		assert copy != object && api.count(copy) == 3 && api.equal(copy, object) && api.equal(object, copy)
		assert api.hash(copy) == api.hash(object)
		api.message(copy, c'setObject:atIndexedSubscript:', values[0], 1, 0)
		assert api.value(copy, 1) == values[0] && api.value(object, 1) == values[1] && !api.equal(object, copy)
		api.release(copy)
	}
	equal_values := [api.text(c'alpha'), api.text(c'beta'), api.text(c'gamma')]!
	equal := api.array(equal_values)
	assert equal_values[0] != values[0] && api.equal(equal, object) && api.equal(object, equal)
	assert api.hash(equal) == api.hash(object)
	api.release(equal)
	for value in equal_values { api.release(value) }
	for _ in 0 .. 20 { assert api.retain(object) == object; api.release(object); assert api.message(object, c'retain', 0, 0, 0) == object; api.release(object); api.release(object) }
	assert api.message(object, c'autorelease', 0, 0, 0) == object
	api.drain(pool)
	assert api.count(object) == 3 && api.value(object, 2) == values[2]
}

fn test_constant_array_native_layout_and_methods() {
	$if macos {
		core := C.dlopen(c'/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation', 2)
		objc := C.dlopen(c'/usr/lib/libobjc.A.dylib', 2)
		assert core != unsafe { nil } && objc != unsafe { nil }
		cls := u64(C.dlsym(core, c'OBJC_CLASS_$_NSConstantArray'))
		assert cls != 0 && C.class_getInstanceSize(voidptr(cls)) == 24
		assert C.class_getSuperclass(voidptr(cls)) == C.dlsym(core, c'OBJC_CLASS_$_NSArray')
		api := ConstantArrayApi{native: true, send: u64(C.dlsym(objc, c'objc_msgSend')), push: u64(C.dlsym(objc, c'objc_autoreleasePoolPush')), pop: u64(C.dlsym(objc, c'objc_autoreleasePoolPop')), callbacks: u64(C.dlsym(core, c'kCFTypeArrayCallBacks'))}
		assert api.send != 0 && api.push != 0 && api.pop != 0 && api.callbacks != 0
		values := [api.text(c'alpha'), api.text(c'beta'), api.text(c'gamma')]!
		mut record := [cls, u64(3), u64(unsafe { &values[0] })]!
		object := u64(unsafe { &record[0] })
		assert C.CFGetTypeID(voidptr(object)) == C.CFArrayGetTypeID()
		for _ in 0 .. 10 { constant_array_cases(api, object, values) }
		assert record[0] == cls && record[1] == 3 && record[2] == u64(unsafe { &values[0] })
		for value in values { assert C.CFGetRetainCount(voidptr(value)) == 1; api.release(value) }
		assert C.dlclose(objc) == 0 && C.dlclose(core) == 0
		println('IOS-CONSTANT-ARRAY-NATIVE: twenty-four-byte count/objects record, CF/ObjC indexing, exact NSRange extraction, batched enumeration, CF equality/hash, immortal copies and independent mutable copies passed')
	}
}

fn constant_array_fixture(base u64, page u64) ObjMetadata {
	for i, text in [c'alpha', c'beta', c'gamma']! {
		object := base + 512 + u64(i) * 32
		bytes := base + 1024 + u64(i) * 32
		unsafe {
			*(&u64(object)) = ios_runtime.names['NSString']
			*(&u64(object + 8)) = 0x7c8
			*(&u64(object + 16)) = bytes
			*(&u64(object + 24)) = u64(ctext(u64(text)).len)
			C.memcpy(voidptr(bytes), text, usize(ctext(u64(text)).len + 1))
			*(&u64(base + 256 + u64(i) * 8)) = object
		}
	}
	for i in 0 .. 4 {
		object := base + u64(i) * 24
		unsafe {
			*(&u64(object)) = ios_runtime.names['NSConstantArray']
			*(&u64(object + 8)) = [u64(3), 0, 2, 1]![i]
			*(&u64(object + 16)) = [base + 256, u64(0), base + 280, base + 296]![i]
		}
	}
	unsafe {
		*(&u64(base + 280)) = base
		*(&u64(base + 288)) = base + 128
		*(&u64(base + 296)) = ios_runtime.names['NSObject']
		*(&u64(base + 304)) = base + 512
		*(&u64(base + 312)) = base
		*(&u64(base + 320)) = base + 544
		*(&u64(base + 328)) = base + 48
	}
	for i in 0 .. 2 {
		object := base + 128 + u64(i) * 40
		unsafe {
			*(&u64(object)) = ios_runtime.names['NSConstantDictionary']
			*(&u64(object + 8)) = 1
			*(&u64(object + 16)) = 1
			*(&u64(object + 24)) = base + 304 + u64(i) * 16
			*(&u64(object + 32)) = base + 312 + u64(i) * 16
		}
	}
	return ObjMetadata{
		image: macho.Image{segments: [macho.Segment{name: '__DATA_CONST', address: 0x1000, size: page, filesize: page, prot: 1, sections: [macho.Section{name: '__objc_arrayobj', address: 0x1000, size: 96}, macho.Section{name: '__objc_dictobj', address: 0x1080, size: 80}, macho.Section{name: '__cfstring', address: 0x1200, size: 96}]}]}
		layout: macho.Layout{base: 0x1000, size: page}
		base: base
	}
}
fn constant_array_register(m ObjMetadata) {
	for i in 0 .. 20 { if i & 1 == 0 { m.constant_arrays() or { panic(err) } } else { m.constant_dictionaries() or { panic(err) } } }
}
fn constant_array_reject_mutation_and_bounds(object u64, value u64) {
	for operation in 0 .. 6 {
		mut descriptors := [2]i32{}
		assert C.pipe(unsafe { &descriptors[0] }) == 0
		pid := C.ios_fork()
		assert pid >= 0
		if pid == 0 {
			C.close(descriptors[0])
			assert C.dup2(descriptors[1], 2) == 2
			C.close(descriptors[1])
			match operation {
				0 { ConstantArrayApi{}.message(object, c'addObject:', value, 0, 0) }
				1 { objc_destruct_instance(object) }
				2 { mut output := [4]u64{}; ConstantArrayApi{}.message(object, c'getObjects:range:', u64(unsafe { &output[0] }), 2, 2) }
				3 { cf_array_value(object, -1) }
				4 { ConstantArrayApi{}.message(object, c'setObject:forKeyedSubscript:', value, value, 0) }
				else { mut output := [4]u64{}; ConstantArrayApi{}.message(object, c'getObjects:range:', u64(unsafe { &output[0] }), ~u64(0), 2) }
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
		if operation == 0 || operation == 4 { assert output.contains('immutable image array') }
		else if operation == 1 { assert output.contains('cannot destruct image array storage') }
		else { assert output.contains('range') }
	}
}
fn test_constant_array_readonly_image_registration_and_lifetimes() {
	for _ in 0 .. 2 {
		objc_start()
		page := u64(C.getpagesize())
		base := u64(C.mmap(unsafe { nil }, usize(page), C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
		assert base != u64(-1)
		m := constant_array_fixture(base, page)
		for i in 0 .. 3 { object := base + 512 + u64(i) * 32; m.constant_string(object) or { panic(err) }; ios_runtime.constants[object] = true }
		mut snapshot := []u8{len: int(page)}
		unsafe { C.memcpy(snapshot.data, voidptr(base), usize(page)) }
		assert C.mprotect(voidptr(base), usize(page), C.PROT_READ) == 0
		mut workers := []thread{}
		for _ in 0 .. 8 { workers << spawn constant_array_register(m) }
		workers.wait()
		unsafe { workers.free() }
		objc_register_image(m.image, m.layout, base) or { panic(err) }
		assert ios_runtime.live == 6 && ios_runtime.objects.len == 6
		cls := runtime_symbol('/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation', '_OBJC_CLASS_$_NSConstantArray') or { panic(err) }
		assert cls == ios_runtime.names['NSConstantArray'] && objc_class_size(cls) == 24
		assert runtime_symbol('/System/Library/Frameworks/Foundation.framework/Foundation', '_OBJC_CLASS_$_NSConstantArray') or { panic(err) } == cls
		assert runtime_symbol('/usr/lib/libobjc.A.dylib', '_OBJC_METACLASS_$_NSConstantArray') or { panic(err) } == read64(cls)
		for i, pair in [[c'_count', c'Q']!, [c'_objects', c'r^@']!]! {
			ivar := objc_find_ivar(cls, pair[0]); assert ivar != 0 && objc_ivar_offset(ivar) == i64((i + 1) * 8)
			assert ctext(u64(objc_ivar_types(ivar))) == ctext(u64(pair[1]))
		}
		assert objc_is_kind(base, ios_runtime.names['NSArray']) && !objc_is_kind(base, ios_runtime.names['NSMutableArray'])
		assert cf_type_id(base) == cf_array_id() && cf_array_count(base + 24) == 0
		assert ConstantArrayApi{}.message(base + 24, c'firstObject', 0, 0, 0) == 0
		assert ConstantArrayApi{}.message(base + 24, c'lastObject', 0, 0, 0) == 0
		assert cf_array_value(base + 48, 0) == base && cf_array_value(base + 48, 1) == base + 128
		assert cf_dictionary_value(base + 128, base + 512) == base && cf_dictionary_value(base + 168, base + 544) == base + 48
		assert cf_array_value(base + 72, 0) == ios_runtime.names['NSObject']
		assert !objc_responds(base, c'addObject:') && objc_responds(base, c'getObjects:range:') && objc_responds(base, c'mutableCopyWithZone:')
		values := [base + 512, base + 544, base + 576]!
		for _ in 0 .. 100 { constant_array_cases(ConstantArrayApi{}, base, values); assert ios_runtime.live == 6 }
		constant_array_reject_mutation_and_bounds(base, values[0])
		assert C.memcmp(voidptr(base), snapshot.data, usize(page)) == 0
		for i in 0 .. 4 { assert obj_header(base + u64(i) * 24).refs == 1 }
		// Root-pool owners must finish before either borrowed metadata family retires.
		objc_autorelease(base + 48)
		array := objc_allocate(ios_runtime.names['NSArray']); array_append(mut obj_header(array), base + 48)
		objc_autorelease(array)
		objc_stop()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 && ios_runtime.image_arrays == 0 && ios_runtime.image_dictionaries == 0
		assert C.memcmp(voidptr(base), snapshot.data, usize(page)) == 0
		unsafe { snapshot.free() }
		assert C.munmap(voidptr(base), usize(page)) == 0
	}
	println('IOS-CONSTANT-ARRAY: read-only image registration, native indexing/ranges/copies/CF behavior, nested/empty/class records, eight concurrent mixed registrations, unchanged bytes and two drained lifetimes passed')
}

fn test_constant_array_invalid_image_records_do_not_publish_metadata() {
	objc_start()
	page := u64(C.getpagesize())
	base := u64(C.calloc(1, usize(page)))
	assert base != 0
	owned := objc_allocate(ios_runtime.names['NSObject'])
	disposable := objc_allocate_class(ios_runtime.names['NSObject'], c'DisposableArrayMember', 0)
	objc_register_class(disposable)
	for trial in 0 .. 19 {
		m := constant_array_fixture(base, page)
		for i in 0 .. 3 { ios_runtime.constants[base + 512 + u64(i) * 32] = true }
		bad := base + 24 // The valid first array must not be published first.
		unsafe {
			*(&u64(bad + 8)) = 1
			*(&u64(bad + 16)) = base + 352
			*(&u64(base + 352)) = base + 512
			match trial {
				0 { *(&u64(bad)) = 1 }
				1 { *(&u64(bad + 8)) = 65537 }
				2 { *(&u64(bad + 8)) = ~u64(0) }
				3 { *(&u64(bad + 16)) = 0 }
				4 { *(&u64(bad + 16)) = base + 353 }
				5 { *(&u64(bad + 16)) = base + page - 4 }
				6 { *(&u64(bad + 16)) = base + page }
				7 { *(&u64(base + 352)) = 0 }
				8 { *(&u64(base + 352)) = 1 }
				9 { *(&u64(base + 352)) = owned }
				10 { *(&u64(base + 352)) = disposable }
				11 { *(&u64(base + 352)) = base + 1 }
				12 { *(&u64(base + 352)) = base + 136 }
				13 { *(&u64(base + 352)) = base + 608; *(&u64(base + 608)) = ios_runtime.names['NSString'] }
				14 { *(&u64(base + 168)) = 1 }
				15 { *(&u64(base + 176)) = 0 }
				16 { *(&u64(base + 184)) = 65537 }
				17 { *(&u64(base + 328)) = owned }
				18 { *(&u64(base + 328)) = base + 8 }
				else {}
			}
		}
		mut rejected := false
		m.constant_arrays() or { assert err.msg().contains('array') || err.msg().contains('dictionary') || err.msg().contains('metadata'); rejected = true }
		assert rejected && ios_runtime.live == 1 && ios_runtime.objects.len == 1 && ios_runtime.image_arrays == 0 && ios_runtime.image_dictionaries == 0 && obj_header(owned).refs == 1
	}
	for size in [u64(23), 97, 24 * 4097]! {
		m := ObjMetadata{image: macho.Image{segments: [macho.Segment{name: '__DATA', address: 0x1000, size: page, filesize: page, prot: 1, sections: [macho.Section{name: '__objc_arrayobj', address: 0x1000, size: size}]}]}, layout: macho.Layout{base: 0x1000, size: page}, base: base}
		mut rejected := false
		m.constant_arrays() or { assert err.msg().contains('section'); rejected = true }
		assert rejected && ios_runtime.live == 1 && ios_runtime.objects.len == 1 && ios_runtime.image_arrays == 0 && ios_runtime.image_dictionaries == 0
	}
	objc_release(owned)
	objc_dispose_class(disposable)
	objc_stop()
	C.free(voidptr(base))
	println('IOS-CONSTANT-ARRAY-INVALID: malformed class/count/storage/member pointers, later mixed dictionaries and section bounds rejected before either collection family publishes metadata')
}

fn constant_array_fixture_resolve(_ string, symbol string) !u64 {
	if symbol == '_OBJC_CLASS_$_NSConstantArray' { return ios_runtime.names['NSConstantArray'] }
	if symbol == '_OBJC_CLASS_$_NSConstantDictionary' { return ios_runtime.names['NSConstantDictionary'] }
	if symbol == '___CFConstantStringClassReference' { return ios_runtime.names['NSString'] }
	// Other fixups are never dereferenced or executed by this metadata-only case.
	return 0
}
fn test_constant_array_records_from_supplied_image() {
	path := os.getenv('VINIX_IOS_CONSTANT_ARRAY_IMAGE')
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
	fixups := image.plan_fixups(layout, base, constant_array_fixture_resolve) or { panic(err) }
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
	m.constant_arrays() or { panic(err) }
	mut count := 0
	mut members := 0
	for segment in image.segments {
		for section in segment.sections {
			if section.name != '__objc_arrayobj' { continue }
			for offset := u64(0); offset < section.size; offset += 24 {
				object := base + section.address - layout.base + offset
				header := obj_header(object)
				assert header.image_array && u64(header.items.len) == read64(object + 8)
				assert cf_array_count(object) == header.items.len
				members += header.items.len
				for i, value in header.items { assert cf_array_value(object, i) == value && value == read64(read64(object + 16) + u64(i) * 8) }
				assert objc_retain(object) == object; objc_release(object)
				count++
			}
		}
	}
	assert count == 6 && members == 11
	objc_stop()
	assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 && ios_runtime.image_arrays == 0 && ios_runtime.image_dictionaries == 0
	assert C.munmap(voidptr(base), usize(layout.size)) == 0
	println('IOS-CONSTANT-ARRAY-IMAGE: ${count} actual read-only image records rebased, registered, indexed and retired; input SHA256=${sha256.sum(data).hex()}; no app code executed')
}

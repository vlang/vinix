// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#flag -framework Foundation
	#flag -framework AppKit
	#include <objc/runtime.h>
}
#include <dlfcn.h>
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.dlsym(voidptr, &char) voidptr
type ValueSend = fn (u64, u64, u64, u64) u64
struct ValueRange { location u64 length u64 }
type ValueRangeCtor = fn (u64, u64, ValueRange) u64
type ValueRangeGet = fn (u64, u64) ValueRange
type ValuePointCtor = fn (u64, u64, ObjPoint) u64
type ValuePointGet = fn (u64, u64) ObjPoint
type ValueRectCtor = fn (u64, u64, ObjRect) u64
type ValueRectGet = fn (u64, u64) ObjRect
type ValueTransformCtor = fn (u64, u64, ObjTransform) u64
type ValueTransformGet = fn (u64, u64) ObjTransform
type ValueSizeAlign = fn (&char, &u64, &u64) &char

struct ValueApi {
	native bool
	send u64
	cls u64
	size_align u64
}
fn (api ValueApi) selector(name &char) u64 {
	$if macos { if api.native { return u64(C.sel_registerName(name)) } }
	return u64(name)
}
fn (api ValueApi) message(object u64, name &char, a u64, b u64) u64 { return unsafe { ValueSend(voidptr(api.send))(object, api.selector(name), a, b) } }
fn (api ValueApi) boxed(bytes u64, types &char) u64 { return api.message(api.cls, c'valueWithBytes:objCType:', bytes, u64(types)) }
fn (api ValueApi) encoding(object u64) string { return ctext(api.message(object, c'objCType', 0, 0)) }
fn (api ValueApi) pool() u64 {
	$if macos { if api.native { return api.message(u64(C.objc_getClass(c'NSAutoreleasePool')), c'new', 0, 0) } }
	return objc_pool_push()
}
fn (api ValueApi) release(object u64) { api.message(object, c'release', 0, 0) }
fn (api ValueApi) drain(pool u64) {
	$if macos { if api.native { api.release(pool); return } }
	objc_pool_pop(pool)
}

fn value_cases(api ValueApi) {
	pool := api.pool()
	for types in [c'c', c'C', c's', c'S', c'i', c'I', c'l', c'L', c'q', c'Q', c'B', c'f', c'd', c'@', c'^v', c'r^i', c'[3i]', c'{Pair=ci}', c'{Named="x"c"y"i}', c'{CGPoint=dd}', c'{CGSize=dd}', c'{CGRect={CGPoint=dd}{CGSize=dd}}', c'{_NSRange=QQ}', c'{CGAffineTransform=dddddd}']! {
		mut count := u64(0); mut alignment := u64(0)
		end := unsafe { ValueSizeAlign(voidptr(api.size_align))(types, &count, &alignment) }
		assert u64(end) - u64(types) == u64(ctext(u64(types)).len) && count > 0 && count <= 128 && alignment in [u64(1), 2, 4, 8]
		mut bytes := [128]u8{}; for i in 0 .. int(count) { bytes[i] = u8(i + 1) }
		value := api.boxed(u64(unsafe { &bytes[0] }), types)
		assert api.encoding(value) == ctext(u64(types))
		bytes[0] = 99
		mut copied := [128]u8{}
		api.message(value, c'getValue:size:', u64(unsafe { &copied[0] }), count)
		assert copied[0] == 1 && copied[int(count) - 1] == u8(count)
		copy := api.message(value, c'copyWithZone:', 0, 0); assert copy == value; api.release(copy)
		other := api.boxed(u64(unsafe { &copied[0] }), types)
		assert api.message(value, c'isEqualToValue:', other, 0) == 1 && api.message(value, c'hash', 0, 0) == api.message(other, c'hash', 0, 0)
	}
	assert api.message(api.cls, c'new', 0, 0) == 0
	raw := [u64(1)]!
	unsigned := api.boxed(u64(unsafe { &raw[0] }), c'Q'); signed := api.boxed(u64(unsafe { &raw[0] }), c'q')
	assert api.message(unsigned, c'isEqual:', signed, 0) == 0
	mut padded := [u8(1), 0, 0, 0, 2, 0, 0, 0]!
	first := api.boxed(u64(unsafe { &padded[0] }), c'{Pair=ci}')
	other_tag := api.boxed(u64(unsafe { &padded[0] }), c'{Other=ci}'); assert api.message(first, c'isEqual:', other_tag, 0) == 0
	padded[1] = 99; other_padding := api.boxed(u64(unsafe { &padded[0] }), c'{Pair=ci}'); assert api.message(first, c'isEqual:', other_padding, 0) == 0
	pointer := api.message(api.cls, c'valueWithPointer:', 0x12345678, 0)
	assert api.encoding(pointer) == '^v' && api.message(pointer, c'pointerValue', 0, 0) == 0x12345678
	mut object := u64(0)
	if !api.native { object = ios_runtime.names['NSObject'] }
	$if macos { if api.native { object = u64(C.objc_getClass(c'NSObject')) } }
	referent := api.message(object, c'new', 0, 0)
	boxed_object := api.message(api.cls, c'valueWithNonretainedObject:', referent, 0)
	assert api.encoding(boxed_object) == '^v' && api.message(boxed_object, c'nonretainedObjectValue', 0, 0) == referent
	api.release(referent) // The value never owns or dereferences this address.
	range := ValueRange{7, 9}
	r := unsafe { ValueRangeCtor(voidptr(api.send))(api.cls, api.selector(c'valueWithRange:'), range) }
	assert unsafe { ValueRangeGet(voidptr(api.send))(r, api.selector(c'rangeValue')) } == range
	point := ObjPoint{1.25, -2.5}
	p := unsafe { ValuePointCtor(voidptr(api.send))(api.cls, api.selector(c'valueWithPoint:'), point) }
	assert unsafe { ValuePointGet(voidptr(api.send))(p, api.selector(c'pointValue')) } == point
	rect := ObjRect{1.25, -2.5, 30, 40}
	b := unsafe { ValueRectCtor(voidptr(api.send))(api.cls, api.selector(c'valueWithRect:'), rect) }
	assert unsafe { ValueRectGet(voidptr(api.send))(b, api.selector(c'rectValue')) } == rect
	assert api.message(b, c'isEqualToValue:', api.boxed(u64(unsafe { &rect }), c'{CGRect={CGPoint=dd}{CGSize=dd}}'), 0) == 1
	initialized := api.message(api.message(api.cls, c'alloc', 0, 0), c'initWithBytes:objCType:', u64(unsafe { &raw[0] }), value_type_pointer(c'Q'))
	assert api.encoding(initialized) == 'Q'; api.release(initialized)
	api.drain(pool)
}

fn value_type_pointer(types &char) u64 { return u64(types) } // Avoid the compiler's one-character literal cast bug.

fn test_value_native_boxes() {
	$if macos {
		api := ValueApi{native: true, send: u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend')), cls: u64(C.objc_getClass(c'NSValue')), size_align: u64(C.dlsym(unsafe { voidptr(-2) }, c'NSGetSizeAndAlignment'))}
		value_cases(api)
		println('IOS-VALUE-NATIVE: type layouts, copied buffers, immutable copies, type/padding equality, pointers, ranges and HFA geometry passed')
	}
}

fn value_runtime_api() ValueApi { return ValueApi{send: u64(unsafe { voidptr(C.ios_objc_builtin) }), cls: ios_runtime.names['NSValue'], size_align: u64(unsafe { voidptr(ns_get_size_alignment) })} }
fn test_value_runtime_ownership() {
	for _ in 0 .. 2 {
		objc_start(); api := value_runtime_api()
		assert objc_class_size(api.cls) == 8 && objc_class_size(ios_runtime.names['NSConcreteValue']) == 24
		assert objc_class_parent(ios_runtime.names['NSNumber']) == api.cls
		assert runtime_symbol('/System/Library/Frameworks/Foundation.framework/Foundation', '_OBJC_CLASS_$_NSValue') or { panic(err) } == api.cls
		value_cases(api); assert ios_runtime.live == 0
		pool := api.pool()
		rect := ObjRect{1, 2, 30, 40}
		value := unsafe { ValueRectCtor(voidptr(api.send))(api.cls, api.selector(c'valueWithCGRect:'), rect) }
		assert unsafe { ValueRectGet(voidptr(api.send))(value, api.selector(c'CGRectValue')) } == rect
		transform := ObjTransform{1, 2, 3, 4, 5, 6}
		t := unsafe { ValueTransformCtor(voidptr(api.send))(api.cls, api.selector(c'valueWithCGAffineTransform:'), transform) }
		assert unsafe { ValueTransformGet(voidptr(api.send))(t, api.selector(c'CGAffineTransformValue')) } == transform
		unsigned := cookie_integer(42); mut out := [u64(0)]!
		assert objc_is_kind(unsigned, api.cls)
		api.message(unsigned, c'getValue:size:', u64(unsafe { &out[0] }), 8); assert out[0] == 42 && api.encoding(unsigned) == 'q'
		objc_release(unsigned)
		other := api.boxed(u64(unsafe { &rect }), c'{CGRect={CGPoint=dd}{CGSize=dd}}')
		assert object_equal(value, other)
		api.drain(pool); assert ios_runtime.live == 0
		for _ in 0 .. 100 {
			pool2 := api.pool(); mut bytes := [u64(123)]!
			mut types := [u8(`Q`), 0]!
			boxed := api.boxed(u64(unsafe { &bytes[0] }), unsafe { &char(&types[0]) })
			bytes[0] = 456; types[0] = `q`; assert api.encoding(boxed) == 'Q'
			assert objc_copy_value(boxed, false) == boxed; objc_release(boxed)
			owner := objc_new(ios_runtime.names['NSObject']); objc_set_associated(owner, 7, boxed, 3)
			assert objc_get_associated(owner, 7) == boxed; objc_release(owner)
			objc_set_class(boxed, ios_runtime.names['NSObject']); api.drain(pool2); assert ios_runtime.live == 0
		}
		storage := u64(C.calloc(1, 24)); assert objc_construct_instance(ios_runtime.names['NSConcreteValue'], storage) == storage
		bytes := [u64(99)]!; assert api.message(storage, c'initWithBytes:objCType:', u64(unsafe { &bytes[0] }), value_type_pointer(c'Q')) == storage
		assert objc_destruct_instance(storage) == storage; C.free(unsafe { voidptr(storage) }); assert ios_runtime.live == 0
		objc_stop()
	}
	println('IOS-VALUE: class cluster, NSNumber inheritance/raw access, UIKit CGRect and indirect transform ABI, collection equality, 100 isa-change/association releases and caller storage passed')
}

fn test_value_rejections() {
	objc_start(); api := value_runtime_api()
	for operation in 0 .. 7 {
		mut fds := [2]i32{}; assert C.pipe(unsafe { &fds[0] }) == 0; pid := C.ios_fork(); assert pid >= 0
		if pid == 0 {
			C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1])
			bytes := [u64(1)]!; mut out := [u64(0), 0]!
			match operation {
				0 { api.boxed(u64(unsafe { &bytes[0] }), c'[bad]') }
				1 { api.boxed(u64(unsafe { &bytes[0] }), c'b3') }
				2 { api.boxed(u64(unsafe { &bytes[0] }), c'{Opaque}') }
				3 { api.boxed(0, c'Q') }
				4, 5 { boxed := api.boxed(u64(unsafe { &bytes[0] }), c'Q'); api.message(boxed, c'getValue:size:', u64(unsafe { &out[0] }), if operation == 4 { u64(7) } else { u64(16) }) }
				else { boxed := api.boxed(u64(unsafe { &bytes[0] }), c'Q'); api.message(boxed, c'pointerValue', 0, 0) }
			}
			C._exit(0)
		}
		C.close(fds[1]); mut bytes := [16384]u8{}; mut length := 0
		for { assert length < bytes.len; count := C.read(fds[0], unsafe { &bytes[length] }, usize(bytes.len - length)); if count == 0 { break }; if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }; assert count > 0; length += int(count) }
		C.close(fds[0]); mut status := i32(0); assert C.ios_waitpid(pid, &status, 0) == pid && status == 256
		output := unsafe { tos(&bytes[0], length) }
		assert output.contains(['value array requires a count', 'value type encoding is not implemented', 'opaque value aggregate is not implemented', 'invalid value bytes or complete type encoding', 'value destination size must match exactly', 'value destination size must match exactly', 'value accessor type does not match']![operation]), output
		assert !output.contains('AddressSanitizer') && !output.contains('runtime error:')
	}
	assert ios_runtime.live == 0; objc_stop()
	println('IOS-VALUE-REJECT: malformed array, bitfield/opaque type, nil bytes, short/large destination and mismatched accessor fail explicitly')
}

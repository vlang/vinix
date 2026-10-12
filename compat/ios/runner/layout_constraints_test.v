// SPDX-License-Identifier: GPL-2.0-or-later
module main

import math.bits

$if macos {
	#flag -framework Foundation
	#flag -framework AppKit
	#include <objc/runtime.h>
}
#include <dlfcn.h>
fn C.dlopen(&char, int) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.dlclose(voidptr) int
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.class_getInstanceSize(voidptr) usize
fn C.class_getSuperclass(voidptr) voidptr
fn C.dup2(i32, i32) i32
type LayoutSend = fn (u64, u64, u64) u64
type LayoutMake = fn (u64, u64, u64, i64, i64, u64, i64, f64, f64) u64
type LayoutDouble = fn (u64, u64) f64
type LayoutFloat = fn (u64, u64) f32
type LayoutSetDouble = fn (u64, u64, f64)
type LayoutSetFloat = fn (u64, u64, f32)
type LayoutAnchorMake = fn (u64, u64, u64, f64, f64) u64
type LayoutPush = fn () u64
type LayoutPop = fn (u64)

struct LayoutApi {
	native bool
	send u64
	constraint_class u64
	view_class u64
	string_class u64
	push u64
	pop u64
}
fn (api LayoutApi) selector(name &char) u64 {
	$if macos { if api.native { return u64(C.sel_registerName(name)) } }
	return u64(name)
}
fn (api LayoutApi) message(object u64, name &char, value u64) u64 {
	return unsafe { LayoutSend(voidptr(api.send))(object, api.selector(name), value) }
}
fn (api LayoutApi) get_double(object u64, name &char) f64 {
	return unsafe { LayoutDouble(voidptr(api.send))(object, api.selector(name)) }
}
fn (api LayoutApi) get_float(object u64, name &char) f32 {
	return unsafe { LayoutFloat(voidptr(api.send))(object, api.selector(name)) }
}
fn (api LayoutApi) set_double(object u64, name &char, value f64) {
	unsafe { LayoutSetDouble(voidptr(api.send))(object, api.selector(name), value) }
}
fn (api LayoutApi) set_float(object u64, name &char, value f32) {
	unsafe { LayoutSetFloat(voidptr(api.send))(object, api.selector(name), value) }
}
fn (api LayoutApi) factory(first u64, a i64, relation i64, second u64, b i64, multiplier f64, constant f64) u64 {
	return unsafe { LayoutMake(voidptr(api.send))(api.constraint_class, api.selector(c'constraintWithItem:attribute:relatedBy:toItem:attribute:multiplier:constant:'), first, a, relation, second, b, multiplier, constant) }
}
fn (api LayoutApi) anchor_factory(anchor u64, name &char, other u64, multiplier f64, constant f64) u64 {
	return unsafe { LayoutAnchorMake(voidptr(api.send))(anchor, api.selector(name), other, multiplier, constant) }
}
fn (api LayoutApi) pool() u64 {
	$if macos { if api.native { return unsafe { LayoutPush(voidptr(api.push))() } } }
	return objc_pool_push()
}
fn (api LayoutApi) drain(pool u64) {
	$if macos { if api.native { unsafe { LayoutPop(voidptr(api.pop))(pool) }; return } }
	objc_pool_pop(pool)
}
fn (api LayoutApi) refs(object u64) i64 {
	$if macos { if api.native { return i64(api.message(object, c'retainCount', 0)) } }
	return obj_header(object).refs
}

fn layout_cases(api LayoutApi) {
	pool := api.pool()
	first := api.message(api.view_class, c'new', 0)
	second := api.message(api.view_class, c'new', 0)
	for relation in [i64(-1), 0, 1]! {
		for attribute in [i64(1), 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]! {
			constraint := api.factory(first, attribute, relation, second, attribute, 1.234567890123, -17.625)
			assert constraint != 0
			assert api.message(constraint, c'firstItem', 0) == first && api.message(constraint, c'secondItem', 0) == second
			assert api.message(constraint, c'firstAttribute', 0) == u64(attribute) && api.message(constraint, c'secondAttribute', 0) == u64(attribute)
			assert i64(api.message(constraint, c'relation', 0)) == relation
			assert api.get_double(constraint, c'multiplier') == f64(f32(1.234567890123))
			assert api.get_double(constraint, c'constant') == -17.625 && api.get_float(constraint, c'priority') == 1000
			assert api.message(constraint, c'isActive', 0) == 0 && api.message(constraint, c'shouldBeArchived', 0) == 0 && api.message(constraint, c'identifier', 0) == 0
			api.set_double(constraint, c'setConstant:', 33.125)
			assert api.get_double(constraint, c'constant') == 33.125
			for priority in [f32(0.125), 1, 751.125, 999, 1000]! {
				api.set_float(constraint, c'setPriority:', priority)
				assert api.get_float(constraint, c'priority') == priority
			}
			api.message(constraint, c'setShouldBeArchived:', 1)
			assert api.message(constraint, c'shouldBeArchived', 0) == 1
			api.message(constraint, c'setShouldBeArchived:', 0)
			api.message(constraint, c'setActive:', 0)
			identifier := api.message(api.string_class, c'stringWithUTF8String:', u64(c'layout-identifier'))
			api.message(constraint, c'setIdentifier:', identifier)
			stored := api.message(constraint, c'identifier', 0)
			assert stored != 0 && ctext(api.message(stored, c'UTF8String', 0)) == 'layout-identifier'
			api.message(constraint, c'setIdentifier:', 0)
			assert api.message(constraint, c'identifier', 0) == 0
		}
	}
	for pair in [[c'widthAnchor', c'heightAnchor']!, [c'leadingAnchor', c'trailingAnchor']!, [c'topAnchor', c'bottomAnchor']!]! {
		a := api.message(first, pair[0], 0); b := api.message(second, pair[1], 0)
		assert a != 0 && b != 0 && api.message(first, pair[0], 0) == a
		for factory in [c'constraintEqualToAnchor:constant:', c'constraintGreaterThanOrEqualToAnchor:constant:', c'constraintLessThanOrEqualToAnchor:constant:']! {
			constraint := api.anchor_factory(a, factory, b, 12.75, 0)
			assert api.message(constraint, c'firstAnchor', 0) == a && api.message(constraint, c'secondAnchor', 0) == b
			assert api.get_double(constraint, c'constant') == 12.75 && api.get_double(constraint, c'multiplier') == 1
		}
	}
	width := api.message(first, c'widthAnchor', 0)
	height := api.message(second, c'heightAnchor', 0)
	constraint := api.anchor_factory(width, c'constraintEqualToAnchor:multiplier:constant:', height, 1.234567890123, 8.25)
	assert api.get_double(constraint, c'multiplier') == f64(f32(1.234567890123)) && api.get_double(constraint, c'constant') == 8.25
	one := api.factory(first, 7, 0, 0, 0, 2.125, 31.5)
	assert api.get_double(one, c'multiplier') == 1 && api.message(one, c'secondAnchor', 0) == 0 && api.message(one, c'secondAttribute', 0) == 0
	assert api.message(one, c'firstAnchor', 0) == width
	single := api.anchor_factory(width, c'constraintEqualToConstant:', 0, 44.75, 0)
	assert api.get_double(single, c'constant') == 44.75 && api.message(single, c'secondItem', 0) == 0
	empty := api.message(api.constraint_class, c'new', 0)
	assert api.get_double(empty, c'multiplier') == 1 && api.get_float(empty, c'priority') == 1000 && api.get_double(empty, c'constant') == 0
	assert api.message(empty, c'firstItem', 0) == 0 && api.message(empty, c'firstAttribute', 0) == 0
	api.message(empty, c'release', 0)
	assert api.refs(first) == 1 && api.refs(second) == 1
	api.drain(pool)
	api.message(first, c'release', 0); api.message(second, c'release', 0)
}

fn test_layout_native_factories_and_scalar_abi() {
	$if macos {
		library := C.dlopen(c'/usr/lib/libobjc.A.dylib', 2)
		assert library != unsafe { nil }
		constraint := u64(C.objc_getClass(c'NSLayoutConstraint')); anchor := C.objc_getClass(c'NSLayoutAnchor')
		assert constraint != 0 && C.class_getInstanceSize(voidptr(constraint)) == 80 && C.class_getInstanceSize(anchor) == 64
		assert C.class_getSuperclass(voidptr(constraint)) == C.objc_getClass(c'NSObject')
		api := LayoutApi{native: true, send: u64(C.dlsym(library, c'objc_msgSend')), constraint_class: constraint, view_class: u64(C.objc_getClass(c'NSView')), string_class: u64(C.objc_getClass(c'NSString')), push: u64(C.dlsym(library, c'objc_autoreleasePoolPush')), pop: u64(C.dlsym(library, c'objc_autoreleasePoolPop'))}
		assert api.view_class != 0 && api.string_class != 0
		layout_cases(api)
		assert C.dlclose(library) == 0
		println('IOS-LAYOUT-NATIVE: 80/64-byte class records, twelve attributes and three relations, float multiplier rounding and priority ABI, double constants, identifiers, flags, cached anchors, single-item normalization and borrowed view ownership passed')
	}
}

fn test_layout_records_ownership_and_repeated_lifetimes() {
	for _ in 0 .. 2 {
		objc_start()
		assert sizeof(AbiLayoutConstraint) == 80 && sizeof(AbiLayoutAnchor) == 64
		cls := runtime_symbol('/System/Library/Frameworks/Foundation.framework/Foundation', '_OBJC_CLASS_$_NSLayoutConstraint') or { panic(err) }
		assert cls == ios_runtime.names['NSLayoutConstraint'] && objc_class_size(cls) == 80
		assert objc_class_parent(cls) == ios_runtime.names['NSObject']
		for pair in [[c'priority', c'f16@0:8']!, [c'setPriority:', c'v20@0:8f16']!, [c'constant', c'd16@0:8']!, [c'setConstant:', c'v24@0:8d16']!]! {
			method := objc_instance_method(cls, u64(pair[0]))
			assert method != 0 && ctext(u64(objc_method_types(method))) == ctext(u64(pair[1]))
		}
		api := LayoutApi{send: u64(unsafe { voidptr(C.ios_objc_builtin) }), constraint_class: cls, view_class: ios_runtime.names['UIView'], string_class: ios_runtime.names['NSString']}
		for _ in 0 .. 10 {
			layout_cases(api)
			assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 && ios_runtime.weak.len == 0
		}
		pool := objc_pool_push()
		view := objc_new(api.view_class)
		constraint := objc_retain(api.factory(view, 7, 0, 0, 0, 1, 12))
		anchor := api.message(constraint, c'firstAnchor', 0)
		assert obj_header(view).refs == 1
		objc_release(view)
		assert api.message(constraint, c'firstItem', 0) == 0 && api.message(constraint, c'firstAttribute', 0) == 7
		assert api.message(constraint, c'firstAnchor', 0) == anchor
		objc_pool_pop(pool)
		assert ios_runtime.live == 2
		objc_release(constraint)
		assert ios_runtime.live == 0 && ios_runtime.weak.len == 0
		objc_stop()
	}
	println('IOS-LAYOUT: actual message trampoline scalar/factory ABI, selector metadata, cached anchors, zeroing borrowed views, repeated drained lifetimes and balanced sidecar/cache ownership passed')
}

fn test_layout_rejects_missing_solver_and_invalid_inputs() {
	objc_start()
	defer { objc_stop() }
	pool := objc_pool_push()
	view := objc_new(ios_runtime.names['UIView'])
	constraint := layout_constraint_from_items(ios_runtime.names['NSLayoutConstraint'], view, 7, 0, 0, 0, 1, 12)
	array := objc_allocate(ios_runtime.names['NSArray'])
	array_append(mut obj_header(array), constraint)
	for operation in 0 .. 6 {
		mut descriptors := [2]i32{}
		assert C.pipe(unsafe { &descriptors[0] }) == 0
		pid := C.ios_fork(); assert pid >= 0
		if pid == 0 {
			C.close(descriptors[0]); assert C.dup2(descriptors[1], 2) == 2; C.close(descriptors[1])
			mut frame := RegisterFrame{}
			match operation {
				0 { frame.x[2] = 1; assert layout_dispatch(constraint, 'setActive:', mut frame) }
				1 { frame.x[2] = array; assert layout_dispatch(ios_runtime.names['NSLayoutConstraint'], 'activateConstraints:', mut frame) }
				2 { frame.q[0] = u64(bits.f32_bits(f32(1001))); assert layout_dispatch(constraint, 'setPriority:', mut frame) }
				3 { layout_constraint_from_items(ios_runtime.names['NSLayoutConstraint'], view, 1, 0, 0, 0, 1, 0) }
				4 {
					frame.x[2] = layout_anchor(view, 3)
					assert layout_dispatch(layout_anchor(view, 1), 'constraintEqualToAnchor:', mut frame)
				}
				else { assert layout_dispatch(constraint, 'setPriority:', mut frame) }
			}
			C._exit(0)
		}
		C.close(descriptors[1]); mut bytes := [16384]u8{}; mut length := 0
		for {
			assert length < bytes.len
			count := C.read(descriptors[0], unsafe { &bytes[length] }, usize(bytes.len - length))
			if count == 0 { break }
			if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }
			assert count > 0; length += int(count)
		}
		C.close(descriptors[0]); mut status := i32(0)
		assert C.ios_waitpid(pid, &status, 0) == pid && status == 256
		output := unsafe { tos(&bytes[0], length) }
		expected := ['constraint activation requires a solver', 'constraint activation requires a solver', 'invalid layout priority', 'invalid item-less layout dimension', 'incompatible layout anchor axes', 'invalid layout priority']![operation]
		assert output.contains(expected) && !output.contains('runtime error:') && !output.contains('AddressSanitizer')
	}
	objc_release(array); objc_pool_pop(pool); objc_release(view)
	assert ios_runtime.live == 0 && ios_runtime.weak.len == 0
	println('IOS-LAYOUT-REJECT: missing solver, invalid priority/dimension and incompatible axes fail explicitly without changing parent state')
}

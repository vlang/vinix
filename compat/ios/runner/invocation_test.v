// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#flag -framework Foundation
	#include <objc/runtime.h>
}
#include <dlfcn.h>
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.objc_allocateClassPair(voidptr, &char, usize) voidptr
fn C.objc_registerClassPair(voidptr)
fn C.class_addMethod(voidptr, voidptr, voidptr, &char) bool
fn C.class_getInstanceMethod(voidptr, voidptr) voidptr
fn C.class_getClassMethod(voidptr, voidptr) voidptr
fn C.method_getTypeEncoding(voidptr) &char
fn C.class_getInstanceSize(voidptr) usize
fn C.class_getSuperclass(voidptr) voidptr
fn C.objc_storeWeak(&u64, voidptr) voidptr

type InvocationFixtureSend = fn (u64, u64, u64, u64, u64) u64
struct InvocationFixtureApi { native bool send u64 }
__global invocation_fixture_api = InvocationFixtureApi{}
__global invocation_fixture_observed = [4]u64{}
__global invocation_fixture_calls = 0
fn (api InvocationFixtureApi) cls(name string) u64 {
	$if macos { if api.native { return u64(C.objc_getClass(name.str)) } }
	return ios_runtime.names[name]
}
fn (api InvocationFixtureApi) selector(name &char) u64 {
	$if macos { if api.native { return u64(C.sel_registerName(name)) } }
	return u64(name)
}
fn (api InvocationFixtureApi) message(object u64, name &char, a u64, b u64, c u64) u64 {
	return unsafe { InvocationFixtureSend(voidptr(api.send))(object, api.selector(name), a, b, c) }
}
fn (api InvocationFixtureApi) pool() u64 {
	$if macos { if api.native { return api.message(api.cls('NSAutoreleasePool'), c'new', 0, 0, 0) } }
	return objc_pool_push()
}
fn (api InvocationFixtureApi) drain(pool u64) {
	$if macos { if api.native { api.message(pool, c'drain', 0, 0, 0); return } }
	objc_pool_pop(pool)
}
fn (api InvocationFixtureApi) weak(slot &u64, object u64) {
	$if macos { if api.native { C.objc_storeWeak(slot, unsafe { voidptr(object) }); return } }
	objc_store_weak(slot, object)
}
fn (api InvocationFixtureApi) destroy_weak(slot &u64) {
	$if macos { if api.native { C.objc_storeWeak(slot, unsafe { nil }); return } }
	objc_destroy_weak(slot)
}
fn (api InvocationFixtureApi) text(pointer u64) string { return unsafe { (&char(voidptr(pointer))).vstring() } }
fn (api InvocationFixtureApi) signature(types &char) u64 { return api.message(api.cls('NSMethodSignature'), c'signatureWithObjCTypes:', u64(types), 0, 0) }
fn (api InvocationFixtureApi) invocation(types &char) u64 { return api.message(api.cls('NSInvocation'), c'invocationWithMethodSignature:', api.signature(types), 0, 0) }
fn (api InvocationFixtureApi) set_argument(object u64, bytes voidptr, index int) { api.message(object, c'setArgument:atIndex:', u64(bytes), u64(index), 0) }
fn (api InvocationFixtureApi) get_argument(object u64, bytes voidptr, index int) { api.message(object, c'getArgument:atIndex:', u64(bytes), u64(index), 0) }
fn (api InvocationFixtureApi) add_method(cls u64, name &char, imp u64, types &char) {
	$if macos { if api.native { assert C.class_addMethod(unsafe { voidptr(cls) }, unsafe { voidptr(api.selector(name)) }, unsafe { voidptr(imp) }, types); return } }
	assert objc_add_method(cls, u64(name), imp, types)
}
fn (api InvocationFixtureApi) new_target_class() u64 {
	mut cls := u64(0)
	$if macos { if api.native { cls = u64(C.objc_allocateClassPair(unsafe { voidptr(api.cls('NSObject')) }, c'VinixInvocationFixtureTarget', 0)) } }
	if !api.native { cls = objc_allocate_class(api.cls('NSObject'), c'VinixInvocationFixtureTarget', 0) }
	assert cls != 0
	for entry in [
		[u64(c'signedByte:'), u64(unsafe { voidptr(invocation_fixture_i8) }), u64(c'c20@0:8c16')]!,
		[u64(c'unsignedByte:'), u64(unsafe { voidptr(invocation_fixture_u8) }), u64(c'C20@0:8C16')]!,
		[u64(c'signedShort:'), u64(unsafe { voidptr(invocation_fixture_i16) }), u64(c's20@0:8s16')]!,
		[u64(c'unsignedShort:'), u64(unsafe { voidptr(invocation_fixture_u16) }), u64(c'S20@0:8S16')]!,
		[u64(c'signedInt:'), u64(unsafe { voidptr(invocation_fixture_i32) }), u64(c'i20@0:8i16')]!,
		[u64(c'unsignedInt:'), u64(unsafe { voidptr(invocation_fixture_u32) }), u64(c'I20@0:8I16')]!,
		[u64(c'signedLong:'), u64(unsafe { voidptr(invocation_fixture_i32) }), u64(c'l20@0:8l16')]!,
		[u64(c'unsignedLong:'), u64(unsafe { voidptr(invocation_fixture_u32) }), u64(c'L20@0:8L16')]!,
		[u64(c'signedWord:'), u64(unsafe { voidptr(invocation_fixture_i64) }), u64(c'q24@0:8q16')]!,
		[u64(c'unsignedWord:'), u64(unsafe { voidptr(invocation_fixture_u64) }), u64(c'Q24@0:8Q16')]!,
		[u64(c'boolean:'), u64(unsafe { voidptr(invocation_fixture_u8) }), u64(c'B20@0:8B16')]!,
		[u64(c'float:'), u64(unsafe { voidptr(invocation_fixture_float) }), u64(c'f20@0:8f16')]!,
		[u64(c'double:'), u64(unsafe { voidptr(invocation_fixture_double) }), u64(c'd24@0:8d16')]!,
		[u64(c'pointer:'), u64(unsafe { voidptr(invocation_fixture_u64) }), u64(c'^v24@0:8^v16')]!,
		[u64(c'object:'), u64(unsafe { voidptr(invocation_fixture_u64) }), u64(c'@24@0:8@16')]!,
		[u64(c'class:'), u64(unsafe { voidptr(invocation_fixture_u64) }), u64(c'#24@0:8#16')]!,
		[u64(c'selector:'), u64(unsafe { voidptr(invocation_fixture_u64) }), u64(c':24@0:8:16')]!,
		[u64(c'cstring:'), u64(unsafe { voidptr(invocation_fixture_u64) }), u64(c'*24@0:8*16')]!,
		[u64(c'mixed:double:float:object:'), u64(unsafe { voidptr(invocation_fixture_mixed) }), u64(c'd48@0:8q16d24f32@40')]!,
		[u64(c'notification:payload:completion:'), u64(unsafe { voidptr(invocation_fixture_notification) }), u64(c'v40@0:8@16@24@?32')]!,
		[u64(c'trackingAuthorizationStatus'), u64(unsafe { voidptr(invocation_fixture_tracking) }), u64(c'q16@0:8')]!,
		[u64(c'allRegisters:b:c:d:e:f:g:h:i:j:k:l:m:n:'), u64(unsafe { voidptr(invocation_fixture_all_registers) }), u64(c'd128@0:8q16q24q32q40q48q56d64d72d80d88d96d104d112d120')]!,
	]! { api.add_method(cls, unsafe { &char(entry[0]) }, entry[1], unsafe { &char(entry[2]) }) }
	$if macos { if api.native { C.objc_registerClassPair(unsafe { voidptr(cls) }) } }
	if !api.native { objc_register_class(cls) }
	return cls
}
fn invocation_fixture_i8(object u64, selector &char, value i8) i8 { return value }
fn invocation_fixture_u8(object u64, selector &char, value u8) u8 { return value }
fn invocation_fixture_i16(object u64, selector &char, value i16) i16 { return value }
fn invocation_fixture_u16(object u64, selector &char, value u16) u16 { return value }
fn invocation_fixture_i32(object u64, selector &char, value i32) i32 { return value }
fn invocation_fixture_u32(object u64, selector &char, value u32) u32 { return value }
fn invocation_fixture_i64(object u64, selector &char, value i64) i64 { return value }
fn invocation_fixture_u64(object u64, selector &char, value u64) u64 { return value }
fn invocation_fixture_float(object u64, selector &char, value f32) f32 { return value * f32(2) }
fn invocation_fixture_double(object u64, selector &char, value f64) f64 { return value * 2 }
fn invocation_fixture_mixed(object u64, selector &char, integer i64, real f64, single f32, argument u64) f64 {
	assert integer == -37 && real == -2.5 && single == f32(1.25) && argument == object
	return f64(integer) + real + f64(single)
}
fn invocation_fixture_notification(object u64, selector &char, application u64, payload u64, completion u64) {
	invocation_fixture_observed = [object, application, payload, completion]!
	invocation_fixture_calls++
}
fn invocation_fixture_tracking(object u64, selector &char) i64 { invocation_fixture_calls++; return 3 }
fn invocation_fixture_all_registers(object u64, selector &char, a i64, b i64, c i64, d i64, e i64, f i64, g f64, h f64, i f64, j f64, k f64, l f64, m f64, n f64) f64 {
	assert [a, b, c, d, e, f]! == [i64(-1), 2, -3, 4, -5, 6]!
	assert [g, h, i, j, k, l, m, n]! == [f64(0.5), 1.5, 2.5, 3.5, -4.5, -5.5, -6.5, -7.5]!
	return f64(a + b + c + d + e + f) + g + h + i + j + k + l + m + n
}

fn invocation_fixture_signatures(api InvocationFixtureApi) {
	for types, expected in {
		'v16@0:8': ['v', '@', ':'],
		'rq40@0:8n^v16o^q24N@32': ['rq', '@', ':', 'n^v', 'o^q', 'N@'],
		'@24@0:8@?16': ['@', '@', ':', '@?'],
		'@"NSString"24@0:8@"NSObject<NSCopying>"16': ['@"NSString"', '@', ':', '@"NSObject<NSCopying>"'],
	} {
		signature := api.signature(types.str); assert signature != 0
		assert api.text(api.message(signature, c'methodReturnType', 0, 0, 0)) == expected[0]
		assert api.message(signature, c'numberOfArguments', 0, 0, 0) == u64(expected.len - 1)
		assert api.message(signature, c'isOneway', 0, 0, 0) == 0
		for i in 1 .. expected.len { assert api.text(api.message(signature, c'getArgumentTypeAtIndex:', u64(i - 1), 0, 0)) == expected[i] }
	}
	oneway := api.signature(c'Vv24@0:8@16'); assert api.message(oneway, c'isOneway', 0, 0, 0) == 1
	for types, size in {'c20@0:8c16': 1, 'C20@0:8C16': 1, 's20@0:8s16': 2, 'S20@0:8S16': 2, 'i20@0:8i16': 4, 'I20@0:8I16': 4, 'l20@0:8l16': 4, 'L20@0:8L16': 4, 'q24@0:8q16': 8, 'Q24@0:8Q16': 8, 'B20@0:8B16': 1, 'f20@0:8f16': 4, 'd24@0:8d16': 8, '^v24@0:8^v16': 8, '*24@0:8*16': 8, '@24@0:8@16': 8, '#24@0:8#16': 8, ':24@0:8:16': 8, 'v16@0:8': 0} {
		signature := api.signature(types.str)
		assert api.message(signature, c'methodReturnLength', 0, 0, 0) == u64(size), types
		assert api.message(signature, c'frameLength', 0, 0, 0) == 224
	}
	mut source := [u8(`q`), `2`, `4`, `@`, `0`, `:`, `8`, `q`, `1`, `6`, 0]!
	signature := api.signature(unsafe { &char(&source[0]) }); source[0] = `v`; source[7] = `i`
	assert api.text(api.message(signature, c'methodReturnType', 0, 0, 0)) == 'q'
	assert api.text(api.message(signature, c'getArgumentTypeAtIndex:', 2, 0, 0)) == 'q'
}

fn invocation_fixture_buffers(api InvocationFixtureApi, target u64) {
	for entry in [
		[u64(c'signedByte:'), u64(c'c20@0:8c16'), u64(1), u64(0x83)]!,
		[u64(c'unsignedByte:'), u64(c'C20@0:8C16'), u64(1), u64(0xe7)]!,
		[u64(c'signedShort:'), u64(c's20@0:8s16'), u64(2), u64(0x8013)]!,
		[u64(c'unsignedShort:'), u64(c'S20@0:8S16'), u64(2), u64(0xf123)]!,
		[u64(c'signedInt:'), u64(c'i20@0:8i16'), u64(4), u64(0x80000037)]!,
		[u64(c'unsignedInt:'), u64(c'I20@0:8I16'), u64(4), u64(0xf1234567)]!,
		[u64(c'signedLong:'), u64(c'l20@0:8l16'), u64(4), u64(0x80000037)]!,
		[u64(c'unsignedLong:'), u64(c'L20@0:8L16'), u64(4), u64(0xf1234567)]!,
		[u64(c'signedWord:'), u64(c'q24@0:8q16'), u64(8), u64(0x8000000012345678)]!,
		[u64(c'unsignedWord:'), u64(c'Q24@0:8Q16'), u64(8), u64(0xf123456789abcdef)]!,
		[u64(c'boolean:'), u64(c'B20@0:8B16'), u64(1), u64(1)]!,
		[u64(c'float:'), u64(c'f20@0:8f16'), u64(4), u64(0x3fa00000)]!,
		[u64(c'double:'), u64(c'd24@0:8d16'), u64(8), u64(0xc004000000000000)]!,
		[u64(c'pointer:'), u64(c'^v24@0:8^v16'), u64(8), u64(0x12345678)]!,
		[u64(c'object:'), u64(c'@24@0:8@16'), u64(8), target]!,
		[u64(c'class:'), u64(c'#24@0:8#16'), u64(8), api.cls('NSObject')]!,
		[u64(c'selector:'), u64(c':24@0:8:16'), u64(8), api.selector(c'notification:payload:completion:')]!,
		[u64(c'cstring:'), u64(c'*24@0:8*16'), u64(8), u64(c'borrowed text')]!,
	]! {
		invocation := api.invocation(unsafe { &char(entry[1]) }); assert invocation != 0
		api.message(invocation, c'setTarget:', target, 0, 0); api.message(invocation, c'setSelector:', api.selector(unsafe { &char(entry[0]) }), 0, 0)
		mut source := [u64(0x1122334455667788), entry[3], u64(0x8877665544332211)]!
		api.set_argument(invocation, unsafe { &source[1] }, 2); source[1] = 0
		mut copied := [24]u8{init: u8(0x5a)}
		api.get_argument(invocation, unsafe { &copied[8] }, 2)
		for i in 0 .. 8 { assert copied[i] == 0x5a }
		for i in int(entry[2]) .. 16 { assert copied[i + 8] == 0x5a }
		for i in 0 .. int(entry[2]) { assert copied[i + 8] == u8(entry[3] >> (i * 8)) }
		api.message(invocation, c'invoke', 0, 0, 0)
		mut result := [24]u8{init: u8(0xa5)}
		api.message(invocation, c'getReturnValue:', u64(unsafe { &result[8] }), 0, 0)
		mut expected := entry[3]
		if api.text(entry[0]) == 'float:' { expected = 0x40200000 }
		if api.text(entry[0]) == 'double:' { expected = 0xc014000000000000 }
		for i in 0 .. 8 { assert result[i] == 0xa5 }
		for i in int(entry[2]) .. 16 { assert result[i + 8] == 0xa5 }
		for i in 0 .. int(entry[2]) { assert result[i + 8] == u8(expected >> (i * 8)), api.text(entry[0]) }
		mut manual := u64(0x123456789abcdef0)
		api.message(invocation, c'setReturnValue:', u64(unsafe { &manual }), 0, 0); result = [24]u8{init: u8(0xa5)}
		api.message(invocation, c'getReturnValue:', u64(unsafe { &result[8] }), 0, 0)
		for i in 0 .. int(entry[2]) { assert result[i + 8] == u8(manual >> (i * 8)) }
		for i in int(entry[2]) .. 16 { assert result[i + 8] == 0xa5 }
		// Native index -1 is the same return-value buffer.
		api.set_argument(invocation, unsafe { &manual }, -1); mut alias := u64(0)
		api.get_argument(invocation, unsafe { &alias }, -1)
		mask := if entry[2] == 8 { ~u64(0) } else { (u64(1) << (entry[2] * 8)) - 1 }
		assert alias == manual & mask
	}
}

fn invocation_fixture_shared(api InvocationFixtureApi) {
	invocation_fixture_api = api
	pool := api.pool(); invocation_fixture_signatures(api)
	for name in ['NSMethodSignature', 'NSInvocation']! {
		assert api.message(api.cls(name), c'new', 0, 0, 0) == 0
		raw := api.message(api.cls(name), c'alloc', 0, 0, 0); mut weak := u64(0)
		api.weak(unsafe { &weak }, raw); assert api.message(raw, c'init', 0, 0, 0) == 0 && weak == 0; api.destroy_weak(unsafe { &weak })
	}
	cls := api.new_target_class(); target := api.message(cls, c'new', 0, 0, 0)
	invocation_fixture_buffers(api, target)
	// Actual consumer shape: two object arguments plus an unretained block pointer.
	invocation := api.invocation(c'v40@0:8@16@24@?32')
	assert api.message(invocation, c'argumentsRetained', 0, 0, 0) == 0
	assert api.message(invocation, c'target', 0, 0, 0) == 0 && api.message(invocation, c'selector', 0, 0, 0) == 0
	api.message(invocation, c'setTarget:', target, 0, 0); api.message(invocation, c'setSelector:', api.selector(c'notification:payload:completion:'), 0, 0)
	mut first := target; mut second := api.cls('NSObject'); mut block := u64(0x123456780)
	api.set_argument(invocation, unsafe { &first }, 2); api.set_argument(invocation, unsafe { &second }, 3); api.set_argument(invocation, unsafe { &block }, 4)
	api.message(invocation, c'invoke', 0, 0, 0); assert invocation_fixture_observed == [target, first, second, block]!
	mut implicit := u64(0); api.get_argument(invocation, unsafe { &implicit }, 0); assert implicit == target
	api.get_argument(invocation, unsafe { &implicit }, 1); assert implicit == api.selector(c'notification:payload:completion:')
	other := api.message(cls, c'new', 0, 0, 0)
	api.message(invocation, c'invokeWithTarget:', other, 0, 0)
	assert invocation_fixture_observed == [other, first, second, block]!
	assert api.message(invocation, c'target', 0, 0, 0) == other
	// Mixed GP/FP placement and double return exercise both register banks.
	mixed := api.invocation(c'd48@0:8q16d24f32@40')
	api.message(mixed, c'setTarget:', target, 0, 0); api.message(mixed, c'setSelector:', api.selector(c'mixed:double:float:object:'), 0, 0)
	mut integer := i64(-37); mut real := f64(-2.5); mut single := f32(1.25)
	api.set_argument(mixed, unsafe { &integer }, 2); api.set_argument(mixed, unsafe { &real }, 3); api.set_argument(mixed, unsafe { &single }, 4); api.set_argument(mixed, unsafe { &first }, 5)
	api.message(mixed, c'invoke', 0, 0, 0); mut returned := f64(0)
	api.message(mixed, c'getReturnValue:', u64(unsafe { &returned }), 0, 0); assert returned == -38.25
	// Simultaneous maximum register occupancy includes self/cmd in GP0/GP1.
	all_registers := api.invocation(c'd128@0:8q16q24q32q40q48q56d64d72d80d88d96d104d112d120')
	api.message(all_registers, c'setTarget:', target, 0, 0); api.message(all_registers, c'setSelector:', api.selector(c'allRegisters:b:c:d:e:f:g:h:i:j:k:l:m:n:'), 0, 0)
	mut gp_values := [i64(-1), 2, -3, 4, -5, 6]!; mut fp_values := [f64(0.5), 1.5, 2.5, 3.5, -4.5, -5.5, -6.5, -7.5]!
	for i in 0 .. 6 { api.set_argument(all_registers, unsafe { &gp_values[i] }, i + 2) }
	for i in 0 .. 8 { api.set_argument(all_registers, unsafe { &fp_values[i] }, i + 8) }
	api.message(all_registers, c'invoke', 0, 0, 0); returned = 0
	api.message(all_registers, c'getReturnValue:', u64(unsafe { &returned }), 0, 0); assert returned == -13
	tracking := api.invocation(c'q16@0:8'); api.message(tracking, c'setTarget:', target, 0, 0); api.message(tracking, c'setSelector:', api.selector(c'trackingAuthorizationStatus'), 0, 0)
	mut status := u64(0); api.message(tracking, c'getReturnValue:', u64(unsafe { &status }), 0, 0); assert status == 0
	api.message(tracking, c'invoke', 0, 0, 0); api.message(tracking, c'getReturnValue:', u64(unsafe { &status }), 0, 0); assert status == 3
	api.message(tracking, c'invokeWithTarget:', 0, 0, 0); assert api.message(tracking, c'target', 0, 0, 0) == 0
	api.message(tracking, c'getReturnValue:', u64(unsafe { &status }), 0, 0); assert status == 3
	// Inherited, instance and class signatures must use typed method metadata.
	signature := api.message(target, c'methodSignatureForSelector:', api.selector(c'trackingAuthorizationStatus'), 0, 0)
	assert signature != 0 && api.text(api.message(signature, c'methodReturnType', 0, 0, 0)) == 'q'
	assert api.message(target, c'methodSignatureForSelector:', api.selector(c'missingInvocationMethod'), 0, 0) == 0
	instance := api.message(cls, c'instanceMethodSignatureForSelector:', api.selector(c'notification:payload:completion:'), 0, 0)
	assert instance != 0 && api.message(instance, c'numberOfArguments', 0, 0, 0) == 5
	class_signature := api.message(api.cls('NSObject'), c'methodSignatureForSelector:', api.selector(c'alloc'), 0, 0)
	assert class_signature != 0 && api.text(api.message(class_signature, c'methodReturnType', 0, 0, 0)) == '@'
	api.message(target, c'release', 0, 0, 0); api.message(other, c'release', 0, 0, 0)
	api.drain(pool)
}
struct InvocationFixtureBlockState { mut: copies int disposals int reenter bool }
struct InvocationFixtureBlockDescriptor { reserved u64 size u64 copy u64 dispose u64 }
struct InvocationFixtureBlock { isa u64 flags u32 reserved u32 invoke u64 descriptor u64 capture u64 }
fn invocation_fixture_word(address u64) u64 { return unsafe { *(&u64(voidptr(address))) } }
fn invocation_fixture_block_reentry() { C.ios_objc_initialize_lock(); C.ios_objc_initialize_unlock() }
fn invocation_fixture_block_copy(destination u64, source u64) {
	mut state := unsafe { &InvocationFixtureBlockState(voidptr(invocation_fixture_word(source + 32))) }
	state.copies++
	assert invocation_fixture_word(destination + 32) == u64(state)
	if state.reenter { worker := spawn invocation_fixture_block_reentry(); worker.wait() }
}
fn invocation_fixture_block_dispose(block u64) {
	mut state := unsafe { &InvocationFixtureBlockState(voidptr(invocation_fixture_word(block + 32))) }
	state.disposals++
	if state.reenter { worker := spawn invocation_fixture_block_reentry(); worker.wait() }
}
fn invocation_fixture_block_invoke(block u64) {}

fn invocation_fixture_ownership(api InvocationFixtureApi) {
	// Both transition orders must retain all replaced values until disposal.
	for retain_first in [false, true]! {
		pool := api.pool()
		invocation := api.message(api.invocation(c'@32@0:8@16*24'), c'retain', 0, 0, 0)
		mut objects := [6]u64{}; mut weak := [6]u64{}
		for i in 0 .. 6 { objects[i] = api.message(api.cls('NSObject'), c'new', 0, 0, 0); api.weak(unsafe { &weak[i] }, objects[i]) }
		mut text := [u8(`f`), `i`, `r`, `s`, `t`, 0]!
		mut text_pointer := u64(unsafe { &text[0] })
		if retain_first { api.message(invocation, c'retainArguments', 0, 0, 0) }
		api.message(invocation, c'setTarget:', objects[0], 0, 0); api.set_argument(invocation, unsafe { &objects[2] }, 2)
		api.message(invocation, c'setReturnValue:', u64(unsafe { &objects[4] }), 0, 0); api.set_argument(invocation, unsafe { &text_pointer }, 3)
		if !retain_first { api.message(invocation, c'retainArguments', 0, 0, 0) }
		assert api.message(invocation, c'argumentsRetained', 0, 0, 0) == 1
		mut copied_text := u64(0); api.get_argument(invocation, unsafe { &copied_text }, 3)
		assert copied_text != text_pointer && api.text(copied_text) == 'first'; text[0] = `x`
		assert api.text(copied_text) == 'first'
		api.message(invocation, c'setTarget:', objects[1], 0, 0); api.set_argument(invocation, unsafe { &objects[3] }, 2)
		api.message(invocation, c'setReturnValue:', u64(unsafe { &objects[5] }), 0, 0)
		api.message(invocation, c'retainArguments', 0, 0, 0)
		for object in objects { api.message(object, c'release', 0, 0, 0) }
		api.drain(pool)
		for i in 0 .. 6 { assert weak[i] == objects[i] }
		fresh := api.pool(); api.message(invocation, c'release', 0, 0, 0); api.drain(fresh)
		for i in 0 .. 6 { assert weak[i] == 0; api.destroy_weak(unsafe { &weak[i] }) }
	}
	// Without retainArguments, object slots and object returns stay borrowed.
	pool := api.pool(); borrowed := api.message(api.invocation(c'@24@0:8@16'), c'retain', 0, 0, 0)
	mut objects := [3]u64{}; mut weak := [3]u64{}
	for i in 0 .. 3 { objects[i] = api.message(api.cls('NSObject'), c'new', 0, 0, 0); api.weak(unsafe { &weak[i] }, objects[i]) }
	api.message(borrowed, c'setTarget:', objects[0], 0, 0); api.set_argument(borrowed, unsafe { &objects[1] }, 2)
	api.message(borrowed, c'setReturnValue:', u64(unsafe { &objects[2] }), 0, 0)
	for object in objects { api.message(object, c'release', 0, 0, 0) }; api.drain(pool)
	for i in 0 .. 3 { assert weak[i] == 0; api.destroy_weak(unsafe { &weak[i] }) }
	fresh := api.pool(); api.message(borrowed, c'release', 0, 0, 0); api.drain(fresh)
	// C-string returns are borrowed before retention and independently copied after it.
	for retain_first in [false, true]! {
		string_pool := api.pool(); invocation := api.invocation(c'*16@0:8')
		mut bytes := [u8(`r`), `e`, `t`, `u`, `r`, `n`, 0]!; mut original := u64(unsafe { &bytes[0] })
		if retain_first { api.message(invocation, c'retainArguments', 0, 0, 0) }
		api.message(invocation, c'setReturnValue:', u64(unsafe { &original }), 0, 0)
		mut result := u64(0); api.message(invocation, c'getReturnValue:', u64(unsafe { &result }), 0, 0)
		if !retain_first { assert result == original; api.message(invocation, c'retainArguments', 0, 0, 0); api.message(invocation, c'getReturnValue:', u64(unsafe { &result }), 0, 0) }
		assert result != original && api.text(result) == 'return'; bytes[0] = `x`; assert api.text(result) == 'return'
		api.drain(string_pool)
	}
	mut isa := u64(0)
	$if macos { if api.native { isa = u64(C.dlsym(unsafe { voidptr(-2) }, c'_NSConcreteStackBlock')) } }
	if !api.native { isa = block_isa(0) }; assert isa != 0
	descriptor := InvocationFixtureBlockDescriptor{0, sizeof(InvocationFixtureBlock), u64(unsafe { voidptr(invocation_fixture_block_copy) }), u64(unsafe { voidptr(invocation_fixture_block_dispose) })}
	mut state := unsafe { &InvocationFixtureBlockState(C.calloc(1, sizeof(InvocationFixtureBlockState))) }; assert state != unsafe { nil }; state.reenter = !api.native
	literal := InvocationFixtureBlock{isa, u32(1) << 25, 0, u64(unsafe { voidptr(invocation_fixture_block_invoke) }), u64(unsafe { &descriptor }), u64(state)}
	block_pool := api.pool(); invocation := api.message(api.invocation(c'@?24@0:8@?16'), c'retain', 0, 0, 0)
	mut original := u64(unsafe { &literal }); api.set_argument(invocation, unsafe { &original }, 2)
	mut stored := u64(0); api.get_argument(invocation, unsafe { &stored }, 2); assert stored == original && state.copies == 0
	api.message(invocation, c'retainArguments', 0, 0, 0); api.get_argument(invocation, unsafe { &stored }, 2)
	assert stored != original && state.copies == 1 && state.disposals == 0
	api.set_argument(invocation, unsafe { &original }, 2); api.message(invocation, c'setReturnValue:', u64(unsafe { &original }), 0, 0)
	assert state.copies == 3 && state.disposals == 0; api.drain(block_pool)
	block_release_pool := api.pool(); api.message(invocation, c'release', 0, 0, 0); api.drain(block_release_pool)
	assert state.copies == 3 && state.disposals == 3; C.free(state)
}

fn test_invocation_native() {
	$if macos {
		api := InvocationFixtureApi{native: true, send: u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend'))}
		invocation_fixture_shared(api); invocation_fixture_ownership(api)
		println('IOS-INVOCATION-NATIVE: copied signatures,19 scalar widths, GP/FP invoke, notification consumer, borrowed block, metadata and targets')
	}
}

// Runtime-only ownership and invalid-input fixtures.
fn invocation_fixture_runtime_api() InvocationFixtureApi { return InvocationFixtureApi{send: u64(unsafe { voidptr(C.ios_objc_builtin) })} }
__global invocation_fixture_receiver = u64(0)
__global invocation_fixture_drop_target = u64(0)
__global invocation_fixture_constructor_mode = ''
__global invocation_fixture_constructor_input = u64(0)
__global invocation_fixture_constructor_weak = u64(0)
__global invocation_fixture_constructor_fired = false
__global invocation_fixture_mutable_types = u64(0)
fn invocation_fixture_drop_callers() {
	api := invocation_fixture_runtime_api()
	assert api.message(invocation_fixture_receiver, c'target', 0, 0, 0) == invocation_fixture_drop_target
	assert api.message(invocation_fixture_receiver, c'methodSignature', 0, 0, 0) != 0
	objc_release(invocation_fixture_receiver); objc_release(invocation_fixture_drop_target)
}
fn invocation_fixture_releasing_target(object u64, selector &char) i64 {
	worker := spawn invocation_fixture_drop_callers(); worker.wait()
	assert obj_header(object).refs >= 1
	return -73
}
fn invocation_fixture_constructor_worker() {
	C.ios_objc_initialize_lock(); C.ios_objc_initialize_unlock()
	if invocation_fixture_constructor_input != 0 { objc_release(invocation_fixture_constructor_input) }
	if invocation_fixture_mutable_types != 0 { unsafe { *(&u8(voidptr(invocation_fixture_mutable_types))) = `v` } }
}
fn invocation_fixture_constructor(object u64, selector &char) u64 {
	if invocation_fixture_constructor_mode.len == 0 { return object }
	invocation_fixture_constructor_fired = true
	worker := spawn invocation_fixture_constructor_worker(); worker.wait()
	if invocation_fixture_constructor_mode == 'fail' {
		objc_store_weak(unsafe { &invocation_fixture_constructor_weak }, object)
		return 0
	}
	return object
}
fn invocation_fixture_runtime_lifetimes(api InvocationFixtureApi) {
	pool := api.pool()
	cls := objc_allocate_class(api.cls('NSObject'), c'VinixInvocationReleasingTarget', 0)
	assert objc_add_method(cls, u64(c'releaseCallers'), u64(unsafe { voidptr(invocation_fixture_releasing_target) }), c'q16@0:8'); objc_register_class(cls)
	invocation_fixture_drop_target = objc_new(cls)
	invocation_fixture_receiver = objc_retain(api.invocation(c'q16@0:8'))
	api.message(invocation_fixture_receiver, c'setTarget:', invocation_fixture_drop_target, 0, 0)
	api.message(invocation_fixture_receiver, c'setSelector:', u64(c'releaseCallers'), 0, 0)
	mut receiver_weak := u64(0); mut target_weak := u64(0)
	objc_store_weak(unsafe { &receiver_weak }, invocation_fixture_receiver); objc_store_weak(unsafe { &target_weak }, invocation_fixture_drop_target)
	api.drain(pool)
	call_pool := api.pool(); api.message(invocation_fixture_receiver, c'invoke', 0, 0, 0)
	assert receiver_weak == 0 && target_weak == 0
	objc_destroy_weak(unsafe { &receiver_weak }); objc_destroy_weak(unsafe { &target_weak }); api.drain(call_pool)
	invocation_fixture_receiver = 0; invocation_fixture_drop_target = 0
	for name in ['NSMethodSignature', 'NSInvocation']! { assert objc_add_method(api.cls(name), u64(c'.cxx_construct'), u64(unsafe { voidptr(invocation_fixture_constructor) }), c'@16@0:8') }
	// The type buffer is copied before application construction can mutate it.
	snapshot_pool := api.pool(); mut types := [u8(`q`), `1`, `6`, `@`, `0`, `:`, `8`, 0]!
	invocation_fixture_constructor_mode = 'snapshot'; invocation_fixture_mutable_types = u64(unsafe { &types[0] }); invocation_fixture_constructor_fired = false
	signature := api.signature(unsafe { &char(&types[0]) })
	assert invocation_fixture_constructor_fired && types[0] == `v`
	assert api.text(api.message(signature, c'methodReturnType', 0, 0, 0)) == 'q'
	invocation_fixture_constructor_mode = ''; invocation_fixture_mutable_types = 0; api.drain(snapshot_pool)
	// Invocation allocation pins its signature while a joined worker releases the caller.
	input_pool := api.pool(); input := objc_retain(api.signature(c'q16@0:8')); mut input_weak := u64(0)
	objc_store_weak(unsafe { &input_weak }, input); api.drain(input_pool)
	factory_pool := api.pool(); invocation_fixture_constructor_mode = 'input'; invocation_fixture_constructor_input = input; invocation_fixture_constructor_fired = false
	invocation := api.message(api.cls('NSInvocation'), c'invocationWithMethodSignature:', input, 0, 0)
	assert invocation_fixture_constructor_fired && input_weak == input && api.message(invocation, c'methodSignature', 0, 0, 0) == input
	invocation_fixture_constructor_mode = ''; invocation_fixture_constructor_input = 0; api.drain(factory_pool)
	assert input_weak == 0; objc_destroy_weak(unsafe { &input_weak })
	// Both newly allocated and caller-owned failed construction retire sidecars.
	failure_pool := api.pool(); valid := api.signature(c'q16@0:8')
	invocation_fixture_constructor_mode = 'fail'
	assert api.signature(c'q16@0:8') == 0 && invocation_fixture_constructor_weak == 0
	objc_destroy_weak(unsafe { &invocation_fixture_constructor_weak })
	assert api.message(api.cls('NSInvocation'), c'invocationWithMethodSignature:', valid, 0, 0) == 0 && invocation_fixture_constructor_weak == 0
	objc_destroy_weak(unsafe { &invocation_fixture_constructor_weak })
	for name in ['NSMethodSignature', 'NSInvocation']! {
		size := if name == 'NSMethodSignature' { 32 } else { 64 }; mut guarded := [10]u64{}
		guarded[0] = 0x1122334455667788; guarded[size / 8 + 1] = 0x8877665544332211
		object := u64(unsafe { &guarded[1] }); assert objc_construct_instance(api.cls(name), object) == 0
		assert invocation_fixture_constructor_weak == 0; objc_destroy_weak(unsafe { &invocation_fixture_constructor_weak })
		assert guarded[0] == 0x1122334455667788 && guarded[size / 8 + 1] == 0x8877665544332211 && guarded[1] == api.cls(name)
		for offset in 8 .. size { assert unsafe { *(&u8(voidptr(object + u64(offset)))) } == 0 }
	}
	invocation_fixture_constructor_mode = ''; api.drain(failure_pool)
	// Provenance drives cleanup even after a non-invocation isa replacement.
	isa_pool := api.pool()
	for _ in 0 .. 32 {
		sig := objc_retain(api.signature(c'@24@0:8@16')); object := objc_retain(api.message(api.cls('NSInvocation'), c'invocationWithMethodSignature:', sig, 0, 0))
		target := objc_new(api.cls('NSObject')); api.message(object, c'setTarget:', target, 0, 0); api.message(object, c'retainArguments', 0, 0, 0); objc_release(target)
		assert objc_set_class(object, api.cls('NSObject')) == api.cls('NSInvocation'); objc_release(object)
		assert objc_set_class(sig, api.cls('NSObject')) == api.cls('NSMethodSignature'); objc_release(sig)
	}
	api.drain(isa_pool)
}
fn test_invocation_runtime() {
	objc_start(); system_data_start()!
	api := invocation_fixture_runtime_api(); invocation_fixture_shared(api); invocation_fixture_ownership(api); invocation_fixture_runtime_lifetimes(api)
	assert ios_runtime.live == 0
	objc_stop(); assert ios_runtime.live == 0; system_data_stop()
	println('IOS-INVOCATION: shared scalar/register/consumer fixture and drained runtime')
}

__global invocation_fixture_invalid_mode = ''
fn invocation_fixture_invalid_target(object u64, selector &char) u64 {
	api := invocation_fixture_runtime_api()
	match invocation_fixture_invalid_mode {
		'nested-invoke' { api.message(invocation_fixture_receiver, c'invoke', 0, 0, 0) }
		'nested-setter' { api.message(invocation_fixture_receiver, c'setTarget:', object, 0, 0) }
		'destruct-active' { objc_destruct_instance(invocation_fixture_receiver) }
		else {}
	}
	return 37
}
fn invocation_fixture_invalid_constructor(object u64, selector &char) u64 {
	objc_destruct_instance(invocation_fixture_constructor_input)
	return object
}
fn test_invocation_rejections() {
	objc_start(); system_data_start()!; api := invocation_fixture_runtime_api()
	for selector in [c'copy', c'mutableCopy', c'encodeWithCoder:', c'initWithCoder:', c'description']! {
		assert !objc_responds(api.cls('NSInvocation'), selector) && !objc_responds(api.cls('NSMethodSignature'), selector)
	}
	assert !objc_responds(api.cls('NSMethodSignature'), c'isEqual:') && !objc_responds(api.cls('NSMethodSignature'), c'hash')
	modes := ['struct', 'array', 'union', 'bitfield', 'unknown', 'long-double', 'bad-quoted', 'bad-pointer', 'gp-stack', 'fp-stack', 'nil-signature', 'wrong-signature', 'no-self', 'raw-signature', 'raw-invocation', 'signature-subclass', 'invocation-subclass', 'signature-spoof', 'invocation-spoof', 'signature-cross-isa', 'invocation-cross-isa', 'negative-index', 'past-index', 'signature-index', 'nil-argument-buffer', 'nil-return-buffer', 'void-return', 'copy', 'coding', 'signature-equality', 'signature-hash', 'missing-selector', 'missing-method', 'signature-mismatch', 'owned-family', 'bad-block', 'nested-invoke', 'nested-setter', 'destruct-active', 'destruct-active-signature', 'owner-limit', 'cstring-limit']!
	for mode in modes {
		mut fds := [2]i32{}; assert C.pipe(unsafe { &fds[0] }) == 0
		pid := C.ios_fork(); assert pid >= 0
		if pid == 0 {
			C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1]); invocation_fixture_invalid_mode = mode
			pool := api.pool(); invocation := api.invocation(c'q16@0:8')
			match mode {
				'struct', 'array', 'union', 'bitfield', 'unknown', 'long-double', 'bad-quoted', 'bad-pointer', 'gp-stack', 'fp-stack' {
					types := match mode { 'struct' { c'{Pair=qq}16@0:8' } 'array' { c'v24@0:8[2q]16' } 'union' { c'(Pair=qd)16@0:8' } 'bitfield' { c'b816@0:8' } 'unknown' { c'?16@0:8' } 'long-double' { c'D16@0:8' } 'bad-quoted' { c'@16@0:8@"unterminated' } 'bad-pointer' { c'q24@0:8^' } 'gp-stack' { c'q@:qqqqqqq' } else { c'd@:ddddddddd' } }
					api.signature(types)
				}
				'nil-signature' { api.message(api.cls('NSInvocation'), c'invocationWithMethodSignature:', 0, 0, 0) }
				'wrong-signature' { api.message(api.cls('NSInvocation'), c'invocationWithMethodSignature:', objc_new(api.cls('NSObject')), 0, 0) }
				'no-self' { api.invocation(c'q') }
				'raw-signature' { api.message(objc_allocate(api.cls('NSMethodSignature')), c'numberOfArguments', 0, 0, 0) }
				'raw-invocation' { api.message(objc_allocate(api.cls('NSInvocation')), c'target', 0, 0, 0) }
				'signature-subclass', 'invocation-subclass' {
					cls := objc_allocate_class(api.cls(if mode == 'signature-subclass' { 'NSMethodSignature' } else { 'NSInvocation' }), c'VinixUnsupportedInvocationSubclass', 0)
					objc_register_class(cls); objc_allocate(cls)
				}
				'signature-spoof', 'invocation-spoof' {
					object := objc_new(api.cls('NSObject')); objc_set_class(object, api.cls(if mode == 'signature-spoof' { 'NSMethodSignature' } else { 'NSInvocation' }))
					api.message(object, if mode == 'signature-spoof' { c'numberOfArguments' } else { c'target' }, 0, 0, 0)
				}
				'signature-cross-isa' { object := api.signature(c'q16@0:8'); objc_set_class(object, api.cls('NSInvocation')); api.message(object, c'target', 0, 0, 0) }
				'invocation-cross-isa' { objc_set_class(invocation, api.cls('NSMethodSignature')); api.message(invocation, c'numberOfArguments', 0, 0, 0) }
				'negative-index', 'past-index', 'nil-argument-buffer' {
					mut value := u64(0); api.get_argument(invocation, if mode == 'nil-argument-buffer' { unsafe { nil } } else { unsafe { &value } }, if mode == 'negative-index' { -2 } else if mode == 'past-index' { 2 } else { 0 })
				}
				'signature-index' { api.message(api.signature(c'q16@0:8'), c'getArgumentTypeAtIndex:', 2, 0, 0) }
				'nil-return-buffer' { api.message(invocation, c'getReturnValue:', 0, 0, 0) }
				'void-return' { mut value := u64(0); api.message(api.invocation(c'v16@0:8'), c'getReturnValue:', u64(unsafe { &value }), 0, 0) }
				'copy' { api.message(invocation, c'copy', 0, 0, 0) }
				'coding' { api.message(invocation, c'encodeWithCoder:', 0, 0, 0) }
				'signature-equality', 'signature-hash' { api.message(api.signature(c'q16@0:8'), if mode == 'signature-hash' { c'hash' } else { c'isEqual:' }, 0, 0, 0) }
				'bad-block' { object := api.invocation(c'v24@0:8@?16'); mut argument := objc_new(api.cls('NSObject')); api.set_argument(object, unsafe { &argument }, 2); api.message(object, c'retainArguments', 0, 0, 0) }
				'destruct-active-signature' {
					invocation_fixture_constructor_input = api.signature(c'q16@0:8')
					assert objc_add_method(api.cls('NSInvocation'), u64(c'.cxx_construct'), u64(unsafe { voidptr(invocation_fixture_invalid_constructor) }), c'@16@0:8')
					api.message(api.cls('NSInvocation'), c'invocationWithMethodSignature:', invocation_fixture_constructor_input, 0, 0)
				}
				'owner-limit' { api.message(invocation, c'retainArguments', 0, 0, 0); for _ in 0 .. 4097 { api.message(invocation, c'setTarget:', api.cls('NSObject'), 0, 0) } }
				'cstring-limit' { object := api.invocation(c'*16@0:8'); bytes := C.malloc(1048577); assert bytes != unsafe { nil }; unsafe { C.memset(bytes, `x`, 1048577) }; mut address := u64(bytes); api.message(object, c'setReturnValue:', u64(unsafe { &address }), 0, 0); api.message(object, c'retainArguments', 0, 0, 0) }
				else {
					cls := objc_allocate_class(api.cls('NSObject'), c'VinixInvalidInvocationTarget', 0)
					selector := if mode == 'owned-family' { c'newResult' } else { c'run' }
					types := if mode == 'signature-mismatch' { c'Q16@0:8' } else { c'q16@0:8' }
					assert objc_add_method(cls, u64(selector), u64(unsafe { voidptr(invocation_fixture_invalid_target) }), types); objc_register_class(cls)
					api.message(invocation, c'setTarget:', objc_new(cls), 0, 0)
					if mode != 'missing-selector' { api.message(invocation, c'setSelector:', if mode == 'missing-method' { u64(c'missingMethod') } else { u64(selector) }, 0, 0) }
					invocation_fixture_receiver = invocation; api.message(invocation, c'invoke', 0, 0, 0)
				}
			}
			api.drain(pool); C._exit(0)
		}
		C.close(fds[1]); mut bytes := [16384]u8{}; mut length := 0
		for { assert length < bytes.len; count := C.read(fds[0], unsafe { &bytes[length] }, usize(bytes.len - length)); if count == 0 { break }; if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }; assert count > 0; length += int(count) }
		C.close(fds[0]); mut status := i32(0); assert C.ios_waitpid(pid, &status, 0) == pid
		output := unsafe { tos(&bytes[0], length) }
		assert status == 256 && output.contains('iOS:') && !output.contains('AddressSanitizer') && !output.contains('runtime error:'), mode + ': ' + output
	}
	assert ios_runtime.live == 0; objc_stop(); system_data_stop()
	println('IOS-INVOCATION-REJECT:42 unsupported types, stack ABI, malformed signature, factories, provenance, bounds, coding, method mismatch, ownership limit and active callback cases fail explicitly')
}

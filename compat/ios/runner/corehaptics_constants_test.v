// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.dlclose(voidptr) i32
type CHName = fn (&char) u64
type CHMessage = fn (u64, u64, u64, u64, u64) u64
type CHRetain = fn (u64) u64
type CHDrop = fn (u64)
type CHPool = fn () u64
type CHText = fn (u64, &char, i64, u32) bool
struct CHApi { native bool haptics u64 objc u64 core u64 }
const ch_symbols = ['_CHHapticDynamicParameterIDHapticIntensityControl',
	'_CHHapticDynamicParameterIDHapticSharpnessControl', '_CHHapticEventParameterIDHapticIntensity',
	'_CHHapticEventParameterIDHapticSharpness', '_CHHapticEventTypeHapticContinuous']!
const ch_values = ['HapticIntensityControl', 'HapticSharpnessControl',
	'HapticIntensity', 'HapticSharpness', 'HapticContinuous']!
__global corehaptics_teardown_calls = 0

fn ch_cell(api CHApi, index int) u64 {
	if api.native { return u64(C.dlsym(unsafe { voidptr(api.haptics) }, unsafe { ch_symbols[index].str + 1 })) }
	return runtime_symbol('/System/Library/Frameworks/CoreHaptics.framework/CoreHaptics',
		ch_symbols[index]) or { panic(err) }
}
fn ch_class(api CHApi, name &char) u64 {
	if api.native { return unsafe { CHName(C.dlsym(voidptr(api.objc), c'objc_getClass'))(name) } }
	return ios_runtime.names[ctext(u64(name))]
}
fn ch_message(api CHApi, object u64, name &char, a u64, b u64, c u64) u64 {
	if api.native {
		selector := unsafe { CHName(C.dlsym(voidptr(api.objc), c'sel_registerName'))(name) }
		return unsafe { CHMessage(C.dlsym(voidptr(api.objc), c'objc_msgSend'))(object, selector, a, b, c) }
	}
	return unsafe { CHMessage(voidptr(C.ios_objc_builtin))(object, u64(name), a, b, c) }
}
fn ch_retain(api CHApi, value u64) u64 {
	if api.native { return unsafe { CHRetain(C.dlsym(voidptr(api.objc), c'objc_retain'))(value) } }
	return objc_retain(value)
}
fn ch_drop(api CHApi, value u64) {
	if api.native { unsafe { CHDrop(C.dlsym(voidptr(api.objc), c'objc_release'))(value) }; return }
	objc_release(value)
}
fn ch_pool(api CHApi) u64 {
	if api.native { return unsafe { CHPool(C.dlsym(voidptr(api.objc), c'objc_autoreleasePoolPush'))() } }
	return objc_pool_push()
}
fn ch_pop(api CHApi, pool u64) {
	if api.native { unsafe { CHDrop(C.dlsym(voidptr(api.objc), c'objc_autoreleasePoolPop'))(pool) }; return }
	objc_pool_pop(pool)
}
fn ch_text(api CHApi, value u64, index int) {
	assert value != 0
	if api.native {
		mut bytes := [64]u8{}
		assert unsafe { CHText(C.dlsym(voidptr(api.core), c'CFStringGetCString'))(value, &char(&bytes[0]), 64, 0x08000100) }
		assert C.strcmp(unsafe { &char(&bytes[0]) }, ch_values[index].str) == 0
	} else { assert string_text(value) == ch_values[index] }
}
fn ch_reader(api CHApi) u64 {
	mut cells := [5]u64{}
	for _ in 0 .. 32 {
		pool := ch_pool(api)
		for i in 0 .. 5 {
			cell := ch_cell(api, i)
			assert cell != 0 && cell % 8 == 0
			if cells[i] == 0 { cells[i] = cell } else { assert cells[i] == cell }
			value := read64(cell)
			assert value != 0 && value != cell
			ch_text(api, value, i)
			assert ch_retain(api, value) == value
			ch_drop(api, value)
			assert ch_message(api, ch_retain(api, value), c'autorelease', 0, 0, 0) == value
		}
		ch_pop(api, pool)
	}
	return cells[0]
}
fn ch_shared(api CHApi) {
	mut workers := []thread u64{}
	for _ in 0 .. 8 { workers << spawn ch_reader(api) }
	mut cells := [5]u64{}
	for i, worker in workers {
		result := worker.wait()
		if i == 0 { cells[0] = result } else { assert cells[0] == result }
	}
	unsafe { workers.free() }
	for i in 1 .. 5 { cells[i] = ch_cell(api, i) }
	pool := ch_pool(api)
	mut objects := [5]u64{}
	mut keys := [5]u64{}
	for i in 0 .. 5 {
		objects[i] = read64(cells[i])
		keys[i] = ch_message(api, ch_class(api, c'NSString'), c'stringWithUTF8String:', u64(ch_values[i].str), 0, 0)
		assert ch_message(api, objects[i], c'isEqualToString:', keys[i], 0, 0) == 1
		for j in 0 .. i { assert cells[j] != cells[i] && objects[j] != objects[i] }
	}
	dictionary := ch_message(api, ch_class(api, c'NSDictionary'), c'dictionaryWithObjects:forKeys:count:',
		unsafe { u64(&objects[0]) }, unsafe { u64(&keys[0]) }, 5)
	assert dictionary != 0 && ch_retain(api, dictionary) == dictionary
	ch_pop(api, pool)
	assert ch_message(api, dictionary, c'count', 0, 0, 0) == 5
	for i in 0 .. 5 {
		got := ch_message(api, dictionary, c'objectForKey:', objects[i], 0, 0)
		ch_text(api, got, i)
	}
	ch_drop(api, dictionary)
	for i in 0 .. 5 { ch_text(api, read64(cells[i]), i) }
	if !api.native { assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 }
}
fn ch_teardown(_object u64, _selector &char) {
	assert ios_runtime.swift_concurrency_retired
	for i in 0 .. 5 {
		cell := corehaptics_constant_symbol(ch_symbols[i]) or { panic('CoreHaptics global retired before pool destructor') }
		ch_text(CHApi{}, read64(cell), i)
	}
	corehaptics_teardown_calls++
}
fn test_corehaptics_constants() {
	$if macos {
		api := CHApi{true, u64(C.dlopen(c'/System/Library/Frameworks/CoreHaptics.framework/CoreHaptics', 2)),
			u64(C.dlopen(c'/usr/lib/libobjc.A.dylib', 2)), u64(C.dlopen(c'/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation', 2))}
		assert api.haptics != 0 && api.objc != 0 && api.core != 0
		ch_shared(api)
		assert C.dlclose(unsafe { voidptr(api.core) }) == 0
		assert C.dlclose(unsafe { voidptr(api.objc) }) == 0
		assert C.dlclose(unsafe { voidptr(api.haptics) }) == 0
		println('IOS-COREHAPTICS-CONSTANTS-NATIVE: five NSString pointer cells,exact values,concurrent identity,retain/release,autorelease and dictionary ownership/equality')
	}
	if _ := corehaptics_constant_symbol(ch_symbols[0]) { assert false }
	for _ in 0 .. 2 {
		objc_start()
		assert ios_runtime.corehaptics_constants_arena == 0
		ios_runtime.swift_concurrency_retired = true
		if _ := corehaptics_constant_symbol(ch_symbols[0]) { assert false }
		assert ios_runtime.corehaptics_constants_arena == 0
		ios_runtime.swift_concurrency_retired = false
		if _ := corehaptics_constant_symbol('_CHHapticInventedParameter') { assert false }
		assert ios_runtime.corehaptics_constants_arena == 0
		ch_shared(CHApi{})
		for library in ['/System/Library/Frameworks/Foundation.framework/Foundation',
			'/System/Library/Frameworks/UIKit.framework/UIKit', '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation',
			'/System/Library/Frameworks/DeviceCheck.framework/DeviceCheck', '/usr/lib/libSystem.B.dylib']! {
			for symbol in ch_symbols { if _ := runtime_symbol(library, symbol) { assert false } }
		}
		probe := objc_allocate_class(ios_runtime.names['NSObject'], c'VinixCoreHapticsTeardownProbe', 0)
		assert probe != 0 && objc_add_method(probe, u64(c'dealloc'), u64(unsafe { voidptr(ch_teardown) }), c'v16@0:8')
		objc_register_class(probe)
		objc_autorelease(objc_new(probe))
		ios_runtime.swift_concurrency_retired = true
		before := corehaptics_teardown_calls
		objc_stop()
		assert corehaptics_teardown_calls == before + 1 && ios_runtime.corehaptics_constants_arena == 0
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
		if _ := corehaptics_constant_symbol(ch_symbols[0]) { assert false }
	}
	println('IOS-COREHAPTICS-CONSTANTS: exact framework scope,five sealed stable NSString pointer cells,contended publication,collection ownership,pool destructor availability and two drained/unmapped runtimes')
}

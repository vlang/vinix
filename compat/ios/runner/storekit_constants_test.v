// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import strconv

#include <dlfcn.h>
$if macos {
	#include <mach/mach.h>
}
fn C.mach_task_self() u32
fn C.vm_region_64(u32, &u64, &u64, i32, &i32, &u32, &u32) i32
fn C.mach_port_deallocate(u32, u32) i32
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.dlclose(voidptr) i32
type SKCName = fn (&char) u64
type SKCMessage = fn (u64, u64, u64, u64, u64) u64
type SKCRetain = fn (u64) u64
type SKCDrop = fn (u64)
type SKCPool = fn () u64
type SKCText = fn (u64, &char, i64, u32) bool
type SKCCacheRange = fn (&usize) voidptr
struct SKCApi { native bool cells [3]u64 objc u64 core u64 }
const skc_symbols = ['_SKAdNetworkCoarseConversionValueHigh',
	'_SKAdNetworkCoarseConversionValueMedium', '_SKAdNetworkCoarseConversionValueLow']!
const skc_values = ['high', 'medium', 'low']!
__global storekit_teardown_calls = 0

// macOS StoreKit omits these iOS exports. Its iOSSupport counterpart is mapped
// in the shared cache even though dlopen rejects its platform. Read only its
// data exports; no StoreKit service code is invoked.
fn skc_native_cells() [3]u64 {
	mut cells := [3]u64{}
	$if macos {
		mut process := os.new_process('/usr/bin/dyld_info')
		process.set_args(['-segments', '-exports',
			'/System/iOSSupport/System/Library/Frameworks/StoreKit.framework/Versions/A/StoreKit'])
		process.set_redirect_stdio_merged()
		process.run()
		output := process.stdout_slurp()
		process.wait()
		code := process.code
		process.close()
		assert code == 0
		lines := output.split_into_lines()
		headers := lines.filter(it.fields().len > 1 && it.fields()[1] == '__TEXT')
		assert headers.len == 1
		image := strconv.parse_uint(headers[0].fields()[0].trim_string_left('0x'), 16, 64) or { panic(err) }
		get_range := C.dlsym(voidptr(-2), c'_dyld_get_shared_cache_range')
		assert get_range != unsafe { nil }
		mut size := usize(0)
		base := u64(unsafe { SKCCacheRange(get_range)(&size) })
		assert base != 0 && size > 32
		mapping_offset := unsafe { *(&u32(base + 16)) }
		assert mapping_offset + 32 < size
		unslid := read64(base + mapping_offset)
		assert image >= unslid && image - unslid < size
		for i, symbol in skc_symbols {
			exports := lines.filter(it.trim_space().ends_with(' ' + symbol))
			assert exports.len == 1
			offset := strconv.parse_uint(exports[0].fields()[0].trim_string_left('0x'), 16, 64) or { panic(err) }
			assert image - unslid + offset + 8 <= size
			cells[i] = base + image - unslid + offset
			assert read64(cells[i]) >= base && read64(cells[i]) + 32 < base + size
			assert read64(read64(cells[i]) + 8) == 0x7c8
			assert read64(read64(cells[i]) + 24) == u64(skc_values[i].len)
		}
	}
	return cells
}

fn skc_cell(api SKCApi, index int) u64 {
	if api.native { return api.cells[index] }
	return runtime_symbol('/System/Library/Frameworks/StoreKit.framework/StoreKit',
		skc_symbols[index]) or { panic(err) }
}
fn skc_class(api SKCApi, name &char) u64 {
	if api.native { return unsafe { SKCName(C.dlsym(voidptr(api.objc), c'objc_getClass'))(name) } }
	return ios_runtime.names[ctext(u64(name))]
}
fn skc_message(api SKCApi, object u64, name &char, a u64, b u64, c u64) u64 {
	if api.native {
		selector := unsafe { SKCName(C.dlsym(voidptr(api.objc), c'sel_registerName'))(name) }
		return unsafe { SKCMessage(C.dlsym(voidptr(api.objc), c'objc_msgSend'))(object, selector, a, b, c) }
	}
	return unsafe { SKCMessage(voidptr(C.ios_objc_builtin))(object, u64(name), a, b, c) }
}
fn skc_retain(api SKCApi, value u64) u64 {
	if api.native { return unsafe { SKCRetain(C.dlsym(voidptr(api.objc), c'objc_retain'))(value) } }
	return objc_retain(value)
}
fn skc_drop(api SKCApi, value u64) {
	if api.native { unsafe { SKCDrop(C.dlsym(voidptr(api.objc), c'objc_release'))(value) }; return }
	objc_release(value)
}
fn skc_pool(api SKCApi) u64 {
	if api.native { return unsafe { SKCPool(C.dlsym(voidptr(api.objc), c'objc_autoreleasePoolPush'))() } }
	return objc_pool_push()
}
fn skc_pop(api SKCApi, pool u64) {
	if api.native { unsafe { SKCDrop(C.dlsym(voidptr(api.objc), c'objc_autoreleasePoolPop'))(pool) }; return }
	objc_pool_pop(pool)
}
fn skc_text(api SKCApi, value u64, index int) {
	assert value != 0
	if api.native {
		mut bytes := [64]u8{}
		assert unsafe { SKCText(C.dlsym(voidptr(api.core), c'CFStringGetCString'))(value, &char(&bytes[0]), 64, 0x08000100) }
		assert C.strcmp(unsafe { &char(&bytes[0]) }, skc_values[index].str) == 0
	} else { assert string_text(value) == skc_values[index] }
}
fn skc_reader(api SKCApi) u64 {
	mut cells := [3]u64{}
	for _ in 0 .. 32 {
		pool := skc_pool(api)
		for i in 0 .. 3 {
			cell := skc_cell(api, i)
			assert cell != 0 && cell % 8 == 0
			if cells[i] == 0 { cells[i] = cell } else { assert cells[i] == cell }
			value := read64(cell)
			assert value != 0 && value != cell
			skc_text(api, value, i)
			assert skc_retain(api, value) == value
			skc_drop(api, value)
			assert skc_message(api, skc_retain(api, value), c'autorelease', 0, 0, 0) == value
			assert skc_message(api, value, c'copy', 0, 0, 0) == value
			skc_drop(api, value)
		}
		skc_pop(api, pool)
	}
	return cells[0]
}
fn skc_shared(api SKCApi) {
	mut workers := []thread u64{}
	for _ in 0 .. 8 { workers << spawn skc_reader(api) }
	mut cells := [3]u64{}
	for i, worker in workers {
		result := worker.wait()
		if i == 0 { cells[0] = result } else { assert cells[0] == result }
	}
	unsafe { workers.free() }
	for i in 1 .. 3 { cells[i] = skc_cell(api, i) }
	pool := skc_pool(api)
	mut objects := [3]u64{}
	mut keys := [3]u64{}
	for i in 0 .. 3 {
		objects[i] = read64(cells[i])
		keys[i] = skc_message(api, skc_class(api, c'NSString'), c'stringWithUTF8String:', u64(skc_values[i].str), 0, 0)
		assert skc_message(api, objects[i], c'isEqualToString:', keys[i], 0, 0) == 1
		if !api.native {
			words := swift_foundation_unbridge(objects[i])
			bytes := swift_string_utf8_cstring(words.first, words.second)
			assert read64(bytes + 16) == u64(skc_values[i].len + 1)
			assert C.strcmp(unsafe { &char(bytes + 32) }, skc_values[i].str) == 0
			swift_bridge_release(bytes)
			swift_bridge_release(words.second)
		}
		for j in 0 .. i { assert cells[j] != cells[i] && objects[j] != objects[i] }
	}
	dictionary := skc_message(api, skc_class(api, c'NSDictionary'), c'dictionaryWithObjects:forKeys:count:',
		unsafe { u64(&objects[0]) }, unsafe { u64(&keys[0]) }, 3)
	assert dictionary != 0 && skc_retain(api, dictionary) == dictionary
	skc_pop(api, pool)
	assert skc_message(api, dictionary, c'count', 0, 0, 0) == 3
	for i in 0 .. 3 {
		got := skc_message(api, dictionary, c'objectForKey:', objects[i], 0, 0)
		skc_text(api, got, i)
	}
	skc_drop(api, dictionary)
	for i in 0 .. 3 { skc_text(api, read64(cells[i]), i) }
	if !api.native { assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 }
}
fn skc_teardown(_object u64, _selector &char) {
	assert ios_runtime.swift_concurrency_retired
	for i in 0 .. 3 {
		cell := storekit_constant_symbol(skc_symbols[i]) or { panic('StoreKit global retired before pool destructor') }
		skc_text(SKCApi{}, read64(cell), i)
	}
	storekit_teardown_calls++
}
fn test_storekit_constants() {
	$if macos {
		api := SKCApi{native: true, cells: skc_native_cells(),
			objc: u64(C.dlopen(c'/usr/lib/libobjc.A.dylib', 2)), core: u64(C.dlopen(c'/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation', 2))}
		assert api.objc != 0 && api.core != 0
		skc_shared(api)
		assert C.dlclose(unsafe { voidptr(api.core) }) == 0
		assert C.dlclose(unsafe { voidptr(api.objc) }) == 0
		println('IOS-STOREKIT-CONSTANTS-NATIVE: three iOSSupport NSString cells,exact values,concurrent identity,copy,retain/release,autorelease and dictionary ownership/equality')
	}
	if _ := storekit_constant_symbol(skc_symbols[0]) { assert false }
	for _ in 0 .. 2 {
		objc_start()
		assert ios_runtime.storekit_constants_arena == 0
		ios_runtime.swift_concurrency_retired = true
		if _ := storekit_constant_symbol(skc_symbols[0]) { assert false }
		assert ios_runtime.storekit_constants_arena == 0
		ios_runtime.swift_concurrency_retired = false
		if _ := storekit_constant_symbol('_SKAdNetworkCoarseConversionValueInvented') { assert false }
		assert ios_runtime.storekit_constants_arena == 0
		skc_shared(SKCApi{})
		arena := ios_runtime.storekit_constants_arena
		skc_mapping(arena, true, false)
		for library in ['/System/Library/Frameworks/Foundation.framework/Foundation',
			'/System/Library/Frameworks/UIKit.framework/UIKit', '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation',
			'/System/Library/Frameworks/DeviceCheck.framework/DeviceCheck', '/usr/lib/libSystem.B.dylib']! {
			for symbol in skc_symbols { if _ := runtime_symbol(library, symbol) { assert false } }
		}
		probe := objc_allocate_class(ios_runtime.names['NSObject'], c'VinixStoreKitTeardownProbe', 0)
		assert probe != 0 && objc_add_method(probe, u64(c'dealloc'), u64(unsafe { voidptr(skc_teardown) }), c'v16@0:8')
		objc_register_class(probe)
		objc_autorelease(objc_new(probe))
		ios_runtime.swift_concurrency_retired = true
		before := storekit_teardown_calls
		objc_stop()
		skc_mapping(arena, false, false)
		assert storekit_teardown_calls == before + 1 && ios_runtime.storekit_constants_arena == 0
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
		if _ := storekit_constant_symbol(skc_symbols[0]) { assert false }
	}
	println('IOS-STOREKIT-CONSTANTS: exact framework scope,three sealed stable NSString cells,contended publication,collection ownership,pool destructor availability and two drained/unmapped runtimes')
}

fn skc_mapping(address u64, mapped bool, executable bool) {
	$if macos {
		mut start := address
		mut size := u64(0)
		mut info := [16]i32{}
		mut count := u32(C.VM_REGION_BASIC_INFO_COUNT_64)
		mut object := u32(0)
		task := C.mach_task_self()
		status := C.vm_region_64(task, &start, &size, C.VM_REGION_BASIC_INFO_64, unsafe { &info[0] }, &count, &object)
		if mapped {
			assert status == 0 && start <= address && address + 8 <= start + size && info[0] == (C.PROT_READ | if executable {
				C.PROT_EXEC
			} else {
				0
			})
		} else {
			assert status != 0 || start > address
		}
		if object != 0 {
			assert C.mach_port_deallocate(task, object) == 0
		}
	} $else {
		mut found := false
		for line in (os.read_file('/proc/self/maps') or { panic(err) }).split_into_lines() {
			fields := line.fields()
			if fields.len < 2 { continue }
			range := fields[0].split('-')
			if range.len != 2 { continue }
			start := strconv.parse_uint(range[0], 16, 64) or { panic(err) }
			end := strconv.parse_uint(range[1], 16, 64) or { panic(err) }
			if address >= start && address < end {
				assert mapped && fields[1] == if executable { 'r-xp' } else { 'r--p' }
				found = true
				break
			}
		}
		assert found == mapped
	}
}


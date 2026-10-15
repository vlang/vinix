// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
type URLName = fn (&char) u64
type URLMessage = fn (u64, u64, u64, u64, u64) u64
type URLRetain = fn (u64) u64
type URLRelease = fn (u64)
type URLPool = fn () u64
type URLBytes = fn (u64, &char, i64, u32) bool
struct URLApi { native bool foundation u64 objc u64 core u64 }
struct URLCells { values [7]u64 }
__global url_error_teardown_calls = 0
fn ur_names() [7]string {
	return ['_NSURLErrorDomain', '_NSURLErrorFailingURLErrorKey', '_NSURLErrorFailingURLStringErrorKey', '_NSErrorFailingURLStringKey', '_NSURLErrorFailingURLPeerTrustErrorKey', '_NSURLErrorBackgroundTaskCancelledReasonKey', '_NSURLErrorNetworkUnavailableReasonKey']!
}
fn ur_texts() [7]string {
	return ['NSURLErrorDomain', 'NSErrorFailingURLKey', 'NSErrorFailingURLStringKey', 'NSErrorFailingURLStringKey', 'NSURLErrorFailingURLPeerTrustErrorKey', 'NSURLErrorBackgroundTaskCancelledReasonKey', 'NSURLErrorNetworkUnavailableReasonKey']!
}
fn ur_api(native bool) URLApi {
	$if macos { if native {
		return URLApi{true, u64(C.dlopen(c'/System/Library/Frameworks/Foundation.framework/Foundation', 2)), u64(C.dlopen(c'/usr/lib/libobjc.A.dylib', 2)), u64(C.dlopen(c'/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation', 2))}
	} }
	return URLApi{}
}
fn ur_cell(api URLApi, name string) u64 {
	if api.native { return u64(C.dlsym(voidptr(api.foundation), unsafe { &char(name.str + 1) })) }
	return runtime_symbol('/System/Library/Frameworks/Foundation.framework/Foundation', name) or { panic(err) }
}
fn ur_class(api URLApi, name &char) u64 {
	if api.native { return unsafe { URLName(C.dlsym(voidptr(api.objc), c'objc_getClass'))(name) } }
	return ios_runtime.names[ctext(u64(name))]
}
fn ur_msg(api URLApi, object u64, name &char, a u64, b u64, c u64) u64 {
	if api.native {
		selector := unsafe { URLName(C.dlsym(voidptr(api.objc), c'sel_registerName'))(name) }
		return unsafe { URLMessage(C.dlsym(voidptr(api.objc), c'objc_msgSend'))(object, selector, a, b, c) }
	}
	return unsafe { URLMessage(voidptr(C.ios_objc_builtin))(object, u64(name), a, b, c) }
}
fn ur_retain(api URLApi, value u64) u64 {
	if api.native { return unsafe { URLRetain(C.dlsym(voidptr(api.objc), c'objc_retain'))(value) } }
	return objc_retain(value)
}
fn ur_release(api URLApi, value u64) {
	if api.native { unsafe { URLRelease(C.dlsym(voidptr(api.objc), c'objc_release'))(value) }; return }
	objc_release(value)
}
fn ur_pool(api URLApi) u64 {
	if api.native { return unsafe { URLPool(C.dlsym(voidptr(api.objc), c'objc_autoreleasePoolPush'))() } }
	return objc_pool_push()
}
fn ur_pop(api URLApi, pool u64) {
	if api.native { unsafe { URLRelease(C.dlsym(voidptr(api.objc), c'objc_autoreleasePoolPop'))(pool) }; return }
	objc_pool_pop(pool)
}
fn ur_text(api URLApi, value u64, expected string) {
	assert value != 0
	if !api.native { assert string_text(value) == expected; return }
	mut buffer := [1024]u8{}
	assert unsafe { URLBytes(C.dlsym(voidptr(api.core), c'CFStringGetCString'))(value, &char(&buffer[0]), 1024, 0x08000100) }
	assert buffer[expected.len] == 0 && C.memcmp(unsafe { &buffer[0] }, expected.str, usize(expected.len)) == 0
}
fn ur_reader(api URLApi, offset int) URLCells {
	mut cells := [7]u64{}
	names := ur_names(); texts := ur_texts()
	for turn in 0 .. 32 {
		pool := ur_pool(api)
		for step in 0 .. 7 {
			index := (offset + step) % 7; cell := ur_cell(api, names[index]); assert cell != 0 && cell % 8 == 0
			if turn == 0 { cells[index] = cell } else { assert cells[index] == cell }
			value := read64(cell); ur_text(api, value, texts[index])
			assert ur_retain(api, value) == value; ur_release(api, value)
			assert ur_msg(api, ur_retain(api, value), c'autorelease', 0, 0, 0) == value
		}
		ur_pop(api, pool)
	}
	return URLCells{cells}
}
fn ur_shared(api URLApi) {
	// Race first publication, including a reader beginning at the old alias.
	mut workers := []thread URLCells{}
	for offset in 0 .. 8 { workers << spawn ur_reader(api, offset % 7) }
	mut cells := [7]u64{}
	for i, worker in workers {
		got := worker.wait().values
		if i == 0 { cells = got } else { assert cells == got }
	}
	unsafe { workers.free() }
	for i in 0 .. 7 { for j in 0 .. i { assert cells[i] != cells[j] } }
	assert read64(cells[2]) == read64(cells[3])
	for i in [0, 1, 2, 4, 5, 6]! { for j in [0, 1, 2, 4, 5, 6]! { if i != j { assert read64(cells[i]) != read64(cells[j]) } } }
	if !api.native { assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 }
	// NSError consumes the globals as ordinary domain and userInfo strings.
	pool := ur_pool(api)
	keys := [read64(cells[5]), read64(cells[6])]!
	values := [ur_msg(api, ur_class(api, c'NSNumber'), c'numberWithInteger:', 1, 0, 0), ur_msg(api, ur_class(api, c'NSNumber'), c'numberWithInteger:', 2, 0, 0)]!
	dictionary := ur_msg(api, ur_class(api, c'NSDictionary'), c'dictionaryWithObjects:forKeys:count:', u64(unsafe { &values[0] }), u64(unsafe { &keys[0] }), 2)
	error_object := ur_msg(api, ur_class(api, c'NSError'), c'errorWithDomain:code:userInfo:', read64(cells[0]), u64(i64(-999)), dictionary)
	assert ur_retain(api, error_object) == error_object
	ur_pop(api, pool)
	check_pool := ur_pool(api)
	ur_text(api, ur_msg(api, error_object, c'domain', 0, 0, 0), 'NSURLErrorDomain')
	assert i64(ur_msg(api, error_object, c'code', 0, 0, 0)) == -999
	info := ur_msg(api, error_object, c'userInfo', 0, 0, 0)
	assert ur_msg(api, info, c'count', 0, 0, 0) == 2
	for i, key in keys {
		equal := ur_msg(api, ur_class(api, c'NSString'), c'stringWithUTF8String:', u64(ur_texts()[i + 5].str), 0, 0)
		for query in [key, equal]! { value := ur_msg(api, info, c'objectForKey:', query, 0, 0); assert ur_msg(api, value, c'integerValue', 0, 0, 0) == u64(i + 1) }
	}
	ur_release(api, error_object); ur_pop(api, check_pool)
	for i, cell in cells { ur_text(api, read64(cell), ur_texts()[i]) }
	if !api.native { assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 }
}
fn ur_teardown(object u64, selector &char) {
	// Shutdown has retired task creation, but pool destructors still need the
	// already-published global cells and their immortal string objects.
	assert ios_runtime.swift_concurrency_retired
	cell := ns_url_error_symbol('_NSURLErrorBackgroundTaskCancelledReasonKey') or { panic('constant retired before pool callback') }
	assert cell == ios_runtime.url_error_arena + 40
	assert string_text(read64(cell)) == 'NSURLErrorBackgroundTaskCancelledReasonKey'
	url_error_teardown_calls++
}
fn test_ns_url_error_constants() {
	$if macos {
		ur_shared(ur_api(true))
		println('IOS-URL-ERROR-NATIVE: seven pointer-sized string globals, exact historical spellings, distinct cells/shared URL-string alias, pool lifetimes, NSError userInfo lookup and eight concurrent readers')
	}
	if _ := ns_url_error_symbol('_NSURLErrorDomain') { assert false }
	for _ in 0 .. 2 {
		objc_start(); assert ios_runtime.url_error_arena == 0
		ur_shared(ur_api(false))
		for symbol in ['_NSURLErrorDomain', '_NSURLErrorFailingURLErrorKey', '_NSErrorFailingURLStringKey', '_NSURLErrorBackgroundTaskCancelledReasonKey', '_NSURLErrorNetworkUnavailableReasonKey']! {
			for library in ['/System/Library/Frameworks/UIKit.framework/UIKit', '/usr/lib/libSystem.B.dylib']! { if _ := runtime_symbol(library, symbol) { assert false } }
		}
		if _ := ns_url_error_symbol('_NSURLErrorInventedKey') { assert false }
		probe := objc_allocate_class(ios_runtime.names['NSObject'], c'VinixURLErrorTeardownProbe', 0); assert probe != 0
		assert objc_add_method(probe, u64(c'dealloc'), u64(unsafe { voidptr(ur_teardown) }), c'v16@0:8')
		objc_register_class(probe); objc_autorelease(objc_new(probe))
		// Cached globals remain available after task entry points retire.
		ios_runtime.swift_concurrency_retired = true
		before := url_error_teardown_calls
		objc_stop()
		assert url_error_teardown_calls == before + 1 && ios_runtime.url_error_arena == 0 && ios_runtime.live == 0 && ios_runtime.objects.len == 0
		if _ := ns_url_error_symbol('_NSURLErrorDomain') { assert false }
	}
	println('IOS-URL-ERROR: Foundation globals, sealed stable cells, immortal strings and shared deprecated alias, first-lookup contention, NSError integration, pool-destructor availability and two drained/unmapped lifetimes')
}

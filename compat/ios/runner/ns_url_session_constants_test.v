// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
type SCName = fn (&char) u64
type SCMessage = fn (u64, u64, u64, u64, u64) u64
type SCRetain = fn (u64) u64
type SCRelease = fn (u64)
type SCPool = fn () u64
type SCBytes = fn (u64, &char, i64, u32) bool
struct SCApi { native bool foundation u64 objc u64 core u64 }
struct SCCells { values [6]u64 }
__global session_constants_teardown_calls = 0
fn sc_names() [6]string {
 return ['_NSURLSessionDownloadTaskResumeData', '_NSURLSessionTaskPriorityDefault', '_NSURLSessionTaskPriorityLow', '_NSURLSessionTaskPriorityHigh', '_NSURLSessionTransferSizeUnknown', '_NSURLSessionUploadTaskResumeData']!
}
fn sc_api(native bool) SCApi {
	$if macos { if native {
		return SCApi{true, u64(C.dlopen(c'/System/Library/Frameworks/Foundation.framework/Foundation', 2)), u64(C.dlopen(c'/usr/lib/libobjc.A.dylib', 2)), u64(C.dlopen(c'/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation', 2))}
	} }
	return SCApi{}
}
fn sc_cell(api SCApi, name string) u64 {
	if api.native { return u64(C.dlsym(voidptr(api.foundation), unsafe { &char(name.str + 1) })) }
	return runtime_symbol('/System/Library/Frameworks/Foundation.framework/Foundation', name) or { panic(err) }
}
fn sc_class(api SCApi, name &char) u64 {
	if api.native { return unsafe { SCName(C.dlsym(voidptr(api.objc), c'objc_getClass'))(name) } }
	return ios_runtime.names[ctext(u64(name))]
}
fn sc_msg(api SCApi, object u64, name &char, a u64, b u64, c u64) u64 {
	if api.native {
		selector := unsafe { SCName(C.dlsym(voidptr(api.objc), c'sel_registerName'))(name) }
		return unsafe { SCMessage(C.dlsym(voidptr(api.objc), c'objc_msgSend'))(object, selector, a, b, c) }
	}
	return unsafe { SCMessage(voidptr(C.ios_objc_builtin))(object, u64(name), a, b, c) }
}
fn sc_retain(api SCApi, value u64) u64 {
	if api.native { return unsafe { SCRetain(C.dlsym(voidptr(api.objc), c'objc_retain'))(value) } }
	return objc_retain(value)
}
fn sc_release(api SCApi, value u64) {
	if api.native { unsafe { SCRelease(C.dlsym(voidptr(api.objc), c'objc_release'))(value) }; return }
	objc_release(value)
}
fn sc_pool(api SCApi) u64 {
	if api.native { return unsafe { SCPool(C.dlsym(voidptr(api.objc), c'objc_autoreleasePoolPush'))() } }
	return objc_pool_push()
}
fn sc_pop(api SCApi, pool u64) {
	if api.native { unsafe { SCRelease(C.dlsym(voidptr(api.objc), c'objc_autoreleasePoolPop'))(pool) }; return }
	objc_pool_pop(pool)
}
fn sc_text(api SCApi, value u64, expected string) {
	assert value != 0
	if !api.native { assert string_text(value) == expected; return }
	mut buffer := [1024]u8{}
	assert unsafe { SCBytes(C.dlsym(voidptr(api.core), c'CFStringGetCString'))(value, &char(&buffer[0]), 1024, 0x08000100) }
	assert buffer[expected.len] == 0 && C.memcmp(unsafe { &buffer[0] }, expected.str, usize(expected.len)) == 0
}

fn sc_check(api SCApi, index int, cell u64) {
 assert cell != 0
 if index in [0, 5]! {
  assert cell % 8 == 0
  value := read64(cell); expected := sc_names()[index][1..]
  sc_text(api, value, expected)
  assert sc_retain(api, value) == value; sc_release(api, value)
  assert sc_msg(api, sc_retain(api, value), c'autorelease', 0, 0, 0) == value
 } else if index == 4 {
  assert cell % 8 == 0 && i64(read64(cell)) == -1
 } else {
  assert cell % 4 == 0
  bits := [u32(0x3f000000), u32(0x3e800000), u32(0x3f400000)]!
  values := [f32(0.5), f32(0.25), f32(0.75)]!
  assert unsafe { *(&u32(cell)) } == bits[index - 1]
  assert unsafe { *(&f32(cell)) } == values[index - 1]
 }
}
fn sc_reader(api SCApi, offset int) SCCells {
 mut cells := [6]u64{}; names := sc_names()
 for turn in 0 .. 32 {
  pool := sc_pool(api)
  for step in 0 .. 6 {
   index := (offset + step) % 6; cell := sc_cell(api, names[index])
   if turn == 0 { cells[index] = cell } else { assert cells[index] == cell }
   sc_check(api, index, cell)
  }
  sc_pop(api, pool)
 }
 return SCCells{cells}
}
fn sc_shared(api SCApi) {
 mut workers := []thread SCCells{}
 for offset in 0 .. 8 { workers << spawn sc_reader(api, offset % 6) }
 mut cells := [6]u64{}
 for i, worker in workers { got := worker.wait().values; if i == 0 { cells = got } else { assert cells == got } }
 unsafe { workers.free() }
 for i in 0 .. 6 { for j in 0 .. i { assert cells[i] != cells[j] } }
 assert read64(cells[0]) != read64(cells[5])
 if !api.native { assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 }
 // NSError retains resume data after the producing pool drains. Equal fresh
 // NSString keys must retrieve exactly the same NSData, including NUL bytes.
 pool := sc_pool(api)
 payload := [u8(0), 0xff, 0x42, 0, 0x7f]!
 data := sc_msg(api, sc_class(api, c'NSData'), c'dataWithBytes:length:', u64(unsafe { &payload[0] }), 5, 0)
 keys := [read64(cells[0]), read64(cells[5])]!; values := [data, data]!
 info := sc_msg(api, sc_class(api, c'NSDictionary'), c'dictionaryWithObjects:forKeys:count:', u64(unsafe { &values[0] }), u64(unsafe { &keys[0] }), 2)
 domain := sc_msg(api, sc_class(api, c'NSString'), c'stringWithUTF8String:', u64(c'NSURLErrorDomain'), 0, 0)
 error_object := sc_msg(api, sc_class(api, c'NSError'), c'errorWithDomain:code:userInfo:', domain, u64(i64(-999)), info)
 assert error_object != 0 && sc_retain(api, error_object) == error_object
 sc_pop(api, pool)
 check_pool := sc_pool(api)
 retained_info := sc_msg(api, error_object, c'userInfo', 0, 0, 0)
 assert sc_msg(api, retained_info, c'count', 0, 0, 0) == 2
 for index in [0, 5]! {
  name := sc_names()[index]
  equal := sc_msg(api, sc_class(api, c'NSString'), c'stringWithUTF8String:', u64(unsafe { name.str + 1 }), 0, 0)
  for query in [read64(cells[index]), equal]! {
   got := sc_msg(api, retained_info, c'objectForKey:', query, 0, 0)
   assert got == data && sc_msg(api, got, c'length', 0, 0, 0) == 5
   bytes := sc_msg(api, got, c'bytes', 0, 0, 0)
   assert bytes != 0 && C.memcmp(voidptr(bytes), unsafe { &payload[0] }, 5) == 0
  }
 }
 sc_release(api, error_object); sc_pop(api, check_pool)
 final_pool := sc_pool(api)
 for i, cell in cells { sc_check(api, i, cell) }
 sc_pop(api, final_pool)
 if !api.native { assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 }
}
fn sc_teardown(object u64, selector &char) {
 assert ios_runtime.swift_concurrency_retired
 for i, name in sc_names() { cell := ns_url_session_constant_symbol(name) or { panic('session constant retired before pool callback') }; sc_check(SCApi{}, i, cell) }
 session_constants_teardown_calls++
}
fn test_ns_url_session_constants() {
 $if macos {
  sc_shared(sc_api(true))
  println('IOS-SESSION-CONSTANTS-NATIVE: float32 priorities, int64 sentinel, two NSString cells, stable addresses, NSError resume bytes across pools and eight concurrent readers')
 }
 if _ := ns_url_session_constant_symbol('_NSURLSessionDownloadTaskResumeData') { assert false }
 for _ in 0 .. 2 {
  objc_start(); assert ios_runtime.url_session_constants_arena == 0
  ios_runtime.swift_concurrency_retired = true
  if _ := ns_url_session_constant_symbol('_NSURLSessionTaskPriorityDefault') { assert false }
  ios_runtime.swift_concurrency_retired = false
  sc_shared(SCApi{})
  for symbol in sc_names() { for library in ['/System/Library/Frameworks/UIKit.framework/UIKit', '/usr/lib/libSystem.B.dylib']! { if _ := runtime_symbol(library, symbol) { assert false } } }
  for symbol in ['_NSURLSessionInventedKey', '_NSURLSession']! { if _ := ns_url_session_constant_symbol(symbol) { assert false } }
  probe := objc_allocate_class(ios_runtime.names['NSObject'], c'VinixSessionConstantsTeardownProbe', 0)
  assert probe != 0 && objc_add_method(probe, u64(c'dealloc'), u64(unsafe { voidptr(sc_teardown) }), c'v16@0:8')
  objc_register_class(probe); objc_autorelease(objc_new(probe))
  ios_runtime.swift_concurrency_retired = true
  before := session_constants_teardown_calls; objc_stop()
  assert session_constants_teardown_calls == before + 1 && ios_runtime.url_session_constants_arena == 0 && ios_runtime.live == 0 && ios_runtime.objects.len == 0
  if _ := ns_url_session_constant_symbol('_NSURLSessionTaskPriorityDefault') { assert false }
 }
 println('IOS-SESSION-CONSTANTS: exact mixed-width data exports, immortal resume keys, cold lookup contention, NSError NSData round trips, pool-destructor availability and two drained/unmapped lifetimes')
}

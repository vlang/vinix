// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.dlclose(voidptr) i32

type IEXName = fn (&char) u64
type IEXMessage = fn (u64, u64, u64, u64, u64) u64
type IEXUnary = fn (u64) u64
type IEXRelease = fn (u64)
type IEXPool = fn () u64
type IEXBytes = fn (u64, &u8, i64, u32) bool
struct IEXApi { native bool foundation u64 core u64 objc u64 }
__global iex_teardown_calls = 0

fn iex_cell(api IEXApi, core bool) u64 {
 if api.native { return u64(C.dlsym(unsafe { voidptr(if core { api.core } else { api.foundation }) }, c'NSInternalInconsistencyException')) }
 library := if core { '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation' } else { '/System/Library/Frameworks/Foundation.framework/Foundation' }
 return runtime_symbol(library, '_NSInternalInconsistencyException') or { panic(err) }
}
fn iex_msg(api IEXApi, object u64, name &char, a u64, b u64, c u64) u64 {
 if api.native {
  selector := unsafe { IEXName(C.dlsym(voidptr(api.objc), c'sel_registerName'))(name) }
  return unsafe { IEXMessage(C.dlsym(voidptr(api.objc), c'objc_msgSend'))(object, selector, a, b, c) }
 }
 return unsafe { IEXMessage(voidptr(C.ios_objc_builtin))(object, u64(name), a, b, c) }
}
fn iex_class(api IEXApi, name &char) u64 {
 if api.native { return unsafe { IEXName(C.dlsym(voidptr(api.objc), c'objc_getClass'))(name) } }
 return ios_runtime.names[ctext(u64(name))]
}
fn iex_pool(api IEXApi) u64 {
 if api.native { return unsafe { IEXPool(C.dlsym(voidptr(api.objc), c'objc_autoreleasePoolPush'))() } }
 return objc_pool_push()
}
fn iex_pop(api IEXApi, pool u64) {
 if api.native { unsafe { IEXRelease(C.dlsym(voidptr(api.objc), c'objc_autoreleasePoolPop'))(pool) }; return }
 objc_pool_pop(pool)
}
fn iex_retain(api IEXApi, object u64) u64 {
 if api.native { return unsafe { IEXUnary(C.dlsym(voidptr(api.core), c'CFRetain'))(object) } }
 return objc_retain(object)
}
fn iex_release(api IEXApi, object u64) {
 if api.native { unsafe { IEXRelease(C.dlsym(voidptr(api.core), c'CFRelease'))(object) }; return }
 objc_release(object)
}
fn iex_hash(api IEXApi, object u64) u64 {
 if api.native { return unsafe { IEXUnary(C.dlsym(voidptr(api.core), c'CFHash'))(object) } }
 return cf_hash(object)
}
fn iex_text(api IEXApi, object u64) {
 assert object != 0
 expected := 'NSInternalInconsistencyException'
 if !api.native { assert string_text(object) == expected && cf_type_id(object) == cf_string_id(); return }
 mut bytes := [128]u8{}
 assert unsafe { IEXBytes(C.dlsym(voidptr(api.core), c'CFStringGetCString'))(object, &bytes[0], 128, 0x08000100) }
 assert bytes[expected.len] == 0 && C.memcmp(unsafe { &bytes[0] }, expected.str, usize(expected.len)) == 0
}
fn iex_reader(api IEXApi, offset int) u64 {
 mut cell := u64(0)
 for turn in 0 .. 64 {
  got := iex_cell(api, (offset + turn) % 2 == 0)
  assert got != 0 && got % 8 == 0
  if turn == 0 { cell = got } else { assert got == cell }
  value := read64(got); assert value != got; iex_text(api, value)
  assert iex_retain(api, value) == value; iex_release(api, value)
 }
 return cell
}
fn iex_shared(api IEXApi) u64 {
 mut workers := []thread u64{}
 for offset in 0 .. 8 { workers << spawn iex_reader(api, offset) }
 mut cell := u64(0)
 for i, worker in workers { got := worker.wait(); if i == 0 { cell = got } else { assert cell == got } }
 unsafe { workers.free() }
 assert iex_cell(api, false) == cell && iex_cell(api, true) == cell
 value := read64(cell); expected := 'NSInternalInconsistencyException'
 if !api.native {
  assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 && ios_runtime.foundation_keys_arena == 0
  assert cell == ios_runtime.ns_internal_exception_arena && value == cell + 32
  assert read64(value) == ios_runtime.names['NSString'] && read64(value + 8) == 0x7c8 && read64(value + 24) == u64(expected.len)
  bytes := read64(value + 16); assert bytes == cell + 64
  assert bytes + u64(expected.len) < cell + u64(C.getpagesize())
  assert unsafe { *(&u8(bytes + u64(expected.len))) } == 0 && value in ios_runtime.constants
 }
 pool := iex_pool(api)
 assert iex_msg(api, iex_retain(api, value), c'autorelease', 0, 0, 0) == value
 copy := iex_msg(api, value, c'copy', 0, 0, 0); assert copy == value; iex_release(api, copy)
 equal := iex_msg(api, iex_class(api, c'NSString'), c'stringWithUTF8String:', u64(c'NSInternalInconsistencyException'), 0, 0)
 assert iex_msg(api, value, c'length', 0, 0, 0) == u64(expected.len)
 assert iex_msg(api, value, c'isEqualToString:', equal, 0, 0) == 1 && iex_hash(api, value) == iex_hash(api, equal)
 keys := [value]!; values := [equal]!
 dictionary := iex_msg(api, iex_class(api, c'NSDictionary'), c'dictionaryWithObjects:forKeys:count:', u64(unsafe { &values[0] }), u64(unsafe { &keys[0] }), 1)
 assert iex_msg(api, dictionary, c'objectForKey:', equal, 0, 0) == equal
 // The IPA uses this name as an NSError domain and code -1, not a throw.
 error_class := iex_class(api, c'NSError')
 empty := iex_msg(api, error_class, c'errorWithDomain:code:userInfo:', value, u64(i64(-1)), 0)
 assert empty != 0 && i64(iex_msg(api, empty, c'code', 0, 0, 0)) == -1
 iex_text(api, iex_msg(api, empty, c'domain', 0, 0, 0))
 error := iex_msg(api, error_class, c'errorWithDomain:code:userInfo:', value, u64(i64(-1)), dictionary)
 assert error != 0 && iex_retain(api, error) == error
 iex_pop(api, pool)
 check_pool := iex_pool(api)
 assert i64(iex_msg(api, error, c'code', 0, 0, 0)) == -1
 iex_text(api, iex_msg(api, error, c'domain', 0, 0, 0))
 info := iex_msg(api, error, c'userInfo', 0, 0, 0)
 iex_text(api, iex_msg(api, info, c'objectForKey:', value, 0, 0))
 iex_release(api, error); iex_pop(api, check_pool); iex_text(api, read64(cell))
 if !api.native { assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 }
 return cell
}
fn iex_teardown(object u64, selector &char) {
 assert ios_runtime.swift_concurrency_retired
 cell := iex_cell(IEXApi{}, true); assert cell == iex_cell(IEXApi{}, false)
 iex_text(IEXApi{}, read64(cell)); assert read64(cell) in ios_runtime.constants
 iex_teardown_calls++
}
fn test_ns_internal_exception() {
 $if macos {
  api := IEXApi{true, u64(C.dlopen(c'/System/Library/Frameworks/Foundation.framework/Foundation', 2)), u64(C.dlopen(c'/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation', 2)), u64(C.dlopen(c'/usr/lib/libobjc.A.dylib', 2))}
  assert api.foundation != 0 && api.core != 0 && api.objc != 0
  iex_shared(api)
  for handle in [api.objc, api.core, api.foundation]! { assert C.dlclose(unsafe { voidptr(handle) }) == 0 }
  println('NATIVE-NS-INTERNAL-EXCEPTION: shared NSString data cell and exact name, immortal ownership, equal-string dictionary lookup, NSError code -1 with nil/retained userInfo across pools and eight concurrent readers')
 }
 if _ := ns_internal_exception_symbol('_NSInternalInconsistencyException') { assert false }
 for _ in 0 .. 2 {
  objc_start(); assert ios_runtime.ns_internal_exception_arena == 0
  ns_internal_exception_stop(); assert ios_runtime.ns_internal_exception_arena == 0
  ios_runtime.swift_concurrency_retired = true
  if _ := ns_internal_exception_symbol('_NSInternalInconsistencyException') { assert false }
  ios_runtime.swift_concurrency_retired = false
  cell := iex_shared(IEXApi{}); value := read64(cell)
  for library in ['/System/Library/Frameworks/UIKit.framework/UIKit', '/usr/lib/libSystem.B.dylib']! { if _ := runtime_symbol(library, '_NSInternalInconsistencyException') { assert false } }
  for name in ['_NSInternalInconsistencyExceptionName', '_NSInvalidArgumentException']! { if _ := ns_internal_exception_symbol(name) { assert false } }
  probe := objc_allocate_class(ios_runtime.names['NSObject'], c'VinixInternalExceptionTeardownProbe', 0); assert probe != 0
  assert objc_add_method(probe, u64(c'dealloc'), u64(unsafe { voidptr(iex_teardown) }), c'v16@0:8')
  objc_register_class(probe); objc_autorelease(objc_new(probe))
  ios_runtime.swift_concurrency_retired = true; assert iex_cell(IEXApi{}, true) == cell
  before := iex_teardown_calls; objc_stop()
  assert iex_teardown_calls == before + 1 && ios_runtime.ns_internal_exception_arena == 0 && ios_runtime.live == 0 && ios_runtime.objects.len == 0
  assert value !in ios_runtime.constants
  if _ := ns_internal_exception_symbol('_NSInternalInconsistencyException') { assert false }
 }
 println('IOS-NS-INTERNAL-EXCEPTION: shared sealed pointer cell with exact exception-name CFString, eight contended cold publishers, immutable string/dictionary behavior, NSError domain and retained userInfo, retirement guards, callback access and two drained/unmapped lifetimes')
}

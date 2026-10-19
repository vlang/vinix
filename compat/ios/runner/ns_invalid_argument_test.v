// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.dlclose(voidptr) i32

type IARName = fn (&char) u64
type IARMessage = fn (u64, u64, u64, u64, u64) u64
type IARUnary = fn (u64) u64
type IARRelease = fn (u64)
type IARPool = fn () u64
type IARBytes = fn (u64, &u8, i64, u32) bool
struct IARApi { native bool foundation u64 core u64 objc u64 }
struct IARCells { values [2]u64 }
__global iar_teardown_calls = 0

fn iar_cell(api IARApi, core bool) u64 {
 if api.native { return u64(C.dlsym(unsafe { voidptr(if core { api.core } else { api.foundation }) }, c'NSInvalidArgumentException')) }
 library := if core { '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation' } else { '/System/Library/Frameworks/Foundation.framework/Foundation' }
 return runtime_symbol(library, '_NSInvalidArgumentException') or { panic(err) }
}
fn iar_internal_cell(api IARApi, core bool) u64 {
 if api.native { return u64(C.dlsym(unsafe { voidptr(if core { api.core } else { api.foundation }) }, c'NSInternalInconsistencyException')) }
 library := if core { '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation' } else { '/System/Library/Frameworks/Foundation.framework/Foundation' }
 return runtime_symbol(library, '_NSInternalInconsistencyException') or { panic(err) }
}
fn iar_msg(api IARApi, object u64, name &char, a u64, b u64, c u64) u64 {
 if api.native {
  selector := unsafe { IARName(C.dlsym(voidptr(api.objc), c'sel_registerName'))(name) }
  return unsafe { IARMessage(C.dlsym(voidptr(api.objc), c'objc_msgSend'))(object, selector, a, b, c) }
 }
 return unsafe { IARMessage(voidptr(C.ios_objc_builtin))(object, u64(name), a, b, c) }
}
fn iar_class(api IARApi, name &char) u64 {
 if api.native { return unsafe { IARName(C.dlsym(voidptr(api.objc), c'objc_getClass'))(name) } }
 return ios_runtime.names[ctext(u64(name))]
}
fn iar_pool(api IARApi) u64 {
 if api.native { return unsafe { IARPool(C.dlsym(voidptr(api.objc), c'objc_autoreleasePoolPush'))() } }
 return objc_pool_push()
}
fn iar_pop(api IARApi, pool u64) {
 if api.native { unsafe { IARRelease(C.dlsym(voidptr(api.objc), c'objc_autoreleasePoolPop'))(pool) }; return }
 objc_pool_pop(pool)
}
fn iar_retain(api IARApi, object u64) u64 {
 if api.native { return unsafe { IARUnary(C.dlsym(voidptr(api.core), c'CFRetain'))(object) } }
 return objc_retain(object)
}
fn iar_release(api IARApi, object u64) {
 if api.native { unsafe { IARRelease(C.dlsym(voidptr(api.core), c'CFRelease'))(object) }; return }
 objc_release(object)
}
fn iar_hash(api IARApi, object u64) u64 {
 if api.native { return unsafe { IARUnary(C.dlsym(voidptr(api.core), c'CFHash'))(object) } }
 return cf_hash(object)
}
fn iar_text(api IARApi, object u64) {
 iar_expected_text(api, object, 'NSInvalidArgumentException')
}
fn iar_expected_text(api IARApi, object u64, expected string) {
 assert object != 0
 if !api.native { assert string_text(object) == expected && cf_type_id(object) == cf_string_id(); return }
 mut bytes := [128]u8{}
 assert unsafe { IARBytes(C.dlsym(voidptr(api.core), c'CFStringGetCString'))(object, &bytes[0], 128, 0x08000100) }
 assert bytes[expected.len] == 0 && C.memcmp(unsafe { &bytes[0] }, expected.str, usize(expected.len)) == 0
}
fn iar_reader(api IARApi, offset int) IARCells {
 mut cells := [2]u64{}
 for turn in 0 .. 64 {
  for step in 0 .. 2 {
   index := (offset + step) % 2; core := (offset + turn) % 2 == 0
   got := if index == 0 { iar_cell(api, core) } else { iar_internal_cell(api, core) }
   assert got != 0 && got % 8 == 0
   if turn == 0 { cells[index] = got } else { assert got == cells[index] }
   value := read64(got); assert value != got
   iar_expected_text(api, value, if index == 0 { 'NSInvalidArgumentException' } else { 'NSInternalInconsistencyException' })
   assert iar_retain(api, value) == value; iar_release(api, value)
  }
 }
 return IARCells{cells}
}
fn iar_shared(api IARApi) u64 {
 mut workers := []thread IARCells{}
 for offset in 0 .. 8 { workers << spawn iar_reader(api, offset) }
 mut cells := [2]u64{}
 for i, worker in workers { got := worker.wait().values; if i == 0 { cells = got } else { assert cells == got } }
 unsafe { workers.free() }
 cell := cells[0]; internal := cells[1]
 assert cell != internal && read64(cell) != read64(internal)
 assert iar_cell(api, false) == cell && iar_cell(api, true) == cell
 assert iar_internal_cell(api, false) == internal && iar_internal_cell(api, true) == internal
 value := read64(cell); expected := 'NSInvalidArgumentException'
 if !api.native {
  assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 && ios_runtime.foundation_keys_arena == 0
  arena := ios_runtime.ns_internal_exception_arena
  assert cell == arena + 8 && value == arena + 128
  assert read64(value) == ios_runtime.names['NSString'] && read64(value + 8) == 0x7c8 && read64(value + 24) == u64(expected.len)
  bytes := read64(value + 16); assert bytes == arena + 160
  assert bytes + u64(expected.len) < arena + u64(C.getpagesize())
  assert unsafe { *(&u8(bytes + u64(expected.len))) } == 0 && value in ios_runtime.constants
  assert internal == arena && read64(internal) == arena + 32 && read64(read64(internal) + 16) == arena + 64
  iar_expected_text(api, read64(internal), 'NSInternalInconsistencyException')
  assert read64(internal) in ios_runtime.constants
 }
 pool := iar_pool(api)
 assert iar_msg(api, iar_retain(api, value), c'autorelease', 0, 0, 0) == value
 copy := iar_msg(api, value, c'copy', 0, 0, 0); assert copy == value; iar_release(api, copy)
 equal := iar_msg(api, iar_class(api, c'NSString'), c'stringWithUTF8String:', u64(c'NSInvalidArgumentException'), 0, 0)
 assert iar_msg(api, value, c'length', 0, 0, 0) == u64(expected.len)
 assert iar_msg(api, value, c'isEqualToString:', equal, 0, 0) == 1 && iar_hash(api, value) == iar_hash(api, equal)
 keys := [value]!; values := [equal]!
 dictionary := iar_msg(api, iar_class(api, c'NSDictionary'), c'dictionaryWithObjects:forKeys:count:', u64(unsafe { &values[0] }), u64(unsafe { &keys[0] }), 1)
 assert iar_msg(api, dictionary, c'objectForKey:', equal, 0, 0) == equal
 iar_pop(api, pool); iar_text(api, read64(cell))
 if !api.native { assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 }
 return cell
}
fn iar_teardown(object u64, selector &char) {
 assert ios_runtime.swift_concurrency_retired
 cell := iar_cell(IARApi{}, true); assert cell == iar_cell(IARApi{}, false)
 iar_text(IARApi{}, read64(cell)); assert read64(cell) in ios_runtime.constants
 internal := iar_internal_cell(IARApi{}, false)
 assert internal + 8 == cell && read64(internal) in ios_runtime.constants
 iar_expected_text(IARApi{}, read64(internal), 'NSInternalInconsistencyException')
 iar_teardown_calls++
}
fn test_ns_invalid_argument() {
 $if macos {
  api := IARApi{true, u64(C.dlopen(c'/System/Library/Frameworks/Foundation.framework/Foundation', 2)), u64(C.dlopen(c'/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation', 2)), u64(C.dlopen(c'/usr/lib/libobjc.A.dylib', 2))}
  assert api.foundation != 0 && api.core != 0 && api.objc != 0
  iar_shared(api)
  for handle in [api.objc, api.core, api.foundation]! { assert C.dlclose(unsafe { voidptr(handle) }) == 0 }
  println('NATIVE-NS-INVALID-ARGUMENT: shared NSString data cell and exact name, distinct internal-inconsistency value, immortal ownership, equal-string dictionary lookup, pool lifetimes and eight mixed-name concurrent readers')
 }
 if _ := ns_invalid_argument_symbol('_NSInvalidArgumentException') { assert false }
 for _ in 0 .. 2 {
  objc_start(); assert ios_runtime.ns_internal_exception_arena == 0
  ns_internal_exception_stop(); assert ios_runtime.ns_internal_exception_arena == 0
  ios_runtime.swift_concurrency_retired = true
  if _ := ns_invalid_argument_symbol('_NSInvalidArgumentException') { assert false }
  ios_runtime.swift_concurrency_retired = false
  cell := iar_shared(IARApi{}); value := read64(cell); internal := read64(cell - 8)
  for library in ['/System/Library/Frameworks/UIKit.framework/UIKit', '/usr/lib/libSystem.B.dylib']! { if _ := runtime_symbol(library, '_NSInvalidArgumentException') { assert false } }
  for name in ['_NSInvalidArgumentExceptionName', '_NSRangeException']! { if _ := ns_invalid_argument_symbol(name) { assert false } }
  probe := objc_allocate_class(ios_runtime.names['NSObject'], c'VinixInvalidArgumentTeardownProbe', 0); assert probe != 0
  assert objc_add_method(probe, u64(c'dealloc'), u64(unsafe { voidptr(iar_teardown) }), c'v16@0:8')
  objc_register_class(probe); objc_autorelease(objc_new(probe))
  ios_runtime.swift_concurrency_retired = true; assert iar_cell(IARApi{}, true) == cell
  before := iar_teardown_calls; objc_stop()
  assert iar_teardown_calls == before + 1 && ios_runtime.ns_internal_exception_arena == 0 && ios_runtime.live == 0 && ios_runtime.objects.len == 0
  assert value !in ios_runtime.constants && internal !in ios_runtime.constants
  if _ := ns_invalid_argument_symbol('_NSInvalidArgumentException') { assert false }
 }
 println('IOS-NS-INVALID-ARGUMENT: shared sealed pointer cell with exact exception-name CFString, eight mixed-name contended cold publishers, preserved internal-inconsistency layout, immutable string/dictionary behavior, retirement guards, both-name callback access and two drained/unmapped lifetimes')
}

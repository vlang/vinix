// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.dlclose(voidptr) i32

type ISOName = fn (&char) u64
type ISOMessage = fn (u64, u64, u64, u64, u64) u64
type ISOUnary = fn (u64) u64
type ISORelease = fn (u64)
type ISOPool = fn () u64
type ISOBytes = fn (u64, &u8, i64, u32) bool
struct ISOApi { native bool foundation u64 core u64 objc u64 }
__global iso_teardown_calls = 0

fn iso_cell(api ISOApi, core bool) u64 {
 if api.native {
  return u64(C.dlsym(unsafe { voidptr(if core { api.core } else { api.foundation }) }, c'NSCalendarIdentifierISO8601'))
 }
 library := if core { '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation' } else { '/System/Library/Frameworks/Foundation.framework/Foundation' }
 return runtime_symbol(library, '_NSCalendarIdentifierISO8601') or { panic(err) }
}
fn iso_msg(api ISOApi, object u64, name &char, a u64, b u64, c u64) u64 {
 if api.native {
  selector := unsafe { ISOName(C.dlsym(voidptr(api.objc), c'sel_registerName'))(name) }
  return unsafe { ISOMessage(C.dlsym(voidptr(api.objc), c'objc_msgSend'))(object, selector, a, b, c) }
 }
 return unsafe { ISOMessage(voidptr(C.ios_objc_builtin))(object, u64(name), a, b, c) }
}
fn iso_class(api ISOApi, name &char) u64 {
 if api.native { return unsafe { ISOName(C.dlsym(voidptr(api.objc), c'objc_getClass'))(name) } }
 return ios_runtime.names[ctext(u64(name))]
}
fn iso_pool(api ISOApi) u64 {
 if api.native { return unsafe { ISOPool(C.dlsym(voidptr(api.objc), c'objc_autoreleasePoolPush'))() } }
 return objc_pool_push()
}
fn iso_pop(api ISOApi, pool u64) {
 if api.native { unsafe { ISORelease(C.dlsym(voidptr(api.objc), c'objc_autoreleasePoolPop'))(pool) }; return }
 objc_pool_pop(pool)
}
fn iso_retain(api ISOApi, object u64) u64 {
 if api.native { return unsafe { ISOUnary(C.dlsym(voidptr(api.core), c'CFRetain'))(object) } }
 return objc_retain(object)
}
fn iso_release(api ISOApi, object u64) {
 if api.native { unsafe { ISORelease(C.dlsym(voidptr(api.core), c'CFRelease'))(object) }; return }
 objc_release(object)
}
fn iso_hash(api ISOApi, object u64) u64 {
 if api.native { return unsafe { ISOUnary(C.dlsym(voidptr(api.core), c'CFHash'))(object) } }
 return cf_hash(object)
}
fn iso_text(api ISOApi, object u64) {
 assert object != 0
 if !api.native { assert string_text(object) == 'iso8601'; return }
 mut bytes := [16]u8{}
 assert unsafe { ISOBytes(C.dlsym(voidptr(api.core), c'CFStringGetCString'))(object, &bytes[0], 16, 0x08000100) }
 assert bytes[7] == 0 && C.memcmp(unsafe { &bytes[0] }, c'iso8601', 7) == 0
}
fn iso_reader(api ISOApi, offset int) u64 {
 mut cell := u64(0)
 for turn in 0 .. 64 {
  got := iso_cell(api, (offset + turn) % 2 == 0)
  assert got != 0 && got % 8 == 0
  if turn == 0 { cell = got } else { assert got == cell }
  value := read64(got); assert value != got; iso_text(api, value)
  assert iso_retain(api, value) == value; iso_release(api, value)
 }
 return cell
}
fn iso_shared(api ISOApi) u64 {
 mut workers := []thread u64{}
 for offset in 0 .. 8 { workers << spawn iso_reader(api, offset) }
 mut cell := u64(0)
 for i, worker in workers { got := worker.wait(); if i == 0 { cell = got } else { assert cell == got } }
 unsafe { workers.free() }
 assert iso_cell(api, false) == cell && iso_cell(api, true) == cell
 value := read64(cell)
 if !api.native {
  assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
  arena := ios_runtime.foundation_keys_arena
  assert arena != 0 && cell == arena + 24 && value == arena + 128
  assert read64(value) == ios_runtime.names['NSString'] && read64(value + 8) == 0x7c8 && read64(value + 24) == 7
  bytes := read64(value + 16)
  assert bytes >= arena + 160 && bytes + 7 < arena + u64(C.getpagesize())
  assert unsafe { *(&u8(bytes + 7)) } == 0 && value in ios_runtime.constants
  for i, name in ['_NSUbiquityIdentityDidChangeNotification', '_NSUnderlyingErrorKey', '_NSUserActivityTypeBrowsingWeb']! {
   other := ns_foundation_key_symbol(name) or { panic(name) }
   assert other == arena + u64(i * 8) && read64(other) == arena + 32 + u64(i * 32)
   assert string_text(read64(other)) == ['NSUbiquityIdentityDidChangeNotification', 'NSUnderlyingError', 'NSUserActivityTypeBrowsingWeb']![i]
  }
 }
 pool := iso_pool(api)
 assert iso_msg(api, iso_retain(api, value), c'autorelease', 0, 0, 0) == value
 copy := iso_msg(api, value, c'copy', 0, 0, 0)
 assert copy == value; iso_release(api, copy)
 equal := iso_msg(api, iso_class(api, c'NSString'), c'stringWithUTF8String:', u64(c'iso8601'), 0, 0)
 assert iso_msg(api, value, c'length', 0, 0, 0) == 7
 assert iso_msg(api, value, c'isEqualToString:', equal, 0, 0) == 1 && iso_hash(api, value) == iso_hash(api, equal)
 keys := [value]!; values := [equal]!
 dictionary := iso_msg(api, iso_class(api, c'NSDictionary'), c'dictionaryWithObjects:forKeys:count:', u64(unsafe { &values[0] }), u64(unsafe { &keys[0] }), 1)
 assert iso_msg(api, dictionary, c'objectForKey:', equal, 0, 0) == equal
 iso_pop(api, pool); iso_text(api, read64(cell))
 if !api.native { assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 }
 return cell
}
fn iso_teardown(object u64, selector &char) {
 assert ios_runtime.swift_concurrency_retired
 cell := iso_cell(ISOApi{}, true)
 assert cell == iso_cell(ISOApi{}, false); iso_text(ISOApi{}, read64(cell))
 for name in ['_NSUbiquityIdentityDidChangeNotification', '_NSUnderlyingErrorKey', '_NSUserActivityTypeBrowsingWeb']! {
  other := ns_foundation_key_symbol(name) or { panic(name) }; assert read64(other) in ios_runtime.constants
 }
 iso_teardown_calls++
}
fn test_ns_calendar_iso8601() {
 $if macos {
  api := ISOApi{true, u64(C.dlopen(c'/System/Library/Frameworks/Foundation.framework/Foundation', 2)), u64(C.dlopen(c'/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation', 2)), u64(C.dlopen(c'/usr/lib/libobjc.A.dylib', 2))}
  assert api.foundation != 0 && api.core != 0 && api.objc != 0
  iso_shared(api)
  for handle in [api.objc, api.core, api.foundation]! { assert C.dlclose(unsafe { voidptr(handle) }) == 0 }
  println('NATIVE-NS-CALENDAR-ISO8601: shared aligned Foundation/CoreFoundation NSString pointer cell, exact iso8601 value, immortal ownership, equal-string dictionary lookup and eight concurrent readers')
 }
 if _ := ns_foundation_key_symbol('_NSCalendarIdentifierISO8601') { assert false }
 for _ in 0 .. 2 {
  objc_start(); assert ios_runtime.foundation_keys_arena == 0
  ios_runtime.swift_concurrency_retired = true
  if _ := ns_foundation_key_symbol('_NSCalendarIdentifierISO8601') { assert false }
  ios_runtime.swift_concurrency_retired = false
  cell := iso_shared(ISOApi{}); value := read64(cell)
  for library in ['/System/Library/Frameworks/UIKit.framework/UIKit', '/usr/lib/libSystem.B.dylib']! { if _ := runtime_symbol(library, '_NSCalendarIdentifierISO8601') { assert false } }
  for name in ['_NSCalendarIdentifierInvented', '_NSCalendarIdentifierGregorian']! { if _ := ns_foundation_key_symbol(name) { assert false } }
  probe := objc_allocate_class(ios_runtime.names['NSObject'], c'VinixISO8601TeardownProbe', 0); assert probe != 0
  assert objc_add_method(probe, u64(c'dealloc'), u64(unsafe { voidptr(iso_teardown) }), c'v16@0:8')
  objc_register_class(probe); objc_autorelease(objc_new(probe))
  ios_runtime.swift_concurrency_retired = true
  assert iso_cell(ISOApi{}, true) == cell
  before := iso_teardown_calls; objc_stop()
  assert iso_teardown_calls == before + 1 && ios_runtime.foundation_keys_arena == 0 && ios_runtime.live == 0 && ios_runtime.objects.len == 0
  assert value !in ios_runtime.constants
  if _ := ns_foundation_key_symbol('_NSCalendarIdentifierISO8601') { assert false }
 }
 println('IOS-NS-CALENDAR-ISO8601: shared sealed data cell with exact iso8601 value, eight contended cold publishers, NSString and dictionary interoperability, existing key layout, retirement guards, callback availability and two drained/unmapped lifetimes')
}

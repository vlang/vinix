// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.dlclose(voidptr) i32

type UCDName = fn (&char) u64
type UCDMessage = fn (u64, u64, u64, u64, u64) u64
type UCDKeep = fn (u64) u64
type UCDDrop = fn (u64)
type UCDPool = fn () u64
type UCDBytes = fn (u64, &char, i64, u32) bool
struct UCDApi { native bool foundation u64 core u64 objc u64 }

fn ucd_cell(api UCDApi, core bool, cf bool) u64 {
 name := if cf { '_kCFURLCreationDateKey' } else { '_NSURLCreationDateKey' }
 if api.native { return u64(C.dlsym(unsafe { voidptr(if core { api.core } else { api.foundation }) }, unsafe { &char(name.str + 1) })) }
 library := if core { '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation' } else { '/System/Library/Frameworks/Foundation.framework/Foundation' }
 return runtime_symbol(library, name) or { panic(err) }
}
fn ucd_msg(api UCDApi, object u64, name &char, a u64, b u64, c u64) u64 {
 if api.native {
  selector := unsafe { UCDName(C.dlsym(voidptr(api.objc), c'sel_registerName'))(name) }
  return unsafe { UCDMessage(C.dlsym(voidptr(api.objc), c'objc_msgSend'))(object, selector, a, b, c) }
 }
 return unsafe { UCDMessage(voidptr(C.ios_objc_builtin))(object, u64(name), a, b, c) }
}
fn ucd_class(api UCDApi, name &char) u64 {
 if api.native { return unsafe { UCDName(C.dlsym(voidptr(api.objc), c'objc_getClass'))(name) } }
 return ios_runtime.names[ctext(u64(name))]
}
fn ucd_pool(api UCDApi) u64 {
 if api.native { return unsafe { UCDPool(C.dlsym(voidptr(api.objc), c'objc_autoreleasePoolPush'))() } }
 return objc_pool_push()
}
fn ucd_pop(api UCDApi, pool u64) {
 if api.native { unsafe { UCDDrop(C.dlsym(voidptr(api.objc), c'objc_autoreleasePoolPop'))(pool) }; return }
 objc_pool_pop(pool)
}
fn ucd_keep(api UCDApi, object u64) u64 {
 if api.native { return unsafe { UCDKeep(C.dlsym(voidptr(api.core), c'CFRetain'))(object) } }
 return objc_retain(object)
}
fn ucd_drop(api UCDApi, object u64) {
 if api.native { unsafe { UCDDrop(C.dlsym(voidptr(api.core), c'CFRelease'))(object) }; return }
 objc_release(object)
}
fn ucd_text(api UCDApi, object u64, expected string) {
 assert object != 0
 if !api.native { assert string_text(object) == expected && cf_type_id(object) == cf_string_id(); return }
 mut bytes := [128]u8{}
 assert unsafe { UCDBytes(C.dlsym(voidptr(api.core), c'CFStringGetCString'))(object, &char(&bytes[0]), 128, 0x08000100) }
 assert bytes[expected.len] == 0 && C.memcmp(unsafe { &bytes[0] }, expected.str, usize(expected.len)) == 0
}
fn ucd_reader(api UCDApi, offset int) u64 {
 mut cell := u64(0)
 for turn in 0 .. 64 {
  for step in 0 .. 4 {
   index := (offset + step + turn) % 4
   got := ucd_cell(api, index % 2 == 0, index / 2 == 0)
   assert got != 0 && got % 8 == 0
   if cell == 0 { cell = got } else { assert got == cell }
   value := read64(got); assert value != got
   ucd_text(api, value, 'NSURLCreationDateKey')
   assert ucd_keep(api, value) == value; ucd_drop(api, value)
  }
 }
 return cell
}
fn ucd_shared(api UCDApi) u64 {
 mut workers := []thread u64{}
 for offset in 0 .. 8 { workers << spawn ucd_reader(api, offset) }
 mut cell := u64(0)
 for i, worker in workers { got := worker.wait(); if i == 0 { cell = got } else { assert cell == got } }
 unsafe { workers.free() }
 value := read64(cell)
 if !api.native {
  assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 && ios_runtime.framework_objects.len == 0
  assert cell == ios_runtime.url_resource_keys_arena && value == cell + 32
  assert read64(value) == ios_runtime.names['NSString'] && read64(value + 8) == 0x7c8 && read64(value + 24) == 20
  assert read64(value + 16) == cell + 64 && unsafe { *(&u8(cell + 84)) } == 0 && value in ios_runtime.constants
  assert '_NSURLCreationDateKey' !in ios_runtime.framework_data && '_kCFURLCreationDateKey' !in ios_runtime.framework_data
 }
 pool := ucd_pool(api)
 objects := [value]!
 array := ucd_msg(api, ucd_class(api, c'NSArray'), c'arrayWithObjects:count:', u64(unsafe { &objects[0] }), 1, 0)
 assert ucd_msg(api, array, c'count', 0, 0, 0) == 1 && ucd_msg(api, array, c'objectAtIndex:', 0, 0, 0) == value
 assert ucd_keep(api, array) == array
 assert ucd_msg(api, ucd_keep(api, value), c'autorelease', 0, 0, 0) == value
 copy := ucd_msg(api, value, c'copy', 0, 0, 0); assert copy == value; ucd_drop(api, copy)
 equal := ucd_msg(api, ucd_class(api, c'NSString'), c'stringWithUTF8String:', u64(c'NSURLCreationDateKey'), 0, 0)
 assert ucd_msg(api, value, c'length', 0, 0, 0) == 20
 assert ucd_msg(api, value, c'isEqualToString:', equal, 0, 0) == 1
 if api.native { assert unsafe { UCDKeep(C.dlsym(voidptr(api.core), c'CFHash'))(value) } == unsafe { UCDKeep(C.dlsym(voidptr(api.core), c'CFHash'))(equal) } } else { assert cf_hash(value) == cf_hash(equal) }
 keys := [value]!; values := [equal]!
 dictionary := ucd_msg(api, ucd_class(api, c'NSDictionary'), c'dictionaryWithObjects:forKeys:count:', u64(unsafe { &values[0] }), u64(unsafe { &keys[0] }), 1)
 assert ucd_msg(api, dictionary, c'objectForKey:', equal, 0, 0) == equal
 ucd_pop(api, pool); ucd_text(api, read64(cell), 'NSURLCreationDateKey')
 assert ucd_msg(api, array, c'objectAtIndex:', 0, 0, 0) == value; ucd_drop(api, array)
 if !api.native { assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 }
 return cell
}

__global ucd_teardown_calls = 0
fn ucd_teardown(object u64, selector &char) {
 assert ios_runtime.swift_concurrency_retired
 cell := ucd_cell(UCDApi{}, true, false)
 assert cell == ucd_cell(UCDApi{}, false, true)
 ucd_text(UCDApi{}, read64(cell), 'NSURLCreationDateKey')
 assert read64(cell) in ios_runtime.constants
 ucd_teardown_calls++
}
fn test_ns_url_creation_date() {
 $if macos {
  api := UCDApi{true, u64(C.dlopen(c'/System/Library/Frameworks/Foundation.framework/Foundation', 2)), u64(C.dlopen(c'/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation', 2)), u64(C.dlopen(c'/usr/lib/libobjc.A.dylib', 2))}
  assert api.foundation != 0 && api.core != 0 && api.objc != 0
  ucd_shared(api)
  for handle in [api.objc, api.core, api.foundation]! { assert C.dlclose(unsafe { voidptr(handle) }) == 0 }
  println('NATIVE-NS-URL-CREATION-DATE: identical NS/CF resource-key cells and exact NSString value, eight mixed-alias readers, immutable copying/hash/dictionary behavior and retained key-array lifetime')
 }
 if _ := ns_url_resource_key_symbol('_NSURLCreationDateKey') { assert false }
 for _ in 0 .. 2 {
  objc_start(); assert ios_runtime.url_resource_keys_arena == 0
  ns_url_resource_keys_stop(); assert ios_runtime.url_resource_keys_arena == 0
  ios_runtime.swift_concurrency_retired = true
  if _ := ns_url_resource_key_symbol('_NSURLCreationDateKey') { assert false }
  ios_runtime.swift_concurrency_retired = false
  cell := ucd_shared(UCDApi{}); value := read64(cell)
  assert ios_runtime.foundation_keys_arena == 0
  for symbol in ['_NSURLCreationDateKey','_kCFURLCreationDateKey']! { for library in ['/System/Library/Frameworks/UIKit.framework/UIKit', '/usr/lib/libSystem.B.dylib']! { if _ := runtime_symbol(library, symbol) { assert false } } }
  for name in ['_NSURLCreationDate','_kCFURLCreationDate','_NSURLCreationDateKeyExtra']! { if _ := ns_url_resource_key_symbol(name) { assert false } }
  probe := objc_allocate_class(ios_runtime.names['NSObject'], c'VinixURLCreationDateTeardownProbe', 0); assert probe != 0
  assert objc_add_method(probe, u64(c'dealloc'), u64(unsafe { voidptr(ucd_teardown) }), c'v16@0:8')
  objc_register_class(probe); objc_autorelease(objc_new(probe))
  ios_runtime.swift_concurrency_retired = true; assert ucd_cell(UCDApi{}, false, true) == cell
  before := ucd_teardown_calls; objc_stop()
  assert ucd_teardown_calls == before + 1 && ios_runtime.url_resource_keys_arena == 0 && ios_runtime.live == 0 && ios_runtime.objects.len == 0 && value !in ios_runtime.constants
  if _ := ns_url_resource_key_symbol('_NSURLCreationDateKey') { assert false }
 }
 println('IOS-NS-URL-CREATION-DATE: shared sealed NS/CF resource-key cell with exact CFString, eight mixed-alias cold publishers, immutable string/hash/dictionary behavior, retained one-key NSArray across pool drain, isolated Foundation storage, retirement guards, callback access and two drained/unmapped lifetimes')
}

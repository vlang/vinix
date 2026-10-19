// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.dlclose(voidptr) i32

type UFSName = fn (&char) u64
type UFSMessage = fn (u64, u64, u64, u64, u64) u64
type UFSKeep = fn (u64) u64
type UFSDrop = fn (u64)
type UFSPool = fn () u64
type UFSBytes = fn (u64, &char, i64, u32) bool
struct UFSApi { native bool foundation u64 core u64 objc u64 }

fn ufs_cell(api UFSApi, key int, core bool, cf bool) u64 {
 name := if key == 0 { if cf { '_kCFURLCreationDateKey' } else { '_NSURLCreationDateKey' } } else { if cf { '_kCFURLFileSizeKey' } else { '_NSURLFileSizeKey' } }
 if api.native { return u64(C.dlsym(unsafe { voidptr(if core { api.core } else { api.foundation }) }, unsafe { &char(name.str + 1) })) }
 library := if core { '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation' } else { '/System/Library/Frameworks/Foundation.framework/Foundation' }
 return runtime_symbol(library, name) or { panic(err) }
}
fn ufs_msg(api UFSApi, object u64, name &char, a u64, b u64, c u64) u64 {
 if api.native {
  selector := unsafe { UFSName(C.dlsym(voidptr(api.objc), c'sel_registerName'))(name) }
  return unsafe { UFSMessage(C.dlsym(voidptr(api.objc), c'objc_msgSend'))(object, selector, a, b, c) }
 }
 return unsafe { UFSMessage(voidptr(C.ios_objc_builtin))(object, u64(name), a, b, c) }
}
fn ufs_class(api UFSApi, name &char) u64 {
 if api.native { return unsafe { UFSName(C.dlsym(voidptr(api.objc), c'objc_getClass'))(name) } }
 return ios_runtime.names[ctext(u64(name))]
}
fn ufs_pool(api UFSApi) u64 {
 if api.native { return unsafe { UFSPool(C.dlsym(voidptr(api.objc), c'objc_autoreleasePoolPush'))() } }
 return objc_pool_push()
}
fn ufs_pop(api UFSApi, pool u64) {
 if api.native { unsafe { UFSDrop(C.dlsym(voidptr(api.objc), c'objc_autoreleasePoolPop'))(pool) }; return }
 objc_pool_pop(pool)
}
fn ufs_keep(api UFSApi, object u64) u64 {
 if api.native { return unsafe { UFSKeep(C.dlsym(voidptr(api.core), c'CFRetain'))(object) } }
 return objc_retain(object)
}
fn ufs_drop(api UFSApi, object u64) {
 if api.native { unsafe { UFSDrop(C.dlsym(voidptr(api.core), c'CFRelease'))(object) }; return }
 objc_release(object)
}
fn ufs_text(api UFSApi, object u64, expected string) {
 assert object != 0
 if !api.native { assert string_text(object) == expected && cf_type_id(object) == cf_string_id(); return }
 mut bytes := [128]u8{}
 assert unsafe { UFSBytes(C.dlsym(voidptr(api.core), c'CFStringGetCString'))(object, &char(&bytes[0]), 128, 0x08000100) }
 assert bytes[expected.len] == 0 && C.memcmp(unsafe { &bytes[0] }, expected.str, usize(expected.len)) == 0
}

fn ufs_reader(api UFSApi, offset int) u64 {
 mut cells := [2]u64{}
 for turn in 0 .. 64 {
  for step in 0 .. 8 {
   index := (offset + step + turn) % 8
   key := index / 4
   got := ufs_cell(api, key, index % 2 == 0, (index / 2) % 2 == 0)
   assert got != 0 && got % 8 == 0
   if cells[key] == 0 { cells[key] = got } else { assert got == cells[key] }
   value := read64(got); assert value != got
   ufs_text(api, value, if key == 0 { 'NSURLCreationDateKey' } else { 'NSURLFileSizeKey' })
   assert ufs_keep(api, value) == value; ufs_drop(api, value)
  }
 }
 assert cells[0] != cells[1] && read64(cells[0]) != read64(cells[1])
 return cells[1]
}
fn ufs_shared(api UFSApi) u64 {
 mut workers := []thread u64{}
 for offset in 0 .. 8 { workers << spawn ufs_reader(api, offset) }
 mut cell := u64(0)
 for i, worker in workers { got := worker.wait(); if i == 0 { cell = got } else { assert cell == got } }
 unsafe { workers.free() }
 creation := ufs_cell(api, 0, false, false)
 cells := [creation, cell]!
 objects := [read64(creation), read64(cell)]!
 texts := ['NSURLCreationDateKey', 'NSURLFileSizeKey']!
 if !api.native {
  assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 && ios_runtime.framework_objects.len == 0
  assert creation == ios_runtime.url_resource_keys_arena && cell == creation + 8
  records := [u64(32), 128]!; bytes := [u64(64), 160]!
  for i in 0 .. 2 {
   value := objects[i]
   assert value == creation + records[i]
   assert read64(value) == ios_runtime.names['NSString'] && read64(value + 8) == 0x7c8 && read64(value + 24) == u64(texts[i].len)
   assert read64(value + 16) == creation + bytes[i] && unsafe { *(&u8(creation + bytes[i] + u64(texts[i].len))) } == 0 && value in ios_runtime.constants
  }
  for symbol in ['_NSURLCreationDateKey','_kCFURLCreationDateKey','_NSURLFileSizeKey','_kCFURLFileSizeKey']! { assert symbol !in ios_runtime.framework_data }
 }
 pool := ufs_pool(api)
 array := ufs_msg(api, ufs_class(api, c'NSArray'), c'arrayWithObjects:count:', u64(unsafe { &objects[0] }), 2, 0)
 assert ufs_msg(api, array, c'count', 0, 0, 0) == 2
 assert ufs_keep(api, array) == array
 mut equal := [2]u64{}
 for i in 0 .. 2 {
  value := objects[i]
  assert ufs_msg(api, array, c'objectAtIndex:', u64(i), 0, 0) == value
  assert ufs_msg(api, ufs_keep(api, value), c'autorelease', 0, 0, 0) == value
  copy := ufs_msg(api, value, c'copy', 0, 0, 0); assert copy == value; ufs_drop(api, copy)
  equal[i] = ufs_msg(api, ufs_class(api, c'NSString'), c'stringWithUTF8String:', u64(texts[i].str), 0, 0)
  assert ufs_msg(api, value, c'length', 0, 0, 0) == u64(texts[i].len)
  assert ufs_msg(api, value, c'isEqualToString:', equal[i], 0, 0) == 1
  if api.native { assert unsafe { UFSKeep(C.dlsym(voidptr(api.core), c'CFHash'))(value) } == unsafe { UFSKeep(C.dlsym(voidptr(api.core), c'CFHash'))(equal[i]) } } else { assert cf_hash(value) == cf_hash(equal[i]) }
 }
 dictionary := ufs_msg(api, ufs_class(api, c'NSDictionary'), c'dictionaryWithObjects:forKeys:count:', u64(unsafe { &equal[0] }), u64(unsafe { &objects[0] }), 2)
 for i in 0 .. 2 { assert ufs_msg(api, dictionary, c'objectForKey:', equal[i], 0, 0) == equal[i] }
 ufs_pop(api, pool)
 for i in 0 .. 2 {
  ufs_text(api, read64(cells[i]), texts[i])
  assert ufs_msg(api, array, c'objectAtIndex:', u64(i), 0, 0) == objects[i]
 }
 ufs_drop(api, array)
 if !api.native { assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 }
 return cell
}
__global ufs_teardown_calls = 0
fn ufs_teardown(object u64, selector &char) {
 assert ios_runtime.swift_concurrency_retired
 for i in 0 .. 2 {
  cell := ufs_cell(UFSApi{}, i, true, false)
  assert cell == ufs_cell(UFSApi{}, i, false, true)
  ufs_text(UFSApi{}, read64(cell), if i == 0 { 'NSURLCreationDateKey' } else { 'NSURLFileSizeKey' })
  assert read64(cell) in ios_runtime.constants
 }
 ufs_teardown_calls++
}
fn test_ns_url_file_size() {
 $if macos {
  api := UFSApi{true, u64(C.dlopen(c'/System/Library/Frameworks/Foundation.framework/Foundation', 2)), u64(C.dlopen(c'/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation', 2)), u64(C.dlopen(c'/usr/lib/libobjc.A.dylib', 2))}
  assert api.foundation != 0 && api.core != 0 && api.objc != 0
  ufs_shared(api)
  for handle in [api.objc, api.core, api.foundation]! { assert C.dlclose(unsafe { voidptr(handle) }) == 0 }
  println('NATIVE-NS-URL-FILE-SIZE: distinct size/creation keys with shared NS/CF alias cells, exact NSString values, eight mixed-key readers, immutable copying/hash/dictionary behavior and retained key-array lifetime')
 }
 for symbol in ['_NSURLFileSizeKey','_kCFURLFileSizeKey']! { if _ := ns_url_resource_key_symbol(symbol) { assert false } }
 for _ in 0 .. 2 {
  objc_start(); assert ios_runtime.url_resource_keys_arena == 0
  ns_url_resource_keys_stop(); assert ios_runtime.url_resource_keys_arena == 0
  ios_runtime.swift_concurrency_retired = true
  for symbol in ['_NSURLCreationDateKey','_kCFURLCreationDateKey','_NSURLFileSizeKey','_kCFURLFileSizeKey']! { if _ := ns_url_resource_key_symbol(symbol) { assert false } }
  ios_runtime.swift_concurrency_retired = false
  cell := ufs_shared(UFSApi{}); size := read64(cell); creation := read64(cell - 8)
  assert ios_runtime.foundation_keys_arena == 0
  for symbol in ['_NSURLFileSizeKey','_kCFURLFileSizeKey']! { for library in ['/System/Library/Frameworks/UIKit.framework/UIKit', '/usr/lib/libSystem.B.dylib']! { if _ := runtime_symbol(library, symbol) { assert false } } }
  for name in ['_NSURLFileSize','_kCFURLFileSize','_NSURLFileSizeKeyExtra','_kCFURLFileSizeKeyExtra']! { if _ := ns_url_resource_key_symbol(name) { assert false } }
  probe := objc_allocate_class(ios_runtime.names['NSObject'], c'VinixURLFileSizeTeardownProbe', 0); assert probe != 0
  assert objc_add_method(probe, u64(c'dealloc'), u64(unsafe { voidptr(ufs_teardown) }), c'v16@0:8')
  objc_register_class(probe); objc_autorelease(objc_new(probe))
  ios_runtime.swift_concurrency_retired = true
  assert ufs_cell(UFSApi{}, 1, false, true) == cell && ufs_cell(UFSApi{}, 0, true, false) == cell - 8
  before := ufs_teardown_calls; objc_stop()
  assert ufs_teardown_calls == before + 1 && ios_runtime.url_resource_keys_arena == 0 && ios_runtime.live == 0 && ios_runtime.objects.len == 0 && size !in ios_runtime.constants && creation !in ios_runtime.constants
  for symbol in ['_NSURLCreationDateKey','_kCFURLCreationDateKey','_NSURLFileSizeKey','_kCFURLFileSizeKey']! { if _ := ns_url_resource_key_symbol(symbol) { assert false } }
 }
 println('IOS-NS-URL-FILE-SIZE: two distinct sealed resource-key cells with exact CFStrings, eight mixed-key cold publishers, preserved creation-date layout, immutable string/hash/dictionary behavior, retained two-key NSArray across pool drain, isolated Foundation storage, retirement guards, callback access and two drained/unmapped lifetimes')
}

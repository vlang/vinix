// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.dlclose(voidptr) i32

type URFName = fn (&char) u64
type URFMessage = fn (u64, u64, u64, u64, u64) u64
type URFKeep = fn (u64) u64
type URFDrop = fn (u64)
type URFPool = fn () u64
type URFBytes = fn (u64, &char, i64, u32) bool
struct URFApi { native bool foundation u64 core u64 objc u64 }

fn urf_cell(api URFApi, key int, core bool, cf bool) u64 {
 names := if cf { ['_kCFURLCreationDateKey','_kCFURLFileSizeKey','_kCFURLIsExcludedFromBackupKey','_kCFURLIsRegularFileKey']! } else { ['_NSURLCreationDateKey','_NSURLFileSizeKey','_NSURLIsExcludedFromBackupKey','_NSURLIsRegularFileKey']! }
 name := names[key]
 if api.native { return u64(C.dlsym(unsafe { voidptr(if core { api.core } else { api.foundation }) }, unsafe { &char(name.str + 1) })) }
 library := if core { '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation' } else { '/System/Library/Frameworks/Foundation.framework/Foundation' }
 return runtime_symbol(library, name) or { panic(err) }
}
fn urf_msg(api URFApi, object u64, name &char, a u64, b u64, c u64) u64 {
 if api.native {
  selector := unsafe { URFName(C.dlsym(voidptr(api.objc), c'sel_registerName'))(name) }
  return unsafe { URFMessage(C.dlsym(voidptr(api.objc), c'objc_msgSend'))(object, selector, a, b, c) }
 }
 return unsafe { URFMessage(voidptr(C.ios_objc_builtin))(object, u64(name), a, b, c) }
}
fn urf_class(api URFApi, name &char) u64 {
 if api.native { return unsafe { URFName(C.dlsym(voidptr(api.objc), c'objc_getClass'))(name) } }
 return ios_runtime.names[ctext(u64(name))]
}
fn urf_pool(api URFApi) u64 {
 if api.native { return unsafe { URFPool(C.dlsym(voidptr(api.objc), c'objc_autoreleasePoolPush'))() } }
 return objc_pool_push()
}
fn urf_pop(api URFApi, pool u64) {
 if api.native { unsafe { URFDrop(C.dlsym(voidptr(api.objc), c'objc_autoreleasePoolPop'))(pool) }; return }
 objc_pool_pop(pool)
}
fn urf_keep(api URFApi, object u64) u64 {
 if api.native { return unsafe { URFKeep(C.dlsym(voidptr(api.core), c'CFRetain'))(object) } }
 return objc_retain(object)
}
fn urf_drop(api URFApi, object u64) {
 if api.native { unsafe { URFDrop(C.dlsym(voidptr(api.core), c'CFRelease'))(object) }; return }
 objc_release(object)
}
fn urf_text(api URFApi, object u64, expected string) {
 assert object != 0
 if !api.native { assert string_text(object) == expected && cf_type_id(object) == cf_string_id(); return }
 mut bytes := [128]u8{}
 assert unsafe { URFBytes(C.dlsym(voidptr(api.core), c'CFStringGetCString'))(object, &char(&bytes[0]), 128, 0x08000100) }
 assert bytes[expected.len] == 0 && C.memcmp(unsafe { &bytes[0] }, expected.str, usize(expected.len)) == 0
}

fn urf_expected(key int) string {
 texts := ['NSURLCreationDateKey','NSURLFileSizeKey','NSURLIsExcludedFromBackupKey', 'NSURLIsRegularFileKey']!
 return texts[key]
}
fn urf_reader(api URFApi, offset int) u64 {
 mut cells := [4]u64{}
 for turn in 0 .. 64 {
  for step in 0 .. 16 {
   index := (offset + step + turn) % 16
   key := index / 4
   got := urf_cell(api, key, index % 2 == 0, (index / 2) % 2 == 0)
   assert got != 0 && got % 8 == 0
   if cells[key] == 0 { cells[key] = got } else { assert got == cells[key] }
   value := read64(got); assert value != got
   urf_text(api, value, urf_expected(key))
   assert urf_keep(api, value) == value; urf_drop(api, value)
  }
 }
 for i in 0 .. 4 { for j in 0 .. i { assert cells[i] != cells[j] && read64(cells[i]) != read64(cells[j]) } }
 return cells[3]
}
fn urf_shared(api URFApi) u64 {
 mut workers := []thread u64{}
 for offset in 0 .. 8 { workers << spawn urf_reader(api, (offset * 5 + 12) % 16) }
 mut cell := u64(0)
 for i, worker in workers { got := worker.wait(); if i == 0 { cell = got } else { assert cell == got } }
 unsafe { workers.free() }
 creation := urf_cell(api, 0, false, false)
 cells := [creation, urf_cell(api, 1, false, false), urf_cell(api, 2, false, false), cell]!
 objects := [read64(cells[0]), read64(cells[1]), read64(cells[2]), read64(cells[3])]!
 texts := ['NSURLCreationDateKey', 'NSURLFileSizeKey', 'NSURLIsExcludedFromBackupKey', 'NSURLIsRegularFileKey']!
 if !api.native {
  assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 && ios_runtime.framework_objects.len == 0
  assert creation == ios_runtime.url_resource_keys_arena && cell == creation + 24
  records := [u64(32), 128, 192, 256]!; bytes := [u64(64), 160, 224, 288]!
  for i in 0 .. 4 {
   value := objects[i]
   assert value == creation + records[i]
   assert read64(value) == ios_runtime.names['NSString'] && read64(value + 8) == 0x7c8 && read64(value + 24) == u64(texts[i].len)
   assert read64(value + 16) == creation + bytes[i] && unsafe { *(&u8(creation + bytes[i] + u64(texts[i].len))) } == 0 && value in ios_runtime.constants
  }
  for symbol in ['_NSURLCreationDateKey','_kCFURLCreationDateKey','_NSURLFileSizeKey','_kCFURLFileSizeKey','_NSURLIsExcludedFromBackupKey','_kCFURLIsExcludedFromBackupKey','_NSURLIsRegularFileKey','_kCFURLIsRegularFileKey']! { assert symbol !in ios_runtime.framework_data }
 }
 pool := urf_pool(api)
 array := urf_msg(api, urf_class(api, c'NSArray'), c'arrayWithObjects:count:', u64(unsafe { &objects[0] }), 4, 0)
 assert urf_msg(api, array, c'count', 0, 0, 0) == 4
 assert urf_keep(api, array) == array
 mut equal := [4]u64{}
 for i in 0 .. 4 {
  value := objects[i]
  assert urf_msg(api, array, c'objectAtIndex:', u64(i), 0, 0) == value
  assert urf_msg(api, urf_keep(api, value), c'autorelease', 0, 0, 0) == value
  copy := urf_msg(api, value, c'copy', 0, 0, 0); assert copy == value; urf_drop(api, copy)
  equal[i] = urf_msg(api, urf_class(api, c'NSString'), c'stringWithUTF8String:', u64(texts[i].str), 0, 0)
  assert urf_msg(api, value, c'length', 0, 0, 0) == u64(texts[i].len)
  assert urf_msg(api, value, c'isEqualToString:', equal[i], 0, 0) == 1
  if api.native { assert unsafe { URFKeep(C.dlsym(voidptr(api.core), c'CFHash'))(value) } == unsafe { URFKeep(C.dlsym(voidptr(api.core), c'CFHash'))(equal[i]) } } else { assert cf_hash(value) == cf_hash(equal[i]) }
 }
 dictionary := urf_msg(api, urf_class(api, c'NSDictionary'), c'dictionaryWithObjects:forKeys:count:', u64(unsafe { &equal[0] }), u64(unsafe { &objects[0] }), 4)
 for i in 0 .. 4 { assert urf_msg(api, dictionary, c'objectForKey:', equal[i], 0, 0) == equal[i] }


 query_keys := [objects[3], objects[1]]!
 query_array := urf_msg(api, urf_class(api, c'NSArray'), c'arrayWithObjects:count:', u64(unsafe { &query_keys[0] }), 2, 0)
 assert urf_msg(api, query_array, c'count', 0, 0, 0) == 2
 for i in 0 .. 2 { assert urf_msg(api, query_array, c'objectAtIndex:', u64(i), 0, 0) == query_keys[i] }
 assert urf_keep(api, query_array) == query_array
 flag := urf_msg(api, urf_class(api, c'NSNumber'), c'numberWithInteger:', 1, 0, 0)
 size := urf_msg(api, urf_class(api, c'NSNumber'), c'numberWithInteger:', 37, 0, 0)
 values := [flag, size]!
 query_dictionary := urf_msg(api, urf_class(api, c'NSDictionary'), c'dictionaryWithObjects:forKeys:count:', u64(unsafe { &values[0] }), u64(unsafe { &query_keys[0] }), 2)
 found := urf_msg(api, query_dictionary, c'objectForKey:', equal[3], 0, 0)
 found_size := urf_msg(api, query_dictionary, c'objectForKey:', equal[1], 0, 0)
 assert found == flag && urf_msg(api, found, c'boolValue', 0, 0, 0) == 1
 assert found_size == size && urf_msg(api, found_size, c'integerValue', 0, 0, 0) == 37
 assert urf_keep(api, query_dictionary) == query_dictionary
 urf_pop(api, pool)
 for i in 0 .. 4 {
  urf_text(api, read64(cells[i]), texts[i])
  assert urf_msg(api, array, c'objectAtIndex:', u64(i), 0, 0) == objects[i]
 }


 for i in 0 .. 2 { assert urf_msg(api, query_array, c'objectAtIndex:', u64(i), 0, 0) == query_keys[i] }
 found_after := urf_msg(api, query_dictionary, c'objectForKey:', objects[3], 0, 0)
 size_after := urf_msg(api, query_dictionary, c'objectForKey:', objects[1], 0, 0)
 assert found_after == flag && urf_msg(api, found_after, c'boolValue', 0, 0, 0) == 1
 assert size_after == size && urf_msg(api, size_after, c'integerValue', 0, 0, 0) == 37
 urf_drop(api, query_dictionary); urf_drop(api, query_array)
 urf_drop(api, array)
 if !api.native { assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 }
 return cell
}
__global urf_teardown_calls = 0
fn urf_teardown(object u64, selector &char) {
 assert ios_runtime.swift_concurrency_retired
 for i in 0 .. 4 {
  cell := urf_cell(URFApi{}, i, true, false)
  assert cell == urf_cell(URFApi{}, i, false, true)
  urf_text(URFApi{}, read64(cell), urf_expected(i))
  assert read64(cell) in ios_runtime.constants
 }
 urf_teardown_calls++
}
fn test_ns_url_regular_file() {
 $if macos {
  api := URFApi{true, u64(C.dlopen(c'/System/Library/Frameworks/Foundation.framework/Foundation', 2)), u64(C.dlopen(c'/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation', 2)), u64(C.dlopen(c'/usr/lib/libobjc.A.dylib', 2))}
  assert api.foundation != 0 && api.core != 0 && api.objc != 0
  urf_shared(api)
  for handle in [api.objc, api.core, api.foundation]! { assert C.dlclose(unsafe { voidptr(handle) }) == 0 }
  println('NATIVE-NS-URL-REGULAR-FILE: distinct regular/backup/size/creation keys with shared NS/CF alias cells, exact NSString values, eight mixed-key readers, immutable copying/hash/dictionary behavior and retained key-array lifetime')
 }
 for symbol in ['_NSURLIsRegularFileKey','_kCFURLIsRegularFileKey']! { if _ := ns_url_resource_key_symbol(symbol) { assert false } }
 for _ in 0 .. 2 {
  objc_start(); assert ios_runtime.url_resource_keys_arena == 0
  ns_url_resource_keys_stop(); assert ios_runtime.url_resource_keys_arena == 0
  ios_runtime.swift_concurrency_retired = true
  for symbol in ['_NSURLCreationDateKey','_kCFURLCreationDateKey','_NSURLFileSizeKey','_kCFURLFileSizeKey','_NSURLIsExcludedFromBackupKey','_kCFURLIsExcludedFromBackupKey','_NSURLIsRegularFileKey','_kCFURLIsRegularFileKey']! { if _ := ns_url_resource_key_symbol(symbol) { assert false } }
  ios_runtime.swift_concurrency_retired = false
  cell := urf_shared(URFApi{}); regular := read64(cell); backup := read64(cell - 8); size := read64(cell - 16); creation := read64(cell - 24)
  assert ios_runtime.foundation_keys_arena == 0
  for symbol in ['_NSURLIsRegularFileKey','_kCFURLIsRegularFileKey']! { for library in ['/System/Library/Frameworks/UIKit.framework/UIKit', '/usr/lib/libSystem.B.dylib']! { if _ := runtime_symbol(library, symbol) { assert false } } }
  for name in ['_NSURLIsRegularFile','_kCFURLIsRegularFile','_NSURLIsRegularFileKeyExtra','_kCFURLIsRegularFileKeyExtra']! { if _ := ns_url_resource_key_symbol(name) { assert false } }
  probe := objc_allocate_class(ios_runtime.names['NSObject'], c'VinixURLRegularFileTeardownProbe', 0); assert probe != 0
  assert objc_add_method(probe, u64(c'dealloc'), u64(unsafe { voidptr(urf_teardown) }), c'v16@0:8')
  objc_register_class(probe); objc_autorelease(objc_new(probe))
  ios_runtime.swift_concurrency_retired = true
  assert urf_cell(URFApi{}, 3, false, true) == cell && urf_cell(URFApi{}, 2, true, false) == cell - 8 && urf_cell(URFApi{}, 1, false, true) == cell - 16 && urf_cell(URFApi{}, 0, true, false) == cell - 24
  before := urf_teardown_calls; objc_stop()
  assert urf_teardown_calls == before + 1 && ios_runtime.url_resource_keys_arena == 0 && ios_runtime.live == 0 && ios_runtime.objects.len == 0 && regular !in ios_runtime.constants && backup !in ios_runtime.constants && size !in ios_runtime.constants && creation !in ios_runtime.constants
  for symbol in ['_NSURLCreationDateKey','_kCFURLCreationDateKey','_NSURLFileSizeKey','_kCFURLFileSizeKey','_NSURLIsExcludedFromBackupKey','_kCFURLIsExcludedFromBackupKey','_NSURLIsRegularFileKey','_kCFURLIsRegularFileKey']! { if _ := ns_url_resource_key_symbol(symbol) { assert false } }
 }
 println('IOS-NS-URL-REGULAR-FILE: four distinct sealed resource-key cells with exact CFStrings, eight mixed-key cold publishers, preserved creation-date/file-size/backup layouts, immutable string/hash/dictionary behavior, retained four-key and regular-file/file-size NSArrays plus NSNumber dictionary across pool drain, isolated Foundation storage, retirement guards, callback access and two drained/unmapped lifetimes')
}

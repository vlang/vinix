// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.dlclose(voidptr) i32

type UBEName = fn (&char) u64
type UBEMessage = fn (u64, u64, u64, u64, u64) u64
type UBEKeep = fn (u64) u64
type UBEDrop = fn (u64)
type UBEPool = fn () u64
type UBEBytes = fn (u64, &char, i64, u32) bool
struct UBEApi { native bool foundation u64 core u64 objc u64 }

fn ube_cell(api UBEApi, key int, core bool, cf bool) u64 {
 names := if cf { ['_kCFURLCreationDateKey','_kCFURLFileSizeKey','_kCFURLIsExcludedFromBackupKey']! } else { ['_NSURLCreationDateKey','_NSURLFileSizeKey','_NSURLIsExcludedFromBackupKey']! }
 name := names[key]
 if api.native { return u64(C.dlsym(unsafe { voidptr(if core { api.core } else { api.foundation }) }, unsafe { &char(name.str + 1) })) }
 library := if core { '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation' } else { '/System/Library/Frameworks/Foundation.framework/Foundation' }
 return runtime_symbol(library, name) or { panic(err) }
}
fn ube_msg(api UBEApi, object u64, name &char, a u64, b u64, c u64) u64 {
 if api.native {
  selector := unsafe { UBEName(C.dlsym(voidptr(api.objc), c'sel_registerName'))(name) }
  return unsafe { UBEMessage(C.dlsym(voidptr(api.objc), c'objc_msgSend'))(object, selector, a, b, c) }
 }
 return unsafe { UBEMessage(voidptr(C.ios_objc_builtin))(object, u64(name), a, b, c) }
}
fn ube_class(api UBEApi, name &char) u64 {
 if api.native { return unsafe { UBEName(C.dlsym(voidptr(api.objc), c'objc_getClass'))(name) } }
 return ios_runtime.names[ctext(u64(name))]
}
fn ube_pool(api UBEApi) u64 {
 if api.native { return unsafe { UBEPool(C.dlsym(voidptr(api.objc), c'objc_autoreleasePoolPush'))() } }
 return objc_pool_push()
}
fn ube_pop(api UBEApi, pool u64) {
 if api.native { unsafe { UBEDrop(C.dlsym(voidptr(api.objc), c'objc_autoreleasePoolPop'))(pool) }; return }
 objc_pool_pop(pool)
}
fn ube_keep(api UBEApi, object u64) u64 {
 if api.native { return unsafe { UBEKeep(C.dlsym(voidptr(api.core), c'CFRetain'))(object) } }
 return objc_retain(object)
}
fn ube_drop(api UBEApi, object u64) {
 if api.native { unsafe { UBEDrop(C.dlsym(voidptr(api.core), c'CFRelease'))(object) }; return }
 objc_release(object)
}
fn ube_text(api UBEApi, object u64, expected string) {
 assert object != 0
 if !api.native { assert string_text(object) == expected && cf_type_id(object) == cf_string_id(); return }
 mut bytes := [128]u8{}
 assert unsafe { UBEBytes(C.dlsym(voidptr(api.core), c'CFStringGetCString'))(object, &char(&bytes[0]), 128, 0x08000100) }
 assert bytes[expected.len] == 0 && C.memcmp(unsafe { &bytes[0] }, expected.str, usize(expected.len)) == 0
}

fn ube_expected(key int) string {
 texts := ['NSURLCreationDateKey','NSURLFileSizeKey','NSURLIsExcludedFromBackupKey']!
 return texts[key]
}
fn ube_reader(api UBEApi, offset int) u64 {
 mut cells := [3]u64{}
 for turn in 0 .. 64 {
  for step in 0 .. 12 {
   index := (offset + step + turn) % 12
   key := index / 4
   got := ube_cell(api, key, index % 2 == 0, (index / 2) % 2 == 0)
   assert got != 0 && got % 8 == 0
   if cells[key] == 0 { cells[key] = got } else { assert got == cells[key] }
   value := read64(got); assert value != got
   ube_text(api, value, ube_expected(key))
   assert ube_keep(api, value) == value; ube_drop(api, value)
  }
 }
 for i in 0 .. 3 { for j in 0 .. i { assert cells[i] != cells[j] && read64(cells[i]) != read64(cells[j]) } }
 return cells[2]
}
fn ube_shared(api UBEApi) u64 {
 mut workers := []thread u64{}
 for offset in 0 .. 8 { workers << spawn ube_reader(api, offset) }
 mut cell := u64(0)
 for i, worker in workers { got := worker.wait(); if i == 0 { cell = got } else { assert cell == got } }
 unsafe { workers.free() }
 creation := ube_cell(api, 0, false, false)
 cells := [creation, ube_cell(api, 1, false, false), cell]!
 objects := [read64(cells[0]), read64(cells[1]), read64(cells[2])]!
 texts := ['NSURLCreationDateKey', 'NSURLFileSizeKey', 'NSURLIsExcludedFromBackupKey']!
 if !api.native {
  assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 && ios_runtime.framework_objects.len == 0
  assert creation == ios_runtime.url_resource_keys_arena && cell == creation + 16
  records := [u64(32), 128, 192]!; bytes := [u64(64), 160, 224]!
  for i in 0 .. 3 {
   value := objects[i]
   assert value == creation + records[i]
   assert read64(value) == ios_runtime.names['NSString'] && read64(value + 8) == 0x7c8 && read64(value + 24) == u64(texts[i].len)
   assert read64(value + 16) == creation + bytes[i] && unsafe { *(&u8(creation + bytes[i] + u64(texts[i].len))) } == 0 && value in ios_runtime.constants
  }
  for symbol in ['_NSURLCreationDateKey','_kCFURLCreationDateKey','_NSURLFileSizeKey','_kCFURLFileSizeKey','_NSURLIsExcludedFromBackupKey','_kCFURLIsExcludedFromBackupKey']! { assert symbol !in ios_runtime.framework_data }
 }
 pool := ube_pool(api)
 array := ube_msg(api, ube_class(api, c'NSArray'), c'arrayWithObjects:count:', u64(unsafe { &objects[0] }), 3, 0)
 assert ube_msg(api, array, c'count', 0, 0, 0) == 3
 assert ube_keep(api, array) == array
 mut equal := [3]u64{}
 for i in 0 .. 3 {
  value := objects[i]
  assert ube_msg(api, array, c'objectAtIndex:', u64(i), 0, 0) == value
  assert ube_msg(api, ube_keep(api, value), c'autorelease', 0, 0, 0) == value
  copy := ube_msg(api, value, c'copy', 0, 0, 0); assert copy == value; ube_drop(api, copy)
  equal[i] = ube_msg(api, ube_class(api, c'NSString'), c'stringWithUTF8String:', u64(texts[i].str), 0, 0)
  assert ube_msg(api, value, c'length', 0, 0, 0) == u64(texts[i].len)
  assert ube_msg(api, value, c'isEqualToString:', equal[i], 0, 0) == 1
  if api.native { assert unsafe { UBEKeep(C.dlsym(voidptr(api.core), c'CFHash'))(value) } == unsafe { UBEKeep(C.dlsym(voidptr(api.core), c'CFHash'))(equal[i]) } } else { assert cf_hash(value) == cf_hash(equal[i]) }
 }
 dictionary := ube_msg(api, ube_class(api, c'NSDictionary'), c'dictionaryWithObjects:forKeys:count:', u64(unsafe { &equal[0] }), u64(unsafe { &objects[0] }), 3)
 for i in 0 .. 3 { assert ube_msg(api, dictionary, c'objectForKey:', equal[i], 0, 0) == equal[i] }

 backup_keys := [objects[2]]!
 backup_array := ube_msg(api, ube_class(api, c'NSArray'), c'arrayWithObjects:count:', u64(unsafe { &backup_keys[0] }), 1, 0)
 assert ube_msg(api, backup_array, c'count', 0, 0, 0) == 1 && ube_msg(api, backup_array, c'objectAtIndex:', 0, 0, 0) == objects[2]
 assert ube_keep(api, backup_array) == backup_array
 flag := ube_msg(api, ube_class(api, c'NSNumber'), c'numberWithInteger:', 1, 0, 0)
 flags := [flag]!
 backup_dictionary := ube_msg(api, ube_class(api, c'NSDictionary'), c'dictionaryWithObjects:forKeys:count:', u64(unsafe { &flags[0] }), u64(unsafe { &backup_keys[0] }), 1)
 found := ube_msg(api, backup_dictionary, c'objectForKey:', equal[2], 0, 0)
 assert found == flag && ube_msg(api, found, c'boolValue', 0, 0, 0) == 1
 assert ube_keep(api, backup_dictionary) == backup_dictionary
 ube_pop(api, pool)
 for i in 0 .. 3 {
  ube_text(api, read64(cells[i]), texts[i])
  assert ube_msg(api, array, c'objectAtIndex:', u64(i), 0, 0) == objects[i]
 }

 assert ube_msg(api, backup_array, c'objectAtIndex:', 0, 0, 0) == objects[2]
 found_after := ube_msg(api, backup_dictionary, c'objectForKey:', objects[2], 0, 0)
 assert found_after == flag && ube_msg(api, found_after, c'boolValue', 0, 0, 0) == 1
 ube_drop(api, backup_dictionary); ube_drop(api, backup_array)
 ube_drop(api, array)
 if !api.native { assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 }
 return cell
}
__global ube_teardown_calls = 0
fn ube_teardown(object u64, selector &char) {
 assert ios_runtime.swift_concurrency_retired
 for i in 0 .. 3 {
  cell := ube_cell(UBEApi{}, i, true, false)
  assert cell == ube_cell(UBEApi{}, i, false, true)
  ube_text(UBEApi{}, read64(cell), ube_expected(i))
  assert read64(cell) in ios_runtime.constants
 }
 ube_teardown_calls++
}
fn test_ns_url_backup_exclusion() {
 $if macos {
  api := UBEApi{true, u64(C.dlopen(c'/System/Library/Frameworks/Foundation.framework/Foundation', 2)), u64(C.dlopen(c'/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation', 2)), u64(C.dlopen(c'/usr/lib/libobjc.A.dylib', 2))}
  assert api.foundation != 0 && api.core != 0 && api.objc != 0
  ube_shared(api)
  for handle in [api.objc, api.core, api.foundation]! { assert C.dlclose(unsafe { voidptr(handle) }) == 0 }
  println('NATIVE-NS-URL-BACKUP-EXCLUSION: distinct backup/size/creation keys with shared NS/CF alias cells, exact NSString values, eight mixed-key readers, immutable copying/hash/dictionary behavior and retained key-array lifetime')
 }
 for symbol in ['_NSURLIsExcludedFromBackupKey','_kCFURLIsExcludedFromBackupKey']! { if _ := ns_url_resource_key_symbol(symbol) { assert false } }
 for _ in 0 .. 2 {
  objc_start(); assert ios_runtime.url_resource_keys_arena == 0
  ns_url_resource_keys_stop(); assert ios_runtime.url_resource_keys_arena == 0
  ios_runtime.swift_concurrency_retired = true
  for symbol in ['_NSURLCreationDateKey','_kCFURLCreationDateKey','_NSURLFileSizeKey','_kCFURLFileSizeKey','_NSURLIsExcludedFromBackupKey','_kCFURLIsExcludedFromBackupKey']! { if _ := ns_url_resource_key_symbol(symbol) { assert false } }
  ios_runtime.swift_concurrency_retired = false
  cell := ube_shared(UBEApi{}); backup := read64(cell); size := read64(cell - 8); creation := read64(cell - 16)
  assert ios_runtime.foundation_keys_arena == 0
  for symbol in ['_NSURLIsExcludedFromBackupKey','_kCFURLIsExcludedFromBackupKey']! { for library in ['/System/Library/Frameworks/UIKit.framework/UIKit', '/usr/lib/libSystem.B.dylib']! { if _ := runtime_symbol(library, symbol) { assert false } } }
  for name in ['_NSURLIsExcludedFromBackup','_kCFURLIsExcludedFromBackup','_NSURLIsExcludedFromBackupKeyExtra','_kCFURLIsExcludedFromBackupKeyExtra']! { if _ := ns_url_resource_key_symbol(name) { assert false } }
  probe := objc_allocate_class(ios_runtime.names['NSObject'], c'VinixURLBackupExclusionTeardownProbe', 0); assert probe != 0
  assert objc_add_method(probe, u64(c'dealloc'), u64(unsafe { voidptr(ube_teardown) }), c'v16@0:8')
  objc_register_class(probe); objc_autorelease(objc_new(probe))
  ios_runtime.swift_concurrency_retired = true
  assert ube_cell(UBEApi{}, 2, false, true) == cell && ube_cell(UBEApi{}, 1, true, false) == cell - 8 && ube_cell(UBEApi{}, 0, false, true) == cell - 16
  before := ube_teardown_calls; objc_stop()
  assert ube_teardown_calls == before + 1 && ios_runtime.url_resource_keys_arena == 0 && ios_runtime.live == 0 && ios_runtime.objects.len == 0 && backup !in ios_runtime.constants && size !in ios_runtime.constants && creation !in ios_runtime.constants
  for symbol in ['_NSURLCreationDateKey','_kCFURLCreationDateKey','_NSURLFileSizeKey','_kCFURLFileSizeKey','_NSURLIsExcludedFromBackupKey','_kCFURLIsExcludedFromBackupKey']! { if _ := ns_url_resource_key_symbol(symbol) { assert false } }
 }
 println('IOS-NS-URL-BACKUP-EXCLUSION: three distinct sealed resource-key cells with exact CFStrings, eight mixed-key cold publishers, preserved creation-date/file-size layouts, immutable string/hash/dictionary behavior, retained three-key and one-key NSArrays plus NSNumber dictionary across pool drain, isolated Foundation storage, retirement guards, callback access and two drained/unmapped lifetimes')
}

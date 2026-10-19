// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.dlclose(voidptr) i32

type UICName = fn (&char) u64
type UICMessage = fn (u64, u64, u64, u64, u64) u64
type UICKeep = fn (u64) u64
type UICDrop = fn (u64)
type UICPool = fn () u64
type UICBytes = fn (u64, &char, i64, u32) bool
struct UICApi { native bool foundation u64 core u64 objc u64 }

fn uic_cell(api UICApi, key int, core bool, cf bool) u64 {
 names := if cf { ['_kCFURLCreationDateKey','_kCFURLFileSizeKey','_kCFURLIsExcludedFromBackupKey','_kCFURLIsRegularFileKey','_kCFURLVolumeAvailableCapacityForImportantUsageKey']! } else { ['_NSURLCreationDateKey','_NSURLFileSizeKey','_NSURLIsExcludedFromBackupKey','_NSURLIsRegularFileKey','_NSURLVolumeAvailableCapacityForImportantUsageKey']! }
 name := names[key]
 if api.native { return u64(C.dlsym(unsafe { voidptr(if core { api.core } else { api.foundation }) }, unsafe { &char(name.str + 1) })) }
 library := if core { '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation' } else { '/System/Library/Frameworks/Foundation.framework/Foundation' }
 return runtime_symbol(library, name) or { panic(err) }
}
fn uic_msg(api UICApi, object u64, name &char, a u64, b u64, c u64) u64 {
 if api.native {
  selector := unsafe { UICName(C.dlsym(voidptr(api.objc), c'sel_registerName'))(name) }
  return unsafe { UICMessage(C.dlsym(voidptr(api.objc), c'objc_msgSend'))(object, selector, a, b, c) }
 }
 return unsafe { UICMessage(voidptr(C.ios_objc_builtin))(object, u64(name), a, b, c) }
}
fn uic_class(api UICApi, name &char) u64 {
 if api.native { return unsafe { UICName(C.dlsym(voidptr(api.objc), c'objc_getClass'))(name) } }
 return ios_runtime.names[ctext(u64(name))]
}
fn uic_pool(api UICApi) u64 {
 if api.native { return unsafe { UICPool(C.dlsym(voidptr(api.objc), c'objc_autoreleasePoolPush'))() } }
 return objc_pool_push()
}
fn uic_pop(api UICApi, pool u64) {
 if api.native { unsafe { UICDrop(C.dlsym(voidptr(api.objc), c'objc_autoreleasePoolPop'))(pool) }; return }
 objc_pool_pop(pool)
}
fn uic_keep(api UICApi, object u64) u64 {
 if api.native { return unsafe { UICKeep(C.dlsym(voidptr(api.core), c'CFRetain'))(object) } }
 return objc_retain(object)
}
fn uic_drop(api UICApi, object u64) {
 if api.native { unsafe { UICDrop(C.dlsym(voidptr(api.core), c'CFRelease'))(object) }; return }
 objc_release(object)
}
fn uic_text(api UICApi, object u64, expected string) {
 assert object != 0
 if !api.native { assert string_text(object) == expected && cf_type_id(object) == cf_string_id(); return }
 mut bytes := [128]u8{}
 assert unsafe { UICBytes(C.dlsym(voidptr(api.core), c'CFStringGetCString'))(object, &char(&bytes[0]), 128, 0x08000100) }
 assert bytes[expected.len] == 0 && C.memcmp(unsafe { &bytes[0] }, expected.str, usize(expected.len)) == 0
}

fn uic_expected(key int) string {
 texts := ['NSURLCreationDateKey','NSURLFileSizeKey','NSURLIsExcludedFromBackupKey', 'NSURLIsRegularFileKey', 'NSURLVolumeAvailableCapacityForImportantUsageKey']!
 return texts[key]
}
fn uic_reader(api UICApi, offset int) u64 {
 mut cells := [5]u64{}
 for turn in 0 .. 64 {
  for step in 0 .. 20 {
   index := (offset + step + turn) % 20
   key := index / 4
   got := uic_cell(api, key, index % 2 == 0, (index / 2) % 2 == 0)
   assert got != 0 && got % 8 == 0
   if cells[key] == 0 { cells[key] = got } else { assert got == cells[key] }
   value := read64(got); assert value != got
   uic_text(api, value, uic_expected(key))
   assert uic_keep(api, value) == value; uic_drop(api, value)
  }
 }
 for i in 0 .. 5 { for j in 0 .. i { assert cells[i] != cells[j] && read64(cells[i]) != read64(cells[j]) } }
 return cells[4]
}
fn uic_shared(api UICApi) u64 {
 mut workers := []thread u64{}
 for offset in 0 .. 8 { workers << spawn uic_reader(api, (offset * 3 + 16) % 20) }
 mut cell := u64(0)
 for i, worker in workers { got := worker.wait(); if i == 0 { cell = got } else { assert cell == got } }
 unsafe { workers.free() }
 creation := uic_cell(api, 0, false, false)
 cells := [creation, uic_cell(api, 1, false, false), uic_cell(api, 2, false, false), uic_cell(api, 3, false, false), cell]!
 objects := [read64(cells[0]), read64(cells[1]), read64(cells[2]), read64(cells[3]), read64(cells[4])]!
 texts := ['NSURLCreationDateKey', 'NSURLFileSizeKey', 'NSURLIsExcludedFromBackupKey', 'NSURLIsRegularFileKey', 'NSURLVolumeAvailableCapacityForImportantUsageKey']!
 if !api.native {
  assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 && ios_runtime.framework_objects.len == 0
  assert creation == ios_runtime.url_resource_keys_arena && cell == creation + 96
  cell_offsets := [u64(0), 8, 16, 24, 96]!
  records := [u64(32), 128, 192, 256, 320]!; bytes := [u64(64), 160, 224, 288, 352]!
  for i in 0 .. 5 {
   assert cells[i] == creation + cell_offsets[i]
   value := objects[i]
   assert value == creation + records[i]
   assert read64(value) == ios_runtime.names['NSString'] && read64(value + 8) == 0x7c8 && read64(value + 24) == u64(texts[i].len)
   assert read64(value + 16) == creation + bytes[i] && unsafe { *(&u8(creation + bytes[i] + u64(texts[i].len))) } == 0 && value in ios_runtime.constants
  }
  for symbol in ['_NSURLCreationDateKey','_kCFURLCreationDateKey','_NSURLFileSizeKey','_kCFURLFileSizeKey','_NSURLIsExcludedFromBackupKey','_kCFURLIsExcludedFromBackupKey','_NSURLIsRegularFileKey','_kCFURLIsRegularFileKey','_NSURLVolumeAvailableCapacityForImportantUsageKey','_kCFURLVolumeAvailableCapacityForImportantUsageKey']! { assert symbol !in ios_runtime.framework_data }
 }
 pool := uic_pool(api)
 array := uic_msg(api, uic_class(api, c'NSArray'), c'arrayWithObjects:count:', u64(unsafe { &objects[0] }), 5, 0)
 assert uic_msg(api, array, c'count', 0, 0, 0) == 5
 assert uic_keep(api, array) == array
 mut equal := [5]u64{}
 for i in 0 .. 5 {
  value := objects[i]
  assert uic_msg(api, array, c'objectAtIndex:', u64(i), 0, 0) == value
  assert uic_msg(api, uic_keep(api, value), c'autorelease', 0, 0, 0) == value
  copy := uic_msg(api, value, c'copy', 0, 0, 0); assert copy == value; uic_drop(api, copy)
  equal[i] = uic_msg(api, uic_class(api, c'NSString'), c'stringWithUTF8String:', u64(texts[i].str), 0, 0)
  assert uic_msg(api, value, c'length', 0, 0, 0) == u64(texts[i].len)
  assert uic_msg(api, value, c'isEqualToString:', equal[i], 0, 0) == 1
  if api.native { assert unsafe { UICKeep(C.dlsym(voidptr(api.core), c'CFHash'))(value) } == unsafe { UICKeep(C.dlsym(voidptr(api.core), c'CFHash'))(equal[i]) } } else { assert cf_hash(value) == cf_hash(equal[i]) }
 }
 dictionary := uic_msg(api, uic_class(api, c'NSDictionary'), c'dictionaryWithObjects:forKeys:count:', u64(unsafe { &equal[0] }), u64(unsafe { &objects[0] }), 5)
 for i in 0 .. 5 { assert uic_msg(api, dictionary, c'objectForKey:', equal[i], 0, 0) == equal[i] }


 capacity_keys := [objects[4]]!
 capacity_array := uic_msg(api, uic_class(api, c'NSArray'), c'arrayWithObjects:count:', u64(unsafe { &capacity_keys[0] }), 1, 0)
 assert uic_msg(api, capacity_array, c'count', 0, 0, 0) == 1 && uic_msg(api, capacity_array, c'objectAtIndex:', 0, 0, 0) == objects[4]
 assert uic_keep(api, capacity_array) == capacity_array
 capacity := u64(5) * 1024 * 1024 * 1024 + 17
 number := uic_msg(api, uic_class(api, c'NSNumber'), c'numberWithInteger:', capacity, 0, 0)
 values := [number]!
 capacity_dictionary := uic_msg(api, uic_class(api, c'NSDictionary'), c'dictionaryWithObjects:forKeys:count:', u64(unsafe { &values[0] }), u64(unsafe { &capacity_keys[0] }), 1)
 found := uic_msg(api, capacity_dictionary, c'objectForKey:', equal[4], 0, 0)
 assert found == number && uic_msg(api, found, c'integerValue', 0, 0, 0) == capacity
 assert uic_keep(api, capacity_dictionary) == capacity_dictionary
 uic_pop(api, pool)
 for i in 0 .. 5 {
  uic_text(api, read64(cells[i]), texts[i])
  assert uic_msg(api, array, c'objectAtIndex:', u64(i), 0, 0) == objects[i]
 }


 assert uic_msg(api, capacity_array, c'objectAtIndex:', 0, 0, 0) == objects[4]
 found_after := uic_msg(api, capacity_dictionary, c'objectForKey:', objects[4], 0, 0)
 assert found_after == number && uic_msg(api, found_after, c'integerValue', 0, 0, 0) == capacity
 uic_drop(api, capacity_dictionary); uic_drop(api, capacity_array)
 uic_drop(api, array)
 if !api.native { assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 }
 return cell
}
__global uic_teardown_calls = 0
fn uic_teardown(object u64, selector &char) {
 assert ios_runtime.swift_concurrency_retired
 for i in 0 .. 5 {
  cell := uic_cell(UICApi{}, i, true, false)
  assert cell == uic_cell(UICApi{}, i, false, true)
  uic_text(UICApi{}, read64(cell), uic_expected(i))
  assert read64(cell) in ios_runtime.constants
 }
 uic_teardown_calls++
}
fn test_ns_url_important_capacity() {
 $if macos {
  api := UICApi{true, u64(C.dlopen(c'/System/Library/Frameworks/Foundation.framework/Foundation', 2)), u64(C.dlopen(c'/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation', 2)), u64(C.dlopen(c'/usr/lib/libobjc.A.dylib', 2))}
  assert api.foundation != 0 && api.core != 0 && api.objc != 0
  uic_shared(api)
  for handle in [api.objc, api.core, api.foundation]! { assert C.dlclose(unsafe { voidptr(handle) }) == 0 }
  println('NATIVE-NS-URL-IMPORTANT-CAPACITY: distinct capacity/regular/backup/size/creation keys with shared NS/CF alias cells, exact NSString values, eight mixed-key readers, immutable copying/hash/dictionary behavior and retained key-array lifetime')
 }
 for symbol in ['_NSURLVolumeAvailableCapacityForImportantUsageKey','_kCFURLVolumeAvailableCapacityForImportantUsageKey']! { if _ := ns_url_resource_key_symbol(symbol) { assert false } }
 for _ in 0 .. 2 {
  objc_start(); assert ios_runtime.url_resource_keys_arena == 0
  ns_url_resource_keys_stop(); assert ios_runtime.url_resource_keys_arena == 0
  ios_runtime.swift_concurrency_retired = true
  for symbol in ['_NSURLCreationDateKey','_kCFURLCreationDateKey','_NSURLFileSizeKey','_kCFURLFileSizeKey','_NSURLIsExcludedFromBackupKey','_kCFURLIsExcludedFromBackupKey','_NSURLIsRegularFileKey','_kCFURLIsRegularFileKey','_NSURLVolumeAvailableCapacityForImportantUsageKey','_kCFURLVolumeAvailableCapacityForImportantUsageKey']! { if _ := ns_url_resource_key_symbol(symbol) { assert false } }
  ios_runtime.swift_concurrency_retired = false
  cell := uic_shared(UICApi{}); base := uic_cell(UICApi{}, 0, false, false)
  important := read64(cell); regular := read64(base + 24); backup := read64(base + 16); size := read64(base + 8); creation := read64(base)
  assert ios_runtime.foundation_keys_arena == 0
  for symbol in ['_NSURLVolumeAvailableCapacityForImportantUsageKey','_kCFURLVolumeAvailableCapacityForImportantUsageKey']! { for library in ['/System/Library/Frameworks/UIKit.framework/UIKit', '/usr/lib/libSystem.B.dylib']! { if _ := runtime_symbol(library, symbol) { assert false } } }
  for name in ['_NSURLVolumeAvailableCapacityForImportantUsage','_kCFURLVolumeAvailableCapacityForImportantUsage','_NSURLVolumeAvailableCapacityForImportantUsageKeyExtra','_kCFURLVolumeAvailableCapacityForImportantUsageKeyExtra']! { if _ := ns_url_resource_key_symbol(name) { assert false } }
  probe := objc_allocate_class(ios_runtime.names['NSObject'], c'VinixURLImportantCapacityTeardownProbe', 0); assert probe != 0
  assert objc_add_method(probe, u64(c'dealloc'), u64(unsafe { voidptr(uic_teardown) }), c'v16@0:8')
  objc_register_class(probe); objc_autorelease(objc_new(probe))
  ios_runtime.swift_concurrency_retired = true
  offsets := [u64(0), 8, 16, 24, 96]!
  for i in 0 .. 5 { assert uic_cell(UICApi{}, i, false, true) == base + offsets[i] && uic_cell(UICApi{}, i, true, false) == base + offsets[i] }
  before := uic_teardown_calls; objc_stop()
  assert uic_teardown_calls == before + 1 && ios_runtime.url_resource_keys_arena == 0 && ios_runtime.live == 0 && ios_runtime.objects.len == 0 && important !in ios_runtime.constants && regular !in ios_runtime.constants && backup !in ios_runtime.constants && size !in ios_runtime.constants && creation !in ios_runtime.constants
  for symbol in ['_NSURLCreationDateKey','_kCFURLCreationDateKey','_NSURLFileSizeKey','_kCFURLFileSizeKey','_NSURLIsExcludedFromBackupKey','_kCFURLIsExcludedFromBackupKey','_NSURLIsRegularFileKey','_kCFURLIsRegularFileKey','_NSURLVolumeAvailableCapacityForImportantUsageKey','_kCFURLVolumeAvailableCapacityForImportantUsageKey']! { if _ := ns_url_resource_key_symbol(symbol) { assert false } }
 }
 println('IOS-NS-URL-IMPORTANT-CAPACITY: five distinct sealed resource-key cells with exact CFStrings, eight mixed-key cold publishers, preserved four prior layouts and gap-cell placement, immutable string/hash/dictionary behavior, retained five-key and important-capacity NSArrays plus 64-bit NSNumber dictionary across pool drain, isolated Foundation storage, retirement guards, callback access and two drained/unmapped lifetimes')
}

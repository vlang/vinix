// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.dlclose(voidptr) i32

type UTCName = fn (&char) u64
type UTCMessage = fn (u64, u64, u64, u64, u64) u64
type UTCKeep = fn (u64) u64
type UTCDrop = fn (u64)
type UTCPool = fn () u64
type UTCBytes = fn (u64, &char, i64, u32) bool
struct UTCApi { native bool foundation u64 core u64 objc u64 }

fn utc_cell(api UTCApi, key int, core bool, cf bool) u64 {
 names := if cf { ['_kCFURLCreationDateKey','_kCFURLFileSizeKey','_kCFURLIsExcludedFromBackupKey','_kCFURLIsRegularFileKey','_kCFURLVolumeAvailableCapacityForImportantUsageKey','_kCFURLVolumeAvailableCapacityKey','_kCFURLVolumeTotalCapacityKey']! } else { ['_NSURLCreationDateKey','_NSURLFileSizeKey','_NSURLIsExcludedFromBackupKey','_NSURLIsRegularFileKey','_NSURLVolumeAvailableCapacityForImportantUsageKey','_NSURLVolumeAvailableCapacityKey','_NSURLVolumeTotalCapacityKey']! }
 name := names[key]
 if api.native { return u64(C.dlsym(unsafe { voidptr(if core { api.core } else { api.foundation }) }, unsafe { &char(name.str + 1) })) }
 library := if core { '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation' } else { '/System/Library/Frameworks/Foundation.framework/Foundation' }
 return runtime_symbol(library, name) or { panic(err) }
}
fn utc_msg(api UTCApi, object u64, name &char, a u64, b u64, c u64) u64 {
 if api.native {
  selector := unsafe { UTCName(C.dlsym(voidptr(api.objc), c'sel_registerName'))(name) }
  return unsafe { UTCMessage(C.dlsym(voidptr(api.objc), c'objc_msgSend'))(object, selector, a, b, c) }
 }
 return unsafe { UTCMessage(voidptr(C.ios_objc_builtin))(object, u64(name), a, b, c) }
}
fn utc_class(api UTCApi, name &char) u64 {
 if api.native { return unsafe { UTCName(C.dlsym(voidptr(api.objc), c'objc_getClass'))(name) } }
 return ios_runtime.names[ctext(u64(name))]
}
fn utc_pool(api UTCApi) u64 {
 if api.native { return unsafe { UTCPool(C.dlsym(voidptr(api.objc), c'objc_autoreleasePoolPush'))() } }
 return objc_pool_push()
}
fn utc_pop(api UTCApi, pool u64) {
 if api.native { unsafe { UTCDrop(C.dlsym(voidptr(api.objc), c'objc_autoreleasePoolPop'))(pool) }; return }
 objc_pool_pop(pool)
}
fn utc_keep(api UTCApi, object u64) u64 {
 if api.native { return unsafe { UTCKeep(C.dlsym(voidptr(api.core), c'CFRetain'))(object) } }
 return objc_retain(object)
}
fn utc_drop(api UTCApi, object u64) {
 if api.native { unsafe { UTCDrop(C.dlsym(voidptr(api.core), c'CFRelease'))(object) }; return }
 objc_release(object)
}
fn utc_text(api UTCApi, object u64, expected string) {
 assert object != 0
 if !api.native { assert string_text(object) == expected && cf_type_id(object) == cf_string_id(); return }
 mut bytes := [128]u8{}
 assert unsafe { UTCBytes(C.dlsym(voidptr(api.core), c'CFStringGetCString'))(object, &char(&bytes[0]), 128, 0x08000100) }
 assert bytes[expected.len] == 0 && C.memcmp(unsafe { &bytes[0] }, expected.str, usize(expected.len)) == 0
}

fn utc_expected(key int) string {
 texts := ['NSURLCreationDateKey','NSURLFileSizeKey','NSURLIsExcludedFromBackupKey', 'NSURLIsRegularFileKey', 'NSURLVolumeAvailableCapacityForImportantUsageKey', 'NSURLVolumeAvailableCapacityKey', 'NSURLVolumeTotalCapacityKey']!
 return texts[key]
}
fn utc_reader(api UTCApi, offset int) u64 {
 mut cells := [7]u64{}
 for turn in 0 .. 64 {
  for step in 0 .. 28 {
   index := (offset + step + turn) % 28
   key := index / 4
   got := utc_cell(api, key, index % 2 == 0, (index / 2) % 2 == 0)
   assert got != 0 && got % 8 == 0
   if cells[key] == 0 { cells[key] = got } else { assert got == cells[key] }
   value := read64(got); assert value != got
   utc_text(api, value, utc_expected(key))
   assert utc_keep(api, value) == value; utc_drop(api, value)
  }
 }
 for i in 0 .. 7 { for j in 0 .. i { assert cells[i] != cells[j] && read64(cells[i]) != read64(cells[j]) } }
 return cells[6]
}
fn utc_shared(api UTCApi) u64 {
 mut workers := []thread u64{}
 for offset in 0 .. 8 { workers << spawn utc_reader(api, (offset * 3 + 24) % 28) }
 mut cell := u64(0)
 for i, worker in workers { got := worker.wait(); if i == 0 { cell = got } else { assert cell == got } }
 unsafe { workers.free() }
 creation := utc_cell(api, 0, false, false)
 cells := [creation, utc_cell(api, 1, false, false), utc_cell(api, 2, false, false), utc_cell(api, 3, false, false), utc_cell(api, 4, false, false), utc_cell(api, 5, false, false), cell]!
 objects := [read64(cells[0]), read64(cells[1]), read64(cells[2]), read64(cells[3]), read64(cells[4]), read64(cells[5]), read64(cells[6])]!
 texts := ['NSURLCreationDateKey', 'NSURLFileSizeKey', 'NSURLIsExcludedFromBackupKey', 'NSURLIsRegularFileKey', 'NSURLVolumeAvailableCapacityForImportantUsageKey', 'NSURLVolumeAvailableCapacityKey', 'NSURLVolumeTotalCapacityKey']!
 if !api.native {
  assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 && ios_runtime.framework_objects.len == 0
  assert creation == ios_runtime.url_resource_keys_arena && cell == creation + 112
  cell_offsets := [u64(0), 8, 16, 24, 96, 104, 112]!
  records := [u64(32), 128, 192, 256, 320, 416, 480]!; bytes := [u64(64), 160, 224, 288, 352, 448, 512]!
  for i in 0 .. 7 {
   assert cells[i] == creation + cell_offsets[i]
   value := objects[i]
   assert value == creation + records[i]
   assert read64(value) == ios_runtime.names['NSString'] && read64(value + 8) == 0x7c8 && read64(value + 24) == u64(texts[i].len)
   assert read64(value + 16) == creation + bytes[i] && unsafe { *(&u8(creation + bytes[i] + u64(texts[i].len))) } == 0 && value in ios_runtime.constants
  }
  for symbol in ['_NSURLCreationDateKey','_kCFURLCreationDateKey','_NSURLFileSizeKey','_kCFURLFileSizeKey','_NSURLIsExcludedFromBackupKey','_kCFURLIsExcludedFromBackupKey','_NSURLIsRegularFileKey','_kCFURLIsRegularFileKey','_NSURLVolumeAvailableCapacityForImportantUsageKey','_kCFURLVolumeAvailableCapacityForImportantUsageKey','_NSURLVolumeAvailableCapacityKey','_kCFURLVolumeAvailableCapacityKey','_NSURLVolumeTotalCapacityKey','_kCFURLVolumeTotalCapacityKey']! { assert symbol !in ios_runtime.framework_data }
 }
 pool := utc_pool(api)
 array := utc_msg(api, utc_class(api, c'NSArray'), c'arrayWithObjects:count:', u64(unsafe { &objects[0] }), 7, 0)
 assert utc_msg(api, array, c'count', 0, 0, 0) == 7
 assert utc_keep(api, array) == array
 mut equal := [7]u64{}
 for i in 0 .. 7 {
  value := objects[i]
  assert utc_msg(api, array, c'objectAtIndex:', u64(i), 0, 0) == value
  assert utc_msg(api, utc_keep(api, value), c'autorelease', 0, 0, 0) == value
  copy := utc_msg(api, value, c'copy', 0, 0, 0); assert copy == value; utc_drop(api, copy)
  equal[i] = utc_msg(api, utc_class(api, c'NSString'), c'stringWithUTF8String:', u64(texts[i].str), 0, 0)
  assert utc_msg(api, value, c'length', 0, 0, 0) == u64(texts[i].len)
  assert utc_msg(api, value, c'isEqualToString:', equal[i], 0, 0) == 1
  if api.native { assert unsafe { UTCKeep(C.dlsym(voidptr(api.core), c'CFHash'))(value) } == unsafe { UTCKeep(C.dlsym(voidptr(api.core), c'CFHash'))(equal[i]) } } else { assert cf_hash(value) == cf_hash(equal[i]) }
 }
 dictionary := utc_msg(api, utc_class(api, c'NSDictionary'), c'dictionaryWithObjects:forKeys:count:', u64(unsafe { &equal[0] }), u64(unsafe { &objects[0] }), 7)
 for i in 0 .. 7 { assert utc_msg(api, dictionary, c'objectForKey:', equal[i], 0, 0) == equal[i] }

 capacity_keys := [objects[4], objects[5], objects[6]]!
 capacity_array := utc_msg(api, utc_class(api, c'NSArray'), c'arrayWithObjects:count:', u64(unsafe { &capacity_keys[0] }), 3, 0)
 assert utc_msg(api, capacity_array, c'count', 0, 0, 0) == 3
 assert utc_keep(api, capacity_array) == capacity_array
 capacities := [u64(5) * 1024 * 1024 * 1024 + 17, u64(7) * 1024 * 1024 * 1024 + 29, u64(11) * 1024 * 1024 * 1024 + 43]!
 values := [utc_msg(api, utc_class(api, c'NSNumber'), c'numberWithInteger:', capacities[0], 0, 0), utc_msg(api, utc_class(api, c'NSNumber'), c'numberWithInteger:', capacities[1], 0, 0), utc_msg(api, utc_class(api, c'NSNumber'), c'numberWithInteger:', capacities[2], 0, 0)]!
 capacity_dictionary := utc_msg(api, utc_class(api, c'NSDictionary'), c'dictionaryWithObjects:forKeys:count:', u64(unsafe { &values[0] }), u64(unsafe { &capacity_keys[0] }), 3)
 for i in 0 .. 3 {
  assert utc_msg(api, capacity_array, c'objectAtIndex:', u64(i), 0, 0) == objects[4+i]
  found := utc_msg(api, capacity_dictionary, c'objectForKey:', equal[4+i], 0, 0)
  assert found == values[i] && utc_msg(api, found, c'integerValue', 0, 0, 0) == capacities[i]
 }
 assert utc_keep(api, capacity_dictionary) == capacity_dictionary
 utc_pop(api, pool)
 for i in 0 .. 7 {
  utc_text(api, read64(cells[i]), texts[i])
  assert utc_msg(api, array, c'objectAtIndex:', u64(i), 0, 0) == objects[i]
 }

 for i in 0 .. 3 {
  assert utc_msg(api, capacity_array, c'objectAtIndex:', u64(i), 0, 0) == objects[4+i]
  found := utc_msg(api, capacity_dictionary, c'objectForKey:', objects[4+i], 0, 0)
  assert found == values[i] && utc_msg(api, found, c'integerValue', 0, 0, 0) == capacities[i]
 }
 utc_drop(api, capacity_dictionary); utc_drop(api, capacity_array)
 utc_drop(api, array)
 if !api.native { assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 }
 return cell
}
__global utc_teardown_calls = 0
fn utc_teardown(object u64, selector &char) {
 assert ios_runtime.swift_concurrency_retired
 for i in 0 .. 7 {
  cell := utc_cell(UTCApi{}, i, true, false)
  assert cell == utc_cell(UTCApi{}, i, false, true)
  utc_text(UTCApi{}, read64(cell), utc_expected(i))
  assert read64(cell) in ios_runtime.constants
 }
 utc_teardown_calls++
}
fn test_ns_url_total_capacity() {
 $if macos {
  api := UTCApi{true, u64(C.dlopen(c'/System/Library/Frameworks/Foundation.framework/Foundation', 2)), u64(C.dlopen(c'/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation', 2)), u64(C.dlopen(c'/usr/lib/libobjc.A.dylib', 2))}
  assert api.foundation != 0 && api.core != 0 && api.objc != 0
  utc_shared(api)
  for handle in [api.objc, api.core, api.foundation]! { assert C.dlclose(unsafe { voidptr(handle) }) == 0 }
  println('NATIVE-NS-URL-TOTAL-CAPACITY: distinct total/available/important/regular/backup/size/creation keys with shared NS/CF alias cells, exact NSString values, eight mixed-key readers, immutable copying/hash/dictionary behavior and retained key-array lifetime')
 }
 for symbol in ['_NSURLVolumeAvailableCapacityForImportantUsageKey','_kCFURLVolumeAvailableCapacityForImportantUsageKey','_NSURLVolumeAvailableCapacityKey','_kCFURLVolumeAvailableCapacityKey','_NSURLVolumeTotalCapacityKey','_kCFURLVolumeTotalCapacityKey']! { if _ := ns_url_resource_key_symbol(symbol) { assert false } }
 for _ in 0 .. 2 {
  objc_start(); assert ios_runtime.url_resource_keys_arena == 0
  ns_url_resource_keys_stop(); assert ios_runtime.url_resource_keys_arena == 0
  ios_runtime.swift_concurrency_retired = true
  for symbol in ['_NSURLCreationDateKey','_kCFURLCreationDateKey','_NSURLFileSizeKey','_kCFURLFileSizeKey','_NSURLIsExcludedFromBackupKey','_kCFURLIsExcludedFromBackupKey','_NSURLIsRegularFileKey','_kCFURLIsRegularFileKey','_NSURLVolumeAvailableCapacityForImportantUsageKey','_kCFURLVolumeAvailableCapacityForImportantUsageKey','_NSURLVolumeAvailableCapacityKey','_kCFURLVolumeAvailableCapacityKey','_NSURLVolumeTotalCapacityKey','_kCFURLVolumeTotalCapacityKey']! { if _ := ns_url_resource_key_symbol(symbol) { assert false } }
  ios_runtime.swift_concurrency_retired = false
  cell := utc_shared(UTCApi{}); base := utc_cell(UTCApi{}, 0, false, false)
  total := read64(cell); available := read64(base + 104); important := read64(base + 96); regular := read64(base + 24); backup := read64(base + 16); size := read64(base + 8); creation := read64(base)
  assert ios_runtime.foundation_keys_arena == 0
  for symbol in ['_NSURLVolumeAvailableCapacityForImportantUsageKey','_kCFURLVolumeAvailableCapacityForImportantUsageKey','_NSURLVolumeAvailableCapacityKey','_kCFURLVolumeAvailableCapacityKey','_NSURLVolumeTotalCapacityKey','_kCFURLVolumeTotalCapacityKey']! { for library in ['/System/Library/Frameworks/UIKit.framework/UIKit', '/usr/lib/libSystem.B.dylib']! { if _ := runtime_symbol(library, symbol) { assert false } } }
  for name in ['_NSURLVolumeTotalCapacity','_kCFURLVolumeTotalCapacity','_NSURLVolumeTotalCapacityKeyExtra','_kCFURLVolumeTotalCapacityKeyExtra']! { if _ := ns_url_resource_key_symbol(name) { assert false } }
  probe := objc_allocate_class(ios_runtime.names['NSObject'], c'VinixURLTotalCapacityTeardownProbe', 0); assert probe != 0
  assert objc_add_method(probe, u64(c'dealloc'), u64(unsafe { voidptr(utc_teardown) }), c'v16@0:8')
  objc_register_class(probe); objc_autorelease(objc_new(probe))
  ios_runtime.swift_concurrency_retired = true
  offsets := [u64(0), 8, 16, 24, 96, 104, 112]!
  for i in 0 .. 7 { assert utc_cell(UTCApi{}, i, false, true) == base + offsets[i] && utc_cell(UTCApi{}, i, true, false) == base + offsets[i] }
  before := utc_teardown_calls; objc_stop()
  assert utc_teardown_calls == before + 1 && ios_runtime.url_resource_keys_arena == 0 && ios_runtime.live == 0 && ios_runtime.objects.len == 0 && total !in ios_runtime.constants && available !in ios_runtime.constants && important !in ios_runtime.constants && regular !in ios_runtime.constants && backup !in ios_runtime.constants && size !in ios_runtime.constants && creation !in ios_runtime.constants
  for symbol in ['_NSURLCreationDateKey','_kCFURLCreationDateKey','_NSURLFileSizeKey','_kCFURLFileSizeKey','_NSURLIsExcludedFromBackupKey','_kCFURLIsExcludedFromBackupKey','_NSURLIsRegularFileKey','_kCFURLIsRegularFileKey','_NSURLVolumeAvailableCapacityForImportantUsageKey','_kCFURLVolumeAvailableCapacityForImportantUsageKey','_NSURLVolumeAvailableCapacityKey','_kCFURLVolumeAvailableCapacityKey','_NSURLVolumeTotalCapacityKey','_kCFURLVolumeTotalCapacityKey']! { if _ := ns_url_resource_key_symbol(symbol) { assert false } }
 }
 println('IOS-NS-URL-TOTAL-CAPACITY: seven distinct sealed resource-key cells with exact CFStrings, eight mixed-key cold publishers, preserved six prior layouts and three gap-cell placements, immutable string/hash/dictionary behavior, retained seven-key and three-capacity NSArrays plus distinct 64-bit NSNumber dictionary values across pool drain, isolated Foundation storage, retirement guards, callback access and two drained/unmapped lifetimes')
}

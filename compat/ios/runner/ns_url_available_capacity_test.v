// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.dlclose(voidptr) i32

type UACName = fn (&char) u64
type UACMessage = fn (u64, u64, u64, u64, u64) u64
type UACKeep = fn (u64) u64
type UACDrop = fn (u64)
type UACPool = fn () u64
type UACBytes = fn (u64, &char, i64, u32) bool
struct UACApi { native bool foundation u64 core u64 objc u64 }

fn uac_cell(api UACApi, key int, core bool, cf bool) u64 {
 names := if cf { ['_kCFURLCreationDateKey','_kCFURLFileSizeKey','_kCFURLIsExcludedFromBackupKey','_kCFURLIsRegularFileKey','_kCFURLVolumeAvailableCapacityForImportantUsageKey','_kCFURLVolumeAvailableCapacityKey']! } else { ['_NSURLCreationDateKey','_NSURLFileSizeKey','_NSURLIsExcludedFromBackupKey','_NSURLIsRegularFileKey','_NSURLVolumeAvailableCapacityForImportantUsageKey','_NSURLVolumeAvailableCapacityKey']! }
 name := names[key]
 if api.native { return u64(C.dlsym(unsafe { voidptr(if core { api.core } else { api.foundation }) }, unsafe { &char(name.str + 1) })) }
 library := if core { '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation' } else { '/System/Library/Frameworks/Foundation.framework/Foundation' }
 return runtime_symbol(library, name) or { panic(err) }
}
fn uac_msg(api UACApi, object u64, name &char, a u64, b u64, c u64) u64 {
 if api.native {
  selector := unsafe { UACName(C.dlsym(voidptr(api.objc), c'sel_registerName'))(name) }
  return unsafe { UACMessage(C.dlsym(voidptr(api.objc), c'objc_msgSend'))(object, selector, a, b, c) }
 }
 return unsafe { UACMessage(voidptr(C.ios_objc_builtin))(object, u64(name), a, b, c) }
}
fn uac_class(api UACApi, name &char) u64 {
 if api.native { return unsafe { UACName(C.dlsym(voidptr(api.objc), c'objc_getClass'))(name) } }
 return ios_runtime.names[ctext(u64(name))]
}
fn uac_pool(api UACApi) u64 {
 if api.native { return unsafe { UACPool(C.dlsym(voidptr(api.objc), c'objc_autoreleasePoolPush'))() } }
 return objc_pool_push()
}
fn uac_pop(api UACApi, pool u64) {
 if api.native { unsafe { UACDrop(C.dlsym(voidptr(api.objc), c'objc_autoreleasePoolPop'))(pool) }; return }
 objc_pool_pop(pool)
}
fn uac_keep(api UACApi, object u64) u64 {
 if api.native { return unsafe { UACKeep(C.dlsym(voidptr(api.core), c'CFRetain'))(object) } }
 return objc_retain(object)
}
fn uac_drop(api UACApi, object u64) {
 if api.native { unsafe { UACDrop(C.dlsym(voidptr(api.core), c'CFRelease'))(object) }; return }
 objc_release(object)
}
fn uac_text(api UACApi, object u64, expected string) {
 assert object != 0
 if !api.native { assert string_text(object) == expected && cf_type_id(object) == cf_string_id(); return }
 mut bytes := [128]u8{}
 assert unsafe { UACBytes(C.dlsym(voidptr(api.core), c'CFStringGetCString'))(object, &char(&bytes[0]), 128, 0x08000100) }
 assert bytes[expected.len] == 0 && C.memcmp(unsafe { &bytes[0] }, expected.str, usize(expected.len)) == 0
}

fn uac_expected(key int) string {
 texts := ['NSURLCreationDateKey','NSURLFileSizeKey','NSURLIsExcludedFromBackupKey', 'NSURLIsRegularFileKey', 'NSURLVolumeAvailableCapacityForImportantUsageKey', 'NSURLVolumeAvailableCapacityKey']!
 return texts[key]
}
fn uac_reader(api UACApi, offset int) u64 {
 mut cells := [6]u64{}
 for turn in 0 .. 64 {
  for step in 0 .. 24 {
   index := (offset + step + turn) % 24
   key := index / 4
   got := uac_cell(api, key, index % 2 == 0, (index / 2) % 2 == 0)
   assert got != 0 && got % 8 == 0
   if cells[key] == 0 { cells[key] = got } else { assert got == cells[key] }
   value := read64(got); assert value != got
   uac_text(api, value, uac_expected(key))
   assert uac_keep(api, value) == value; uac_drop(api, value)
  }
 }
 for i in 0 .. 6 { for j in 0 .. i { assert cells[i] != cells[j] && read64(cells[i]) != read64(cells[j]) } }
 return cells[5]
}
fn uac_shared(api UACApi) u64 {
 mut workers := []thread u64{}
 for offset in 0 .. 8 { workers << spawn uac_reader(api, (offset * 5 + 20) % 24) }
 mut cell := u64(0)
 for i, worker in workers { got := worker.wait(); if i == 0 { cell = got } else { assert cell == got } }
 unsafe { workers.free() }
 creation := uac_cell(api, 0, false, false)
 cells := [creation, uac_cell(api, 1, false, false), uac_cell(api, 2, false, false), uac_cell(api, 3, false, false), uac_cell(api, 4, false, false), cell]!
 objects := [read64(cells[0]), read64(cells[1]), read64(cells[2]), read64(cells[3]), read64(cells[4]), read64(cells[5])]!
 texts := ['NSURLCreationDateKey', 'NSURLFileSizeKey', 'NSURLIsExcludedFromBackupKey', 'NSURLIsRegularFileKey', 'NSURLVolumeAvailableCapacityForImportantUsageKey', 'NSURLVolumeAvailableCapacityKey']!
 if !api.native {
  assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 && ios_runtime.framework_objects.len == 0
  assert creation == ios_runtime.url_resource_keys_arena && cell == creation + 104
  cell_offsets := [u64(0), 8, 16, 24, 96, 104]!
  records := [u64(32), 128, 192, 256, 320, 416]!; bytes := [u64(64), 160, 224, 288, 352, 448]!
  for i in 0 .. 6 {
   assert cells[i] == creation + cell_offsets[i]
   value := objects[i]
   assert value == creation + records[i]
   assert read64(value) == ios_runtime.names['NSString'] && read64(value + 8) == 0x7c8 && read64(value + 24) == u64(texts[i].len)
   assert read64(value + 16) == creation + bytes[i] && unsafe { *(&u8(creation + bytes[i] + u64(texts[i].len))) } == 0 && value in ios_runtime.constants
  }
  for symbol in ['_NSURLCreationDateKey','_kCFURLCreationDateKey','_NSURLFileSizeKey','_kCFURLFileSizeKey','_NSURLIsExcludedFromBackupKey','_kCFURLIsExcludedFromBackupKey','_NSURLIsRegularFileKey','_kCFURLIsRegularFileKey','_NSURLVolumeAvailableCapacityForImportantUsageKey','_kCFURLVolumeAvailableCapacityForImportantUsageKey','_NSURLVolumeAvailableCapacityKey','_kCFURLVolumeAvailableCapacityKey']! { assert symbol !in ios_runtime.framework_data }
 }
 pool := uac_pool(api)
 array := uac_msg(api, uac_class(api, c'NSArray'), c'arrayWithObjects:count:', u64(unsafe { &objects[0] }), 6, 0)
 assert uac_msg(api, array, c'count', 0, 0, 0) == 6
 assert uac_keep(api, array) == array
 mut equal := [6]u64{}
 for i in 0 .. 6 {
  value := objects[i]
  assert uac_msg(api, array, c'objectAtIndex:', u64(i), 0, 0) == value
  assert uac_msg(api, uac_keep(api, value), c'autorelease', 0, 0, 0) == value
  copy := uac_msg(api, value, c'copy', 0, 0, 0); assert copy == value; uac_drop(api, copy)
  equal[i] = uac_msg(api, uac_class(api, c'NSString'), c'stringWithUTF8String:', u64(texts[i].str), 0, 0)
  assert uac_msg(api, value, c'length', 0, 0, 0) == u64(texts[i].len)
  assert uac_msg(api, value, c'isEqualToString:', equal[i], 0, 0) == 1
  if api.native { assert unsafe { UACKeep(C.dlsym(voidptr(api.core), c'CFHash'))(value) } == unsafe { UACKeep(C.dlsym(voidptr(api.core), c'CFHash'))(equal[i]) } } else { assert cf_hash(value) == cf_hash(equal[i]) }
 }
 dictionary := uac_msg(api, uac_class(api, c'NSDictionary'), c'dictionaryWithObjects:forKeys:count:', u64(unsafe { &equal[0] }), u64(unsafe { &objects[0] }), 6)
 for i in 0 .. 6 { assert uac_msg(api, dictionary, c'objectForKey:', equal[i], 0, 0) == equal[i] }

 capacity_keys := [objects[4], objects[5]]!
 capacity_array := uac_msg(api, uac_class(api, c'NSArray'), c'arrayWithObjects:count:', u64(unsafe { &capacity_keys[0] }), 2, 0)
 assert uac_msg(api, capacity_array, c'count', 0, 0, 0) == 2
 assert uac_keep(api, capacity_array) == capacity_array
 capacities := [u64(5) * 1024 * 1024 * 1024 + 17, u64(7) * 1024 * 1024 * 1024 + 29]!
 values := [uac_msg(api, uac_class(api, c'NSNumber'), c'numberWithInteger:', capacities[0], 0, 0), uac_msg(api, uac_class(api, c'NSNumber'), c'numberWithInteger:', capacities[1], 0, 0)]!
 capacity_dictionary := uac_msg(api, uac_class(api, c'NSDictionary'), c'dictionaryWithObjects:forKeys:count:', u64(unsafe { &values[0] }), u64(unsafe { &capacity_keys[0] }), 2)
 for i in 0 .. 2 {
  assert uac_msg(api, capacity_array, c'objectAtIndex:', u64(i), 0, 0) == objects[4+i]
  found := uac_msg(api, capacity_dictionary, c'objectForKey:', equal[4+i], 0, 0)
  assert found == values[i] && uac_msg(api, found, c'integerValue', 0, 0, 0) == capacities[i]
 }
 assert uac_keep(api, capacity_dictionary) == capacity_dictionary
 uac_pop(api, pool)
 for i in 0 .. 6 {
  uac_text(api, read64(cells[i]), texts[i])
  assert uac_msg(api, array, c'objectAtIndex:', u64(i), 0, 0) == objects[i]
 }

 for i in 0 .. 2 {
  assert uac_msg(api, capacity_array, c'objectAtIndex:', u64(i), 0, 0) == objects[4+i]
  found := uac_msg(api, capacity_dictionary, c'objectForKey:', objects[4+i], 0, 0)
  assert found == values[i] && uac_msg(api, found, c'integerValue', 0, 0, 0) == capacities[i]
 }
 uac_drop(api, capacity_dictionary); uac_drop(api, capacity_array)
 uac_drop(api, array)
 if !api.native { assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 }
 return cell
}
__global uac_teardown_calls = 0
fn uac_teardown(object u64, selector &char) {
 assert ios_runtime.swift_concurrency_retired
 for i in 0 .. 6 {
  cell := uac_cell(UACApi{}, i, true, false)
  assert cell == uac_cell(UACApi{}, i, false, true)
  uac_text(UACApi{}, read64(cell), uac_expected(i))
  assert read64(cell) in ios_runtime.constants
 }
 uac_teardown_calls++
}
fn test_ns_url_available_capacity() {
 $if macos {
  api := UACApi{true, u64(C.dlopen(c'/System/Library/Frameworks/Foundation.framework/Foundation', 2)), u64(C.dlopen(c'/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation', 2)), u64(C.dlopen(c'/usr/lib/libobjc.A.dylib', 2))}
  assert api.foundation != 0 && api.core != 0 && api.objc != 0
  uac_shared(api)
  for handle in [api.objc, api.core, api.foundation]! { assert C.dlclose(unsafe { voidptr(handle) }) == 0 }
  println('NATIVE-NS-URL-AVAILABLE-CAPACITY: distinct available/important/regular/backup/size/creation keys with shared NS/CF alias cells, exact NSString values, eight mixed-key readers, immutable copying/hash/dictionary behavior and retained key-array lifetime')
 }
 for symbol in ['_NSURLVolumeAvailableCapacityForImportantUsageKey','_kCFURLVolumeAvailableCapacityForImportantUsageKey','_NSURLVolumeAvailableCapacityKey','_kCFURLVolumeAvailableCapacityKey']! { if _ := ns_url_resource_key_symbol(symbol) { assert false } }
 for _ in 0 .. 2 {
  objc_start(); assert ios_runtime.url_resource_keys_arena == 0
  ns_url_resource_keys_stop(); assert ios_runtime.url_resource_keys_arena == 0
  ios_runtime.swift_concurrency_retired = true
  for symbol in ['_NSURLCreationDateKey','_kCFURLCreationDateKey','_NSURLFileSizeKey','_kCFURLFileSizeKey','_NSURLIsExcludedFromBackupKey','_kCFURLIsExcludedFromBackupKey','_NSURLIsRegularFileKey','_kCFURLIsRegularFileKey','_NSURLVolumeAvailableCapacityForImportantUsageKey','_kCFURLVolumeAvailableCapacityForImportantUsageKey','_NSURLVolumeAvailableCapacityKey','_kCFURLVolumeAvailableCapacityKey']! { if _ := ns_url_resource_key_symbol(symbol) { assert false } }
  ios_runtime.swift_concurrency_retired = false
  cell := uac_shared(UACApi{}); base := uac_cell(UACApi{}, 0, false, false)
  available := read64(cell); important := read64(base + 96); regular := read64(base + 24); backup := read64(base + 16); size := read64(base + 8); creation := read64(base)
  assert ios_runtime.foundation_keys_arena == 0
  for symbol in ['_NSURLVolumeAvailableCapacityForImportantUsageKey','_kCFURLVolumeAvailableCapacityForImportantUsageKey','_NSURLVolumeAvailableCapacityKey','_kCFURLVolumeAvailableCapacityKey']! { for library in ['/System/Library/Frameworks/UIKit.framework/UIKit', '/usr/lib/libSystem.B.dylib']! { if _ := runtime_symbol(library, symbol) { assert false } } }
  for name in ['_NSURLVolumeAvailableCapacity','_kCFURLVolumeAvailableCapacity','_NSURLVolumeAvailableCapacityKeyExtra','_kCFURLVolumeAvailableCapacityKeyExtra']! { if _ := ns_url_resource_key_symbol(name) { assert false } }
  probe := objc_allocate_class(ios_runtime.names['NSObject'], c'VinixURLAvailableCapacityTeardownProbe', 0); assert probe != 0
  assert objc_add_method(probe, u64(c'dealloc'), u64(unsafe { voidptr(uac_teardown) }), c'v16@0:8')
  objc_register_class(probe); objc_autorelease(objc_new(probe))
  ios_runtime.swift_concurrency_retired = true
  offsets := [u64(0), 8, 16, 24, 96, 104]!
  for i in 0 .. 6 { assert uac_cell(UACApi{}, i, false, true) == base + offsets[i] && uac_cell(UACApi{}, i, true, false) == base + offsets[i] }
  before := uac_teardown_calls; objc_stop()
  assert uac_teardown_calls == before + 1 && ios_runtime.url_resource_keys_arena == 0 && ios_runtime.live == 0 && ios_runtime.objects.len == 0 && available !in ios_runtime.constants && important !in ios_runtime.constants && regular !in ios_runtime.constants && backup !in ios_runtime.constants && size !in ios_runtime.constants && creation !in ios_runtime.constants
  for symbol in ['_NSURLCreationDateKey','_kCFURLCreationDateKey','_NSURLFileSizeKey','_kCFURLFileSizeKey','_NSURLIsExcludedFromBackupKey','_kCFURLIsExcludedFromBackupKey','_NSURLIsRegularFileKey','_kCFURLIsRegularFileKey','_NSURLVolumeAvailableCapacityForImportantUsageKey','_kCFURLVolumeAvailableCapacityForImportantUsageKey','_NSURLVolumeAvailableCapacityKey','_kCFURLVolumeAvailableCapacityKey']! { if _ := ns_url_resource_key_symbol(symbol) { assert false } }
 }
 println('IOS-NS-URL-AVAILABLE-CAPACITY: six distinct sealed resource-key cells with exact CFStrings, eight mixed-key cold publishers, preserved five prior layouts and two gap-cell placements, immutable string/hash/dictionary behavior, retained six-key and paired-capacity NSArrays plus distinct 64-bit NSNumber dictionary values across pool drain, isolated Foundation storage, retirement guards, callback access and two drained/unmapped lifetimes')
}

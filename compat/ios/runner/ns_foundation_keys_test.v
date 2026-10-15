// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
type FKName = fn (&char) u64
type FKMessage = fn (u64, u64, u64, u64, u64) u64
type FKRetain = fn (u64) u64
type FKRelease = fn (u64)
type FKPool = fn () u64
type FKBytes = fn (u64, &char, i64, u32) bool
struct FKApi { native bool foundation u64 objc u64 core u64 }
struct FKCells { values [3]u64 }
__global foundation_keys_teardown_calls = 0
__global foundation_key_calls = 0
__global foundation_key_note = u64(0)
__global foundation_key_api = FKApi{}
fn fk_names() [3]string {
 return ['_NSUbiquityIdentityDidChangeNotification', '_NSUnderlyingErrorKey', '_NSUserActivityTypeBrowsingWeb']!
}
fn fk_texts() [3]string {
 return ['NSUbiquityIdentityDidChangeNotification', 'NSUnderlyingError', 'NSUserActivityTypeBrowsingWeb']!
}
fn fk_api(native bool) FKApi {
	$if macos { if native {
		return FKApi{true, u64(C.dlopen(c'/System/Library/Frameworks/Foundation.framework/Foundation', 2)), u64(C.dlopen(c'/usr/lib/libobjc.A.dylib', 2)), u64(C.dlopen(c'/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation', 2))}
	} }
	return FKApi{}
}
fn fk_cell(api FKApi, name string) u64 {
	if api.native { return u64(C.dlsym(voidptr(api.foundation), unsafe { &char(name.str + 1) })) }
	return runtime_symbol('/System/Library/Frameworks/Foundation.framework/Foundation', name) or { panic(err) }
}
fn fk_class(api FKApi, name &char) u64 {
	if api.native { return unsafe { FKName(C.dlsym(voidptr(api.objc), c'objc_getClass'))(name) } }
	return ios_runtime.names[ctext(u64(name))]
}
fn fk_msg(api FKApi, object u64, name &char, a u64, b u64, c u64) u64 {
	if api.native {
		selector := unsafe { FKName(C.dlsym(voidptr(api.objc), c'sel_registerName'))(name) }
		return unsafe { FKMessage(C.dlsym(voidptr(api.objc), c'objc_msgSend'))(object, selector, a, b, c) }
	}
	return unsafe { FKMessage(voidptr(C.ios_objc_builtin))(object, u64(name), a, b, c) }
}
fn fk_retain(api FKApi, value u64) u64 {
	if api.native { return unsafe { FKRetain(C.dlsym(voidptr(api.objc), c'objc_retain'))(value) } }
	return objc_retain(value)
}
fn fk_release(api FKApi, value u64) {
	if api.native { unsafe { FKRelease(C.dlsym(voidptr(api.objc), c'objc_release'))(value) }; return }
	objc_release(value)
}
fn fk_pool(api FKApi) u64 {
	if api.native { return unsafe { FKPool(C.dlsym(voidptr(api.objc), c'objc_autoreleasePoolPush'))() } }
	return objc_pool_push()
}
fn fk_pop(api FKApi, pool u64) {
	if api.native { unsafe { FKRelease(C.dlsym(voidptr(api.objc), c'objc_autoreleasePoolPop'))(pool) }; return }
	objc_pool_pop(pool)
}
fn fk_text(api FKApi, value u64, expected string) {
	assert value != 0
	if !api.native { assert string_text(value) == expected; return }
	mut buffer := [1024]u8{}
	assert unsafe { FKBytes(C.dlsym(voidptr(api.core), c'CFStringGetCString'))(value, &char(&buffer[0]), 1024, 0x08000100) }
	assert buffer[expected.len] == 0 && C.memcmp(unsafe { &buffer[0] }, expected.str, usize(expected.len)) == 0
}

type FKMessage4 = fn (u64, u64, u64, u64, u64, u64) u64
type FKAllocateClass = fn (u64, &char, usize) u64
type FKAddMethod = fn (u64, u64, u64, &char) bool
fn fk_selector(api FKApi, name &char) u64 {
 if api.native { return unsafe { FKName(C.dlsym(voidptr(api.objc), c'sel_registerName'))(name) } }
 return u64(name)
}
fn fk_msg4(api FKApi, object u64, name &char, a u64, b u64, c u64, d u64) u64 {
 if api.native { return unsafe { FKMessage4(C.dlsym(voidptr(api.objc), c'objc_msgSend'))(object, fk_selector(api, name), a, b, c, d) } }
 return unsafe { FKMessage4(voidptr(C.ios_objc_builtin))(object, u64(name), a, b, c, d) }
}
fn fk_reader(api FKApi, offset int) FKCells {
 mut cells := [3]u64{}; names := fk_names(); texts := fk_texts()
 for turn in 0 .. 32 {
  pool := fk_pool(api)
  for step in 0 .. 3 {
   index := (offset + step) % 3; cell := fk_cell(api, names[index]); assert cell != 0 && cell % 8 == 0
   if turn == 0 { cells[index] = cell } else { assert cells[index] == cell }
   value := read64(cell); fk_text(api, value, texts[index])
   assert fk_retain(api, value) == value; fk_release(api, value)
   assert fk_msg(api, fk_retain(api, value), c'autorelease', 0, 0, 0) == value
  }
  fk_pop(api, pool)
 }
 return FKCells{cells}
}
fn fk_shared(api FKApi) {
 mut workers := []thread FKCells{}
 for offset in 0 .. 8 { workers << spawn fk_reader(api, offset % 3) }
 mut cells := [3]u64{}
 for i, worker in workers { got := worker.wait().values; if i == 0 { cells = got } else { assert cells == got } }
 unsafe { workers.free() }
 for i in 0 .. 3 { for j in 0 .. i { assert cells[i] != cells[j] && read64(cells[i]) != read64(cells[j]) } }
 if !api.native { assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 }
 pool := fk_pool(api)
 domain := fk_msg(api, fk_class(api, c'NSString'), c'stringWithUTF8String:', u64(c'VinixUnderlying'), 0, 0)
 inner := fk_msg(api, fk_class(api, c'NSError'), c'errorWithDomain:code:userInfo:', domain, 13, 0)
 keys := [read64(cells[1])]!; values := [inner]!
 info := fk_msg(api, fk_class(api, c'NSDictionary'), c'dictionaryWithObjects:forKeys:count:', u64(unsafe { &values[0] }), u64(unsafe { &keys[0] }), 1)
 outer := fk_msg(api, fk_class(api, c'NSError'), c'errorWithDomain:code:userInfo:', domain, u64(i64(-1)), info)
 assert outer != 0 && fk_retain(api, outer) == outer
 fk_pop(api, pool)
 check_pool := fk_pool(api)
 retained_info := fk_msg(api, outer, c'userInfo', 0, 0, 0)
 equal := fk_msg(api, fk_class(api, c'NSString'), c'stringWithUTF8String:', u64(c'NSUnderlyingError'), 0, 0)
 for query in [read64(cells[1]), equal]! {
  got := fk_msg(api, retained_info, c'objectForKey:', query, 0, 0)
  assert got == inner && fk_msg(api, got, c'code', 0, 0, 0) == 13
  fk_text(api, fk_msg(api, got, c'domain', 0, 0, 0), 'VinixUnderlying')
 }
 fk_release(api, outer); fk_pop(api, check_pool)
 for i, cell in cells { fk_text(api, read64(cell), fk_texts()[i]) }
 if !api.native { assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 }
}
fn fk_note_received(object u64, selector &char, notification u64) {
 api := foundation_key_api
 fk_text(api, fk_msg(api, notification, c'name', 0, 0, 0), 'NSUbiquityIdentityDidChangeNotification')
 assert foundation_key_note == 0
 foundation_key_note = fk_retain(api, notification)
 foundation_key_calls++
}
fn fk_notification(api FKApi) {
 foundation_key_api = api; assert foundation_key_note == 0
 pool := fk_pool(api); before := foundation_key_calls
 parent := fk_class(api, c'NSObject')
 observer_class := if api.native { unsafe { FKAllocateClass(C.dlsym(voidptr(api.objc), c'objc_allocateClassPair'))(parent, c'VinixFoundationKeyObserver', 0) } } else { objc_allocate_class(parent, c'VinixFoundationKeyObserver', 0) }
 assert observer_class != 0
 action := fk_selector(api, c'vinixFoundationKeyNotification:')
 implementation := u64(unsafe { voidptr(fk_note_received) })
 if api.native {
  assert unsafe { FKAddMethod(C.dlsym(voidptr(api.objc), c'class_addMethod'))(observer_class, action, implementation, c'v24@0:8@16') }
  unsafe { FKRelease(C.dlsym(voidptr(api.objc), c'objc_registerClassPair'))(observer_class) }
 } else { assert objc_add_method(observer_class, action, implementation, c'v24@0:8@16'); objc_register_class(observer_class) }
 observer := fk_msg(api, observer_class, c'new', 0, 0, 0)
 filter := fk_msg(api, parent, c'new', 0, 0, 0)
 center := fk_msg(api, fk_class(api, c'NSNotificationCenter'), c'defaultCenter', 0, 0, 0)
 name := read64(fk_cell(api, fk_names()[0]))
 equal_name := fk_msg(api, fk_class(api, c'NSString'), c'stringWithUTF8String:', u64(c'NSUbiquityIdentityDidChangeNotification'), 0, 0)
 assert observer != 0 && filter != 0 && center != 0
 fk_msg4(api, center, c'addObserver:selector:name:object:', observer, action, name, filter)
 fk_msg(api, center, c'postNotificationName:object:userInfo:', equal_name, 0, 0)
 assert foundation_key_calls == before && foundation_key_note == 0
 keys := [read64(fk_cell(api, fk_names()[2]))]!
 values := [fk_msg(api, fk_class(api, c'NSString'), c'stringWithUTF8String:', u64(c'https://example.invalid/fortnite'), 0, 0)]!
 info := fk_msg(api, fk_class(api, c'NSDictionary'), c'dictionaryWithObjects:forKeys:count:', u64(unsafe { &values[0] }), u64(unsafe { &keys[0] }), 1)
 fk_msg(api, center, c'postNotificationName:object:userInfo:', equal_name, filter, info)
 assert foundation_key_calls == before + 1 && foundation_key_note != 0
 fk_msg(api, center, c'removeObserver:name:object:', observer, equal_name, filter)
 fk_msg(api, center, c'postNotificationName:object:userInfo:', name, filter, info)
 assert foundation_key_calls == before + 1
 // Leave a zeroing-weak registration for runtime notification shutdown to
 // remove while its immortal name is still registered and readable.
 fk_msg4(api, center, c'addObserver:selector:name:object:', observer, action, name, filter)
 fk_release(api, observer); fk_release(api, filter); fk_pop(api, pool)
 check_pool := fk_pool(api)
 note := foundation_key_note
 assert fk_msg(api, note, c'object', 0, 0, 0) == filter
 retained_info := fk_msg(api, note, c'userInfo', 0, 0, 0)
 equal_key := fk_msg(api, fk_class(api, c'NSString'), c'stringWithUTF8String:', u64(c'NSUserActivityTypeBrowsingWeb'), 0, 0)
 for query in [keys[0], equal_key]! { fk_text(api, fk_msg(api, retained_info, c'objectForKey:', query, 0, 0), 'https://example.invalid/fortnite') }
 fk_release(api, note); foundation_key_note = 0; fk_pop(api, check_pool)
 if !api.native { assert ios_runtime.live == 1 && ios_runtime.observers.len == 1 }
}
fn fk_teardown(object u64, selector &char) {
 assert ios_runtime.swift_concurrency_retired
 for i, name in fk_names() { cell := ns_foundation_key_symbol(name) or { panic('Foundation key retired before pool callback') }; assert string_text(read64(cell)) == fk_texts()[i] }
 foundation_keys_teardown_calls++
}
fn test_ns_foundation_keys() {
 $if macos {
  api := fk_api(true); fk_shared(api); fk_notification(api)
  println('IOS-FOUNDATION-KEYS-NATIVE: three NSString cells and exact values, nested NSError ownership, equal-name notifications with object filters/removal, web-activity dictionary lookup, pool lifetimes and eight concurrent readers')
 }
 if _ := ns_foundation_key_symbol('_NSUnderlyingErrorKey') { assert false }
 for _ in 0 .. 2 {
  objc_start(); assert ios_runtime.foundation_keys_arena == 0
  ios_runtime.swift_concurrency_retired = true
  if _ := ns_foundation_key_symbol('_NSUnderlyingErrorKey') { assert false }
  ios_runtime.swift_concurrency_retired = false
  fk_shared(FKApi{}); fk_notification(FKApi{})
  for symbol in fk_names() { for library in ['/System/Library/Frameworks/UIKit.framework/UIKit', '/usr/lib/libSystem.B.dylib']! { if _ := runtime_symbol(library, symbol) { assert false } } }
  if _ := ns_foundation_key_symbol('_NSUbiquityInventedNotification') { assert false }
  probe := objc_allocate_class(ios_runtime.names['NSObject'], c'VinixFoundationKeyTeardownProbe', 0); assert probe != 0
  assert objc_add_method(probe, u64(c'dealloc'), u64(unsafe { voidptr(fk_teardown) }), c'v16@0:8')
  objc_register_class(probe); objc_autorelease(objc_new(probe))
  ios_runtime.swift_concurrency_retired = true
  before := foundation_keys_teardown_calls; objc_stop()
  assert foundation_keys_teardown_calls == before + 1 && ios_runtime.foundation_keys_arena == 0 && ios_runtime.live == 0 && ios_runtime.objects.len == 0 && ios_runtime.observers.len == 0
  if _ := ns_foundation_key_symbol('_NSUnderlyingErrorKey') { assert false }
 }
 println('IOS-FOUNDATION-KEYS: stable sealed pointer globals, exact underlying-error spelling, nested NSError and notification ownership, equal-name filtering/removal, contended first publication, teardown availability and two drained/unmapped lifetimes')
}

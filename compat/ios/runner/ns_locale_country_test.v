// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.dlclose(voidptr) i32

type CountryName = fn (&char) u64
type CountryMessage = fn (u64, u64, u64, u64, u64) u64
type CountryKeep = fn (u64) u64
type CountryDrop = fn (u64)
type CountryPool = fn () u64
type CountryGet = fn (u64, u64) u64
type CountryBytes = fn (u64, &char, i64, u32) bool
struct CountryApi { native bool foundation u64 core u64 objc u64 }
__global country_teardown_calls = 0

fn country_cell(api CountryApi, core bool, cf bool) u64 {
 name := if cf { '_kCFLocaleCountryCode' } else { '_NSLocaleCountryCode' }
 if api.native { return u64(C.dlsym(unsafe { voidptr(if core { api.core } else { api.foundation }) }, unsafe { &char(name.str + 1) })) }
 library := if core { '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation' } else { '/System/Library/Frameworks/Foundation.framework/Foundation' }
 return runtime_symbol(library, name) or { panic(err) }
}
fn country_msg(api CountryApi, object u64, name &char, a u64, b u64, c u64) u64 {
 if api.native {
  selector := unsafe { CountryName(C.dlsym(voidptr(api.objc), c'sel_registerName'))(name) }
  return unsafe { CountryMessage(C.dlsym(voidptr(api.objc), c'objc_msgSend'))(object, selector, a, b, c) }
 }
 return unsafe { CountryMessage(voidptr(C.ios_objc_builtin))(object, u64(name), a, b, c) }
}
fn country_class(api CountryApi, name &char) u64 {
 if api.native { return unsafe { CountryName(C.dlsym(voidptr(api.objc), c'objc_getClass'))(name) } }
 return ios_runtime.names[ctext(u64(name))]
}
fn country_pool(api CountryApi) u64 {
 if api.native { return unsafe { CountryPool(C.dlsym(voidptr(api.objc), c'objc_autoreleasePoolPush'))() } }
 return objc_pool_push()
}
fn country_pop(api CountryApi, pool u64) {
 if api.native { unsafe { CountryDrop(C.dlsym(voidptr(api.objc), c'objc_autoreleasePoolPop'))(pool) }; return }
 objc_pool_pop(pool)
}
fn country_keep(api CountryApi, object u64) u64 {
 if api.native { return unsafe { CountryKeep(C.dlsym(voidptr(api.core), c'CFRetain'))(object) } }
 return objc_retain(object)
}
fn country_drop(api CountryApi, object u64) {
 if api.native { unsafe { CountryDrop(C.dlsym(voidptr(api.core), c'CFRelease'))(object) }; return }
 objc_release(object)
}
fn country_text(api CountryApi, object u64, expected string) {
 assert object != 0
 if !api.native { assert string_text(object) == expected && cf_type_id(object) == cf_string_id(); return }
 mut bytes := [128]u8{}
 assert unsafe { CountryBytes(C.dlsym(voidptr(api.core), c'CFStringGetCString'))(object, &char(&bytes[0]), 128, 0x08000100) }
 assert bytes[expected.len] == 0 && C.memcmp(unsafe { &bytes[0] }, expected.str, usize(expected.len)) == 0
}
fn country_reader(api CountryApi, offset int) u64 {
 mut cell := u64(0)
 for turn in 0 .. 64 {
  for step in 0 .. 4 {
   index := (offset + step + turn) % 4
   got := country_cell(api, index % 2 == 0, index / 2 == 0)
   assert got != 0 && got % 8 == 0
   if cell == 0 { cell = got } else { assert got == cell }
   value := read64(got); assert value != got
   country_text(api, value, 'kCFLocaleCountryCodeKey')
   assert country_keep(api, value) == value; country_drop(api, value)
  }
 }
 return cell
}
fn country_shared(api CountryApi) u64 {
 mut workers := []thread u64{}
 for offset in 0 .. 8 { workers << spawn country_reader(api, offset) }
 mut cell := u64(0)
 for i, worker in workers { got := worker.wait(); if i == 0 { cell = got } else { assert cell == got } }
 unsafe { workers.free() }
 value := read64(cell)
 if !api.native {
  assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 && ios_runtime.framework_objects.len == 0
  assert cell == ios_runtime.ns_locale_country_arena && value == cell + 32
  assert read64(value) == ios_runtime.names['NSString'] && read64(value + 8) == 0x7c8 && read64(value + 24) == 23
  assert read64(value + 16) == cell + 64 && unsafe { *(&u8(cell + 87)) } == 0 && value in ios_runtime.constants
  assert '_NSLocaleCountryCode' !in ios_runtime.framework_data && '_kCFLocaleCountryCode' !in ios_runtime.framework_data
 }
 pool := country_pool(api)
 assert country_msg(api, country_keep(api, value), c'autorelease', 0, 0, 0) == value
 copy := country_msg(api, value, c'copy', 0, 0, 0); assert copy == value; country_drop(api, copy)
 equal := country_msg(api, country_class(api, c'NSString'), c'stringWithUTF8String:', u64(c'kCFLocaleCountryCodeKey'), 0, 0)
 assert country_msg(api, value, c'length', 0, 0, 0) == 23
 assert country_msg(api, value, c'isEqualToString:', equal, 0, 0) == 1
 keys := [value]!; values := [equal]!
 dictionary := country_msg(api, country_class(api, c'NSDictionary'), c'dictionaryWithObjects:forKeys:count:', u64(unsafe { &values[0] }), u64(unsafe { &keys[0] }), 1)
 assert country_msg(api, dictionary, c'objectForKey:', equal, 0, 0) == equal
 country_pop(api, pool); country_text(api, read64(cell), 'kCFLocaleCountryCodeKey')
 if !api.native { assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 }
 return cell
}
fn country_locale(api CountryApi, identifier string) u64 {
 if api.native { $if macos {
  name := C.CFStringCreateWithCString(unsafe { nil }, unsafe { &char(identifier.str) }, 0x08000100)
  locale := C.CFLocaleCreate(unsafe { nil }, name); assert locale != unsafe { nil }; C.CFRelease(name)
  return u64(locale)
 } }
 locale := objc_allocate(ios_runtime.names['NSLocale'])
 name := owned_string(identifier); store_field(locale, 0, name); objc_release(name)
 return locale
}
fn country_get(api CountryApi, locale u64, key u64, cf bool) u64 {
 if cf {
  if api.native { return unsafe { CountryGet(C.dlsym(voidptr(api.core), c'CFLocaleGetValue'))(locale, key) } }
  return cf_locale_get_value(locale, key)
 }
 return country_msg(api, locale, c'objectForKey:', key, 0, 0)
}
fn country_cases(api CountryApi, cell u64) {
 key := read64(cell)
 for pair in [['en_US','US']!, ['fr_FR','FR']!, ['ru_RU','RU']!, ['es_419','419']!,
  ['zh-Hant-TW','TW']!, ['sr_Latn_RS','RS']!, ['iw_IL','IL']!, ['en_US_POSIX','US']!,
  ['en','']!, ['','']!, ['en__POSIX','']!]! {
  pool := country_pool(api); locale := country_locale(api, pair[0])
  first := country_get(api, locale, key, false)
  if pair[1] == '' { assert first == 0 } else { country_text(api, first, pair[1]) }
  equal := country_msg(api, country_class(api, c'NSString'), c'stringWithUTF8String:', u64(c'kCFLocaleCountryCodeKey'), 0, 0)
  before := if api.native { 0 } else { ios_runtime.live }
  for _ in 0 .. 32 { for candidate in [key, read64(country_cell(api, true, true)), equal]! {
   assert country_get(api, locale, candidate, false) == first && country_get(api, locale, candidate, true) == first
  } }
  if !api.native { assert ios_runtime.live == before && obj_header(locale).valid }
  if first != 0 { assert country_keep(api, first) == first }
  country_pop(api, pool); country_drop(api, locale)
  if first != 0 { country_text(api, first, pair[1]); country_drop(api, first) }
  if !api.native { assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 }
 }
 // Match the application's currentLocale -> objectForKey: country-key path.
 pool := country_pool(api)
 current := country_msg(api, country_class(api, c'NSLocale'), c'currentLocale', 0, 0, 0)
 assert current != 0
 assert country_get(api, current, key, false) == country_get(api, current, key, true)
 country_pop(api, pool)
}
fn country_teardown(object u64, selector &char) {
 assert ios_runtime.swift_concurrency_retired
 cell := country_cell(CountryApi{}, true, false)
 assert cell == country_cell(CountryApi{}, false, true)
 country_text(CountryApi{}, read64(cell), 'kCFLocaleCountryCodeKey')
 assert read64(cell) in ios_runtime.constants
 country_teardown_calls++
}
fn test_ns_locale_country() {
 $if macos {
  api := CountryApi{true, u64(C.dlopen(c'/System/Library/Frameworks/Foundation.framework/Foundation', 2)), u64(C.dlopen(c'/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation', 2)), u64(C.dlopen(c'/usr/lib/libobjc.A.dylib', 2))}
  assert api.foundation != 0 && api.core != 0 && api.objc != 0
  cell := country_shared(api); country_cases(api, cell)
  for handle in [api.objc, api.core, api.foundation]! { assert C.dlclose(unsafe { voidptr(handle) }) == 0 }
  println('NATIVE-NS-LOCALE-COUNTRY: identical NS/CF cells and exact key value, eight mixed-alias readers, immutable string/dictionary behavior, currentLocale objectForKey, alpha/numeric/script/absent countries and retained-result lifetime')
 }
 if _ := ns_locale_country_symbol('_NSLocaleCountryCode') { assert false }
 for _ in 0 .. 2 {
  objc_start(); assert ios_runtime.ns_locale_country_arena == 0
  ios_runtime.swift_concurrency_retired = true
  if _ := ns_locale_country_symbol('_NSLocaleCountryCode') { assert false }
  ios_runtime.swift_concurrency_retired = false
  cell := country_shared(CountryApi{}); value := read64(cell); country_cases(CountryApi{}, cell)
  for symbol in ['_NSLocaleCountryCode','_kCFLocaleCountryCode']! { for library in ['/System/Library/Frameworks/UIKit.framework/UIKit', '/usr/lib/libSystem.B.dylib']! { if _ := runtime_symbol(library, symbol) { assert false } } }
  for name in ['_NSLocaleCountryCodeKey','_kCFLocaleCountryCodeKey','_NSLocaleLanguageCode']! { if _ := ns_locale_country_symbol(name) { assert false } }
  probe := objc_allocate_class(ios_runtime.names['NSObject'], c'VinixLocaleCountryTeardownProbe', 0); assert probe != 0
  assert objc_add_method(probe, u64(c'dealloc'), u64(unsafe { voidptr(country_teardown) }), c'v16@0:8')
  objc_register_class(probe); objc_autorelease(objc_new(probe))
  ios_runtime.swift_concurrency_retired = true; assert country_cell(CountryApi{}, false, true) == cell
  before := country_teardown_calls; objc_stop()
  assert country_teardown_calls == before + 1 && ios_runtime.ns_locale_country_arena == 0 && ios_runtime.live == 0 && ios_runtime.objects.len == 0 && value !in ios_runtime.constants
  if _ := ns_locale_country_symbol('_NSLocaleCountryCode') { assert false }
 }
 println('IOS-NS-LOCALE-COUNTRY: shared sealed NS/CF pointer cell with exact country-key CFString, eight mixed-alias cold publishers, locale matrix/currentLocale objectForKey/CFLocaleGetValue equivalence, absent-country caching and retained results, retirement guards, callback access and two drained/unmapped lifetimes')
}

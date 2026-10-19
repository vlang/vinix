// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.dlclose(voidptr) i32

type CurrencyName = fn (&char) u64
type CurrencyMessage = fn (u64, u64, u64, u64, u64) u64
type CurrencyKeep = fn (u64) u64
type CurrencyDrop = fn (u64)
type CurrencyPool = fn () u64
type CurrencyBytes = fn (u64, &char, i64, u32) bool
struct CurrencyApi { native bool foundation u64 core u64 objc u64 }
struct CurrencyCells { values [2]u64 }
__global currency_teardown_calls = 0

fn currency_cell(api CurrencyApi, core bool, cf bool, country bool) u64 {
 name := if country { if cf { '_kCFLocaleCountryCode' } else { '_NSLocaleCountryCode' } } else { if cf { '_kCFLocaleCurrencyCode' } else { '_NSLocaleCurrencyCode' } }
 if api.native { return u64(C.dlsym(unsafe { voidptr(if core { api.core } else { api.foundation }) }, unsafe { &char(name.str + 1) })) }
 library := if core { '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation' } else { '/System/Library/Frameworks/Foundation.framework/Foundation' }
 return runtime_symbol(library, name) or { panic(err) }
}
fn currency_msg(api CurrencyApi, object u64, name &char, a u64, b u64, c u64) u64 {
 if api.native {
  selector := unsafe { CurrencyName(C.dlsym(voidptr(api.objc), c'sel_registerName'))(name) }
  return unsafe { CurrencyMessage(C.dlsym(voidptr(api.objc), c'objc_msgSend'))(object, selector, a, b, c) }
 }
 return unsafe { CurrencyMessage(voidptr(C.ios_objc_builtin))(object, u64(name), a, b, c) }
}
fn currency_class(api CurrencyApi, name &char) u64 {
 if api.native { return unsafe { CurrencyName(C.dlsym(voidptr(api.objc), c'objc_getClass'))(name) } }
 return ios_runtime.names[ctext(u64(name))]
}
fn currency_pool(api CurrencyApi) u64 {
 if api.native { return unsafe { CurrencyPool(C.dlsym(voidptr(api.objc), c'objc_autoreleasePoolPush'))() } }
 return objc_pool_push()
}
fn currency_pop(api CurrencyApi, pool u64) {
 if api.native { unsafe { CurrencyDrop(C.dlsym(voidptr(api.objc), c'objc_autoreleasePoolPop'))(pool) }; return }
 objc_pool_pop(pool)
}
fn currency_keep(api CurrencyApi, object u64) u64 {
 if api.native { return unsafe { CurrencyKeep(C.dlsym(voidptr(api.core), c'CFRetain'))(object) } }
 return objc_retain(object)
}
fn currency_drop(api CurrencyApi, object u64) {
 if api.native { unsafe { CurrencyDrop(C.dlsym(voidptr(api.core), c'CFRelease'))(object) }; return }
 objc_release(object)
}
fn currency_hash(api CurrencyApi, object u64) u64 {
 if api.native { return unsafe { CurrencyKeep(C.dlsym(voidptr(api.core), c'CFHash'))(object) } }
 return cf_hash(object)
}
fn currency_text(api CurrencyApi, object u64, country bool) {
 expected := if country { 'kCFLocaleCountryCodeKey' } else { 'currency' }
 assert object != 0
 if !api.native { assert string_text(object) == expected && cf_type_id(object) == cf_string_id(); return }
 mut bytes := [128]u8{}
 assert unsafe { CurrencyBytes(C.dlsym(voidptr(api.core), c'CFStringGetCString'))(object, &char(&bytes[0]), 128, 0x08000100) }
 assert bytes[expected.len] == 0 && C.memcmp(unsafe { &bytes[0] }, expected.str, usize(expected.len)) == 0
}
fn currency_reader(api CurrencyApi, offset int) CurrencyCells {
 mut cells := [2]u64{}
 for turn in 0 .. 64 { for step in 0 .. 8 {
  index := (offset + step + turn) % 8; kind := index / 4
  got := currency_cell(api, index % 2 == 0, index / 2 % 2 == 0, kind == 0)
  assert got != 0 && got % 8 == 0
  if cells[kind] == 0 { cells[kind] = got } else { assert got == cells[kind] }
  value := read64(got); assert value != got; currency_text(api, value, kind == 0)
  assert currency_keep(api, value) == value; currency_drop(api, value)
 } }
 return CurrencyCells{cells}
}
fn currency_shared(api CurrencyApi) u64 {
 mut workers := []thread CurrencyCells{}
 for offset in 0 .. 8 { workers << spawn currency_reader(api, offset) }
 mut cells := [2]u64{}
 for i, worker in workers { got := worker.wait().values; if i == 0 { cells = got } else { assert cells == got } }
 unsafe { workers.free() }
 country := cells[0]; cell := cells[1]; value := read64(cell)
 assert cell != country && value != read64(country)
 if !api.native {
  assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 && ios_runtime.framework_objects.len == 0
  arena := ios_runtime.ns_locale_country_arena
  assert cell == arena + 8 && value == arena + 128
  assert read64(value) == ios_runtime.names['NSString'] && read64(value + 8) == 0x7c8 && read64(value + 24) == 8
  assert read64(value + 16) == arena + 160 && unsafe { *(&u8(arena + 168)) } == 0 && value in ios_runtime.constants
  assert country == arena && read64(country) == arena + 32 && read64(read64(country) + 16) == arena + 64
  assert read64(country) in ios_runtime.constants
  assert '_NSLocaleCurrencyCode' !in ios_runtime.framework_data && '_kCFLocaleCurrencyCode' !in ios_runtime.framework_data
 }
 pool := currency_pool(api)
 assert currency_msg(api, currency_keep(api, value), c'autorelease', 0, 0, 0) == value
 copy := currency_msg(api, value, c'copy', 0, 0, 0); assert copy == value; currency_drop(api, copy)
 equal := currency_msg(api, currency_class(api, c'NSString'), c'stringWithUTF8String:', u64(c'currency'), 0, 0)
 assert currency_msg(api, value, c'length', 0, 0, 0) == 8 && currency_msg(api, value, c'isEqualToString:', equal, 0, 0) == 1
 assert currency_hash(api, value) == currency_hash(api, equal)
 keys := [value]!; values := [equal]!
 dictionary := currency_msg(api, currency_class(api, c'NSDictionary'), c'dictionaryWithObjects:forKeys:count:', u64(unsafe { &values[0] }), u64(unsafe { &keys[0] }), 1)
 assert currency_msg(api, dictionary, c'objectForKey:', equal, 0, 0) == equal
 currency_pop(api, pool); currency_text(api, read64(cell), false); currency_text(api, read64(country), true)
 if !api.native { assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 }
 return cell
}
fn currency_query_boundary(cell u64) {
 locale := objc_allocate(ios_runtime.names['NSLocale'])
 name := owned_string('en_US'); store_field(locale, 0, name); objc_release(name)
 equal := owned_string('currency'); before := ios_runtime.live
 for _ in 0 .. 32 { for key in [read64(cell), read64(currency_cell(CurrencyApi{}, true, true, false)), equal]! {
  if _ := cf_locale_value_checked(locale, key) { assert false } else { assert err.msg() == 'iOS: unsupported locale value query' }
 } }
 assert ios_runtime.live == before && !obj_header(locale).valid
 country := cf_locale_get_value(locale, read64(cell - 8)); assert string_text(country) == 'US'
 after_country := ios_runtime.live
 if _ := cf_locale_value_checked(locale, read64(cell)) { assert false }
 assert ios_runtime.live == after_country && cf_locale_get_value(locale, read64(cell - 8)) == country
 objc_release(equal); objc_release(locale); assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
}
fn currency_teardown(object u64, selector &char) {
 assert ios_runtime.swift_concurrency_retired
 cell := currency_cell(CurrencyApi{}, true, false, false)
 assert cell == currency_cell(CurrencyApi{}, false, true, false)
 currency_text(CurrencyApi{}, read64(cell), false); currency_text(CurrencyApi{}, read64(cell - 8), true)
 assert read64(cell) in ios_runtime.constants && read64(cell - 8) in ios_runtime.constants
 currency_teardown_calls++
}
fn test_ns_locale_currency() {
 $if macos {
  api := CurrencyApi{true, u64(C.dlopen(c'/System/Library/Frameworks/Foundation.framework/Foundation', 2)), u64(C.dlopen(c'/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation', 2)), u64(C.dlopen(c'/usr/lib/libobjc.A.dylib', 2))}
  assert api.foundation != 0 && api.core != 0 && api.objc != 0
  currency_shared(api)
  for handle in [api.objc, api.core, api.foundation]! { assert C.dlclose(unsafe { voidptr(handle) }) == 0 }
  println('NATIVE-NS-LOCALE-CURRENCY: identical NS/CF currency-key cells and exact value, distinct country key, eight mixed-key/alias readers, immutable string/hash/dictionary behavior and immortal ownership')
 }
 if _ := ns_locale_currency_symbol('_NSLocaleCurrencyCode') { assert false }
 for _ in 0 .. 2 {
  objc_start(); assert ios_runtime.ns_locale_country_arena == 0
  ns_locale_country_stop(); assert ios_runtime.ns_locale_country_arena == 0
  ios_runtime.swift_concurrency_retired = true
  if _ := ns_locale_currency_symbol('_NSLocaleCurrencyCode') { assert false }
  ios_runtime.swift_concurrency_retired = false
  cell := currency_shared(CurrencyApi{}); value := read64(cell); country := read64(cell - 8); currency_query_boundary(cell)
  for symbol in ['_NSLocaleCurrencyCode','_kCFLocaleCurrencyCode']! { for library in ['/System/Library/Frameworks/UIKit.framework/UIKit', '/usr/lib/libSystem.B.dylib']! { if _ := runtime_symbol(library, symbol) { assert false } } }
  for name in ['_NSLocaleCurrencyCodeKey','_kCFLocaleCurrencyCodeKey','_NSLocaleCurrencySymbol']! { if _ := ns_locale_currency_symbol(name) { assert false } }
  probe := objc_allocate_class(ios_runtime.names['NSObject'], c'VinixLocaleCurrencyTeardownProbe', 0); assert probe != 0
  assert objc_add_method(probe, u64(c'dealloc'), u64(unsafe { voidptr(currency_teardown) }), c'v16@0:8')
  objc_register_class(probe); objc_autorelease(objc_new(probe))
  ios_runtime.swift_concurrency_retired = true; assert currency_cell(CurrencyApi{}, false, true, false) == cell
  before := currency_teardown_calls; objc_stop()
  assert currency_teardown_calls == before + 1 && ios_runtime.ns_locale_country_arena == 0 && ios_runtime.live == 0 && ios_runtime.objects.len == 0
  assert value !in ios_runtime.constants && country !in ios_runtime.constants
  if _ := ns_locale_currency_symbol('_NSLocaleCurrencyCode') { assert false }
 }
 println('IOS-NS-LOCALE-CURRENCY: shared sealed NS/CF currency-key cell with exact CFString, eight mixed-key/alias cold publishers, preserved country layout and queries, immutable string/dictionary behavior, explicit unsupported currency queries, retirement guards, both-key callback access and two drained/unmapped lifetimes')
}

// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.dlclose(voidptr) i32

type CurrencySymbolName = fn (&char) u64
type CurrencySymbolMessage = fn (u64, u64, u64, u64, u64) u64
type CurrencySymbolKeep = fn (u64) u64
type CurrencySymbolDrop = fn (u64)
type CurrencySymbolPool = fn () u64
type CurrencySymbolBytes = fn (u64, &char, i64, u32) bool
struct CurrencySymbolApi { native bool foundation u64 core u64 objc u64 }
struct CurrencySymbolCells { values [3]u64 }
__global csym_teardown_calls = 0

fn csym_cell(api CurrencySymbolApi, core bool, cf bool, kind int) u64 {
 names := ['_NSLocaleCountryCode', '_kCFLocaleCountryCode', '_NSLocaleCurrencyCode', '_kCFLocaleCurrencyCode', '_NSLocaleCurrencySymbol', '_kCFLocaleCurrencySymbol']!
 name := names[kind * 2 + if cf { 1 } else { 0 }]
 if api.native { return u64(C.dlsym(unsafe { voidptr(if core { api.core } else { api.foundation }) }, unsafe { &char(name.str + 1) })) }
 library := if core { '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation' } else { '/System/Library/Frameworks/Foundation.framework/Foundation' }
 return runtime_symbol(library, name) or { panic(err) }
}
fn csym_msg(api CurrencySymbolApi, object u64, name &char, a u64, b u64, c u64) u64 {
 if api.native {
  selector := unsafe { CurrencySymbolName(C.dlsym(voidptr(api.objc), c'sel_registerName'))(name) }
  return unsafe { CurrencySymbolMessage(C.dlsym(voidptr(api.objc), c'objc_msgSend'))(object, selector, a, b, c) }
 }
 return unsafe { CurrencySymbolMessage(voidptr(C.ios_objc_builtin))(object, u64(name), a, b, c) }
}
fn csym_class(api CurrencySymbolApi, name &char) u64 {
 if api.native { return unsafe { CurrencySymbolName(C.dlsym(voidptr(api.objc), c'objc_getClass'))(name) } }
 return ios_runtime.names[ctext(u64(name))]
}
fn csym_pool(api CurrencySymbolApi) u64 {
 if api.native { return unsafe { CurrencySymbolPool(C.dlsym(voidptr(api.objc), c'objc_autoreleasePoolPush'))() } }
 return objc_pool_push()
}
fn csym_pop(api CurrencySymbolApi, pool u64) {
 if api.native { unsafe { CurrencySymbolDrop(C.dlsym(voidptr(api.objc), c'objc_autoreleasePoolPop'))(pool) }; return }
 objc_pool_pop(pool)
}
fn csym_keep(api CurrencySymbolApi, object u64) u64 {
 if api.native { return unsafe { CurrencySymbolKeep(C.dlsym(voidptr(api.core), c'CFRetain'))(object) } }
 return objc_retain(object)
}
fn csym_drop(api CurrencySymbolApi, object u64) {
 if api.native { unsafe { CurrencySymbolDrop(C.dlsym(voidptr(api.core), c'CFRelease'))(object) }; return }
 objc_release(object)
}
fn csym_hash(api CurrencySymbolApi, object u64) u64 {
 if api.native { return unsafe { CurrencySymbolKeep(C.dlsym(voidptr(api.core), c'CFHash'))(object) } }
 return cf_hash(object)
}
fn csym_text(api CurrencySymbolApi, object u64, kind int) {
 texts := ['kCFLocaleCountryCodeKey', 'currency', 'kCFLocaleCurrencySymbolKey']!
 expected := texts[kind]
 assert object != 0
 if !api.native { assert string_text(object) == expected && cf_type_id(object) == cf_string_id(); return }
 mut bytes := [128]u8{}
 assert unsafe { CurrencySymbolBytes(C.dlsym(voidptr(api.core), c'CFStringGetCString'))(object, &char(&bytes[0]), 128, 0x08000100) }
 assert bytes[expected.len] == 0 && C.memcmp(unsafe { &bytes[0] }, expected.str, usize(expected.len)) == 0
}
fn csym_reader(api CurrencySymbolApi, offset int) CurrencySymbolCells {
 mut cells := [3]u64{}
 for turn in 0 .. 64 { for step in 0 .. 12 {
  index := (offset + step + turn) % 12; kind := index / 4
  got := csym_cell(api, index % 2 == 0, index / 2 % 2 == 0, kind)
  assert got != 0 && got % 8 == 0
  if cells[kind] == 0 { cells[kind] = got } else { assert got == cells[kind] }
  value := read64(got); assert value != got; csym_text(api, value, kind)
  assert csym_keep(api, value) == value; csym_drop(api, value)
 } }
 return CurrencySymbolCells{cells}
}
fn csym_shared(api CurrencySymbolApi) u64 {
 mut workers := []thread CurrencySymbolCells{}
 for offset in 0 .. 8 { workers << spawn csym_reader(api, offset + 8) }
 mut cells := [3]u64{}
 for i, worker in workers { got := worker.wait().values; if i == 0 { cells = got } else { assert cells == got } }
 unsafe { workers.free() }
 country := cells[0]; code := cells[1]; cell := cells[2]; value := read64(cell)
 assert cell != country && cell != code && code != country && value != read64(country) && value != read64(code) && read64(code) != read64(country)
 if !api.native {
  assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 && ios_runtime.framework_objects.len == 0
  arena := ios_runtime.ns_locale_country_arena
  assert cell == arena + 16 && value == arena + 192
  assert read64(value) == ios_runtime.names['NSString'] && read64(value + 8) == 0x7c8 && read64(value + 24) == 26
  assert read64(value + 16) == arena + 224 && unsafe { *(&u8(arena + 250)) } == 0 && value in ios_runtime.constants
  assert country == arena && read64(country) == arena + 32 && read64(read64(country) + 16) == arena + 64
  assert read64(country) in ios_runtime.constants && read64(code) in ios_runtime.constants
  assert code == arena + 8 && read64(code) == arena + 128 && read64(read64(code) + 16) == arena + 160
  csym_text(api, read64(code), 1)
  assert '_NSLocaleCurrencySymbol' !in ios_runtime.framework_data && '_kCFLocaleCurrencySymbol' !in ios_runtime.framework_data
 }
 pool := csym_pool(api)
 assert csym_msg(api, csym_keep(api, value), c'autorelease', 0, 0, 0) == value
 copy := csym_msg(api, value, c'copy', 0, 0, 0); assert copy == value; csym_drop(api, copy)
 equal := csym_msg(api, csym_class(api, c'NSString'), c'stringWithUTF8String:', u64(c'kCFLocaleCurrencySymbolKey'), 0, 0)
 assert csym_msg(api, value, c'length', 0, 0, 0) == 26 && csym_msg(api, value, c'isEqualToString:', equal, 0, 0) == 1
 assert csym_hash(api, value) == csym_hash(api, equal)
 keys := [value]!; values := [equal]!
 dictionary := csym_msg(api, csym_class(api, c'NSDictionary'), c'dictionaryWithObjects:forKeys:count:', u64(unsafe { &values[0] }), u64(unsafe { &keys[0] }), 1)
 assert csym_msg(api, dictionary, c'objectForKey:', equal, 0, 0) == equal
 csym_pop(api, pool); csym_text(api, read64(cell), 2); csym_text(api, read64(country), 0)
 if !api.native { assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 }
 return cell
}
fn csym_query_boundary(cell u64) {
 locale := objc_allocate(ios_runtime.names['NSLocale'])
 name := owned_string('en_US'); store_field(locale, 0, name); objc_release(name)
 equal := owned_string('kCFLocaleCurrencySymbolKey'); before := ios_runtime.live
 for _ in 0 .. 32 { for key in [read64(cell), read64(csym_cell(CurrencySymbolApi{}, true, true, 2)), equal, read64(cell - 8)]! {
  if _ := cf_locale_value_checked(locale, key) { assert false } else { assert err.msg() == 'iOS: unsupported locale value query' }
 } }
 assert ios_runtime.live == before && !obj_header(locale).valid
 country := cf_locale_get_value(locale, read64(cell - 16)); assert string_text(country) == 'US'
 after_country := ios_runtime.live
 if _ := cf_locale_value_checked(locale, read64(cell)) { assert false }
 assert ios_runtime.live == after_country && cf_locale_get_value(locale, read64(cell - 16)) == country
 objc_release(equal); objc_release(locale); assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
}
fn csym_teardown(object u64, selector &char) {
 assert ios_runtime.swift_concurrency_retired
 cell := csym_cell(CurrencySymbolApi{}, true, false, 2)
 assert cell == csym_cell(CurrencySymbolApi{}, false, true, 2)
 csym_text(CurrencySymbolApi{}, read64(cell), 2); csym_text(CurrencySymbolApi{}, read64(cell - 16), 0); csym_text(CurrencySymbolApi{}, read64(cell - 8), 1)
 assert read64(cell) in ios_runtime.constants && read64(cell - 8) in ios_runtime.constants && read64(cell - 16) in ios_runtime.constants
 csym_teardown_calls++
}
fn test_ns_locale_currency_symbol() {
 $if macos {
  api := CurrencySymbolApi{true, u64(C.dlopen(c'/System/Library/Frameworks/Foundation.framework/Foundation', 2)), u64(C.dlopen(c'/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation', 2)), u64(C.dlopen(c'/usr/lib/libobjc.A.dylib', 2))}
  assert api.foundation != 0 && api.core != 0 && api.objc != 0
  csym_shared(api)
  for handle in [api.objc, api.core, api.foundation]! { assert C.dlclose(unsafe { voidptr(handle) }) == 0 }
  println('NATIVE-NS-LOCALE-CURRENCY-SYMBOL: identical NS/CF currency-symbol-key cells and exact value, distinct country/code keys, eight mixed-key/alias readers, immutable string/hash/dictionary behavior and immortal ownership')
 }
 if _ := ns_locale_currency_symbol('_NSLocaleCurrencySymbol') { assert false }
 for _ in 0 .. 2 {
  objc_start(); assert ios_runtime.ns_locale_country_arena == 0
  ns_locale_country_stop(); assert ios_runtime.ns_locale_country_arena == 0
  ios_runtime.swift_concurrency_retired = true
  if _ := ns_locale_currency_symbol('_NSLocaleCurrencySymbol') { assert false }
  ios_runtime.swift_concurrency_retired = false
  cell := csym_shared(CurrencySymbolApi{}); value := read64(cell); country := read64(cell - 16); code := read64(cell - 8); csym_query_boundary(cell)
  for symbol in ['_NSLocaleCurrencySymbol','_kCFLocaleCurrencySymbol']! { for library in ['/System/Library/Frameworks/UIKit.framework/UIKit', '/usr/lib/libSystem.B.dylib']! { if _ := runtime_symbol(library, symbol) { assert false } } }
  for name in ['_NSLocaleCurrencySymbolKey','_kCFLocaleCurrencySymbolKey','_NSLocaleCurrencySymbolExtra']! { if _ := ns_locale_currency_symbol(name) { assert false } }
  probe := objc_allocate_class(ios_runtime.names['NSObject'], c'VinixLocaleCurrencySymbolTeardownProbe', 0); assert probe != 0
  assert objc_add_method(probe, u64(c'dealloc'), u64(unsafe { voidptr(csym_teardown) }), c'v16@0:8')
  objc_register_class(probe); objc_autorelease(objc_new(probe))
  ios_runtime.swift_concurrency_retired = true; assert csym_cell(CurrencySymbolApi{}, false, true, 2) == cell
  before := csym_teardown_calls; objc_stop()
  assert csym_teardown_calls == before + 1 && ios_runtime.ns_locale_country_arena == 0 && ios_runtime.live == 0 && ios_runtime.objects.len == 0
  assert value !in ios_runtime.constants && country !in ios_runtime.constants && code !in ios_runtime.constants
  if _ := ns_locale_currency_symbol('_NSLocaleCurrencySymbol') { assert false }
 }
 println('IOS-NS-LOCALE-CURRENCY-SYMBOL: shared sealed NS/CF currency-symbol-key cell with exact CFString, eight mixed-key/alias cold publishers, preserved country/code layouts and country queries, immutable string/dictionary behavior, explicit unsupported currency code/symbol queries, retirement guards, three-key callback access and two drained/unmapped lifetimes')
}

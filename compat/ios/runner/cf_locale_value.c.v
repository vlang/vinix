// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	fn C.CFStringCreateWithCString(voidptr, &char, u32) voidptr
	fn C.CFLocaleCreate(voidptr, voidptr) voidptr
	fn C.CFLocaleGetValue(voidptr, voidptr) voidptr
}

struct CFLocaleValueFailure {}
fn (_ &CFLocaleValueFailure) msg() string { return 'iOS: unsupported locale value query' }
fn (_ &CFLocaleValueFailure) code() int { return 1 }
__global cf_locale_value_failure_value = CFLocaleValueFailure{}
fn cf_locale_value_failure() IError { return unsafe { &cf_locale_value_failure_value } }

struct CFLocaleParts {
	language_length int
	country_length int
}

// Vinix's bounded identifier profile. Language occupies bytes 0..7 and
// country bytes 8..15; no country is inferred from language or script.
fn cf_locale_parts_checked(source string, output &u8) !CFLocaleParts {
	if source.len > 128 { return cf_locale_value_failure() }
	if source == '' { return CFLocaleParts{} }
	if source in ['c', 'C']! { unsafe { output[0] = `c` }; return CFLocaleParts{language_length: 1} }
	mut posix := source.len == 5
	if posix { for i in 0 .. 5 { posix = posix && (source[i] & ~u8(32)) == 'POSIX'[i] } }
	if posix { C.memcpy(output, c'posix', 5); return CFLocaleParts{language_length: 5} }
	mut starts := [4]int{}
	mut lengths := [4]int{}
	mut count := 0
	mut start := 0
	for i in 0 .. source.len + 1 {
		if i < source.len && source[i] !in [u8(`_`), `-`]! { continue }
		if count == 4 { return cf_locale_value_failure() }
		starts[count] = start; lengths[count] = i - start; count++; start = i + 1
	}
	if lengths[0] != 2 { return cf_locale_value_failure() }
	mut script := false
	mut region := false
	mut variant := false
	mut country_length := 0
	for part in 0 .. count {
		length := lengths[part]
		mut alpha := true
		mut digits := true
		for i in starts[part] .. starts[part] + length {
			byte := source[i]
			alpha = alpha && ((byte >= `A` && byte <= `Z`) || (byte >= `a` && byte <= `z`))
			digits = digits && byte >= `0` && byte <= `9`
		}
		if part == 0 {
			if !alpha { return cf_locale_value_failure() }
			for i in 0 .. 2 { unsafe { output[i] = source[i] | 32 } }
		} else if length == 4 && alpha && !script && !region && !variant {
			script = true
		} else if length == 0 && part == 1 && count == 3 && lengths[2] == 5 {
			region = true // en__POSIX has no country, as measured natively.
		} else if !region && !variant && ((length == 2 && alpha) || (length == 3 && digits)) {
			region = true; country_length = length
			for i in 0 .. length {
				byte := source[starts[part] + i]
				unsafe { output[8 + i] = if byte >= `a` && byte <= `z` { byte & ~u8(32) } else { byte } }
			}
		} else if length == 5 && alpha && region && !variant {
			for i in 0 .. 5 { if (source[starts[part] + i] & ~u8(32)) != 'POSIX'[i] { return cf_locale_value_failure() } }
			variant = true
		} else { return cf_locale_value_failure() }
	}
	language := unsafe { tos(output, 2) }
	alias := match language { 'iw' { 'he' } 'in' { 'id' } 'ji' { 'yi' } else { '' } }
	if alias != '' { C.memcpy(output, alias.str, 2) }
	return CFLocaleParts{language_length: 2, country_length: country_length}
}

// Caller holds the recursive runtime lock. The locale owns both cached
// strings through fields[1..2]; valid also caches an absent country.
fn cf_locale_cache_values_checked(locale u64) ! {
	mut header := obj_header(locale)
	if header.valid { return }
	identifier := string_text(header.fields[0])
	mut values := [2]u64{}
	mut complete := false
	defer { if !complete { for value in values { objc_release(value) } } }
	$if macos {
		for byte in identifier { if byte == 0 { return cf_locale_value_failure() } }
		pool := C.objc_autoreleasePoolPush()
		defer { C.objc_autoreleasePoolPop(pool) }
		name := C.CFStringCreateWithCString(unsafe { nil }, unsafe { &char(identifier.str) }, 0x08000100)
		if name == unsafe { nil } { return cf_locale_value_failure() }
		defer { C.CFRelease(name) }
		native := C.CFLocaleCreate(unsafe { nil }, name)
		if native == unsafe { nil } { return cf_locale_value_failure() }
		defer { C.CFRelease(native) }
		for i, key in [voidptr(C.kCFLocaleLanguageCode), voidptr(C.kCFLocaleCountryCode)]! {
			value := C.CFLocaleGetValue(native, key)
			if value == unsafe { nil } { continue }
			mut bytes := [1024]u8{}
			if !C.CFStringGetCString(value, unsafe { &char(&bytes[0]) }, 1024, 0x08000100) { return cf_locale_value_failure() }
			values[i] = owned_string(ctext(u64(unsafe { &bytes[0] })))
		}
	}
	$if linux {
		mut bytes := [16]u8{}
		parts := cf_locale_parts_checked(identifier, unsafe { &bytes[0] })!
		values[0] = owned_string(unsafe { tos(&bytes[0], parts.language_length) })
		if parts.country_length > 0 { values[1] = owned_string(unsafe { tos(&bytes[8], parts.country_length) }) }
	}
	$if !macos && !linux { return cf_locale_value_failure() }
	header.fields[1] = values[0]; header.fields[2] = values[1]
	header.valid = true
	complete = true
}

fn cf_locale_value_checked(locale u64, key u64) !u64 {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired { return cf_locale_value_failure() }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	header := ios_runtime.objects[locale] or { return cf_locale_value_failure() }
	if header.destroyed || read64(locale) != ios_runtime.names['NSLocale'] || header.fields[0] == 0 || !objc_is_kind(header.fields[0], ios_runtime.names['NSString']) { return cf_locale_value_failure() }
	if key == 0 || !objc_is_kind(key, ios_runtime.names['NSString']) { return cf_locale_value_failure() }
	index := match string_text(key) {
		'kCFLocaleIdentifierKey' { 0 }
		'kCFLocaleLanguageCodeKey' { 1 }
		'kCFLocaleCountryCodeKey' { 2 }
		'kCFLocaleScriptCodeKey', 'kCFLocaleVariantCodeKey', 'kCFLocaleExemplarCharacterSetKey',
		'calendar', 'kCFLocaleCalendarKey', 'collation', 'kCFLocaleUsesMetricSystemKey',
		'kCFLocaleMeasurementSystemKey', 'kCFLocaleDecimalSeparatorKey', 'kCFLocaleGroupingSeparatorKey',
		'kCFLocaleCurrencySymbolKey', 'currency', 'kCFLocaleCollatorIdentifierKey',
		'kCFLocaleQuotationBeginDelimiterKey', 'kCFLocaleQuotationEndDelimiterKey',
		'kCFLocaleAlternateQuotationBeginDelimiterKey', 'kCFLocaleAlternateQuotationEndDelimiterKey' { return cf_locale_value_failure() }
		else { return 0 }
	}
	if index > 0 { cf_locale_cache_values_checked(locale)! }
	return header.fields[index]
}

fn cf_locale_get_value(locale u64, key u64) u64 {
	return cf_locale_value_checked(locale, key) or { panic(err) }
}

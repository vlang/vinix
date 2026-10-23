// SPDX-License-Identifier: GPL-2.0-or-later
module main

import math

$if macos {
	#flag -framework Foundation
	#include <objc/runtime.h>
}
#include <dlfcn.h>
#include <time.h>
#define date_formatter_fixture_localtime_r localtime_r
#define date_formatter_fixture_mktime mktime
#define date_formatter_fixture_strftime strftime
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.class_getInstanceMethod(voidptr, voidptr) voidptr
fn C.method_getTypeEncoding(voidptr) &char
fn C.class_getInstanceSize(voidptr) usize
fn C.class_getSuperclass(voidptr) voidptr
fn C.objc_storeWeak(&u64, voidptr) voidptr
fn C.date_formatter_fixture_localtime_r(voidptr, voidptr) voidptr
fn C.date_formatter_fixture_mktime(voidptr) i64
fn C.date_formatter_fixture_strftime(&u8, usize, &char, voidptr) usize

type DateFormatterSend = fn (u64, u64, u64, u64, u64) u64
type DateFormatterRealSend = fn (u64, u64, f64) u64
type DateFormatterRealGet = fn (u64, u64) f64
struct DateFormatterApi { native bool send u64 }
fn (api DateFormatterApi) cls(name string) u64 {
	$if macos { if api.native { return u64(C.objc_getClass(name.str)) } }
	return ios_runtime.names[name]
}
fn (api DateFormatterApi) selector(name &char) u64 {
	$if macos { if api.native { return u64(C.sel_registerName(name)) } }
	return u64(name)
}
fn (api DateFormatterApi) message(object u64, name &char, a u64, b u64, c u64) u64 {
	return unsafe { DateFormatterSend(voidptr(api.send))(object, api.selector(name), a, b, c) }
}
fn (api DateFormatterApi) string(value string) u64 { return api.message(api.cls('NSString'), c'stringWithUTF8String:', u64(value.str), 0, 0) }
fn (api DateFormatterApi) text(object u64) string {
	assert object != 0
	pointer := api.message(object, c'UTF8String', 0, 0, 0); assert pointer != 0
	return unsafe { (&char(voidptr(pointer))).vstring() }
}
fn (api DateFormatterApi) date(seconds f64) u64 {
	return unsafe { DateFormatterRealSend(voidptr(api.send))(api.cls('NSDate'), api.selector(c'dateWithTimeIntervalSince1970:'), seconds) }
}
fn (api DateFormatterApi) seconds(date u64) f64 {
	return unsafe { DateFormatterRealGet(voidptr(api.send))(date, api.selector(c'timeIntervalSince1970')) }
}
fn (api DateFormatterApi) pool() u64 {
	$if macos { if api.native { return api.message(api.cls('NSAutoreleasePool'), c'new', 0, 0, 0) } }
	return objc_pool_push()
}
fn (api DateFormatterApi) drain(pool u64) {
	$if macos { if api.native { api.message(pool, c'drain', 0, 0, 0); return } }
	objc_pool_pop(pool)
}
fn (api DateFormatterApi) weak(slot &u64, object u64) {
	$if macos { if api.native { C.objc_storeWeak(slot, unsafe { voidptr(object) }); return } }
	objc_store_weak(slot, object)
}
fn (api DateFormatterApi) destroy_weak(slot &u64) {
	$if macos { if api.native { C.objc_storeWeak(slot, unsafe { nil }); return } }
	objc_destroy_weak(slot)
}
fn (api DateFormatterApi) locale(identifier string) u64 { return api.message(api.cls('NSLocale'), c'localeWithLocaleIdentifier:', api.string(identifier), 0, 0) }
fn (api DateFormatterApi) zone(seconds i64) u64 { return api.message(api.cls('NSTimeZone'), c'timeZoneForSecondsFromGMT:', u64(seconds), 0, 0) }
fn (api DateFormatterApi) format(object u64, pattern string) { api.message(object, c'setDateFormat:', api.string(pattern), 0, 0) }
fn (api DateFormatterApi) output(object u64, seconds f64) string { return api.text(api.message(object, c'stringFromDate:', api.date(seconds), 0, 0)) }
fn (api DateFormatterApi) formatter(pattern string, offset i64) u64 {
	object := api.message(api.cls('NSDateFormatter'), c'new', 0, 0, 0)
	api.message(object, c'setLocale:', api.locale('en_US_POSIX'), 0, 0)
	api.message(object, c'setTimeZone:', api.zone(offset), 0, 0); api.format(object, pattern)
	return object
}
fn date_formatter_local_text(seconds i64, pattern &char) string {
	mut value := seconds; mut fields := [7]u64{}; mut buffer := [96]u8{}
	assert C.date_formatter_fixture_localtime_r(unsafe { &value }, unsafe { voidptr(&fields[0]) }) != unsafe { nil }
	length := C.date_formatter_fixture_strftime(unsafe { &buffer[0] }, usize(buffer.len), pattern, unsafe { voidptr(&fields[0]) }); assert length > 0
	return unsafe { tos(&buffer[0], int(length)).clone() }
}
fn date_formatter_local_seconds() f64 {
	mut fields := [7]u64{}; mut values := unsafe { &i32(&fields[0]) }
	unsafe { values[0] = 56; values[1] = 34; values[2] = 12; values[3] = 29; values[4] = 1; values[5] = 124; values[8] = -1 }
	return f64(C.date_formatter_fixture_mktime(unsafe { voidptr(&fields[0]) }))
}
fn date_formatter_metadata(api DateFormatterApi) {
	cls := api.cls('NSDateFormatter'); parent := api.cls('NSFormatter')
	$if macos {
		if api.native { assert C.class_getInstanceSize(unsafe { voidptr(cls) }) == 56; assert u64(C.class_getSuperclass(unsafe { voidptr(cls) })) == parent; assert C.class_getInstanceSize(unsafe { voidptr(parent) }) == 8 }
	}
	if !api.native { assert objc_class_size(cls) == 56 && objc_class_parent(cls) == parent && objc_class_size(parent) == 8 && objc_class_parent(parent) == api.cls('NSObject') }
	for name, types in {
		'init': '@16@0:8', 'dateFormat': '@16@0:8', 'setDateFormat:': 'v24@0:8@16',
		'locale': '@16@0:8', 'setLocale:': 'v24@0:8@16', 'timeZone': '@16@0:8', 'setTimeZone:': 'v24@0:8@16',
		'stringFromDate:': '@24@0:8@16', 'dateFromString:': '@24@0:8@16', 'stringForObjectValue:': '@24@0:8@16',
		'copyWithZone:': '@24@0:8^{_NSZone=}16', 'dateStyle': 'Q16@0:8', 'setDateStyle:': 'v24@0:8Q16',
		'timeStyle': 'Q16@0:8', 'setTimeStyle:': 'v24@0:8Q16', 'isLenient': 'B16@0:8',
		'formatterBehavior': 'Q16@0:8', 'setFormatterBehavior:': 'v24@0:8Q16',
		'formattingContext': 'q16@0:8', 'setFormattingContext:': 'v24@0:8q16',
		'defaultDate': '@16@0:8', 'setDefaultDate:': 'v24@0:8@16',
	} {
		mut actual := ''
		$if macos { if api.native { method := C.class_getInstanceMethod(unsafe { voidptr(cls) }, unsafe { voidptr(api.selector(name.str)) }); assert method != unsafe { nil }; actual = unsafe { C.method_getTypeEncoding(method).vstring() } } }
		if !api.native { method := objc_instance_method(cls, u64(name.str)); assert method != 0; actual = ctext(u64(objc_method_types(method))) }
		assert actual == types, name + ': ' + actual
	}
}
fn date_formatter_shared_defaults(api DateFormatterApi) {
	pool := api.pool(); date_formatter_metadata(api)
	object := api.message(api.cls('NSDateFormatter'), c'new', 0, 0, 0)
	assert api.message(object, c'classForCoder', 0, 0, 0) == api.cls('NSDateFormatter')
	assert api.text(api.message(object, c'dateFormat', 0, 0, 0)) == '' && api.output(object, 0) == ''
	assert api.message(object, c'stringFromDate:', 0, 0, 0) == 0 && api.message(object, c'dateFromString:', 0, 0, 0) == 0
	assert api.message(object, c'stringForObjectValue:', api.string('not a date'), 0, 0) == 0
	for selector in [c'dateStyle', c'timeStyle', c'formatterBehavior', c'formattingContext', c'isLenient', c'doesRelativeDateFormatting', c'generatesCalendarDates', c'allowsNaturalLanguage', c'defaultDate']! { assert api.message(object, selector, 0, 0, 0) == 0 }
	for selector in [c'setFormatterBehavior:', c'setFormattingContext:', c'setLenient:', c'setDoesRelativeDateFormatting:', c'setGeneratesCalendarDates:', c'setDefaultDate:']! { api.message(object, selector, 0, 0, 0) }
	for identifier in ['en_US_POSIX', 'en_US', 'en_GB']! {
		locale := api.locale(identifier); assert locale != 0
		assert api.text(api.message(locale, c'localeIdentifier', 0, 0, 0)) == identifier
		owned := api.message(api.message(api.cls('NSLocale'), c'alloc', 0, 0, 0), c'initWithLocaleIdentifier:', api.string(identifier), 0, 0)
		assert api.text(api.message(owned, c'localeIdentifier', 0, 0, 0)) == identifier
		api.message(object, c'setLocale:', owned, 0, 0); api.message(owned, c'release', 0, 0, 0)
		assert api.text(api.message(api.message(object, c'locale', 0, 0, 0), c'localeIdentifier', 0, 0, 0)) == identifier
	}
	for selector in [c'timeZoneWithAbbreviation:', c'timeZoneWithName:']! { for name in ['UTC', 'GMT']! {
		zone := api.message(api.cls('NSTimeZone'), selector, api.string(name), 0, 0); assert zone != 0
		assert api.message(zone, c'secondsFromGMT', 0, 0, 0) == 0
		api.message(object, c'setTimeZone:', zone, 0, 0); assert api.message(api.message(object, c'timeZone', 0, 0, 0), c'secondsFromGMT', 0, 0, 0) == 0
	} }
	api.format(object, 'yyyy-MM-dd'); assert api.message(object, c'init', 0, 0, 0) == object
	assert api.text(api.message(object, c'dateFormat', 0, 0, 0)) == 'yyyy-MM-dd'
	for selector in [c'setDateStyle:', c'setTimeStyle:']! { api.format(object, 'yyyy-MM-dd'); api.message(object, selector, 0, 0, 0); assert api.text(api.message(object, c'dateFormat', 0, 0, 0)) == '' }
	api.message(object, c'setDateFormat:', 0, 0, 0); assert api.text(api.message(object, c'dateFormat', 0, 0, 0)) == ''
	api.message(object, c'setLocale:', 0, 0, 0); assert api.message(object, c'locale', 0, 0, 0) != 0
	api.message(object, c'setTimeZone:', 0, 0, 0); api.format(object, 'yyyy-MM-dd HH:mm:ss')
	assert api.output(object, 0) == date_formatter_local_text(0, c'%Y-%m-%d %H:%M:%S')
	local_date := api.message(object, c'dateFromString:', api.string('2024-02-29 12:34:56'), 0, 0)
	assert local_date != 0 && math.abs(api.seconds(local_date) - date_formatter_local_seconds()) < 0.00001
	api.format(object, 'yyyy-MM-dd_HHmmssZ'); assert api.output(object, 0) == date_formatter_local_text(0, c'%Y-%m-%d_%H%M%S%z')
	api.message(object, c'release', 0, 0, 0)
	raw := api.message(api.cls('NSDateFormatter'), c'alloc', 0, 0, 0)
	assert api.text(api.message(raw, c'dateFormat', 0, 0, 0)) == ''
	assert api.message(raw, c'init', 0, 0, 0) == raw && api.text(api.message(raw, c'dateFormat', 0, 0, 0)) == ''
	current := api.message(api.cls('NSLocale'), c'currentLocale', 0, 0, 0)
	assert api.text(api.message(api.message(raw, c'locale', 0, 0, 0), c'localeIdentifier', 0, 0, 0)) == api.text(api.message(current, c'localeIdentifier', 0, 0, 0))
	api.format(raw, 'yyyy-MM-dd HH:mm:ss'); assert api.output(raw, 0) == date_formatter_local_text(0, c'%Y-%m-%d %H:%M:%S')
	api.message(raw, c'setLocale:', api.locale('en_US_POSIX'), 0, 0); api.message(raw, c'setTimeZone:', api.zone(0), 0, 0); api.format(raw, 'yyyy-MM-dd')
	assert api.output(raw, 0) == '1970-01-01'
	api.message(raw, c'release', 0, 0, 0); api.drain(pool)
}
fn date_formatter_shared_format(api DateFormatterApi) {
	pool := api.pool()
	for pattern, expected in {
		'yyyy-MM-dd': '2024-02-29', 'yyyy-MM-dd HH:mm:ss': '2024-02-29 12:34:56',
		'yyyy-MM-dd_HHmmssZ': '2024-02-29_123456+0000', "yyyy-MM-dd'T'HH:mm:ss.SSS": '2024-02-29T12:34:56.789',
	} {
		object := api.formatter(pattern, 0)
		assert api.output(object, 1709210096.789) == expected, pattern
		assert api.text(api.message(object, c'stringForObjectValue:', api.date(1709210096.789), 0, 0)) == expected
		api.message(object, c'release', 0, 0, 0)
	}
	object := api.formatter("yyyy-MM-dd'T'HH:mm:ss.SSS", 0)
	for entry in [
		[f64(0), 0.9994, 0.9996, -0.0004, -0.0006, -0.9994, -0.9996]!,
		[f64(978307200), 978307200.9994, 978307200.9996, 978307199.9996, 978307199.9994, 978307199.0006, 978307199.0004]!,
	] {
		prefix := if entry[0] == 0 { '1970-01-01T00:00:' } else { '2001-01-01T00:00:' }
		prior := if entry[0] == 0 { '1969-12-31T23:59:' } else { '2000-12-31T23:59:' }
		for index, value in entry { expected := match index { 0 { prefix + '00.000' } 1 { prefix + '00.999' } 2 { prefix + '01.000' } 3 { prefix + '00.000' } 4 { prior + '59.999' } 5 { prior + '59.001' } else { prior + '59.000' } }; assert api.output(object, value) == expected }
	}
	for seconds, expected in {
		f64(-0.0625): '1969-12-31T23:59:59.938', f64(-0.5625): '1969-12-31T23:59:59.438',
		f64(-1.9375): '1969-12-31T23:59:58.063', f64(0.0625): '1970-01-01T00:00:00.063',
	} { assert api.output(object, seconds) == expected }
	api.format(object, 'yyyy-MM-dd HH:mm:ss'); assert api.output(object, 0.9996) == '1970-01-01 00:00:01'
	api.format(object, 'yyyy-MM-dd_HHmmssZ')
	for offset, expected in {
		i64(-64800): '1969-12-31_060000-1800', i64(-19800): '1969-12-31_183000-0530',
		i64(-30): '1969-12-31_235900-0001', i64(-29): '1970-01-01_000000+0000',
		i64(29): '1970-01-01_000000+0000', i64(30): '1970-01-01_000100+0001',
		i64(19800): '1970-01-01_053000+0530', i64(64800): '1970-01-01_180000+1800',
	} { api.message(object, c'setTimeZone:', api.zone(offset), 0, 0); assert api.output(object, 0) == expected }
	api.message(object, c'release', 0, 0, 0); api.drain(pool)
}
fn date_formatter_shared_parse(api DateFormatterApi) {
	pool := api.pool(); object := api.formatter('yyyy-MM-dd HH:mm:ss', 0)
	for input, expected in {
		'1970-01-01 00:00:00': f64(0), '1970-1-1 0:0:0': f64(0),
		' 2024-02-29 12:34:56 ': 1709210096.0, '2024-02-29  12:34:56': 1709210096.0,
		'2024-02-29\t12:34:56': 1709210096.0, '2024-2-29 1:2:3': 1709168523.0,
		'2000-02-29 00:00:00': 951782400.0,
	} { date := api.message(object, c'dateFromString:', api.string(input), 0, 0); assert date != 0 && math.abs(api.seconds(date) - expected) < 0.00001, input }
	for input in ['2023-02-29 12:34:56', '1900-02-29 00:00:00', '2024-00-01 00:00:00', '2024-13-01 00:00:00', '2024-01-00 00:00:00', '2024-01-32 00:00:00', '2024-02-29 24:00:00', '2024-02-29 23:60:00', '2024-02-29 23:59:60', '2024-02-29T12:34:56', '2024-02-29 12:34:56junk', '2024-02-29 12:34:56\n', '', 'not-a-date']! { assert api.message(object, c'dateFromString:', api.string(input), 0, 0) == 0, input }
	api.format(object, "yyyy-MM-dd'T'HH:mm:ss.SSS")
	for input, expected in {'1970-01-01T00:00:00.0': f64(0), '1970-01-01T00:00:00.1': 0.1, '1970-01-01T00:00:00.12': 0.12, '1970-01-01T00:00:00.123': 0.123, '1970-01-01T00:00:00.123999999': 0.123, '1970-01-01T00:00:00.000999': f64(0), '1970-01-01T00:00:00.999999': 0.999, ' 1970-1-1T0:0:0.1 ': 0.1} {
		date := api.message(object, c'dateFromString:', api.string(input), 0, 0); assert date != 0 && math.abs(api.seconds(date) - expected) < 0.00001, input
	}
	for input in ['1970-01-01T00:00:00.', '1970-01-01T00:00:00', '1970-01-01t00:00:00.123', '1970-01-01 00:00:00.123', '1970-01-01T00:00:00,123', '1970-01-01T00:00:00.123Z', '1970-01-01T00:00:00.123abc']! { assert api.message(object, c'dateFromString:', api.string(input), 0, 0) == 0, input }
	api.format(object, 'yyyy-MM-dd_HHmmssZ')
	for input, expected in {'1970-01-01_000000+0000': f64(0), '1970-01-01_000000Z': f64(0), '1970-01-01_000000+0530': f64(-19800), '1970-01-01_000000-0530': f64(19800), '1970-01-01_000000+1800': f64(-64800), '1970-01-01_123456+0000': f64(45296)} {
		date := api.message(object, c'dateFromString:', api.string(input), 0, 0); assert date != 0 && math.abs(api.seconds(date) - expected) < 0.00001, input
	}
	for input in ['1970-01-01_000000+2400', '1970-01-01_000000+0060', '1970-01-01_240000+0000', '1970-01-01_000000+0000junk']! { assert api.message(object, c'dateFromString:', api.string(input), 0, 0) == 0, input }
	api.format(object, 'yyyy-MM-dd')
	for input, expected in {'1970-01-01': f64(0), ' 2024-2-29 ': f64(1709164800), '2000-02-29': f64(951782400), '1582-10-15': f64(-12219292800), '9999-12-31': f64(253402214400)} { date := api.message(object, c'dateFromString:', api.string(input), 0, 0); assert date != 0 && math.abs(api.seconds(date) - expected) < 0.00001, input; assert api.output(object, expected) == input.trim_space().replace('2024-2-29', '2024-02-29') }
	for input in ['2023-02-29', '2024-02-29junk', '2024-02-29 00:00:00']! { assert api.message(object, c'dateFromString:', api.string(input), 0, 0) == 0 }
	api.format(object, ''); empty := api.message(object, c'dateFromString:', api.string(''), 0, 0); assert empty != 0 && api.seconds(empty) == 946684800.0
	api.message(object, c'release', 0, 0, 0); api.drain(pool)
}
fn date_formatter_shared_ownership(api DateFormatterApi) {
	pool := api.pool(); original := api.formatter('yyyy-MM-dd', 19800)
	mutable := api.message(api.cls('NSMutableString'), c'stringWithUTF8String:', u64(c"yyyy-MM-dd'T'HH:mm:ss.SSS"), 0, 0)
	api.message(original, c'setDateFormat:', mutable, 0, 0); api.message(mutable, c'appendString:', api.string('x'), 0, 0)
	assert api.text(api.message(original, c'dateFormat', 0, 0, 0)) == "yyyy-MM-dd'T'HH:mm:ss.SSS"
	copy := api.message(original, c'copyWithZone:', 0, 0, 0); assert copy != 0 && copy != original
	mut first := u64(0); mut second := u64(0); api.weak(unsafe { &first }, original); api.weak(unsafe { &second }, copy)
	api.drain(pool); next := api.pool()
	assert first == original && second == copy
	assert api.output(copy, 0) == '1970-01-01T05:30:00.000'
	api.format(original, 'yyyy-MM-dd'); api.message(original, c'setTimeZone:', api.zone(-19800), 0, 0); api.message(original, c'setLocale:', api.locale('en_GB'), 0, 0)
	assert api.output(original, 0) == '1969-12-31' && api.output(copy, 0) == '1970-01-01T05:30:00.000'
	assert api.text(api.message(api.message(copy, c'locale', 0, 0, 0), c'localeIdentifier', 0, 0, 0)) == 'en_US_POSIX'
	api.message(original, c'release', 0, 0, 0); assert first == 0 && second == copy
	api.format(copy, 'yyyy-MM-dd HH:mm:ss'); assert api.output(copy, 0) == '1970-01-01 05:30:00'
	api.message(copy, c'release', 0, 0, 0); assert second == 0
	api.destroy_weak(unsafe { &first }); api.destroy_weak(unsafe { &second }); api.drain(next)
	getter_pool := api.pool(); source := api.formatter("yyyy-MM-dd'T'HH:mm:ss.SSS", 19800)
	format := api.message(source, c'dateFormat', 0, 0, 0); locale := api.message(source, c'locale', 0, 0, 0); zone := api.message(source, c'timeZone', 0, 0, 0)
	api.message(source, c'release', 0, 0, 0)
	assert api.text(format) == "yyyy-MM-dd'T'HH:mm:ss.SSS" && api.text(api.message(locale, c'localeIdentifier', 0, 0, 0)) == 'en_US_POSIX' && api.message(zone, c'secondsFromGMT', 0, 0, 0) == 19800
	api.drain(getter_pool)
}
fn date_formatter_shared(api DateFormatterApi) { date_formatter_shared_defaults(api); date_formatter_shared_format(api); date_formatter_shared_parse(api); date_formatter_shared_ownership(api) }
fn test_date_formatter_native() {
	$if macos {
		date_formatter_shared(DateFormatterApi{native: true, send: u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend'))})
		println('IOS-DATE-FORMATTER-NATIVE: metadata, four consumer formats, local and fixed zones, strict modern parse, fractional rounding, initializer state, copied properties and independent copy lifetime')
	}
}

fn date_formatter_runtime_api() DateFormatterApi { return DateFormatterApi{send: u64(unsafe { voidptr(C.ios_objc_msgsend) })} }
__global date_formatter_callback_mode = ''
__global date_formatter_callback_source = u64(0)
__global date_formatter_callback_fired = false
__global date_formatter_callback_weak = u64(0)
__global date_formatter_callback_property_weak = u64(0)

fn date_formatter_callback_worker() {
	api := date_formatter_runtime_api(); pool := api.pool()
	C.ios_objc_initialize_lock(); C.ios_objc_initialize_unlock()
	if date_formatter_callback_mode == 'copy' {
		source := date_formatter_callback_source
		assert api.text(api.message(source, c'dateFormat', 0, 0, 0)) == "yyyy-MM-dd'T'HH:mm:ss.SSS"
		assert api.output(source, 0) == '1970-01-01T05:30:00.000'
		api.format(source, 'yyyy-MM-dd'); api.message(source, c'setLocale:', api.locale('en_GB'), 0, 0)
		api.message(source, c'setTimeZone:', api.zone(-19800), 0, 0); objc_release(source)
	}
	if date_formatter_callback_mode == 'locale-input' { objc_release(date_formatter_callback_source) }
	api.drain(pool)
}

fn date_formatter_constructor(object u64, selector &char) u64 {
	if date_formatter_callback_mode == '' { return object }
	date_formatter_callback_fired = true
	if date_formatter_callback_mode == 'destruct' { objc_destruct_instance(date_formatter_callback_source); return object }
	worker := spawn date_formatter_callback_worker(); worker.wait()
	if date_formatter_callback_mode == 'fail' {
		api := date_formatter_runtime_api()
		api.message(object, c'init', 0, 0, 0); api.format(object, 'yyyy-MM-dd')
		api.message(object, c'setLocale:', api.locale('en_GB'), 0, 0); api.message(object, c'setTimeZone:', api.zone(19800), 0, 0)
		objc_store_weak(unsafe { &date_formatter_callback_weak }, object)
		objc_store_weak(unsafe { &date_formatter_callback_property_weak }, obj_header(object).fields[0])
		return 0
	}
	return object
}

fn date_formatter_string_constructor(object u64, selector &char) u64 {
	if date_formatter_callback_mode != 'string-fail' { return object }
	date_formatter_callback_fired = true
	worker := spawn date_formatter_callback_worker(); worker.wait()
	objc_store_weak(unsafe { &date_formatter_callback_property_weak }, object)
	return 0
}

fn date_formatter_locale_constructor(object u64, selector &char) u64 {
	if date_formatter_callback_mode !in ['locale-input', 'cache-race']! { return object }
	C.ios_objc_initialize_lock(); date_formatter_callback_fired = true; C.ios_objc_initialize_unlock()
	worker := spawn date_formatter_callback_worker(); worker.wait()
	return object
}

fn date_formatter_reset_cached_locale() {
	C.ios_objc_initialize_lock(); locale := ios_runtime.locale; ios_runtime.locale = 0; C.ios_objc_initialize_unlock()
	objc_release(locale)
}

fn date_formatter_cache_reader() {
	api := date_formatter_runtime_api(); pool := api.pool()
	locale := cf_locale_copy_current(); assert locale != 0 && locale == ns_locale_current()
	assert api.text(api.message(locale, c'localeIdentifier', 0, 0, 0)).len > 0
	objc_release(locale); api.drain(pool)
}

fn date_formatter_initial_locale_callbacks(api DateFormatterApi) {
	assert ios_runtime.locale == 0
	assert objc_add_method(api.cls('NSLocale'), u64(c'.cxx_construct'), u64(unsafe { voidptr(date_formatter_locale_constructor) }), c'@16@0:8')
	pool := api.pool()
	for parse in [false, true]! {
		object := api.message(api.cls('NSDateFormatter'), c'new', 0, 0, 0)
		api.format(object, 'yyyy-MM-dd HH:mm:ss'); api.message(object, c'setTimeZone:', api.zone(0), 0, 0)
		input := if parse { owned_string('1970-01-01 00:00:00') } else { cf_date_create(0, -978307200.0) }
		mut weak := u64(0); objc_store_weak(unsafe { &weak }, input)
		date_formatter_callback_source = input; date_formatter_callback_mode = 'locale-input'; date_formatter_callback_fired = false
		result := api.message(object, if parse { c'dateFromString:' } else { c'stringFromDate:' }, input, 0, 0)
		date_formatter_callback_mode = ''; date_formatter_callback_source = 0
		assert date_formatter_callback_fired && weak == 0 && result != 0
		if parse { assert api.seconds(result) == 0 } else { assert api.text(result) == '1970-01-01 00:00:00' }
		objc_destroy_weak(unsafe { &weak }); objc_release(object); date_formatter_reset_cached_locale()
	}
	// Concurrent first publication may construct losing cache candidates. Each
	// constructor joins a worker taking the runtime lock before publication.
	date_formatter_callback_mode = 'cache-race'; date_formatter_callback_fired = false
	mut readers := []thread{cap: 8}; for _ in 0 .. 8 { readers << spawn date_formatter_cache_reader() }; readers.wait(); unsafe { readers.free() }
	date_formatter_callback_mode = ''; assert date_formatter_callback_fired && ios_runtime.locale != 0
	api.drain(pool); date_formatter_only_cached_locale()
}

fn date_formatter_reader_worker(object u64) {
	api := date_formatter_runtime_api(); pool := api.pool()
	for _ in 0 .. 32 {
		assert api.output(object, 1709210096.789) == '2024-02-29T12:34:56.789'
		date := api.message(object, c'dateFromString:', api.string('2024-02-29T12:34:56.789'), 0, 0)
		assert date != 0 && math.abs(api.seconds(date) - 1709210096.789) < 0.00001
		assert api.text(api.message(object, c'dateFormat', 0, 0, 0)) == "yyyy-MM-dd'T'HH:mm:ss.SSS"
	}
	api.drain(pool)
}

fn date_formatter_runtime_bounds(api DateFormatterApi) {
	pool := api.pool(); object := api.formatter('yyyy-MM-dd HH:mm:ss', 0)
	for input in ['1582-10-14 00:00:00', '1582-01-01 00:00:00', '0001-01-01 00:00:00', '999-01-01 00:00:00', '10000-01-01 00:00:00', '2024/02/29 12:34:56', '2024-02-29 12.34.56', '٢٠٢٤-٠٢-٢٩ ١٢:٣٤:٥٦', '2024-02-29\n12:34:56']! { assert api.message(object, c'dateFromString:', api.string(input), 0, 0) == 0, input }
	api.format(object, 'yyyy-MM-dd_HHmmssZ')
	for input in ['1970-01-01_00000+0000', '1970-01-01_000000GMT', '1970-01-01_000000UTC', '1970-01-01_000000+00', '1970-01-01_000000+00:00', '1970-01-01_000000+000000']! { assert api.message(object, c'dateFromString:', api.string(input), 0, 0) == 0, input }
	api.format(object, "yyyy-MM-dd'T'HH:mm:ss.SSS")
	assert api.message(object, c'dateFromString:', api.string('1970-01-01T00:00:00.1234567890'), 0, 0) == 0
	assert api.message(object, c'dateFromString:', api.string(' '.repeat(129)), 0, 0) == 0
	api.message(object, c'release', 0, 0, 0); api.drain(pool)
}

fn date_formatter_runtime_lifetimes(api DateFormatterApi) {
	pool := api.pool(); cls := api.cls('NSDateFormatter')
	for name in ['NSDateFormatter', 'NSFormatter']! {
		library := '/System/Library/Frameworks/Foundation.framework/Foundation'
		assert runtime_symbol(library, '_OBJC_CLASS_$_' + name) or { panic(err) } == api.cls(name)
		assert runtime_symbol(library, '_OBJC_METACLASS_$_' + name) or { panic(err) } == read64(api.cls(name))
	}
	assert ios_runtime.classes[cls].ivars.len == 6
	for i, pair in [['_attributes', '@"NSMutableDictionary"']!, ['_formatter', '^{__CFDateFormatter=}']!, ['_counter', 'Q']!, ['_cacheGeneration', 'q']!, ['_behavior', 'Q']!, ['_lock', '{os_unfair_lock_s="_os_unfair_lock_opaque"I}']!]! {
		ivar := objc_find_ivar(cls, pair[0].str)
		assert ivar != 0 && objc_ivar_offset(ivar) == u64(8 + i * 8) && ctext(u64(objc_ivar_types(ivar))) == pair[1]
	}
	// A copy snapshots settings before a destination constructor joins a worker
	// that reads, mutates and drops the source's final caller-owned reference.
	assert objc_add_method(cls, u64(c'.cxx_construct'), u64(unsafe { voidptr(date_formatter_constructor) }), c'@16@0:8')
	source := api.formatter("yyyy-MM-dd'T'HH:mm:ss.SSS", 19800); mut source_weak := u64(0)
	objc_store_weak(unsafe { &source_weak }, source)
	date_formatter_callback_source = source; date_formatter_callback_mode = 'copy'; date_formatter_callback_fired = false
	copy := api.message(source, c'copy', 0, 0, 0)
	date_formatter_callback_mode = ''; date_formatter_callback_source = 0
	assert date_formatter_callback_fired && source_weak == 0 && copy != 0
	assert api.output(copy, 0) == '1970-01-01T05:30:00.000'
	assert api.text(api.message(api.message(copy, c'locale', 0, 0, 0), c'localeIdentifier', 0, 0, 0)) == 'en_US_POSIX'
	objc_release(copy); objc_destroy_weak(unsafe { &source_weak })
	// Failed new/copy/caller-storage constructors own properties before returning
	// nil. Both those properties and the destination sidecar must be retired.
	valid := api.formatter('yyyy-MM-dd', 0); date_formatter_callback_mode = 'fail'
	assert api.message(cls, c'new', 0, 0, 0) == 0 && date_formatter_callback_weak == 0 && date_formatter_callback_property_weak == 0
	objc_destroy_weak(unsafe { &date_formatter_callback_weak }); objc_destroy_weak(unsafe { &date_formatter_callback_property_weak })
	assert api.message(valid, c'copy', 0, 0, 0) == 0 && date_formatter_callback_weak == 0 && date_formatter_callback_property_weak == 0
	objc_destroy_weak(unsafe { &date_formatter_callback_weak }); objc_destroy_weak(unsafe { &date_formatter_callback_property_weak })
	mut failed := [9]u64{}; failed[0] = 0x1122334455667788; failed[8] = 0x8877665544332211
	assert objc_construct_instance(cls, u64(unsafe { &failed[1] })) == 0
	assert date_formatter_callback_weak == 0 && date_formatter_callback_property_weak == 0
	objc_destroy_weak(unsafe { &date_formatter_callback_weak }); objc_destroy_weak(unsafe { &date_formatter_callback_property_weak })
	assert failed[0] == 0x1122334455667788 && failed[8] == 0x8877665544332211 && failed[1] == cls
	date_formatter_callback_mode = ''; assert api.output(valid, 0) == '1970-01-01'; objc_release(valid)
	// A failed identifier string allocation consumes the locale initializer's
	// caller-owned receiver and clears both weak slots before returning nil.
	assert objc_add_method(api.cls('NSString'), u64(c'.cxx_construct'), u64(unsafe { voidptr(date_formatter_string_constructor) }), c'@16@0:8')
	identifier := api.string('en_US_POSIX'); failed_locale := objc_allocate(api.cls('NSLocale'))
	mut locale_weak := u64(0); objc_store_weak(unsafe { &locale_weak }, failed_locale)
	date_formatter_callback_mode = 'string-fail'; date_formatter_callback_fired = false
	assert api.message(failed_locale, c'initWithLocaleIdentifier:', identifier, 0, 0) == 0
	date_formatter_callback_mode = ''
	assert date_formatter_callback_fired && locale_weak == 0 && date_formatter_callback_property_weak == 0
	objc_destroy_weak(unsafe { &locale_weak }); objc_destroy_weak(unsafe { &date_formatter_callback_property_weak })
	mut guarded := [9]u64{}; guarded[0] = 0x1122334455667788; guarded[8] = 0x8877665544332211
	caller := u64(unsafe { &guarded[1] }); assert objc_construct_instance(cls, caller) == caller
	api.message(caller, c'init', 0, 0, 0); api.format(caller, 'yyyy-MM-dd'); api.message(caller, c'setTimeZone:', api.zone(0), 0, 0)
	assert api.output(caller, 0) == '1970-01-01'
	assert objc_set_class(caller, api.cls('NSObject')) == cls && objc_destruct_instance(caller) == caller
	assert caller !in ios_runtime.objects && guarded[0] == 0x1122334455667788 && guarded[8] == 0x8877665544332211
	for _ in 0 .. 32 {
		object := api.formatter('yyyy-MM-dd HH:mm:ss', 19800)
		assert objc_set_class(object, api.cls('NSObject')) == cls; objc_release(object)
	}
	concurrent := api.formatter("yyyy-MM-dd'T'HH:mm:ss.SSS", 0)
	mut readers := []thread{cap: 6}; for _ in 0 .. 6 { readers << spawn date_formatter_reader_worker(concurrent) }; readers.wait(); unsafe { readers.free() }
	objc_release(concurrent); api.drain(pool)
}

fn date_formatter_only_cached_locale() {
	locale := ios_runtime.locale
	assert locale != 0 && ios_runtime.live == 2 && ios_runtime.objects.len == 2 && ios_runtime.weak.len == 0
	assert obj_header(locale).refs == 1 && obj_header(obj_header(locale).fields[0]).refs == 1
}

fn test_date_formatter_runtime() {
	for _ in 0 .. 2 {
		objc_start(); system_data_start()!; api := date_formatter_runtime_api(); date_formatter_initial_locale_callbacks(api); date_formatter_shared(api)
		date_formatter_runtime_bounds(api); date_formatter_runtime_lifetimes(api); date_formatter_only_cached_locale()
		api.pool(); objc_autorelease(api.formatter('yyyy-MM-dd', 19800))
		objc_stop(); assert ios_runtime.live == 0 && ios_runtime.objects.len == 0; system_data_stop()
	}
	println('IOS-DATE-FORMATTER: four measured formats, local/fixed zones, metadata, parser bounds, first-locale callbacks release format/parse input,8 concurrent cache publishers, joined-worker copy snapshots and source pin, constructor rollback, guarded storage,32 isa replacements,192 concurrent roundtrips and two drained runtimes')
}
fn test_date_formatter_rejections() {
	objc_start(); system_data_start()!; api := date_formatter_runtime_api()
	for selector in [c'calendar', c'setCalendar:', c'encodeWithCoder:', c'initWithCoder:', c'setLocalizedDateFormatFromTemplate:', c'monthSymbols', c'twoDigitStartDate', c'mutableCopy']! { assert !objc_responds(api.cls('NSDateFormatter'), selector) }
	modes := ['pattern', 'style', 'time-style', 'behavior', 'context', 'lenient', 'relative', 'calendar-dates', 'natural-language', 'default-date', 'default-zone-getter', 'calendar', 'coding', 'template', 'symbols', 'mutable-copy', 'subclass', 'caller-subclass', 'spoof', 'isa-change', 'copy-provenance', 'format-object', 'format-class', 'format-custom', 'format-spoof', 'parse-object', 'date-object', 'date-raw', 'date-spoof', 'date-isa', 'locale-object', 'locale-raw', 'locale-unsupported', 'locale-nil-id', 'zone-object', 'zone-raw', 'zone-named', 'zone-abbreviation', 'date-low', 'date-high', 'destruct-active', 'raw-format', 'raw-locale', 'raw-zone', 'format-copy-fail']!
	for mode in modes {
		mut fds := [2]i32{}; assert C.pipe(unsafe { &fds[0] }) == 0
		pid := C.ios_fork(); assert pid >= 0
		if pid == 0 {
			C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1])
			pool := api.pool(); object := api.formatter('yyyy-MM-dd', 0)
			match mode {
				'format-copy-fail' {
					value := api.string('yyyy-MM-dd')
					assert objc_add_method(api.cls('NSString'), u64(c'.cxx_construct'), u64(unsafe { voidptr(date_formatter_string_constructor) }), c'@16@0:8')
					date_formatter_callback_mode = 'string-fail'; api.message(object, c'setDateFormat:', value, 0, 0)
				}
				'raw-format', 'raw-locale', 'raw-zone' {
					raw := api.message(api.cls('NSDateFormatter'), c'alloc', 0, 0, 0)
					selector := match mode { 'raw-format' { c'setDateFormat:' } 'raw-locale' { c'setLocale:' } else { c'setTimeZone:' } }
					value := match mode { 'raw-format' { api.string('yyyy-MM-dd') } 'raw-locale' { api.locale('en_US_POSIX') } else { api.zone(0) } }
					api.message(raw, selector, value, 0, 0)
				}
				'pattern' { api.format(object, 'yyyy') }
				'style', 'time-style', 'behavior', 'context', 'lenient', 'relative', 'calendar-dates', 'natural-language', 'default-date' {
					selector := match mode { 'style' { c'setDateStyle:' } 'time-style' { c'setTimeStyle:' } 'behavior' { c'setFormatterBehavior:' } 'context' { c'setFormattingContext:' } 'lenient' { c'setLenient:' } 'relative' { c'setDoesRelativeDateFormatting:' } 'calendar-dates' { c'setGeneratesCalendarDates:' } 'natural-language' { c'setAllowsNaturalLanguage:' } else { c'setDefaultDate:' } }
					api.message(object, selector, 1, 0, 0)
				}
				'default-zone-getter' { api.message(object, c'setTimeZone:', 0, 0, 0); api.message(object, c'timeZone', 0, 0, 0) }
				'calendar', 'coding', 'template', 'symbols', 'mutable-copy' {
					selector := match mode { 'calendar' { c'calendar' } 'coding' { c'initWithCoder:' } 'template' { c'setLocalizedDateFormatFromTemplate:' } 'symbols' { c'monthSymbols' } else { c'mutableCopy' } }; api.message(object, selector, 0, 0, 0)
				}
				'subclass', 'caller-subclass' {
					cls := objc_allocate_class(api.cls('NSDateFormatter'), c'VinixUnsupportedDateFormatter', 0); objc_register_class(cls)
					if mode == 'subclass' { objc_allocate(cls) } else { mut bytes := [7]u64{}; objc_construct_instance(cls, u64(unsafe { &bytes[0] })) }
				}
				'spoof' { value := objc_new(api.cls('NSObject')); objc_set_class(value, api.cls('NSDateFormatter')); api.message(value, c'dateFormat', 0, 0, 0) }
				'isa-change' { objc_set_class(object, api.cls('NSFormatter')); api.message(object, c'copy', 0, 0, 0) }
				'copy-provenance' { objc_set_class(object, api.cls('NSURLRequest')); objc_copy_value(object, false) }
				'format-object', 'format-class', 'format-custom', 'format-spoof', 'parse-object' {
					mut value := if mode == 'format-class' { api.cls('NSString') } else if mode in ['format-custom', 'format-spoof']! { owned_string('yyyy-MM-dd') } else { objc_new(api.cls('NSObject')) }
					if mode == 'format-custom' { cls := objc_allocate_class(api.cls('NSString'), c'VinixUnsupportedFormatterString', 0); objc_register_class(cls); objc_set_class(value, cls) }
					if mode == 'format-spoof' { value = objc_new(api.cls('NSObject')); objc_set_class(value, api.cls('NSString')) }
					api.message(object, if mode == 'parse-object' { c'dateFromString:' } else { c'setDateFormat:' }, value, 0, 0)
				}
				'date-object', 'date-raw', 'date-spoof', 'date-isa' {
					value := if mode == 'date-raw' { objc_allocate(api.cls('NSDate')) } else if mode == 'date-isa' { api.date(0) } else { objc_new(api.cls('NSObject')) }
					if mode == 'date-spoof' { objc_set_class(value, cf_date_id()) }; if mode == 'date-isa' { objc_set_class(value, api.cls('NSObject')) }
					api.message(object, c'stringFromDate:', value, 0, 0)
				}
				'locale-object', 'locale-raw' { api.message(object, c'setLocale:', objc_allocate(api.cls(if mode == 'locale-raw' { 'NSLocale' } else { 'NSObject' })), 0, 0) }
				'locale-unsupported', 'locale-nil-id' { api.message(api.cls('NSLocale'), c'localeWithLocaleIdentifier:', if mode == 'locale-nil-id' { u64(0) } else { api.string('fr_FR') }, 0, 0) }
				'zone-object', 'zone-raw' { api.message(object, c'setTimeZone:', objc_allocate(api.cls(if mode == 'zone-raw' { 'NSTimeZone' } else { 'NSObject' })), 0, 0) }
				'zone-named', 'zone-abbreviation' { api.message(api.cls('NSTimeZone'), if mode == 'zone-named' { c'timeZoneWithName:' } else { c'timeZoneWithAbbreviation:' }, api.string(if mode == 'zone-named' { 'Europe/Moscow' } else { 'PST' }), 0, 0) }
				'date-low', 'date-high' { api.output(object, if mode == 'date-low' { -12219292801.0 } else { 253402300800.0 }) }
				'destruct-active' {
					date_formatter_callback_mode = 'destruct'; date_formatter_callback_source = object
					assert objc_add_method(api.cls('NSDateFormatter'), u64(c'.cxx_construct'), u64(unsafe { voidptr(date_formatter_constructor) }), c'@16@0:8')
					api.message(object, c'copy', 0, 0, 0)
				}
				else {}
			}
			api.drain(pool); C._exit(0)
		}
		C.close(fds[1]); mut bytes := [16384]u8{}; mut length := 0
		for { assert length < bytes.len; count := C.read(fds[0], unsafe { &bytes[length] }, usize(bytes.len - length)); if count == 0 { break }; if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }; assert count > 0; length += int(count) }
		C.close(fds[0]); mut status := i32(0); assert C.ios_waitpid(pid, &status, 0) == pid
		output := unsafe { tos(&bytes[0], length) }
		assert status == 256 && output.contains('iOS:') && !output.contains('AddressSanitizer') && !output.contains('runtime error:'), mode + ': ' + output
	}
	objc_stop(); system_data_stop()
	println('IOS-DATE-FORMATTER-REJECT:45 unsupported patterns/options/coding/templates/styles, raw setters, subclasses/provenance, property types, failed format copying, named zones, calendar bounds and active destruction fail explicitly')
}

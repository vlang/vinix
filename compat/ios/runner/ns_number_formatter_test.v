// SPDX-License-Identifier: GPL-2.0-or-later
module main

import math

$if macos {
	#flag -framework Foundation
	#include <objc/runtime.h>
}
#include <dlfcn.h>
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.class_getInstanceMethod(voidptr, voidptr) voidptr
fn C.method_getTypeEncoding(voidptr) &char
fn C.class_getInstanceSize(voidptr) usize
fn C.class_getSuperclass(voidptr) voidptr
fn C.objc_storeWeak(&u64, voidptr) voidptr

type NumberFormatterSend = fn (u64, u64, u64, u64, u64) u64
type NumberFormatterRealSend = fn (u64, u64, f64) u64
type NumberFormatterRealGet = fn (u64, u64) f64
struct NumberFormatterApi { native bool send u64 }
fn (api NumberFormatterApi) cls(name string) u64 {
	$if macos { if api.native { return u64(C.objc_getClass(name.str)) } }
	return ios_runtime.names[name]
}
fn (api NumberFormatterApi) selector(name &char) u64 {
	$if macos { if api.native { return u64(C.sel_registerName(name)) } }
	return u64(name)
}
fn (api NumberFormatterApi) message(object u64, name &char, a u64, b u64, c u64) u64 {
	return unsafe { NumberFormatterSend(voidptr(api.send))(object, api.selector(name), a, b, c) }
}
fn (api NumberFormatterApi) string(value string) u64 { return api.message(api.cls('NSString'), c'stringWithUTF8String:', u64(value.str), 0, 0) }
fn (api NumberFormatterApi) text(object u64) string {
	assert object != 0
	pointer := api.message(object, c'UTF8String', 0, 0, 0); assert pointer != 0
	return unsafe { (&char(voidptr(pointer))).vstring() }
}
fn (api NumberFormatterApi) number(value f64) u64 {
	$if macos { if api.native { return unsafe { NumberFormatterRealSend(voidptr(api.send))(api.cls('NSNumber'), api.selector(c'numberWithDouble:'), value) } } }
	object := objc_allocate(api.cls('NSNumber')); mut header := obj_header(object)
	header.is_real = true; header.real_number = value
	return objc_autorelease(object)
}
fn (api NumberFormatterApi) integer(value u64, unsigned bool) u64 {
	$if macos { if api.native { return api.message(api.cls('NSNumber'), if unsigned { c'numberWithUnsignedLongLong:' } else { c'numberWithLongLong:' }, value, 0, 0) } }
	object := objc_allocate(api.cls('NSNumber')); mut header := obj_header(object)
	header.number = i64(value); header.unsigned_number = unsigned
	return objc_autorelease(object)
}
fn (api NumberFormatterApi) real(number u64) f64 {
	$if macos { if api.native { return unsafe { NumberFormatterRealGet(voidptr(api.send))(number, api.selector(c'doubleValue')) } } }
	return json_number_double(obj_header(number))
}
fn (api NumberFormatterApi) pool() u64 {
	$if macos { if api.native { return api.message(api.cls('NSAutoreleasePool'), c'new', 0, 0, 0) } }
	return objc_pool_push()
}
fn (api NumberFormatterApi) drain(pool u64) {
	$if macos { if api.native { api.message(pool, c'drain', 0, 0, 0); return } }
	objc_pool_pop(pool)
}
fn (api NumberFormatterApi) weak(slot &u64, object u64) {
	$if macos { if api.native { C.objc_storeWeak(slot, unsafe { voidptr(object) }); return } }
	objc_store_weak(slot, object)
}
fn (api NumberFormatterApi) destroy_weak(slot &u64) {
	$if macos { if api.native { C.objc_storeWeak(slot, unsafe { nil }); return } }
	objc_destroy_weak(slot)
}
fn (api NumberFormatterApi) locale(identifier string) u64 { return api.message(api.cls('NSLocale'), c'localeWithLocaleIdentifier:', api.string(identifier), 0, 0) }
fn (api NumberFormatterApi) formatter(identifier string, style u64) u64 {
	object := api.message(api.cls('NSNumberFormatter'), c'new', 0, 0, 0)
	api.message(object, c'setLocale:', api.locale(identifier), 0, 0)
	api.message(object, c'setNumberStyle:', style, 0, 0)
	return object
}
fn (api NumberFormatterApi) output(object u64, value f64) string { return api.text(api.message(object, c'stringFromNumber:', api.number(value), 0, 0)) }
fn number_formatter_metadata(api NumberFormatterApi) {
	cls := api.cls('NSNumberFormatter'); parent := api.cls('NSFormatter')
	$if macos { if api.native { assert C.class_getInstanceSize(unsafe { voidptr(cls) }) == 64 && u64(C.class_getSuperclass(unsafe { voidptr(cls) })) == parent && C.class_getInstanceSize(unsafe { voidptr(parent) }) == 8 } }
	if !api.native { assert objc_class_size(cls) == 64 && objc_class_parent(cls) == parent && objc_class_size(parent) == 8 && objc_class_parent(parent) == api.cls('NSObject') }
	for name, types in {
		'init': '@16@0:8', 'copyWithZone:': '@24@0:8^{_NSZone=}16',
		'locale': '@16@0:8', 'setLocale:': 'v24@0:8@16',
		'stringFromNumber:': '@24@0:8@16', 'numberFromString:': '@24@0:8@16', 'stringForObjectValue:': '@24@0:8@16',
		'numberStyle': 'Q16@0:8', 'setNumberStyle:': 'v24@0:8Q16',
		'minimumIntegerDigits': 'Q16@0:8', 'setMinimumIntegerDigits:': 'v24@0:8Q16',
		'maximumIntegerDigits': 'Q16@0:8', 'setMaximumIntegerDigits:': 'v24@0:8Q16',
		'minimumFractionDigits': 'Q16@0:8', 'setMinimumFractionDigits:': 'v24@0:8Q16',
		'maximumFractionDigits': 'Q16@0:8', 'setMaximumFractionDigits:': 'v24@0:8Q16',
		'groupingSize': 'Q16@0:8', 'setGroupingSize:': 'v24@0:8Q16',
		'roundingMode': 'Q16@0:8', 'setRoundingMode:': 'v24@0:8Q16',
		'formatterBehavior': 'Q16@0:8', 'setFormatterBehavior:': 'v24@0:8Q16',
		'formattingContext': 'q16@0:8', 'setFormattingContext:': 'v24@0:8q16',
		'allowsFloats': 'B16@0:8', 'setAllowsFloats:': 'v20@0:8B16',
		'usesGroupingSeparator': 'B16@0:8', 'setUsesGroupingSeparator:': 'v20@0:8B16',
		'decimalSeparator': '@16@0:8', 'negativeInfinitySymbol': '@16@0:8',
	} {
		mut actual := ''
		$if macos { if api.native { method := C.class_getInstanceMethod(unsafe { voidptr(cls) }, unsafe { voidptr(api.selector(name.str)) }); assert method != unsafe { nil }; actual = unsafe { C.method_getTypeEncoding(method).vstring() } } }
		if !api.native { method := objc_instance_method(cls, u64(name.str)); assert method != 0; actual = ctext(u64(objc_method_types(method))) }
		assert actual == types, name + ': ' + actual
	}
}
fn number_formatter_shared(api NumberFormatterApi) {
	pool := api.pool(); number_formatter_metadata(api)
	for identifier in ['en_US_POSIX', 'en_US', 'en_GB']! {
		for style in [u64(0), 1]! {
			object := api.formatter(identifier, style); posix := identifier == 'en_US_POSIX'
			assert api.message(object, c'classForCoder', 0, 0, 0) == api.cls('NSNumberFormatter')
			assert api.message(object, c'numberStyle', 0, 0, 0) == style
			assert api.message(object, c'minimumIntegerDigits', 0, 0, 0) == 1
			assert api.message(object, c'maximumIntegerDigits', 0, 0, 0) == if style == 0 { u64(42) } else { u64(2000000000) }
			assert api.message(object, c'minimumFractionDigits', 0, 0, 0) == 0
			assert api.message(object, c'maximumFractionDigits', 0, 0, 0) == if style == 0 { u64(0) } else if posix { u64(6) } else { u64(3) }
			assert api.message(object, c'usesGroupingSeparator', 0, 0, 0) == u64(style == 1 && !posix)
			assert api.message(object, c'groupingSize', 0, 0, 0) == if style == 1 && !posix { u64(3) } else { u64(0) }
			assert api.message(object, c'roundingMode', 0, 0, 0) == 4 && api.message(object, c'allowsFloats', 0, 0, 0) == 1
			assert api.message(object, c'stringFromNumber:', 0, 0, 0) == 0
			assert api.text(api.message(object, c'stringForObjectValue:', 0, 0, 0)) == ''
			assert api.message(object, c'stringForObjectValue:', api.string('abc'), 0, 0) == 0
			for selector in [c'formatterBehavior', c'formattingContext', c'isLenient', c'usesSignificantDigits', c'generatesDecimalNumbers', c'alwaysShowsDecimalSeparator', c'zeroSymbol']! { assert api.message(object, selector, 0, 0, 0) == 0 }
			for selector in [c'setFormatterBehavior:', c'setFormattingContext:', c'setLenient:', c'setUsesSignificantDigits:', c'setGeneratesDecimalNumbers:', c'setAlwaysShowsDecimalSeparator:']! { api.message(object, selector, 0, 0, 0) }
			for selector, expected in {'decimalSeparator': '.', 'groupingSeparator': ',', 'positivePrefix': '', 'negativePrefix': '-', 'positiveSuffix': '', 'negativeSuffix': '', 'nilSymbol': '', 'notANumberSymbol': 'NaN', 'positiveInfinitySymbol': '+∞', 'negativeInfinitySymbol': '-∞'} { assert api.text(api.message(object, selector.str, 0, 0, 0)) == expected }
			assert api.output(object, -0.0) == '-0' && api.output(object, 0) == '0'
			assert api.output(object, 12345.6789) == if style == 0 { '12346' } else if posix { '12345.6789' } else { '12,345.679' }
			assert api.output(object, math.inf(1)) == '+∞' && api.output(object, math.inf(-1)) == '-∞' && api.output(object, math.nan()) == 'NaN'
			api.message(object, c'release', 0, 0, 0)
		}
	}
	object := api.formatter('en_US_POSIX', 0)
	for value, expected in { '2.5': '2', '3.5': '4', '-2.5': '-2', '12.5': '12' } { assert api.output(object, value.f64()) == expected }
	api.message(object, c'setMinimumFractionDigits:', 5, 0, 0); api.message(object, c'setNumberStyle:', 1, 0, 0)
	assert api.message(object, c'maximumFractionDigits', 0, 0, 0) == 6
	api.message(object, c'setNumberStyle:', 0, 0, 0); assert api.message(object, c'maximumFractionDigits', 0, 0, 0) == 5
	api.message(object, c'setMinimumFractionDigits:', 0, 0, 0); api.message(object, c'setNumberStyle:', 1, 0, 0)
	api.message(object, c'setMaximumFractionDigits:', 2, 0, 0)
	for value, expected in { '2.675': '2.68', '1.005': '1', '9.995': '10', '99.995': '100', '999.995': '1000', '-0.005': '-0', '0.005': '0', '0.015': '0.02', '0.125': '0.12', '0.375': '0.38' } { assert api.output(object, value.f64()) == expected, value }
	api.message(object, c'setMinimumIntegerDigits:', 4, 0, 0); api.message(object, c'setMinimumFractionDigits:', 2, 0, 0)
	assert api.output(object, 99.995) == '0100.00' && api.output(object, 0.001) == '0000.00'
	api.message(object, c'setMaximumIntegerDigits:', 2, 0, 0); api.message(object, c'setMinimumIntegerDigits:', 0, 0, 0)
	api.message(object, c'setMinimumFractionDigits:', 0, 0, 0)
	assert api.output(object, 12345.67) == '45.67' && api.output(object, 0.5) == '.5' && api.output(object, 0) == '0'
	api.message(object, c'release', 0, 0, 0)
	exact := api.formatter('en_US_POSIX', 1)
	for value, expected in { u64(9223372036854775807): '9223372036854775807', u64(9223372036854775808): '9223372036854775808', u64(-1): '18446744073709551615' } { assert api.text(api.message(exact, c'stringFromNumber:', api.integer(value, true), 0, 0)) == expected }
	assert api.text(api.message(exact, c'stringFromNumber:', api.integer(u64(9223372036854775808), false), 0, 0)) == '-9223372036854775808'
	for text, expected in { ' 12 ': 12.0, '-0': 0.0, '12.50': 12.5, '1e3': 1000.0, '.5': 0.5, '-1.25e-2': -0.0125 } {
		value := api.message(exact, c'numberFromString:', api.string(text), 0, 0); assert value != 0 && api.real(value) == expected, text
	}
	assert api.real(api.message(exact, c'numberFromString:', api.string('-∞'), 0, 0)) == math.inf(-1)
	for text in ['', '12abc', '+12', '1,234.5', '12,34', 'nan', '∞', '1e', '--1', '.', '1.2.3']! { assert api.message(exact, c'numberFromString:', api.string(text), 0, 0) == 0, text }
	api.message(exact, c'setUsesGroupingSeparator:', 1, 0, 0); api.message(exact, c'setGroupingSize:', 3, 0, 0)
	assert api.output(exact, 1234567.5) == '1,234,567.5'
	assert api.real(api.message(exact, c'numberFromString:', api.string('1,234,567.5'), 0, 0)) == 1234567.5
	assert api.message(exact, c'numberFromString:', api.string('12,34.5'), 0, 0) == 0
	api.message(exact, c'release', 0, 0, 0)
	api.drain(pool)
	inner := api.pool(); source := api.formatter('en_US_POSIX', 1); mut weak := u64(0)
	api.weak(unsafe { &weak }, source); copy := api.message(source, c'copyWithZone:', 0, 0, 0)
	assert copy != 0 && copy != source; api.message(source, c'setMaximumFractionDigits:', 1, 0, 0)
	assert api.output(source, 1.25) == '1.2' && api.output(copy, 1.25) == '1.25'
	api.message(source, c'release', 0, 0, 0); assert weak == 0; api.destroy_weak(unsafe { &weak }); api.drain(inner)
	outer := api.pool(); assert api.output(copy, 12345.5) == '12345.5'
	assert api.text(api.message(api.message(copy, c'locale', 0, 0, 0), c'localeIdentifier', 0, 0, 0)) == 'en_US_POSIX'
	assert api.message(copy, c'init', 0, 0, 0) == copy && api.output(copy, 1.25) == '1'
	assert api.message(copy, c'numberStyle', 0, 0, 0) == 0 && api.message(copy, c'maximumFractionDigits', 0, 0, 0) == 0
	assert api.message(copy, c'locale', 0, 0, 0) == api.message(api.cls('NSLocale'), c'currentLocale', 0, 0, 0)
	api.message(copy, c'release', 0, 0, 0); api.drain(outer)
}
fn test_number_formatter_native() {
	$if macos { number_formatter_shared(NumberFormatterApi{native: true, send: u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend'))}); println('IOS-NUMBER-FORMATTER-NATIVE: metadata, English no-style/decimal defaults, half-even rounding, grouping, padding, exact integers, parsing and independent copies') }
}
fn number_formatter_runtime_api() NumberFormatterApi { return NumberFormatterApi{send: u64(unsafe { voidptr(C.ios_objc_msgsend) })} }
__global number_formatter_callback_mode = ''
__global number_formatter_callback_source = u64(0)
__global number_formatter_callback_fired = false
__global number_formatter_callback_weak = u64(0)
__global number_formatter_callback_property_weak = u64(0)
fn number_formatter_callback_worker() {
	api := number_formatter_runtime_api(); pool := api.pool()
	C.ios_objc_initialize_lock(); C.ios_objc_initialize_unlock()
	if number_formatter_callback_mode == 'copy' {
		source := number_formatter_callback_source
		assert api.output(source, 12345.6789) == '12345.6789'
		api.message(source, c'setMaximumFractionDigits:', 1, 0, 0); api.message(source, c'setLocale:', api.locale('en_GB'), 0, 0); objc_release(source)
	}
	if number_formatter_callback_mode == 'locale-input' { objc_release(number_formatter_callback_source) }
	api.drain(pool)
}
fn number_formatter_constructor(object u64, selector &char) u64 {
	if number_formatter_callback_mode == '' { return object }
	number_formatter_callback_fired = true
	if number_formatter_callback_mode == 'destruct' { objc_destruct_instance(number_formatter_callback_source); return object }
	worker := spawn number_formatter_callback_worker(); worker.wait()
	if number_formatter_callback_mode == 'fail' {
		api := number_formatter_runtime_api(); api.message(object, c'init', 0, 0, 0)
		locale := api.message(api.message(api.cls('NSLocale'), c'alloc', 0, 0, 0), c'initWithLocaleIdentifier:', api.string('en_GB'), 0, 0)
		api.message(object, c'setLocale:', locale, 0, 0); objc_release(locale)
		objc_store_weak(unsafe { &number_formatter_callback_weak }, object)
		objc_store_weak(unsafe { &number_formatter_callback_property_weak }, obj_header(object).fields[0]); return 0
	}
	return object
}
fn number_formatter_locale_constructor(object u64, selector &char) u64 {
	if number_formatter_callback_mode != 'locale-input' { return object }
	number_formatter_callback_fired = true; worker := spawn number_formatter_callback_worker(); worker.wait(); return object
}
fn number_formatter_reader_worker(object u64) {
	api := number_formatter_runtime_api(); pool := api.pool()
	for _ in 0 .. 32 {
		assert api.output(object, 12345.6789) == '12345.6789'
		value := api.message(object, c'numberFromString:', api.string('12345.6789'), 0, 0); assert value != 0 && api.real(value) == 12345.6789
	}
	api.drain(pool)
}
fn number_formatter_runtime_lifetimes(api NumberFormatterApi) {
	pool := api.pool(); cls := api.cls('NSNumberFormatter')
	assert objc_add_method(cls, u64(c'.cxx_construct'), u64(unsafe { voidptr(number_formatter_constructor) }), c'@16@0:8')
	source := api.formatter('en_US_POSIX', 1); mut weak := u64(0); objc_store_weak(unsafe { &weak }, source)
	number_formatter_callback_mode = 'copy'; number_formatter_callback_source = source; number_formatter_callback_fired = false
	copy := api.message(source, c'copy', 0, 0, 0); number_formatter_callback_mode = ''; number_formatter_callback_source = 0
	assert copy != 0 && weak == 0 && number_formatter_callback_fired && api.output(copy, 12345.6789) == '12345.6789'
	objc_destroy_weak(unsafe { &weak }); objc_release(copy)
	valid := api.formatter('en_US_POSIX', 1); number_formatter_callback_mode = 'fail'
	assert api.message(cls, c'new', 0, 0, 0) == 0 && number_formatter_callback_weak == 0 && number_formatter_callback_property_weak == 0
	objc_destroy_weak(unsafe { &number_formatter_callback_weak }); objc_destroy_weak(unsafe { &number_formatter_callback_property_weak })
	assert api.message(valid, c'copy', 0, 0, 0) == 0 && number_formatter_callback_weak == 0 && number_formatter_callback_property_weak == 0
	objc_destroy_weak(unsafe { &number_formatter_callback_weak }); objc_destroy_weak(unsafe { &number_formatter_callback_property_weak })
	mut failed := [10]u64{}; failed[0] = 0x1122334455667788; failed[9] = 0x8877665544332211
	assert objc_construct_instance(cls, u64(unsafe { &failed[1] })) == 0 && number_formatter_callback_weak == 0 && number_formatter_callback_property_weak == 0
	objc_destroy_weak(unsafe { &number_formatter_callback_weak }); objc_destroy_weak(unsafe { &number_formatter_callback_property_weak })
	assert failed[0] == 0x1122334455667788 && failed[9] == 0x8877665544332211 && failed[1] == cls
	number_formatter_callback_mode = ''; objc_release(valid)
	mut guarded := [10]u64{}; guarded[0] = 0x1122334455667788; guarded[9] = 0x8877665544332211
	caller := u64(unsafe { &guarded[1] }); assert objc_construct_instance(cls, caller) == caller
	api.message(caller, c'init', 0, 0, 0); assert api.output(caller, 12.5) == '12'
	assert objc_set_class(caller, api.cls('NSObject')) == cls && objc_destruct_instance(caller) == caller
	assert caller !in ios_runtime.objects && guarded[0] == 0x1122334455667788 && guarded[9] == 0x8877665544332211
	for _ in 0 .. 32 { object := api.formatter('en_US_POSIX', 1); assert objc_set_class(object, api.cls('NSObject')) == cls; objc_release(object) }
	concurrent := api.formatter('en_US_POSIX', 1); mut readers := []thread{cap: 6}
	for _ in 0 .. 6 { readers << spawn number_formatter_reader_worker(concurrent) }; readers.wait(); unsafe { readers.free() }; objc_release(concurrent)
	api.drain(pool)
}
fn number_formatter_initial_callbacks(api NumberFormatterApi) {
	assert ios_runtime.locale == 0
	assert objc_add_method(api.cls('NSLocale'), u64(c'.cxx_construct'), u64(unsafe { voidptr(number_formatter_locale_constructor) }), c'@16@0:8')
	for parse in [false, true]! {
		pool := api.pool()
		object := api.message(api.cls('NSNumberFormatter'), c'new', 0, 0, 0)
		input := if parse { owned_string('12.5') } else { objc_allocate(api.cls('NSNumber')) }
		if !parse { mut header := obj_header(input); header.is_real = true; header.real_number = 12.5 }
		mut weak := u64(0); objc_store_weak(unsafe { &weak }, input)
		number_formatter_callback_mode = 'locale-input'; number_formatter_callback_source = input; number_formatter_callback_fired = false
		result := api.message(object, if parse { c'numberFromString:' } else { c'stringFromNumber:' }, input, 0, 0)
		number_formatter_callback_mode = ''; number_formatter_callback_source = 0
		assert result != 0 && weak == 0 && number_formatter_callback_fired
		if parse { assert api.real(result) == 12.5 } else { assert api.text(result) == '12' }
		objc_destroy_weak(unsafe { &weak }); objc_release(object)
		locale := ios_runtime.locale; ios_runtime.locale = 0; objc_release(locale)
		api.drain(pool)
	}
}
fn test_number_formatter_runtime() {
	for _ in 0 .. 2 {
		objc_start(); system_data_start()!; api := number_formatter_runtime_api(); number_formatter_initial_callbacks(api)
		number_formatter_shared(api); number_formatter_runtime_lifetimes(api)
		locale := ios_runtime.locale; assert locale != 0 && ios_runtime.live == 2 && ios_runtime.objects.len == 2 && ios_runtime.weak.len == 0
		assert obj_header(locale).refs == 1 && obj_header(obj_header(locale).fields[0]).refs == 1
		api.pool(); objc_autorelease(api.formatter('en_US_POSIX', 1)); objc_stop()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0; system_data_stop()
	}
	println('IOS-NUMBER-FORMATTER: input snapshots across first-locale callbacks, joined-worker copy/source pin, constructor rollback, guarded storage,32 isa replacements,192 concurrent roundtrips and two drained runtimes')
}
fn test_number_formatter_rejections() {
	objc_start(); system_data_start()!; api := number_formatter_runtime_api()
	for selector in [c'mutableCopy', c'initWithCoder:', c'encodeWithCoder:', c'multiplier', c'setDecimalSeparator:', c'secondaryGroupingSize']! { assert !objc_responds(api.cls('NSNumberFormatter'), selector) }
	modes := ['style', 'rounding', 'min-integer', 'max-integer', 'min-fraction', 'max-fraction', 'group', 'floats', 'behavior', 'context', 'lenient', 'significant', 'decimal', 'always', 'mutable-copy', 'coding', 'symbol', 'multiplier', 'subclass', 'caller-subclass', 'spoof', 'isa-change', 'copy-provenance', 'number-object', 'number-isa', 'parse-object', 'locale-object', 'locale-raw', 'raw-setter', 'integer-overflow', 'precision', 'exponent', 'destruct-active']!
	for mode in modes {
		mut fds := [2]i32{}; assert C.pipe(unsafe { &fds[0] }) == 0; pid := C.ios_fork(); assert pid >= 0
		if pid == 0 {
			C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1]); pool := api.pool(); object := api.formatter('en_US_POSIX', 1)
			match mode {
				'style', 'rounding', 'min-integer', 'max-integer', 'min-fraction', 'max-fraction', 'group', 'floats', 'behavior', 'context', 'lenient', 'significant', 'decimal', 'always' {
					selector := match mode { 'style' { c'setNumberStyle:' } 'rounding' { c'setRoundingMode:' } 'min-integer' { c'setMinimumIntegerDigits:' } 'max-integer' { c'setMaximumIntegerDigits:' } 'min-fraction' { c'setMinimumFractionDigits:' } 'max-fraction' { c'setMaximumFractionDigits:' } 'group' { c'setGroupingSize:' } 'floats' { c'setAllowsFloats:' } 'behavior' { c'setFormatterBehavior:' } 'context' { c'setFormattingContext:' } 'lenient' { c'setLenient:' } 'significant' { c'setUsesSignificantDigits:' } 'decimal' { c'setGeneratesDecimalNumbers:' } else { c'setAlwaysShowsDecimalSeparator:' } }
					value := if mode == 'floats' { u64(0) } else if mode == 'style' { u64(2) } else if mode in ['min-integer', 'max-integer']! { u64(65) } else if mode in ['min-fraction', 'max-fraction', 'group']! { u64(17) } else { u64(1) }; api.message(object, selector, value, 0, 0)
				}
				'mutable-copy', 'coding', 'symbol', 'multiplier' { api.message(object, match mode { 'mutable-copy' { c'mutableCopy' } 'coding' { c'initWithCoder:' } 'symbol' { c'setDecimalSeparator:' } else { c'multiplier' } }, 0, 0, 0) }
				'subclass', 'caller-subclass' { cls := objc_allocate_class(api.cls('NSNumberFormatter'), c'VinixUnsupportedNumberFormatter', 0); objc_register_class(cls); if mode == 'subclass' { objc_allocate(cls) } else { mut bytes := [8]u64{}; objc_construct_instance(cls, u64(unsafe { &bytes[0] })) } }
				'spoof' { value := objc_new(api.cls('NSObject')); objc_set_class(value, api.cls('NSNumberFormatter')); api.message(value, c'numberStyle', 0, 0, 0) }
				'isa-change' { objc_set_class(object, api.cls('NSFormatter')); api.message(object, c'copy', 0, 0, 0) }
				'copy-provenance' { objc_set_class(object, api.cls('NSURLRequest')); objc_copy_value(object, false) }
				'number-object', 'number-isa' { value := if mode == 'number-isa' { api.number(1) } else { objc_new(api.cls('NSObject')) }; if mode == 'number-isa' { objc_set_class(value, api.cls('NSObject')) }; api.message(object, c'stringFromNumber:', value, 0, 0) }
				'parse-object' { api.message(object, c'numberFromString:', objc_new(api.cls('NSObject')), 0, 0) }
				'locale-object', 'locale-raw' { api.message(object, c'setLocale:', objc_allocate(api.cls(if mode == 'locale-raw' { 'NSLocale' } else { 'NSObject' })), 0, 0) }
				'raw-setter' { api.message(objc_allocate(api.cls('NSNumberFormatter')), c'setNumberStyle:', 1, 0, 0) }
				'integer-overflow', 'precision', 'exponent' { api.message(object, c'numberFromString:', api.string(if mode == 'integer-overflow' { '18446744073709551616' } else if mode == 'precision' { '1.234567890123456789' } else { '1e9999' }), 0, 0) }
				'destruct-active' { number_formatter_callback_mode = 'destruct'; number_formatter_callback_source = object; assert objc_add_method(api.cls('NSNumberFormatter'), u64(c'.cxx_construct'), u64(unsafe { voidptr(number_formatter_constructor) }), c'@16@0:8'); api.message(object, c'copy', 0, 0, 0) }
				else {}
			}
			api.drain(pool); C._exit(0)
		}
		C.close(fds[1]); mut bytes := [16384]u8{}; mut length := 0
		for { assert length < bytes.len; count := C.read(fds[0], unsafe { &bytes[length] }, usize(bytes.len - length)); if count == 0 { break }; if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }; assert count > 0; length += int(count) }
		C.close(fds[0]); mut status := i32(0); assert C.ios_waitpid(pid, &status, 0) == pid; output := unsafe { tos(&bytes[0], length) }
		assert status == 256 && output.contains('iOS:') && !output.contains('AddressSanitizer') && !output.contains('runtime error:'), mode + ': ' + output
	}
	objc_stop(); system_data_stop(); println('IOS-NUMBER-FORMATTER-REJECT:33 unsupported options, coding, subclasses, provenance, raw setters, parse bounds and active destruction fail explicitly')
}

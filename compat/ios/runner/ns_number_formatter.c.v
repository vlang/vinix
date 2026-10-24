// SPDX-License-Identifier: GPL-2.0-or-later
module main

import math
import strconv

// Measured English no-style/decimal profile. Native ivars are metadata only;
// settings and lifetime state belong to the allocation, including caller storage.
struct NumberFormatterSettings {
mut:
	style int
	minimum_integer int = 1
	maximum_integer int = -1
	minimum_fraction int
	maximum_fraction int = -1
	grouping int = -1
	group_size int = -1
	allows_floats bool = true
}

struct FoundationNumberFormatter {
mut:
	settings NumberFormatterSettings
	initialized bool
	calls u64
	retiring bool
}

fn ns_number_formatter_metadata() {
	mut cls := ios_runtime.classes[ios_runtime.names['NSNumberFormatter']] or { panic('iOS: missing NSNumberFormatter') }
	for i, pair in [['_attributes', '@"NSMutableDictionary"']!, ['_formatter', '^{__CFNumberFormatter=}']!, ['_counter', 'Q']!, ['_behavior', 'Q']!, ['_lock', '@"NSRecursiveLock"']!, ['_stateBitMask', 'Q']!, ['_cacheGeneration', 'q']!]! {
		cls.ivars[pair[0]] = &ObjIvar{name: pair[0].clone(), types: pair[1].clone(), offset: i64(8 + i * 8), size: 8}
	}
}

fn ns_number_formatter_family(cls u64) bool {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return false }
		if info.name == 'NSNumberFormatter' { return true }
		current = info.parent
		if current == 0 { return false }
	}
	panic('iOS: cyclic number formatter superclass chain')
}

fn ns_number_formatter_require_class(cls u64) {
	if ns_number_formatter_family(cls) && cls != ios_runtime.names['NSNumberFormatter'] {
		panic('iOS: custom number formatter subclass construction is not implemented')
	}
}

fn ns_number_formatter_install(cls u64, mut header ObjHeader) {
	if cls != ios_runtime.names['NSNumberFormatter'] { return }
	header.number_formatter = unsafe { &FoundationNumberFormatter(C.calloc(1, sizeof(FoundationNumberFormatter))) }
	if header.number_formatter == unsafe { nil } { panic('iOS: cannot allocate number formatter state') }
	unsafe { *header.number_formatter = FoundationNumberFormatter{} }
}

fn ns_number_formatter_state(object u64) &FoundationNumberFormatter {
	header := obj_header(object)
	state := header.number_formatter
	if state == unsafe { nil } || header.destroying || header.destroyed || state.retiring
		|| C.ios_ref_change(unsafe { &header.refs }, 0) <= 0
		|| header.native_size < 64 || header.cls != header.allocation_cls
		|| header.allocation_cls != ios_runtime.names['NSNumberFormatter'] || read64(object) != header.allocation_cls {
		panic('iOS: NSNumberFormatter requires live owned formatter storage')
	}
	return state
}

fn ns_number_formatter_retire(mut header ObjHeader) {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if header.number_formatter == unsafe { nil } { return }
	if header.number_formatter.calls != 0 { panic('iOS: destroying an active NSNumberFormatter') }
	header.number_formatter.retiring = true
}

fn ns_number_formatter_dispose(mut header ObjHeader) {
	state := header.number_formatter
	header.number_formatter = unsafe { nil }
	if state != unsafe { nil } { C.free(state) }
}

fn ns_number_formatter_finish(object u64) {
	C.ios_objc_initialize_lock()
	mut state := ns_number_formatter_state(object)
	if state.calls == 0 { panic('iOS: unbalanced number formatter call') }
	state.calls--
	C.ios_objc_initialize_unlock()
	objc_release(object)
}

fn ns_number_formatter_initialize(object u64) {
	C.ios_objc_initialize_lock()
	mut state := ns_number_formatter_state(object)
	// Apple resets settings and the explicit locale even on a second init.
	state.initialized = true
	state.settings = NumberFormatterSettings{}
	mut header := obj_header(object)
	old := header.fields[0]
	header.fields[0] = 0
	C.ios_objc_initialize_unlock()
	objc_release(old)
}

fn ns_number_formatter_copy(object u64) u64 {
	C.ios_objc_initialize_lock()
	mut state := ns_number_formatter_state(object)
	objc_retain(object); state.calls++
	defer { ns_number_formatter_finish(object) }
	settings := state.settings
	locale := objc_retain(obj_header(object).fields[0])
	C.ios_objc_initialize_unlock()
	// Constructors can reenter and mutate the source. Only the snapshot survives.
	copy := objc_allocate(ios_runtime.names['NSNumberFormatter'])
	if copy == 0 { objc_release(locale); return 0 }
	C.ios_objc_initialize_lock()
	mut target := ns_number_formatter_state(copy)
	// Releasing constructor-owned locale state can invoke application code.
	objc_retain(copy); target.calls++
	defer { ns_number_formatter_finish(copy) }
	target.settings = settings
	target.initialized = true
	mut header := obj_header(copy)
	old := header.fields[0]
	header.fields[0] = locale
	C.ios_objc_initialize_unlock()
	objc_release(old)
	return copy
}

fn ns_number_formatter_posix(locale u64) bool {
	ns_date_formatter_locale(locale)
	return ns_date_formatter_text(obj_header(locale).fields[0]) == 'en_US_POSIX'
}

fn ns_number_formatter_options(object u64) NumberFormatterSettings {
	C.ios_objc_initialize_lock()
	mut settings := ns_number_formatter_state(object).settings
	locale := obj_header(object).fields[0]
	mut posix := false
	if locale != 0 { posix = ns_number_formatter_posix(locale) }
	C.ios_objc_initialize_unlock()
	if locale == 0 {
		current := ns_locale_current()
		C.ios_objc_initialize_lock()
		posix = ns_number_formatter_posix(current)
		C.ios_objc_initialize_unlock()
	}
	if settings.maximum_integer == -1 { settings.maximum_integer = if settings.style == 0 { 42 } else { 2000000000 }; if settings.maximum_integer < settings.minimum_integer { settings.maximum_integer = settings.minimum_integer } }
	if settings.maximum_fraction == -1 { settings.maximum_fraction = if settings.style == 0 { 0 } else if posix { 6 } else { 3 }; if settings.maximum_fraction < settings.minimum_fraction { settings.maximum_fraction = settings.minimum_fraction } }
	if settings.grouping == -1 { settings.grouping = int(settings.style == 1 && !posix) }
	if settings.group_size == -1 { settings.group_size = if settings.style == 1 && !posix { 3 } else { 0 } }
	return settings
}

// Runs under the runtime lock. No borrowed number/string bytes escape a callback.
fn ns_number_formatter_digits(number u64) (string, bool) {
	header := ios_runtime.objects[number] or { panic('iOS: number formatter requires a built-in NSNumber') }
	if header.destroying || header.destroyed || header.allocation_cls != ios_runtime.names['NSNumber']
		|| read64(number) != header.allocation_cls { panic('iOS: number formatter requires live built-in number storage') }
	if header.is_real {
		value := header.real_number
		if !math.is_finite(value) { return (if math.is_nan(value) { 'NaN' } else if value < 0 { '-∞' } else { '+∞' }).clone(), false }
		// Decimal Ryu output preserves the shortest round-tripping mantissa.
		// Round that decimal, rather than multiplying a double across a tie.
		return strconv.ftoa_long_64(math.abs(value)), math.signbit(value)
	}
	negative := !header.unsigned_number && header.number < 0
	magnitude := if negative { u64(0) - u64(header.number) } else { u64(header.number) }
	return magnitude.str(), negative
}

fn ns_number_formatter_render(text string, negative bool, settings NumberFormatterSettings) u64 {
	if text in ['NaN', '+∞', '-∞']! { return owned_string(text) }
	mut digits := [768]u8{}
	mut count := 1
	mut integer := 0
	mut point := false
	for byte in text {
		if byte == `.` { point = true; continue }
		if byte < `0` || byte > `9` || count >= 740 { panic('iOS: number formatter decimal profile exceeded') }
		digits[count] = byte - `0`; count++
		if !point { integer++ }
	}
	mut end := 1 + integer + settings.maximum_fraction
	if end < count {
		mut rest := false
		for i in end + 1 .. count { rest = rest || digits[i] != 0 }
		round_up := digits[end] > 5 || (digits[end] == 5 && (rest || digits[end - 1] & 1 != 0))
		if round_up {
			mut i := end - 1
			for i > 0 && digits[i] == 9 { digits[i] = 0; i-- }
			digits[i]++
		}
	}
	mut start := 1
	if digits[0] != 0 { start = 0; integer++ }
	// Carry changes the decimal point but not the number of fractional places.
	for end > start + integer + settings.minimum_fraction && digits[end - 1] == 0 { end-- }
	if integer > settings.maximum_integer { start += integer - settings.maximum_integer; integer = settings.maximum_integer }
	mut nonzero := false
	for i in start .. end { nonzero = nonzero || digits[i] != 0 }
	if integer == 1 && digits[start] == 0 && settings.minimum_integer == 0 && nonzero { start++; integer-- }
	padding := if settings.minimum_integer > integer { settings.minimum_integer - integer } else { 0 }
	mut output := [1024]u8{}
	mut size := 0
	if negative { output[size] = `-`; size++ }
	whole := padding + integer
	for i in 0 .. whole {
		if i > 0 && settings.grouping != 0 && settings.group_size > 0 && (whole - i) % settings.group_size == 0 { output[size] = `,`; size++ }
		output[size] = if i < padding { u8(`0`) } else { digits[start + i - padding] + `0` }; size++
	}
	if end > start + integer {
		output[size] = `.`; size++
		for i in start + integer .. end { output[size] = digits[i] + `0`; size++ }
	}
	if size == int(negative) { output[size] = `0`; size++ }
	return owned_string(unsafe { tos(&output[0], size) })
}

struct NumberFormatterValue {
	magnitude u64
	negative bool
	real bool
	value f64
}

fn ns_number_formatter_parse(text string, settings NumberFormatterSettings) ?NumberFormatterValue {
	if text.len == 0 || text.len > 128 { return none }
	mut start := 0
	mut end := text.len
	for start < end && text[start] in [` `, `\t`, `\n`, `\r`]! { start++ }
	for end > start && text[end - 1] in [` `, `\t`, `\n`, `\r`]! { end-- }
	if start == end { return none }
	if end - start == 4 && text[start] == `-` && text[start + 1] == 0xe2
		&& text[start + 2] == 0x88 && text[start + 3] == 0x9e { return NumberFormatterValue{real: true, value: math.inf(-1)} }
	mut buffer := [129]u8{}
	mut size := 0
	negative := text[start] == `-`
	if negative { buffer[size] = `-`; size++; start++ }
	mut digits := 0
	mut group := 0
	mut separated := false
	mut real := false
	mut significant := 0
	mut magnitude := u64(0)
	mut overflow := false
	for start < end {
		byte := text[start]
		if byte >= `0` && byte <= `9` {
			buffer[size] = byte; size++; start++; digits++; group++
			if significant != 0 || byte != `0` { significant++ }
			digit := u64(byte - `0`)
			if magnitude > (u64(-1) - digit) / 10 { overflow = true } else { magnitude = magnitude * 10 + digit }
		} else if byte == `,` && settings.grouping != 0 && settings.group_size > 0 {
			if group == 0 || (!separated && group > settings.group_size) || (separated && group != settings.group_size) { return none }
			separated = true; group = 0; start++
		} else { break }
	}
	if separated && group != settings.group_size { return none }
	if start < end && text[start] == `.` && settings.allows_floats {
		real = true; buffer[size] = `.`; size++; start++
		for start < end && text[start] >= `0` && text[start] <= `9` {
			byte := text[start]; buffer[size] = byte; size++; start++; digits++
			if significant != 0 || byte != `0` { significant++ }
		}
	}
	if digits == 0 { return none }
	if start < end && text[start] in [`e`, `E`]! && settings.allows_floats {
		real = true; buffer[size] = `e`; size++; start++
		if start < end && text[start] in [`+`, `-`]! { buffer[size] = text[start]; size++; start++ }
		begin := start
		for start < end && text[start] >= `0` && text[start] <= `9` { buffer[size] = text[start]; size++; start++ }
		if start == begin { return none }
	}
	if start != end { return none }
	if real {
		if significant > 17 { panic('iOS: number formatter decimal precision profile exceeded') }
		value := C.strtod(unsafe { &char(&buffer[0]) }, unsafe { nil })
		if !math.is_finite(value) { panic('iOS: number formatter parsed exponent profile exceeded') }
		return NumberFormatterValue{real: true, value: value}
	}
	if overflow || (negative && magnitude > u64(1) << 63) { panic('iOS: number formatter integer profile exceeded') }
	return NumberFormatterValue{magnitude: magnitude, negative: negative}
}

fn ns_number_formatter_types(name string, meta bool, selector string) ?string {
	if name != 'NSNumberFormatter' { return none }
	if meta { return match selector { 'alloc', 'new' { '@16@0:8' } 'allocWithZone:' { '@24@0:8^{_NSZone=}16' } else { return none } } }
	return match selector {
		'init', 'copy', 'locale', 'decimalSeparator', 'groupingSeparator', 'positivePrefix', 'negativePrefix', 'positiveSuffix', 'negativeSuffix', 'nilSymbol', 'zeroSymbol', 'notANumberSymbol', 'positiveInfinitySymbol', 'negativeInfinitySymbol' { '@16@0:8' }
		'copyWithZone:' { '@24@0:8^{_NSZone=}16' }
		'stringFromNumber:', 'numberFromString:', 'stringForObjectValue:' { '@24@0:8@16' }
		'setLocale:' { 'v24@0:8@16' }
		'numberStyle', 'minimumIntegerDigits', 'maximumIntegerDigits', 'minimumFractionDigits', 'maximumFractionDigits', 'groupingSize', 'roundingMode', 'formatterBehavior' { 'Q16@0:8' }
		'setNumberStyle:', 'setMinimumIntegerDigits:', 'setMaximumIntegerDigits:', 'setMinimumFractionDigits:', 'setMaximumFractionDigits:', 'setGroupingSize:', 'setRoundingMode:', 'setFormatterBehavior:' { 'v24@0:8Q16' }
		'formattingContext' { 'q16@0:8' }
		'setFormattingContext:' { 'v24@0:8q16' }
		'allowsFloats', 'usesGroupingSeparator', 'isLenient', 'usesSignificantDigits', 'generatesDecimalNumbers', 'alwaysShowsDecimalSeparator' { 'B16@0:8' }
		'setAllowsFloats:', 'setUsesGroupingSeparator:', 'setLenient:', 'setUsesSignificantDigits:', 'setGeneratesDecimalNumbers:', 'setAlwaysShowsDecimalSeparator:' { 'v20@0:8B16' }
		'classForCoder' { '#16@0:8' }
		else { return none }
	}
}

fn ns_number_formatter_unsupported(selector string) bool {
	return selector in ['mutableCopy', 'mutableCopyWithZone:', 'initWithCoder:', 'encodeWithCoder:', 'supportsSecureCoding',
		'localizedStringFromNumber:numberStyle:', 'defaultFormatterBehavior', 'setDefaultFormatterBehavior:',
		'getObjectValue:forString:errorDescription:', 'getObjectValue:forString:range:error:',
		'editingStringForObjectValue:', 'attributedStringForObjectValue:withDefaultAttributes:',
		'multiplier', 'minimum', 'maximum', 'roundingIncrement', 'roundingBehavior', 'format', 'positiveFormat', 'negativeFormat',
		'currencyCode', 'currencySymbol', 'internationalCurrencySymbol', 'currencyDecimalSeparator', 'currencyGroupingSeparator',
		'exponentSymbol', 'percentSymbol', 'perMillSymbol', 'paddingCharacter', 'paddingPosition', 'formatWidth',
		'secondaryGroupingSize', 'minimumGroupingDigits', 'minimumSignificantDigits', 'maximumSignificantDigits',
		'hasThousandSeparators', 'thousandSeparator', 'localizesFormat', 'isPartialStringValidationEnabled']!
		|| (selector.starts_with('set') && ns_number_formatter_types('NSNumberFormatter', false, selector) == none)
}

fn ns_number_formatter_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	meta := object in ios_runtime.classes
	cls := if meta { object } else { read64(object) }
	mut formatter := ns_number_formatter_family(cls)
	if !meta {
		C.ios_objc_initialize_lock()
		if header := ios_runtime.objects[object] { formatter = formatter || header.number_formatter != unsafe { nil } }
		C.ios_objc_initialize_unlock()
	}
	if !formatter { return false }
	if ns_number_formatter_unsupported(selector) { panic('iOS: number formatter option is not implemented') }
	if ns_number_formatter_types('NSNumberFormatter', meta, selector) == none { return false }
	if meta { frame.x[0] = if selector == 'new' { objc_new(object) } else { objc_allocate(object) }; return true }
	C.ios_objc_initialize_lock()
	mut state := ns_number_formatter_state(object)
	objc_retain(object); state.calls++
	if selector.starts_with('set') && !state.initialized { panic('iOS: number formatter setters require init') }
	C.ios_objc_initialize_unlock()
	defer { ns_number_formatter_finish(object) }
	match selector {
		'init' { ns_number_formatter_initialize(object); frame.x[0] = object }
		'copy', 'copyWithZone:' { frame.x[0] = ns_number_formatter_copy(object) }
		'classForCoder' { frame.x[0] = ios_runtime.names['NSNumberFormatter'] }
		'locale' {
			C.ios_objc_initialize_lock(); mut value := objc_retain(obj_header(object).fields[0]); C.ios_objc_initialize_unlock()
			if value == 0 { value = objc_retain(ns_locale_current()) }
			frame.x[0] = objc_autorelease(value)
		}
		'setLocale:' {
			C.ios_objc_initialize_lock()
			value := if frame.x[2] == 0 { u64(0) } else { objc_retain(ns_date_formatter_locale(frame.x[2])) }
			mut header := obj_header(object); old := header.fields[0]; header.fields[0] = value
			C.ios_objc_initialize_unlock(); objc_release(old)
		}
		'stringFromNumber:', 'stringForObjectValue:' {
			if frame.x[2] == 0 { frame.x[0] = if selector == 'stringForObjectValue:' { objc_autorelease(owned_string('')) } else { u64(0) }; return true }
			C.ios_objc_initialize_lock()
			if selector == 'stringForObjectValue:' && (frame.x[2] !in ios_runtime.objects || obj_header(frame.x[2]).allocation_cls != ios_runtime.names['NSNumber']) {
				C.ios_objc_initialize_unlock(); frame.x[0] = 0; return true
			}
			text, negative := ns_number_formatter_digits(frame.x[2])
			C.ios_objc_initialize_unlock()
			settings := ns_number_formatter_options(object)
			frame.x[0] = objc_autorelease(ns_number_formatter_render(text, negative, settings))
			unsafe { text.free() }
		}
		'numberFromString:' {
			if frame.x[2] == 0 { frame.x[0] = 0; return true }
			C.ios_objc_initialize_lock(); text := ns_date_formatter_text(frame.x[2]).clone(); C.ios_objc_initialize_unlock()
			settings := ns_number_formatter_options(object)
			parsed := ns_number_formatter_parse(text, settings)
			unsafe { text.free() }
			if value := parsed {
				number := objc_allocate(ios_runtime.names['NSNumber']); mut header := obj_header(number)
				header.is_real = value.real; header.real_number = value.value
				header.number = if value.negative { i64(u64(0) - value.magnitude) } else { i64(value.magnitude) }
				header.unsigned_number = !value.negative && value.magnitude > u64(9223372036854775807)
				frame.x[0] = objc_autorelease(number)
			} else { frame.x[0] = 0 }
		}
		'decimalSeparator', 'groupingSeparator', 'positivePrefix', 'negativePrefix', 'positiveSuffix', 'negativeSuffix', 'nilSymbol', 'notANumberSymbol', 'positiveInfinitySymbol', 'negativeInfinitySymbol', 'zeroSymbol' {
			frame.x[0] = if selector == 'zeroSymbol' { u64(0) } else { objc_autorelease(owned_string(match selector { 'decimalSeparator' { '.' } 'groupingSeparator' { ',' } 'negativePrefix' { '-' } 'notANumberSymbol' { 'NaN' } 'positiveInfinitySymbol' { '+∞' } 'negativeInfinitySymbol' { '-∞' } else { '' } })) }
		}
		else {
			settings := ns_number_formatter_options(object)
			C.ios_objc_initialize_lock()
			mut current := ns_number_formatter_state(object)
			value := frame.x[2]
			match selector {
				'numberStyle' { frame.x[0] = u64(settings.style) }
				'minimumIntegerDigits' { frame.x[0] = u64(settings.minimum_integer) }
				'maximumIntegerDigits' { frame.x[0] = u64(settings.maximum_integer) }
				'minimumFractionDigits' { frame.x[0] = u64(settings.minimum_fraction) }
				'maximumFractionDigits' { frame.x[0] = u64(settings.maximum_fraction) }
				'usesGroupingSeparator' { frame.x[0] = u64(settings.grouping) }
				'groupingSize' { frame.x[0] = u64(settings.group_size) }
				'allowsFloats' { frame.x[0] = u64(settings.allows_floats) }
				'roundingMode' { frame.x[0] = 4 }
				'setNumberStyle:' { if value > 1 { panic('iOS: localized number styles are not implemented') }; current.settings.style = int(value) }
				'setMinimumIntegerDigits:' { if value > 64 { panic('iOS: number formatter integer digit profile exceeded') }; current.settings.minimum_integer = int(value); if current.settings.maximum_integer >= 0 && int(value) > current.settings.maximum_integer { current.settings.maximum_integer = int(value) } }
				'setMaximumIntegerDigits:' { if value == 0 || value > 64 { panic('iOS: number formatter integer digit profile exceeded') }; current.settings.maximum_integer = int(value); if int(value) < current.settings.minimum_integer { current.settings.minimum_integer = int(value) } }
				'setMinimumFractionDigits:' { if value > 16 { panic('iOS: number formatter fraction digit profile exceeded') }; current.settings.minimum_fraction = int(value); if current.settings.maximum_fraction >= 0 && int(value) > current.settings.maximum_fraction { current.settings.maximum_fraction = int(value) } }
				'setMaximumFractionDigits:' { if value > 16 { panic('iOS: number formatter fraction digit profile exceeded') }; current.settings.maximum_fraction = int(value); if int(value) < current.settings.minimum_fraction { current.settings.minimum_fraction = int(value) } }
				'setUsesGroupingSeparator:' { current.settings.grouping = int(value & 255 != 0) }
				'setGroupingSize:' { if value > 16 { panic('iOS: number formatter grouping profile exceeded') }; current.settings.group_size = int(value) }
				'setAllowsFloats:' { if value & 255 == 0 { panic('iOS: integer-only number parsing is not implemented') } }
				'setRoundingMode:' { if value != 4 { panic('iOS: number formatter rounding mode is not implemented') } }
				'setFormatterBehavior:', 'setFormattingContext:', 'setLenient:', 'setUsesSignificantDigits:', 'setGeneratesDecimalNumbers:', 'setAlwaysShowsDecimalSeparator:' { if value != 0 { panic('iOS: non-default number formatter option is not implemented') } }
				else { frame.x[0] = 0 }
			}
			C.ios_objc_initialize_unlock()
		}
	}
	return true
}

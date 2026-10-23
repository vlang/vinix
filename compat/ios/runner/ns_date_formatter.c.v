// SPDX-License-Identifier: GPL-2.0-or-later
module main

import math

// Fortnite's four POSIX/Gregorian formats. This is deliberately not an ICU
// replacement: other patterns, calendars and localized styles fail explicitly.
// Owned immutable settings live in ObjHeader.fields[0..3], not private ivars.
struct FoundationDateFormatter {
mut:
	format int
	initialized bool
	calls u64
	retiring bool
}

struct DateFormatterReader {
	text string
mut:
	pos int
}

fn ns_date_formatter_metadata() {
	mut cls := ios_runtime.classes[ios_runtime.names['NSDateFormatter']] or { panic('iOS: missing NSDateFormatter') }
	for i, pair in [['_attributes', '@"NSMutableDictionary"']!, ['_formatter', '^{__CFDateFormatter=}']!, ['_counter', 'Q']!, ['_cacheGeneration', 'q']!, ['_behavior', 'Q']!, ['_lock', '{os_unfair_lock_s="_os_unfair_lock_opaque"I}']!]! {
		cls.ivars[pair[0]] = &ObjIvar{name: pair[0].clone(), types: pair[1].clone(), offset: i64(8 + i * 8), size: if i == 5 { u64(4) } else { u64(8) }}
	}
}

fn ns_date_formatter_family(cls u64) bool {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return false }
		if info.name == 'NSDateFormatter' { return true }
		current = info.parent
		if current == 0 { return false }
	}
	panic('iOS: cyclic date formatter superclass chain')
}

fn ns_date_formatter_require_class(cls u64) {
	if ns_date_formatter_family(cls) && cls != ios_runtime.names['NSDateFormatter'] {
		panic('iOS: custom date formatter subclass construction is not implemented')
	}
}

fn ns_date_formatter_install(cls u64, mut header ObjHeader) {
	if cls != ios_runtime.names['NSDateFormatter'] { return }
	header.date_formatter = unsafe { &FoundationDateFormatter(C.calloc(1, sizeof(FoundationDateFormatter))) }
	if header.date_formatter == unsafe { nil } { panic('iOS: cannot allocate date formatter state') }
}

fn ns_date_formatter_state(object u64) &FoundationDateFormatter {
	header := obj_header(object)
	state := header.date_formatter
	if state == unsafe { nil } || header.destroying || header.destroyed || state.retiring
		|| C.ios_ref_change(unsafe { &header.refs }, 0) <= 0
		|| header.native_size < 56 || header.cls != header.allocation_cls || header.allocation_cls != ios_runtime.names['NSDateFormatter']
		|| read64(object) != header.allocation_cls {
		panic('iOS: NSDateFormatter requires live owned formatter storage')
	}
	return state
}

fn ns_date_formatter_retire(mut header ObjHeader) {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if header.date_formatter == unsafe { nil } { return }
	if header.date_formatter.calls != 0 { panic('iOS: destroying an active NSDateFormatter') }
	header.date_formatter.retiring = true
}

fn ns_date_formatter_dispose(mut header ObjHeader) {
	state := header.date_formatter
	header.date_formatter = unsafe { nil }
	if state != unsafe { nil } { C.free(state) }
}

fn ns_date_formatter_initialize(object u64) {
	C.ios_objc_initialize_lock()
	mut state := ns_date_formatter_state(object)
	if state.initialized { C.ios_objc_initialize_unlock(); return }
	objc_retain(object)
	state.calls++
	defer { ns_date_formatter_finish(object) }
	state.initialized = true
	state.format = 0
	// Raw alloc supports default getters. Its first init resets any settings
	// established by a constructor before publishing an initialized formatter.
	mut old := [3]u64{}
	mut header := obj_header(object)
	for i in 0 .. 3 { old[i] = header.fields[i]; header.fields[i] = 0 }
	C.ios_objc_initialize_unlock()
	for value in old { objc_release(value) }
}

fn ns_date_formatter_copy(object u64) u64 {
	C.ios_objc_initialize_lock()
	mut state := ns_date_formatter_state(object)
	objc_retain(object)
	state.calls++
	defer { ns_date_formatter_finish(object) }
	// Snapshot before allocation: application +initialize/constructors can
	// reenter this formatter and change its settings while making the copy.
	format := state.format
	source := obj_header(object)
	mut fields := [3]u64{}
	for i in 0 .. 3 { fields[i] = objc_retain(source.fields[i]) }
	C.ios_objc_initialize_unlock()
	copy := objc_allocate(ios_runtime.names['NSDateFormatter'])
	if copy == 0 { for value in fields { objc_release(value) }; return 0 }
	C.ios_objc_initialize_lock()
	mut target_state := ns_date_formatter_state(copy)
	objc_retain(copy)
	target_state.calls++
	defer { ns_date_formatter_finish(copy) }
	mut target := obj_header(copy)
	mut old := [3]u64{}
	target_state.format = format
	target_state.initialized = true
	for i in 0 .. 3 { old[i] = target.fields[i]; target.fields[i] = fields[i] }
	C.ios_objc_initialize_unlock()
	for value in old { objc_release(value) }
	return copy
}

fn ns_date_formatter_finish(object u64) {
	C.ios_objc_initialize_lock()
	mut state := ns_date_formatter_state(object)
	if state.calls == 0 { panic('iOS: unbalanced date formatter call') }
	state.calls--
	C.ios_objc_initialize_unlock()
	objc_release(object)
}

// Caller transfers one owned immutable setting. Publish under the lock, then
// release the previous value outside it: dealloc can invoke application code.
fn ns_date_formatter_setting(object u64, index int, value u64, format int) {
	C.ios_objc_initialize_lock()
	mut state := ns_date_formatter_state(object)
	mut header := obj_header(object)
	old := header.fields[index]
	header.fields[index] = value
	if index == 0 { state.format = format }
	C.ios_objc_initialize_unlock()
	objc_release(old)
}

fn ns_date_formatter_text(object u64) string {
	if header := ios_runtime.objects[object] {
		if header.destroying || header.allocation_cls !in [ios_runtime.names['NSString'], ios_runtime.names['NSMutableString']]!
			|| read64(object) != header.allocation_cls { panic('iOS: date formatter string subclasses are not implemented') }
	}
	return cf_string_compare_text(object) or { panic('iOS: date formatter requires a live UTF8 NSString') }
}

fn ns_date_formatter_format_code(text string) int {
	return match text {
		'' { 0 }
		'yyyy-MM-dd_HHmmssZ' { 1 }
		'yyyy-MM-dd HH:mm:ss' { 2 }
		"yyyy-MM-dd'T'HH:mm:ss.SSS" { 3 }
		'yyyy-MM-dd' { 4 }
		else { panic('iOS: unsupported date formatter pattern') }
	}
}

// English POSIX-compatible identifiers only. Swift's wider locale value
// representation remains separate; these constructors serve measured callers.
fn ns_date_formatter_locale(object u64) u64 {
	header := ios_runtime.objects[object] or { panic('iOS: date formatter requires a built-in locale') }
	if header.destroying || header.destroyed || header.allocation_cls != ios_runtime.names['NSLocale']
		|| read64(object) != header.allocation_cls || header.fields[0] == 0 {
		panic('iOS: date formatter requires an initialized built-in locale')
	}
	identifier := ns_date_formatter_text(header.fields[0])
	if identifier !in ['en_US_POSIX', 'en_US', 'en_GB']! { panic('iOS: localized date formatting is not implemented') }
	return object
}

fn ns_date_formatter_check_locale() {
	// Getting the default can allocate and invoke application constructors.
	// Call only after snapshotting all borrowed date/string input and settings.
	current := ns_locale_current()
	C.ios_objc_initialize_lock()
	ns_date_formatter_locale(current)
	C.ios_objc_initialize_unlock()
}

fn ns_date_formatter_locale_init(object u64, identifier u64) u64 {
	C.ios_objc_initialize_lock()
	text := ns_date_formatter_text(identifier)
	if text !in ['en_US_POSIX', 'en_US', 'en_GB']! { panic('iOS: unsupported locale identifier') }
	// Only immutable literal bytes survive object allocation and its callbacks.
	canonical := match text { 'en_US_POSIX' { 'en_US_POSIX' } 'en_GB' { 'en_GB' } else { 'en_US' } }
	objc_retain(object)
	defer { objc_release(object) }
	C.ios_objc_initialize_unlock()
	copy := owned_string(canonical)
	if copy == 0 { objc_release(object); return 0 }
	// Revalidate after allocation callbacks; no borrowed header survives them.
	C.ios_objc_initialize_lock()
	mut header := ios_runtime.objects[object] or { panic('iOS: locale initializer requires owned storage') }
	if header.allocation_cls != ios_runtime.names['NSLocale'] || read64(object) != header.allocation_cls
		|| header.destroying || header.destroyed || header.fields[0] != 0 {
		panic('iOS: locale initializer requires an uninitialized built-in locale')
	}
	header.fields[0] = copy
	C.ios_objc_initialize_unlock()
	return object
}

fn ns_date_formatter_fields(seconds i64, local bool) [7]u64 {
	mut calendar := [7]u64{}
	result := if local { C.ios_localtime_r(unsafe { &seconds }, unsafe { &calendar[0] }) } else { C.ios_gmtime_r(unsafe { &seconds }, unsafe { &calendar[0] }) }
	if result == unsafe { nil } { panic('iOS: date formatter calendar conversion failed') }
	return calendar
}

fn ns_date_formatter_gregorian(parts [6]int) ?i64 {
	year := parts[0]
	month := parts[1]
	day := parts[2]
	if year < 1582 || year > 9999 || month < 1 || month > 12 || day < 1
		|| parts[3] < 0 || parts[3] > 23 || parts[4] < 0 || parts[4] > 59 || parts[5] < 0 || parts[5] > 59
		|| (year == 1582 && (month < 10 || (month == 10 && day < 15))) { return none }
	leap := year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
	months := [31, if leap { 29 } else { 28 }, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]!
	if day > months[month - 1] { return none }
	previous := i64(year - 1)
	mut days := previous * 365 + previous / 4 - previous / 100 + previous / 400 - 719162
	for i in 0 .. month - 1 { days += months[i] }
	return (days + day - 1) * 86400 + parts[3] * 3600 + parts[4] * 60 + parts[5]
}

fn ns_date_formatter_local(parts [6]int) ?i64 {
	// Native strict parsing rejects gaps and chooses standard time in an
	// overlap. Probe both DST hints and verify every field after normalization.
	for hint in [0, 1, -1]! {
		mut calendar := [7]u64{}
		mut fields := unsafe { &i32(&calendar[0]) }
		unsafe {
			fields[0] = parts[5]; fields[1] = parts[4]; fields[2] = parts[3]
			fields[3] = parts[2]; fields[4] = parts[1] - 1; fields[5] = parts[0] - 1900
			fields[8] = hint
		}
		seconds := C.ios_mktime(unsafe { &calendar[0] })
		check := ns_date_formatter_fields(seconds, true)
		actual := unsafe { &i32(&check[0]) }
		matches := unsafe { actual[0] == parts[5] && actual[1] == parts[4] && actual[2] == parts[3]
			&& actual[3] == parts[2] && actual[4] + 1 == parts[1] && actual[5] + 1900 == parts[0] }
		if matches { return seconds }
	}
	return none
}

fn ns_date_formatter_string(object u64, date u64) u64 {
	if date == 0 { return 0 }
	C.ios_objc_initialize_lock()
	header := ios_runtime.objects[date] or { panic('iOS: date formatter requires a built-in NSDate') }
	if header.destroying || header.destroyed || !header.date_owned || !header.date_initialized
		|| header.allocation_cls != cf_date_id() || read64(date) != header.allocation_cls { panic('iOS: date formatter requires an initialized built-in NSDate') }
	state := ns_date_formatter_state(object)
	code := state.format
	settings := obj_header(object)
	default_locale := settings.fields[1] == 0
	if settings.fields[1] != 0 { ns_date_formatter_locale(settings.fields[1]) }
	unix := header.real_number + 978307200.0
	fixed := settings.fields[2] != 0
	shift := if fixed { swift_timezone_identity(ns_timezone_seconds(settings.fields[2])) * 60 } else { i64(0) }
	C.ios_objc_initialize_unlock()
	if default_locale { ns_date_formatter_check_locale() }
	if !math.is_finite(unix) || unix < -12219292800.0 - 64800 || unix >= 253402300800.0 + 64800 {
		panic('iOS: date formatter requires Gregorian years 1582-10-15 through 9999')
	}
	// Foundation rounds the instant to milliseconds before extracting ANY
	// calendar field, including patterns which don't print the fraction.
	// ICU resolves exact half milliseconds toward positive infinity, including
	// negative instants (1969-12-31T23:59:59.9375 becomes .938).
	millis := i64(math.floor(unix * 1000.0 + 0.5))
	whole := i64(math.floor(f64(millis) / 1000.0))
	fraction := int(millis - whole * 1000)
	calendar := ns_date_formatter_fields(whole + shift, !fixed)
	fields := unsafe { &i32(&calendar[0]) }
	parts := unsafe { [int(fields[5] + 1900), int(fields[4] + 1), int(fields[3]), int(fields[2]), int(fields[1]), int(fields[0])]! }
	if ns_date_formatter_gregorian(parts) == none { panic('iOS: date formatter fields outside supported Gregorian range') }
	if code == 0 { return owned_string('') }
	offset := if fixed { shift } else { unsafe { *(&i64(u64(&calendar[0]) + 40)) } }
	positive := if offset < 0 { -offset } else { offset }
	minutes := positive / 60
	mut bytes := [40]u8{}
	length := match code {
		1 { unsafe { C.snprintf(&char(&bytes[0]), bytes.len, c'%04d-%02d-%02d_%02d%02d%02d%c%02d%02d', parts[0], parts[1], parts[2], parts[3], parts[4], parts[5], if offset < 0 { i32(`-`) } else { i32(`+`) }, i32(minutes / 60), i32(minutes % 60)) } }
		2 { unsafe { C.snprintf(&char(&bytes[0]), bytes.len, c'%04d-%02d-%02d %02d:%02d:%02d', parts[0], parts[1], parts[2], parts[3], parts[4], parts[5]) } }
		3 { unsafe { C.snprintf(&char(&bytes[0]), bytes.len, c'%04d-%02d-%02dT%02d:%02d:%02d.%03d', parts[0], parts[1], parts[2], parts[3], parts[4], parts[5], fraction) } }
		else { unsafe { C.snprintf(&char(&bytes[0]), bytes.len, c'%04d-%02d-%02d', parts[0], parts[1], parts[2]) } }
	}
	if length != [0, 22, 19, 23, 10]![code] { panic('iOS: date formatter output overflow') }
	// Historical local zones can have second precision (Moscow +02:30:17).
	if code == 1 && positive % 60 != 0 {
		bytes[22] = u8(`0` + (positive % 60) / 10)
		bytes[23] = u8(`0` + positive % 10)
		return owned_string(unsafe { tos(&bytes[0], 24) })
	}
	return owned_string(unsafe { tos(&bytes[0], length) })
}

fn (mut reader DateFormatterReader) digits(minimum int, maximum int) ?int {
	start := reader.pos
	mut value := 0
	for reader.pos < reader.text.len && reader.pos - start < maximum {
		byte := reader.text[reader.pos]
		if byte < `0` || byte > `9` { break }
		value = value * 10 + int(byte - `0`)
		reader.pos++
	}
	if reader.pos - start < minimum { return none }
	return value
}

fn (mut reader DateFormatterReader) byte(expected u8) bool {
	if reader.pos >= reader.text.len || reader.text[reader.pos] != expected { return false }
	reader.pos++
	return true
}

fn (mut reader DateFormatterReader) spaces() {
	for reader.pos < reader.text.len && reader.text[reader.pos] in [` `, `\t`]! { reader.pos++ }
}

fn ns_date_formatter_parse(object u64, text string) ?f64 {
	if text.len > 128 { return none }
	state := ns_date_formatter_state(object)
	settings := obj_header(object)
	if settings.fields[1] != 0 { ns_date_formatter_locale(settings.fields[1]) }
	code := state.format
	mut reader := DateFormatterReader{text: text}
	reader.spaces()
	mut parts := [2000, 1, 1, 0, 0, 0]!
	mut fraction := 0
	mut offset := if settings.fields[2] != 0 { swift_timezone_identity(ns_timezone_seconds(settings.fields[2])) * 60 } else { i64(0) }
	mut explicit_zone := settings.fields[2] != 0
	if code != 0 {
		parts[0] = reader.digits(4, 4) or { return none }
		if !reader.byte(`-`) { return none }
		parts[1] = reader.digits(1, 2) or { return none }
		if !reader.byte(`-`) { return none }
		parts[2] = reader.digits(1, 2) or { return none }
		if code == 1 {
			if !reader.byte(`_`) { return none }
			for i in 3 .. 6 { parts[i] = reader.digits(2, 2) or { return none } }
			explicit_zone = true
			if reader.byte(`Z`) { offset = 0 } else {
				negative := reader.byte(`-`)
				if !negative && !reader.byte(`+`) { return none }
				hours := reader.digits(2, 2) or { return none }
				minutes := reader.digits(2, 2) or { return none }
				if hours > 23 || minutes > 59 { return none }
				offset = (hours * 60 + minutes) * 60 * if negative { -1 } else { 1 }
			}
		} else if code in [2, 3]! {
			if code == 2 {
				start := reader.pos
				reader.spaces()
				if reader.pos == start { return none }
			} else if !reader.byte(`T`) { return none }
			for i in 3 .. 6 {
				parts[i] = reader.digits(1, 2) or { return none }
				if i != 5 && !reader.byte(`:`) { return none }
			}
			if code == 3 {
				if !reader.byte(`.`) { return none }
				start := reader.pos
				for i in 0 .. 9 {
					if reader.pos >= text.len || text[reader.pos] < `0` || text[reader.pos] > `9` { break }
					if i < 3 { fraction = fraction * 10 + int(text[reader.pos] - `0`) }
					reader.pos++
				}
				count := reader.pos - start
				if count == 0 { return none }
				if count == 1 { fraction *= 100 } else if count == 2 { fraction *= 10 }
			}
		}
	}
	reader.spaces()
	if reader.pos != text.len { return none }
	base := ns_date_formatter_gregorian(parts) or { return none }
	seconds := if explicit_zone { base - offset } else { ns_date_formatter_local(parts) or { return none } }
	return f64(seconds) + f64(fraction) / 1000.0 - 978307200.0
}

fn ns_date_formatter_types(name string, meta bool, selector string) ?string {
	if name == 'NSLocale' && selector in ['localeWithLocaleIdentifier:', 'initWithLocaleIdentifier:']! {
		if meta == (selector == 'localeWithLocaleIdentifier:') { return '@24@0:8@16' }
	}
	if name != 'NSDateFormatter' { return none }
	if meta {
		return match selector {
			'alloc', 'new' { '@16@0:8' }
			'allocWithZone:' { '@24@0:8^{_NSZone=}16' }
			else { return none }
		}
	}
	return match selector {
		'init', 'copy', 'dateFormat', 'locale', 'timeZone', 'defaultDate' { '@16@0:8' }
		'copyWithZone:' { '@24@0:8^{_NSZone=}16' }
		'stringFromDate:', 'dateFromString:', 'stringForObjectValue:' { '@24@0:8@16' }
		'setDateFormat:', 'setLocale:', 'setTimeZone:', 'setDefaultDate:' { 'v24@0:8@16' }
		'dateStyle', 'timeStyle', 'formatterBehavior' { 'Q16@0:8' }
		'setDateStyle:', 'setTimeStyle:', 'setFormatterBehavior:' { 'v24@0:8Q16' }
		'formattingContext' { 'q16@0:8' }
		'setFormattingContext:' { 'v24@0:8q16' }
		'isLenient', 'doesRelativeDateFormatting', 'generatesCalendarDates', 'allowsNaturalLanguage' { 'B16@0:8' }
		'setLenient:', 'setDoesRelativeDateFormatting:', 'setGeneratesCalendarDates:', 'setAllowsNaturalLanguage:' { 'v20@0:8B16' }
		'classForCoder' { '#16@0:8' }
		else { return none }
	}
}

fn ns_date_formatter_unsupported(selector string) bool {
	return selector in ['mutableCopy', 'mutableCopyWithZone:', 'initWithCoder:', 'encodeWithCoder:', 'supportsSecureCoding',
		'calendar', 'setCalendar:', 'setLocalizedDateFormatFromTemplate:', 'dateFormatFromTemplate:options:locale:',
		'localizedStringFromDate:dateStyle:timeStyle:', 'defaultFormatterBehavior', 'setDefaultFormatterBehavior:',
		'getObjectValue:forString:errorDescription:', 'getObjectValue:forString:range:error:',
		'editingStringForObjectValue:', 'attributedStringForObjectValue:withDefaultAttributes:']!
		|| selector.contains('Symbols') || selector.contains('StartDate') || selector.contains('TwoDigit')
}

fn ns_date_formatter_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	meta := object in ios_runtime.classes
	cls := if meta { object } else { read64(object) }
	// Allocation provenance still owns the state after object_setClass. Route
	// formatter methods through its validator before a generic fallback can act.
	mut formatter := ns_date_formatter_family(cls)
	if !meta {
		C.ios_objc_initialize_lock()
		if header := ios_runtime.objects[object] {
			formatter = formatter || header.date_formatter != unsafe { nil }
		}
		C.ios_objc_initialize_unlock()
	}
	if cls == ios_runtime.names['NSLocale'] && !formatter {
		if selector == 'localeWithLocaleIdentifier:' && meta {
			// Validate/canonicalize input before allocation can invoke callbacks.
			C.ios_objc_initialize_lock()
			text := ns_date_formatter_text(frame.x[2])
			canonical := match text { 'en_US_POSIX' { 'en_US_POSIX' } 'en_US' { 'en_US' } 'en_GB' { 'en_GB' } else { panic('iOS: unsupported locale identifier') } }
			C.ios_objc_initialize_unlock()
			identifier := owned_string(canonical)
			if identifier == 0 { frame.x[0] = 0; return true }
			mut locale := objc_allocate(cls)
			if locale != 0 { locale = ns_date_formatter_locale_init(locale, identifier) }
			objc_release(identifier)
			frame.x[0] = objc_autorelease(locale)
			return true
		}
		if selector == 'initWithLocaleIdentifier:' && !meta {
			frame.x[0] = ns_date_formatter_locale_init(object, frame.x[2])
			return true
		}
		return false
	}
	if !formatter { return false }
	if ns_date_formatter_unsupported(selector) { panic('iOS: date formatter option is not implemented') }
	if ns_date_formatter_types('NSDateFormatter', meta, selector) == none { return false }
	if meta {
		frame.x[0] = if selector == 'new' { objc_new(object) } else { objc_allocate(object) }
		return true
	}
	C.ios_objc_initialize_lock()
	mut state := ns_date_formatter_state(object)
	objc_retain(object)
	state.calls++
	if selector.starts_with('set') && !state.initialized {
		panic('iOS: date formatter setters require init')
	}
	C.ios_objc_initialize_unlock()
	defer { ns_date_formatter_finish(object) }
	match selector {
		'init' { ns_date_formatter_initialize(object); frame.x[0] = object }
		'copy', 'copyWithZone:' { frame.x[0] = ns_date_formatter_copy(object) }
		'dateFormat' {
			C.ios_objc_initialize_lock()
			value := objc_retain(obj_header(object).fields[0])
			C.ios_objc_initialize_unlock()
			frame.x[0] = objc_autorelease(if value != 0 { value } else { owned_string('') })
		}
		'setDateFormat:' {
			C.ios_objc_initialize_lock()
			text := if frame.x[2] == 0 { '' } else { ns_date_formatter_text(frame.x[2]) }
			code := ns_date_formatter_format_code(text)
			// Canonical static bytes have the validated pattern's exact contents.
			pattern := ['', 'yyyy-MM-dd_HHmmssZ', 'yyyy-MM-dd HH:mm:ss', "yyyy-MM-dd'T'HH:mm:ss.SSS", 'yyyy-MM-dd']![code]
			C.ios_objc_initialize_unlock()
			value := owned_string(pattern)
			if value == 0 { panic('iOS: cannot copy date formatter pattern') }
			ns_date_formatter_setting(object, 0, value, code)
		}
		'locale' {
			C.ios_objc_initialize_lock()
			mut value := objc_retain(obj_header(object).fields[1])
			C.ios_objc_initialize_unlock()
			if value == 0 {
				current := ns_locale_current()
				C.ios_objc_initialize_lock()
				value = objc_retain(ns_date_formatter_locale(current))
				C.ios_objc_initialize_unlock()
			}
			frame.x[0] = objc_autorelease(value)
		}
		'setLocale:' {
			C.ios_objc_initialize_lock()
			value := if frame.x[2] == 0 { u64(0) } else { objc_retain(ns_date_formatter_locale(frame.x[2])) }
			C.ios_objc_initialize_unlock()
			ns_date_formatter_setting(object, 1, value, 0)
		}
		'timeZone' {
			C.ios_objc_initialize_lock()
			value := obj_header(object).fields[2]
			if value == 0 { panic('iOS: implicit local timezone object is not implemented') }
			ns_timezone_seconds(value)
			objc_retain(value)
			C.ios_objc_initialize_unlock()
			frame.x[0] = objc_autorelease(value)
		}
		'setTimeZone:' {
			C.ios_objc_initialize_lock()
			if frame.x[2] != 0 { ns_timezone_seconds(frame.x[2]) }
			value := objc_retain(frame.x[2])
			C.ios_objc_initialize_unlock()
			ns_date_formatter_setting(object, 2, value, 0)
		}
		'stringFromDate:' { frame.x[0] = objc_autorelease(ns_date_formatter_string(object, frame.x[2])) }
		'stringForObjectValue:' {
			value := frame.x[2]
			C.ios_objc_initialize_lock()
			date := value in ios_runtime.objects && obj_header(value).date_owned
			if date { objc_retain(value) }
			C.ios_objc_initialize_unlock()
			frame.x[0] = if date { objc_autorelease(ns_date_formatter_string(object, value)) } else { u64(0) }
			if date { objc_release(value) }
		}
		'dateFromString:' {
			if frame.x[2] == 0 { frame.x[0] = 0 } else {
				C.ios_objc_initialize_lock()
				text := ns_date_formatter_text(frame.x[2])
				parsed := ns_date_formatter_parse(object, text)
				default_locale := obj_header(object).fields[1] == 0
				C.ios_objc_initialize_unlock()
				if default_locale { ns_date_formatter_check_locale() }
				if absolute := parsed { frame.x[0] = objc_autorelease(cf_date_create(0, absolute)) } else { frame.x[0] = 0 }
			}
		}
		'classForCoder' { frame.x[0] = ios_runtime.names['NSDateFormatter'] }
		'setDateStyle:', 'setTimeStyle:' {
			if frame.x[2] != 0 { panic('iOS: localized date formatter styles are not implemented') }
			ns_date_formatter_setting(object, 0, 0, 0)
		}
		'setFormatterBehavior:', 'setFormattingContext:', 'setLenient:', 'setDoesRelativeDateFormatting:', 'setGeneratesCalendarDates:', 'setAllowsNaturalLanguage:', 'setDefaultDate:' {
			value := if selector in ['setLenient:', 'setDoesRelativeDateFormatting:', 'setGeneratesCalendarDates:', 'setAllowsNaturalLanguage:']! { frame.x[2] & 255 } else { frame.x[2] }
			if value != 0 { panic('iOS: non-default date formatter option is not implemented') }
		}
		else { frame.x[0] = 0 }
	}
	return true
}

// SPDX-License-Identifier: GPL-2.0-or-later
module main

import math

// Both public Foundation classes have only an isa. Private native cluster
// layouts are not guest ABI. Integer values and settings live in this sidecar;
// NSDateComponents fields[0/1] own its time zone and independent calendar.
struct FoundationCalendar {
mut:
	components bool
	initialized bool
	retiring bool
	calls u64
	iso bool
	local bool
	offset i64
	first i64 = 1
	minimum i64 = 1
	values [14]i64
}

fn ns_calendar_name(cls u64) string {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return '' }
		if info.name in ['NSCalendar', 'NSDateComponents']! { return info.name }
		current = info.parent
		if current == 0 { return '' }
	}
	panic('iOS: cyclic calendar superclass chain')
}

fn ns_calendar_require_class(cls u64) {
	name := ns_calendar_name(cls)
	if name != '' && cls != ios_runtime.names[name] { panic('iOS: custom calendar subclasses are not implemented') }
}

fn ns_calendar_install(cls u64, mut header ObjHeader) {
	if cls !in [ios_runtime.names['NSCalendar'], ios_runtime.names['NSDateComponents']]! { return }
	header.calendar = unsafe { &FoundationCalendar(C.calloc(1, sizeof(FoundationCalendar))) }
	if header.calendar == unsafe { nil } { panic('iOS: cannot allocate calendar state') }
	header.calendar.components = cls == ios_runtime.names['NSDateComponents']
	header.calendar.first = 1
	header.calendar.minimum = 1
	for i in 0 .. 14 { header.calendar.values[i] = max_i64 }
}

// Caller holds the recursive runtime lock. Disposal uses provenance even if
// an application changes isa; operations require the original built-in class.
fn ns_calendar_state(object u64, initialized bool) &FoundationCalendar {
	header := obj_header(object)
	state := header.calendar
	if state == unsafe { nil } || header.destroying || header.destroyed || state.retiring
		|| C.ios_ref_change(unsafe { &header.refs }, 0) <= 0 || header.native_size < 8
		|| header.cls != header.allocation_cls || read64(object) != header.allocation_cls
		|| header.allocation_cls != ios_runtime.names[if state.components { 'NSDateComponents' } else { 'NSCalendar' }] {
		panic('iOS: calendar requires live owned built-in storage')
	}
	if initialized && !state.initialized { panic('iOS: calendar requires initialization') }
	return state
}

fn ns_calendar_retire(mut header ObjHeader) {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if header.calendar == unsafe { nil } { return }
	if header.calendar.calls != 0 { panic('iOS: destroying an active calendar') }
	header.calendar.retiring = true
}

fn ns_calendar_dispose(mut header ObjHeader) {
	state := header.calendar
	header.calendar = unsafe { nil }
	if state != unsafe { nil } { C.free(state) }
}

fn ns_calendar_pin(object u64) {
	mut state := ns_calendar_state(object, true)
	objc_retain(object)
	state.calls++
}

fn ns_calendar_finish(object u64) {
	C.ios_objc_initialize_lock()
	mut state := ns_calendar_state(object, true)
	if state.calls == 0 { panic('iOS: unbalanced calendar call') }
	state.calls--
	C.ios_objc_initialize_unlock()
	objc_release(object)
}

fn ns_calendar_initialize(object u64, identifier u64, current bool) u64 {
	C.ios_objc_initialize_lock()
	mut kind := -1
	if current { kind = 0 } else if identifier != 0 {
		text := ns_date_formatter_text(identifier)
		kind = match text { 'gregorian' { 0 } 'iso8601' { 1 } else { -1 } }
	}
	C.ios_objc_initialize_unlock()
	return ns_calendar_initialize_kind(object, kind)
}

fn ns_calendar_initialize_kind(object u64, kind int) u64 {
	C.ios_objc_initialize_lock()
	mut state := ns_calendar_state(object, false)
	if state.initialized { panic('iOS: calendar reinitialization is not implemented') }
	if state.components { state.initialized = true; C.ios_objc_initialize_unlock(); return object }
	if kind < 0 {
		C.ios_objc_initialize_unlock()
		objc_release(object)
		return 0 // Apple's default init and unknown identifier return nil.
	}
	state.iso = kind == 1
	state.first = if state.iso { 2 } else { 1 }
	state.minimum = if state.iso { 4 } else { 1 }
	state.local = true
	state.initialized = true
	C.ios_objc_initialize_unlock()
	return object
}

fn ns_calendar_copy(object u64) u64 {
	C.ios_objc_initialize_lock()
	state := ns_calendar_state(object, true)
	ns_calendar_pin(object)
	defer { ns_calendar_finish(object) }
	snapshot := *state
	source := obj_header(object)
	zone := objc_retain(source.fields[0])
	calendar := objc_retain(source.fields[1])
	C.ios_objc_initialize_unlock()
	return ns_calendar_copy_snapshot(snapshot, zone, calendar)
}

// Takes ownership of both input references. The same immutable snapshot can
// produce extracted fields and their associated calendar despite reentry.
fn ns_calendar_copy_snapshot(snapshot FoundationCalendar, zone u64, calendar u64) u64 {
	defer { objc_release(calendar) }
	// No borrowed metadata crosses class initialization or constructors.
	calendar_copy := if calendar != 0 { ns_calendar_copy(calendar) } else { u64(0) }
	if calendar != 0 && calendar_copy == 0 { objc_release(zone); return 0 }
	copy := objc_allocate(ios_runtime.names[if snapshot.components { 'NSDateComponents' } else { 'NSCalendar' }])
	if copy == 0 { objc_release(zone); objc_release(calendar_copy); return 0 }
	C.ios_objc_initialize_lock()
	mut target := ns_calendar_state(copy, false)
	if target.initialized { panic('iOS: calendar copy constructor initialized its destination') }
	target.initialized = true
	target.iso = snapshot.iso; target.local = snapshot.local; target.offset = snapshot.offset
	target.first = snapshot.first; target.minimum = snapshot.minimum; target.values = snapshot.values
	mut header := obj_header(copy)
	header.fields[0] = zone; header.fields[1] = calendar_copy
	C.ios_objc_initialize_unlock()
	return copy
}

fn ns_calendar_field(selector string) int {
	return match selector {
		'era', 'setEra:' { 0 } 'year', 'setYear:' { 1 } 'month', 'setMonth:' { 2 }
		'day', 'setDay:' { 3 } 'hour', 'setHour:' { 4 } 'minute', 'setMinute:' { 5 }
		'second', 'setSecond:' { 6 } 'nanosecond', 'setNanosecond:' { 7 }
		'weekday', 'setWeekday:' { 8 } 'weekdayOrdinal', 'setWeekdayOrdinal:' { 9 }
		'quarter', 'setQuarter:' { 10 } 'weekOfMonth', 'setWeekOfMonth:' { 11 }
		'weekOfYear', 'setWeekOfYear:' { 12 } 'yearForWeekOfYear', 'setYearForWeekOfYear:' { 13 }
		else { -1 }
	}
}

fn ns_calendar_zone(object u64) (bool, i64) {
	local, offset := ns_timezone_snapshot(object)
	if !local && offset % 60 != 0 { panic('iOS: calendar subminute time zones are not implemented') }
	return local, offset
}

fn ns_timezone_snapshot(object u64) (bool, i64) {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if object == 0 { panic('iOS: calendar requires a time zone') }
	header := ios_runtime.objects[object] or { panic('iOS: calendar requires a built-in time zone') }
	if header.destroying || header.destroyed || header.allocation_cls != ios_runtime.names['NSTimeZone']
		|| header.cls != header.allocation_cls || read64(object) != header.allocation_cls
		|| C.ios_ref_change(unsafe { &header.refs }, 0) <= 0 || !header.timezone_initialized {
		panic('iOS: calendar requires an initialized built-in time zone')
	}
	return header.timezone_local, header.number
}

fn ns_calendar_local_zone() u64 {
	object := objc_allocate(ios_runtime.names['NSTimeZone'])
	if object == 0 { return 0 }
	C.ios_objc_initialize_lock()
	mut header := obj_header(object)
	if header.allocation_cls != ios_runtime.names['NSTimeZone'] || read64(object) != header.allocation_cls || header.timezone_initialized {
		panic('iOS: local calendar zone requires uninitialized built-in storage')
	}
	header.timezone_initialized = true
	header.timezone_local = true
	C.ios_objc_initialize_unlock()
	return object
}

fn ns_calendar_local_zone_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	if selector in ['copy', 'copyWithZone:']! { frame.x[0] = objc_retain(object); return true }
	if selector == 'classForCoder' { frame.x[0] = ios_runtime.names['NSTimeZone']; return true }
	if selector !in ['secondsFromGMT', 'secondsFromGMTForDate:', 'isDaylightSavingTime', 'isDaylightSavingTimeForDate:']! {
		panic('iOS: local calendar time zone metadata is not implemented')
	}
	C.ios_objc_initialize_lock()
	unix := if selector.ends_with('ForDate:') && frame.x[2] != 0 { ns_calendar_date(frame.x[2]) } else { cf_absolute_time() + 978307200.0 }
	C.ios_objc_initialize_unlock()
	calendar := ns_date_formatter_fields(i64(math.floor(unix)), true)
	frame.x[0] = if selector.starts_with('seconds') { calendar[5] } else { u64(unsafe { (&i32(&calendar[0]))[8] > 0 }) }
	return true
}

fn ns_calendar_date(date u64) f64 {
	header := ios_runtime.objects[date] or { panic('iOS: calendar requires a built-in NSDate') }
	if header.destroying || header.destroyed || !header.date_owned || !header.date_initialized
		|| header.allocation_cls != cf_date_id() || header.cls != header.allocation_cls
		|| read64(date) != header.allocation_cls || C.ios_ref_change(unsafe { &header.refs }, 0) <= 0 {
		panic('iOS: calendar requires an initialized built-in NSDate')
	}
	unix := header.real_number + 978307200.0
	if !math.is_finite(unix) || unix < -12212553600.0 + 64800 || unix >= 253402300800.0 - 64800 {
		panic('iOS: calendar supports Gregorian dates within years 1583 through 9999')
	}
	return unix
}

// Days since 1970; only positive AD years and normalized months are passed.
fn ns_calendar_days(year i64, month i64, day i64) i64 {
	previous := year - 1
	mut days := previous * 365 + previous / 4 - previous / 100 + previous / 400 - 719162
	leap := year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
	months := [31, if leap { 29 } else { 28 }, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]!
	for i in 0 .. int(month - 1) { days += months[i] }
	return days + day - 1
}

fn ns_calendar_week_start(year i64, month i64, first i64, minimum i64) i64 {
	day := ns_calendar_days(year, month, 1)
	weekday := ((day + 4) % 7 + 7) % 7 + 1
	back := (weekday - first + 7) % 7
	return day - back + if 7 - back < minimum { i64(7) } else { i64(0) }
}

fn ns_calendar_extract(unix f64, local bool, offset i64, first i64, minimum i64) [14]i64 {
	seconds := i64(math.floor(unix))
	calendar := ns_date_formatter_fields(seconds + if local { i64(0) } else { offset }, local)
	parts := unsafe { &i32(&calendar[0]) }
	year := unsafe { i64(parts[5]) + 1900 }
	if year < 1583 || year > 9999 { panic('iOS: local calendar date is outside supported years') }
	month := unsafe { i64(parts[4]) + 1 }
	day := unsafe { i64(parts[3]) }
	days := ns_calendar_days(year, month, day)
	mut week_year := year
	mut start := ns_calendar_week_start(year, 1, first, minimum)
	if days < start { week_year--; start = ns_calendar_week_start(week_year, 1, first, minimum) }
	else if days >= ns_calendar_week_start(year + 1, 1, first, minimum) { week_year++; start = ns_calendar_week_start(week_year, 1, first, minimum) }
	month_start := ns_calendar_week_start(year, month, first, minimum)
	return [i64(1), year, month, day, unsafe { i64(parts[2]) }, unsafe { i64(parts[1]) }, unsafe { i64(parts[0]) },
		i64((unix - math.floor(unix)) * 1000000000.0), unsafe { i64(parts[6]) + 1 }, (day - 1) / 7 + 1,
		(month - 1) / 3 + 1, if days < month_start { i64(0) } else { (days - month_start) / 7 + 1 },
		(days - start) / 7 + 1, week_year]!
}

fn ns_calendar_components(object u64, mask u64, date u64, zone u64, full bool) u64 {
	C.ios_objc_initialize_lock()
	state := ns_calendar_state(object, true)
	if state.components { panic('iOS: calendar extraction requires NSCalendar') }
	snapshot := *state
	if !full && mask != 252 { panic('iOS: calendar component masks other than YMDHMS are not implemented') }
	unix := ns_calendar_date(date)
	mut local := state.local
	mut offset := state.offset
	if full { local, offset = ns_calendar_zone(zone) }
	values := ns_calendar_extract(unix, local, offset, state.first, state.minimum)
	ns_calendar_pin(object)
	defer { ns_calendar_finish(object) }
	retained_zone := if full { objc_retain(zone) } else { u64(0) }
	C.ios_objc_initialize_unlock()
	calendar_copy := if full { ns_calendar_copy_snapshot(snapshot, 0, 0) } else { u64(0) }
	if full && calendar_copy == 0 { objc_release(retained_zone); return 0 }
	if full {
		C.ios_objc_initialize_lock()
		mut copied := ns_calendar_state(calendar_copy, true)
		copied.local = local; copied.offset = offset
		C.ios_objc_initialize_unlock()
	}
	result := objc_allocate(ios_runtime.names['NSDateComponents'])
	if result == 0 { objc_release(retained_zone); objc_release(calendar_copy); return 0 }
	C.ios_objc_initialize_lock()
	mut target := ns_calendar_state(result, false)
	if target.initialized { panic('iOS: component constructor initialized its destination') }
	target.initialized = true
	if full { target.values = values } else { for i in 1 .. 7 { target.values[i] = values[i] } }
	mut header := obj_header(result)
	header.fields[0] = retained_zone; header.fields[1] = calendar_copy
	C.ios_objc_initialize_unlock()
	return result
}

// libc supplies local-zone rules. Select the first matching instant in an
// overlap, and move forward over a gap, as measured against Foundation.
fn ns_calendar_local_seconds(wall i64) i64 {
	normal := ns_date_formatter_fields(wall, false)
	mut best := max_i64
	mut forward := max_i64
	mut forward_wall := max_i64
	for hint in [-1, 0, 1]! {
		mut calendar := normal
		unsafe { (&i32(&calendar[0]))[8] = hint }
		seconds := C.ios_mktime(unsafe { &calendar[0] })
		check := ns_date_formatter_fields(seconds, true)
		parts := unsafe { &i32(&check[0]) }
		actual := unsafe { ns_calendar_days(i64(parts[5]) + 1900, i64(parts[4]) + 1, i64(parts[3])) * 86400 + i64(parts[2]) * 3600 + i64(parts[1]) * 60 + parts[0] }
		if actual == wall && seconds < best { best = seconds }
		if actual > wall && (actual < forward_wall || (actual == forward_wall && seconds < forward)) { forward = seconds; forward_wall = actual }
	}
	if best != max_i64 { return best }
	if forward != max_i64 { return forward }
	panic('iOS: local calendar date cannot be normalized')
}

fn ns_calendar_from_components(object u64, components u64) u64 {
	C.ios_objc_initialize_lock()
	state := ns_calendar_state(object, true)
	input := ns_calendar_state(components, true)
	if state.components || !input.components { panic('iOS: dateFromComponents requires calendar and components') }
	values := input.values
	for i in [0, 8, 9, 10, 11, 12, 13]! {
		if values[i] != max_i64 && !(i == 0 && values[i] == 1) { panic('iOS: week-based and non-AD component construction is not implemented') }
	}
	mut parts := [6]i64{}
	for i in 0 .. 6 { parts[i] = if values[i + 1] == max_i64 { if i < 3 { i64(1) } else { i64(0) } } else { values[i + 1] } }
	if parts[0] < 1600 || parts[0] > 9998 || parts[1] < -120 || parts[1] > 120 || parts[2] < -3660 || parts[2] > 3660
		|| parts[3] < -87600 || parts[3] > 87600 || parts[4] < -5256000 || parts[4] > 5256000 || parts[5] < -315360000 || parts[5] > 315360000 {
		panic('iOS: date component normalization exceeds the supported range')
	}
	nano := if values[7] == max_i64 { i64(0) } else { values[7] }
	if nano < 0 || nano >= 1000000000 { panic('iOS: nanosecond normalization is not implemented') }
	mut year := parts[0]
	mut month := parts[1]
	for month < 1 { month += 12; year-- }
	for month > 12 { month -= 12; year++ }
	wall := ns_calendar_days(year, month, 1) * 86400 + (parts[2] - 1) * 86400 + parts[3] * 3600 + parts[4] * 60 + parts[5]
	mut local := state.local
	mut offset := state.offset
	zone := obj_header(components).fields[0]
	if zone != 0 { local, offset = ns_calendar_zone(zone) }
	C.ios_objc_initialize_unlock()
	unix := if local { ns_calendar_local_seconds(wall) } else { wall - offset }
	if unix < -12212488800 || unix >= 253402236000 { panic('iOS: normalized calendar date is outside supported years') }
	return cf_date_create(0, f64(unix) - 978307200.0 + f64(nano) / 1000000000.0)
}

fn ns_calendar_unsupported(selector string) bool {
	return selector in ['mutableCopy', 'mutableCopyWithZone:', 'description', 'descriptionWithLocale:', 'debugDescription',
		'isEqual:', 'hash', 'isEqualToCalendar:', 'isEqualToDateComponents:', 'locale', 'setLocale:',
		'initWithCoder:', 'encodeWithCoder:', 'supportsSecureCoding', 'date', 'isValidDate', 'isValidDateInCalendar:']!
}

fn ns_calendar_types(name string, meta bool, selector string) ?string {
	if name !in ['NSCalendar', 'NSDateComponents']! { return none }
	if meta {
		if name == 'NSCalendar' {
			if selector in ['currentCalendar', 'autoupdatingCurrentCalendar']! { return '@16@0:8' }
			if selector == 'calendarWithIdentifier:' { return '@24@0:8@16' }
		}
		return match selector { 'alloc', 'new' { '@16@0:8' } 'allocWithZone:' { '@24@0:8^{_NSZone=}16' } else { none } }
	}
	if name == 'NSDateComponents' {
		index := ns_calendar_field(selector)
		if index >= 0 { return if selector.starts_with('set') { 'v24@0:8q16' } else { 'q16@0:8' } }
		if selector == 'isLeapMonth' { return 'B16@0:8' }
		if selector == 'setLeapMonth:' { return 'v20@0:8B16' }
		if selector == 'calendar' { return '@16@0:8' }
		if selector == 'setCalendar:' { return 'v24@0:8@16' }
	} else {
		if selector == 'calendarIdentifier' { return '@16@0:8' }
		if selector in ['firstWeekday', 'minimumDaysInFirstWeek']! { return 'Q16@0:8' }
		if selector in ['setFirstWeekday:', 'setMinimumDaysInFirstWeek:']! { return 'v24@0:8Q16' }
		if selector in ['initWithCalendarIdentifier:', 'dateFromComponents:']! { return '@24@0:8@16' }
		if selector == 'components:fromDate:' { return '@32@0:8Q16@24' }
		if selector == 'componentsInTimeZone:fromDate:' { return '@32@0:8@16@24' }
	}
	return match selector {
		'init', 'copy', 'timeZone' { '@16@0:8' }
		'copyWithZone:' { '@24@0:8^{_NSZone=}16' }
		'setTimeZone:' { 'v24@0:8@16' }
		'classForCoder' { '#16@0:8' }
		else { none }
	}
}

fn ns_calendar_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	meta := object in ios_runtime.classes
	mut name := ns_calendar_name(if meta { object } else { read64(object) })
	if !meta {
		C.ios_objc_initialize_lock()
		if header := ios_runtime.objects[object] {
			if header.calendar != unsafe { nil } { name = if header.calendar.components { 'NSDateComponents' } else { 'NSCalendar' } }
		}
		C.ios_objc_initialize_unlock()
	}
	if name == '' { return false }
	if ns_calendar_unsupported(selector) { panic('iOS: unsupported calendar operation') }
	if ns_calendar_types(name, meta, selector) == none { return false }
	if meta {
		ns_calendar_require_class(object)
		match selector {
			'alloc', 'allocWithZone:' { frame.x[0] = objc_allocate(object) }
			'new' { frame.x[0] = objc_new(object) }
			else {
				// Snapshot the identifier before +initialize/constructors can
				// mutate or release the caller's string.
				mut kind := 0
				mut british := false
				if selector == 'calendarWithIdentifier:' {
					C.ios_objc_initialize_lock()
					text := if frame.x[2] == 0 { '' } else { ns_date_formatter_text(frame.x[2]) }
					kind = match text { 'gregorian' { 0 } 'iso8601' { 1 } else { -1 } }
					C.ios_objc_initialize_unlock()
				} else {
					locale := ns_locale_current()
					C.ios_objc_initialize_lock()
					ns_date_formatter_locale(locale)
					british = ns_date_formatter_text(obj_header(locale).fields[0]) == 'en_GB'
					C.ios_objc_initialize_unlock()
				}
				candidate := objc_allocate(object)
				frame.x[0] = if candidate == 0 { u64(0) } else { objc_autorelease(ns_calendar_initialize_kind(candidate, kind)) }
				if frame.x[0] != 0 && british {
					C.ios_objc_initialize_lock()
					mut created := ns_calendar_state(frame.x[0], true)
					created.first = 2; created.minimum = 4
					C.ios_objc_initialize_unlock()
				}
			}
		}
		return true
	}
	if selector in ['init', 'initWithCalendarIdentifier:']! {
		frame.x[0] = ns_calendar_initialize(object, if selector == 'init' { u64(0) } else { frame.x[2] }, false)
		return true
	}
	if selector in ['copy', 'copyWithZone:']! { frame.x[0] = ns_calendar_copy(object); return true }
	if selector == 'dateFromComponents:' { frame.x[0] = objc_autorelease(ns_calendar_from_components(object, frame.x[2])); return true }
	if selector in ['components:fromDate:', 'componentsInTimeZone:fromDate:']! {
		frame.x[0] = objc_autorelease(ns_calendar_components(object, frame.x[2], frame.x[3], frame.x[2], selector == 'componentsInTimeZone:fromDate:'))
		return true
	}
	C.ios_objc_initialize_lock()
	mut state := ns_calendar_state(object, true)
	index := ns_calendar_field(selector)
	if state.components && index >= 0 {
		if selector.starts_with('set') { state.values[index] = i64(frame.x[2]); frame.x[0] = 0 } else { frame.x[0] = u64(state.values[index]) }
		C.ios_objc_initialize_unlock(); return true
	}
	if selector == 'setLeapMonth:' {
		if frame.x[2] != 0 { panic('iOS: leap-month calendars are not implemented') }
		frame.x[0] = 0; C.ios_objc_initialize_unlock(); return true
	}
	if selector == 'isLeapMonth' { frame.x[0] = 0; C.ios_objc_initialize_unlock(); return true }
	if selector == 'classForCoder' { frame.x[0] = ios_runtime.names[name]; C.ios_objc_initialize_unlock(); return true }
	if selector in ['setFirstWeekday:', 'setMinimumDaysInFirstWeek:']! {
		if frame.x[2] < 1 || frame.x[2] > 7 { panic('iOS: calendar week setting is outside 1 through 7') }
		if selector == 'setFirstWeekday:' { state.first = i64(frame.x[2]) } else { state.minimum = i64(frame.x[2]) }
		frame.x[0] = 0; C.ios_objc_initialize_unlock(); return true
	}
	if selector in ['firstWeekday', 'minimumDaysInFirstWeek']! {
		frame.x[0] = u64(if selector == 'firstWeekday' { state.first } else { state.minimum }); C.ios_objc_initialize_unlock(); return true
	}
	if selector == 'calendarIdentifier' {
		iso := state.iso
		C.ios_objc_initialize_unlock()
		frame.x[0] = objc_autorelease(owned_string(if iso { 'iso8601' } else { 'gregorian' })); return true
	}
	if selector in ['setTimeZone:', 'setCalendar:']! {
		value := frame.x[2]
		if !state.components && selector == 'setTimeZone:' {
			if value != 0 { state.local, state.offset = ns_calendar_zone(value) }
			frame.x[0] = 0; C.ios_objc_initialize_unlock(); return true
		}
		field := if selector == 'setCalendar:' { 1 } else { 0 }
		if value != 0 {
			if field == 0 { ns_calendar_zone(value) } else if ns_calendar_state(value, true).components { panic('iOS: component calendar must be NSCalendar') }
		}
		ns_calendar_pin(object)
		defer { ns_calendar_finish(object) }
		retained := objc_retain(value)
		C.ios_objc_initialize_unlock()
		copy := if field == 1 && retained != 0 { ns_calendar_copy(retained) } else { retained }
		if field == 1 { objc_release(retained) }
		if value != 0 && copy == 0 { frame.x[0] = 0; return true }
		C.ios_objc_initialize_lock()
		ns_calendar_state(object, true)
		mut header := obj_header(object)
		old := header.fields[field]; header.fields[field] = copy
		C.ios_objc_initialize_unlock()
		objc_release(old)
		frame.x[0] = 0; return true
	}
	// Getter snapshots are retained under the lock and autoreleased outside it.
	if state.components {
		value := objc_retain(obj_header(object).fields[if selector == 'calendar' { 1 } else { 0 }])
		C.ios_objc_initialize_unlock()
		frame.x[0] = objc_autorelease(value)
	} else {
		local := state.local; offset := state.offset
		C.ios_objc_initialize_unlock()
		frame.x[0] = objc_autorelease(if local { ns_calendar_local_zone() } else { ns_timezone_fixed(offset) })
	}
	return true
}

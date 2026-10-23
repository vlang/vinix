// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Only fixed-offset snapshots are implemented. Native NSTimeZone's public
// instance is eight bytes; immutable seconds live in Vinix's owned metadata.
fn ns_timezone_family(cls u64) bool {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return false }
		if info.name == 'NSTimeZone' { return true }
		current = info.parent
		if current == 0 { return false }
	}
	panic('iOS: cyclic timezone superclass chain')
}

fn ns_timezone_require_class(cls u64) {
	if ns_timezone_family(cls) && cls != ios_runtime.names['NSTimeZone'] {
		panic('iOS: custom timezone subclass construction is not implemented')
	}
}

fn ns_timezone_seconds(object u64) i64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	header := ios_runtime.objects[object] or { panic('iOS: timezone requires a live registered object') }
	if header.destroying || header.destroyed || header.cls != ios_runtime.names['NSTimeZone'] || read64(object) != header.cls || !header.timezone_initialized || header.timezone_local {
		panic('iOS: timezone requires an initialized fixed snapshot')
	}
	return header.number
}

fn ns_timezone_fixed(seconds i64) u64 {
	if seconds < -64800 || seconds > 64800 { return 0 }
	object := objc_allocate(ios_runtime.names['NSTimeZone'])
	if object == 0 { return 0 }
	mut header := obj_header(object)
	header.number = seconds
	header.timezone_initialized = true
	return object
}

fn ns_timezone_equal(left u64, right u64) bool {
	a := ns_timezone_seconds(left)
	if right == 0 || !objc_is_kind(right, ios_runtime.names['NSTimeZone']) { return false }
	return swift_timezone_identity(a) == swift_timezone_identity(ns_timezone_seconds(right))
}

fn ns_timezone_hash(object u64) u64 {
	// Hashes are opaque. Native equality compares minute-rounded identifiers,
	// including offsets of opposite signs that both have the identifier GMT.
	return u64(swift_timezone_identity(ns_timezone_seconds(object)))
}

fn ns_timezone_name(object u64) u64 {
	words := swift_timezone_identifier_seconds(ns_timezone_seconds(object))
	return swift_foundation_bridge(words.first, words.second)
}

fn ns_timezone_abbreviation(object u64) u64 {
	minutes := swift_timezone_identity(ns_timezone_seconds(object))
	if minutes == 0 { return owned_string('GMT') }
	positive := if minutes < 0 { -minutes } else { minutes }
	hours := positive / 60
	buffer := u64(C.__builtin_alloca(9))
	C.memcpy(voidptr(buffer), c'GMT', 3)
	unsafe { *(&u8(buffer + 3)) = if minutes < 0 { `-` } else { `+` } }
	mut count := 4
	if hours >= 10 { unsafe { *(&u8(buffer + u64(count))) = u8(`0` + hours / 10) }; count++ }
	unsafe { *(&u8(buffer + u64(count))) = u8(`0` + hours % 10) }; count++
	if positive % 60 != 0 {
		unsafe {
			*(&u8(buffer + u64(count))) = `:`
			*(&u8(buffer + u64(count + 1))) = u8(`0` + (positive % 60) / 10)
			*(&u8(buffer + u64(count + 2))) = u8(`0` + positive % 10)
		}
		count += 3
	}
	return owned_string(unsafe { tos(&u8(buffer), count) })
}

fn ns_timezone_types(name string, meta bool, selector string) ?string {
	if name != 'NSTimeZone' { return none }
	if meta {
		return match selector {
			'alloc' { '@16@0:8' }
			'allocWithZone:' { '@24@0:8^{_NSZone=}16' }
			'timeZoneForSecondsFromGMT:' { '@24@0:8q16' }
			'timeZoneWithAbbreviation:', 'timeZoneWithName:' { '@24@0:8@16' }
			else { return none }
		}
	}
	return match selector {
		'name', 'abbreviation', 'copy', 'nextDaylightSavingTimeTransition' { '@16@0:8' }
		'abbreviationForDate:', 'nextDaylightSavingTimeTransitionAfterDate:' { '@24@0:8@16' }
		'copyWithZone:' { '@24@0:8^{_NSZone=}16' }
		'secondsFromGMT' { 'q16@0:8' }
		'secondsFromGMTForDate:' { 'q24@0:8@16' }
		'isDaylightSavingTime' { 'B16@0:8' }
		'isDaylightSavingTimeForDate:', 'isEqual:', 'isEqualToTimeZone:' { 'B24@0:8@16' }
		'daylightSavingTimeOffset' { 'd16@0:8' }
		'daylightSavingTimeOffsetForDate:' { 'd24@0:8@16' }
		'hash', '_cfTypeID' { 'Q16@0:8' }
		'classForCoder' { '#16@0:8' }
		else { return none }
	}
}

fn ns_timezone_selector(object u64, selector string) bool {
	meta := object in ios_runtime.classes
	return ns_timezone_family(if meta { object } else { read64(object) }) && ns_timezone_types('NSTimeZone', meta, selector) != none
}

fn ns_timezone_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	meta := object in ios_runtime.classes
	if !ns_timezone_family(if meta { object } else { read64(object) }) { return false }
	if selector in ['init', 'new', 'mutableCopy', 'mutableCopyWithZone:', 'description', 'descriptionWithLocale:',
		'initWithName:', 'initWithName:data:', 'timeZoneWithName:abbreviation:',
		'defaultTimeZone', 'localTimeZone', 'systemTimeZone', 'setDefaultTimeZone:', 'resetSystemTimeZone',
		'initWithCoder:', 'encodeWithCoder:', 'supportsSecureCoding', 'localizedName:locale:']! {
		panic('iOS: timezone defaults, named zones, coding and locale formatting are not implemented')
	}
	if ns_timezone_types('NSTimeZone', meta, selector) == none { return false }
	if !meta {
		C.ios_objc_initialize_lock()
		local, _ := ns_timezone_snapshot(object)
		C.ios_objc_initialize_unlock()
		if local { return ns_calendar_local_zone_dispatch(object, selector, mut frame) }
	}
	if meta {
		if selector in ['timeZoneWithAbbreviation:', 'timeZoneWithName:']! {
			C.ios_objc_initialize_lock()
			text := ns_date_formatter_text(frame.x[2])
			if text !in ['UTC', 'GMT']! { panic('iOS: timezone names other than UTC and GMT are not implemented') }
			C.ios_objc_initialize_unlock()
			frame.x[0] = objc_autorelease(ns_timezone_fixed(0))
			return true
		}
		frame.x[0] = if selector == 'timeZoneForSecondsFromGMT:' { objc_autorelease(ns_timezone_fixed(i64(frame.x[2]))) } else { objc_allocate(object) }
		return true
	}
	seconds := ns_timezone_seconds(object)
	if selector.ends_with('ForDate:') || selector == 'nextDaylightSavingTimeTransitionAfterDate:' {
		date := frame.x[2]
		if date != 0 {
			C.ios_objc_initialize_lock()
			if date !in ios_runtime.objects || !ns_date_is_date(date) { C.ios_objc_initialize_unlock(); panic('iOS: timezone query requires a built-in NSDate') }
			ns_date_state(date)
			C.ios_objc_initialize_unlock()
		}
	}
	match selector {
		'name' { frame.x[0] = objc_autorelease(ns_timezone_name(object)) }
		'abbreviation', 'abbreviationForDate:' { frame.x[0] = objc_autorelease(ns_timezone_abbreviation(object)) }
		'secondsFromGMT', 'secondsFromGMTForDate:' { frame.x[0] = u64(seconds) }
		'copy', 'copyWithZone:' { frame.x[0] = objc_retain(object) }
		'isEqual:', 'isEqualToTimeZone:' { frame.x[0] = u64(ns_timezone_equal(object, frame.x[2])) }
		'hash' { frame.x[0] = ns_timezone_hash(object) }
		'classForCoder' { frame.x[0] = ios_runtime.names['NSTimeZone'] }
		'_cfTypeID' { frame.x[0] = ios_runtime.names['NSTimeZone'] }
		'daylightSavingTimeOffset', 'daylightSavingTimeOffsetForDate:' { frame_float_return(mut frame, 0, 0) }
		else { frame.x[0] = 0 } // Fixed zones have no DST and no future transition.
	}
	return true
}

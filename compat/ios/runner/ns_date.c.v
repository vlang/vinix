// SPDX-License-Identifier: GPL-2.0-or-later
module main

import math

// NSDate's public class is eight bytes. Vinix keeps its immutable double in
// existing owned metadata and uses the same heap representation as CFDate.
fn ns_date_family(cls u64) bool {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return false }
		if info.name == 'NSDate' { return true }
		current = info.parent
		if current == 0 { return false }
	}
	panic('iOS: cyclic date superclass chain')
}

fn ns_date_allocation_class(cls u64) u64 {
	if cls == ios_runtime.names['NSDate'] { return cf_date_id() }
	if ns_date_family(cls) && cls != cf_date_id() { panic('iOS: custom date subclass construction is not implemented') }
	return cls
}

fn ns_date_is_date(object u64) bool {
	return object != 0 && object !in ios_runtime.classes && ns_date_family(read64(object))
}

fn ns_date_state(object u64) &ObjHeader {
	header := obj_header(object)
	if !header.date_owned || !header.date_initialized { panic('iOS: date is not initialized') }
	return header
}

fn ns_date_initialize(object u64, absolute f64) {
	mut header := obj_header(object)
	if !header.date_owned { panic('iOS: date initialization requires owned date metadata') }
	if header.date_initialized { panic('iOS: immutable date reinitialization is not implemented') }
	if !math.is_finite(absolute) { panic('iOS: NSDate construction requires a finite interval') }
	header.real_number = absolute
	header.date_initialized = true
}

fn ns_date_equal(left u64, right u64) bool {
	if !ns_date_is_date(right) { return false }
	return ns_date_state(left).real_number == ns_date_state(right).real_number
}

fn ns_date_compare(left u64, right u64) i64 {
	if right == 0 { return 0 }
	if !ns_date_is_date(right) { panic('iOS: date comparison requires NSDate') }
	a := ns_date_state(left).real_number
	b := ns_date_state(right).real_number
	return i64(a > b) - i64(a < b)
}

fn ns_date_hash(object u64) u64 {
	value := ns_date_state(object).real_number
	// Hashes are opaque; normalize signed zero so equal dates hash equally.
	return if value == 0 { u64(0) } else { unsafe { *(&u64(&value)) } }
}

fn ns_date_description(object u64) u64 {
	seconds := ns_date_state(object).real_number + 978307200.0
	if !math.is_finite(seconds) || seconds < -62135596800.0 || seconds >= 253402300800.0 { panic('iOS: date description is outside UTC years 1 through 9999') }
	whole := i64(math.floor(seconds))
	mut calendar := [7]u64{}
	if C.ios_gmtime_r(unsafe { &whole }, unsafe { &calendar[0] }) == unsafe { nil } { panic('iOS: date UTC conversion failed') }
	fields := unsafe { &i32(&calendar[0]) }
	mut bytes := [32]u8{}
	length := unsafe { C.snprintf(&char(&bytes[0]), bytes.len, c'%04d-%02d-%02d %02d:%02d:%02d +0000',
		i32(fields[5] + 1900), i32(fields[4] + 1), fields[3], fields[2], fields[1], fields[0]) }
	if length != 25 { panic('iOS: date UTC formatting failed') }
	return owned_string(unsafe { tos(&bytes[0], length) })
}

fn ns_date_distant(future bool) u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	index := int(future)
	if ios_runtime.distant_dates[index] == 0 { ios_runtime.distant_dates[index] = cf_date_create(0, if future { f64(63113904000) } else { f64(-63114076800) }) }
	return ios_runtime.distant_dates[index]
}

fn ns_date_stop() {
	for index in 0 .. 2 { object := ios_runtime.distant_dates[index]; ios_runtime.distant_dates[index] = 0; objc_release(object) }
}

fn ns_date_types(name string, meta bool, selector string) ?string {
	if name != 'NSDate' && name != 'VinixCFDate' { return none }
	if meta {
		return match selector {
			'alloc', 'new', 'date', 'now', 'distantPast', 'distantFuture' { '@16@0:8' }
			'allocWithZone:' { '@24@0:8^{_NSZone=}16' }
			'timeIntervalSinceReferenceDate' { 'd16@0:8' }
			'dateWithTimeIntervalSinceReferenceDate:', 'dateWithTimeIntervalSince1970:', 'dateWithTimeIntervalSinceNow:' { '@24@0:8d16' }
			'dateWithTimeInterval:sinceDate:' { '@32@0:8d16@24' }
			'dateWithDate:' { '@24@0:8@16' }
			else { return none }
		}
	}
	return match selector {
		'init', 'copy', 'description' { '@16@0:8' }
		'copyWithZone:' { '@24@0:8^{_NSZone=}16' }
		'initWithTimeIntervalSinceReferenceDate:', 'initWithTimeIntervalSince1970:', 'initWithTimeIntervalSinceNow:', 'dateByAddingTimeInterval:' { '@24@0:8d16' }
		'initWithTimeInterval:sinceDate:' { '@32@0:8d16@24' }
		'initWithDate:', 'earlierDate:', 'laterDate:' { '@24@0:8@16' }
		'timeIntervalSinceReferenceDate', 'timeIntervalSince1970', 'timeIntervalSinceNow' { 'd16@0:8' }
		'timeIntervalSinceDate:' { 'd24@0:8@16' }
		'isEqualToDate:', 'isEqual:' { 'B24@0:8@16' }
		'compare:' { 'q24@0:8@16' }
		'hash', '_cfTypeID' { 'Q16@0:8' }
		'classForCoder' { '#16@0:8' }
		else { return none }
	}
}

fn ns_date_selector(object u64, selector string) bool {
	meta := object in ios_runtime.classes
	return ns_date_family(if meta { object } else { read64(object) }) && ns_date_types('NSDate', meta, selector) != none
}

fn ns_date_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	meta := object in ios_runtime.classes
	if !ns_date_family(if meta { object } else { read64(object) }) { return false }
	if selector in ['mutableCopy', 'mutableCopyWithZone:', 'initWithCoder:', 'encodeWithCoder:', 'supportsSecureCoding', 'initWithString:', 'dateWithString:', 'descriptionWithLocale:']! { panic('iOS: date parsing, coding, mutable copies and locale formatting are not implemented') }
	if ns_date_types('NSDate', meta, selector) == none { return false }
	if selector in ['alloc', 'allocWithZone:']! && meta { frame.x[0] = objc_allocate(object); return true }
	if selector == 'new' && meta { frame.x[0] = objc_new(object); return true }
	if selector in ['distantPast', 'distantFuture']! && meta { frame.x[0] = ns_date_distant(selector == 'distantFuture'); return true }
	if selector in ['timeIntervalSinceReferenceDate', 'timeIntervalSince1970', 'timeIntervalSinceNow', 'timeIntervalSinceDate:']! {
		value := if meta { cf_absolute_time() } else { ns_date_state(object).real_number }
		result := match selector {
			'timeIntervalSince1970' { value + 978307200.0 }
			'timeIntervalSinceNow' { value - cf_absolute_time() }
			'timeIntervalSinceDate:' { if frame.x[2] == 0 { math.nan() } else { value - cf_date_absolute(frame.x[2]) } }
			else { value }
		}
		frame_float_return(mut frame, 0, result)
		return true
	}
	if !meta && selector in ['copy', 'copyWithZone:', 'description', 'compare:', 'earlierDate:', 'laterDate:', 'isEqual:', 'isEqualToDate:', 'hash', '_cfTypeID', 'classForCoder', 'dateByAddingTimeInterval:']! {
		match selector {
			'copy', 'copyWithZone:' { ns_date_state(object); frame.x[0] = objc_retain(object) }
			'description' { frame.x[0] = objc_autorelease(ns_date_description(object)) }
			'compare:' { frame.x[0] = u64(ns_date_compare(object, frame.x[2])) }
			'earlierDate:', 'laterDate:' { order := ns_date_compare(object, frame.x[2]); frame.x[0] = if (selector == 'earlierDate:' && order > 0) || (selector == 'laterDate:' && order < 0) { frame.x[2] } else { object } }
			'isEqual:', 'isEqualToDate:' { frame.x[0] = u64(ns_date_equal(object, frame.x[2])) }
			'hash' { frame.x[0] = ns_date_hash(object) }
			'_cfTypeID' { frame.x[0] = cf_date_id() }
			'classForCoder' { frame.x[0] = ios_runtime.names['NSDate'] }
			else { absolute := ns_date_state(object).real_number + frame_double(frame, 0); if !math.is_finite(absolute) { panic('iOS: date arithmetic requires a finite interval') }; frame.x[0] = objc_autorelease(cf_date_create(0, absolute)) }
		}
		return true
	}
	mut absolute := frame_double(frame, 0)
	if selector in ['init', 'date', 'now']! { absolute = cf_absolute_time() }
	else if selector.ends_with('Since1970:') { absolute -= 978307200.0 }
	else if selector.ends_with('SinceNow:') { absolute += cf_absolute_time() }
	else if selector.ends_with(':sinceDate:') { absolute += cf_date_absolute(frame.x[2]) }
	else if selector in ['initWithDate:', 'dateWithDate:']! { absolute = cf_date_absolute(frame.x[2]) }
	if meta {
		if !math.is_finite(absolute) { panic('iOS: NSDate construction requires a finite interval') }
		frame.x[0] = objc_autorelease(cf_date_create(0, absolute))
	} else { ns_date_initialize(object, absolute) }
	return true
}

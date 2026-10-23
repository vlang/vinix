// SPDX-License-Identifier: GPL-2.0-or-later
module main

import math
import os

$if macos {
	#flag -framework Foundation
	#include <objc/runtime.h>
}
#include <dlfcn.h>
#include <time.h>
#define ns_calendar_fixture_gmtime_r gmtime_r
#define ns_calendar_fixture_localtime_r localtime_r
#define ns_calendar_fixture_mktime mktime
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.class_getInstanceMethod(voidptr, voidptr) voidptr
fn C.method_getTypeEncoding(voidptr) &char
fn C.class_getInstanceSize(voidptr) usize
fn C.class_getSuperclass(voidptr) voidptr
fn C.class_copyIvarList(voidptr, &u32) voidptr
fn C.objc_storeWeak(&u64, voidptr) voidptr
fn C.ns_calendar_fixture_gmtime_r(voidptr, voidptr) voidptr
fn C.ns_calendar_fixture_localtime_r(voidptr, voidptr) voidptr
fn C.ns_calendar_fixture_mktime(voidptr) i64

type NSCalendarSend = fn (u64, u64, u64, u64, u64) u64
type NSCalendarRealSend = fn (u64, u64, f64) u64
type NSCalendarRealGet = fn (u64, u64) f64
struct NSCalendarApi { native bool send u64 }

fn (api NSCalendarApi) cls(name string) u64 {
	$if macos { if api.native { return u64(C.objc_getClass(name.str)) } }
	return ios_runtime.names[name]
}
fn (api NSCalendarApi) sel(name &char) u64 {
	$if macos { if api.native { return u64(C.sel_registerName(name)) } }
	return u64(name)
}
fn (api NSCalendarApi) msg(object u64, name &char, a u64, b u64, c u64) u64 {
	return unsafe { NSCalendarSend(voidptr(api.send))(object, api.sel(name), a, b, c) }
}
fn (api NSCalendarApi) retain(object u64) u64 { return api.msg(object, c'retain', 0, 0, 0) }
fn (api NSCalendarApi) release(object u64) { api.msg(object, c'release', 0, 0, 0) }
fn (api NSCalendarApi) string(value string) u64 { return api.msg(api.cls('NSString'), c'stringWithUTF8String:', u64(value.str), 0, 0) }
fn (api NSCalendarApi) text(object u64) string {
	assert object != 0
	pointer := api.msg(object, c'UTF8String', 0, 0, 0); assert pointer != 0
	return unsafe { (&char(voidptr(pointer))).vstring() }
}
fn (api NSCalendarApi) pool() u64 {
	$if macos { if api.native { return api.msg(api.cls('NSAutoreleasePool'), c'new', 0, 0, 0) } }
	return objc_pool_push()
}
fn (api NSCalendarApi) pop(pool u64) {
	$if macos { if api.native { api.msg(pool, c'drain', 0, 0, 0); return } }
	objc_pool_pop(pool)
}
fn (api NSCalendarApi) weak(slot &u64, object u64) {
	$if macos { if api.native { C.objc_storeWeak(slot, unsafe { voidptr(object) }); return } }
	objc_store_weak(slot, object)
}
fn (api NSCalendarApi) weak_destroy(slot &u64) {
	$if macos { if api.native { C.objc_storeWeak(slot, unsafe { nil }); return } }
	objc_destroy_weak(slot)
}
fn (api NSCalendarApi) date(seconds f64) u64 {
	return unsafe { NSCalendarRealSend(voidptr(api.send))(api.cls('NSDate'), api.sel(c'dateWithTimeIntervalSince1970:'), seconds) }
}
fn (api NSCalendarApi) seconds(date u64) f64 {
	return unsafe { NSCalendarRealGet(voidptr(api.send))(date, api.sel(c'timeIntervalSince1970')) }
}
fn (api NSCalendarApi) zone(seconds i64) u64 { return api.msg(api.cls('NSTimeZone'), c'timeZoneForSecondsFromGMT:', u64(seconds), 0, 0) }
fn (api NSCalendarApi) calendar(identifier string) u64 {
	return api.msg(api.msg(api.cls('NSCalendar'), c'alloc', 0, 0, 0), c'initWithCalendarIdentifier:', api.string(identifier), 0, 0)
}
fn (api NSCalendarApi) components(values [6]i64) u64 {
	object := api.msg(api.cls('NSDateComponents'), c'new', 0, 0, 0)
	for i, setter in [c'setYear:', c'setMonth:', c'setDay:', c'setHour:', c'setMinute:', c'setSecond:']! { api.msg(object, setter, u64(values[i]), 0, 0) }
	return object
}
fn ns_calendar_fields(api NSCalendarApi, object u64) [6]i64 {
	mut fields := [6]i64{}
	for i, getter in [c'year', c'month', c'day', c'hour', c'minute', c'second']! { fields[i] = i64(api.msg(object, getter, 0, 0, 0)) }
	return fields
}
fn ns_calendar_libc_fields(seconds i64, local bool) [6]i64 {
	mut value := seconds; mut storage := [7]u64{}
	result := if local { C.ns_calendar_fixture_localtime_r(unsafe { &value }, unsafe { voidptr(&storage[0]) }) } else { C.ns_calendar_fixture_gmtime_r(unsafe { &value }, unsafe { voidptr(&storage[0]) }) }
	assert result != unsafe { nil }
	fields := unsafe { &i32(&storage[0]) }
	return unsafe { [i64(fields[5] + 1900), i64(fields[4] + 1), i64(fields[3]), i64(fields[2]), i64(fields[1]), i64(fields[0])]! }
}
fn ns_calendar_libc_seconds(values [6]i64) i64 {
	mut storage := [7]u64{}; fields := unsafe { &i32(&storage[0]) }
	unsafe { fields[0] = int(values[5]); fields[1] = int(values[4]); fields[2] = int(values[3]); fields[3] = int(values[2]); fields[4] = int(values[1] - 1); fields[5] = int(values[0] - 1900); fields[8] = -1 }
	return C.ns_calendar_fixture_mktime(unsafe { voidptr(&storage[0]) })
}
fn ns_calendar_metadata(api NSCalendarApi) {
	for name in ['NSCalendar', 'NSDateComponents']! {
		cls := api.cls(name); assert cls != 0
		$if macos { if api.native { assert C.class_getInstanceSize(unsafe { voidptr(cls) }) == 8; assert u64(C.class_getSuperclass(unsafe { voidptr(cls) })) == api.cls('NSObject'); mut count := u32(0); list := C.class_copyIvarList(unsafe { voidptr(cls) }, unsafe { &count }); assert count == 0; C.free(list) } }
		if !api.native { assert objc_class_size(cls) == 8 && objc_class_parent(cls) == api.cls('NSObject'); mut count := u32(1); list := objc_copy_ivars(cls, unsafe { &count }); assert count == 0; C.free(list) }
		mut types := {'init': '@16@0:8', 'copyWithZone:': '@24@0:8^{_NSZone=}16', 'timeZone': '@16@0:8', 'setTimeZone:': 'v24@0:8@16'}
		if name == 'NSCalendar' {
			for selector, encoding in {'initWithCalendarIdentifier:': '@24@0:8@16', 'calendarIdentifier': '@16@0:8', 'firstWeekday': 'Q16@0:8', 'setFirstWeekday:': 'v24@0:8Q16', 'minimumDaysInFirstWeek': 'Q16@0:8', 'setMinimumDaysInFirstWeek:': 'v24@0:8Q16', 'components:fromDate:': '@32@0:8Q16@24', 'componentsInTimeZone:fromDate:': '@32@0:8@16@24', 'dateFromComponents:': '@24@0:8@16'} { types[selector] = encoding }
		} else {
			for field in ['era', 'year', 'month', 'day', 'hour', 'minute', 'second', 'nanosecond', 'weekday', 'weekdayOrdinal', 'quarter', 'weekOfMonth', 'weekOfYear', 'yearForWeekOfYear']! { types[field] = 'q16@0:8' }
			for field in ['Era', 'Year', 'Month', 'Day', 'Hour', 'Minute', 'Second', 'Nanosecond', 'Weekday', 'WeekdayOrdinal', 'Quarter', 'WeekOfMonth', 'WeekOfYear', 'YearForWeekOfYear']! { types['set' + field + ':'] = 'v24@0:8q16' }
			types['calendar'] = '@16@0:8'; types['setCalendar:'] = 'v24@0:8@16'; types['isLeapMonth'] = 'B16@0:8'; types['setLeapMonth:'] = 'v20@0:8B16'
		}
		for selector, encoding in types {
			mut actual := ''
			$if macos { if api.native { method := C.class_getInstanceMethod(unsafe { voidptr(cls) }, unsafe { voidptr(api.sel(selector.str)) }); assert method != unsafe { nil }; actual = unsafe { C.method_getTypeEncoding(method).vstring() } } }
			if !api.native { method := objc_instance_method(cls, u64(selector.str)); assert method != 0; actual = ctext(u64(objc_method_types(method))) }
			assert actual == encoding, name + '.' + selector + ' ' + actual
		}
	}
}
fn ns_calendar_shared_defaults(api NSCalendarApi) {
	pool := api.pool(); ns_calendar_metadata(api)
	cls := api.cls('NSCalendar')
	assert api.msg(cls, c'new', 0, 0, 0) == 0
	assert api.msg(api.msg(cls, c'alloc', 0, 0, 0), c'init', 0, 0, 0) == 0
	assert api.msg(api.msg(cls, c'alloc', 0, 0, 0), c'initWithCalendarIdentifier:', 0, 0, 0) == 0
	for identifier in ['invented', 'ISO8601']! { assert api.calendar(identifier) == 0 }
	for i, identifier in ['gregorian', 'iso8601']! {
		calendar := api.calendar(identifier); assert calendar != 0
		assert api.text(api.msg(calendar, c'calendarIdentifier', 0, 0, 0)) == identifier
		assert api.msg(calendar, c'firstWeekday', 0, 0, 0) == [u64(1), 2]![i]
		assert api.msg(calendar, c'minimumDaysInFirstWeek', 0, 0, 0) == [u64(1), 4]![i]
		api.release(calendar)
	}
	components := api.msg(api.cls('NSDateComponents'), c'new', 0, 0, 0)
	for field in [c'era', c'year', c'month', c'day', c'hour', c'minute', c'second', c'nanosecond', c'weekday', c'weekdayOrdinal', c'quarter', c'weekOfMonth', c'weekOfYear', c'yearForWeekOfYear']! { assert api.msg(components, field, 0, 0, 0) == 0x7fffffffffffffff }
	assert api.msg(components, c'isLeapMonth', 0, 0, 0) == 0 && api.msg(components, c'calendar', 0, 0, 0) == 0 && api.msg(components, c'timeZone', 0, 0, 0) == 0
	for value in [i64(-99), 0, 2024, i64(0x7fffffffffffffff)]! { api.msg(components, c'setYear:', u64(value), 0, 0); assert i64(api.msg(components, c'year', 0, 0, 0)) == value }
	api.release(components); api.pop(pool)
}
fn ns_calendar_shared_fixed(api NSCalendarApi) {
	pool := api.pool()
	for identifier in ['gregorian', 'iso8601']! {
		calendar := api.calendar(identifier)
		for offset in [i64(-64800), -19800, 0, 19800, 64800]! {
			zone := api.zone(offset); assert zone != 0; api.msg(calendar, c'setTimeZone:', zone, 0, 0)
			assert i64(api.msg(api.msg(calendar, c'timeZone', 0, 0, 0), c'secondsFromGMT', 0, 0, 0)) == offset
			for value in [-12212488800.0, 0.0, -0.5, 1.5, 1709210096.75, 1609459200.0, 253402235999.0]! {
				date := api.date(value); components := api.msg(calendar, c'components:fromDate:', 252, date, 0)
				assert ns_calendar_fields(api, components) == ns_calendar_libc_fields(i64(math.floor(value)) + offset, false)
				for field in [c'era', c'nanosecond', c'weekday', c'weekdayOrdinal', c'quarter', c'weekOfMonth', c'weekOfYear', c'yearForWeekOfYear']! { assert api.msg(components, field, 0, 0, 0) == 0x7fffffffffffffff }
				assert api.msg(components, c'calendar', 0, 0, 0) == 0 && api.msg(components, c'timeZone', 0, 0, 0) == 0
				full := api.msg(calendar, c'componentsInTimeZone:fromDate:', zone, date, 0)
				assert ns_calendar_fields(api, full) == ns_calendar_fields(api, components)
				assert api.msg(full, c'era', 0, 0, 0) == 1 && api.msg(full, c'isLeapMonth', 0, 0, 0) == 0
				assert api.msg(full, c'nanosecond', 0, 0, 0) == if value == -0.5 || value == 1.5 { u64(500000000) } else if value == 1709210096.75 { u64(750000000) } else { u64(0) }
				assert api.msg(full, c'calendar', 0, 0, 0) != 0 && api.msg(full, c'timeZone', 0, 0, 0) != 0
			}
		}
		zone := api.zone(0)
		for value in [0.1, -0.1, 0.9999999, 1.0000001, 1709210096.1234567]! {
			date := api.date(value); stored := api.seconds(date)
			full := api.msg(calendar, c'componentsInTimeZone:fromDate:', zone, date, 0)
			assert api.msg(full, c'nanosecond', 0, 0, 0) == u64((stored - math.floor(stored)) * 1000000000.0)
		}
		api.release(calendar)
	}
	api.pop(pool)
}
fn ns_calendar_shared_weeks(api NSCalendarApi) {
	pool := api.pool(); zone := api.zone(0)
	for identifier in ['iso8601', 'gregorian']! {
		calendar := api.calendar(identifier); api.msg(calendar, c'setTimeZone:', zone, 0, 0)
		for i, value in [1609459200.0, 1609372800.0, 1640995200.0, 1672531200.0, 1704067200.0]! {
			full := api.msg(calendar, c'componentsInTimeZone:fromDate:', zone, api.date(value), 0)
			assert api.msg(full, c'weekday', 0, 0, 0) == [u64(6), 5, 7, 1, 2]![i]
			assert api.msg(full, c'weekdayOrdinal', 0, 0, 0) == [u64(1), 5, 1, 1, 1]![i]
			assert api.msg(full, c'quarter', 0, 0, 0) == [u64(1), 4, 1, 1, 1]![i]
			assert api.msg(full, c'weekOfMonth', 0, 0, 0) == if identifier == 'iso8601' { [u64(0), 5, 0, 0, 1]![i] } else { [u64(1), 5, 1, 1, 1]![i] }
			assert api.msg(full, c'weekOfYear', 0, 0, 0) == if identifier == 'iso8601' { [u64(53), 53, 52, 52, 1]![i] } else { u64(1) }
			assert api.msg(full, c'yearForWeekOfYear', 0, 0, 0) == if identifier == 'iso8601' { [u64(2020), 2020, 2021, 2022, 2024]![i] } else { [u64(2021), 2021, 2022, 2023, 2024]![i] }
		}
		api.release(calendar)
	}
	api.pop(pool)
}
fn ns_calendar_shared_construct(api NSCalendarApi) {
	pool := api.pool(); calendar := api.calendar('iso8601'); api.msg(calendar, c'setTimeZone:', api.zone(0), 0, 0)
	for values in [[i64(2001), 1, 1, 0, 0, 0]!, [i64(2024), 2, 29, 23, 59, 59]!, [i64(2023), 2, 29, 25, 61, 61]!, [i64(2001), 0, 0, 0, 0, 0]!] {
		components := api.components(values); date := api.msg(calendar, c'dateFromComponents:', components, 0, 0); assert date != 0
		actual := ns_calendar_fields(api, api.msg(calendar, c'components:fromDate:', 252, date, 0))
		expected := if values[0] == 2023 { [i64(2023), 3, 2, 2, 2, 1]! } else if values[1] == 0 { [i64(2000), 11, 30, 0, 0, 0]! } else { values }
		assert actual == expected
		if values[0] == 2001 && values[1] == 1 { assert api.seconds(date) == 978307200.0 }
		api.release(components)
	}
	components := api.msg(api.cls('NSDateComponents'), c'new', 0, 0, 0)
	api.msg(components, c'setYear:', 2001, 0, 0); api.msg(components, c'setMonth:', 1, 0, 0); api.msg(components, c'setDay:', 1, 0, 0)
	api.msg(components, c'setTimeZone:', api.zone(19800), 0, 0)
	assert api.seconds(api.msg(calendar, c'dateFromComponents:', components, 0, 0)) == 978287400.0
	api.release(components); api.release(calendar); api.pop(pool)
}
fn ns_calendar_shared_local(api NSCalendarApi) {
	pool := api.pool()
	for selector in [c'currentCalendar', c'autoupdatingCurrentCalendar']! {
		calendar := api.msg(api.cls('NSCalendar'), selector, 0, 0, 0); assert calendar != 0
		local := api.msg(calendar, c'timeZone', 0, 0, 0); assert local != 0
		for value in [-12212488800.0, 0.0, -0.5, 1709210096.75, 1710055800.0, 1730611800.0, 253402235999.0]! {
			date := api.date(value); components := api.msg(calendar, c'components:fromDate:', 252, date, 0)
			assert ns_calendar_fields(api, components) == ns_calendar_libc_fields(i64(math.floor(value)), true)
			full := api.msg(calendar, c'componentsInTimeZone:fromDate:', local, date, 0)
			assert ns_calendar_fields(api, full) == ns_calendar_fields(api, components)
		}
		for values in [[i64(1970), 1, 1, 0, 0, 0]!, [i64(2024), 2, 29, 12, 34, 56]!] {
			components := api.components(values)
			assert api.seconds(api.msg(calendar, c'dateFromComponents:', components, 0, 0)) == f64(ns_calendar_libc_seconds(values))
			api.release(components)
		}
		if os.getenv('TZ') == 'America/New_York' {
			for i, values in [[i64(2024), 3, 10, 2, 30, 0]!, [i64(2024), 11, 3, 1, 30, 0]!] {
				components := api.components(values)
				assert api.seconds(api.msg(calendar, c'dateFromComponents:', components, 0, 0)) == [1710055800.0, 1730611800.0]![i]
				api.release(components)
			}
		}
	}
	api.pop(pool)
}
fn ns_calendar_shared_copies(api NSCalendarApi) {
	pool := api.pool(); calendar := api.calendar('iso8601'); zone := api.zone(19800)
	api.msg(calendar, c'setTimeZone:', zone, 0, 0); api.msg(calendar, c'setFirstWeekday:', 3, 0, 0); api.msg(calendar, c'setMinimumDaysInFirstWeek:', 5, 0, 0)
	duplicate := api.msg(calendar, c'copy', 0, 0, 0); assert duplicate != 0 && duplicate != calendar
	api.msg(calendar, c'setFirstWeekday:', 6, 0, 0)
	assert api.msg(duplicate, c'firstWeekday', 0, 0, 0) == 3 && api.msg(duplicate, c'minimumDaysInFirstWeek', 0, 0, 0) == 5
	identifier := api.retain(api.msg(duplicate, c'calendarIdentifier', 0, 0, 0)); getter := api.retain(api.msg(duplicate, c'timeZone', 0, 0, 0))
	api.release(calendar); api.release(duplicate)
	assert api.text(identifier) == 'iso8601' && api.msg(getter, c'secondsFromGMT', 0, 0, 0) == 19800
	api.release(identifier); api.release(getter)
	components := api.components([i64(2024), 2, 29, 12, 34, 56]!)
	calendar2 := api.calendar('iso8601'); api.msg(calendar2, c'setTimeZone:', zone, 0, 0)
	api.msg(components, c'setCalendar:', calendar2, 0, 0); api.msg(components, c'setTimeZone:', zone, 0, 0)
	api.msg(calendar2, c'setFirstWeekday:', 6, 0, 0)
	assert api.msg(api.msg(components, c'calendar', 0, 0, 0), c'firstWeekday', 0, 0, 0) == 2
	duplicate2 := api.msg(components, c'copy', 0, 0, 0); assert duplicate2 != components && duplicate2 != 0
	api.msg(components, c'setYear:', 2023, 0, 0)
	api.msg(api.msg(components, c'calendar', 0, 0, 0), c'setFirstWeekday:', 7, 0, 0)
	assert api.msg(duplicate2, c'year', 0, 0, 0) == 2024
	assert api.msg(api.msg(duplicate2, c'calendar', 0, 0, 0), c'firstWeekday', 0, 0, 0) == 2
	api.release(calendar2); api.release(components); api.release(duplicate2); api.pop(pool)
}
fn ns_calendar_shared(api NSCalendarApi) {
	ns_calendar_shared_defaults(api); ns_calendar_shared_fixed(api); ns_calendar_shared_weeks(api)
	ns_calendar_shared_construct(api); ns_calendar_shared_local(api); ns_calendar_shared_copies(api)
}

fn test_ns_calendar() {
	$if macos {
		send := u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend')); assert send != 0
		ns_calendar_shared(NSCalendarApi{true, send})
		println('IOS-NS-CALENDAR-NATIVE: public layout and encodings, ISO and Gregorian snapshots, minute-aligned fixed/local extraction, week edges, normalized components and independent copies PASS')
	}
	for _ in 0 .. 2 {
		objc_start(); system_data_start()!; api := ns_calendar_runtime_api(); ns_calendar_shared(api)
		ns_calendar_runtime_lifetimes(api)
		objc_stop(); assert ios_runtime.live == 0 && ios_runtime.objects.len == 0; system_data_stop()
	}
	println('IOS-NS-CALENDAR: public layout and encodings, ISO and Gregorian snapshots, minute-aligned fixed/local extraction, week edges, normalized components, independent copies, unlocked joined-worker snapshots, failed constructors, guarded storage, isa disposal and two drained lifetimes PASS')
}

fn ns_calendar_runtime_api() NSCalendarApi { return NSCalendarApi{false, u64(unsafe { voidptr(C.ios_objc_msgsend) })} }

__global ns_calendar_callback_mode = ''
__global ns_calendar_callback_target = u64(0)
__global ns_calendar_callback_source = u64(0)
__global ns_calendar_callback_fired = false
__global ns_calendar_callback_weak = u64(0)
__global ns_calendar_callback_calendar_weak = u64(0)

fn ns_calendar_callback_worker() {
	api := ns_calendar_runtime_api(); pool := api.pool()
	C.ios_objc_initialize_lock(); C.ios_objc_initialize_unlock()
	if ns_calendar_callback_mode in ['copy', 'extract', 'full']! {
		source := ns_calendar_callback_source
		assert api.msg(source, c'firstWeekday', 0, 0, 0) == 2
		api.msg(source, c'setFirstWeekday:', 6, 0, 0); api.msg(source, c'setTimeZone:', api.zone(-19800), 0, 0)
		api.release(source)
	}
	if ns_calendar_callback_mode == 'identifier' {
		api.msg(ns_calendar_callback_source, c'setString:', api.string('gregorian'), 0, 0)
		api.release(ns_calendar_callback_source)
	}
	api.pop(pool)
}

fn ns_calendar_constructor(object u64, _selector &char) u64 {
	if ns_calendar_callback_mode == '' || ns_calendar_callback_fired || read64(object) != ns_calendar_callback_target { return object }
	ns_calendar_callback_fired = true
	if ns_calendar_callback_mode == 'destruct' { objc_destruct_instance(ns_calendar_callback_source); return object }
	if ns_calendar_callback_mode == 'constructor-isa' { objc_set_class(object, ios_runtime.names['NSObject']); return object }
	if ns_calendar_callback_mode == 'constructor-state' { obj_header(object).calendar.initialized = true; return object }
	worker := spawn ns_calendar_callback_worker(); worker.wait()
	if ns_calendar_callback_mode == 'fail' {
		api := ns_calendar_runtime_api()
		objc_store_weak(unsafe { &ns_calendar_callback_weak }, object)
		if read64(object) == api.cls('NSDateComponents') {
			api.msg(object, c'init', 0, 0, 0)
			calendar := api.calendar('iso8601'); api.msg(object, c'setCalendar:', calendar, 0, 0); api.release(calendar)
			api.msg(object, c'setTimeZone:', api.zone(19800), 0, 0)
			objc_store_weak(unsafe { &ns_calendar_callback_calendar_weak }, obj_header(object).fields[1])
		}
		return 0
	}
	return object
}

fn ns_calendar_callback_set(mode string, target u64, source u64) {
	ns_calendar_callback_mode = mode; ns_calendar_callback_target = target; ns_calendar_callback_source = source; ns_calendar_callback_fired = false
}

fn ns_calendar_override(_object u64, _selector &char) u64 { return 99 }

fn ns_calendar_runtime_lifetimes(api NSCalendarApi) {
	pool := api.pool(); calendar_cls := api.cls('NSCalendar'); components_cls := api.cls('NSDateComponents')
	for name in ['NSCalendar', 'NSDateComponents']! {
		for library in ['/System/Library/Frameworks/Foundation.framework/Foundation', '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation']! {
			assert runtime_symbol(library, '_OBJC_CLASS_$_' + name) or { panic(err) } == api.cls(name)
			assert runtime_symbol(library, '_OBJC_METACLASS_$_' + name) or { panic(err) } == read64(api.cls(name))
		}
		assert objc_add_method(api.cls(name), u64(c'.cxx_construct'), u64(unsafe { voidptr(ns_calendar_constructor) }), c'@16@0:8')
	}
	// Destination constructors join a worker that mutates the source and drops
	// its last caller-owned reference. Neither runtime locks nor borrowed state
	// may cross the callback, and the returned copy must retain the old snapshot.
	for mode in ['copy', 'extract', 'full']! {
		source := api.calendar('iso8601'); api.msg(source, c'setTimeZone:', api.zone(19800), 0, 0)
		mut weak := u64(0); objc_store_weak(unsafe { &weak }, source)
		ns_calendar_callback_set(mode, if mode in ['copy', 'full']! { calendar_cls } else { components_cls }, source)
		result := if mode == 'copy' { api.msg(source, c'copy', 0, 0, 0) } else if mode == 'full' { api.msg(source, c'componentsInTimeZone:fromDate:', api.zone(0), api.date(0), 0) } else { api.msg(source, c'components:fromDate:', 252, api.date(0), 0) }
		ns_calendar_callback_mode = ''
		assert ns_calendar_callback_fired && weak == 0 && result != 0
		if mode == 'copy' {
			assert api.msg(result, c'firstWeekday', 0, 0, 0) == 2
			assert api.msg(api.msg(result, c'timeZone', 0, 0, 0), c'secondsFromGMT', 0, 0, 0) == 19800
			api.release(result)
		} else if mode == 'full' {
			assert ns_calendar_fields(api, result) == [i64(1970), 1, 1, 0, 0, 0]!
			copied := api.msg(result, c'calendar', 0, 0, 0)
			assert api.msg(copied, c'firstWeekday', 0, 0, 0) == 2
			assert api.msg(api.msg(copied, c'timeZone', 0, 0, 0), c'secondsFromGMT', 0, 0, 0) == 0
		} else { assert ns_calendar_fields(api, result) == [i64(1970), 1, 1, 5, 30, 0]! }
		objc_destroy_weak(unsafe { &weak })
	}
	identifier := api.msg(api.msg(api.cls('NSMutableString'), c'alloc', 0, 0, 0), c'initWithString:', api.string('iso8601'), 0, 0)
	mut identifier_weak := u64(0); objc_store_weak(unsafe { &identifier_weak }, identifier)
	ns_calendar_callback_set('identifier', calendar_cls, identifier)
	created := api.msg(calendar_cls, c'calendarWithIdentifier:', identifier, 0, 0)
	ns_calendar_callback_mode = ''
	assert ns_calendar_callback_fired && identifier_weak == 0 && api.text(api.msg(created, c'calendarIdentifier', 0, 0, 0)) == 'iso8601'
	objc_destroy_weak(unsafe { &identifier_weak })
	// Failure cleanup must retire fields installed by the constructor itself,
	// including its independently copied calendar, for all storage origins.
	for cls in [calendar_cls, components_cls]! {
		valid := if cls == calendar_cls { api.calendar('iso8601') } else { api.components([i64(2024), 2, 29, 12, 34, 56]!) }
		for operation in ['new', 'copy', 'caller']! {
			ns_calendar_callback_set('fail', cls, 0)
			mut guarded := [u64(0x1122334455667788), 0, 0x8877665544332211]!
			result := if operation == 'new' { api.msg(cls, c'new', 0, 0, 0) } else if operation == 'copy' { api.msg(valid, c'copy', 0, 0, 0) } else { objc_construct_instance(cls, u64(unsafe { &guarded[1] })) }
			ns_calendar_callback_mode = ''
			assert result == 0 && ns_calendar_callback_fired && ns_calendar_callback_weak == 0 && ns_calendar_callback_calendar_weak == 0
			objc_destroy_weak(unsafe { &ns_calendar_callback_weak }); objc_destroy_weak(unsafe { &ns_calendar_callback_calendar_weak })
			assert guarded[0] == 0x1122334455667788 && guarded[2] == 0x8877665544332211
		}
		api.release(valid)
		mut guarded := [u64(0x1122334455667788), 0, 0x8877665544332211]!
		caller := u64(unsafe { &guarded[1] }); assert objc_construct_instance(cls, caller) == caller
		api.msg(caller, if cls == calendar_cls { c'initWithCalendarIdentifier:' } else { c'init' }, if cls == calendar_cls { api.string('iso8601') } else { u64(0) }, 0, 0)
		assert objc_set_class(caller, api.cls('NSObject')) == cls && objc_destruct_instance(caller) == caller
		assert caller !in ios_runtime.objects && guarded[0] == 0x1122334455667788 && guarded[2] == 0x8877665544332211
		for _ in 0 .. 24 {
			object := if cls == calendar_cls { api.calendar('iso8601') } else { api.components([i64(2024), 2, 29, 12, 34, 56]!) }
			assert objc_set_class(object, api.cls('NSObject')) == cls; api.release(object)
		}
	}
	// Application native methods retain their usual precedence over built-ins.
	overridden := api.calendar('iso8601')
	assert objc_replace_method(calendar_cls, u64(c'firstWeekday'), u64(unsafe { voidptr(ns_calendar_override) }), c'Q16@0:8') != 0
	assert api.msg(overridden, c'firstWeekday', 0, 0, 0) == 99
	api.release(overridden)
	api.pop(pool)
	assert ios_runtime.live == 2 && ios_runtime.objects.len == 2 && ios_runtime.weak.len == 0
}

fn test_ns_calendar_rejections() {
	objc_start(); system_data_start()!; api := ns_calendar_runtime_api()
	modes := ['raw', 'raw-components', 'repeat-init', 'subclass', 'caller-subclass', 'spoof', 'isa-change', 'copy-provenance', 'tombstone', 'identifier-object', 'zone-object', 'zone-raw', 'zone-odd', 'full-zone-nil', 'date-object', 'date-raw', 'date-isa', 'date-low', 'date-high', 'components-object', 'components-calendar', 'calendar-components', 'mask', 'week-low', 'week-high', 'leap', 'year', 'month', 'nanosecond', 'empty', 'week-construction', 'mutable-copy', 'coding', 'locale', 'description', 'local-name', 'local-fixed-helper', 'local-cutover', 'destruct-active', 'constructor-isa', 'constructor-state']!
	for mode in modes {
		mut fds := [2]i32{}; assert C.pipe(unsafe { &fds[0] }) == 0
		pid := C.ios_fork(); assert pid >= 0
		if pid == 0 {
			C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1])
			pool := api.pool(); cls := api.cls('NSCalendar'); calendar := api.calendar('iso8601'); components := api.components([i64(2024), 2, 29, 12, 34, 56]!)
			ns_calendar_callback_mode = ''
			match mode {
				'raw' { api.msg(objc_allocate(cls), c'calendarIdentifier', 0, 0, 0) }
				'raw-components' { api.msg(objc_allocate(api.cls('NSDateComponents')), c'year', 0, 0, 0) }
				'repeat-init' { api.msg(calendar, c'initWithCalendarIdentifier:', api.string('iso8601'), 0, 0) }
				'subclass', 'caller-subclass' {
					custom := objc_allocate_class(cls, c'VinixUnsupportedCalendar', 0); objc_register_class(custom)
					if mode == 'subclass' { objc_allocate(custom) } else { mut storage := [3]u64{}; objc_construct_instance(custom, u64(unsafe { &storage[1] })) }
				}
				'spoof' { value := objc_new(api.cls('NSObject')); objc_set_class(value, cls); api.msg(value, c'calendarIdentifier', 0, 0, 0) }
				'isa-change', 'copy-provenance' { objc_set_class(calendar, api.cls('NSURLRequest')); if mode == 'copy-provenance' { objc_copy_value(calendar, false) } else { api.msg(calendar, c'calendarIdentifier', 0, 0, 0) } }
				'tombstone' { mut storage := [3]u64{}; caller := objc_construct_instance(cls, u64(unsafe { &storage[1] })); api.msg(caller, c'initWithCalendarIdentifier:', api.string('iso8601'), 0, 0); objc_destruct_instance(caller); api.msg(caller, c'calendarIdentifier', 0, 0, 0) }
				'identifier-object' { api.msg(cls, c'calendarWithIdentifier:', objc_new(api.cls('NSObject')), 0, 0) }
				'zone-object', 'zone-raw', 'zone-odd' { zone := if mode == 'zone-odd' { api.zone(29) } else { objc_allocate(api.cls(if mode == 'zone-raw' { 'NSTimeZone' } else { 'NSObject' })) }; api.msg(calendar, c'setTimeZone:', zone, 0, 0) }
				'full-zone-nil' { api.msg(calendar, c'componentsInTimeZone:fromDate:', 0, api.date(0), 0) }
				'date-object', 'date-raw', 'date-isa', 'date-low', 'date-high' {
					date := if mode == 'date-object' { objc_new(api.cls('NSObject')) } else if mode == 'date-raw' { objc_allocate(cf_date_id()) } else { api.date(if mode == 'date-low' { -12212488801.0 } else if mode == 'date-high' { 253402300800.0 } else { 0.0 }) }
					if mode == 'date-isa' { objc_set_class(date, api.cls('NSObject')) }; api.msg(calendar, c'components:fromDate:', 252, date, 0)
				}
				'components-object', 'components-calendar' { api.msg(calendar, c'dateFromComponents:', if mode == 'components-object' { objc_new(api.cls('NSObject')) } else { calendar }, 0, 0) }
				'calendar-components' { api.msg(components, c'setCalendar:', components, 0, 0) }
				'mask' { api.msg(calendar, c'components:fromDate:', 254, api.date(0), 0) }
				'week-low', 'week-high' { api.msg(calendar, if mode == 'week-low' { c'setFirstWeekday:' } else { c'setMinimumDaysInFirstWeek:' }, if mode == 'week-low' { u64(0) } else { u64(8) }, 0, 0) }
				'leap' { api.msg(components, c'setLeapMonth:', 1, 0, 0) }
				'year', 'month', 'nanosecond', 'empty', 'week-construction' {
					if mode == 'empty' { api.msg(calendar, c'dateFromComponents:', api.msg(api.cls('NSDateComponents'), c'new', 0, 0, 0), 0, 0) } else {
						api.msg(components, if mode == 'year' { c'setYear:' } else if mode == 'month' { c'setMonth:' } else if mode == 'nanosecond' { c'setNanosecond:' } else { c'setWeekOfYear:' }, if mode == 'year' { u64(1599) } else if mode == 'month' { u64(121) } else if mode == 'nanosecond' { u64(1000000000) } else { u64(1) }, 0, 0)
						api.msg(calendar, c'dateFromComponents:', components, 0, 0)
					}
				}
				'mutable-copy', 'coding', 'locale', 'description' { api.msg(calendar, if mode == 'mutable-copy' { c'mutableCopy' } else if mode == 'coding' { c'encodeWithCoder:' } else if mode == 'locale' { c'locale' } else { c'description' }, 0, 0, 0) }
				'local-name', 'local-fixed-helper' { zone := api.msg(api.msg(cls, c'currentCalendar', 0, 0, 0), c'timeZone', 0, 0, 0); if mode == 'local-name' { api.msg(zone, c'name', 0, 0, 0) } else { ns_timezone_seconds(zone) } }
				'local-cutover' { os.setenv('TZ', 'UTC18:01', true); C.tzset(); assert ns_calendar_libc_fields(-12212488800, true)[0] == 1582; current := api.msg(cls, c'currentCalendar', 0, 0, 0); api.msg(current, c'components:fromDate:', 252, api.date(-12212488800.0), 0) }
				'destruct-active', 'constructor-isa', 'constructor-state' { assert objc_add_method(cls, u64(c'.cxx_construct'), u64(unsafe { voidptr(ns_calendar_constructor) }), c'@16@0:8'); ns_calendar_callback_set(if mode == 'destruct-active' { 'destruct' } else { mode }, cls, calendar); api.msg(calendar, c'copy', 0, 0, 0) }
				else { assert false }
			}
			api.pop(pool); C._exit(0)
		}
		C.close(fds[1]); mut bytes := [16384]u8{}; mut length := 0
		for { assert length < bytes.len; count := C.read(fds[0], unsafe { &bytes[length] }, usize(bytes.len - length)); if count == 0 { break }; if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }; assert count > 0; length += int(count) }
		C.close(fds[0]); mut status := i32(0); assert C.ios_waitpid(pid, &status, 0) == pid
		output := unsafe { tos(&bytes[0], length) }
		assert status == 256 && output.contains('iOS:') && !output.contains('AddressSanitizer') && !output.contains('runtime error:'), mode + ': ' + output
	}
	objc_stop(); assert ios_runtime.live == 0; system_data_stop()
	println('IOS-NS-CALENDAR-REJECT:' + modes.len.str() + ' unsupported masks/options and limits, malformed property/date/component inputs, storage provenance, local-zone metadata/cutover, active destruction and constructor mutation fail explicitly PASS')
}

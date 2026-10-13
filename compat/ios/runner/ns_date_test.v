// SPDX-License-Identifier: GPL-2.0-or-later
module main

import math

$if macos {
	#flag -framework Foundation
	#flag -framework CoreFoundation
	#include <objc/runtime.h>
	#include <CoreFoundation/CFDate.h>
}
#include <dlfcn.h>
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.CFDateCreate(voidptr, f64) voidptr
fn C.CFDateGetAbsoluteTime(voidptr) f64
fn C.CFDateGetTypeID() u64
fn C.CFGetTypeID(voidptr) u64
fn C.CFHash(voidptr) u64
fn C.CFEqual(voidptr, voidptr) bool
fn C.CFAbsoluteTimeGetCurrent() f64
type DateSend = fn (u64, u64, u64) u64
type DateSendReal = fn (u64, u64, f64, u64) u64
type DateGetReal = fn (u64, u64, u64) f64
struct DateApi { native bool send u64 cls u64 }
fn (api DateApi) selector(name &char) u64 {
	$if macos { if api.native { return u64(C.sel_registerName(name)) } }
	return u64(name)
}
fn (api DateApi) message(object u64, name &char, argument u64) u64 { return unsafe { DateSend(voidptr(api.send))(object, api.selector(name), argument) } }
fn (api DateApi) real(object u64, name &char, value f64, argument u64) u64 { return unsafe { DateSendReal(voidptr(api.send))(object, api.selector(name), value, argument) } }
fn (api DateApi) get(object u64, name &char, argument u64) f64 { return unsafe { DateGetReal(voidptr(api.send))(object, api.selector(name), argument) } }
fn (api DateApi) cf_create(value f64) u64 {
	$if macos { if api.native { return u64(C.CFDateCreate(unsafe { nil }, value)) } }
	return cf_date_create(0, value)
}
fn (api DateApi) cf_value(object u64) f64 {
	$if macos { if api.native { return C.CFDateGetAbsoluteTime(unsafe { voidptr(object) }) } }
	return cf_date_absolute(object)
}
fn (api DateApi) cf_type(object u64) u64 {
	$if macos { if api.native { return C.CFGetTypeID(unsafe { voidptr(object) }) } }
	return cf_type_id(object)
}
fn (api DateApi) date_type() u64 {
	$if macos { if api.native { return C.CFDateGetTypeID() } }
	return cf_date_id()
}
fn (api DateApi) hash(object u64) u64 {
	$if macos { if api.native { return C.CFHash(unsafe { voidptr(object) }) } }
	return cf_hash(object)
}
fn (api DateApi) equal(left u64, right u64) bool {
	$if macos { if api.native { return C.CFEqual(unsafe { voidptr(left) }, unsafe { voidptr(right) }) } }
	return object_equal(left, right)
}
fn (api DateApi) current() f64 {
	$if macos { if api.native { return C.CFAbsoluteTimeGetCurrent() } }
	return cf_absolute_time()
}
fn (api DateApi) pool() u64 {
	$if macos { if api.native { return api.message(u64(C.objc_getClass(c'NSAutoreleasePool')), c'new', 0) } }
	return objc_pool_push()
}
fn (api DateApi) drain(pool u64) {
	$if macos { if api.native { api.message(pool, c'drain', 0); return } }
	objc_pool_pop(pool)
}
fn (api DateApi) release(object u64) { api.message(object, c'release', 0) }
fn date_cases(api DateApi) {
	pool := api.pool()
	for value in [f64(0), 0.25, -0.25, 978307200.125, -978307200.125, 1e100]! {
		date := api.real(api.cls, c'dateWithTimeIntervalSinceReferenceDate:', value, 0)
		bridged := api.cf_create(value)
		actual := api.get(date, c'timeIntervalSinceReferenceDate', 0); bridge_actual := api.cf_value(date)
		assert actual == value && bridge_actual == value, 'native=' + api.native.str() + ' expected=' + value.str() + ' objc=' + actual.str() + ' cf=' + bridge_actual.str();
		assert api.get(bridged, c'timeIntervalSinceReferenceDate', 0) == value;
		assert api.cf_type(date) == api.date_type() && api.cf_type(bridged) == api.date_type();
		assert api.message(date, c'isEqualToDate:', bridged) == 1 && api.equal(date, bridged);
		assert api.message(date, c'hash', 0) == api.hash(date) && api.hash(date) == api.hash(bridged);
		copied := api.message(date, c'copyWithZone:', 0)
		assert copied == date; api.release(copied)
		fresh := api.real(api.message(api.cls, c'allocWithZone:', 0), c'initWithTimeIntervalSinceReferenceDate:', value, 0)
		assert api.equal(fresh, date); api.release(fresh)
		api.release(bridged)
	}
	base := api.real(api.cls, c'dateWithTimeIntervalSince1970:', 978307300.25, 0)
	equal := api.real(api.cls, c'dateWithTimeIntervalSinceReferenceDate:', 100.25, 0)
	later := api.real(api.cls, c'dateWithTimeInterval:sinceDate:', 100.25, base)
	assert api.get(base, c'timeIntervalSinceReferenceDate', 0) == 100.25 && api.get(base, c'timeIntervalSince1970', 0) == 978307300.25;
	assert i64(api.message(base, c'compare:', later)) == -1 && i64(api.message(later, c'compare:', base)) == 1;
	assert api.message(base, c'compare:', equal) == 0 && api.get(later, c'timeIntervalSinceDate:', base) == 100.25;
	assert api.message(base, c'earlierDate:', later) == base && api.message(base, c'laterDate:', later) == later;
	assert api.message(base, c'earlierDate:', equal) == base && api.message(base, c'laterDate:', equal) == base;
	assert api.message(base, c'compare:', 0) == 0 && api.message(base, c'earlierDate:', 0) == base && api.message(base, c'laterDate:', 0) == base;
	assert api.message(base, c'isEqualToDate:', 0) == 0 && math.is_nan(api.get(base, c'timeIntervalSinceDate:', 0));
	added := api.real(base, c'dateByAddingTimeInterval:', 100.25, 0)
	assert api.equal(added, later);
	for selector in [c'initWithTimeIntervalSince1970:', c'initWithTimeInterval:sinceDate:', c'initWithDate:']! {
		allocated := api.message(api.cls, c'alloc', 0)
		initialized := if selector == c'initWithDate:' { api.message(allocated, selector, base) } else { api.real(allocated, selector, if selector == c'initWithTimeIntervalSince1970:' { f64(978307300.25) } else { f64(0) }, base) }
		assert api.equal(initialized, base); api.release(initialized)
	}
	assert api.equal(api.message(api.cls, c'dateWithDate:', base), base);
	for selector in [c'date', c'now', c'new']! {
		before := api.current(); date := api.message(api.cls, selector, 0); after := api.current()
		absolute := api.get(date, c'timeIntervalSinceReferenceDate', 0)
		assert absolute >= before - 0.01 && absolute <= after + 0.01;
		if selector == c'new' { api.release(date) }
	}
	for route in [false, true]! {
		before := api.current()
		date := if route { api.real(api.message(api.cls, c'alloc', 0), c'initWithTimeIntervalSinceNow:', 10.5, 0) } else { api.real(api.cls, c'dateWithTimeIntervalSinceNow:', 10.5, 0) }
		after := api.current(); value := api.get(date, c'timeIntervalSinceNow', 0)
		assert value <= 10.51 && value >= 10.49 - (after - before);
		if route { api.release(date) }
	}
	before := api.current(); current := api.get(api.cls, c'timeIntervalSinceReferenceDate', 0); after := api.current()
	assert current >= before - 0.01 && current <= after + 0.01;
	for index, value in [f64(0), 0.25, -0.25, -978307200.125, 604672496.75]! {
		date := api.real(api.cls, c'dateWithTimeIntervalSinceReferenceDate:', value, 0)
		description := api.message(date, c'description', 0)
		expected := ['2001-01-01 00:00:00 +0000', '2001-01-01 00:00:00 +0000', '2000-12-31 23:59:59 +0000', '1969-12-31 23:59:59 +0000', '2020-02-29 12:34:56 +0000']![index]
		assert ctext(api.message(description, c'UTF8String', 0)) == expected;
		if !api.native { owned := cf_copy_description(date); assert string_text(owned) == expected; objc_release(owned) }
	}
	assert api.get(api.message(api.cls, c'distantPast', 0), c'timeIntervalSinceReferenceDate', 0) == -63114076800.0;
	assert api.get(api.message(api.cls, c'distantFuture', 0), c'timeIntervalSinceReferenceDate', 0) == 63113904000.0;
	api.drain(pool)
}
fn test_date_native() {
	$if macos {
		date_cases(DateApi{native: true, send: u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend')), cls: u64(C.objc_getClass(c'NSDate'))})
		println('IOS-DATE-NATIVE: epoch and fractional intervals, constructors, nil/tie ordering, immutable copy, UTC description and CFDate bridge through typed FP/integer calls')
	}
}
fn date_worker(api DateApi, date u64, later u64, distant u64) {
	for _ in 0 .. 1000 {
		assert api.get(date, c'timeIntervalSinceReferenceDate', 0) == 100.25;
		assert api.cf_value(date) == 100.25 && i64(api.message(date, c'compare:', later)) == -1;
		assert api.message(api.cls, c'distantFuture', 0) == distant;
	}
}
__global date_late_destroyed = 0
fn date_late_dealloc(object u64, selector &char) { date_late_destroyed++; ns_date_distant(true) }
fn test_date_runtime() {
	for _ in 0 .. 2 {
		objc_start(); api := DateApi{send: u64(unsafe { voidptr(C.ios_objc_msgsend) }), cls: ios_runtime.names['NSDate']}
		for library in ['/System/Library/Frameworks/Foundation.framework/Foundation', '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation']! {
			assert runtime_symbol(library, '_OBJC_CLASS_$_NSDate')! == api.cls;
			assert runtime_symbol(library, '_OBJC_METACLASS_$_NSDate')! == read64(api.cls);
		}
		assert objc_class_size(api.cls) == 8 && objc_class_parent(api.cls) == ios_runtime.names['NSObject'];
		assert objc_class_parent(cf_date_id()) == api.cls;
		date_cases(api); assert ios_runtime.live == 2;
		zero := cf_date_create(0, 0.0); negative_zero := cf_date_create(0, -0.0)
		assert object_equal(zero, negative_zero) && cf_hash(zero) == cf_hash(negative_zero);
		objc_release(zero); objc_release(negative_zero)
		pool := api.pool(); date := api.real(api.cls, c'dateWithTimeIntervalSinceReferenceDate:', 100.25, 0); later := api.real(date, c'dateByAddingTimeInterval:', 1, 0)
		for name, types in {'dateWithTimeInterval:sinceDate:': '@32@0:8d16@24', 'timeIntervalSinceReferenceDate': 'd16@0:8', 'compare:': 'q24@0:8@16'} {
			method := if name.starts_with('dateWith') { objc_class_method(api.cls, u64(name.str)) } else { objc_instance_method(api.cls, u64(name.str)) }
			assert method != 0 && ctext(u64(objc_method_types(method))) == types;
		}
		for selector in [c'mutableCopy', c'mutableCopyWithZone:', c'initWithCoder:', c'encodeWithCoder:', c'initWithString:', c'descriptionWithLocale:']! { assert !objc_responds(date, selector); assert objc_instance_method(api.cls, u64(selector)) == 0; }
		mut workers := []thread{}
		for _ in 0 .. 8 { workers << spawn date_worker(api, date, later, ns_date_distant(true)) }
		workers.wait(); api.drain(pool)
		for _ in 0 .. 100 { object := objc_new(api.cls); objc_set_class(object, ios_runtime.names['NSObject']); objc_release(object) }
		mut storage := [u64(0x123456789abcdef0), 0, 0xfedcba9876543210]!
		caller := objc_construct_instance(api.cls, u64(unsafe { &storage[1] }))
		assert api.real(caller, c'initWithTimeIntervalSinceReferenceDate:', 0.25, 0) == caller && cf_date_absolute(caller) == 0.25 && cf_type_id(caller) == cf_date_id();
		certificate := objc_allocate(sec_certificate_type_id()); policy := sec_policy_basic(); mut trust := u64(0)
		assert sec_trust_create(certificate, policy, unsafe { &trust }) == 0;
		assert sec_trust_date(trust, caller) == 0 && obj_header(trust).fields[3] == caller;
		assert sec_trust_date(trust, 0) == 0;
		objc_release(trust); objc_release(policy); objc_release(certificate)
		assert objc_destruct_instance(caller) == caller && storage[0] == 0x123456789abcdef0 && storage[2] == 0xfedcba9876543210;
		assert ios_runtime.live == 2 + ios_runtime.framework_objects.len;
		probe := objc_allocate_class(ios_runtime.names['NSObject'], c'VinixDateLateProbe', 0)
		assert objc_add_method(probe, u64(c'dealloc'), u64(unsafe { voidptr(date_late_dealloc) }), c'v16@0:8'); objc_register_class(probe)
		date_late_destroyed = 0; objc_autorelease(objc_new(probe))
		objc_stop(); assert date_late_destroyed == 1 && ios_runtime.live == 0;
	}
	println('IOS-DATE: shared CFDate storage, guarded caller bytes, 8,000 concurrent queries and100 isa changes per cycle; late destructor cache recreation and two zero-live-object shutdowns')
}
fn test_date_rejections() {
	objc_start(); api := DateApi{send: u64(unsafe { voidptr(C.ios_objc_msgsend) }), cls: ios_runtime.names['NSDate']}
	for mode in ['nonfinite', 'reinit', 'uninitialized', 'wrong-date', 'description-range', 'overflow', 'mutable-copy', 'subclass']! {
		mut fds := [2]i32{}; assert C.pipe(unsafe { &fds[0] }) == 0;
		pid := C.fork(); assert pid >= 0;
		if pid == 0 {
			C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1])
			object := objc_new(api.cls)
			match mode {
				'nonfinite' { api.real(api.cls, c'dateWithTimeIntervalSinceReferenceDate:', math.nan(), 0) }
				'reinit' { api.real(object, c'initWithTimeIntervalSinceReferenceDate:', 0, 0) }
				'uninitialized' { api.get(api.message(api.cls, c'alloc', 0), c'timeIntervalSinceReferenceDate', 0) }
				'wrong-date' { api.message(object, c'compare:', objc_new(ios_runtime.names['NSObject'])) }
				'description-range' { api.message(cf_date_create(0, 1e100), c'description', 0) }
				'overflow' { api.real(cf_date_create(0, 1.7e308), c'dateByAddingTimeInterval:', 1.7e308, 0) }
				'mutable-copy' { api.message(object, c'mutableCopy', 0) }
				else { subclass := objc_allocate_class(api.cls, c'UnsupportedDateSubclass', 0); objc_register_class(subclass); objc_new(subclass) }
			}
			C._exit(0)
		}
		C.close(fds[1]); mut buffer := [16384]u8{}; mut length := 0
		for { assert length < buffer.len; count := C.read(fds[0], unsafe { &buffer[length] }, usize(buffer.len - length)); if count == 0 { break }; if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }; assert count > 0; length += int(count) }
		C.close(fds[0]); mut status := i32(0); assert C.ios_waitpid(pid, &status, 0) == pid && status == 256;
		output := unsafe { tos(&buffer[0], length) }
		reason := match mode { 'nonfinite' { 'NSDate construction requires a finite interval' } 'reinit' { 'immutable date reinitialization is not implemented' } 'uninitialized' { 'date is not initialized' } 'wrong-date' { 'date comparison requires NSDate' } 'description-range' { 'date description is outside UTC years 1 through 9999' } 'overflow' { 'date arithmetic requires a finite interval' } 'mutable-copy' { 'date parsing, coding, mutable copies and locale formatting are not implemented' } else { 'custom date subclass construction is not implemented' } }
		assert output.contains('iOS: ' + reason) && !output.contains('AddressSanitizer') && !output.contains('runtime error:'), output;
	}
	assert ios_runtime.live == 0; objc_stop()
	println('IOS-DATE-REJECT: eight nonfinite/reinit/uninitialized/type/format/overflow/copy/subclass cases fail explicitly')
}

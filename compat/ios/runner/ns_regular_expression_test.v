// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#flag -framework Foundation
	#include <objc/runtime.h>
}
#include <dlfcn.h>
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.class_getInstanceSize(voidptr) usize
fn C.class_getSuperclass(voidptr) voidptr
type RegexMessage = fn (u64, u64, u64, u64, u64) u64
struct RegexRange { location u64 length u64 }
type RegexQuery = fn (u64, u64, u64, u64, RegexRange) u64
type RegexRangeQuery = fn (u64, u64, u64, u64, RegexRange) RegexRange
type RegexRangeGetter = fn (u64, u64) RegexRange
type RegexCaptureGetter = fn (u64, u64, u64) RegexRange
struct RegexApi { native bool send u64 cls u64 strings u64 mutable_strings u64 }
fn (api RegexApi) selector(name &char) u64 {
	$if macos { if api.native { return u64(C.sel_registerName(name)) } }
	return objc_selector(name)
}
fn (api RegexApi) message(object u64, name &char, a u64, b u64, c u64) u64 {
	return unsafe { RegexMessage(voidptr(api.send))(object, api.selector(name), a, b, c) }
}
fn (api RegexApi) string(value string) u64 {
	allocated := api.message(api.strings, c'alloc', 0, 0, 0)
	return api.message(api.message(allocated, c'initWithBytes:length:encoding:', u64(value.str), u64(value.len), 4), c'autorelease', 0, 0, 0)
}
fn (api RegexApi) text(object u64) string { assert object != 0; return ctext(api.message(object, c'UTF8String', 0, 0, 0)) }
fn (api RegexApi) retain(object u64) u64 { return api.message(object, c'retain', 0, 0, 0) }
fn (api RegexApi) release(object u64) { api.message(object, c'release', 0, 0, 0) }
fn (api RegexApi) pool() u64 {
	$if macos { if api.native { return api.message(u64(C.objc_getClass(c'NSAutoreleasePool')), c'new', 0, 0, 0) } }
	return objc_pool_push()
}
fn (api RegexApi) drain(pool u64) {
	$if macos { if api.native { api.message(pool, c'drain', 0, 0, 0); return } }
	objc_pool_pop(pool)
}
fn (api RegexApi) compile(pattern string, options u64) u64 {
	mut error_slot := u64(0x1122334455667788)
	object := api.message(api.message(api.cls, c'alloc', 0, 0, 0), c'initWithPattern:options:error:', api.string(pattern), options, u64(unsafe { &error_slot }))
	assert object != 0 && error_slot == 0x1122334455667788, 'pattern=' + pattern
	return object
}
fn (api RegexApi) query(object u64, selector &char, text u64, options u64, range RegexRange) u64 {
	return unsafe { RegexQuery(voidptr(api.send))(object, api.selector(selector), text, options, range) }
}
fn (api RegexApi) first_range(object u64, text u64, options u64, range RegexRange) RegexRange {
	return unsafe { RegexRangeQuery(voidptr(api.send))(object, api.selector(c'rangeOfFirstMatchInString:options:range:'), text, options, range) }
}
fn (api RegexApi) range(result u64) RegexRange {
	return unsafe { RegexRangeGetter(voidptr(api.send))(result, api.selector(c'range')) }
}
fn (api RegexApi) capture(result u64, index u64) RegexRange {
	return unsafe { RegexCaptureGetter(voidptr(api.send))(result, api.selector(c'rangeAtIndex:'), index) }
}
fn regex_probe_string_copy(object u64, selector &char) u64 { return owned_string(string_text(object)) }
fn (api RegexApi) mutable_string(value string) u64 {
	$if macos { if api.native { return api.retain(api.message(api.mutable_strings, c'stringWithUTF8String:', u64(value.str), 0, 0)) } }
	object := owned_string(value); objc_set_class(object, api.mutable_strings); return object
}
fn (api RegexApi) change_string(object u64, value string) {
	$if macos { if api.native { api.message(object, c'setString:', api.string(value), 0, 0); return } }
	mut header := obj_header(object)
	C.free(header.text); header.text = unsafe { &char(C.malloc(usize(value.len + 1))) }; assert header.text != unsafe { nil }
	unsafe { C.memcpy(header.text, value.str, usize(value.len)); header.text[value.len] = 0 }; header.text_length = value.len
}
fn regex_runtime_api() RegexApi {
	mutable := objc_allocate_class(ios_runtime.names['NSString'], c'VinixRegexMutableString', 0)
	assert mutable != 0 && objc_add_method(mutable, u64(c'copy'), u64(unsafe { voidptr(regex_probe_string_copy) }), c'@16@0:8')
	objc_register_class(mutable)
	return RegexApi{send: u64(unsafe { voidptr(C.ios_objc_msgsend) }), cls: ios_runtime.names['NSRegularExpression'], strings: ios_runtime.names['NSString'], mutable_strings: mutable}
}

fn regex_construction_cases(api RegexApi) {
	pool := api.pool()
	for construction in [c'alloc', c'new']! {
		object := api.message(api.cls, construction, 0, 0, 0)
		assert object != 0 && api.message(object, c'class', 0, 0, 0) == api.cls
		assert api.message(object, c'pattern', 0, 0, 0) == 0 && api.message(object, c'options', 0, 0, 0) == 0 && api.message(object, c'numberOfCaptureGroups', 0, 0, 0) == 0
		assert api.message(object, c'init', 0, 0, 0) == object
		text := api.string('abc')
		assert api.query(object, c'numberOfMatchesInString:options:range:', text, 0, RegexRange{0, 3}) == 0
		assert api.first_range(object, text, 0, RegexRange{0, 3}) == RegexRange{0x7fffffffffffffff, 0}
		assert api.query(object, c'firstMatchInString:options:range:', text, 0, RegexRange{0, 3}) == 0
		assert api.message(api.query(object, c'matchesInString:options:range:', text, 0, RegexRange{0, 3}), c'count', 0, 0, 0) == 0
		api.release(object)
	}
	for factory in [false, true]! {
		pattern := api.mutable_string('(ab)+(c)?')
		mut guarded_error := [u64(0x1122334455667788), 0x1234, 0x8877665544332211]!
		allocated := if factory { api.cls } else { api.message(api.cls, c'alloc', 0, 0, 0) }
		selector := if factory { c'regularExpressionWithPattern:options:error:' } else { c'initWithPattern:options:error:' }
		object := api.message(allocated, selector, pattern, 1, u64(unsafe { &guarded_error[1] }))
		assert object != 0 && (factory || object == allocated) && guarded_error == [u64(0x1122334455667788), 0x1234, 0x8877665544332211]!
		stored := api.message(object, c'pattern', 0, 0, 0)
		assert stored != pattern && api.text(stored) == '(ab)+(c)?' && api.message(object, c'options', 0, 0, 0) == 1 && api.message(object, c'numberOfCaptureGroups', 0, 0, 0) == 2
		api.change_string(pattern, 'changed'); api.release(pattern)
		assert api.text(api.message(object, c'pattern', 0, 0, 0)) == '(ab)+(c)?'
		for copy_selector in [c'copy', c'copyWithZone:']! { assert api.message(object, copy_selector, 0, 0, 0) == object; api.release(object) }
		if !api.native { for zone in [false, true]! { assert objc_copy_value(object, zone) == object; api.release(object) } }
		if !factory { api.release(object) }
	}
	for pattern in ['(', '', r'\0', r'[\0]']! {
		mut guarded_error := [u64(0x1122334455667788), 0, 0x8877665544332211]!
		assert api.message(api.cls, c'regularExpressionWithPattern:options:error:', api.string(pattern), 0, u64(unsafe { &guarded_error[1] })) == 0
		assert guarded_error[0] == 0x1122334455667788 && guarded_error[2] == 0x8877665544332211 && guarded_error[1] != 0
		error_object := guarded_error[1]
		assert api.message(error_object, c'code', 0, 0, 0) == 2048 && api.text(api.message(error_object, c'domain', 0, 0, 0)) == 'NSCocoaErrorDomain'
		info := api.message(error_object, c'userInfo', 0, 0, 0)
		assert api.text(api.message(info, c'objectForKey:', api.string('NSInvalidValue'), 0, 0)) == pattern
		assert api.message(api.message(api.cls, c'alloc', 0, 0, 0), c'initWithPattern:options:error:', api.string(pattern), 0, 0) == 0
	}
	api.drain(pool)
}

struct RegexVector {
	pattern string
	text string
	options u64
	query_options u64
	input_range RegexRange
	count u64
	ranges []RegexRange
}
fn regex_check_result(api RegexApi, result u64, expression u64, ranges []RegexRange) {
	assert result != 0 && api.message(result, c'regularExpression', 0, 0, 0) == expression
	assert api.message(result, c'resultType', 0, 0, 0) == 1024 && api.message(result, c'numberOfRanges', 0, 0, 0) == u64(ranges.len)
	assert api.range(result) == ranges[0]
	for index, expected in ranges { assert api.capture(result, u64(index)) == expected, 'capture=' + index.str() }
}
fn regex_matching_cases(api RegexApi) {
	not_found := RegexRange{0x7fffffffffffffff, 0}
	vectors := [
		RegexVector{'(ab)+(c)?', 'zzABabc ab', 1, 0, RegexRange{0, 10}, 2, [RegexRange{2, 5}, RegexRange{4, 2}, RegexRange{6, 1}]},
		RegexVector{'(a)?b', 'b', 0, 0, RegexRange{0, 1}, 1, [RegexRange{0, 1}, not_found]},
		RegexVector{'()a()', 'a', 0, 0, RegexRange{0, 1}, 1, [RegexRange{0, 1}, RegexRange{0, 0}, RegexRange{1, 0}]},
		RegexVector{'(a)(b)(c)(d)(e)(f)(g)', 'abcdefg', 0, 0, RegexRange{0, 7}, 1, [RegexRange{0, 7}, RegexRange{0, 1}, RegexRange{1, 1}, RegexRange{2, 1}, RegexRange{3, 1}, RegexRange{4, 1}, RegexRange{5, 1}, RegexRange{6, 1}]},
		RegexVector{'(a|aa)', 'aa', 0, 0, RegexRange{0, 2}, 2, [RegexRange{0, 1}, RegexRange{0, 1}]},
		RegexVector{'(a?)*', 'a', 0, 0, RegexRange{0, 1}, 2, [RegexRange{0, 1}, RegexRange{1, 0}]},
		RegexVector{'(a|(b))+', 'ba', 0, 0, RegexRange{0, 2}, 1, [RegexRange{0, 2}, RegexRange{1, 1}, RegexRange{0, 1}]},
		RegexVector{'a+?', 'aaa', 0, 0, RegexRange{0, 3}, 3, [RegexRange{0, 1}]},
		RegexVector{'a{2,3}', 'aaaaa', 0, 0, RegexRange{0, 5}, 2, [RegexRange{0, 3}]},
		RegexVector{r'(a)(b)\2\1', 'zabba', 0, 0, RegexRange{0, 5}, 1, [RegexRange{1, 4}, RegexRange{1, 1}, RegexRange{2, 1}]},
		RegexVector{r'[\1]', '1', 0, 0, RegexRange{0, 1}, 1, [RegexRange{0, 1}]},
		RegexVector{r'[\7]', '7', 0, 0, RegexRange{0, 1}, 1, [RegexRange{0, 1}]},
		RegexVector{r'[\8]', '8', 0, 0, RegexRange{0, 1}, 1, [RegexRange{0, 1}]},
		RegexVector{r'[\9]', '9', 0, 0, RegexRange{0, 1}, 1, [RegexRange{0, 1}]},
		RegexVector{'a*', 'bb', 0, 0, RegexRange{0, 2}, 3, [RegexRange{0, 0}]},
		RegexVector{'a*', '', 0, 0, RegexRange{0, 0}, 1, [RegexRange{0, 0}]},
		RegexVector{'$', 'a\n', 0, 0, RegexRange{0, 2}, 2, [RegexRange{1, 0}]},
		RegexVector{'x', 'abc', 0, 0, RegexRange{0, 3}, 0, []RegexRange{}},
		RegexVector{'ab', 'zab', 0, 4, RegexRange{0, 3}, 0, []RegexRange{}},
		RegexVector{'ab', 'zabz', 0, 4, RegexRange{1, 2}, 1, [RegexRange{1, 2}]},
		RegexVector{'a', 'aaa', 0, 4, RegexRange{0, 3}, 3, [RegexRange{0, 1}]},
		RegexVector{'a*', 'aaa', 0, 4, RegexRange{0, 3}, 2, [RegexRange{0, 3}]},
		RegexVector{'a*', 'bbb', 0, 4, RegexRange{0, 3}, 1, [RegexRange{0, 0}]},
		RegexVector{'^ab$', 'zabz', 0, 0, RegexRange{1, 2}, 1, [RegexRange{1, 2}]},
		RegexVector{'a.b', 'a\nb', 8, 0, RegexRange{0, 3}, 1, [RegexRange{0, 3}]},
		RegexVector{'^b$', 'a\nb\nc', 16, 0, RegexRange{0, 5}, 1, [RegexRange{2, 1}]},
		RegexVector{'a b # comment\n c', 'abc', 2, 0, RegexRange{0, 3}, 1, [RegexRange{0, 3}]},
		RegexVector{'[a b]', 'a b', 2, 0, RegexRange{0, 3}, 2, [RegexRange{0, 1}]},
		RegexVector{'[]a]', ']a', 0, 0, RegexRange{0, 2}, 2, [RegexRange{0, 1}]},
		RegexVector{'.', '\r\n', 32, 0, RegexRange{0, 2}, 1, [RegexRange{0, 1}]},
		RegexVector{'a.+', 'za.+z', 4, 0, RegexRange{0, 5}, 1, [RegexRange{1, 3}]},
		RegexVector{'(é😀)(x)?', 'Qé😀R', 0, 0, RegexRange{0, 5}, 1, [RegexRange{1, 3}, RegexRange{1, 3}, not_found]},
		RegexVector{'.', '😀x', 0, 0, RegexRange{0, 3}, 2, [RegexRange{0, 2}]},
		RegexVector{'a*', '😀x', 0, 0, RegexRange{0, 3}, 3, [RegexRange{0, 0}]},
		RegexVector{'b', 'a\x00b', 0, 0, RegexRange{0, 3}, 1, [RegexRange{2, 1}]},
		RegexVector{'\x00', 'a\x00b', 4, 0, RegexRange{0, 3}, 1, [RegexRange{1, 1}]},
		RegexVector{'^[A-Z]{3}$', 'USD', 0, 0, RegexRange{0, 3}, 1, [RegexRange{0, 3}]},
		RegexVector{r'fb\d*?://authorize.*access_token=([^&]*)', 'fb123://authorize?access_token=token42&next=1', 0, 0, RegexRange{0, 45}, 1, [RegexRange{0, 38}, RegexRange{31, 7}]},
		RegexVector{r'^[\d\w_]{1,45}$', 'Fortnite_123', 0, 0, RegexRange{0, 12}, 1, [RegexRange{0, 12}]},
		RegexVector{'/topics/([a-zA-Z0-9-_.~%]+)', '/topics/Fortnite-1_2.~%20', 0, 0, RegexRange{0, 25}, 1, [RegexRange{0, 25}, RegexRange{8, 17}]},
	]
	for vector in vectors {
		pool := api.pool(); expression := api.compile(vector.pattern, vector.options); text := api.string(vector.text)
		assert api.query(expression, c'numberOfMatchesInString:options:range:', text, vector.query_options, vector.input_range) == vector.count, vector.pattern
		expected := if vector.count == 0 { not_found } else { vector.ranges[0] }
		assert api.first_range(expression, text, vector.query_options, vector.input_range) == expected, vector.pattern
		first := api.query(expression, c'firstMatchInString:options:range:', text, vector.query_options, vector.input_range)
		matches := api.query(expression, c'matchesInString:options:range:', text, vector.query_options, vector.input_range)
		assert api.message(matches, c'count', 0, 0, 0) == vector.count
		if vector.count == 0 { assert first == 0 } else {
			regex_check_result(api, first, expression, vector.ranges)
			regex_check_result(api, api.message(matches, c'objectAtIndex:', 0, 0, 0), expression, vector.ranges)
			mut previous_end := u64(0)
			for index in 0 .. int(vector.count) {
				result := api.message(matches, c'objectAtIndex:', u64(index), 0, 0); range := api.range(result)
				assert range.location >= previous_end && range.location + range.length <= vector.input_range.location + vector.input_range.length
				previous_end = range.location + range.length
			}
		}
		api.release(expression); api.drain(pool)
	}
	unsafe { for vector in vectors { vector.ranges.free() }; vectors.free() }
}

fn regex_escape_cases(api RegexApi) {
	pool := api.pool()
	inputs := ['', 'abc', r'a.b+c?d*e^f$g|h(i)[j]{k}\l', '- / # = ! < > : , & ~ \t\n', '😀é']!
	patterns := ['', 'abc', r'a\.b\+c\?d\*e\^f\$g\|h\(i\)\[j]\{k\}\\l', '- \\/ # = ! < > : , & ~ \t\n', '😀é']!
	templates := ['', 'abc', r'a.b+c?d*e^f\$g|h(i)[j]{k}\\l', '- / # = ! < > : , & ~ \t\n', '😀é']!
	for index, input in inputs {
		assert api.text(api.message(api.cls, c'escapedPatternForString:', api.string(input), 0, 0)) == patterns[index]
		assert api.text(api.message(api.cls, c'escapedTemplateForString:', api.string(input), 0, 0)) == templates[index]
	}
	api.drain(pool)
}

fn regex_result_lifetime_case(api RegexApi) {
	pool := api.pool(); expression := api.compile('(ab)(c)?', 0)
	first := api.retain(api.query(expression, c'firstMatchInString:options:range:', api.string('zabz'), 0, RegexRange{0, 4}))
	for selector in [c'copy', c'copyWithZone:']! { assert api.message(first, selector, 0, 0, 0) == first; api.release(first) }
	if !api.native { for zone in [false, true]! { assert objc_copy_value(first, zone) == first; api.release(first) } }
	api.release(expression); api.drain(pool)
	assert api.text(api.message(api.message(first, c'regularExpression', 0, 0, 0), c'pattern', 0, 0, 0)) == '(ab)(c)?'
	assert api.range(first) == RegexRange{1, 2} && api.capture(first, 2) == RegexRange{0x7fffffffffffffff, 0}
	api.release(first)
	array_pool := api.pool(); array_expression := api.compile('(ab)', 0)
	matches := api.retain(api.query(array_expression, c'matchesInString:options:range:', api.string('ab ab'), 0, RegexRange{0, 5}))
	api.release(array_expression); api.drain(array_pool)
	assert api.message(matches, c'count', 0, 0, 0) == 2
	for index in 0 .. 2 {
		result := api.message(matches, c'objectAtIndex:', u64(index), 0, 0)
		assert api.range(result) == RegexRange{u64(index * 3), 2}
		assert api.text(api.message(api.message(result, c'regularExpression', 0, 0, 0), c'pattern', 0, 0, 0)) == '(ab)'
	}
	api.release(matches)
}

fn regex_reader(api RegexApi, expression u64, text u64) {
	pool := api.pool()
	for _ in 0 .. 64 {
		assert api.message(expression, c'numberOfCaptureGroups', 0, 0, 0) == 2
		assert api.query(expression, c'numberOfMatchesInString:options:range:', text, 0, RegexRange{0, 10}) == 2
		assert api.first_range(expression, text, 0, RegexRange{0, 10}) == RegexRange{2, 5}
		result := api.query(expression, c'firstMatchInString:options:range:', text, 0, RegexRange{0, 10})
		assert api.capture(result, 1) == RegexRange{4, 2}
	}
	api.drain(pool)
}

__global regex_copy_api = RegexApi{}
__global regex_copy_receiver = u64(0)
__global regex_copy_drops_receiver = bool(false)
__global regex_copy_pattern_weak = u64(0)
fn regex_initialization_reader(api RegexApi, expression u64) {
	assert api.message(expression, c'pattern', 0, 0, 0) == 0
	assert api.message(expression, c'options', 0, 0, 0) == 0
	assert api.message(expression, c'numberOfCaptureGroups', 0, 0, 0) == 0
}
fn regex_reentrant_string_copy(object u64, selector &char) u64 {
	worker := spawn regex_initialization_reader(regex_copy_api, regex_copy_receiver); worker.wait()
	copy := owned_string(string_text(object)); objc_store_weak(unsafe { &regex_copy_pattern_weak }, copy)
	if regex_copy_drops_receiver { receiver := regex_copy_receiver; regex_copy_receiver = 0; objc_release(receiver) }
	return copy
}
fn regex_constructor_lifetime_cases(api RegexApi) {
	cls := objc_allocate_class(ios_runtime.names['NSString'], c'VinixRegexReentrantString', 0)
	assert objc_add_method(cls, u64(c'copy'), u64(unsafe { voidptr(regex_reentrant_string_copy) }), c'@16@0:8'); objc_register_class(cls)
	regex_copy_api = api
	for drops_receiver in [false, true]! {
		pool := api.pool(); source := owned_string('(copy callback)'); objc_set_class(source, cls)
		allocated := api.message(api.cls, c'alloc', 0, 0, 0)
		if drops_receiver { api.retain(allocated) }
		mut receiver_weak := u64(0); objc_store_weak(unsafe { &receiver_weak }, allocated)
		regex_copy_receiver = allocated; regex_copy_drops_receiver = drops_receiver
		assert api.message(allocated, c'initWithPattern:options:error:', source, 0, 0) == allocated
		api.release(source)
		assert receiver_weak != 0 && regex_copy_pattern_weak != 0
		assert api.text(api.message(allocated, c'pattern', 0, 0, 0)) == '(copy callback)'; api.release(allocated)
		assert receiver_weak == 0 && regex_copy_pattern_weak == 0
		objc_destroy_weak(unsafe { &receiver_weak }); objc_destroy_weak(unsafe { &regex_copy_pattern_weak }); api.drain(pool)
	}
	regex_copy_receiver = 0; regex_copy_api = RegexApi{}
}

fn test_regular_expression_native() {
	$if macos {
		api := RegexApi{native: true, send: u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend')), cls: u64(C.objc_getClass(c'NSRegularExpression')), strings: u64(C.objc_getClass(c'NSString')), mutable_strings: u64(C.objc_getClass(c'NSMutableString'))}
		assert C.class_getInstanceSize(unsafe { voidptr(api.cls) }) == 40 && C.class_getSuperclass(unsafe { voidptr(api.cls) }) == C.objc_getClass(c'NSObject')
		regex_construction_cases(api); regex_matching_cases(api); regex_escape_cases(api); regex_result_lifetime_case(api)
		println('IOS-REGULAR-EXPRESSION-NATIVE: typed constructors and NSRange ABI, copied mutable patterns, guarded error outputs, invalid-pattern Cocoa errors, retained copies and match lifetimes, capture and nonoverlap order, empty matches, UTF16 supplementary text and embedded NUL, exact escaping and Fortnite patterns')
	}
}

fn test_regular_expression_runtime() {
	for _ in 0 .. 2 {
		objc_start(); api := regex_runtime_api()
		library := '/System/Library/Frameworks/Foundation.framework/Foundation'
		assert runtime_symbol(library, '_OBJC_CLASS_$_NSRegularExpression')! == api.cls && runtime_symbol(library, '_OBJC_METACLASS_$_NSRegularExpression')! == read64(api.cls)
		assert objc_class_size(api.cls) == 40 && objc_class_parent(api.cls) == ios_runtime.names['NSObject']
		for name, types in {'init': '@16@0:8', 'initWithPattern:options:error:': '@40@0:8@16Q24^@32', 'pattern': '@16@0:8', 'options': 'Q16@0:8', 'numberOfCaptureGroups': 'Q16@0:8', 'numberOfMatchesInString:options:range:': 'Q48@0:8@16Q24{_NSRange=QQ}32', 'rangeOfFirstMatchInString:options:range:': '{_NSRange=QQ}48@0:8@16Q24{_NSRange=QQ}32', 'firstMatchInString:options:range:': '@48@0:8@16Q24{_NSRange=QQ}32', 'matchesInString:options:range:': '@48@0:8@16Q24{_NSRange=QQ}32', 'copyWithZone:': '@24@0:8^{_NSZone=}16'} {
			method := objc_instance_method(api.cls, u64(name.str)); assert method != 0 && ctext(u64(objc_method_types(method))) == types
		}
		for name, types in {'regularExpressionWithPattern:options:error:': '@40@0:8@16Q24^@32', 'escapedPatternForString:': '@24@0:8@16', 'escapedTemplateForString:': '@24@0:8@16'} {
			method := objc_class_method(api.cls, u64(name.str)); assert method != 0 && ctext(u64(objc_method_types(method))) == types
		}
		for index, name in ['_pattern', '_options', '_internal', '_checkout']! {
			ivar := objc_find_ivar(api.cls, unsafe { &char(name.str) }); assert ivar != 0 && objc_ivar_offset(ivar) == i64(8 + index * 8)
			assert ctext(u64(objc_ivar_types(ivar))) == ['@"NSString"', 'Q', '^v', 'i']![index]
		}
		result_class := ios_runtime.names['NSTextCheckingResult']
		assert runtime_symbol(library, '_OBJC_CLASS_$_NSTextCheckingResult')! == result_class && objc_class_parent(result_class) == ios_runtime.names['NSObject']
		for name, types in {'range': '{_NSRange=QQ}16@0:8', 'rangeAtIndex:': '{_NSRange=QQ}24@0:8Q16', 'numberOfRanges': 'Q16@0:8', 'resultType': 'Q16@0:8', 'regularExpression': '@16@0:8', 'copyWithZone:': '@24@0:8^{_NSZone=}16'} {
			method := objc_instance_method(result_class, u64(name.str)); assert method != 0 && ctext(u64(objc_method_types(method))) == types
		}
		regex_construction_cases(api); regex_matching_cases(api); regex_escape_cases(api); regex_result_lifetime_case(api)
		regex_constructor_lifetime_cases(api)
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
		pool := api.pool(); expression := api.compile('(ab)+(c)?', 1); text := api.string('zzABabc ab')
		mut readers := []thread{}
		for _ in 0 .. 8 { readers << spawn regex_reader(api, expression, text) }
		readers.wait(); unsafe { readers.free() }; api.release(expression); api.drain(pool)
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
		mut guarded := [7]u64{}; guarded[0] = 0x1122334455667788; guarded[6] = 0x8877665544332211
		caller := objc_construct_instance(api.cls, u64(unsafe { &guarded[1] })); inner := api.pool()
		source := api.mutable_string('(caller)'); assert api.message(caller, c'initWithPattern:options:error:', source, 0, 0) == caller; api.release(source)
		mut pattern_weak := u64(0); objc_store_weak(unsafe { &pattern_weak }, api.message(caller, c'pattern', 0, 0, 0)); api.drain(inner)
		assert pattern_weak != 0 && objc_destruct_instance(caller) == caller && pattern_weak == 0
		for index in 1 .. 5 { assert read64(caller + u64(index * 8)) == 0 }
		objc_destroy_weak(unsafe { &pattern_weak }); assert guarded[0] == 0x1122334455667788 && guarded[6] == 0x8877665544332211
		for _ in 0 .. 64 {
			isa_pool := api.pool(); changed := api.compile('(isa)', 0)
			assert objc_set_class(changed, ios_runtime.names['NSObject']) == api.cls; api.release(changed); api.drain(isa_pool)
		}
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
		pooled := objc_autorelease(api.compile('(shutdown)', 0)); mut pooled_weak := u64(0); mut final_pattern_weak := u64(0)
		objc_store_weak(unsafe { &pooled_weak }, pooled); objc_store_weak(unsafe { &final_pattern_weak }, api.message(pooled, c'pattern', 0, 0, 0)); objc_stop()
		assert pooled_weak == 0 && final_pattern_weak == 0 && ios_runtime.live == 0 && ios_runtime.objects.len == 0
	}
	println('IOS-REGULAR-EXPRESSION: typed capture and NSRange ABI, mutable pattern snapshots, retained result ownership, Unicode scalar boundaries, exact escaping, Fortnite patterns, eight concurrent readers, guarded caller storage, 64 isa replacements and two drained runtimes')
}

fn regex_probe_bad_copy(object u64, selector &char) u64 { return objc_new(ios_runtime.names['NSObject']) }
fn regex_probe_nil_copy(object u64, selector &char) u64 { return 0 }
fn test_regular_expression_rejections() {
	objc_start(); api := regex_runtime_api()
	for mode in ['mutable', 'coding', 'description', 'equality', 'enumeration', 'replacement', 'compile-options', 'match-options', 'nil-pattern', 'bad-pattern', 'bad-copy', 'nil-copy', 'copy-ownership', 'invalid-copy-ownership', 'reinitialize', 'lookaround', 'unicode-case', 'unicode-shorthand', 'range', 'surrogate-range', 'result-index', 'named-result', 'subclass', 'caller-subclass', 'spoof', 'abstract-result', 'long-pattern', 'long-subject']! {
		mut fds := [2]i32{}; assert C.pipe(unsafe { &fds[0] }) == 0
		pid := C.fork(); assert pid >= 0
		if pid == 0 {
			C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1])
			match mode {
				'mutable', 'coding', 'description', 'equality', 'enumeration', 'replacement' {
					object := api.compile('a', 0)
					selector := match mode { 'mutable' { c'mutableCopy' } 'coding' { c'initWithCoder:' } 'description' { c'description' } 'equality' { c'isEqual:' } 'enumeration' { c'enumerateMatchesInString:options:range:usingBlock:' } else { c'stringByReplacingMatchesInString:options:range:withTemplate:' } }
					api.message(object, selector, 0, 0, 0)
				}
				'compile-options' { api.compile('a', 64) }
				'match-options' { api.query(api.compile('a', 0), c'numberOfMatchesInString:options:range:', api.string('a'), 1, RegexRange{0, 1}) }
				'nil-pattern', 'bad-pattern' {
					pattern := if mode == 'nil-pattern' { u64(0) } else { objc_new(ios_runtime.names['NSObject']) }
					api.message(api.message(api.cls, c'alloc', 0, 0, 0), c'initWithPattern:options:error:', pattern, 0, 0)
				}
				'bad-copy', 'nil-copy' {
					cls := objc_allocate_class(ios_runtime.names['NSString'], c'VinixRegexBadCopyString', 0)
					imp := if mode == 'bad-copy' { u64(unsafe { voidptr(regex_probe_bad_copy) }) } else { u64(unsafe { voidptr(regex_probe_nil_copy) }) }
					assert objc_add_method(cls, u64(c'copy'), imp, c'@16@0:8'); objc_register_class(cls)
					pattern := owned_string('a'); objc_set_class(pattern, cls)
					api.message(api.message(api.cls, c'alloc', 0, 0, 0), c'initWithPattern:options:error:', pattern, 0, 0)
				}
				'copy-ownership', 'invalid-copy-ownership' {
					cls := objc_allocate_class(ios_runtime.names['NSString'], c'VinixRegexConsumedCopyString', 0)
					assert objc_add_method(cls, u64(c'copy'), u64(unsafe { voidptr(regex_reentrant_string_copy) }), c'@16@0:8'); objc_register_class(cls)
					pattern := owned_string(if mode == 'invalid-copy-ownership' { '(' } else { 'a' }); objc_set_class(pattern, cls)
					allocated := api.message(api.cls, c'alloc', 0, 0, 0)
					regex_copy_api = api; regex_copy_receiver = allocated; regex_copy_drops_receiver = true
					api.message(allocated, c'initWithPattern:options:error:', pattern, 0, 0)
				}
				'reinitialize' { object := api.compile('a', 0); api.message(object, c'initWithPattern:options:error:', api.string('b'), 0, 0) }
				'lookaround' { api.compile('(?=a)', 0) }
				'unicode-case' { api.query(api.compile('a', 1), c'numberOfMatchesInString:options:range:', api.string('éa'), 0, RegexRange{0, 2}) }
				'unicode-shorthand' { api.query(api.compile(r'\w+', 0), c'numberOfMatchesInString:options:range:', api.string('éa'), 0, RegexRange{0, 2}) }
				'range' { api.query(api.compile('a', 0), c'numberOfMatchesInString:options:range:', api.string('a'), 0, RegexRange{1, 1}) }
				'surrogate-range' { api.query(api.compile('.', 0), c'numberOfMatchesInString:options:range:', api.string('😀x'), 0, RegexRange{1, 1}) }
				'result-index', 'named-result' {
					result := api.query(api.compile('(a)', 0), c'firstMatchInString:options:range:', api.string('a'), 0, RegexRange{0, 1})
					if mode == 'result-index' { api.capture(result, 2) } else { api.message(result, c'rangeWithName:', api.string('a'), 0, 0) }
				}
				'subclass', 'caller-subclass' {
					subclass := objc_allocate_class(api.cls, c'VinixUnsupportedRegexSubclass', 0); objc_register_class(subclass)
					if mode == 'subclass' { objc_allocate(subclass) } else { mut storage := [5]u64{}; objc_construct_instance(subclass, u64(unsafe { &storage[0] })) }
				}
				'spoof' {
					cls := objc_allocate_class(ios_runtime.names['NSObject'], c'VinixRegexSpoof', 0)
					assert objc_add_ivar(cls, c'bytes', 32, 3, c'[32C]'); objc_register_class(cls)
					object := objc_new(cls); objc_set_class(object, api.cls); api.message(object, c'pattern', 0, 0, 0)
				}
				'abstract-result' { objc_allocate(ios_runtime.names['NSTextCheckingResult']) }
				'long-pattern' { api.compile('a'.repeat(4097), 0) }
				else { api.query(api.compile('a', 0), c'numberOfMatchesInString:options:range:', api.string('a'.repeat(65537)), 0, RegexRange{0, 1}) }
			}
			C._exit(0)
		}
		C.close(fds[1]); mut bytes := [16384]u8{}; mut length := 0
		for { assert length < bytes.len; count := C.read(fds[0], unsafe { &bytes[length] }, usize(bytes.len - length)); if count == 0 { break }; if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }; assert count > 0; length += int(count) }
		C.close(fds[0]); mut status := i32(0); assert C.ios_waitpid(pid, &status, 0) == pid && status == 256
		output := unsafe { tos(&bytes[0], length) }
		reason := match mode {
			'mutable', 'coding', 'description', 'equality', 'enumeration', 'replacement' { 'regular expression operation is not implemented' }
			'compile-options' { 'regular expression compilation options are not implemented' }
			'match-options' { 'regular expression matching options are not implemented' }
			'nil-pattern', 'bad-pattern', 'bad-copy', 'nil-copy' { 'regular expression requires a live valid UTF-8 NSString' }
			'copy-ownership', 'invalid-copy-ownership' { 'regular expression pattern copy consumed initializer ownership' }
			'reinitialize' { 'regular expression designated reinitialization is not implemented' }
			'lookaround' { 'regular expression unsupported: regular expression group extension' }
			'unicode-case', 'unicode-shorthand' { 'regular expression unsupported: Unicode subject with ASCII case or character classes' }
			'range', 'surrogate-range' { 'regular expression range is out of bounds or bisects a UTF-16 surrogate pair' }
			'result-index' { 'regular expression result range index is out of bounds' }
			'named-result' { 'regular expression result operation is not implemented' }
			'subclass', 'caller-subclass' { 'regular expression subclass construction is not implemented' }
			'spoof' { 'regular expression requires live owned storage' }
			'abstract-result' { 'regular expression results require the matching APIs' }
			else { 'regular expression string exceeds the supported limit' }
		}
		assert output.contains('iOS: ' + reason) && !output.contains('AddressSanitizer') && !output.contains('runtime error:'), mode + ': ' + output
	}
	assert ios_runtime.live == 0 && ios_runtime.objects.len == 0; objc_stop()
	println('IOS-REGULAR-EXPRESSION-REJECT: 28 mutability/coding/equality/enumeration/replacement/options/type/copy/ownership/reinitialization/syntax/Unicode/range/result/subclass/spoof/limit cases fail explicitly')
}

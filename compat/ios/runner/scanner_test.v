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
fn C.class_getInstanceMethod(voidptr, voidptr) voidptr
fn C.class_getClassMethod(voidptr, voidptr) voidptr
fn C.method_getTypeEncoding(voidptr) &char
fn C.class_getInstanceSize(voidptr) usize
fn C.class_getSuperclass(voidptr) voidptr
fn C.class_copyIvarList(voidptr, &u32) voidptr
fn C.objc_storeWeak(&u64, voidptr) voidptr

type ScannerFixtureSend = fn (u64, u64, u64, u64) u64
type ScannerFixtureBytes = fn (u64, u64, u64, u64, u64) u64

struct ScannerFixtureApi {
	native bool
	send   u64
}

fn (api ScannerFixtureApi) cls(name string) u64 {
	$if macos {
		if api.native { return u64(C.objc_getClass(name.str)) }
	}
	return ios_runtime.names[name]
}

fn (api ScannerFixtureApi) selector(name &char) u64 {
	$if macos {
		if api.native { return u64(C.sel_registerName(name)) }
	}
	return u64(name)
}

fn (api ScannerFixtureApi) message(object u64, name &char, a u64, b u64) u64 {
	return unsafe { ScannerFixtureSend(voidptr(api.send))(object, api.selector(name), a, b) }
}

fn (api ScannerFixtureApi) string(value string) u64 {
	allocated := api.message(api.cls('NSString'), c'alloc', 0, 0)
	initialized := unsafe { ScannerFixtureBytes(voidptr(api.send))(allocated, api.selector(c'initWithBytes:length:encoding:'), u64(value.str), u64(value.len), 4) }
	return api.message(initialized, c'autorelease', 0, 0)
}

fn (api ScannerFixtureApi) text(object u64) string {
	assert object != 0
	return ctext(api.message(object, c'UTF8String', 0, 0))
}

fn (api ScannerFixtureApi) expect_bytes(object u64, expected string) {
	assert object != 0
	assert unsafe { tos(&u8(api.message(object, c'UTF8String', 0, 0)), expected.len) } == expected
}

fn (api ScannerFixtureApi) scanner(value string) u64 {
	return api.message(api.cls('NSScanner'), c'scannerWithString:', api.string(value), 0)
}

fn (api ScannerFixtureApi) retain(object u64) u64 { return api.message(object, c'retain', 0, 0) }

fn (api ScannerFixtureApi) release(object u64) { api.message(object, c'release', 0, 0) }

fn (api ScannerFixtureApi) pool() u64 {
	$if macos {
		if api.native { return api.message(api.cls('NSAutoreleasePool'), c'new', 0, 0) }
	}
	return objc_pool_push()
}

fn (api ScannerFixtureApi) drain(pool u64) {
	$if macos {
		if api.native {
			api.message(pool, c'drain', 0, 0)
			return
		}
	}
	objc_pool_pop(pool)
}

fn (api ScannerFixtureApi) weak(slot &u64, object u64) {
	$if macos {
		if api.native {
			C.objc_storeWeak(slot, unsafe { voidptr(object) })
			return
		}
	}
	objc_store_weak(slot, object)
}

fn (api ScannerFixtureApi) destroy_weak(slot &u64) {
	$if macos {
		if api.native {
			C.objc_storeWeak(slot, unsafe { nil })
			return
		}
	}
	objc_destroy_weak(slot)
}

fn scanner_fixture_metadata(api ScannerFixtureApi) {
	cls := api.cls('NSScanner')
	assert cls != 0
	mut count := u32(99)
	$if macos {
		if api.native {
			assert C.class_getInstanceSize(voidptr(cls)) == 8 && u64(C.class_getSuperclass(voidptr(cls))) == api.cls('NSObject')
			ivars := C.class_copyIvarList(voidptr(cls), &count)
			assert count == 0
			unsafe { C.free(ivars) }
		}
	}
	if !api.native {
		assert objc_class_size(cls) == 8 && objc_class_parent(cls) == api.cls('NSObject')
		ivars := objc_copy_ivars(cls, &count)
		assert count == 0
		unsafe { C.free(ivars) }
	}
	for name, types in {
		'scannerWithString:':                    '@24@0:8@16'
		'initWithString:':                       '@24@0:8@16'
		'init':                                  '@16@0:8'
		'string':                                '@16@0:8'
		'scanLocation':                          'Q16@0:8'
		'setScanLocation:':                      'v24@0:8Q16'
		'isAtEnd':                               'B16@0:8'
		'caseSensitive':                         'B16@0:8'
		'setCaseSensitive:':                     'v20@0:8B16'
		'charactersToBeSkipped':                 '@16@0:8'
		'setCharactersToBeSkipped:':             'v24@0:8@16'
		'locale':                                '@16@0:8'
		'setLocale:':                            'v24@0:8@16'
		'copyWithZone:':                         '@24@0:8^{_NSZone=}16'
		'scanInteger:':                          'B24@0:8^q16'
		'scanLongLong:':                         'B24@0:8^q16'
		'scanInt:':                              'B24@0:8^i16'
		'scanHexInt:':                           'B24@0:8^I16'
		'scanHexLongLong:':                      'B24@0:8^Q16'
		'scanString:intoString:':                'B32@0:8@16^@24'
		'scanUpToString:intoString:':            'B32@0:8@16^@24'
		'scanCharactersFromSet:intoString:':     'B32@0:8@16^@24'
		'scanUpToCharactersFromSet:intoString:': 'B32@0:8@16^@24'
	} {
		meta := name == 'scannerWithString:'
		mut actual := ''
		$if macos {
			if api.native {
				method := if meta {
					C.class_getClassMethod(voidptr(cls), voidptr(api.selector(name.str)))
				} else {
					C.class_getInstanceMethod(voidptr(cls), voidptr(api.selector(name.str)))
				}
				assert method != unsafe { nil }, name
				actual = unsafe { C.method_getTypeEncoding(method).vstring() }
			}
		}
		if !api.native {
			method := if meta {
				objc_class_method(cls, u64(name.str))
			} else {
				objc_instance_method(cls, u64(name.str))
			}
			assert method != 0, name
			actual = ctext(u64(objc_method_types(method)))
		}
		assert actual == types, name + ': ' + actual
	}
}

struct ScannerFixtureNumber {
	text     string
	ok       bool
	value    u64
	location u64
}

fn scanner_fixture_numbers(api ScannerFixtureApi) {
	for selector in [c'scanInteger:', c'scanHexLongLong:']! {
		cases := if selector == c'scanInteger:' {
			[ScannerFixtureNumber{'', false, 0, 0}, ScannerFixtureNumber{'  nope', false, 0, 0},
				ScannerFixtureNumber{'+', false, 0, 0},
				ScannerFixtureNumber{' -42x', true, u64(-42), 4},
				ScannerFixtureNumber{'- 12', true, u64(-12), 4},
				ScannerFixtureNumber{'+\t12', true, 12, 4},
				ScannerFixtureNumber{'+12 34', true, 12, 3},
				ScannerFixtureNumber{'9223372036854775808!', true, 0x7fffffffffffffff, 19},
				ScannerFixtureNumber{'-9223372036854775809!', true, 0x8000000000000000, 20}]
		} else {
			[ScannerFixtureNumber{'', false, 0, 0}, ScannerFixtureNumber{'  xyz', false, 0, 0},
				ScannerFixtureNumber{'-1', false, 0, 0}, ScannerFixtureNumber{'+1', false, 0, 0},
				ScannerFixtureNumber{'\t\n0xFf!', true, 255, 6},
				ScannerFixtureNumber{'0x', true, 0, 1}, ScannerFixtureNumber{'0xg', true, 0, 1},
				ScannerFixtureNumber{'ffffffffffffffff', true, 0xffffffffffffffff, 16},
				ScannerFixtureNumber{'10000000000000000!', true, 0xffffffffffffffff, 17}]
		}
		for test in cases {
			object := api.scanner(test.text)
			mut guarded := [u64(0x1122334455667788), 0xa5a5a5a5deadbeef, 0x8877665544332211]!
			ok := api.message(object, selector, u64(unsafe { &guarded[1] }), 0) != 0
			assert ok == test.ok && guarded[0] == 0x1122334455667788 && guarded[2] == 0x8877665544332211, test.text
			assert guarded[1] == if test.ok { test.value } else { u64(0xa5a5a5a5deadbeef) }, test.text
			assert api.message(object, c'scanLocation', 0, 0) == test.location, test.text
		}
		object := api.scanner(if selector == c'scanInteger:' { ' 12' } else { ' ff' })
		assert api.message(object, selector, 0, 0) != 0 && api.message(object, c'scanLocation', 0, 0) == 3
	}
	for selector in [c'scanInt:', c'scanHexInt:']! {
		object := api.scanner(if selector == c'scanInt:' { '-2147483649!' } else { '1ffffffff!' })
		mut guarded := [u32(0x11223344), 0xdeadbeef, 0x88776655]!
		assert api.message(object, selector, u64(unsafe { &guarded[1] }), 0) != 0
		assert guarded[0] == 0x11223344 && guarded[2] == 0x88776655 && guarded[1] == if selector == c'scanInt:' {
			u32(0x80000000)
		} else {
			u32(0xffffffff)
		}
		assert api.message(object, c'scanLocation', 0, 0) == if selector == c'scanInt:' {
			u64(11)
		} else {
			u64(9)
		}
		failed := api.scanner('nope')
		guarded[1] = 0xdeadbeef
		assert api.message(failed, selector, u64(unsafe { &guarded[1] }), 0) == 0 && guarded[1] == 0xdeadbeef && guarded[0] == 0x11223344 && guarded[2] == 0x88776655
	}
	mut signed := i64(0)
	assert api.message(api.scanner('- 42x'), c'scanLongLong:', u64(unsafe { &signed }), 0) != 0 && signed == -42
}

fn scanner_fixture_parsers(api ScannerFixtureApi) {
	// The exact selector sequence selected from FIRApp's format validator.
	object := api.scanner('1:123:ios:deadBEEF')
	api.message(object, c'setCharactersToBeSkipped:', 0, 0)
	assert api.message(object, c'scanString:intoString:', api.string('1'), 0) != 0
	assert api.message(object, c'scanString:intoString:', api.string(':'), 0) != 0
	mut number := i64(0)
	assert api.message(object, c'scanInteger:', u64(unsafe { &number }), 0) != 0 && number == 123
	assert api.message(object, c'scanString:intoString:', api.string(':'), 0) != 0
	mut output := u64(0)
	assert api.message(object, c'scanUpToString:intoString:', api.string(':'), u64(unsafe { &output })) != 0 && api.text(output) == 'ios'
	assert api.message(object, c'scanString:intoString:', api.string(':'), 0) != 0
	mut hash := u64(0)
	assert api.message(object, c'scanHexLongLong:', u64(unsafe { &hash }), 0) != 0 && hash == 0xdeadbeef
	assert api.message(object, c'isAtEnd', 0, 0) != 0
	// The leading decimal-set parse selected from FIRApp validateAppID:.
	leading := api.scanner('123:ios')
	api.message(leading, c'setCharactersToBeSkipped:', 0, 0)
	digits := api.message(api.cls('NSCharacterSet'), c'decimalDigitCharacterSet', 0, 0)
	assert api.message(leading, c'scanCharactersFromSet:intoString:', digits, u64(unsafe { &output })) != 0 && api.text(output) == '123'
	assert api.message(leading, c'scanString:intoString:', api.string(':'), 0) != 0
	// PLCrashHostInfo's three dot-separated NSInteger outputs.
	version := api.scanner('18.6.2')
	for index, expected in [i64(18), 6, 2]! {
		assert api.message(version, c'scanInteger:', u64(unsafe { &number }), 0) != 0 && number == expected
		if index < 2 {
			assert api.message(version, c'scanString:intoString:', api.string('.'), 0) != 0
		}
	}
	// The stripped plist extraction's two scans leave its closing delimiter.
	plist := api.scanner('prefix<plist>value</plist>suffix')
	assert api.message(plist, c'scanUpToString:intoString:', api.string('<plist'), 0) != 0
	assert api.message(plist, c'scanUpToString:intoString:', api.string('</plist>'), u64(unsafe { &output })) != 0 && api.text(output) == '<plist>value'
	assert api.message(plist, c'scanString:intoString:', api.string('</plist>'), 0) != 0
}

fn scanner_fixture_shared(api ScannerFixtureApi) {
	pool := api.pool()
	scanner_fixture_metadata(api)
	cls := api.cls('NSScanner')
	for selector in [c'new', c'init']! {
		empty := if selector == c'new' {
			api.message(cls, selector, 0, 0)
		} else {
			api.message(api.message(cls, c'alloc', 0, 0), selector, 0, 0)
		}
		assert api.message(empty, c'string', 0, 0) == 0 && api.message(empty, c'charactersToBeSkipped', 0, 0) == 0 && api.message(empty, c'scanLocation', 0, 0) == 0 && api.message(empty, c'isAtEnd', 0, 0) != 0
		empty_copy := api.message(empty, c'copy', 0, 0)
		assert empty_copy != empty && api.text(api.message(empty_copy, c'string', 0, 0)) == '' && api.message(empty_copy, c'charactersToBeSkipped', 0, 0) == 0
		api.release(empty_copy)
		api.release(empty)
	}
	for factory in [true, false]! {
		empty := if factory {
			api.message(cls, c'scannerWithString:', 0, 0)
		} else {
			api.message(api.message(cls, c'alloc', 0, 0), c'initWithString:', 0, 0)
		}
		assert api.text(api.message(empty, c'string', 0, 0)) == '' && api.message(empty, c'charactersToBeSkipped', 0, 0) != 0 && api.message(empty, c'isAtEnd', 0, 0) != 0
		if !factory { api.release(empty) }
	}
	for text in ['', 'plain', 'é中😀', 'x'.repeat(65536)] {
		for factory in [true, false]! {
			object := if factory {
				api.scanner(text)
			} else {
				api.message(api.message(cls, c'alloc', 0, 0), c'initWithString:', api.string(text), 0)
			}
			assert object != 0 && api.message(object, c'isKindOfClass:', cls, 0) != 0
			assert api.text(api.message(object, c'string', 0, 0)) == text
			assert api.message(object, c'scanLocation', 0, 0) == 0 && api.message(object, c'caseSensitive', 0, 0) == 0 && api.message(object, c'locale', 0, 0) == 0
			api.message(object, c'setLocale:', 0, 0)
			if !factory { api.release(object) }
		}
	}
	scanner_fixture_numbers(api)
	scanner_fixture_parsers(api)
	object := api.scanner(' \t\nAbC rest')
	mut guarded := [u64(0x1122334455667788), 0, 0x8877665544332211]!
	assert api.message(object, c'scanString:intoString:', api.string('abc'), u64(unsafe { &guarded[1] })) != 0 && api.text(guarded[1]) == 'AbC'
	assert guarded[0] == 0x1122334455667788 && guarded[2] == 0x8877665544332211 && api.message(object, c'scanLocation', 0, 0) == 6
	api.message(object, c'setScanLocation:', 0, 0)
	api.message(object, c'setCaseSensitive:', 1, 0)
	assert api.message(object, c'scanString:intoString:', api.string('abc'), 0) == 0 && api.message(object, c'scanLocation', 0, 0) == 0
	assert api.message(object, c'scanString:intoString:', api.string('AbC'), 0) != 0
	// All failed text scans leave the caller's output object and cursor intact.
	for selector in [c'scanString:intoString:', c'scanUpToString:intoString:',
		c'scanCharactersFromSet:intoString:']! {
		failed := api.scanner('  abc')
		sentinel := api.string('prior output')
		mut failure_guard := [u64(0x1122334455667788), sentinel, 0x8877665544332211]!
		argument := if selector == c'scanCharactersFromSet:intoString:' {
			api.message(api.cls('NSCharacterSet'), c'characterSetWithCharactersInString:', api.string('z'), 0)
		} else {
			api.string(if selector == c'scanUpToString:intoString:' { 'abc' } else { 'z' })
		}
		assert api.message(failed, selector, argument, u64(unsafe { &failure_guard[1] })) == 0
		assert failure_guard[0] == 0x1122334455667788 && failure_guard[1] == sentinel && failure_guard[2] == 0x8877665544332211 && api.message(failed, c'scanLocation', 0, 0) == 0
	}
	for selector in [c'scanString:intoString:', c'scanUpToString:intoString:']! {
		empty_pattern := api.scanner(' abc ')
		ok := api.message(empty_pattern, selector, api.string(''), u64(unsafe { &guarded[1] })) != 0
		assert ok == (selector == c'scanUpToString:intoString:')
		if ok {
			assert api.text(guarded[1]) == 'abc ' && api.message(empty_pattern, c'scanLocation', 0, 0) == 5
		}
	}
	spaces := api.scanner(' \t\n')
	assert api.message(spaces, c'isAtEnd', 0, 0) != 0 && api.message(spaces, c'scanLocation', 0, 0) == 0
	api.message(spaces, c'setCharactersToBeSkipped:', 0, 0)
	assert api.message(spaces, c'isAtEnd', 0, 0) == 0
	// Nil skips and a copied custom skip set change token boundaries explicitly.
	mutable_skip := api.message(api.cls('NSMutableCharacterSet'), c'characterSetWithCharactersInString:', api.string(' '), 0)
	with_skip := api.scanner(' ff!')
	api.message(with_skip, c'setCharactersToBeSkipped:', mutable_skip, 0)
	api.message(mutable_skip, c'addCharactersInString:', api.string('f'), 0)
	assert api.message(api.message(with_skip, c'charactersToBeSkipped', 0, 0), c'characterIsMember:', 102, 0) == 0
	mut value := u64(0)
	assert api.message(with_skip, c'scanHexLongLong:', u64(unsafe { &value }), 0) != 0 && value == 255
	copy := api.message(with_skip, c'copy', 0, 0)
	assert copy != with_skip && api.message(copy, c'scanLocation', 0, 0) == 3
	api.message(with_skip, c'setScanLocation:', 0, 0)
	assert api.message(copy, c'scanLocation', 0, 0) == 3
	api.message(copy, c'setCharactersToBeSkipped:', 0, 0)
	assert api.message(copy, c'charactersToBeSkipped', 0, 0) == 0
	api.release(copy)
	unicode_space := api.scanner('\u0085\u200b\u2028')
	assert api.message(unicode_space, c'isAtEnd', 0, 0) != 0 && api.message(unicode_space, c'scanLocation', 0, 0) == 0
	scalar_skip := api.message(api.message(api.cls('NSCharacterSet'), c'alphanumericCharacterSet', 0, 0), c'invertedSet', 0, 0)
	emoji_skip := api.scanner('😀')
	api.message(emoji_skip, c'setCharactersToBeSkipped:', scalar_skip, 0)
	assert api.message(emoji_skip, c'isAtEnd', 0, 0) != 0 && api.message(emoji_skip, c'scanLocation', 0, 0) == 0
	// UTF16 cursor coordinates count a supplementary scalar as two code units.
	unicode := api.scanner('😀é中!')
	api.message(unicode, c'setCaseSensitive:', 1, 0)
	assert api.text(api.message(unicode, c'string', 0, 0)) == '😀é中!'
	api.message(unicode, c'setScanLocation:', 2, 0)
	assert api.message(unicode, c'scanLocation', 0, 0) == 2
	api.message(unicode, c'setScanLocation:', 4, 0)
	assert api.message(unicode, c'scanLocation', 0, 0) == 4
	letters := api.message(api.cls('NSCharacterSet'), c'characterSetWithCharactersInString:', api.string('é中'), 0)
	bmp := api.scanner('é中!')
	mut output := u64(0)
	assert api.message(bmp, c'scanCharactersFromSet:intoString:', letters, u64(unsafe { &output })) != 0 && api.text(output) == 'é中' && api.message(bmp, c'scanLocation', 0, 0) == 2
	api.message(unicode, c'setScanLocation:', 5, 0)
	assert api.message(unicode, c'isAtEnd', 0, 0) != 0
	zero := api.scanner('a\x00b')
	api.message(zero, c'setCaseSensitive:', 1, 0)
	api.expect_bytes(api.message(zero, c'string', 0, 0), 'a\x00b')
	assert api.message(zero, c'scanString:intoString:', api.string('a\x00b'), u64(unsafe { &output })) != 0
	api.expect_bytes(output, 'a\x00b')
	assert api.message(zero, c'scanLocation', 0, 0) == 3
	up_set := api.scanner(' ab:cd')
	delimiter := api.message(api.cls('NSCharacterSet'), c'characterSetWithCharactersInString:', api.string(':'), 0)
	assert api.message(up_set, c'scanUpToCharactersFromSet:intoString:', delimiter, u64(unsafe { &output })) != 0 && api.text(output) == 'ab' && api.message(up_set, c'scanLocation', 0, 0) == 3
	// Successful output ownership is +0 and does not depend on the scanner.
	for selector in [c'scanString:intoString:', c'scanUpToString:intoString:',
		c'scanCharactersFromSet:intoString:']! {
		output_pool := api.pool()
		// Force heap strings: tagged native NSStrings do not die at pool drain.
		long_text := 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
		owned := api.message(api.message(cls, c'alloc', 0, 0), c'initWithString:', api.string(long_text + '!'), 0)
		argument := if selector == c'scanCharactersFromSet:intoString:' {
			api.message(api.cls('NSCharacterSet'), c'characterSetWithCharactersInString:', api.string(long_text), 0)
		} else {
			api.string(if selector == c'scanUpToString:intoString:' { '!' } else { long_text })
		}
		mut returned := u64(0)
		mut weak_output := u64(0)
		mut weak_scanner := u64(0)
		api.weak(unsafe { &weak_scanner }, owned)
		assert api.message(owned, selector, argument, u64(unsafe { &returned })) != 0
		api.weak(unsafe { &weak_output }, returned)
		api.release(owned)
		assert weak_scanner == 0 && weak_output != 0 && api.text(returned) == long_text
		api.drain(output_pool)
		assert weak_output == 0
		api.destroy_weak(unsafe { &weak_output })
		api.destroy_weak(unsafe { &weak_scanner })
	}
	// The scanner and a copied scanner own the mutable input's snapshot.
	inner := api.pool()
	input := api.message(api.message(api.cls('NSMutableString'), c'alloc', 0, 0), c'initWithString:', api.string('before café 😀'), 0)
	mut weak_input := u64(0)
	api.weak(unsafe { &weak_input }, input)
	survivor := api.retain(api.message(cls, c'scannerWithString:', input, 0))
	snapshot := api.message(survivor, c'copyWithZone:', 0, 0)
	api.message(input, c'setString:', api.string('changed'), 0)
	api.release(input)
	api.drain(inner)
	assert weak_input == 0 && api.text(api.message(survivor, c'string', 0, 0)) == 'before café 😀'
	api.release(survivor)
	api.drain(pool)
	last_pool := api.pool()
	assert api.text(api.message(snapshot, c'string', 0, 0)) == 'before café 😀'
	api.release(snapshot)
	api.destroy_weak(unsafe { &weak_input })
	api.drain(last_pool)
}

fn scanner_runtime_api() ScannerFixtureApi {
	return ScannerFixtureApi{false, u64(unsafe { voidptr(C.ios_objc_msgsend) })}
}

__global scanner_fixture_mode = ''
__global scanner_fixture_fired = false
__global scanner_fixture_target = u64(0)
__global scanner_fixture_input = u64(0)
__global scanner_fixture_source = u64(0)
__global scanner_fixture_delimiter = u64(0)
__global scanner_fixture_weak_input = u64(0)
__global scanner_fixture_weak_source = u64(0)
__global scanner_fixture_weak_result = u64(0)
__global scanner_fixture_weak_property = u64(0)

fn scanner_fixture_worker() {
	C.ios_objc_initialize_lock()
	C.ios_objc_initialize_unlock()
	if scanner_fixture_mode == 'reenter' {
		api := scanner_runtime_api()
		assert api.message(scanner_fixture_source, c'scanLocation', 0, 0) == 2
		assert api.message(scanner_fixture_source, c'scanString:intoString:', scanner_fixture_delimiter, 0) != 0
		assert api.message(scanner_fixture_source, c'scanUpToString:intoString:', scanner_fixture_delimiter, 0) != 0
		assert api.message(scanner_fixture_source, c'scanLocation', 0, 0) == 5
	} else {
		if scanner_fixture_input != 0 { objc_release(scanner_fixture_input) }
		if scanner_fixture_source != 0 { objc_release(scanner_fixture_source) }
	}
}

fn scanner_fixture_constructor(object u64, selector u64) u64 {
	if scanner_fixture_mode == '' || scanner_fixture_fired || read64(object) != scanner_fixture_target {
		return object
	}
	scanner_fixture_fired = true
	if scanner_fixture_mode in ['release-input', 'release-source', 'reenter']! {
		worker := spawn scanner_fixture_worker()
		worker.wait()
	}
	if scanner_fixture_mode == 'fail' {
		objc_store_weak(unsafe { &scanner_fixture_weak_result }, object)
		property := objc_new(ios_runtime.names['NSObject'])
		obj_header(object).fields[3] = property
		objc_store_weak(unsafe { &scanner_fixture_weak_property }, property)
		return 0
	}
	if scanner_fixture_mode == 'constructor-isa' {
		objc_set_class(object, ios_runtime.names['NSObject'])
	}
	if scanner_fixture_mode == 'constructor-storage' {
		obj_header(object).scanner.initialized = true
	}
	return object
}

fn scanner_fixture_hook(cls u64) {
	assert objc_add_method(cls, u64(c'.cxx_construct'), u64(unsafe { voidptr(scanner_fixture_constructor) }), c'@16@0:8')
}

fn scanner_fixture_activate(mode string, cls u64) {
	scanner_fixture_mode = mode
	scanner_fixture_target = cls
	scanner_fixture_fired = false
}

fn scanner_fixture_owned(api ScannerFixtureApi, text string) u64 {
	return api.message(api.message(api.cls('NSScanner'), c'alloc', 0, 0), c'initWithString:', api.string(text), 0)
}

fn scanner_fixture_runtime_lifetimes(api ScannerFixtureApi) {
	pool := api.pool()
	cls := api.cls('NSScanner')
	library := '/System/Library/Frameworks/Foundation.framework/Foundation'
	assert runtime_symbol(library, '_OBJC_CLASS_$_NSScanner') or { panic(err) } == cls
	assert runtime_symbol(library, '_OBJC_METACLASS_$_NSScanner') or { panic(err) } == read64(cls)
	image_text := 'image é中😀'.clone()
	mut image_record := [api.cls('NSString'), u64(0x7c8), u64(image_text.str), u64(image_text.len)]!
	image_address := u64(unsafe { &image_record[0] })
	ios_runtime.constants[image_address] = true
	image_scanner := api.message(cls, c'scannerWithString:', image_address, 0)
	ios_runtime.constants.delete(image_address)
	unsafe { image_text.free() }
	assert api.text(api.message(image_scanner, c'string', 0, 0)) == 'image é中😀'
	mut guarded := [u64(0x1122334455667788), 0, 0x8877665544332211]!
	caller := u64(unsafe { &guarded[1] })
	assert objc_construct_instance(cls, caller) == caller
	assert api.message(caller, c'initWithString:', api.string('123!'), 0) == caller
	mut number := i64(0)
	assert api.message(caller, c'scanInteger:', u64(unsafe { &number }), 0) != 0 && number == 123
	objc_set_class(caller, api.cls('NSObject'))
	assert objc_destruct_instance(caller) == caller
	assert caller !in ios_runtime.objects && guarded[0] == 0x1122334455667788 && guarded[2] == 0x8877665544332211
	for _ in 0 .. 32 {
		object := scanner_fixture_owned(api, 'owned é中😀')
		objc_set_class(object, api.cls('NSObject'))
		api.release(object)
	}
	for name in ['NSScanner', 'NSString', 'NSCharacterSet']! { scanner_fixture_hook(api.cls(name)) }
	input := owned_string('before constructor é中😀')
	objc_store_weak(unsafe { &scanner_fixture_weak_input }, input)
	scanner_fixture_input = input
	scanner_fixture_activate('release-input', cls)
	snapshot := api.message(cls, c'scannerWithString:', input, 0)
	scanner_fixture_mode = ''
	scanner_fixture_input = 0
	assert scanner_fixture_fired && scanner_fixture_weak_input == 0 && api.text(api.message(snapshot, c'string', 0, 0)) == 'before constructor é中😀'
	objc_destroy_weak(unsafe { &scanner_fixture_weak_input })
	source := scanner_fixture_owned(api, 'ab:cd')
	api.message(source, c'setScanLocation:', 2, 0)
	api.message(source, c'setCaseSensitive:', 1, 0)
	api.message(source, c'setCharactersToBeSkipped:', 0, 0)
	objc_store_weak(unsafe { &scanner_fixture_weak_source }, source)
	scanner_fixture_source = source
	scanner_fixture_activate('release-source', cls)
	copy := api.message(source, c'copy', 0, 0)
	scanner_fixture_mode = ''
	scanner_fixture_source = 0
	assert scanner_fixture_fired && scanner_fixture_weak_source == 0 && api.text(api.message(copy, c'string', 0, 0)) == 'ab:cd'
	assert api.message(copy, c'scanLocation', 0, 0) == 2 && api.message(copy, c'caseSensitive', 0, 0) != 0 && api.message(copy, c'charactersToBeSkipped', 0, 0) == 0
	api.release(copy)
	objc_destroy_weak(unsafe { &scanner_fixture_weak_source })
	// Each getter snapshots its payload before its constructor drops the receiver.
	for getter in [c'string', c'charactersToBeSkipped']! {
		owned := scanner_fixture_owned(api, 'getter é中😀')
		objc_store_weak(unsafe { &scanner_fixture_weak_source }, owned)
		scanner_fixture_source = owned
		scanner_fixture_activate('release-source', api.cls(if getter == c'string' {
			'NSString'
		} else {
			'NSCharacterSet'
		}))
		result := api.message(owned, getter, 0, 0)
		scanner_fixture_mode = ''
		scanner_fixture_source = 0
		assert scanner_fixture_fired && scanner_fixture_weak_source == 0
		if getter == c'string' {
			assert api.text(result) == 'getter é中😀'
		} else {
			assert api.message(result, c'characterIsMember:', 10, 0) != 0
		}
		objc_destroy_weak(unsafe { &scanner_fixture_weak_source })
	}
	delimiter := api.string(':')
	scanner_fixture_delimiter = delimiter
	for mode in ['release-source', 'reenter']! {
		owned := scanner_fixture_owned(api, 'ab:cd')
		objc_store_weak(unsafe { &scanner_fixture_weak_source }, owned)
		scanner_fixture_source = owned
		scanner_fixture_activate(mode, api.cls('NSString'))
		mut output := u64(0)
		assert api.message(owned, c'scanUpToString:intoString:', delimiter, u64(unsafe { &output })) != 0
		scanner_fixture_mode = ''
		scanner_fixture_source = 0
		assert scanner_fixture_fired && api.text(output) == 'ab'
		if mode == 'release-source' {
			assert scanner_fixture_weak_source == 0
		} else {
			assert api.message(owned, c'scanLocation', 0, 0) == 5
			api.release(owned)
		}
		objc_destroy_weak(unsafe { &scanner_fixture_weak_source })
	}
	scanner_fixture_delimiter = 0
	// A failed result constructor writes nil after committing a successful scan.
	failing_output := scanner_fixture_owned(api, 'ab:cd')
	before_output := ios_runtime.objects.len
	scanner_fixture_activate('fail', api.cls('NSString'))
	mut output := u64(0xdeadbeef)
	assert api.message(failing_output, c'scanUpToString:intoString:', delimiter, u64(unsafe { &output })) != 0
	scanner_fixture_mode = ''
	assert scanner_fixture_fired && output == 0 && api.message(failing_output, c'scanLocation', 0, 0) == 2
	assert scanner_fixture_weak_result == 0 && scanner_fixture_weak_property == 0 && ios_runtime.objects.len == before_output
	objc_destroy_weak(unsafe { &scanner_fixture_weak_result })
	objc_destroy_weak(unsafe { &scanner_fixture_weak_property })
	api.release(failing_output)
	// Factory/copy/caller constructor failure removes state, properties and weak refs.
	valid := scanner_fixture_owned(api, 'rollback')
	input2 := owned_string('input')
	for operation in 0 .. 3 {
		before := ios_runtime.objects.len
		scanner_fixture_activate('fail', cls)
		result := if operation == 0 {
			api.message(cls, c'scannerWithString:', input2, 0)
		} else if operation == 1 {
			api.message(valid, c'copy', 0, 0)
		} else {
			objc_construct_instance(cls, caller)
		}
		scanner_fixture_mode = ''
		assert result == 0 && scanner_fixture_fired && scanner_fixture_weak_result == 0 && scanner_fixture_weak_property == 0
		objc_destroy_weak(unsafe { &scanner_fixture_weak_result })
		objc_destroy_weak(unsafe { &scanner_fixture_weak_property })
		assert ios_runtime.objects.len == before && guarded[0] == 0x1122334455667788 && guarded[2] == 0x8877665544332211
	}
	api.release(valid)
	api.release(input2)
	api.drain(pool)
}

fn test_scanner_runtime() {
	for _ in 0 .. 2 {
		scanner_fixture_mode = ''
		scanner_fixture_source = 0
		scanner_fixture_input = 0
		objc_start()
		api := scanner_runtime_api()
		scanner_fixture_shared(api)
		scanner_fixture_runtime_lifetimes(api)
		assert ios_runtime.objects.len == 0 && ios_runtime.live == 0 && ios_runtime.weak.len == 0
		objc_stop()
		assert ios_runtime.objects.len == 0 && ios_runtime.live == 0
	}
	println('IOS-SCANNER: selected parser sequences, numeric/output canaries, snapshots, joined-worker constructor release/reentry, failure rollback, guarded caller storage, isa disposal and two drained runtimes')
}

fn test_scanner_rejections() {
	objc_start()
	api := scanner_runtime_api()
	cls := api.cls('NSScanner')
	for selector in [c'localizedScannerWithString:', c'scanDouble:', c'scanFloat:', c'scanHexDouble:',
		c'encodeWithCoder:']! {
		assert !objc_responds(cls, selector)
	}
	modes := ['raw-getter', 'repeat-init', 'subclass', 'caller-subclass', 'spoof', 'isa-change',
		'copy-provenance', 'tombstone', 'string-type', 'string-class', 'string-custom', 'string-spoof',
		'string-isa', 'string-raw', 'string-utf8', 'string-limit', 'nil-pattern', 'nil-set',
		'pattern-type', 'pattern-utf8', 'number-nonascii', 'insensitive-source', 'sensitive-source',
		'insensitive-pattern', 'sensitive-pattern', 'set-supplementary', 'skip-type', 'skip-raw',
		'skip-isa', 'skip-tombstone', 'scan-set-type', 'scan-set-raw', 'scan-set-isa', 'state-missing',
		'state-uninitialized', 'location-limit', 'location-surrogate', 'nonzero-locale', 'nonzero-zone',
		'unsupported-float', 'unsupported-copy', 'unsupported-coding', 'unsupported-hash',
		'constructor-isa', 'constructor-storage']!
	for mode in modes {
		mut fds := [2]i32{}
		assert C.pipe(unsafe { &fds[0] }) == 0
		pid := C.ios_fork()
		assert pid >= 0
		if pid == 0 {
			C.close(fds[0])
			assert C.dup2(fds[1], 2) == 2
			C.close(fds[1])
			pool := api.pool()
			object := api.scanner('abc')
			scanner_fixture_mode = ''
			scanner_fixture_fired = false
			match mode {
				'raw-getter' { api.message(objc_allocate(cls), c'string', 0, 0) }
				'repeat-init' { api.message(object, c'initWithString:', api.string('again'), 0) }
				'subclass', 'caller-subclass' {
					custom := objc_allocate_class(cls, c'VinixUnsupportedScanner', 0)
					objc_register_class(custom)
					if mode == 'subclass' {
						objc_allocate(custom)
					} else {
						mut bytes := [1]u64{}
						objc_construct_instance(custom, u64(unsafe { &bytes[0] }))
					}
				}
				'spoof' {
					wrong := objc_new(api.cls('NSObject'))
					objc_set_class(wrong, cls)
					api.message(wrong, c'string', 0, 0)
				}
				'isa-change' {
					objc_set_class(object, api.cls('NSObject'))
					api.message(object, c'string', 0, 0)
				}
				'copy-provenance' {
					objc_set_class(object, api.cls('NSURLRequest'))
					objc_copy_value(object, false)
				}
				'tombstone' {
					mut bytes := [1]u64{}
					caller := objc_construct_instance(cls, u64(unsafe { &bytes[0] }))
					api.message(caller, c'init', 0, 0)
					objc_destruct_instance(caller)
					api.message(caller, c'string', 0, 0)
				}
				'string-type', 'string-class' {
					input := if mode == 'string-class' {
						api.cls('NSString')
					} else {
						objc_new(api.cls('NSObject'))
					}
					api.message(cls, c'scannerWithString:', input, 0)
				}
				'string-custom', 'string-spoof', 'string-isa', 'string-raw', 'string-utf8',
				'pattern-utf8' {
					mut input := if mode == 'string-raw' {
						objc_allocate(api.cls('NSMutableString'))
					} else {
						owned_string('input')
					}
					if mode == 'string-custom' {
						custom := objc_allocate_class(api.cls('NSString'), c'VinixUnsupportedScannerString', 0)
						objc_register_class(custom)
						objc_set_class(input, custom)
					}
					if mode == 'string-spoof' {
						objc_release(input)
						input = objc_new(api.cls('NSObject'))
						objc_set_class(input, api.cls('NSString'))
					}
					if mode == 'string-isa' { objc_set_class(input, api.cls('NSMutableString')) }
					if mode in ['string-utf8', 'pattern-utf8']! {
						unsafe { obj_header(input).text[0] = char(0xff) }
					}
					if mode == 'pattern-utf8' {
						api.message(object, c'scanString:intoString:', input, 0)
					} else {
						api.message(cls, c'scannerWithString:', input, 0)
					}
				}
				'string-limit' { api.scanner('x'.repeat(65537)) }
				'nil-pattern' { api.message(object, c'scanString:intoString:', 0, 0) }
				'nil-set' { api.message(object, c'scanCharactersFromSet:intoString:', 0, 0) }
				'pattern-type' {
					api.message(object, c'scanUpToString:intoString:', objc_new(api.cls('NSObject')), 0)
				}
				'number-nonascii' { api.message(api.scanner('1é'), c'scanInteger:', 0, 0) }
				'insensitive-source', 'sensitive-source', 'insensitive-pattern', 'sensitive-pattern' {
					pattern_case := mode.ends_with('pattern')
					scanner := api.scanner(if pattern_case { 'abc' } else { 'aé' })
					api.message(scanner, c'setCaseSensitive:', u64(mode.starts_with('sensitive')), 0)
					api.message(scanner, c'scanString:intoString:', api.string(if pattern_case {
						'é'
					} else {
						'a'
					}), 0)
				}
				'set-supplementary' {
					api.message(api.scanner('a😀'), c'scanCharactersFromSet:intoString:', api.message(api.cls('NSCharacterSet'), c'alphanumericCharacterSet', 0, 0), 0)
				}
				'skip-type', 'skip-raw', 'skip-isa', 'skip-tombstone', 'scan-set-type',
				'scan-set-raw', 'scan-set-isa' {
					mut other := if mode.ends_with('type') {
						objc_new(api.cls('NSObject'))
					} else if mode.ends_with('raw') {
						objc_allocate(api.cls('NSCharacterSet'))
					} else {
						api.message(api.cls('NSCharacterSet'), c'alphanumericCharacterSet', 0, 0)
					}
					if mode.ends_with('isa') { objc_set_class(other, api.cls('NSObject')) }
					mut storage := [1]u64{}
					if mode.ends_with('tombstone') {
						other = objc_construct_instance(api.cls('NSCharacterSet'), u64(unsafe { &storage[0] }))
						api.message(other, c'init', 0, 0)
						objc_destruct_instance(other)
					}
					api.message(object, if mode.starts_with('skip') {
						c'setCharactersToBeSkipped:'
					} else {
						c'scanCharactersFromSet:intoString:'
					}, other, 0)
				}
				'state-missing' {
					obj_header(object).scanner.skip = unsafe { nil }
					api.message(object, c'string', 0, 0)
				}
				'state-uninitialized' {
					obj_header(object).scanner.initialized = false
					api.message(object, c'string', 0, 0)
				}
				'location-limit' { api.message(object, c'setScanLocation:', 4, 0) }
				'location-surrogate' { api.message(api.scanner('😀'), c'setScanLocation:', 1, 0) }
				'nonzero-locale' {
					api.message(object, c'setLocale:', objc_new(api.cls('NSObject')), 0)
				}
				'nonzero-zone' { api.message(object, c'copyWithZone:', 1, 0) }
				'unsupported-float', 'unsupported-copy', 'unsupported-coding', 'unsupported-hash' {
					selector := match mode {
						'unsupported-float' { c'scanDouble:' }
						'unsupported-copy' { c'mutableCopy' }
						'unsupported-coding' { c'encodeWithCoder:' }
						else { c'hash' }
					}
					api.message(object, selector, 0, 0)
				}
				'constructor-isa', 'constructor-storage' {
					scanner_fixture_hook(cls)
					scanner_fixture_activate(mode, cls)
					api.message(object, c'copy', 0, 0)
				}
				else {}
			}
			api.drain(pool)
			C._exit(0)
		}
		C.close(fds[1])
		mut bytes := [16384]u8{}
		mut length := 0
		for {
			assert length < bytes.len
			count := C.read(fds[0], unsafe { &bytes[length] }, usize(bytes.len - length))
			if count == 0 { break }
			if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }
			assert count > 0
			length += int(count)
		}
		C.close(fds[0])
		mut status := i32(0)
		assert C.ios_waitpid(pid, &status, 0) == pid
		output := unsafe { tos(&bytes[0], length) }
		assert status == 256 && output.contains('iOS:') && !output.contains('AddressSanitizer') && !output.contains('runtime error:'), mode + ': ' + output
	}
	objc_stop()
	assert ios_runtime.live == 0
	println('IOS-SCANNER-REJECT:' + modes.len.str() + ' provenance, input/domain, invalid cursor, malformed sets, unsupported options and constructor mutation failures are explicit')
}

fn test_scanner_native() {
	$if macos {
		api := ScannerFixtureApi{true, u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend'))}
		assert api.send != 0
		scanner_fixture_shared(api)
		println('IOS-SCANNER-NATIVE: public metadata, selected parser sequences, numeric canaries/saturation, string/set scans, skips, UTF16 locations, copies and snapshot lifetimes')
	}
}

// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256

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

type CharacterSetFixtureSend = fn (u64, u64, u64, u64) u64
type CharacterSetFixtureBytes = fn (u64, u64, u64, u64, u64) u64

struct CharacterSetFixtureApi {
	native bool
	send   u64
}

fn (api CharacterSetFixtureApi) cls(name string) u64 {
	$if macos {
		if api.native { return u64(C.objc_getClass(name.str)) }
	}
	return ios_runtime.names[name]
}

fn (api CharacterSetFixtureApi) selector(name &char) u64 {
	$if macos {
		if api.native { return u64(C.sel_registerName(name)) }
	}
	return u64(name)
}

fn (api CharacterSetFixtureApi) message(object u64, name &char, a u64, b u64) u64 {
	return unsafe { CharacterSetFixtureSend(voidptr(api.send))(object, api.selector(name), a, b) }
}

fn (api CharacterSetFixtureApi) string(value string) u64 {
	object := api.message(api.cls('NSString'), c'alloc', 0, 0)
	result := unsafe { CharacterSetFixtureBytes(voidptr(api.send))(object, api.selector(c'initWithBytes:length:encoding:'), u64(value.str), u64(value.len), 4) }
	return api.message(result, c'autorelease', 0, 0)
}

fn (api CharacterSetFixtureApi) set(value string, mutable bool) u64 {
	return api.message(api.cls(if mutable { 'NSMutableCharacterSet' } else { 'NSCharacterSet' }), c'characterSetWithCharactersInString:', api.string(value), 0)
}

fn (api CharacterSetFixtureApi) member(object u64, point u32) bool {
	return api.message(object, c'longCharacterIsMember:', point, 0) != 0
}

fn (api CharacterSetFixtureApi) retain(object u64) u64 {
	return api.message(object, c'retain', 0, 0)
}

fn (api CharacterSetFixtureApi) release(object u64) { api.message(object, c'release', 0, 0) }

fn (api CharacterSetFixtureApi) pool() u64 {
	$if macos {
		if api.native { return api.message(api.cls('NSAutoreleasePool'), c'new', 0, 0) }
	}
	return objc_pool_push()
}

fn (api CharacterSetFixtureApi) drain(pool u64) {
	$if macos {
		if api.native {
			api.message(pool, c'drain', 0, 0)
			return
		}
	}
	objc_pool_pop(pool)
}

fn (api CharacterSetFixtureApi) weak(slot &u64, object u64) {
	$if macos {
		if api.native {
			C.objc_storeWeak(slot, unsafe { voidptr(object) })
			return
		}
	}
	objc_store_weak(slot, object)
}

fn (api CharacterSetFixtureApi) destroy_weak(slot &u64) {
	$if macos {
		if api.native {
			C.objc_storeWeak(slot, unsafe { nil })
			return
		}
	}
	objc_destroy_weak(slot)
}

fn character_set_fixture_metadata(api CharacterSetFixtureApi) {
	for name in ['NSCharacterSet', 'NSMutableCharacterSet']! {
		cls := api.cls(name)
		parent := api.cls(if name == 'NSCharacterSet' { 'NSObject' } else { 'NSCharacterSet' })
		assert cls != 0
		mut count := u32(99)
		$if macos {
			if api.native {
				assert C.class_getInstanceSize(voidptr(cls)) == 8 && u64(C.class_getSuperclass(voidptr(cls))) == parent
				ivars := C.class_copyIvarList(voidptr(cls), &count)
				assert count == 0
				unsafe { C.free(ivars) }
			}
		}
		if !api.native {
			assert objc_class_size(cls) == 8 && objc_class_parent(cls) == parent
			ivars := objc_copy_ivars(cls, &count)
			assert count == 0
			unsafe { C.free(ivars) }
		}
		for selector, types in {
			'characterSetWithCharactersInString:': '@24@0:8@16'
			'alphanumericCharacterSet':            '@16@0:8'
			'decimalDigitCharacterSet':            '@16@0:8'
			'whitespaceCharacterSet':              '@16@0:8'
			'URLQueryAllowedCharacterSet':         '@16@0:8'
			'URLHostAllowedCharacterSet':          '@16@0:8'
			'URLPathAllowedCharacterSet':          '@16@0:8'
			'illegalCharacterSet':                 '@16@0:8'
			'controlCharacterSet':                 '@16@0:8'
			'init':                                '@16@0:8'
			'copy':                                '@16@0:8'
			'copyWithZone:':                       '@24@0:8^{_NSZone=}16'
			'mutableCopy':                         '@16@0:8'
			'mutableCopyWithZone:':                '@24@0:8^{_NSZone=}16'
			'invertedSet':                         '@16@0:8'
			'characterIsMember:':                  'B20@0:8S16'
			'longCharacterIsMember:':              'B20@0:8I16'
			'isSupersetOfSet:':                    'B24@0:8@16'
		} {
			meta := selector.ends_with('CharacterSet') || selector == 'characterSetWithCharactersInString:'
			mut actual := ''
			$if macos {
				if api.native {
					method := if meta {
						C.class_getClassMethod(voidptr(cls), voidptr(api.selector(selector.str)))
					} else {
						C.class_getInstanceMethod(voidptr(cls), voidptr(api.selector(selector.str)))
					}
					assert method != unsafe { nil }, selector
					actual = unsafe { C.method_getTypeEncoding(method).vstring() }
				}
			}
			if !api.native {
				method := if meta {
					objc_class_method(cls, u64(selector.str))
				} else {
					objc_instance_method(cls, u64(selector.str))
				}
				assert method != 0, selector
				actual = ctext(u64(objc_method_types(method)))
			}
			assert actual == types, name + ' ' + selector + ': ' + actual
		}
		if name == 'NSMutableCharacterSet' {
			for selector in ['addCharactersInString:', 'removeCharactersInString:',
				'formUnionWithCharacterSet:']! {
				mut actual := ''
				$if macos {
					if api.native {
						method := C.class_getInstanceMethod(voidptr(cls), voidptr(api.selector(selector.str)))
						assert method != unsafe { nil }
						actual = unsafe { C.method_getTypeEncoding(method).vstring() }
					}
				}
				if !api.native {
					method := objc_instance_method(cls, u64(selector.str))
					assert method != 0
					actual = ctext(u64(objc_method_types(method)))
				}
				assert actual == 'v24@0:8@16', selector + ': ' + actual
			}
		}
	}
}

fn character_set_fixture_shared(api CharacterSetFixtureApi) {
	pool := api.pool()
	character_set_fixture_metadata(api)
	for mutable in [false, true]! {
		cls := api.cls(if mutable { 'NSMutableCharacterSet' } else { 'NSCharacterSet' })
		for construction in [c'new', c'alloc']! {
			mut object := api.message(cls, construction, 0, 0)
			if construction == c'alloc' { object = api.message(object, c'init', 0, 0) }
			assert object != 0
			for point in [u32(0), 65, 0xe9, 0xd800, 0x1f600, 0x10ffff]! {
				assert !api.member(object, point)
			}
			api.release(object)
		}
		object := api.set('aA0é中\x00a', mutable)
		for point in [u32(0), 48, 65, 97, 0xe9, 0x4e2d]! {
			assert api.member(object, point)
		}
		for point in [u32(1), 66, 98, 0x301, 0xd800, 0xd83d, 0xde00, 0x1f601, 0x10ffff]! {
			assert !api.member(object, point)
		}
		assert api.message(object, c'characterIsMember:', 0xe9, 0) != 0
		assert api.message(object, c'characterIsMember:', 0xd83d, 0) == 0 && api.message(object, c'characterIsMember:', 0xde00, 0) == 0
		for selector in [c'copy', c'copyWithZone:', c'mutableCopy', c'mutableCopyWithZone:']! {
			copy := api.message(object, selector, 0, 0)
			assert copy != 0
			for point in [u32(0), 65, 97, 0xe9, 0x4e2d]! {
				assert api.member(copy, point)
			}
			assert !api.member(copy, 66)
			api.release(copy)
		}
		inverse := api.message(object, c'invertedSet', 0, 0)
		for point in [u32(0), 1, 65, 66, 0xe9, 0x301, 0xd800, 0xd83d, 0xde00, 0x1f600, 0x1f601,
			0x10ffff]! {
			assert api.member(inverse, point) != api.member(object, point)
		}
	}
	// Copying a mutable set produces snapshots independent in both directions.
	original := api.set('a中', true)
	copy := api.message(original, c'copy', 0, 0)
	mutable_copy := api.message(original, c'mutableCopy', 0, 0)
	assert copy != original && mutable_copy != original && copy != mutable_copy
	api.message(original, c'removeCharactersInString:', api.string('a中'), 0)
	api.message(original, c'addCharactersInString:', api.string('b'), 0)
	assert !api.member(original, 97) && !api.member(original, 0x4e2d) && api.member(original, 98)
	assert api.member(copy, 97) && api.member(copy, 0x4e2d) && !api.member(copy, 98)
	assert api.member(mutable_copy, 97) && api.member(mutable_copy, 0x4e2d)
	api.message(mutable_copy, c'addCharactersInString:', api.string('c'), 0)
	assert api.member(mutable_copy, 99) && !api.member(copy, 99) && !api.member(original, 99)
	api.release(copy)
	api.release(mutable_copy)
	merged := api.set('a', true)
	additions := api.set('b中', true)
	api.message(merged, c'formUnionWithCharacterSet:', additions, 0)
	api.message(merged, c'formUnionWithCharacterSet:', merged, 0)
	assert api.message(merged, c'isSupersetOfSet:', additions, 0) != 0 && api.message(merged, c'isSupersetOfSet:', merged, 0) != 0
	assert api.message(additions, c'isSupersetOfSet:', merged, 0) == 0
	api.message(additions, c'removeCharactersInString:', api.string('b中'), 0)
	assert api.member(merged, 97) && api.member(merged, 98) && api.member(merged, 0x4e2d)
	assert api.message(merged, c'isSupersetOfSet:', api.set('', false), 0) != 0
	for cls in [api.cls('NSCharacterSet'), api.cls('NSMutableCharacterSet')]! {
		for selector in ['alphanumericCharacterSet', 'decimalDigitCharacterSet',
			'whitespaceCharacterSet', 'URLQueryAllowedCharacterSet', 'URLHostAllowedCharacterSet',
			'URLPathAllowedCharacterSet', 'illegalCharacterSet', 'controlCharacterSet']! {
			predefined := api.message(cls, selector.str, 0, 0)
			copy_set := api.message(predefined, c'mutableCopy', 0, 0)
			inverted := api.message(predefined, c'invertedSet', 0, 0)
			for point in [u32(0), 9, 10, 32, 35, 37, 47, 48, 65, 95, 0xa0, 0xe9, 0x660, 0x2000,
				0x4e2d, 0xd800, 0x10400, 0x1d7ce, 0x1f600, 0x10ffff]! {
				assert api.member(predefined, point) == api.member(copy_set, point)
				assert api.member(predefined, point) != api.member(inverted, point)
			}
			match selector {
				'alphanumericCharacterSet' {
					for point in [u32(48), 65, 0xe9, 0x4e2d, 0x10400, 0x1d7ce]! {
						assert api.member(predefined, point)
					}
					assert !api.member(predefined, 32) && !api.member(predefined, 0x1f600)
				}
				'decimalDigitCharacterSet' {
					for point in [u32(48), 0x660, 0x1d7ce]! {
						assert api.member(predefined, point)
					}
					assert !api.member(predefined, 65) && !api.member(predefined, 0xe9)
				}
				'whitespaceCharacterSet' {
					for point in [u32(9), 32, 0xa0, 0x2000]! {
						assert api.member(predefined, point)
					}
					assert !api.member(predefined, 10) && !api.member(predefined, 65)
				}
				'URLQueryAllowedCharacterSet', 'URLHostAllowedCharacterSet',
				'URLPathAllowedCharacterSet' {
					for point in [u32(48), 65, 95]! {
						assert api.member(predefined, point)
					}
					for point in [u32(32), 35, 37]! {
						assert !api.member(predefined, point)
					}
					assert api.member(predefined, 47) == (selector != 'URLHostAllowedCharacterSet')
				}
				'controlCharacterSet' {
					for point in [u32(0), 9, 10, 0x7f, 0x85, 0x200b, 0xe0001]! {
						assert api.member(predefined, point)
					}
					assert !api.member(predefined, 65) && !api.member(predefined, 0xd800)
				}
				'illegalCharacterSet' {
					for point in [u32(0x378), 0xfdd0, 0xfffe, 0xffff, 0x1fffe, 0x1ffff]! {
						assert api.member(predefined, point)
					}
					assert !api.member(predefined, 0xd800) && !api.member(predefined, 0x10ffff)
				}
				else {}
			}
			api.message(copy_set, c'addCharactersInString:', api.string('A中'), 0)
			assert api.member(copy_set, 65) && api.member(copy_set, 0x4e2d)
			api.release(copy_set)
		}
	}
	large := api.set('x'.repeat(65536), false)
	assert api.member(large, 120) && !api.member(large, 121)
	// Factories capture mutable inputs and owned copies outlive their pool.
	inner := api.pool()
	text := api.message(api.message(api.cls('NSMutableString'), c'alloc', 0, 0), c'initWithString:', api.string('é中'), 0)
	mut weak := u64(0)
	api.weak(unsafe { &weak }, text)
	set := api.message(api.cls('NSCharacterSet'), c'characterSetWithCharactersInString:', text, 0)
	survivor := api.message(set, c'mutableCopy', 0, 0)
	api.message(text, c'setString:', api.string('z'), 0)
	api.release(text)
	api.drain(inner)
	assert weak == 0
	assert api.member(survivor, 0xe9) && api.member(survivor, 0x4e2d) && !api.member(survivor, 122)
	api.drain(pool)
	assert api.member(survivor, 0x4e2d)
	api.release(survivor)
	api.destroy_weak(unsafe { &weak })
}

fn character_set_runtime_api() CharacterSetFixtureApi {
	return CharacterSetFixtureApi{false, u64(unsafe { voidptr(C.ios_objc_msgsend) })}
}

__global character_set_fixture_mode = ''
__global character_set_fixture_fired = false
__global character_set_fixture_input = u64(0)
__global character_set_fixture_source = u64(0)
__global character_set_fixture_weak_input = u64(0)
__global character_set_fixture_weak_source = u64(0)
__global character_set_fixture_weak_result = u64(0)
__global character_set_fixture_weak_property = u64(0)

fn character_set_fixture_worker() {
	C.ios_objc_initialize_lock()
	C.ios_objc_initialize_unlock()
	if character_set_fixture_input != 0 { objc_release(character_set_fixture_input) }
	if character_set_fixture_source != 0 { objc_release(character_set_fixture_source) }
}

fn character_set_fixture_constructor(object u64, selector u64) u64 {
	if character_set_fixture_mode == '' || character_set_fixture_fired { return object }
	character_set_fixture_fired = true
	if character_set_fixture_mode in ['release-input', 'release-source']! {
		worker := spawn character_set_fixture_worker()
		worker.wait()
	}
	if character_set_fixture_mode == 'fail' {
		objc_store_weak(unsafe { &character_set_fixture_weak_result }, object)
		property := objc_new(ios_runtime.names['NSObject'])
		obj_header(object).fields[3] = property
		objc_store_weak(unsafe { &character_set_fixture_weak_property }, property)
		return 0
	}
	if character_set_fixture_mode == 'constructor-isa' {
		objc_set_class(object, ios_runtime.names['NSObject'])
	}
	if character_set_fixture_mode == 'constructor-storage' {
		obj_header(object).character_set.initialized = true
	}
	return object
}

fn character_set_fixture_hook(cls u64) {
	assert objc_add_method(cls, u64(c'.cxx_construct'), u64(unsafe { voidptr(character_set_fixture_constructor) }), c'@16@0:8')
}

fn character_set_fixture_runtime_lifetimes(api CharacterSetFixtureApi) {
	pool := api.pool()
	cls := api.cls('NSCharacterSet')
	mutable_cls := api.cls('NSMutableCharacterSet')
	library := '/System/Library/Frameworks/Foundation.framework/Foundation'
	for name in ['NSCharacterSet', 'NSMutableCharacterSet']! {
		assert runtime_symbol(library, '_OBJC_CLASS_$_' + name) or { panic(err) } == api.cls(name)
		assert runtime_symbol(library, '_OBJC_METACLASS_$_' + name) or { panic(err) } == read64(api.cls(name))
	}
	// Compare every generated bit against independently measured native hashes.
	for selector, golden in {
		'alphanumericCharacterSet':    '586a7d372aacbc7fb5c0de5a956fc029364dcd0125b89fccfab226cdc8b12b78'
		'decimalDigitCharacterSet':    'b355b814949e2c7facc5ba9c77413e7dde23309eba9fafde1675f86d8b66d521'
		'whitespaceCharacterSet':      'a8f42246033ede95a96c85e94a161b2d93b33715736def3a43989962b226b15b'
		'URLQueryAllowedCharacterSet': '5bde8ea76e638701f0f99630a38db413db47980d9ecea0ea2bc3c419c3b45db1'
		'URLHostAllowedCharacterSet':  'ba44ae279c4fd64e912ea792b44a00adafe9278c5608e5ef35794aac7b3223ab'
		'URLPathAllowedCharacterSet':  'df5259ab6121e48dde8191dac0cb7da2c5febf4d24ad0d89c59874e332f14ce6'
		'illegalCharacterSet':         '8e9fb234468580d8d774174673c261e6b250a3a11892444254f8a4f264cc24a9'
		'controlCharacterSet':         'dbb8312b78c0aa92f63952bd4e37085f0a138d31899c5a38982572fe3eccb2ec'
	} {
		for receiver in [cls, mutable_cls]! {
			object := api.message(receiver, selector.str, 0, 0)
			C.ios_objc_initialize_lock()
			state := ns_character_set_storage(object, true)
			bytes := unsafe { state.bits.vbytes(ns_character_set_bytes) }
			digest := sha256.sum(bytes).hex()
			C.ios_objc_initialize_unlock()
			assert digest == golden, selector + ': ' + digest
		}
	}
	image_text := 'image é中'.clone()
	mut image_record := [api.cls('NSString'), u64(0x7c8), u64(image_text.str), u64(image_text.len)]!
	image_address := u64(unsafe { &image_record[0] })
	ios_runtime.constants[image_address] = true
	image_set := api.message(cls, c'characterSetWithCharactersInString:', image_address, 0)
	ios_runtime.constants.delete(image_address)
	unsafe { image_text.free() }
	assert api.member(image_set, 0xe9) && api.member(image_set, 0x4e2d)
	mut guarded := [u64(0x1122334455667788), 0, 0x8877665544332211]!
	caller := u64(unsafe { &guarded[1] })
	assert objc_construct_instance(mutable_cls, caller) == caller
	assert api.message(caller, c'init', 0, 0) == caller
	api.message(caller, c'addCharactersInString:', api.string('caller中'), 0)
	assert api.member(caller, 0x4e2d)
	objc_set_class(caller, api.cls('NSObject'))
	assert objc_destruct_instance(caller) == caller
	assert caller !in ios_runtime.objects && guarded[0] == 0x1122334455667788 && guarded[2] == 0x8877665544332211
	for _ in 0 .. 32 {
		object := api.retain(api.set('owned中', true))
		objc_set_class(object, api.cls('NSObject'))
		api.release(object)
	}
	character_set_fixture_hook(cls)
	character_set_fixture_hook(mutable_cls)
	input := owned_string('before constructor é中')
	objc_store_weak(unsafe { &character_set_fixture_weak_input }, input)
	character_set_fixture_input = input
	character_set_fixture_mode = 'release-input'
	character_set_fixture_fired = false
	snapshot := api.message(cls, c'characterSetWithCharactersInString:', input, 0)
	character_set_fixture_mode = ''
	character_set_fixture_input = 0
	assert character_set_fixture_fired && character_set_fixture_weak_input == 0 && api.member(snapshot, 0xe9) && api.member(snapshot, 0x4e2d)
	objc_destroy_weak(unsafe { &character_set_fixture_weak_input })
	for operation in [c'copy', c'mutableCopy', c'invertedSet']! {
		// Drain the factory's autorelease before the callback drops the last ref.
		inner := api.pool()
		source := api.retain(api.set('a中', true))
		api.drain(inner)
		objc_store_weak(unsafe { &character_set_fixture_weak_source }, source)
		character_set_fixture_source = source
		character_set_fixture_mode = 'release-source'
		character_set_fixture_fired = false
		result := api.message(source, operation, 0, 0)
		character_set_fixture_mode = ''
		character_set_fixture_source = 0
		assert character_set_fixture_fired && character_set_fixture_weak_source == 0
		assert api.member(result, 97) == (operation != c'invertedSet') && api.member(result, 0x1f600) == (operation == c'invertedSet')
		if operation != c'invertedSet' { api.release(result) }
		objc_destroy_weak(unsafe { &character_set_fixture_weak_source })
	}
	// Failed constructors retire sidecars, weak references and user properties.
	valid := api.retain(api.set('rollback中', true))
	input2 := owned_string('input')
	for operation in 0 .. 3 {
		before := ios_runtime.objects.len
		character_set_fixture_mode = 'fail'
		character_set_fixture_fired = false
		result := if operation == 0 {
			api.message(cls, c'characterSetWithCharactersInString:', input2, 0)
		} else if operation == 1 {
			api.message(valid, c'copy', 0, 0)
		} else {
			objc_construct_instance(mutable_cls, caller)
		}
		character_set_fixture_mode = ''
		assert result == 0 && character_set_fixture_fired && character_set_fixture_weak_result == 0 && character_set_fixture_weak_property == 0
		objc_destroy_weak(unsafe { &character_set_fixture_weak_result })
		objc_destroy_weak(unsafe { &character_set_fixture_weak_property })
		assert ios_runtime.objects.len == before && guarded[0] == 0x1122334455667788 && guarded[2] == 0x8877665544332211
	}
	api.release(valid)
	api.release(input2)
	api.drain(pool)
}

fn test_character_set_runtime() {
	for _ in 0 .. 2 {
		character_set_fixture_mode = ''
		character_set_fixture_input = 0
		character_set_fixture_source = 0
		objc_start()
		api := character_set_runtime_api()
		character_set_fixture_shared(api)
		character_set_fixture_runtime_lifetimes(api)
		assert ios_runtime.objects.len == 0 && ios_runtime.live == 0 && ios_runtime.weak.len == 0
		objc_stop()
		assert ios_runtime.objects.len == 0 && ios_runtime.live == 0
	}
	println('IOS-CHARACTER-SET: metadata, BMP/NUL strings, 65536-byte inputs, full-plane native bitmap hashes, copy/invert/union isolation, joined-worker constructors, rollback, guarded caller storage, 32 isa disposal paths and two drained runtimes')
}

fn test_character_set_rejections() {
	objc_start()
	api := character_set_runtime_api()
	cls := api.cls('NSCharacterSet')
	mutable_cls := api.cls('NSMutableCharacterSet')
	for selector in [c'initWithCharactersInString:', c'characterSetWithRange:', c'bitmapRepresentation',
		c'encodeWithCoder:', c'formIntersectionWithCharacterSet:', c'hash', c'description']! {
		assert !objc_responds(cls, selector)
	}
	modes := ['raw-member', 'repeat-init', 'subclass', 'caller-subclass', 'spoof', 'isa-change',
		'copy-provenance', 'string-nil', 'string-type', 'string-class', 'string-custom', 'string-spoof',
		'string-isa', 'string-raw', 'string-utf8', 'string-limit', 'string-supplementary', 'add-nil',
		'remove-nil', 'add-supplementary', 'immutable-add', 'url-mutable-add', 'union-nil', 'union-type',
		'union-raw', 'union-isa', 'superset-isa', 'union-tombstone', 'state-missing',
		'state-uninitialized', 'outdomain', 'nonzero-zone', 'unsupported-range',
		'unsupported-intersection', 'unsupported-coding', 'unsupported-hash', 'constructor-isa',
		'constructor-storage']!
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
			object := api.set('a', true)
			character_set_fixture_mode = ''
			character_set_fixture_fired = false
			match mode {
				'raw-member' { api.member(objc_allocate(cls), 97) }
				'repeat-init' { api.message(object, c'init', 0, 0) }
				'subclass', 'caller-subclass' {
					custom := objc_allocate_class(cls, c'VinixUnsupportedCharacterSet', 0)
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
					api.member(wrong, 97)
				}
				'isa-change' {
					objc_set_class(object, api.cls('NSObject'))
					api.member(object, 97)
				}
				'copy-provenance' {
					objc_set_class(object, api.cls('NSURLRequest'))
					objc_copy_value(object, false)
				}
				'string-nil', 'string-type', 'string-class' {
					input := if mode == 'string-nil' {
						u64(0)
					} else if mode == 'string-class' {
						api.cls('NSString')
					} else {
						objc_new(api.cls('NSObject'))
					}
					api.message(cls, c'characterSetWithCharactersInString:', input, 0)
				}
				'string-custom', 'string-spoof', 'string-isa', 'string-raw', 'string-utf8' {
					mut input := if mode == 'string-raw' {
						objc_allocate(api.cls('NSMutableString'))
					} else {
						owned_string('input')
					}
					if mode == 'string-custom' {
						custom := objc_allocate_class(api.cls('NSString'), c'VinixUnsupportedCharacterString', 0)
						objc_register_class(custom)
						objc_set_class(input, custom)
					}
					if mode == 'string-spoof' {
						objc_release(input)
						input = objc_new(api.cls('NSObject'))
						objc_set_class(input, api.cls('NSString'))
					}
					if mode == 'string-isa' { objc_set_class(input, api.cls('NSMutableString')) }
					if mode == 'string-utf8' { unsafe { obj_header(input).text[0] = char(0xff) } }
					api.message(cls, c'characterSetWithCharactersInString:', input, 0)
				}
				'string-limit', 'string-supplementary' {
					api.message(cls, c'characterSetWithCharactersInString:', api.string(if mode == 'string-limit' {
						'x'.repeat(65537)
					} else {
						'A😀'
					}), 0)
				}
				'add-nil', 'remove-nil', 'add-supplementary' {
					api.message(object, if mode == 'remove-nil' {
						c'removeCharactersInString:'
					} else {
						c'addCharactersInString:'
					}, if mode == 'add-supplementary' { api.string('A😀') } else { u64(0) }, 0)
				}
				'immutable-add', 'url-mutable-add' {
					immutable := if mode == 'immutable-add' {
						api.set('a', false)
					} else {
						api.message(mutable_cls, c'URLQueryAllowedCharacterSet', 0, 0)
					}
					api.message(immutable, c'addCharactersInString:', api.string('b'), 0)
				}
				'union-nil', 'union-type', 'union-raw', 'union-isa', 'superset-isa',
				'union-tombstone' {
					mut other := if mode == 'union-nil' {
						u64(0)
					} else if mode == 'union-type' {
						objc_new(api.cls('NSObject'))
					} else if mode == 'union-raw' {
						objc_allocate(cls)
					} else {
						api.set('b', false)
					}
					if mode in ['union-isa', 'superset-isa']! {
						objc_set_class(other, api.cls('NSObject'))
					}
					mut storage := [1]u64{}
					if mode == 'union-tombstone' {
						other = objc_construct_instance(cls, u64(unsafe { &storage[0] }))
						api.message(other, c'init', 0, 0)
						objc_destruct_instance(other)
					}
					api.message(object, if mode == 'superset-isa' {
						c'isSupersetOfSet:'
					} else {
						c'formUnionWithCharacterSet:'
					}, other, 0)
				}
				'state-missing' {
					obj_header(object).character_set.bits = unsafe { nil }
					api.member(object, 97)
				}
				'state-uninitialized' {
					obj_header(object).character_set.initialized = false
					api.member(object, 97)
				}
				'outdomain' { api.member(object, 0x110000) }
				'nonzero-zone' { api.message(object, c'copyWithZone:', 1, 0) }
				'unsupported-range', 'unsupported-intersection', 'unsupported-coding',
				'unsupported-hash' {
					selector := match mode {
						'unsupported-range' { c'addCharactersInRange:' }
						'unsupported-intersection' { c'formIntersectionWithCharacterSet:' }
						'unsupported-coding' { c'encodeWithCoder:' }
						else { c'hash' }
					}
					api.message(object, selector, object, 0)
				}
				'constructor-isa', 'constructor-storage' {
					character_set_fixture_hook(cls)
					character_set_fixture_mode = mode
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
	println('IOS-CHARACTER-SET-REJECT:' + modes.len.str() + ' raw/reinitialized/custom/spoof/isa storage, invalid strings/BMP domain/limits, immutable mutation, malformed union/superset inputs, unsupported options and constructor changes fail explicitly')
}

fn test_character_set_native() {
	$if macos {
		api := CharacterSetFixtureApi{true, u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend'))}
		assert api.send != 0
		character_set_fixture_shared(api)
		println('IOS-CHARACTER-SET-NATIVE: public metadata, empty defaults, BMP/NUL membership, 65536-byte input, eight predefined full-plane samples, copy/invert/union isolation and retained lifetimes')
	}
}

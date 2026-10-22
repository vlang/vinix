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

type MutableStringMessage = fn (u64, u64, u64, u64, u64) u64
struct MutableStringRange { location u64 length u64 }
type MutableStringReplace = fn (u64, u64, MutableStringRange, u64)
type MutableStringDelete = fn (u64, u64, MutableStringRange)
struct MutableStringApi { native bool send u64 strings u64 mutable_strings u64 }
fn (api MutableStringApi) selector(name &char) u64 {
	$if macos { if api.native { return u64(C.sel_registerName(name)) } }
	return objc_selector(name)
}
fn (api MutableStringApi) message(object u64, name &char, a u64, b u64, c u64) u64 {
	return unsafe { MutableStringMessage(voidptr(api.send))(object, api.selector(name), a, b, c) }
}
fn (api MutableStringApi) string(value string) u64 {
	return api.message(api.message(api.strings, c'alloc', 0, 0, 0), c'initWithBytes:length:encoding:', u64(value.str), u64(value.len), 4)
}
fn (api MutableStringApi) mutable(value string) u64 {
	return api.message(api.message(api.mutable_strings, c'alloc', 0, 0, 0), c'initWithBytes:length:encoding:', u64(value.str), u64(value.len), 4)
}
fn (api MutableStringApi) text(object u64) string {
	assert object != 0
	length := api.message(object, c'lengthOfBytesUsingEncoding:', 4, 0, 0)
	bytes := api.message(object, c'UTF8String', 0, 0, 0); assert bytes != 0
	return if length == 0 { '' } else { unsafe { tos(&u8(voidptr(bytes)), int(length)) } }
}
fn (api MutableStringApi) expect(object u64, text string, utf16_length u64) {
	assert api.text(object) == text
	assert api.message(object, c'length', 0, 0, 0) == utf16_length
}
fn (api MutableStringApi) release(object u64) { api.message(object, c'release', 0, 0, 0) }
fn (api MutableStringApi) pool() u64 {
	$if macos { if api.native { return api.message(u64(C.objc_getClass(c'NSAutoreleasePool')), c'new', 0, 0, 0) } }
	return objc_pool_push()
}
fn (api MutableStringApi) drain(pool u64) {
	$if macos { if api.native { api.message(pool, c'drain', 0, 0, 0); return } }
	objc_pool_pop(pool)
}
fn (api MutableStringApi) replace(object u64, range MutableStringRange, replacement u64) {
	unsafe { MutableStringReplace(voidptr(api.send))(object, api.selector(c'replaceCharactersInRange:withString:'), range, replacement) }
}
fn (api MutableStringApi) delete(object u64, range MutableStringRange) {
	unsafe { MutableStringDelete(voidptr(api.send))(object, api.selector(c'deleteCharactersInRange:'), range) }
}

// The same constructors and mutations run against Apple Foundation and Vinix.
fn mutstr_shared_construction(api MutableStringApi) {
	pool := api.pool()
	for construction in [c'new', c'alloc']! {
		object := api.message(api.mutable_strings, construction, 0, 0, 0)
		initialized := if construction == c'alloc' { api.message(object, c'init', 0, 0, 0) } else { object }
		api.expect(initialized, '', 0); api.release(initialized)
	}
	for capacity in [u64(0), 17, 4096]! {
		object := api.message(api.message(api.mutable_strings, c'alloc', 0, 0, 0), c'initWithCapacity:', capacity, 0, 0)
		api.expect(object, '', 0); api.release(object)
		api.expect(api.message(api.mutable_strings, c'stringWithCapacity:', capacity, 0, 0), '', 0)
	}
	for value in ['', 'ASCII', 'é😀', 'a\x00' + 'b']! {
		source := api.mutable(value)
		for factory in [false, true]! {
			allocated := if factory { api.mutable_strings } else { api.message(api.mutable_strings, c'alloc', 0, 0, 0) }
			selector := if factory { c'stringWithString:' } else { c'initWithString:' }
			object := api.message(allocated, selector, source, 0, 0)
			assert object != source && api.text(object) == value
			if !factory { api.release(object) }
		}
		api.release(source)
		for factory in [false, true]! {
			allocated := if factory { api.mutable_strings } else { api.message(api.mutable_strings, c'alloc', 0, 0, 0) }
			selector := if factory { c'stringWithUTF8String:' } else { c'initWithUTF8String:' }
			object := api.message(allocated, selector, u64(value.str), 0, 0)
			assert api.text(object) == value.all_before('\x00')
			if !factory { api.release(object) }
		}
	}
	mut bytes := [u8(65), 0, 66, 0]!
	object := api.message(api.message(api.mutable_strings, c'alloc', 0, 0, 0), c'initWithBytes:length:encoding:', u64(unsafe { &bytes[0] }), 3, 4)
	bytes[0] = 90; api.expect(object, 'A\x00' + 'B', 3); api.release(object)
	empty_bytes := api.message(api.message(api.mutable_strings, c'alloc', 0, 0, 0), c'initWithBytes:length:encoding:', 0, 0, 4)
	api.expect(empty_bytes, '', 0); api.release(empty_bytes)
	mut invalid := [u8(0xff), 0]!
	assert api.message(api.message(api.mutable_strings, c'alloc', 0, 0, 0), c'initWithBytes:length:encoding:', u64(unsafe { &invalid[0] }), 1, 4) == 0
	// Apple returns nil or an empty mutable object for this invalid C string,
	// depending on its allocation path. Vinix consistently returns nil.
	if !api.native {
		assert api.message(api.message(api.mutable_strings, c'alloc', 0, 0, 0), c'initWithUTF8String:', u64(unsafe { &invalid[0] }), 0, 0) == 0
	}
	ascii := api.message(api.message(api.mutable_strings, c'alloc', 0, 0, 0), c'initWithBytes:length:encoding:', u64(c'ASCII'), 5, 1)
	api.expect(ascii, 'ASCII', 5); api.release(ascii)
	api.drain(pool)
}

fn mutstr_shared_mutation(api MutableStringApi) {
	pool := api.pool(); object := api.mutable('Aé😀Z'); source := api.mutable('Q')
	api.message(object, c'appendString:', source, 0, 0); api.expect(object, 'Aé😀ZQ', 6)
	api.message(source, c'setString:', object, 0, 0); api.expect(source, 'Aé😀ZQ', 6)
	api.message(object, c'insertString:atIndex:', source, 2, 0); api.expect(object, 'AéAé😀ZQ😀ZQ', 12)
	api.delete(object, MutableStringRange{2, 6}); api.expect(object, 'Aé😀ZQ', 6)
	replacement := api.string('x\x00' + 'y')
	api.replace(object, MutableStringRange{2, 2}, replacement); api.expect(object, 'Aéx\x00' + 'yZQ', 7)
	api.replace(object, MutableStringRange{7, 0}, source); api.expect(object, 'Aéx\x00' + 'yZQAé😀ZQ', 13)
	api.delete(object, MutableStringRange{0, 13}); api.expect(object, '', 0)
	api.delete(object, MutableStringRange{0, 0}); api.replace(object, MutableStringRange{0, 0}, replacement); api.expect(object, 'x\x00' + 'y', 3)
	api.message(object, c'insertString:atIndex:', source, 0, 0); api.expect(object, 'Aé😀ZQx\x00' + 'y', 9)
	api.message(object, c'setString:', object, 0, 0); api.expect(object, 'Aé😀ZQx\x00' + 'y', 9)
	assert api.message(object, c'init', 0, 0, 0) == object; api.expect(object, 'Aé😀ZQx\x00' + 'y', 9)
	api.release(replacement); api.release(source); api.release(object)
	self := api.mutable('é😀')
	api.message(self, c'appendString:', self, 0, 0); api.expect(self, 'é😀é😀', 6)
	api.message(self, c'insertString:atIndex:', self, 1, 0); api.expect(self, 'éé😀é😀😀é😀', 12)
	api.replace(self, MutableStringRange{0, 12}, self); api.expect(self, 'éé😀é😀😀é😀', 12)
	api.delete(self, MutableStringRange{0, 12}); api.expect(self, '', 0); api.release(self)
	for text in ['', 'ordinary', 'a\x00' + 'b', 'é😀']! {
		mutable := api.mutable(text); immutable := api.string(text)
		assert api.message(mutable, c'description', 0, 0, 0) == mutable
		assert api.message(mutable, c'isEqualToString:', immutable, 0, 0) == 1
		appended := api.message(mutable, c'stringByAppendingString:', immutable, 0, 0)
		assert api.text(appended) == text + text && api.text(mutable) == text
		api.release(mutable); api.release(immutable)
	}
	api.drain(pool)
}

fn mutstr_shared_copies(api MutableStringApi) {
	for mutable_source in [false, true]! {
		pool := api.pool(); source := if mutable_source { api.mutable('é😀\x00' + 'snapshot') } else { api.string('é😀\x00' + 'snapshot') }
		mut copies := []u64{}
		for selector in [c'copy', c'copyWithZone:', c'mutableCopy', c'mutableCopyWithZone:']! {
			copy := api.message(source, selector, 0, 0, 0); assert copy != 0
			if mutable_source || selector in [c'mutableCopy', c'mutableCopyWithZone:']! { assert copy != source }
			copies << copy
		}
		if mutable_source {
			changed := api.string('changed'); api.message(source, c'setString:', changed, 0, 0); api.release(changed)
		}
		api.release(source); api.drain(pool)
		for index, copy in copies {
			api.expect(copy, 'é😀\x00' + 'snapshot', 12)
			if index >= 2 {
				change := api.string('X'); api.message(copy, c'appendString:', change, 0, 0); api.release(change)
				api.expect(copy, 'é😀\x00' + 'snapshotX', 13)
			}
			api.release(copy)
		}
		unsafe { copies.free() }
	}
}

fn test_mutable_string_native() {
	$if macos {
		api := MutableStringApi{native: true, send: u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend')), strings: u64(C.objc_getClass(c'NSString')), mutable_strings: u64(C.objc_getClass(c'NSMutableString'))}
		assert C.class_getInstanceSize(unsafe { voidptr(api.mutable_strings) }) == 8 && C.class_getSuperclass(unsafe { voidptr(api.mutable_strings) }) == unsafe { voidptr(api.strings) }
		mutstr_shared_construction(api); mutstr_shared_mutation(api); mutstr_shared_copies(api)
		println('IOS-MUTABLE-STRING-NATIVE: typed constructors, advisory capacities, copied input bytes, UTF16 mutation ranges, scalar and embedded NUL text, self mutation snapshots, immutable and mutable copies after pool drainage')
	}
}

fn mutstr_runtime_api() MutableStringApi {
	return MutableStringApi{send: u64(unsafe { voidptr(C.ios_objc_msgsend) }), strings: ios_runtime.names['NSString'], mutable_strings: ios_runtime.names['NSMutableString']}
}

__global mutstr_callback_api = MutableStringApi{}
__global mutstr_callback_source = u64(0)
__global mutstr_callback_active = bool(false)
fn mutstr_copy_change_source() {
	replacement := mutstr_callback_api.string('changed during allocation')
	mutstr_callback_api.message(mutstr_callback_source, c'setString:', replacement, 0, 0)
	mutstr_callback_api.release(replacement)
}
fn mutstr_copy_constructor(object u64, selector &char) u64 {
	if mutstr_callback_active {
		mutstr_callback_active = false
		worker := spawn mutstr_copy_change_source(); worker.wait()
	}
	return object
}
fn mutstr_copy_callback_cases(api MutableStringApi) {
	mutstr_callback_api = api
	pool := api.pool()
	for target in [api.strings, api.mutable_strings]! {
		assert objc_add_method(target, u64(c'.cxx_construct'), u64(unsafe { voidptr(mutstr_copy_constructor) }), c'@16@0:8')
		mutstr_callback_source = api.mutable('snapshot before allocation😀')
		mutstr_callback_active = true
		copy := api.message(mutstr_callback_source, if target == api.strings { c'copy' } else { c'mutableCopy' }, 0, 0, 0)
		assert !mutstr_callback_active && api.text(copy) == 'snapshot before allocation😀'
		assert api.text(mutstr_callback_source) == 'changed during allocation'
		api.release(copy); api.release(mutstr_callback_source); mutstr_callback_source = 0
		mutstr_callback_source = api.mutable('snapshot before allocation😀')
		bytes := api.message(mutstr_callback_source, c'UTF8String', 0, 0, 0)
		mutstr_callback_active = true
		factory := api.message(target, c'stringWithUTF8String:', bytes, 0, 0)
		assert !mutstr_callback_active && api.text(factory) == 'snapshot before allocation😀'
		assert api.text(mutstr_callback_source) == 'changed during allocation'
		api.release(mutstr_callback_source); mutstr_callback_source = 0
		if target == api.strings {
			mutstr_callback_source = api.mutable('snapshot before allocation😀')
			mutstr_callback_active = true
			owned := owned_string(string_text(mutstr_callback_source))
			assert !mutstr_callback_active && api.text(owned) == 'snapshot before allocation😀'
			assert api.text(mutstr_callback_source) == 'changed during allocation'
			api.release(owned); api.release(mutstr_callback_source); mutstr_callback_source = 0
		}
	}
	api.drain(pool)
	mutstr_callback_api = MutableStringApi{}
}
fn test_mutable_string_runtime() {
	for _ in 0 .. 2 {
		objc_start(); api := mutstr_runtime_api()
		library := '/System/Library/Frameworks/Foundation.framework/Foundation'
		assert runtime_symbol(library, '_OBJC_CLASS_$_NSMutableString')! == api.mutable_strings
		assert runtime_symbol(library, '_OBJC_METACLASS_$_NSMutableString')! == read64(api.mutable_strings)
		assert objc_class_size(api.mutable_strings) == 8 && objc_class_parent(api.mutable_strings) == api.strings
		for name, types in {'initWithCapacity:': '@24@0:8Q16', 'initWithString:': '@24@0:8@16', 'initWithUTF8String:': '@24@0:8r*16', 'initWithBytes:length:encoding:': '@40@0:8r^v16Q24Q32', 'copyWithZone:': '@24@0:8^{_NSZone=}16', 'mutableCopyWithZone:': '@24@0:8^{_NSZone=}16', 'setString:': 'v24@0:8@16', 'appendString:': 'v24@0:8@16', 'insertString:atIndex:': 'v32@0:8@16Q24', 'deleteCharactersInRange:': 'v32@0:8{_NSRange=QQ}16', 'replaceCharactersInRange:withString:': 'v40@0:8{_NSRange=QQ}16@32'} {
			method := objc_instance_method(api.mutable_strings, u64(name.str)); assert method != 0 && ctext(u64(objc_method_types(method))) == types
		}
		method := objc_class_method(api.mutable_strings, u64(c'stringWithCapacity:')); assert method != 0 && ctext(u64(objc_method_types(method))) == '@24@0:8Q16'
		mutstr_shared_construction(api); mutstr_shared_mutation(api); mutstr_shared_copies(api)
		mutable := api.mutable('shared ASCII'); snapshot := api.message(mutable, c'copy', 0, 0, 0)
		if _ := swift_shared_utf8_checked(12, mutable | u64(0x4000000000000000)) { assert false }
		assert objc_set_class(mutable, api.strings) == api.mutable_strings
		if _ := swift_shared_utf8_checked(12, mutable | u64(0x4000000000000000)) { assert false }
		borrowed := swift_shared_utf8_checked(12, snapshot | u64(0x4000000000000000)) or { panic(err) }
		assert borrowed.count == 12 && borrowed.address == u64(obj_header(snapshot).text)
		api.release(mutable); api.release(snapshot)
		mutstr_copy_callback_cases(api)
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
		mut guarded := [u64(0x1122334455667788), 0, 0x8877665544332211]!
		caller := objc_construct_instance(api.mutable_strings, u64(unsafe { &guarded[1] })); source := api.string('caller😀')
		assert api.message(caller, c'initWithString:', source, 0, 0) == caller; api.release(source)
		mut weak := u64(0); objc_store_weak(unsafe { &weak }, caller)
		api.expect(caller, 'caller😀', 8); assert objc_destruct_instance(caller) == caller && weak == 0
		objctext := api.mutable('reset'); objc_store_weak(unsafe { &weak }, objctext); api.release(objctext); assert weak == 0
		objc_destroy_weak(unsafe { &weak }); assert guarded[0] == 0x1122334455667788 && guarded[2] == 0x8877665544332211
		for _ in 0 .. 64 {
			object := api.mutable('isa😀'); mut isa_weak := u64(0); objc_store_weak(unsafe { &isa_weak }, object)
			assert objc_set_class(object, ios_runtime.names['NSObject']) == api.mutable_strings; api.release(object); assert isa_weak == 0; objc_destroy_weak(unsafe { &isa_weak })
		}
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
		pooled := objc_autorelease(api.mutable('shutdown')); mut final_weak := u64(0); objc_store_weak(unsafe { &final_weak }, pooled)
		objc_stop(); assert final_weak == 0 && ios_runtime.live == 0 && ios_runtime.objects.len == 0
	}
	println('IOS-MUTABLE-STRING: typed Foundation ABI, copied inputs and mutation snapshots, UTF16 scalar boundaries and embedded NUL, independent copies after pool drainage and reentrant allocation callbacks, mutable Swift shared storage rejection, guarded caller storage, weak cleanup, 64 isa replacements and two drained runtimes')
}

fn test_mutable_string_rejections() {
	objc_start(); api := mutstr_runtime_api()
	modes := ['nil-source', 'bad-source', 'nil-utf8', 'nil-bytes', 'encoding', 'high-ascii', 'range', 'range-overflow', 'insert-range', 'surrogate-insert', 'surrogate-delete', 'immutable', 'format', 'format-factory', 'replacements', 'characters', 'reinitialize', 'capacity', 'long-bytes', 'long-result', 'subclass', 'caller-subclass', 'spoof', 'uninitialized', 'cf-description']!
	for mode in modes {
		mut fds := [2]i32{}; assert C.pipe(unsafe { &fds[0] }) == 0
		pid := C.fork(); assert pid >= 0
		if pid == 0 {
			C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1])
			match mode {
				'nil-source', 'bad-source' {
					source := if mode == 'nil-source' { u64(0) } else { objc_new(ios_runtime.names['NSObject']) }
					api.message(api.mutable('a'), c'appendString:', source, 0, 0)
				}
				'nil-utf8' { api.message(api.message(api.mutable_strings, c'alloc', 0, 0, 0), c'initWithUTF8String:', 0, 0, 0) }
				'nil-bytes' { api.message(api.message(api.mutable_strings, c'alloc', 0, 0, 0), c'initWithBytes:length:encoding:', 0, 1, 4) }
				'encoding' { api.message(api.message(api.mutable_strings, c'alloc', 0, 0, 0), c'initWithBytes:length:encoding:', u64(c'a'), 1, 2) }
				'high-ascii' { mut byte := [u8(0x80)]!; api.message(api.message(api.mutable_strings, c'alloc', 0, 0, 0), c'initWithBytes:length:encoding:', u64(unsafe { &byte[0] }), 1, 1) }
				'range', 'range-overflow' { api.delete(api.mutable('a'), MutableStringRange{1, if mode == 'range' { u64(1) } else { ~u64(0) }}) }
				'insert-range' { api.message(api.mutable('a'), c'insertString:atIndex:', api.string('x'), 2, 0) }
				'surrogate-insert' { api.message(api.mutable('😀x'), c'insertString:atIndex:', api.string('x'), 1, 0) }
				'surrogate-delete' { api.delete(api.mutable('😀x'), MutableStringRange{0, 1}) }
				'immutable' { api.message(api.string('a'), c'setString:', api.string('x'), 0, 0) }
				'format' { api.message(api.mutable('a'), c'appendFormat:', api.string('%@'), 0, 0) }
				'format-factory' { api.message(api.mutable_strings, c'stringWithFormat:', api.string('%@'), 0, 0) }
				'replacements' { api.message(api.mutable('a'), c'replaceOccurrencesOfString:withString:options:range:', api.string('a'), api.string('b'), 0) }
				'characters' { api.message(api.mutable('a'), c'appendCharacters:length:', 0, 0, 0) }
				'reinitialize' { api.message(api.mutable('a'), c'initWithCapacity:', 1, 0, 0) }
				'capacity' { api.message(api.mutable_strings, c'stringWithCapacity:', 16777217, 0, 0) }
				'long-bytes' { api.message(api.message(api.mutable_strings, c'alloc', 0, 0, 0), c'initWithBytes:length:encoding:', u64(c'a'), 16777217, 4) }
				'long-result' { object := api.mutable('a'.repeat(8388609)); api.message(object, c'appendString:', object, 0, 0) }
				'subclass', 'caller-subclass' {
					subclass := objc_allocate_class(api.mutable_strings, c'VinixUnsupportedMutableString', 0); objc_register_class(subclass)
					if mode == 'subclass' { objc_allocate(subclass) } else { mut bytes := [u64(0)]!; objc_construct_instance(subclass, u64(unsafe { &bytes[0] })) }
				}
				'spoof' { object := objc_new(ios_runtime.names['NSObject']); objc_set_class(object, api.mutable_strings); api.message(object, c'length', 0, 0, 0) }
				'uninitialized' { api.message(api.message(api.mutable_strings, c'alloc', 0, 0, 0), c'appendString:', api.string('x'), 0, 0) }
				else { cf_copy_description(api.mutable('a')) }
			}
			C._exit(0)
		}
		C.close(fds[1]); mut bytes := [16384]u8{}; mut length := 0
		for { assert length < bytes.len; count := C.read(fds[0], unsafe { &bytes[length] }, usize(bytes.len - length)); if count == 0 { break }; if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }; assert count > 0; length += int(count) }
		C.close(fds[0]); mut status := i32(0); assert C.ios_waitpid(pid, &status, 0) == pid && status == 256
		output := unsafe { tos(&bytes[0], length) }
		reason := match mode {
			'nil-source' { 'mutable string source must not be nil' }
			'bad-source' { 'mutable string source requires a live UTF8 string' }
			'nil-utf8' { 'mutable string UTF8 input must not be nil' }
			'nil-bytes', 'long-bytes' { 'invalid mutable string byte input' }
			'encoding' { 'mutable string input encoding is not implemented' }
			'high-ascii' { 'mutable string non-ASCII byte input is not implemented' }
			'range', 'range-overflow', 'insert-range' { 'mutable string range is out of bounds' }
			'surrogate-insert', 'surrogate-delete' { 'mutable string range splits a surrogate pair' }
			'immutable', 'characters' { 'unimplemented Objective-C method' }
			'format', 'format-factory', 'replacements' { 'mutable string operation is outside the supported profile' }
			'reinitialize' { 'mutable string designated reinitialization is not implemented' }
			'capacity' { 'mutable string capacity exceeds the supported size' }
			'long-result' { 'mutable string exceeds the supported size' }
			'subclass', 'caller-subclass' { 'mutable string subclass construction is not implemented' }
			'spoof' { 'mutable string requires live owned storage' }
			'uninitialized' { 'mutable string mutation requires initialization' }
			else { 'mutable string CF diagnostic description is not implemented' }
		}
		assert output.contains('iOS: ' + reason) && !output.contains('AddressSanitizer') && !output.contains('runtime error:'), mode + ': ' + output
	}
	assert ios_runtime.live == 0 && ios_runtime.objects.len == 0; objc_stop()
	println('IOS-MUTABLE-STRING-REJECT: 25 nil/type/encoding/strictASCII/range/surrogate/immutable/format/replacement/characters/reinitialization/limit/subclass/spoof/initialization/CoreFoundation cases fail explicitly')
}

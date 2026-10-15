// SPDX-License-Identifier: GPL-2.0-or-later
module main

import macho
#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
type PLookup = fn (u64) u64
type PGet = fn (&char) u64
type PBool = fn (u64, u64) bool
type PDrop = fn (u64)
type PPush = fn () u64
type PMake = fn (u64, &u8, i64, u32, bool) u64
type PAllocateClass = fn (u64, &char, usize) u64
type PAddParent = fn (u64, u64)
type PSend = fn (u64, u64, u64) u64
type PProbe = fn (u64, u64, u64, &u64)
struct PApi { native bool values [9]u64 objc u64 core u64 probe u64 guard u64 }
fn p_api(native bool, probe u64, guard u64) PApi {
	mut values := [9]u64{}
	mut obj := unsafe { voidptr(nil) }
	mut core := unsafe { voidptr(nil) }
	mut foundation := unsafe { voidptr(nil) }
	$if macos { if native {
		obj = C.dlopen(c'/usr/lib/libobjc.A.dylib', 2)
		core = C.dlopen(c'/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation', 2)
		foundation = C.dlopen(c'/System/Library/Frameworks/Foundation.framework/Foundation', 2)
	} }
	for i, name in ['_NSProtocolFromString', '_objc_getProtocol', '_protocol_getName', '_protocol_isEqual', '_protocol_conformsToProtocol', '_class_conformsToProtocol', '_class_addProtocol', '_objc_retain', '_objc_release']! {
		if native { values[i] = u64(C.dlsym(if i == 0 { foundation } else { obj }, unsafe { &char(name.str + 1) })) }
		else { values[i] = runtime_symbol(if i == 0 { '/System/Library/Frameworks/Foundation.framework/Foundation' } else { '/usr/lib/libobjc.A.dylib' }, name) or { panic(err) } }
		assert values[i] != 0
	}
	return PApi{native: native, values: values, objc: u64(obj), core: u64(core), probe: probe, guard: guard}
}
fn p_make(api PApi, text string) u64 {
	if !api.native { return owned_string(text) }
	return unsafe { PMake(C.dlsym(voidptr(api.core), c'CFStringCreateWithBytes'))(0, text.str, i64(text.len), 0x08000100, false) }
}
fn p_drop(api PApi, object u64) { unsafe { PDrop(voidptr(api.values[8]))(object) } }
fn p_pool(api PApi) u64 { return if api.native { unsafe { PPush(C.dlsym(voidptr(api.objc), c'objc_autoreleasePoolPush'))() } } else { objc_pool_push() } }
fn p_pop(api PApi, pool u64) { if api.native { unsafe { PDrop(C.dlsym(voidptr(api.objc), c'objc_autoreleasePoolPop'))(pool) } } else { objc_pool_pop(pool) } }
fn p_get(api PApi, name &char) u64 { return unsafe { PGet(voidptr(api.values[1]))(name) } }
fn p_bool(api PApi, slot int, a u64, b u64) bool { return unsafe { PBool(voidptr(api.values[slot]))(a, b) } }
fn p_name(api PApi, value u64) string { return unsafe { (&char(PLookup(voidptr(api.values[2]))(value))).vstring() } }
fn p_case(api PApi, text string, expected u64) {
	input := p_make(api, text)
	assert unsafe { PLookup(voidptr(api.values[0]))(input) } == expected
	mut capture := [u64(0xcafe), 0, 0, 0, 0xbeef]!
	unsafe { PProbe(voidptr(api.probe))(api.values[0], input, api.guard, &capture[1]) }
	assert capture[0] == 0xcafe && capture[1] == expected && capture[2] == api.guard && capture[3] == 0x1234 && capture[4] == 0xbeef
	if !api.native { assert obj_header(input).refs == 1 }
	p_drop(api, input)
}
fn p_native_protocol(api PApi, name &char, parent u64) u64 {
	value := unsafe { PGet(C.dlsym(voidptr(api.objc), c'objc_allocateProtocol'))(name) }
	assert value != 0 && p_get(api, name) == 0
	if parent != 0 { unsafe { PAddParent(C.dlsym(voidptr(api.objc), c'protocol_addProtocol'))(value, parent) } }
	unsafe { PDrop(C.dlsym(voidptr(api.objc), c'objc_registerProtocol'))(value) }
	assert p_get(api, name) == value
	return value
}
fn p_class(api PApi, parent u64, name &char) u64 {
	if api.native { return unsafe { PAllocateClass(C.dlsym(voidptr(api.objc), c'objc_allocateClassPair'))(parent, name, 0) } }
	return objc_allocate_class(parent, name, 0)
}
fn p_register(api PApi, cls u64) { if api.native { unsafe { PDrop(C.dlsym(voidptr(api.objc), c'objc_registerClassPair'))(cls) } } else { objc_register_class(cls) } }
fn p_dispose(api PApi, cls u64) { if api.native { unsafe { PDrop(C.dlsym(voidptr(api.objc), c'objc_disposeClassPair'))(cls) } } else { objc_dispose_class(cls) } }
fn p_message(api PApi, object u64, protocol u64) bool {
	if api.native {
		selector := unsafe { PGet(C.dlsym(voidptr(api.objc), c'sel_registerName'))(c'conformsToProtocol:') }
		responds := unsafe { PGet(C.dlsym(voidptr(api.objc), c'sel_registerName'))(c'respondsToSelector:') }
		assert unsafe { PSend(C.dlsym(voidptr(api.objc), c'objc_msgSend'))(object, responds, selector) } != 0
		return unsafe { PSend(C.dlsym(voidptr(api.objc), c'objc_msgSend'))(object, selector, protocol) } != 0
	}
	assert objc_responds(object, c'conformsToProtocol:')
	return unsafe { PSend(voidptr(C.ios_objc_msgsend))(object, u64(c'conformsToProtocol:'), protocol) } != 0
}
fn p_shared(api PApi, parent u64, child u64, unicode u64) {
	pool := p_pool(api)
	p_case(api, 'VinixProtocolParent', parent)
	p_case(api, 'VinixProtocolChild', child)
	p_case(api, 'VinixProtocol_π_🎮', unicode)
	for name in ['', 'vinixProtocolChild', ' VinixProtocolChild', 'VinixProtocolChild ', 'VinixProtocolChild\x00tail', 'VinixProtocolChild\x00', 'UnknownVinixProtocol']! { p_case(api, name, 0) }
	assert p_name(api, child) == 'VinixProtocolChild' && p_get(api, c'VinixProtocolChild') == child
	assert p_bool(api, 3, child, child) && !p_bool(api, 3, child, parent)
	assert p_bool(api, 3, 0, 0) && !p_bool(api, 3, child, 0) && !p_bool(api, 3, 0, child)
	assert p_bool(api, 4, child, parent) && p_bool(api, 4, child, child) && !p_bool(api, 4, parent, child)
	assert !p_bool(api, 4, 0, child) && !p_bool(api, 4, child, 0)
	root := if api.native { unsafe { PGet(C.dlsym(voidptr(api.objc), c'objc_getClass'))(c'NSObject') } } else { ios_runtime.names['NSObject'] }
	cls := p_class(api, root, c'VinixProtocolFixtureClass')
	assert cls != 0 && !p_bool(api, 5, cls, child)
	assert p_bool(api, 6, cls, child) && !p_bool(api, 6, cls, child)
	p_register(api, cls)
	subclass := p_class(api, cls, c'VinixProtocolFixtureSubclass')
	p_register(api, subclass)
	assert p_bool(api, 5, cls, parent) && !p_bool(api, 5, subclass, child) && !p_bool(api, 5, root, child)
	assert p_message(api, subclass, child) && !p_message(api, root, child)
	assert !p_bool(api, 6, cls, parent) && p_bool(api, 6, subclass, child)
	object := if api.native { unsafe { PSend(C.dlsym(voidptr(api.objc), c'objc_msgSend'))(subclass, PGet(C.dlsym(voidptr(api.objc), c'sel_registerName'))(c'new'), 0) } } else { objc_new(subclass) }
	assert p_message(api, object, parent) && !p_message(api, object, unicode)
	p_drop(api, object)
	p_dispose(api, subclass)
	p_dispose(api, cls)
	assert unsafe { PLookup(voidptr(api.values[7]))(child) } == child
	p_pop(api, pool)
	assert p_name(api, child) == 'VinixProtocolChild'
	p_drop(api, child)
}
fn p_emit_descriptor(base u64, at u64, name string, name_at u64, parents u64) {
	unsafe { *(&u64(base + at + 8)) = base + name_at; *(&u64(base + at + 16)) = if parents == 0 { u64(0) } else { base + parents } }
	write32(base + at + 64, 96)
	C.memcpy(unsafe { voidptr(base + name_at) }, name.str, usize(name.len + 1))
}
fn p_image(base u64, size u64) ObjMetadata {
	return ObjMetadata{image: macho.Image{segments: [macho.Segment{name: '__DATA', address: 0x1000, filesize: size, size: size, prot: 3, sections: [macho.Section{name: '__objc_protolist', address: 0x1000, size: 24}, macho.Section{name: '__objc_protorefs', address: 0x1020, size: 24}, macho.Section{name: '__objc_classlist', address: 0x1040, size: 8}, macho.Section{name: '__objc_catlist', address: 0x1048, size: 8}]}]}, layout: macho.Layout{base: 0x1000, size: size}, base: base}
}
fn p_worker(api PApi, child u64, parent u64) {
	pool := p_pool(api)
	input := p_make(api, 'VinixProtocolChild')
	for _ in 0 .. 64 {
		assert unsafe { PLookup(voidptr(api.values[0]))(input) } == child
		assert p_get(api, c'VinixProtocolChild') == child && p_bool(api, 4, child, parent)
		assert unsafe { PLookup(voidptr(api.values[7]))(child) } == child
		p_drop(api, child)
	}
	p_drop(api, input)
	p_pop(api, pool)
}
fn p_threads(api PApi, child u64, parent u64) {
	mut workers := []thread{}
	for _ in 0 .. 8 { workers << spawn p_worker(api, child, parent) }
	workers.wait()
	unsafe { workers.free() }
}
fn p_private(api PApi, base u64, size u64) {
	C.memset(unsafe { voidptr(base) }, 0, usize(size))
	p_emit_descriptor(base, 128, 'VinixProtocolParent', 1024, 0)
	p_emit_descriptor(base, 224, 'VinixProtocolChild', 1088, 512)
	p_emit_descriptor(base, 320, 'VinixProtocol_π_🎮', 1152, 0)
	unsafe { *(&u64(base + 512)) = 1; *(&u64(base + 520)) = base + 128 }
	for i in 0 .. 3 { unsafe { *(&u64(base + u64(i * 8))) = base + 128 + u64(i * 96); *(&u64(base + 32 + u64(i * 8))) = base + 128 + u64(i * 96) } }
	m := p_image(base, size)
	// Malformed roots reject before any name or reference is published.
	write32(base + 128 + 64, 71)
	if _ := m.protocols_register() { assert false }
	assert p_get(api, c'VinixProtocolParent') == 0 && read64(base + 32) == base + 128
	write32(base + 128 + 64, 96)
	unsafe { *(&u64(base + 128 + 16)) = base + 512 }
	if _ := m.protocols_register() { assert false }
	unsafe { *(&u64(base + 128 + 16)) = 0; *(&u64(base + 512)) = 4097 }
	if _ := m.protocols_register() { assert false }
	unsafe { *(&u64(base + 512)) = 1 }
	unsafe { *(&u8(base + 1024)) = 0xff }
	if _ := m.protocols_register() { assert false }
	unsafe { *(&u8(base + 1024)) = `V`; *(&u64(base)) = base + size - 4 }
	if _ := m.protocols_register() { assert false }
	unsafe { *(&u64(base)) = base + 128 }
	assert ios_runtime.protocol_aliases.len == 0 && ios_runtime.protocols.len == 6
	// Exercise actual class_ro_t and category_t adoption fields through the
	// full image registration path, including superclass conformance.
	root := ios_runtime.names['NSObject']
	root_info := ios_runtime.classes[root] or { panic('missing fixture root') }
	root_size := root_info.size
	unsafe {
		*(&u64(base + 64)) = base + 704; *(&u64(base + 72)) = base + 640
		*(&u64(base + 704)) = read64(root); *(&u64(base + 712)) = root; *(&u64(base + 736)) = base + 768
		*(&u64(base + 792)) = base + 1344; *(&u64(base + 808)) = base + 560
		*(&u64(base + 560)) = 1; *(&u64(base + 568)) = base + 224
		*(&u64(base + 640)) = base + 1280; *(&u64(base + 648)) = base + 704; *(&u64(base + 672)) = base + 512
	}
	write32(base + 772, root_size); write32(base + 776, root_size)
	C.memcpy(unsafe { voidptr(base + 1344) }, c'VinixProtocolImageClass', 24)
	C.memcpy(unsafe { voidptr(base + 1280) }, c'ProtocolCategory', 17)
	objc_register_image(m.image, m.layout, base) or { panic(err) }
	parent := p_get(api, c'VinixProtocolParent')
	child := p_get(api, c'VinixProtocolChild')
	unicode := p_get(api, c'VinixProtocol_π_🎮')
	assert parent != 0 && child != 0 && unicode != 0 && read64(base + 40) == child
	assert objc_class_conforms(base + 704, child) && objc_class_conforms(base + 704, parent)
	assert objc_protocol_equal(base + 224, child) && objc_is_kind(child, ios_runtime.names['Protocol'])
	objc_register_image(m.image, m.layout, base) or { panic(err) }
	p_shared(api, parent, child, unicode)
	p_threads(api, child, parent)
	// A second descriptor for an existing name aliases the same object.
	p_emit_descriptor(base, 416, 'VinixProtocolChild', 1216, 0)
	mut seen := map[u64]u8{}
	m.protocol_validate(base + 416, 0, mut seen) or { panic(err) }
	assert m.protocol_publish(base + 416) or { panic(err) } == child
	unsafe { seen.free() }
	cls := objc_allocate_class(ios_runtime.names['NSObject'], c'VinixProtocolCategoryClass', 0)
	objc_register_class(cls)
	unsafe { *(&u64(base + 640)) = base + 1280; *(&u64(base + 648)) = cls; *(&u64(base + 672)) = base + 512 }
	C.memcpy(unsafe { voidptr(base + 1280) }, c'ProtocolCategory', 17)
	m.attach_category(base + 640) or { panic(err) }
	assert objc_class_conforms(cls, parent)
	objc_dispose_class(cls)
	// Borrow a length-delimited NSString name ending at a protected page;
	// there is deliberately no accessible C terminator after the name.
	text := 'VinixProtocolChild'
	constant := base + 2048
	C.memcpy(unsafe { voidptr(base + size - u64(text.len)) }, text.str, usize(text.len))
	unsafe { *(&u64(constant)) = ios_runtime.names['NSString']; *(&u64(constant + 16)) = base + size - u64(text.len); *(&u64(constant + 24)) = u64(text.len) }
	ios_runtime.constants[constant] = true
	assert ns_protocol_from_string_checked(constant) or { panic(err) } == child
	ios_runtime.constants.delete(constant)
	for value in [u64(1), ~u64(0)]! { if _ := ns_protocol_from_string_checked(value) { assert false } }
	long_name := 'x'.repeat(1023)
	input := p_make(api, long_name)
	assert ns_protocol_from_string_checked(input) or { panic(err) } == 0
	p_drop(api, input)
	longer := long_name + 'x'
	invalid := p_make(api, longer)
	if _ := ns_protocol_from_string_checked(invalid) { assert false }
	p_drop(api, invalid)
	unsafe { long_name.free(); longer.free() }
	assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
}
fn test_objc_protocols() {
	page := usize(C.getpagesize())
	code := C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	data := C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	assert code != voidptr(-1) && data != voidptr(-1)
	defer { assert C.munmap(code, page * 2) == 0 && C.munmap(data, page * 2) == 0 }
	for i, op in [u32(0xa9bc7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0303f3, 0xaa0003f0, 0xaa0103e0, 0xaa0203e1, 0xaa0203e8, 0xaa0203f4, 0xaa0203e3, 0xaa0203e4, 0xaa0203e5, 0xaa0203e6, 0xaa0203e7, 0xd2824695, 0xd63f0200, 0xf9000260, 0xa900d674, 0xa9425bf5, 0xa94153f3, 0xa8c47bfd, 0xd65f03c0]! { write32(u64(code) + u64(i * 4), op) }
	C.__builtin___clear_cache(code, voidptr(u64(code) + 88))
	assert C.mprotect(code, page, C.PROT_READ | C.PROT_EXEC) == 0 && C.mprotect(voidptr(u64(code) + u64(page)), page, C.PROT_NONE) == 0 && C.mprotect(voidptr(u64(data) + u64(page)), page, C.PROT_NONE) == 0
	$if macos {
		api := p_api(true, u64(code), u64(code) + u64(page))
		parent := p_native_protocol(api, c'VinixProtocolParent', 0)
		child := p_native_protocol(api, c'VinixProtocolChild', parent)
		unicode := p_native_protocol(api, c'VinixProtocol_π_🎮', 0)
		p_shared(api, parent, child, unicode)
		p_threads(api, child, parent)
		println('IOS-OBJC-PROTOCOL-NATIVE: registered names, nil/case/space/NUL/Unicode lookup, guarded C ABI, stable immortal results, protocol/class/inherited/instance conformance and eight concurrent readers')
	}
	if _ := ns_protocol_from_string_checked(0) { assert false }
	for _ in 0 .. 2 {
		objc_start()
		api := p_api(false, u64(code), u64(code) + u64(page))
		p_private(api, u64(data), u64(page))
		objc_stop()
		assert ios_runtime.protocols.len == 0 && ios_runtime.protocol_names.len == 0 && ios_runtime.protocol_aliases.len == 0
		if _ := ns_protocol_from_string_checked(0) { assert false }
	}
	println('IOS-OBJC-PROTOCOL: canonical copied metadata, image roots/references/adoptions and category integration, Foundation/libobjc lookup, inherited conformance, bounded malformed metadata/name rejection, concurrent readers and two drained registries')
}

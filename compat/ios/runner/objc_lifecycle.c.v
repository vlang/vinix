// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn C.ios_objc_initialize_lock()
fn C.ios_objc_initialize_unlock()

struct ObjLoad {
	cls u64
	imp u64
}

fn objc_get_class(name &char) u64 { return ios_runtime.names[ctext(u64(name))] }

// +initialize is sent once for each class, superclass first. An inherited
// implementation is called with the subclass as self. The recursive lock
// lets an initializer send messages to itself and serializes other threads.
fn objc_initialize(cls u64) {
	if cls == 0 { return }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut info := ios_runtime.classes[cls] or { panic('iOS: initialization of an unknown class') }
	if info.meta || info.initialized || info.initializing { return }
	objc_initialize(info.parent)
	info.initializing = true
	imp := native_method(read64(cls), 'initialize')
	if imp != 0 { unsafe { ObjVoid(voidptr(imp))(cls, c'initialize') } }
	info.initializing = false
	info.initialized = true
}

fn objc_load_class(cls u64, mut visited map[u64]bool) {
	if cls == 0 || cls in visited { return }
	visited[cls] = true
	info := ios_runtime.classes[cls] or { panic('iOS: unknown load class') }
	objc_load_class(info.parent, mut visited)
	meta := ios_runtime.classes[read64(cls)] or { panic('iOS: unknown load metaclass') }
	if meta.load_imp != 0 { unsafe { ObjVoid(voidptr(meta.load_imp))(cls, c'load') } }
}

fn objc_load_image() {
	pool := objc_pool_push()
	defer { objc_pool_pop(pool) }
	mut visited := map[u64]bool{}
	defer { unsafe { visited.free() } }
	for cls in ios_runtime.load_classes { objc_load_class(cls, mut visited) }
	// Categories keep their own +load IMP even when another category overrides
	// the dispatch-table entry. +load is never inherited or sent as a message.
	for item in ios_runtime.load_categories {
		unsafe { ObjVoid(voidptr(item.imp))(item.cls, c'load') }
	}
}

fn (m ObjMetadata) attach_category(category u64) ! {
	// category_t's first six pointers are stable across the supported SDKs;
	// the newer class-property pointer is not needed for method dispatch.
	m.range(category, 48, false)!
	m.string_at(read64(category))!
	cls := read64(category + 8)
	m.register(cls, 0)!
	m.register(read64(cls), 0)!
	mut info := ios_runtime.classes[cls] or { return error('iOS: missing category class') }
	mut meta := ios_runtime.classes[read64(cls)] or { return error('iOS: missing category metaclass') }
	for name, imp in m.methods(read64(category + 16))! { info.methods[name] = imp }
	methods := m.methods(read64(category + 24))!
	if imp := methods['load'] { ios_runtime.load_categories << ObjLoad{cls, imp} }
	for name, imp in methods { meta.methods[name] = imp }
}

fn objc_construct(object u64, cls u64) u64 {
	mut chain := []u64{cap: 16}
	chain.flags |= .noslices
	defer { unsafe { chain.free() } }
	mut current := cls
	for _ in 0 .. 128 {
		if current == 0 { break }
		chain << current
		info := ios_runtime.classes[current] or { panic('iOS: unknown constructor class') }
		current = info.parent
	}
	if current != 0 { panic('iOS: cyclic constructor superclass chain') }
	for i := chain.len - 1; i >= 0; i-- {
		info := ios_runtime.classes[chain[i]] or { panic('iOS: unknown constructor class') }
		if imp := info.methods['.cxx_construct'] {
			result := unsafe { ObjInit(voidptr(imp))(object, c'.cxx_construct') }
			if result == 0 {
				// Only bases whose constructor completed may be destroyed.
				for j := i + 1; j < chain.len; j++ {
					parent := ios_runtime.classes[chain[j]] or { panic('iOS: unknown destructor class') }
					if destructor := parent.methods['.cxx_destruct'] {
						unsafe { ObjVoid(voidptr(destructor))(object, c'.cxx_destruct') }
					}
				}
				C.free(obj_header(object))
				C.ios_ref_change(unsafe { &ios_runtime.live }, -1)
				return 0
			}
			if result != object { panic('iOS: invalid Objective-C C++ constructor result') }
		}
	}
	return object
}

fn (m ObjMetadata) constant_string(object u64) ! {
	flags := read32(object + 8)
	address := read64(object + 16)
	length := read64(object + 24)
	if length > 16 * 1024 * 1024 { return error('iOS: constant string exceeds limit') }
	if flags == 0x7c8 {
		m.range(address, length + 1, false)!
		if unsafe { *(&u8(address + length)) } != 0 { return error('iOS: constant string is not terminated') }
		return
	}
	if flags != 0x7d0 { return error('iOS: unsupported constant string encoding') }
	m.range(address, (length + 1) * 2, false)!
	if unsafe { *(&u16(address + length * 2)) } != 0 { return error('iOS: constant string is not terminated') }
	mut utf8 := []u8{cap: int(length) * 3 + 1}
	utf8.flags |= .noslices
	defer { unsafe { utf8.free() } }
	mut i := u64(0)
	for i < length {
		mut code := u32(unsafe { *(&u16(address + i * 2)) })
		i++
		if code >= 0xd800 && code <= 0xdbff {
			if i == length { return error('iOS: incomplete UTF-16 surrogate pair') }
			low := u32(unsafe { *(&u16(address + i * 2)) })
			if low < 0xdc00 || low > 0xdfff { return error('iOS: invalid UTF-16 surrogate pair') }
			code = 0x10000 + ((code - 0xd800) << 10) + low - 0xdc00
			i++
		} else if code >= 0xdc00 && code <= 0xdfff { return error('iOS: unpaired UTF-16 surrogate') }
		if code < 0x80 { utf8 << u8(code) }
		else if code < 0x800 { utf8 << u8(0xc0 | code >> 6); utf8 << u8(0x80 | code & 0x3f) }
		else if code < 0x10000 {
			utf8 << u8(0xe0 | code >> 12); utf8 << u8(0x80 | (code >> 6) & 0x3f); utf8 << u8(0x80 | code & 0x3f)
		} else {
			utf8 << u8(0xf0 | code >> 18); utf8 << u8(0x80 | (code >> 12) & 0x3f)
			utf8 << u8(0x80 | (code >> 6) & 0x3f); utf8 << u8(0x80 | code & 0x3f)
		}
	}
	ios_runtime.constant_utf8[object] = utf8.bytestr()
}

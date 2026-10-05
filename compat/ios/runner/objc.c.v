// SPDX-License-Identifier: GPL-2.0-or-later
module main

import macho
import os

$if arm64 {
	#flag @VMODROOT/abi/dispatch.S
}

#include <stdlib.h>
#include "@VMODROOT/abi/dispatch.h"

fn C.calloc(usize, usize) voidptr
fn C.ios_objc_msgsend()
fn C.ios_objc_super()
fn C.ios_snprintf()
fn C.strtod(&char, &&char) f64
fn C.snprintf(&char, usize, &char, ...voidptr) int

struct AbiClass {
mut:
	isa    u64
	parent u64
	cache  [2]u64
	data   u64
}

struct ObjClass {
mut:
	name    string
	parent  u64
	size    u32
	meta    bool
	methods map[string]u64
	owned   bool
}

// The header is private to Vinix. The returned object still begins with the
// compiler's ordinary 8-byte isa and uses the Mach-O's nonfragile ivar offsets.
struct ObjHeader {
mut:
	refs        int
	text        &char = unsafe { nil }
	frame       ObjRect
	color       u32
	font_size   f64 = 17
	radius      f64
	tag         i64
	align       int
	target      u64 // UIControl targets are non-owning.
	action      u64
	fields      [8]u64
	children    [64]u64
	child_count int
}

struct ObjRect {
mut:
	x      f64
	y      f64
	width  f64
	height f64
}

struct RegisterFrame {
mut:
	x [10]u64
	q [16]u64
}

struct ObjRuntime {
mut:
	classes map[u64]&ObjClass
	names   map[string]u64
	pool    []u64
	window  u64
	screen  u64
	live    int
	trace   bool
}

__global ios_runtime = &ObjRuntime(unsafe { nil })

fn objc_start() {
	ios_runtime = &ObjRuntime{ trace: os.getenv('VINIX_IOS_TRACE') == '1' }
	ios_runtime.pool.flags |= .noslices
	for name in ['NSObject', 'NSString', 'UIColor', 'UIFont', 'CALayer', 'UIView', 'UILabel', 'UIButton',
		'UIWindow', 'UIViewController', 'UIScreen'] {
		parent := match name {
			'NSObject' { u64(0) }
			'UILabel', 'UIButton', 'UIWindow' { ios_runtime.names['UIView'] }
			else { ios_runtime.names['NSObject'] }
		}
		cls := unsafe { &AbiClass(C.calloc(2, sizeof(AbiClass))) }
		meta := u64(cls) + sizeof(AbiClass)
		unsafe {
			cls.isa = meta
			cls.parent = parent
		}
		mut metaclass := unsafe { &AbiClass(meta) }
		metaclass.isa = if parent == 0 { meta } else { read64(parent) }
		metaclass.parent = if parent == 0 { u64(cls) } else { read64(parent) }
		ios_runtime.classes[u64(cls)] = &ObjClass{ name: name, parent: parent, size: 8, owned: true }
		ios_runtime.classes[meta] = &ObjClass{ name: name, parent: metaclass.parent, size: 40, meta: true }
		ios_runtime.names[name] = u64(cls)
	}
}

fn read64(address u64) u64 { return unsafe { *(&u64(address)) } }

fn read32(address u64) u32 { return unsafe { *(&u32(address)) } }

fn write32(address u64, value u32) {
	unsafe { *(&u32(address)) = value }
}

fn ctext(address u64) string {
	if address == 0 { return '' }
	return unsafe { tos(&u8(address), int(darwin_strlen(&char(address)))) }
}

fn obj_header(object u64) &ObjHeader {
	return unsafe { &ObjHeader(object - sizeof(ObjHeader)) }
}

fn objc_allocate(cls u64) u64 {
	info := ios_runtime.classes[cls] or { panic('iOS: allocation of an unknown class') }
	memory := C.calloc(1, sizeof(ObjHeader) + usize(info.size))
	if memory == unsafe { nil } { panic('iOS: out of memory') }
	mut header := unsafe { &ObjHeader(memory) }
	header.refs = 1
	header.font_size = 17
	object := u64(memory) + sizeof(ObjHeader)
	unsafe { *(&u64(object)) = cls }
	ios_runtime.live++
	return object
}

fn objc_retain(object u64) u64 {
	if object != 0 && object !in ios_runtime.classes {
		mut header := obj_header(object)
		header.refs++
	}
	return object
}

type ObjVoid = fn (u64, &char)
type ObjInit = fn (u64, &char) u64
type ObjAction = fn (u64, &char, u64)
type ObjLaunch = fn (u64, &char, u64, u64) bool

fn native_method(cls u64, selector string) u64 {
	mut current := cls
	for _ in 0 .. 128 {
		if current == 0 { return 0 }
		info := ios_runtime.classes[current] or { panic('iOS: unknown Objective-C class') }
		if imp := info.methods[selector] { return imp }
		current = info.parent
	}
	panic('iOS: cyclic Objective-C superclass chain')
}

fn objc_release(object u64) {
	if object == 0 || object in ios_runtime.classes { return }
	mut header := obj_header(object)
	if header.refs <= 0 { panic('iOS: over-release') }
	header.refs--
	if header.refs != 0 { return }
	// Invoke each class's compiler-generated ARC destructor once, derived first.
	mut cls := read64(object)
	for _ in 0 .. 128 {
		if cls == 0 { break }
		info := ios_runtime.classes[cls] or { panic('iOS: unknown object class') }
		if imp := info.methods['.cxx_destruct'] {
			destructor := unsafe { ObjVoid(voidptr(imp)) }
			destructor(object, c'.cxx_destruct')
		}
		cls = info.parent
	}
	for field in header.fields { objc_release(field) }
	for i in 0 .. header.child_count { objc_release(header.children[i]) }
	C.free(header.text)
	C.free(header)
	ios_runtime.live--
}

fn objc_store_strong(location &u64, object u64) {
	old := unsafe { *location }
	objc_retain(object)
	unsafe { *location = object }
	objc_release(old)
}

fn objc_autorelease(object u64) u64 {
	if object != 0 { ios_runtime.pool << object }
	return object
}

fn objc_pool_push() u64 { return u64(ios_runtime.pool.len) + 1 }

fn objc_pool_pop(token u64) {
	if token == 0 || token > u64(ios_runtime.pool.len) + 1 { panic('iOS: invalid autorelease pool') }
	for ios_runtime.pool.len >= int(token) {
		object := ios_runtime.pool.pop()
		objc_release(object)
	}
}

fn objc_new(cls u64) u64 {
	object := objc_allocate(cls)
	imp := native_method(cls, 'init')
	if imp != 0 { return unsafe { ObjInit(voidptr(imp))(object, c'init') } }
	return object
}

fn objc_stop() {
	objc_release(ios_runtime.window)
	objc_release(ios_runtime.screen)
	objc_pool_pop(1)
	if ios_runtime.live != 0 {
		eprintln('iOS: ${ios_runtime.live} Objective-C objects still owned at shutdown')
	}
	for address, info in ios_runtime.classes {
		if info.owned { C.free(unsafe { voidptr(address) }) }
	}
}

@[export: 'ios_format_double']
fn format_double(destination &char, size usize, format &char, value f64) int {
	if darwin_strcmp(format, c'%.12g') != 0 {
		panic('iOS: unsupported snprintf format: ' + ctext(u64(format)))
	}
	return C.snprintf(destination, size, c'%.12g', value)
}

fn runtime_symbol(library string, symbol string) !u64 {
	if library == '/usr/lib/libSystem.B.dylib' {
		if symbol == '_strtod' { return u64(unsafe { voidptr(C.strtod) }) }
		if symbol == '_snprintf' { return u64(unsafe { voidptr(C.ios_snprintf) }) }
		return libsystem_symbol(library, symbol)
	}
	if library == '/usr/lib/libobjc.A.dylib' {
		address := match symbol {
			'_objc_msgSend' { unsafe { voidptr(C.ios_objc_msgsend) } }
			'_objc_msgSendSuper2' { unsafe { voidptr(C.ios_objc_super) } }
			'_objc_retain', '_objc_retainAutoreleasedReturnValue' {
				unsafe { voidptr(objc_retain) }
			}
			'_objc_release' { unsafe { voidptr(objc_release) } }
			'_objc_alloc' { unsafe { voidptr(objc_allocate) } }
			'_objc_opt_new' { unsafe { voidptr(objc_new) } }
			'_objc_storeStrong' { unsafe { voidptr(objc_store_strong) } }
			'_objc_autoreleasePoolPush' { unsafe { voidptr(objc_pool_push) } }
			'_objc_autoreleasePoolPop' { unsafe { voidptr(objc_pool_pop) } }
			'__objc_empty_cache' { unsafe { voidptr(ios_runtime) } } // Unused: lookup is in V.
			else { return error('iOS: Objective-C symbol is not implemented: ${symbol}') }
		}
		return u64(address)
	}
	if library !in ['/System/Library/Frameworks/Foundation.framework/Foundation',
		'/System/Library/Frameworks/UIKit.framework/UIKit'] {
		return error('iOS: library is not implemented: ${library} (${symbol})')
	}
	if symbol == '_UIApplicationMain' { return u64(unsafe { voidptr(ui_application_main) }) }
	for prefix in ['_OBJC_CLASS_$_', '_OBJC_METACLASS_$_'] {
		if symbol.starts_with(prefix) {
			cls := ios_runtime.names[symbol[prefix.len..]] or { break }
			return if prefix == '_OBJC_CLASS_$_' { cls } else { read64(cls) }
		}
	}
	return error('iOS: framework symbol is not implemented: ${symbol}')
}

// Bounds are checked against loaded segments, not just the mmap reservation.
struct ObjMetadata {
	image  macho.Image
	layout macho.Layout
	base   u64
}

fn (m ObjMetadata) range(address u64, size u64, writable bool) ! {
	if size > m.layout.size { return error('iOS: invalid Objective-C metadata range') }
	for segment in m.image.segments {
		if segment.name == '__PAGEZERO' { continue }
		start := m.base + segment.address - m.layout.base
		if address >= start && address - start <= segment.filesize
			&& size <= segment.filesize - (address - start)
			&& (!writable || segment.prot & 2 != 0) {
			return
		}
	}
	return error('iOS: Objective-C metadata lies outside a loaded segment')
}

fn (m ObjMetadata) string_at(address u64) !string {
	for length in 0 .. 1024 {
		m.range(address + u64(length), 1, false)!
		if unsafe { *(&u8(address + u64(length))) } == 0 {
			return unsafe { tos(&u8(address), length) }
		}
	}
	return error('iOS: Objective-C metadata string exceeds 1023 bytes')
}

fn (m ObjMetadata) methods(list u64) !map[string]u64 {
	mut methods := map[string]u64{}
	if list == 0 { return methods }
	m.range(list, 8, false)!
	flags := read32(list)
	stride := flags & 0xfffc
	count := read32(list + 4)
	small := flags & 0x80000000 != 0
	if count > 4096 || stride != if small { u32(12) } else { u32(24) } {
		return error('iOS: unsupported Objective-C method list')
	}
	m.range(list + 8, u64(count) * stride, false)!
	for i in 0 .. count {
		entry := list + 8 + u64(i) * stride
		mut name := u64(0)
		mut imp := u64(0)
		if small {
			name = u64(i64(entry) + i64(i32(read32(entry))))
			if flags & 0x40000000 == 0 {
				m.range(name, 8, false)!
				name = read64(name)
			}
			imp = u64(i64(entry + 8) + i64(i32(read32(entry + 8))))
		} else {
			name = read64(entry)
			imp = read64(entry + 16)
		}
		m.range(imp, 4, false)!
		mut executable := false
		for segment in m.image.segments {
			start := m.base + segment.address - m.layout.base
			if imp >= start && imp - start < segment.filesize && segment.prot & 4 != 0 {
				executable = true
			}
		}
		if !executable || imp % 4 != 0 {
			return error('iOS: method implementation is not executable')
		}
		selector := m.string_at(name)!
		if selector in ['load', 'initialize'] {
			return error('iOS: Objective-C +load/+initialize is not implemented')
		}
		methods[selector] = imp
	}
	return methods
}

fn (m ObjMetadata) register(cls u64, depth int) ! {
	if cls in ios_runtime.classes { return }
	if depth > 64 { return error('iOS: cyclic Objective-C class metadata') }
	m.range(cls, 40, false)!
	ro := read64(cls + 32) & ~u64(7)
	m.range(ro, 72, false)!
	flags := read32(ro)
	if flags & 0x40 != 0 { return error('iOS: Swift class metadata is not implemented') }
	parent := read64(cls + 8)
	if parent != 0 { m.register(parent, depth + 1)! }
	name := m.string_at(read64(ro + 24))!
	meta := flags & 1 != 0
	start := read32(ro + 4)
	mut size := read32(ro + 8)
	if size < start || size > 1024 * 1024 { return error('iOS: invalid Objective-C instance size') }
	if !meta && parent != 0 {
		parent_info := ios_runtime.classes[parent] or { return error('iOS: missing superclass') }
		parent_size := parent_info.size
		if parent_size > start {
			// Slide the compiler's exported ivar offset cells before sealing data.
			delta := (parent_size - start + 7) & ~u32(7)
			ivars := read64(ro + 48)
			if ivars != 0 {
				m.range(ivars, 8, false)!
				stride := read32(ivars)
				count := read32(ivars + 4)
				if stride != 32 || count > 4096 {
					return error('iOS: unsupported Objective-C ivar list')
				}
				m.range(ivars + 8, u64(count) * stride, false)!
				for i in 0 .. count {
					offset := read64(ivars + 8 + u64(i) * stride)
					m.range(offset, 4, true)!
					write32(offset, read32(offset) + delta)
				}
			}
			size += delta
		}
	}
	ios_runtime.classes[cls] = &ObjClass{
		name:    name
		parent:  parent
		size:    size
		meta:    meta
		methods: m.methods(read64(ro + 32))!
	}
	if !meta { ios_runtime.names[name] = cls }
}

fn objc_register_image(image macho.Image, layout macho.Layout, base u64) ! {
	m := ObjMetadata{image, layout, base}
	mut classes := []u64{}
	for segment in image.segments {
		for section in segment.sections {
			if section.name in ['__objc_catlist', '__objc_nlclslist', '__objc_nlcatlist'] && section.size != 0 {
				return error('iOS: Objective-C categories/+load are not implemented')
			}
			if section.name != '__objc_classlist' { continue }
			if section.size % 8 != 0 || section.size > 32768 {
				return error('iOS: invalid Objective-C class list')
			}
			address := base + section.address - layout.base
			m.range(address, section.size, false)!
			for offset := u64(0); offset < section.size; offset += 8 {
				classes << read64(address + offset)
			}
		}
	}
	for cls in classes { m.register(cls, 0)! }
	for cls in classes { m.register(read64(cls), 0)! }
}

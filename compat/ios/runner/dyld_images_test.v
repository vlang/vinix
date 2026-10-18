// SPDX-License-Identifier: GPL-2.0-or-later
module main

import macho
import os

#include <dlfcn.h>

fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.dlclose(voidptr) i32

$if macos {
	#include <mach-o/dyld.h>
	fn C._dyld_image_count() u32
	fn C._dyld_get_image_header(u32) voidptr
	fn C._dyld_get_image_name(u32) &char
	fn C._dyld_get_image_vmaddr_slide(u32) i64
}

type DyiCount = fn () u32
type DyiHeader = fn (u32) voidptr
type DyiName = fn (u32) &char
type DyiSlide = fn (u32) i64

struct DyiApi {
	count  DyiCount
	header DyiHeader
	name   DyiName
	slide  DyiSlide
}

struct DyiMapping {
	image  macho.Image
	layout macho.Layout
	base   u64
}

const dyi_symbols = ['__dyld_image_count', '__dyld_get_image_header', '__dyld_get_image_name',
	'__dyld_get_image_vmaddr_slide']!

fn dyi_put32(mut bytes []u8, at int, value u32) {
	for i in 0 .. 4 { bytes[at + i] = u8(value >> u32(i * 8)) }
}

fn dyi_put64(mut bytes []u8, at int, value u64) {
	for i in 0 .. 8 { bytes[at + i] = u8(value >> u32(i * 8)) }
}

fn dyi_text(mut bytes []u8, at int, text string) {
	for i, c in text { bytes[at + i] = c }
}

fn dyi_segment(mut bytes []u8, at int, name string, address u64, size u64,
	fileoff u64, filesize u64, prot u32, section bool) int {
	length := if section { 152 } else { 72 }
	dyi_put32(mut bytes, at, 0x19)
	dyi_put32(mut bytes, at + 4, u32(length))
	dyi_text(mut bytes, at + 8, name)
	dyi_put64(mut bytes, at + 24, address)
	dyi_put64(mut bytes, at + 32, size)
	dyi_put64(mut bytes, at + 40, fileoff)
	dyi_put64(mut bytes, at + 48, filesize)
	dyi_put32(mut bytes, at + 56, prot)
	dyi_put32(mut bytes, at + 60, prot)
	if section {
		dyi_put32(mut bytes, at + 64, 1)
		dyi_text(mut bytes, at + 72, '__fixture')
		dyi_text(mut bytes, at + 88, name)
		dyi_put64(mut bytes, at + 104, address + 32)
		dyi_put64(mut bytes, at + 112, 64)
		dyi_put32(mut bytes, at + 120, u32(fileoff + 32))
		dyi_put32(mut bytes, at + 124, 3)
	}
	return at + length
}

// Construct and parse real load commands, then map their file-backed segments
// between inaccessible guard pages. A lower data segment exercises headers
// away from the reservation's start; internal holes also stay inaccessible.
fn dyi_mapping(preferred u64, is_main bool, lower bool) DyiMapping {
	page := u64(C.getpagesize())
	mut bytes := []u8{len: int(page * 3)}
	defer { unsafe { bytes.free() } }
	dyi_put32(mut bytes, 0, 0xfeedfacf)
	dyi_put32(mut bytes, 4, 0x100000c)
	dyi_put32(mut bytes, 12, if is_main { u32(2) } else { u32(6) })
	dyi_put32(mut bytes, 16, u32(4 + int(is_main) + int(lower)))
	dyi_put32(mut bytes, 24, 0x85 | if is_main { u32(0x200000) } else { u32(0) })
	text := preferred + if lower { page * 2 } else { u64(0) }
	data := text + page * 2
	mut at := 32
	if is_main { at = dyi_segment(mut bytes, at, '__PAGEZERO', 0, preferred, 0, 0, 0, false) }
	if lower { at = dyi_segment(mut bytes, at, '__LOW', preferred, page, page, page, 1, false) }
	at = dyi_segment(mut bytes, at, '__TEXT', text, page, 0, page, 5, false)
	at = dyi_segment(mut bytes, at, '__DATA', data, page, page * 2, page, 1, true)
	dyi_put32(mut bytes, at, 0x32)
	dyi_put32(mut bytes, at + 4, 24)
	dyi_put32(mut bytes, at + 8, 2)
	dyi_put32(mut bytes, at + 12, 0x110000)
	dyi_put32(mut bytes, at + 16, 0x110000)
	at += 24
	if is_main {
		dyi_put32(mut bytes, at, 0x80000028)
		dyi_put32(mut bytes, at + 4, 24)
		dyi_put64(mut bytes, at + 8, 1024)
		at += 24
	} else {
		install := '@rpath/libImages.dylib'
		size := (24 + install.len + 1 + 7) & ~7
		dyi_put32(mut bytes, at, 0xd)
		dyi_put32(mut bytes, at + 4, u32(size))
		dyi_put32(mut bytes, at + 8, 24)
		dyi_put32(mut bytes, at + 16, 0x10000)
		dyi_put32(mut bytes, at + 20, 0x10000)
		dyi_text(mut bytes, at + 24, install)
		at += size
	}
	dyi_put32(mut bytes, 20, u32(at - 32))
	dyi_put32(mut bytes, 1024, 0xd65f03c0) // RET; this fixture executes no image code.
	for i in 0 .. 64 { bytes[int(page * 2) + 32 + i] = u8(i + 1) }
	image := macho.parse(bytes) or { panic(err) }
	layout := image.layout(page) or { panic(err) }
	region := C.mmap(unsafe { nil }, usize(layout.size + page * 2), C.PROT_NONE,
		C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	assert region != unsafe { voidptr(-1) }
	base := u64(region) + page
	for segment in image.segments {
		if segment.name == '__PAGEZERO' { continue }
		destination := base + segment.address - layout.base
		assert C.mprotect(unsafe { voidptr(destination) }, usize(page), C.PROT_READ | C.PROT_WRITE) == 0
		unsafe { C.memcpy(voidptr(destination), &image.data[int(segment.fileoff)], usize(segment.filesize)) }
		assert C.mprotect(unsafe { voidptr(destination) }, usize(page), C.PROT_READ) == 0
	}
	return DyiMapping{image, layout, base}
}

fn dyi_invalid(api DyiApi, count u32) {
	for index in [count, count + 1, u32(0x80000000), u32(0xffffffff)]! {
		darwin_set_errno(42)
		assert api.header(index) == unsafe { nil } && api.name(index) == unsafe { nil }
		assert api.slide(index) == 0 && unsafe { *C.ios_errno_address() } == 42
	}
}

fn dyi_reader(api DyiApi, headers [3]u64, names [3]u64, slides [3]i64) {
	for _ in 0 .. 256 {
		darwin_set_errno(42)
		assert api.count() == 3
		for i in 0 .. 3 {
			assert u64(api.header(u32(i))) == headers[i] && u64(api.name(u32(i))) == names[i]
			assert api.slide(u32(i)) == slides[i]
			assert read32(headers[i]) == 0xfeedfacf && unsafe { *(&u8(names[i])) } == `/`
		}
		assert unsafe { *C.ios_errno_address() } == 42
		dyi_invalid(api, 3)
	}
}

fn dyi_profile(api DyiApi) {
	regions := [dyi_mapping(0x100000000, true, false), dyi_mapping(0, false, true),
		dyi_mapping(0x7000000000000000, false, false)]!
	paths := ['/opt/ios/Главная.app/Fortnite', '/opt/ios/Frameworks/One.framework/One',
		'/opt/ios/Frameworks/Два.framework/Два']!
	modules_start(regions[0].image, regions[0].layout, regions[0].base, paths[0], false)
	for i in 1 .. 3 {
		region := regions[i]
		module_runtime.modules << &LoadedModule{
			image:  region.image
			layout: region.layout
			base:   region.base
			path:   paths[i].clone()
		}
		module_runtime.lookup_order << ModuleProvider{ index: i }
	}
	module_runtime.order = [2, 0, 1]
	module_lookup_builtin_add('/usr/lib/libSystem.B.dylib')
	module_lookup_builtin_add('/System/Library/Frameworks/Foundation.framework/Foundation')
	assert module_runtime.lookup_order.len == 5 && api.count() == 3
	mut headers := [3]u64{}
	mut names := [3]u64{}
	mut slides := [3]i64{}
	for i in 0 .. 3 {
		headers[i] = u64(api.header(u32(i)))
		names[i] = u64(api.name(u32(i)))
		slides[i] = api.slide(u32(i))
		assert headers[i] != 0 && names[i] != 0
		assert read32(headers[i]) == 0xfeedfacf && read32(headers[i] + 12) == if i == 0 {
			u32(2)
		} else {
			u32(6)
		}
		assert C.strcmp(unsafe { &char(names[i]) }, paths[i].str) == 0
		// Walk the returned header as Fortnite does, independently of registry
		// metadata. The reported slide relocates each command's virtual address.
		mut at := headers[i] + 32
		mut found := false
		for _ in 0 .. read32(headers[i] + 16) {
			if read32(at) == 0x19 && read64(at + 40) == 0 && read64(at + 48) >= 32 && read32(at + 60) & 1 != 0 {
				assert read64(at + 24) + u64(slides[i]) == headers[i]
				found = true
			}
			at += u64(read32(at + 4))
		}
		assert found && at == headers[i] + 32 + u64(read32(headers[i] + 20))
		mut info := DarwinDlInfo{}
		assert darwin_dladdr(headers[i] + 32, &info) == 1
		assert u64(info.base) == headers[i] && u64(info.filename) == names[i]
		mut size := u64(0xffffffffffffffff)
		section := darwin_getsectiondata(headers[i], c'__DATA', c'__fixture', &size)
		assert size == 64 && section != 0
		for j in 0 .. 64 {
			assert unsafe { *(&u8(section + u64(j))) } == u8(j + 1)
		}
		assert darwin_getsectiondata(headers[i], c'__DATA', c'__missing', &size) == 0 && size == 0
		// dlopen/dlclose of an already linked module does not change this
		// runner's process-lifetime mappings or the enumeration order.
		handle := darwin_dlopen(paths[i].str, 2)
		assert handle == u64(module_runtime.modules[i]) && darwin_dlclose(handle) == 0
		assert api.count() == 3 && u64(api.header(u32(i))) == headers[i]
	}
	assert headers[1] == regions[1].base + u64(C.getpagesize()) * 2
	assert slides[1] > 0 && slides[2] < 0
	dyi_invalid(api, 3)
	mut workers := []thread{}
	for _ in 0 .. 8 { workers << spawn dyi_reader(api, headers, names, slides) }
	workers.wait()
	unsafe { workers.free() }
	modules_stop()
	assert module_runtime == unsafe { nil } && api.count() == 0
	dyi_invalid(api, 0)
	module_image_free(regions[0].image)
	page := u64(C.getpagesize())
	for i, region in regions {
		if i == 0 {
			assert C.munmap(unsafe { voidptr(region.base) }, usize(region.layout.size)) == 0
		}
		assert C.munmap(unsafe { voidptr(region.base - page) }, usize(page)) == 0
		assert C.munmap(unsafe { voidptr(region.base + region.layout.size) }, usize(page)) == 0
	}
}

fn test_dyld_images() {
	assert module_runtime == unsafe { nil } && image_runtime == unsafe { nil }
	mut entries := [4]u64{}
	for i, symbol in dyi_symbols {
		entries[i] = runtime_symbol('/usr/lib/libSystem.B.dylib', symbol) or { panic(err) }
		assert entries[i] != 0
		for library in ['/usr/lib/libobjc.A.dylib', '/usr/lib/libz.1.dylib',
			'/System/Library/Frameworks/Foundation.framework/Foundation']! {
			if _ := runtime_symbol(library, symbol) {
				assert false
			}
		}
	}
	api := DyiApi{unsafe { DyiCount(voidptr(entries[0])) }, unsafe { DyiHeader(voidptr(entries[1])) }, unsafe { DyiName(voidptr(entries[2])) }, unsafe { DyiSlide(voidptr(entries[3])) }}
	assert api.count() == 0
	dyi_invalid(api, 0)
	for _ in 0 .. 2 { dyi_profile(api) }
	// Static import audits use address 1 without creating a Mach-O mapping.
	modules_start(macho.Image{}, macho.Layout{}, 1, '/audit-only', true)
	assert api.count() == 0
	dyi_invalid(api, 0)
	modules_stop()
	$if macos {
		handle := C.dlopen(c'/usr/lib/libSystem.B.dylib', 2)
		assert handle != unsafe { nil }
		for name in [c'_dyld_image_count', c'_dyld_get_image_header', c'_dyld_get_image_name',
			c'_dyld_get_image_vmaddr_slide']! {
			assert C.dlsym(handle, name) != unsafe { nil }
		}
		count := C._dyld_image_count()
		assert count > 0
		assert read32(u64(C._dyld_get_image_header(0)) + 12) == 2
		assert os.real_path(unsafe { C._dyld_get_image_name(0).vstring() }) == os.real_path(os.executable())
		for index in [count, count + 1, u32(0x80000000), u32(0xffffffff)]! {
			darwin_set_errno(42)
			assert C._dyld_get_image_header(index) == unsafe { nil } && C._dyld_get_image_name(index) == unsafe { nil }
			assert C._dyld_get_image_vmaddr_slide(index) == 0 && unsafe { *C.ios_errno_address() } == 42
		}
		assert C.dlclose(handle) == 0
	}
	println('IOS-DYLD-IMAGES: scoped 32-bit enumeration, real guarded mapped headers/load commands, borrowed UTF-8 paths, positive/negative 64-bit slides, upper-bound indices, dladdr/section identity, stable linked libraries, eight readers, two retired runtimes and audit placeholders excluded')
}

// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char,i32) voidptr
fn C.dlsym(voidptr,&char) voidptr
fn C.mincore(voidptr,usize,&u8) i32
type ClassContextLookup = fn (u64,u64,u64,u64) u64
type ClassArrayAccess = fn (u64,u64) SwiftAssociatedMetadata
fn array_class_relative(address u64) u64 {
	delta := i32(read32(address));return if delta == 0 { u64(0) } else { u64(i64(address) + i64(delta)) }
}
fn array_class_declaration(descriptor u64) {
	assert read32(descriptor) & 0xffff == 0xd0
	assert read32(descriptor) & 0x20000000 == 0 // No resilient ancestry.
	parent := array_class_relative(descriptor + 4)
	assert read32(parent) == 0 && unsafe { (&char(array_class_relative(parent + 8))).vstring() } == 'Swift'
	assert unsafe { (&char(array_class_relative(descriptor + 8))).vstring() } == '_ContiguousArrayStorage'
	assert read32(descriptor + 24) == 3 && read32(descriptor + 28) == 19 && read32(descriptor + 32) == 1
	assert read32(descriptor + 36) == 0 && read32(descriptor + 40) == 19
	assert read32(descriptor + 52) == 1 && read32(descriptor + 56) == 1
	assert read32(descriptor + 60) & 0xff == 0x80
	assert array_class_relative(descriptor + 20) != 0
}
fn array_class_context(lookup ClassContextLookup, access ClassArrayAccess, descriptor u64, element u64) {
	page := usize(C.getpagesize())
	base := u64(C.mmap(unsafe { nil },page * 2,C.PROT_READ | C.PROT_WRITE,C.MAP_PRIVATE | C.MAP_ANONYMOUS,-1,0))
	assert base != u64(-1);assert C.mprotect(unsafe { voidptr(base + u64(page)) },page,C.PROT_NONE) == 0
	argument := base + u64(page) - 8
	unsafe { *(&u64(argument)) = element }
	inner := access(0,element)
	outer := access(0,inner.metadata)
	for _ in 0 .. 100 {
		assert lookup(u64('x'.str),1,descriptor,argument) == element
		assert lookup(u64(c'SayxG'),5,descriptor,argument) == inner.metadata
		assert lookup(u64(c'SaySayxGG'),9,descriptor,argument) == outer.metadata
	}
	assert lookup(u64(c'Si'),2,base + u64(page),base + u64(page)) != 0
	assert C.munmap(unsafe { voidptr(base) },page * 2) == 0
}
fn array_class_reader(descriptor u64, element u64) {
	for _ in 0 .. 400 {
		assert (runtime_symbol('/usr/lib/swift/libswiftCore.dylib','_$ss23_ContiguousArrayStorageCMn') or { panic(err) }) == descriptor
		mut arguments := [element]!
		assert swift_mangled_lookup(u64('x'.str),1,descriptor,u64(unsafe { &arguments[0] })) == element
	}
}
fn array_class_invalid(descriptor u64) {
	mut argument := u64(0)
	assert swift_mangled_lookup(u64('x'.str),1,descriptor,u64(unsafe { &argument })) == 0
	assert swift_mangled_lookup(u64('x'.str),1,descriptor,0) == 0
	page := usize(C.getpagesize());guard := C.mmap(unsafe { nil },page,C.PROT_NONE,C.MAP_PRIVATE | C.MAP_ANONYMOUS,-1,0)
	assert guard != unsafe { voidptr(-1) }
	for context in [u64(1),u64(guard),descriptor + 4]! {
		if _ := swift_mangled_lookup_checked(u64('x'.str),1,context,u64(guard)) { assert false }
	}
	if _ := swift_mangled_nominal(descriptor) { assert false }
	for library in ['/usr/lib/libSystem.B.dylib','/usr/lib/swift/libswiftFoundation.dylib']! {
		assert runtime_symbol(library,'_$ss23_ContiguousArrayStorageCMn') == none
	}
	for symbol in ['$ss23_ContiguousArrayStorageCMn','_$ss23_ContiguousArrayStorageCMa','_swift_getGenericMetadata']! {
		assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib',symbol) == none
	}
	assert C.munmap(guard,page) == 0
}
fn array_class_retired(address u64) {
	$if macos {
		// macOS redacts mincore; mprotect fails on an unmapped page.
		assert C.mprotect(unsafe { voidptr(address) },usize(C.getpagesize()),C.PROT_READ) == -1
	} $else {
		mut state := u8(0)
		assert C.mincore(unsafe { voidptr(address) },usize(C.getpagesize()),&state) == -1
	}
}
fn test_swift_array_storage_nominal_declaration() {
	$if macos {
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',C.RTLD_NOW);assert core != unsafe { nil }
		descriptor := u64(C.dlsym(core,c'$ss23_ContiguousArrayStorageCMn'));assert descriptor != 0
		array_class_declaration(descriptor)
		lookup := unsafe { ClassContextLookup(C.dlsym(core,c'swift_getTypeByMangledNameInContext')) }
		access := unsafe { ClassArrayAccess(C.dlsym(core,c'$sSaMa')) }
		class_access := unsafe { ClassArrayAccess(C.dlsym(core,c'$ss23_ContiguousArrayStorageCMa')) }
		mut previous := u64(0)
		for symbol in [c'$sSiN',c'$sSSN',c'$ss4Int8VN']! {
			element := u64(C.dlsym(core,symbol));assert element != 0
			array_class_context(lookup,access,descriptor,element)
			canonical := class_access(0,element).metadata;assert canonical != 0 && canonical != previous
			for request in [u64(0),0x3f,0xff,0x100,0x1ff]! {
				response := class_access(request,element)
				assert response.metadata == canonical && response.state == 0
				assert read64(canonical + 64) == descriptor && read64(canonical + 144) == element
			}
			previous = canonical
		}
		println('IOS-ARRAY-CLASS-NATIVE: generic class descriptor name/module/bounds, one key parameter at metadata word18, three native complete specializations and bounded Element/nested Array context lookup with protected argument boundary')
	}
	for _ in 0 .. 2 {
		objc_start();baseline := ios_runtime.live
		descriptor := runtime_symbol('/usr/lib/swift/libswiftCore.dylib','_$ss23_ContiguousArrayStorageCMn') or { panic(err) }
		array_class_declaration(descriptor)
		assert descriptor == swift_array_class_descriptor() && descriptor != read64(swift_array_access(0,swift_integer_metadata()).metadata + 8)
		assert read32(descriptor) == 0xd0
		for offset in [u64(12),16,44,48]! { assert read32(descriptor + offset) == 0 }
		assert unsafe { (&char(array_class_relative(descriptor + 20))).vstring() } == 's28__ContiguousArrayStorageBaseC'
		lookup := unsafe { ClassContextLookup(voidptr(runtime_symbol('/usr/lib/swift/libswiftCore.dylib','_swift_getTypeByMangledNameInContext') or { panic(err) })) }
		access := unsafe { ClassArrayAccess(voidptr(runtime_symbol('/usr/lib/swift/libswiftCore.dylib','_$sSaMa') or { panic(err) })) }
		for element in [swift_integer_metadata(),swift_string_metadata(),swift_array_access(0,swift_integer_metadata()).metadata]! {
			array_class_context(lookup,access,descriptor,element)
			mut workers := []thread{cap: 8}
			for _ in 0 .. 8 { workers << spawn array_class_reader(descriptor,element) }
			workers.wait();unsafe { workers.free() }
		}
		array_class_invalid(descriptor)
		owner := swift_array_allocate(2,swift_integer_metadata())
		assert read64(owner.owner) == u64(&swift_array_storage_descriptor)
		assert read64(owner.owner) != descriptor
		unsafe { *(&u64(owner.bytes)) = 12;*(&u64(owner.bytes + 8)) = 34 }
		if _ := swift_object_type_checked(owner.owner) { assert false }
		swift_bridge_release(owner.owner)
		assert ios_runtime.live == baseline && ios_runtime.swift_arrays.len == 0 && ios_runtime.swift_heap.len == 0
		arena := ios_runtime.swift_array_arena
		mut pages := []u64{cap: ios_runtime.swift_array_metadata.len}
		for _, metadata in ios_runtime.swift_array_metadata { pages << metadata - 8 }
		objc_stop();assert ios_runtime.swift_array_arena == 0
		for address in pages { array_class_retired(address) }
		for offset in 0 .. 3 { array_class_retired(arena + u64(offset * C.getpagesize())) }
		unsafe { pages.free() }
	}
	println('IOS-ARRAY-CLASS: canonical sealed declaration independent of private owner headers, checked Element/nested Array substitution, eight readers, invalid/unsupported instantiation rejection and two drained/unmapped existing arenas without new lifetime')
}

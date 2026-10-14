// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
$if macos {
	#flag -framework CoreFoundation
	#include <CoreFoundation/CFString.h>
}
fn C.dlopen(&char,i32) voidptr
fn C.dlsym(voidptr,&char) voidptr
fn C.dlclose(voidptr) i32
fn C.CFStringCreateMutable(voidptr,i64) voidptr
fn C.CFStringAppendCString(voidptr,&char,u32)
fn C.CFGetRetainCount(voidptr) i64
type GutsAccess = fn (u64) SwiftAssociatedMetadata
type GutsCopy = fn (u64,u64,u64) u64
type GutsDestroy = fn (u64,u64)
type GutsGetTag = fn (u64,u32,u64) u32
type GutsStoreTag = fn (u64,u32,u32,u64)
type GutsCString = fn (&u8) SwiftStringWords
struct GutsApi {
	native bool
	metadata u64
	string_type u64
	accessor u64
}
fn guts_relative(address u64) u64 {
	delta := i32(read32(address)); return if delta == 0 {u64(0)} else {u64(i64(address) + i64(delta))}
}
fn guts_layout(api GutsApi) {
	m := api.metadata; w := read64(m - 8); d := read64(m + 8)
	assert m != api.string_type && d != read64(api.string_type + 8)
	assert read64(m) == 0x200 && read64(m + 16) == 0
	assert read64(w + 64) == 16 && read64(w + 72) == 16 && read64(w + 80) == 0x7fffffff02010007
	for i in 0 .. 11 { assert read64(w + u64(i * 8)) == read64(read64(api.string_type - 8) + u64(i * 8)) }
	assert read32(d) == 0x51 && read32(d + 20) == 1 && read32(d + 24) == 2
	assert unsafe { (&char(guts_relative(d + 8))).vstring() } == '_StringGuts'
	parent := guts_relative(d + 4)
	assert read32(parent) == 0 && read32(parent + 4) == 0 && unsafe { (&char(guts_relative(parent + 8))).vstring() } == 'Swift'
	if !api.native { assert guts_relative(d + 16) == 0 && w == read64(api.string_type - 8) }
	for entry in [api.accessor,guts_relative(d + 12)]! {
		access := unsafe { GutsAccess(voidptr(entry)) }
		for request in [u64(0),0x3f,0xff,0x100,0x1ff]! { response := access(request); assert response.metadata == m && response.state == 0 }
	}
}
fn guts_copy(api GutsApi,slot int,destination u64,source u64) u64 {
	call := unsafe { GutsCopy(voidptr(read64(read64(api.metadata - 8) + u64(slot * 8)))) }; return call(destination,source,api.metadata)
}
fn guts_destroy(api GutsApi,value u64) { call := unsafe { GutsDestroy(voidptr(read64(read64(api.metadata - 8) + 8))) }; call(value,api.metadata) }
fn guts_refs(api GutsApi,object u64,heap bool) u64 {
	if heap { return (read64(object + 8) >> 33) + 1 }
	$if macos { if api.native { return u64(C.CFGetRetainCount(voidptr(object))) } }
	return u64(obj_header(object).refs)
}
fn guts_owned(api GutsApi,text string) SwiftStringWords {
	mut object := u64(0)
	$if macos { if api.native { object = u64(C.CFStringCreateMutable(unsafe { nil },0)); assert object != 0; C.CFStringAppendCString(voidptr(object),text.str,0x08000100) } }
	if !api.native { object = owned_string(text) }
	return SwiftStringWords{first:u64(text.len),second:object | u64(0x5000000000000000)}
}
fn guts_ownership(api GutsApi,words SwiftStringWords,object u64,heap bool) {
	mut source := words; mut destination := SwiftStringWords{}; mut buffer := [u64(0),0,0xabcdefabcdefabcd]!
	s := u64(unsafe { &source }); d := u64(unsafe { &destination }); b := u64(unsafe { &buffer[0] })
	assert guts_copy(api,2,d,s) == d && destination == words
	assert guts_copy(api,0,b,d) == b && buffer[0] == words.first && buffer[1] == words.second && buffer[2] == 0xabcdefabcdefabcd
	assert guts_copy(api,3,d,d) == d && guts_copy(api,3,b,d) == b
	if object != 0 { assert guts_refs(api,object,heap) == 3 }
	guts_destroy(api,d); if object != 0 { assert guts_refs(api,object,heap) == 2 }
	mut moved := SwiftStringWords{}; p := u64(unsafe { &moved })
	assert guts_copy(api,4,p,b) == p && moved == words
	assert guts_copy(api,5,s,p) == s && source == words
	if object != 0 { assert guts_refs(api,object,heap) == 1 }; guts_destroy(api,s)
}
fn guts_enums(api GutsApi) {
	w := read64(api.metadata - 8); get := unsafe { GutsGetTag(voidptr(read64(w + 48))) }; put := unsafe { GutsStoreTag(voidptr(read64(w + 56))) }
	page := u64(C.getpagesize()); mapping := u64(C.mmap(unsafe { nil },usize(page * 3),C.PROT_NONE,C.MAP_PRIVATE | C.MAP_ANONYMOUS,-1,0)); assert mapping != u64(-1)
	assert C.mprotect(voidptr(mapping + page),usize(page),C.PROT_READ | C.PROT_WRITE) == 0
	assert get(mapping,0,api.metadata) == 0
	for cases in [u32(0),1,17,0x7fffffff,0x80000000,0xffffffff]! {
		length := if cases > 0x7fffffff {u64(17)} else {u64(16)}
		span := (length + 7) & ~u64(7); value := mapping + page * 2 - span
		for tag in [u32(0),1,17,0x7fffffff,0x80000000,0xffffffff]! {
			if tag > cases { continue }; C.memset(voidptr(value - 8),0x5a,usize(span + 8)); put(value,tag,cases,api.metadata)
			assert get(value,cases,api.metadata) == tag && read64(value - 8) == 0x5a5a5a5a5a5a5a5a
			assert read64(value) == if tag > 0x7fffffff {u64(tag - 0x80000000)} else {u64(0x5a5a5a5a5a5a5a5a)}
			assert read64(value + 8) == if tag == 0 {u64(0x5a5a5a5a5a5a5a5a)} else if tag <= 0x7fffffff {u64(tag - 1)} else {u64(0)}
			if length == 17 { assert unsafe { *(&u8(value + 16)) } == if tag > 0x7fffffff {u8(1)} else {u8(0)} }
			for i in length .. span { assert unsafe { *(&u8(value + i)) } == 0x5a }
		}
	}
	assert C.munmap(voidptr(mapping),usize(page * 3)) == 0
}
fn guts_lookup_worker() u64 {
	library := '/usr/lib/swift/libswiftCore.dylib'; mut first := u64(0)
	for _ in 0 .. 400 {
		m := runtime_symbol(library,'_$ss11_StringGutsVN') or {panic(err)}
		if first == 0 { first = m }; assert m == first
		assert runtime_symbol(library,'_$ss11_StringGutsVMn') or {panic(err)} == read64(m + 8)
		entry := runtime_symbol(library,'_$ss11_StringGutsVMa') or {panic(err)}; call := unsafe { GutsAccess(voidptr(entry)) }
		response := call(0x100); assert response.metadata == m && response.state == 0
	}
	return first
}
fn guts_arrays(api GutsApi) {
	guts_array := swift_array_access(0,api.metadata).metadata; strings := swift_array_access(0,api.string_type).metadata
	assert guts_array != strings && read64(guts_array + 16) == api.metadata
	assert swift_mangled_nominal(read64(api.metadata + 8)) or {panic(err)} == api.metadata
	mut source := guts_owned(api,'StringGuts typed tail ownership'); object := source.second & swift_address_mask
	allocation := swift_array_allocate(2,api.metadata)
	for i in 0 .. 2 { assert guts_copy(api,2,allocation.bytes + u64(i * 16),u64(unsafe { &source })) == allocation.bytes + u64(i * 16) }
	assert obj_header(object).refs == 3; swift_bridge_retain(allocation.owner); swift_bridge_release(allocation.owner)
	assert obj_header(object).refs == 3; swift_bridge_release(allocation.owner); assert obj_header(object).refs == 1
	guts_destroy(api,u64(unsafe { &source }))
}
__global guts_reentry_metadata = u64(0)
__global guts_reentry_destination = u64(0)
__global guts_reentry_word = u64(0)
__global guts_reentry_seen = false
fn guts_dealloc(_object u64,_selector &char) {
	assert read64(guts_reentry_destination + 8) == guts_reentry_word
	worker := spawn guts_lookup_worker(); assert worker.wait() == guts_reentry_metadata; guts_reentry_seen = true
}
fn guts_reentry(api GutsApi) {
	cls := objc_allocate_class(ios_runtime.names['NSString'],c'GutsAssignmentReentry',0); assert cls != 0
	assert objc_add_method(cls,objc_selector(c'dealloc'),u64(unsafe { voidptr(guts_dealloc) }),c'v16@0:8'); objc_register_class(cls)
	for slot in [3,5]! {
		mut old := guts_owned(api,'previous StringGuts owner'); mut next := guts_owned(api,'published StringGuts owner')
		assert objc_set_class(old.second & swift_address_mask,cls) != 0
		guts_reentry_metadata = api.metadata; guts_reentry_destination = u64(unsafe { &old }); guts_reentry_word = next.second; guts_reentry_seen = false
		assert guts_copy(api,slot,guts_reentry_destination,u64(unsafe { &next })) == guts_reentry_destination && guts_reentry_seen
		if slot == 3 { guts_destroy(api,u64(unsafe { &next })) }; guts_destroy(api,guts_reentry_destination)
	}
	guts_reentry_metadata = 0; guts_reentry_destination = 0; guts_reentry_word = 0; guts_reentry_seen = false
}
fn guts_suite(api GutsApi) {
	guts_layout(api); guts_enums(api)
	for text in ['', 'Fortnite', '1234567890123456', 'é 🎮', 'a\x00b']! { guts_ownership(api,swift_string_literal(text.str,i64(text.len),text.is_ascii()),0,false) }
	words := guts_owned(api,'owned StringGuts witness input'); guts_ownership(api,words,words.second & swift_address_mask,false)
}
fn test_swift_string_guts() {
	$if macos {
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',C.RTLD_NOW); assert core != unsafe { nil }
		api := GutsApi{native:true,metadata:u64(C.dlsym(core,c'$ss11_StringGutsVN')),string_type:u64(C.dlsym(core,c'$sSSN')),accessor:u64(C.dlsym(core,c'$ss11_StringGutsVMa'))}
		assert api.metadata != 0 && api.string_type != 0 && api.accessor != 0; guts_suite(api)
		ctor := unsafe { GutsCString(C.dlsym(core,c'$sSS7cStringSSSPys4Int8VG_tcfC')) }; words := ctor(c'native owned StringGuts witness storage beyond fifteen bytes')
		guts_ownership(api,words,words.second,true); assert C.dlclose(core) == 0
		println('IOS-STRING-GUTS-NATIVE: distinct 16-byte struct metadata/descriptor, zero field offset, String-equivalent eight witnesses, complete direct/relative accessors, guarded enums through UINT32_MAX and balanced native/ObjC/inline/immortal copy/take ownership')
	}
	for _ in 0 .. 2 {
		objc_start(); mut workers := []thread u64{}; for _ in 0 .. 8 { workers << spawn guts_lookup_worker() }; results := workers.wait(); m := results[0]
		for result in results { assert result == m }; unsafe { workers.free(); results.free() }
		api := GutsApi{metadata:m,string_type:swift_string_metadata(),accessor:ios_runtime.swift_metadata_arena + 192}; guts_suite(api); guts_arrays(api); guts_reentry(api)
		assert m == ios_runtime.swift_metadata_arena + u64(C.getpagesize()) + 648
		for library in ['/usr/lib/libSystem.B.dylib','/usr/lib/swift/libswiftFoundation.dylib']! { assert runtime_symbol(library,'_$ss11_StringGutsVN') == none }
		assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib','$ss11_StringGutsVN') == none
		assert ios_runtime.objects.len == 0 && ios_runtime.swift_arrays.len == 0 && ios_runtime.swift_strings.len == 0 && ios_runtime.swift_buffers.len == 0
		objc_stop(); assert ios_runtime.swift_metadata_arena == 0 && ios_runtime.swift_array_arena == 0 && ios_runtime.swift_arc_code == 0
	}
	println('IOS-STRING-GUTS: independent nominal identity in existing sealed arena, shared String ARC/witnesses, guarded enums, canonical concurrent lookup, distinct typed Array specialization/destruction, unlocked reentrant assignments and two drained/unmapped runtime lifetimes')
}

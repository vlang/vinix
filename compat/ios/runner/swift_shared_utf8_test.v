// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
$if macos {
	#flag -framework CoreFoundation
	#include <CoreFoundation/CFString.h>
}
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.CFStringCreateWithBytes(voidptr, &u8, i64, u32, bool) voidptr
fn C.CFGetRetainCount(voidptr) i64
fn C.CFRelease(voidptr)
type SharedUTF8Call = fn (u64, u64) SwiftStringBytes
type SharedUTF8Start = fn (u64, u64) u64
struct SharedUTF8Api {
	call SharedUTF8Call
	start SharedUTF8Start
}
fn shared_utf8_check(api SharedUTF8Api, first u64, second u64, address u64) {
	result := api.call(first, second)
	assert result.address == address && result.count == first & swift_count_mask
	assert api.start(first, second) == address
}
fn shared_utf8_worker(api SharedUTF8Api, first u64, second u64, address u64) {
	for _ in 0 .. 400 { shared_utf8_check(api, first, second, address) }
}
fn shared_utf8_lookup() {
	assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$ss13_StringObjectV10sharedUTF8SRys5UInt8VGvg') != none
}
fn shared_utf8_override(owner u64, selector &char, requires_nul bool) u64 {
	assert unsafe { selector.vstring() } == '_fastCStringContents:' && requires_nul
	worker := spawn shared_utf8_lookup();worker.wait()
	assert obj_header(owner).refs == 1
	return u64(obj_header(owner).text)
}
fn shared_utf8_raw(api SharedUTF8Api, native bool) {
	page := usize(C.getpagesize())
	guard := C.mmap(unsafe { nil },page,C.PROT_NONE,C.MAP_PRIVATE | C.MAP_ANONYMOUS,-1,0)
	assert guard != unsafe { voidptr(-1) }
	mut record := [6]u64{}
	owner := u64(unsafe { &record[0] })
	mut allocated := u64(0)
	mut metadata := [12]u64{}
	if !native {
		metadata[3] = 0x500;metadata[1] = u64(unsafe { voidptr(shared_utf8_lookup) })
		allocated = swift_heap_allocate(u64(unsafe { &metadata[3] }),48,7)
	}
	for count in [u64(0),1,0xffffffff,0x0000ffffffffffff]! {
		for flags in [u64(0),0x4000000000000000,0xc000000000000000]! {
			first := count | flags
			if native {
				record[2] = u64(guard);record[3] = 0
				shared_utf8_check(api,first,owner | u64(0xc000000000000000),u64(guard))
				record[3] = u64(guard)
				shared_utf8_check(api,first,owner,u64(guard))
			} else {
				unsafe { *(&u64(allocated + 24)) = u64(guard);*(&u64(allocated + 32)) = first }
				shared_utf8_check(api,first,allocated,u64(guard))
				assert read64(allocated + 8) == 3
			}
		}
	}
	if !native {
		unsafe { *(&u64(allocated + 32)) = 0 }
		if _ := swift_shared_utf8_checked(1,allocated) { assert false }
		unsafe { *(&u64(allocated + 24)) = 0 }
		if _ := swift_shared_utf8_checked(0,allocated) { assert false }
		swift_heap_deallocate_uninitialized(allocated,48,7)
		if _ := swift_shared_utf8_checked(0,allocated) { assert false }
	}
	assert C.munmap(guard,page) == 0
}
fn shared_utf8_constants(api SharedUTF8Api, native bool) {
	for text in ['', 'Fortnite', 'a\x00b', 'Constant shared UTF8 π🎮', '🎮🎮🎮🎮🎮🎮🎮🎮']! {
		mut record := [u64(0),0x7c8,u64(text.str),u64(text.len)]!
		owner := u64(unsafe { &record[0] })
		if !native { record[0] = ios_runtime.names['NSString'];ios_runtime.constants[owner] = true }
		for flags in [u64(0),0x4000000000000000,0xc000000000000000]! {
			shared_utf8_check(api,u64(text.len) | flags,owner | u64(0xc000000000000000),u64(text.str))
		}
		if !native {
			mut workers := []thread{}
			for _ in 0 .. 4 { workers << spawn shared_utf8_worker(api,u64(text.len),owner | u64(0xc000000000000000),u64(text.str)) }
			workers.wait();unsafe { workers.free() }
			if _ := swift_shared_utf8_checked(u64(text.len + 1),owner | u64(0xc000000000000000)) { assert false }
			record[1] = 0x7d0
			if _ := swift_shared_utf8_checked(u64(text.len),owner | u64(0xc000000000000000)) { assert false }
			ios_runtime.constants.delete(owner)
		}
	}
}
fn shared_utf8_cocoa(api SharedUTF8Api) {
	for text in ['', 'a\x00b', 'Fortnite shared ASCII NSString backing bytes']! {
		owner := owned_string(text);address := u64(obj_header(owner).text)
		shared_utf8_check(api,u64(text.len) | u64(0xc000000000000000),owner | u64(0x4000000000000000),address)
		mut workers := []thread{}
		for _ in 0 .. 4 { workers << spawn shared_utf8_worker(api,u64(text.len),owner | u64(0x4000000000000000),address) }
		workers.wait();unsafe { workers.free() }
		assert obj_header(owner).refs == 1 && string_text(owner) == text
		if _ := swift_shared_utf8_checked(u64(text.len + 1),owner | u64(0x4000000000000000)) { assert false }
		objc_release(owner)
		if _ := swift_shared_utf8_checked(u64(text.len),owner | u64(0x4000000000000000)) { assert false }
	}
	cls := objc_allocate_class(ios_runtime.names['NSString'],c'SharedUTF8Probe',0)
	assert cls != 0 && objc_add_method(cls,u64(c'_fastCStringContents:'),u64(unsafe { voidptr(shared_utf8_override) }),c'^c20@0:8B16')
	objc_register_class(cls)
	owner := owned_string('Shared subclass π🎮')
	assert objc_set_class(owner,cls) == ios_runtime.names['NSString']
	shared_utf8_check(api,22,owner | u64(0x4000000000000000),u64(obj_header(owner).text))
	assert obj_header(owner).refs == 1;objc_release(owner)
}
fn shared_utf8_invalid() {
	page := usize(C.getpagesize());guard := C.mmap(unsafe { nil },page,C.PROT_NONE,C.MAP_PRIVATE | C.MAP_ANONYMOUS,-1,0)
	assert guard != unsafe { voidptr(-1) }
	for owner in [u64(0),1,u64(guard)]! {
		for discriminator in [u64(0),4,12]! { if _ := swift_shared_utf8_checked(0,owner | discriminator << 60) { assert false } }
	}
	for discriminator in [u64(1),2,3,5,6,7,8,9,10,11,13,14,15]! {
		if _ := swift_shared_utf8_checked(0,u64(guard) | discriminator << 60) { assert false }
	}
	for bit in 48 .. 62 { if _ := swift_shared_utf8_checked(u64(1) << bit,u64(guard)) { assert false } }
	assert C.munmap(guard,page) == 0
	owner := owned_string('π🎮')
	if _ := swift_shared_utf8_checked(6,owner | u64(0x4000000000000000)) { assert false }
	if _ := swift_shared_utf8_checked(6,owner | u64(0xc000000000000000)) { assert false }
	if _ := swift_shared_utf8_checked(6,owner) { assert false };objc_release(owner)
	object := objc_allocate(ios_runtime.names['NSObject'])
	if _ := swift_shared_utf8_checked(0,object | u64(0x4000000000000000)) { assert false };objc_release(object)
	// Native tail, Array and raw allocations cannot be mistaken for shared owners.
	text := swift_string_storage(24,23,true)
	if _ := swift_shared_utf8_checked(23,text.second) { assert false }
	swift_bridge_release(text.second)
	mut metadata := [12]u64{};metadata[3] = 0x500;metadata[1] = u64(unsafe { voidptr(shared_utf8_lookup) })
	short := swift_heap_allocate(u64(unsafe { &metadata[3] }),32,7)
	if _ := swift_shared_utf8_checked(0,short) { assert false };swift_heap_deallocate_uninitialized(short,32,7)
	dead := swift_heap_allocate(u64(unsafe { &metadata[3] }),48,7)
	unsafe { *(&u64(dead + 8)) = 0x100000003 }
	if _ := swift_shared_utf8_checked(0,dead) { assert false }
	unsafe { *(&u64(dead + 8)) = 3 };swift_heap_deallocate_uninitialized(dead,48,7)
}
fn test_swift_shared_utf8_getter() {
	$if macos {
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',C.RTLD_NOW)
		api := SharedUTF8Api{
			call: unsafe { SharedUTF8Call(C.dlsym(core,c'$ss13_StringObjectV10sharedUTF8SRys5UInt8VGvg')) }
			start: unsafe { SharedUTF8Start(C.dlsym(core,c'$ss13_StringObjectV18getSharedUTF8StartSPys5UInt8VGyF')) }
		}
		shared_utf8_raw(api,true);shared_utf8_constants(api,true)
		for text in ['Fortnite shared ASCII NSString backing bytes','long\x00 embedded NUL ASCII backing bytes']! {
			owner := C.CFStringCreateWithBytes(unsafe { nil },text.str,i64(text.len),0x08000100,false)
			assert owner != unsafe { nil };before := C.CFGetRetainCount(owner)
			address := api.start(u64(text.len),u64(owner) | u64(0x4000000000000000))
			assert address != 0 && C.memcmp(unsafe { voidptr(address) },text.str,usize(text.len)) == 0
			shared_utf8_worker(api,u64(text.len),u64(owner) | u64(0x4000000000000000),address)
			assert C.CFGetRetainCount(owner) == before;C.CFRelease(owner)
		}
		println('IOS-SHARED-UTF8-NATIVE: getter/delegate register ABI, constant slot16/shared slot24, 48-bit masked counts and protected payload without reads, real Cocoa ASCII/NUL selector path and unchanged ownership')
	}
	if _ := swift_shared_utf8_checked(0,0) { assert false }
	for _ in 0 .. 2 {
		objc_start();baseline := ios_runtime.live
		api := SharedUTF8Api{
			call: unsafe { SharedUTF8Call(voidptr(runtime_symbol('/usr/lib/swift/libswiftCore.dylib','_$ss13_StringObjectV10sharedUTF8SRys5UInt8VGvg') or { panic(err) })) }
			start: unsafe { SharedUTF8Start(voidptr(runtime_symbol('/usr/lib/swift/libswiftCore.dylib','_$ss13_StringObjectV18getSharedUTF8StartSPys5UInt8VGyF') or { panic(err) })) }
		}
		shared_utf8_raw(api,false);shared_utf8_constants(api,false);shared_utf8_cocoa(api);shared_utf8_invalid()
		for library in ['/usr/lib/libSystem.B.dylib','/usr/lib/swift/libswiftFoundation.dylib']! {
			assert runtime_symbol(library,'_$ss13_StringObjectV10sharedUTF8SRys5UInt8VGvg') == none
		}
		assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib','$ss13_StringObjectV10sharedUTF8SRys5UInt8VGvg') == none
		assert ios_runtime.live == baseline && ios_runtime.swift_heap.len == 0 && ios_runtime.swift_strings.len == 0 && ios_runtime.swift_buffers.len == 0
		objc_stop();if _ := swift_shared_utf8_checked(0,0) { assert false }
	}
	println('IOS-SHARED-UTF8: borrowed registered constant/Cocoa/shared owners, Unicode/NUL pointer identity, 48-bit counts without payload reads, four readers, unlocked reentrant subclass callback, invalid representation/owner/type/extent/dead state rejection and two drained runtimes')
}

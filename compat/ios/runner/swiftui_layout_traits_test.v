// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char,i32)voidptr
fn C.dlsym(voidptr,&char)voidptr
fn C.dlclose(voidptr)i32
type LayoutTraitsProbe = fn (&u64,u64,&u64)

fn layout_traits_resolve() u64 {
	return runtime_symbol('/System/Library/Frameworks/SwiftUI.framework/SwiftUI','_$s7SwiftUI19UIViewRepresentablePAAE21_overrideLayoutTraits_3foryAA01_fG0Vz_0C4TypeQztF') or { panic(err) }
}

fn layout_traits_call(probe LayoutTraitsProbe, entry u64, input [7]u64) {
	mut output := [u64(0xcafe),0,0,0,0,0,0,0,0xbeef]!
	probe(unsafe { &input[0] },entry,unsafe { &output[1] })
	assert output == [u64(0xcafe),input[0],input[1],input[2],input[3],input[4],input[5],input[6],0xbeef]!
}

fn layout_traits_raw(probe LayoutTraitsProbe, entry u64, guard u64) {
	for input in [[u64(0),0,0,0,guard,u64(0x5020),0x5021]!,[guard,guard,guard,guard,guard,guard,guard]!,[~u64(0),guard,guard,guard,guard,u64(0x5020),0x5021]!,[guard,~u64(0),guard,guard,guard,~u64(0),guard]!]! {
		for _ in 0..128 { layout_traits_call(probe,entry,input) }
	}
}

fn layout_traits_reader(probe LayoutTraitsProbe, guard u64) u64 {
	entry := layout_traits_resolve()
	for _ in 0..1024 {
		assert layout_traits_resolve() == entry
		layout_traits_call(probe,entry,[guard,guard,guard,guard,guard,u64(0x5020),0x5021]!)
	}
	return entry
}

fn layout_traits_unchanged(data u64, page usize) {
	for i in u64(0)..u64(page) { assert unsafe { *(&u8(data+i)) } == 0xa5 }
}

fn layout_traits_owned(probe LayoutTraitsProbe, entry u64, guard u64, data u64, borrowed u64, page usize, cycle int) {
	baseline := ios_runtime.live
	view := objc_new(ios_runtime.names['UIView']); coordinator := objc_new(ios_runtime.names['NSObject'])
	assert view != 0 && coordinator != 0
	words := swift_interpolation_init(64,0); mut text := [words.first,words.second]!
	contents := 'borrowed layout-traits self'
	swift_string_append_bytes(u64(unsafe { &text[0] }),u64(contents.str),u64(contents.len))
	owner := text[1]&swift_address_mask
	initial_view_refs := obj_header(view).refs; initial_coordinator_refs := obj_header(coordinator).refs; initial_string_refs := read64(owner+8)
	alias := cycle&1 != 0
	if alias { assert objc_retain(view) == view && objc_retain(coordinator) == coordinator; assert swift_bridge_retain(text[1]) == text[1] }
	view_refs := obj_header(view).refs; coordinator_refs := obj_header(coordinator).refs; string_refs := read64(owner+8)
	self_span := borrowed+u64(page)-24
	assert C.mprotect(voidptr(borrowed),page,C.PROT_READ|C.PROT_WRITE) == 0
	unsafe { *(&u64(self_span)) = coordinator; *(&u64(self_span+8)) = text[0]; *(&u64(self_span+16)) = text[1] }
	assert C.mprotect(voidptr(borrowed),page,C.PROT_READ) == 0
	assert C.mprotect(voidptr(data),page,C.PROT_READ|C.PROT_WRITE) == 0
	C.memset(voidptr(data),0xa5,page)
	assert C.mprotect(voidptr(data),page,C.PROT_READ|if cycle&2 != 0 { C.PROT_WRITE } else { 0 }) == 0
	span := if cycle&4 != 0 { data+u64(page)-64 } else { data }
	layout_traits_call(probe,entry,[span,view,guard,guard,guard,self_span,guard]!)
	layout_traits_unchanged(data,page)
	assert read64(self_span) == coordinator && read64(self_span+8) == text[0] && read64(self_span+16) == text[1]
	assert obj_header(view).refs == view_refs && obj_header(coordinator).refs == coordinator_refs && read64(owner+8) == string_refs
	objc_release(view); objc_release(coordinator); swift_bridge_release(text[1])
	if alias {
		assert obj_header(view).refs == initial_view_refs && obj_header(coordinator).refs == initial_coordinator_refs && read64(owner+8) == initial_string_refs
		objc_release(view); objc_release(coordinator); swift_bridge_release(text[1])
	}
	assert ios_runtime.live == baseline && ios_runtime.swift_strings.len == 0
}

__global layout_traits_callback_calls = 0
__global layout_traits_probe_address = u64(0)
__global layout_traits_guard_address = u64(0)
fn layout_traits_callback(object u64, selector &char) {
	assert ios_runtime.swift_concurrency_retired
	layout_traits_raw(unsafe { LayoutTraitsProbe(voidptr(layout_traits_probe_address)) },layout_traits_resolve(),layout_traits_guard_address)
	layout_traits_callback_calls++
}

fn test_swiftui_layout_traits() {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil },page,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0))
	traits_base := u64(C.mmap(unsafe { nil },page*3,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0))
	borrowed := u64(C.mmap(unsafe { nil },page*2,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0))
	assert code != u64(-1) && traits_base != u64(-1) && borrowed != u64(-1)
	guard := traits_base; data := traits_base+u64(page)
	assert C.mprotect(voidptr(data),page,C.PROT_READ|C.PROT_WRITE) == 0
	C.memset(voidptr(data),0xa5,page)
	for i,op in [u32(0xa9bd7bfd),0xa90153f3,0xa9025bf5,0xaa0003f1,0xaa0103f0,0xaa0203f3,0xa9400620,0xa9410e22,0xf9401228,0xf9401634,0xf9401a35,0xd63f0200,0xa9000660,0xa9010e62,0xf9001268,0xa902d674,0xa9425bf5,0xa94153f3,0xa8c37bfd,0xd65f03c0]! { write32(code+u64(i*4),op) }
	C.__builtin___clear_cache(voidptr(code),voidptr(code+80))
	assert C.mprotect(voidptr(code),page,C.PROT_READ|C.PROT_EXEC) == 0
	probe := unsafe { LayoutTraitsProbe(voidptr(code)) }; layout_traits_probe_address = code; layout_traits_guard_address = guard
	$if macos {
		library := C.dlopen(c'/System/Library/Frameworks/SwiftUI.framework/SwiftUI',2); assert library != unsafe { nil }
		entry := u64(C.dlsym(library,c'$s7SwiftUI19NSViewRepresentablePAAE21_overrideLayoutTraits_3foryAA01_fG0Vz_0C4TypeQztF'))
		assert entry != 0 && read32(entry) == 0xd65f03c0
		layout_traits_raw(probe,entry,guard)
		for writable in [false,true]! {
			assert C.mprotect(voidptr(data),page,C.PROT_READ|if writable { C.PROT_WRITE } else { 0 }) == 0
			for span in [data,data+u64(page)-64]! {
				for _ in 0..64 { layout_traits_call(probe,entry,[span,guard,guard,guard,guard,guard,guard]!); layout_traits_unchanged(data,page) }
			}
		}
		assert C.dlclose(library) == 0
		println('NATIVE-SWIFTUI-LAYOUT-TRAITS: AppKit default is ret, read-only/writable inout boundary bytes and protected arguments/x8 untouched, x0-x3/x8/x20/x21 preserved; UIKit default was not executed natively')
	}
	entry := layout_traits_resolve(); layout_traits_raw(probe,entry,guard)
	for symbol in ['_$s7SwiftUI19UIViewRepresentablePAAE21_overrideLayoutTraits_3foryAA01_fG0Vz_0C4TypeQztFExtra','_$s7SwiftUI19NSViewRepresentablePAAE21_overrideLayoutTraits_3foryAA01_fG0Vz_0C4TypeQztF','_$s7SwiftUI19UIViewRepresentablePAAE21_overrideSizeThatFits_2in6uiViewySo6CGSizeVz_AA09_ProposedF0V0C4TypeQztF']! { if _ := swiftui_layout_traits_symbol(symbol) { assert false } }
	for _ in 0..2 {
		objc_start(); mut workers := []thread u64{}
		for _ in 0..8 { workers << spawn layout_traits_reader(probe,guard) }
		for worker in workers { assert worker.wait() == entry }; unsafe { workers.free() }
		for i in 0..300 { layout_traits_owned(probe,entry,guard,data,borrowed,page,i) }
		for library in ['/usr/lib/swift/libswiftCore.dylib','/System/Library/Frameworks/Foundation.framework/Foundation','/System/Library/Frameworks/SwiftUICore.framework/SwiftUICore']! { if _ := runtime_symbol(library,'_$s7SwiftUI19UIViewRepresentablePAAE21_overrideLayoutTraits_3foryAA01_fG0Vz_0C4TypeQztF') { assert false } }
		assert ios_runtime.swift_strings.len == 0 && ios_runtime.swift_arrays.len == 0 && ios_runtime.swift_heap.len == 0 && ios_runtime.swift_buffers.len == 0 && ios_runtime.live == 0
		cls := objc_allocate_class(ios_runtime.names['NSObject'],c'VinixLayoutTraitsCallback',0)
		assert cls != 0 && objc_add_method(cls,u64(c'dealloc'),u64(unsafe { voidptr(layout_traits_callback) }),c'v16@0:8')
		objc_register_class(cls); objc_autorelease(objc_new(cls)); before := layout_traits_callback_calls
		ios_runtime.swift_concurrency_retired = true; objc_stop()
		assert layout_traits_callback_calls == before+1 && ios_runtime.live == 0 && layout_traits_resolve() == entry
		layout_traits_raw(probe,entry,guard)
	}
	assert C.munmap(voidptr(code),page) == 0 && C.munmap(voidptr(traits_base),page*3) == 0 && C.munmap(voidptr(borrowed),page*2) == 0
	println('IOS-SWIFTUI-LAYOUT-TRAITS: empty default leaves inout traits unchanged, eight readers and 16384 concurrent calls, 600 borrowed ownership cycles with unchanged ObjC/Swift aliases, read-only/writable traits at both protected boundaries, read-only Swift self boundary and protected metadata/witness/x8, x0-x3/x8/x20/x21 preserved, exact framework routing, callbacks and two drained runtime lifetimes; custom traits, layout and graph execution remain unsupported')
}

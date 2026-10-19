// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char,i32)voidptr
fn C.dlsym(voidptr,&char)voidptr
fn C.dlclose(voidptr)i32
type SizingProbe = fn (&u64,u64,&u64)

fn sizing_resolve() u64 {
	return runtime_symbol('/System/Library/Frameworks/SwiftUI.framework/SwiftUI', '_$s7SwiftUI19UIViewRepresentablePAAE12sizeThatFits_6uiView7contextSo6CGSizeVSgAA08ProposedI4SizeV_0C4TypeQzAA0cD7ContextVyxGtF') or { panic(err) }
}

fn sizing_call(probe SizingProbe, entry u64, input [13]u64) {
	mut result := [u64(0xcafe),0,0,0,0,0,0,0,0,0,0,0,0,0,0xbeef]!
	probe(unsafe { &input[0] }, entry, unsafe { &result[1] })
	assert result[0] == 0xcafe && result[14] == 0xbeef
	assert result[1] == 0 && result[2] == 0 && result[3] == 1
	for i in 3..13 { assert result[i + 1] == input[i] }
}

fn sizing_raw(probe SizingProbe, entry u64, guard u64) {
	// Nil/finite proposals, infinities, negative zero and NaNs are ignored.
	for proposal in [[u64(0),1,0,1]!, [u64(0x405e000000000000),0,0x407c800000000000,0]!, [u64(0x7ff0000000000000),0,0x8000000000000000,0]!, [u64(0x7ff800000000abcd),0,0xfff0000000000000,1]!]! {
		for _ in 0..128 {
			sizing_call(probe,entry,[proposal[0],proposal[1],proposal[2],proposal[3],guard,guard,guard,guard,guard,u64(0x5020),0x5021,0x7ff800000000abcd,0x8000000000000000]!)
		}
	}
}

fn sizing_reader(probe SizingProbe, guard u64) u64 {
	entry := sizing_resolve()
	for _ in 0..1024 {
		assert sizing_resolve() == entry
		sizing_call(probe,entry,[u64(0),1,0,1,guard,guard,guard,guard,guard,u64(0x5020),0x5021,0x4010000000000000,0x4020000000000000]!)
	}
	return entry
}

fn sizing_owned(probe SizingProbe, entry u64, guard u64, borrowed u64, page usize, alias bool) {
	baseline := ios_runtime.live
	view := objc_new(ios_runtime.names['UIView'])
	coordinator := objc_new(ios_runtime.names['NSObject'])
	assert view != 0 && coordinator != 0
	words := swift_interpolation_init(64,0)
	mut text := [words.first,words.second]!
	contents := 'borrowed sizing context'
	swift_string_append_bytes(u64(unsafe { &text[0] }),u64(contents.str),u64(contents.len))
	owner := text[1] & swift_address_mask
	initial_view_refs := obj_header(view).refs
	initial_coordinator_refs := obj_header(coordinator).refs
	initial_string_refs := read64(owner + 8)
	if alias { assert objc_retain(view) == view && objc_retain(coordinator) == coordinator; assert swift_bridge_retain(text[1]) == text[1] }
	view_refs := obj_header(view).refs
	coordinator_refs := obj_header(coordinator).refs
	string_refs := read64(owner + 8)
	span := borrowed + u64(page) - 24
	assert C.mprotect(voidptr(borrowed),page,C.PROT_READ|C.PROT_WRITE) == 0
	unsafe { *(&u64(span)) = coordinator; *(&u64(span+8)) = text[0]; *(&u64(span+16)) = text[1] }
	assert C.mprotect(voidptr(borrowed),page,C.PROT_READ) == 0
	sizing_call(probe,entry,[u64(0x405e000000000000),0,0,1,view,span,guard,guard,guard,span,u64(0x5021),0,0]!)
	assert read64(span) == coordinator && read64(span+8) == text[0] && read64(span+16) == text[1]
	assert obj_header(view).refs == view_refs && obj_header(coordinator).refs == coordinator_refs && read64(owner+8) == string_refs
	objc_release(view); objc_release(coordinator); swift_bridge_release(text[1])
	if alias { assert obj_header(view).refs == initial_view_refs && obj_header(coordinator).refs == initial_coordinator_refs && read64(owner+8) == initial_string_refs; objc_release(view); objc_release(coordinator); swift_bridge_release(text[1]) }
	assert ios_runtime.live == baseline && ios_runtime.swift_strings.len == 0
}

__global sizing_callback_calls = 0
__global sizing_probe_address = u64(0)
__global sizing_guard_address = u64(0)
fn sizing_callback(object u64, selector &char) {
	assert ios_runtime.swift_concurrency_retired
	sizing_raw(unsafe { SizingProbe(voidptr(sizing_probe_address)) },sizing_resolve(),sizing_guard_address)
	sizing_callback_calls++
}

fn test_swiftui_sizing() {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil },page,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0))
	guard := u64(C.mmap(unsafe { nil },page,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0))
	borrowed := u64(C.mmap(unsafe { nil },page*2,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0))
	assert code != u64(-1) && guard != u64(-1) && borrowed != u64(-1)
	ops := [u32(0xa9bd7bfd),0xa90153f3,0xa9025bf5,0xaa0003f1,0xaa0103f0,0xaa0203f3,0xa9400620,0xa9410e22,0xa9421624,0xa9431e26,0xf9402228,0xf9402634,0xf9402a35,0xfd402e20,0xfd403221,0xd63f0200,0xa9000660,0xa9010e62,0xa9021664,0xa9031e66,0xf9002268,0xa904d674,0x6d058660,0xa9425bf5,0xa94153f3,0xa8c37bfd,0xd65f03c0]!
	for i,op in ops { write32(code+u64(i*4),op) }
	C.__builtin___clear_cache(voidptr(code),voidptr(code+u64(ops.len*4)))
	assert C.mprotect(voidptr(code),page,C.PROT_READ|C.PROT_EXEC) == 0
	probe := unsafe { SizingProbe(voidptr(code)) }
	sizing_probe_address = code; sizing_guard_address = guard
	$if macos {
		ui := C.dlopen(c'/System/Library/Frameworks/SwiftUI.framework/SwiftUI',2)
		assert ui != unsafe { nil }
		entry := u64(C.dlsym(ui,c'$s7SwiftUI19NSViewRepresentablePAAE12sizeThatFits_6nsView7contextSo6CGSizeVSgAA08ProposedI4SizeV_0C4TypeQzAA0cD7ContextVyxGtF'))
		assert entry != 0
		for i,op in [u32(0xd2800000),0xd2800001,0x52800022,0xd65f03c0]! { assert read32(entry+u64(i*4)) == op }
		sizing_raw(probe,entry,guard)
		assert C.dlclose(ui) == 0
		println('NATIVE-SWIFTUI-SIZING: AppKit default returns nil in x0/x1/w2, x3-x8/x20/x21/d0/d1 preserved; UIKit default was not executed natively')
	}
	entry := sizing_resolve(); sizing_raw(probe,entry,guard)
	for symbol in ['_$s7SwiftUI19UIViewRepresentablePAAE12sizeThatFits_6uiView7contextSo6CGSizeVSgAA08ProposedI4SizeV_0C4TypeQzAA0cD7ContextVyxGtFExtra','_$s7SwiftUI19NSViewRepresentablePAAE12sizeThatFits_6nsView7contextSo6CGSizeVSgAA08ProposedI4SizeV_0C4TypeQzAA0cD7ContextVyxGtF','_$s7SwiftUI29UIViewControllerRepresentablePAAE12sizeThatFits']! { if _ := swiftui_sizing_symbol(symbol) { assert false } }
	for _ in 0..2 {
		objc_start()
		mut workers := []thread u64{}
		for _ in 0..8 { workers << spawn sizing_reader(probe,guard) }
		for worker in workers { assert worker.wait() == entry }; unsafe { workers.free() }
		for i in 0..300 { sizing_owned(probe,entry,guard,borrowed,page,i&1 != 0) }
		for library in ['/usr/lib/swift/libswiftCore.dylib','/System/Library/Frameworks/Foundation.framework/Foundation','/System/Library/Frameworks/SwiftUICore.framework/SwiftUICore']! { if _ := runtime_symbol(library,'_$s7SwiftUI19UIViewRepresentablePAAE12sizeThatFits_6uiView7contextSo6CGSizeVSgAA08ProposedI4SizeV_0C4TypeQzAA0cD7ContextVyxGtF') { assert false } }
		assert ios_runtime.swift_strings.len == 0 && ios_runtime.swift_arrays.len == 0 && ios_runtime.swift_heap.len == 0 && ios_runtime.swift_buffers.len == 0 && ios_runtime.live == 0
		cls := objc_allocate_class(ios_runtime.names['NSObject'],c'VinixSizingCallback',0)
		assert cls != 0 && objc_add_method(cls,u64(c'dealloc'),u64(unsafe { voidptr(sizing_callback) }),c'v16@0:8')
		objc_register_class(cls); objc_autorelease(objc_new(cls))
		before := sizing_callback_calls; ios_runtime.swift_concurrency_retired = true; objc_stop()
		assert sizing_callback_calls == before+1 && ios_runtime.live == 0
		assert sizing_resolve() == entry; sizing_raw(probe,entry,guard)
	}
	assert C.munmap(voidptr(code),page) == 0 && C.munmap(voidptr(guard),page) == 0 && C.munmap(voidptr(borrowed),page*2) == 0
	println('IOS-SWIFTUI-SIZING: nil default in x0/x1/w2, nil/finite/infinite/NaN proposals, eight readers and 16384 concurrent calls, 600 borrowed ownership cycles with unchanged ObjC/Swift aliases, read-only context boundary and protected input/result pages, x3-x8/x20/x21/d0/d1 preserved, exact framework routing, callbacks and two drained runtime lifetimes; custom sizing, layout and graph execution remain unsupported')
}

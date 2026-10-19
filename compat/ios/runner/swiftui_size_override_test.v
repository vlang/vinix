// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char,i32)voidptr
fn C.dlsym(voidptr,&char)voidptr
fn C.dlclose(voidptr)i32
type SizeOverrideProbe = fn (&u64,u64,&u64)

fn size_override_resolve() u64 {
	return runtime_symbol('/System/Library/Frameworks/SwiftUI.framework/SwiftUI','_$s7SwiftUI19UIViewRepresentablePAAE21_overrideSizeThatFits_2in6uiViewySo6CGSizeVz_AA09_ProposedF0V0C4TypeQztF') or { panic(err) }
}

fn size_override_call(probe SizeOverrideProbe, entry u64, input [13]u64) {
	mut output := [u64(0xcafe),0,0,0,0,0,0,0,0,0,0,0,0,0,0xbeef]!
	probe(unsafe { &input[0] },entry,unsafe { &output[1] })
	assert output[0] == 0xcafe && output[14] == 0xbeef
	for i in 0..13 { assert output[i+1] == input[i] }
}

fn size_override_raw(probe SizeOverrideProbe, entry u64, guard u64) {
	proposals := [[u64(0),1,0,1]!,[u64(0x405e000000000000),0,0x407c800000000000,0]!,[u64(0x7ff0000000000000),0,0x8000000000000000,0]!,[u64(0x7ff800000000abcd),0,0xfff0000000000000,1]!]!
	for i,proposal in proposals {
		size := if i == 0 { u64(0) } else if i == 2 { ~u64(0) } else { guard }
		for _ in 0..128 {
			size_override_call(probe,entry,[size,proposal[0],proposal[1],proposal[2],proposal[3],guard,guard,guard,guard,guard,guard,u64(0x7ff800000000abcd),0x8000000000000000]!)
		}
	}
}

fn size_override_frame(probe SizeOverrideProbe, entry u64, guard u64, data u64, page usize, view u64, self_value u64, cycle int) {
	proposals := [[u64(0),1,0,1]!,[u64(0x405e000000000000),0,0x407c800000000000,0]!,[u64(0x7ff0000000000000),0,0x8000000000000000,0]!,[u64(0x7ff800000000abcd),0,0xfff0000000000000,1]!]!
	sizes := [[u64(0),0]!,[u64(0x405e000000000000),0x407c800000000000]!,[u64(0x8000000000000000),0x7ff0000000000000]!,[u64(0x7ff800000000abcd),0xfff0000000000000]!]!
	proposal := proposals[cycle&3]; size := sizes[cycle&3]
	span := if cycle&8 != 0 { data+u64(page)-16 } else { data }
	assert C.mprotect(voidptr(data),page,C.PROT_READ|C.PROT_WRITE) == 0
	C.memset(voidptr(data),0xa5,page)
	unsafe { *(&u64(span)) = size[0]; *(&u64(span+8)) = size[1] }
	assert C.mprotect(voidptr(data),page,C.PROT_READ|if cycle&4 != 0 { C.PROT_WRITE } else { 0 }) == 0
	size_override_call(probe,entry,[span,proposal[0],proposal[1],proposal[2],proposal[3],view,guard,guard,guard,self_value,guard,u64(0x7ff800000000abcd),0x8000000000000000]!)
	assert read64(span) == size[0] && read64(span+8) == size[1]
	for i in u64(0)..u64(page) {
		address := data+i
		if address >= span && address < span+16 { continue }
		assert unsafe { *(&u8(address)) } == 0xa5
	}
}

fn size_override_reader(probe SizeOverrideProbe, guard u64) u64 {
	entry := size_override_resolve()
	for _ in 0..1024 {
		assert size_override_resolve() == entry
		size_override_call(probe,entry,[guard,u64(0),1,0,1,guard,guard,guard,guard,guard,guard,u64(0x7ff800000000abcd),0x8000000000000000]!)
	}
	return entry
}

fn size_override_owned(probe SizeOverrideProbe, entry u64, guard u64, data u64, borrowed u64, page usize, cycle int) {
	baseline := ios_runtime.live
	view := objc_new(ios_runtime.names['UIView']); coordinator := objc_new(ios_runtime.names['NSObject'])
	assert view != 0 && coordinator != 0
	words := swift_interpolation_init(64,0); mut text := [words.first,words.second]!
	contents := 'borrowed size-override self'
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
	size_override_frame(probe,entry,guard,data,page,view,self_span,cycle)
	assert read64(self_span) == coordinator && read64(self_span+8) == text[0] && read64(self_span+16) == text[1]
	assert obj_header(view).refs == view_refs && obj_header(coordinator).refs == coordinator_refs && read64(owner+8) == string_refs
	objc_release(view); objc_release(coordinator); swift_bridge_release(text[1])
	if alias {
		assert obj_header(view).refs == initial_view_refs && obj_header(coordinator).refs == initial_coordinator_refs && read64(owner+8) == initial_string_refs
		objc_release(view); objc_release(coordinator); swift_bridge_release(text[1])
	}
	assert ios_runtime.live == baseline && ios_runtime.swift_strings.len == 0
}

__global size_override_callback_calls = 0
__global size_override_probe_address = u64(0)
__global size_override_guard_address = u64(0)
fn size_override_callback(object u64, selector &char) {
	assert ios_runtime.swift_concurrency_retired
	size_override_raw(unsafe { SizeOverrideProbe(voidptr(size_override_probe_address)) },size_override_resolve(),size_override_guard_address)
	size_override_callback_calls++
}

fn test_swiftui_size_override() {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil },page,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0))
	sizes_base := u64(C.mmap(unsafe { nil },page*3,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0))
	borrowed := u64(C.mmap(unsafe { nil },page*2,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0))
	assert code != u64(-1) && sizes_base != u64(-1) && borrowed != u64(-1)
	guard := sizes_base; data := sizes_base+u64(page)
	ops := [u32(0xa9bd7bfd),0xa90153f3,0xa9025bf5,0xaa0003f1,0xaa0103f0,0xaa0203f3,0xa9400620,0xa9410e22,0xa9421624,0xa9431e26,0xf9402228,0xf9402634,0xf9402a35,0xfd402e20,0xfd403221,0xd63f0200,0xa9000660,0xa9010e62,0xa9021664,0xa9031e66,0xf9002268,0xa904d674,0x6d058660,0xa9425bf5,0xa94153f3,0xa8c37bfd,0xd65f03c0]!
	for i,op in ops { write32(code+u64(i*4),op) }
	C.__builtin___clear_cache(voidptr(code),voidptr(code+u64(ops.len*4)))
	assert C.mprotect(voidptr(code),page,C.PROT_READ|C.PROT_EXEC) == 0
	probe := unsafe { SizeOverrideProbe(voidptr(code)) }; size_override_probe_address = code; size_override_guard_address = guard
	$if macos {
		library := C.dlopen(c'/System/Library/Frameworks/SwiftUI.framework/SwiftUI',2); assert library != unsafe { nil }
		entry := u64(C.dlsym(library,c'$s7SwiftUI19NSViewRepresentablePAAE21_overrideSizeThatFits_2in6nsViewySo6CGSizeVz_AA09_ProposedF0V0C4TypeQztF'))
		assert entry != 0 && read32(entry) == 0xd65f03c0
		size_override_raw(probe,entry,guard)
		for i in 0..64 { size_override_frame(probe,entry,guard,data,page,guard,guard,i) }
		assert C.dlclose(library) == 0
		println('NATIVE-SWIFTUI-SIZE-OVERRIDE: AppKit default is ret, unchanged read-only/writable CGSize boundary bits and nil/finite/infinite/NaN proposals, x0-x8/x20/x21/d0/d1 preserved; UIKit default was not executed natively')
	}
	entry := size_override_resolve(); size_override_raw(probe,entry,guard)
	for symbol in ['_$s7SwiftUI19UIViewRepresentablePAAE21_overrideSizeThatFits_2in6uiViewySo6CGSizeVz_AA09_ProposedF0V0C4TypeQztFExtra','_$s7SwiftUI19NSViewRepresentablePAAE21_overrideSizeThatFits_2in6nsViewySo6CGSizeVz_AA09_ProposedF0V0C4TypeQztF','_$s7SwiftUI19UIViewRepresentablePAAE12sizeThatFits_6uiView7contextSo6CGSizeVSgAA08ProposedI4SizeV_0C4TypeQzAA0cD7ContextVyxGtF']! { if _ := swiftui_size_override_symbol(symbol) { assert false } }
	for _ in 0..2 {
		objc_start(); mut workers := []thread u64{}
		for _ in 0..8 { workers << spawn size_override_reader(probe,guard) }
		for worker in workers { assert worker.wait() == entry }; unsafe { workers.free() }
		for i in 0..300 { size_override_owned(probe,entry,guard,data,borrowed,page,i) }
		for library in ['/usr/lib/swift/libswiftCore.dylib','/System/Library/Frameworks/Foundation.framework/Foundation','/System/Library/Frameworks/SwiftUICore.framework/SwiftUICore']! { if _ := runtime_symbol(library,'_$s7SwiftUI19UIViewRepresentablePAAE21_overrideSizeThatFits_2in6uiViewySo6CGSizeVz_AA09_ProposedF0V0C4TypeQztF') { assert false } }
		assert ios_runtime.swift_strings.len == 0 && ios_runtime.swift_arrays.len == 0 && ios_runtime.swift_heap.len == 0 && ios_runtime.swift_buffers.len == 0 && ios_runtime.live == 0
		cls := objc_allocate_class(ios_runtime.names['NSObject'],c'VinixSizeOverrideCallback',0)
		assert cls != 0 && objc_add_method(cls,u64(c'dealloc'),u64(unsafe { voidptr(size_override_callback) }),c'v16@0:8')
		objc_register_class(cls); objc_autorelease(objc_new(cls)); before := size_override_callback_calls
		ios_runtime.swift_concurrency_retired = true; objc_stop()
		assert size_override_callback_calls == before+1 && ios_runtime.live == 0 && size_override_resolve() == entry
		size_override_raw(probe,entry,guard)
	}
	assert C.munmap(voidptr(code),page) == 0 && C.munmap(voidptr(sizes_base),page*3) == 0 && C.munmap(voidptr(borrowed),page*2) == 0
	println('IOS-SWIFTUI-SIZE-OVERRIDE: empty default leaves all CGSize bits unchanged, nil/finite/infinite/NaN proposals and negative-zero sizes, eight readers and 16384 concurrent calls, 600 borrowed ownership cycles with unchanged ObjC/Swift aliases, read-only/writable CGSize at both protected boundaries, read-only Swift self and protected metadata/witness/x8, x0-x8/x20/x21/d0/d1 preserved, exact framework routing, callbacks and two drained runtime lifetimes; custom sizing, layout and graph execution remain unsupported')
}

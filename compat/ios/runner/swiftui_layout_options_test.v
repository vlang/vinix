// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char,i32)voidptr
fn C.dlsym(voidptr,&char)voidptr
fn C.dlclose(voidptr)i32
type LayoutOptionsProbe = fn (&u64,u64,&u64)
type LayoutOptionsMetadata = fn (u64)SwiftAssociatedMetadata

fn layout_options_resolve() u64 {
	return runtime_symbol('/System/Library/Frameworks/SwiftUI.framework/SwiftUI','_$s7SwiftUI19UIViewRepresentablePAAE14_layoutOptionsyAA013_PlatformViewd6LayoutF0V0C4TypeQzFZ') or { panic(err) }
}

fn layout_options_allocate(page usize) u64 {
	base := u64(C.mmap(unsafe { nil },page*3,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0))
	assert base != u64(-1) && C.mprotect(voidptr(base+u64(page)),page,C.PROT_READ|C.PROT_WRITE) == 0
	return base
}

fn layout_options_check(probe LayoutOptionsProbe, entry u64, provider u64, guard u64, base u64, page usize, at_end bool, strict bool) {
	data := base+u64(page)
	destination := if at_end { data+u64(page)-8 } else { data }
	C.memset(voidptr(data),0xa5,page)
	input := [provider,guard,guard,u64(0xdeadbeef),destination,u64(0x5020),0x5021]!
	mut output := [u64(0xcafe),0,0,0,0,0,0,0,0xbeef]!
	probe(unsafe { &input[0] },entry,unsafe { &output[1] })
	assert output[0] == 0xcafe && output[8] == 0xbeef && output[6] == input[5] && output[7] == input[6]
	if strict { for i in 0..7 { assert output[i+1] == input[i] } }
	assert read64(destination) == 1
	for i in u64(0)..u64(page) {
		if data+i >= destination && data+i < destination+8 { continue }
		assert unsafe { *(&u8(data+i)) } == 0xa5
	}
}

fn layout_options_reader(probe LayoutOptionsProbe, guard u64, page usize) u64 {
	entry := layout_options_resolve(); base := layout_options_allocate(page)
	for i in 0..1024 {
		assert layout_options_resolve() == entry
		layout_options_check(probe,entry,guard,guard,base,page,i&1 != 0,true)
	}
	assert C.munmap(voidptr(base),page*3) == 0
	return entry
}

__global layout_options_callback_calls = 0
__global layout_options_probe_address = u64(0)
__global layout_options_guard_address = u64(0)
__global layout_options_result_address = u64(0)
fn layout_options_callback(object u64, selector &char) {
	assert ios_runtime.swift_concurrency_retired
	page := usize(C.getpagesize())
	layout_options_check(unsafe { LayoutOptionsProbe(voidptr(layout_options_probe_address)) },layout_options_resolve(),object,layout_options_guard_address,layout_options_result_address,page,true,true)
	layout_options_callback_calls++
}

fn test_swiftui_layout_options() {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil },page,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0))
	assert code != u64(-1)
	base := layout_options_allocate(page); guard := base
	provider_base := layout_options_allocate(page); provider := provider_base+u64(page*2)-24
	unsafe { *(&u64(provider)) = 0x1234; *(&u64(provider+8)) = 0x5678; *(&u64(provider+16)) = 0x9abc }
	assert C.mprotect(voidptr(provider_base+u64(page)),page,C.PROT_READ) == 0
	for i,op in [u32(0xa9bd7bfd),0xa90153f3,0xa9025bf5,0xaa0003f1,0xaa0103f0,0xaa0203f3,0xa9400620,0xa9410e22,0xf9401228,0xf9401634,0xf9401a35,0xd63f0200,0xa9000660,0xa9010e62,0xf9001268,0xa902d674,0xa9425bf5,0xa94153f3,0xa8c37bfd,0xd65f03c0]! { write32(code+u64(i*4),op) }
	C.__builtin___clear_cache(voidptr(code),voidptr(code+80))
	assert C.mprotect(voidptr(code),page,C.PROT_READ|C.PROT_EXEC) == 0
	probe := unsafe { LayoutOptionsProbe(voidptr(code)) }
	layout_options_probe_address = code; layout_options_guard_address = guard; layout_options_result_address = base
	$if macos {
		library := C.dlopen(c'/System/Library/Frameworks/SwiftUI.framework/SwiftUI',2)
		assert library != unsafe { nil }
		access := u64(C.dlsym(library,c'$s7SwiftUI39_PlatformViewRepresentableLayoutOptionsVMa'))
		assert access != 0
		metadata := unsafe { LayoutOptionsMetadata(voidptr(access)) }(0)
		assert metadata.metadata != 0 && metadata.state == 0
		witness := read64(metadata.metadata-8)
		assert read64(witness+64) == 8 && read64(witness+72) == 8 && read32(witness+80)&0x1ffff == 7
		entry := u64(C.dlsym(library,c'$s7SwiftUI19NSViewRepresentablePAAE14_layoutOptionsyAA013_PlatformViewd6LayoutF0V0C4TypeQzFZ'))
		constructor := u64(C.dlsym(library,c'$s7SwiftUI39_PlatformViewRepresentableLayoutOptionsV8rawValueACSi_tcfC'))
		assert entry != 0 && constructor != 0 && read32(constructor) == 0xf9000100 && read32(constructor+4) == 0xd65f03c0
		for i in 0..256 {
			layout_options_check(probe,entry,guard,guard,base,page,i&1 != 0,false)
			layout_options_check(probe,constructor,1,guard,base,page,i&1 != 0,true)
		}
		assert C.dlclose(library) == 0
		println('NATIVE-SWIFTUI-LAYOUT-OPTIONS: native POD size/stride/alignment 8/8/8, AppKit default and rawValue constructor return 1 through x8, exact eight-byte writes at protected boundaries, x20/x21 preserved; UIKit default was not executed natively')
	}
	entry := layout_options_resolve()
	for symbol in ['_$s7SwiftUI19UIViewRepresentablePAAE14_layoutOptionsyAA013_PlatformViewd6LayoutF0V0C4TypeQzFZExtra','_$s7SwiftUI19NSViewRepresentablePAAE14_layoutOptionsyAA013_PlatformViewd6LayoutF0V0C4TypeQzFZ','_$s7SwiftUI39_PlatformViewRepresentableLayoutOptionsVMa']! { if _ := swiftui_layout_options_symbol(symbol) { assert false } }
	for _ in 0..2 {
		objc_start()
		mut workers := []thread u64{}
		for _ in 0..8 { workers << spawn layout_options_reader(probe,guard,page) }
		for worker in workers { assert worker.wait() == entry }; unsafe { workers.free() }
		for p in [u64(0),guard,~u64(0),provider]! { for at_end in [false,true]! { layout_options_check(probe,entry,p,guard,base,page,at_end,true) } }
		assert read64(provider) == 0x1234 && read64(provider+8) == 0x5678 && read64(provider+16) == 0x9abc
		for i in 0..300 {
			view := objc_new(ios_runtime.names['UIView']); assert view != 0
			initial := obj_header(view).refs
			if i&1 != 0 { assert objc_retain(view) == view }
			refs := obj_header(view).refs
			layout_options_check(probe,entry,view,guard,base,page,i&1 != 0,true)
			assert obj_header(view).refs == refs
			objc_release(view)
			if i&1 != 0 { assert obj_header(view).refs == initial; objc_release(view) }
			assert ios_runtime.live == 0
		}
		for path in ['/usr/lib/swift/libswiftCore.dylib','/System/Library/Frameworks/Foundation.framework/Foundation','/System/Library/Frameworks/SwiftUICore.framework/SwiftUICore']! { if _ := runtime_symbol(path,'_$s7SwiftUI19UIViewRepresentablePAAE14_layoutOptionsyAA013_PlatformViewd6LayoutF0V0C4TypeQzFZ') { assert false } }
		assert ios_runtime.swift_strings.len == 0 && ios_runtime.swift_arrays.len == 0 && ios_runtime.swift_heap.len == 0 && ios_runtime.swift_buffers.len == 0 && ios_runtime.live == 0
		cls := objc_allocate_class(ios_runtime.names['NSObject'],c'VinixLayoutOptionsCallback',0)
		assert cls != 0 && objc_add_method(cls,u64(c'dealloc'),u64(unsafe { voidptr(layout_options_callback) }),c'v16@0:8')
		objc_register_class(cls); objc_autorelease(objc_new(cls)); before := layout_options_callback_calls
		ios_runtime.swift_concurrency_retired = true; objc_stop()
		assert layout_options_callback_calls == before+1 && ios_runtime.live == 0 && layout_options_resolve() == entry
		layout_options_check(probe,entry,provider,guard,base,page,true,true)
	}
	assert C.munmap(voidptr(code),page) == 0 && C.munmap(voidptr(base),page*3) == 0 && C.munmap(voidptr(provider_base),page*3) == 0
	println('IOS-SWIFTUI-LAYOUT-OPTIONS: rawValue 1 through indirect x8 result, exact eight-byte writes with protected bounds, eight readers and 16384 concurrent calls, 600 borrowed UIView ownership cycles, read-only provider boundary and protected metadata/witnesses, x0-x3/x8/x20/x21 preserved, exact framework routing, callbacks and two drained runtime lifetimes; custom options, layout and graph execution remain unsupported')
}

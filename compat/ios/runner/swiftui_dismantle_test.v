// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char,i32)voidptr
fn C.dlsym(voidptr,&char)voidptr
fn C.dlclose(voidptr)i32
type DismantleProbe=fn (&u64,u64,&u64)
fn dismantle_resolve()u64{return runtime_symbol('/System/Library/Frameworks/SwiftUI.framework/SwiftUI','_$s7SwiftUI19UIViewRepresentablePAAE09dismantleC0_11coordinatory0C4TypeQz_11CoordinatorQztFZ') or {panic(err)}}
fn dismantle_call(probe DismantleProbe,entry u64,input [7]u64){
	mut result:=[u64(0xcafe),0,0,0,0,0,0,0,0xbeef]!
	probe(unsafe{&input[0]},entry,unsafe{&result[1]})
	assert result==[u64(0xcafe),input[0],input[1],input[2],input[3],input[4],input[5],input[6],0xbeef]!
}
fn dismantle_raw(probe DismantleProbe,entry u64,guard u64){
	for input in [[u64(0),0,0,0,guard,0x5020,0x5021]!,[guard,guard,guard,guard,guard,guard,guard]!,[u64(0xffffffffffffffff),guard,guard,guard,guard,0x5020,0x5021]!,[guard,u64(0xffffffffffffffff),guard,guard,guard,0x5020,0x5021]!]!{for _ in 0..128{dismantle_call(probe,entry,input)}}
}
fn dismantle_reader(probe DismantleProbe,guard u64)u64{
	entry:=dismantle_resolve();for _ in 0..1024{assert dismantle_resolve()==entry;dismantle_call(probe,entry,[guard,guard,guard,guard,guard,u64(0x5020),0x5021]!)};return entry
}
fn dismantle_owned(probe DismantleProbe,entry u64,guard u64,borrowed u64,page usize,alias bool){
	baseline:=ios_runtime.live;view:=objc_new(ios_runtime.names['UIView']);coordinator:=objc_new(ios_runtime.names['NSObject']);assert view!=0&&coordinator!=0
	words:=swift_interpolation_init(64,0);mut text:=[words.first,words.second]!;contents:='borrowed coordinator string';swift_string_append_bytes(u64(unsafe{&text[0]}),u64(contents.str),u64(contents.len));owner:=text[1]&swift_address_mask
	initial_view_refs:=obj_header(view).refs;initial_coordinator_refs:=obj_header(coordinator).refs;initial_string_refs:=read64(owner+8)
	if alias{assert objc_retain(view)==view&&objc_retain(coordinator)==coordinator;assert swift_bridge_retain(text[1])==text[1]}
	view_refs:=obj_header(view).refs;coordinator_refs:=obj_header(coordinator).refs;string_refs:=read64(owner+8)
	span:=borrowed+u64(page)-24;assert C.mprotect(voidptr(borrowed),page,C.PROT_READ|C.PROT_WRITE)==0
	unsafe{*(&u64(span))=coordinator;*(&u64(span+8))=text[0];*(&u64(span+16))=text[1]};assert C.mprotect(voidptr(borrowed),page,C.PROT_READ)==0
	dismantle_call(probe,entry,[view,span,guard,guard,guard,u64(0x5020),0x5021]!)
	assert read64(span)==coordinator&&read64(span+8)==text[0]&&read64(span+16)==text[1]
	assert obj_header(view).refs==view_refs&&obj_header(coordinator).refs==coordinator_refs&&read64(owner+8)==string_refs
	objc_release(view);objc_release(coordinator);swift_bridge_release(text[1]);if alias{assert obj_header(view).refs==initial_view_refs&&obj_header(coordinator).refs==initial_coordinator_refs&&read64(owner+8)==initial_string_refs;objc_release(view);objc_release(coordinator);swift_bridge_release(text[1])}
	assert ios_runtime.live==baseline&&ios_runtime.swift_strings.len==0
}
__global dismantle_callback_calls=0
__global dismantle_probe_address=u64(0)
__global dismantle_guard_address=u64(0)
fn dismantle_callback(object u64,selector &char){assert ios_runtime.swift_concurrency_retired;dismantle_raw(unsafe{DismantleProbe(voidptr(dismantle_probe_address))},dismantle_resolve(),dismantle_guard_address);dismantle_callback_calls++}
fn test_swiftui_dismantle(){
	page:=usize(C.getpagesize());code:=u64(C.mmap(unsafe{nil},page,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));guard:=u64(C.mmap(unsafe{nil},page,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));borrowed:=u64(C.mmap(unsafe{nil},page*2,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert code!=u64(-1)&&guard!=u64(-1)&&borrowed!=u64(-1)
	for i,op in [u32(0xa9bd7bfd),0xa90153f3,0xa9025bf5,0xaa0003f1,0xaa0103f0,0xaa0203f3,0xa9400620,0xa9410e22,0xf9401228,0xf9401634,0xf9401a35,0xd63f0200,0xa9000660,0xa9010e62,0xf9001268,0xa902d674,0xa9425bf5,0xa94153f3,0xa8c37bfd,0xd65f03c0]!{write32(code+u64(i*4),op)}
	C.__builtin___clear_cache(voidptr(code),voidptr(code+80));assert C.mprotect(voidptr(code),page,C.PROT_READ|C.PROT_EXEC)==0;probe:=unsafe{DismantleProbe(voidptr(code))};dismantle_probe_address=code;dismantle_guard_address=guard
	$if macos{
		ui:=C.dlopen(c'/System/Library/Frameworks/SwiftUI.framework/SwiftUI',2);assert ui!=unsafe{nil};entry:=u64(C.dlsym(ui,c'$s7SwiftUI19NSViewRepresentablePAAE09dismantleC0_11coordinatory0C4TypeQz_11CoordinatorQztFZ'));assert entry!=0&&read32(entry)==0xd65f03c0;dismantle_raw(probe,entry,guard);assert C.dlclose(ui)==0
		println('NATIVE-SWIFTUI-DISMANTLE: AppKit default is ret, borrowed/protected input spans and x8 untouched, x0-x3/x8/x20/x21 preserved; UIKit default was not executed natively')
	}
	entry:=dismantle_resolve();dismantle_raw(probe,entry,guard)
	for symbol in ['_$s7SwiftUI19UIViewRepresentablePAAE09dismantleC0_11coordinatory0C4TypeQz_11CoordinatorQztFZExtra','_$s7SwiftUI19NSViewRepresentablePAAE09dismantleC0_11coordinatory0C4TypeQz_11CoordinatorQztFZ','_$s7SwiftUI29UIViewControllerRepresentablePAAE09dismantleC0_11coordinatory0C4TypeQz_11CoordinatorQztFZ']!{if _:=swiftui_dismantle_symbol(symbol){assert false}}
	for _ in 0..2{
		objc_start();mut workers:=[]thread u64{};for _ in 0..8{workers<<spawn dismantle_reader(probe,guard)};for worker in workers{assert worker.wait()==entry};unsafe{workers.free()}
		for i in 0..300{dismantle_owned(probe,entry,guard,borrowed,page,i&1!=0)}
		for library in ['/usr/lib/swift/libswiftCore.dylib','/System/Library/Frameworks/Foundation.framework/Foundation','/System/Library/Frameworks/SwiftUICore.framework/SwiftUICore']!{if _:=runtime_symbol(library,'_$s7SwiftUI19UIViewRepresentablePAAE09dismantleC0_11coordinatory0C4TypeQz_11CoordinatorQztFZ'){assert false}}
		assert ios_runtime.swift_strings.len==0&&ios_runtime.swift_arrays.len==0&&ios_runtime.swift_heap.len==0&&ios_runtime.swift_buffers.len==0&&ios_runtime.live==0
		cls:=objc_allocate_class(ios_runtime.names['NSObject'],c'VinixDismantleCallback',0);assert cls!=0&&objc_add_method(cls,u64(c'dealloc'),u64(unsafe{voidptr(dismantle_callback)}),c'v16@0:8');objc_register_class(cls);objc_autorelease(objc_new(cls))
		before:=dismantle_callback_calls;ios_runtime.swift_concurrency_retired=true;objc_stop();assert dismantle_callback_calls==before+1&&ios_runtime.live==0;assert dismantle_resolve()==entry;dismantle_raw(probe,entry,guard)
	}
	assert C.munmap(voidptr(code),page)==0&&C.munmap(voidptr(guard),page)==0&&C.munmap(voidptr(borrowed),page*2)==0
	println('IOS-SWIFTUI-DISMANTLE: empty default only, eight readers and 16384 concurrent calls, 600 borrowed ownership cycles with unchanged ObjC/Swift aliases, read-only coordinator boundary and protected input/result pages, x0-x3/x8/x20/x21 preserved, exact framework routing, callbacks and two drained runtime lifetimes; view removal, custom lifecycle and graph execution remain unsupported')
}

// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char,i32)voidptr
fn C.dlsym(voidptr,&char)voidptr
fn C.dlclose(voidptr)i32
type AlignmentGetter = fn ()u64
type AlignmentPairGetter = fn ()SwiftUIAlignmentValue
type AlignmentProbe = fn (u64,u64,u64,&u64,u64)
struct AlignmentApi {
	horizontal u64
	pair u64
	horizontal_key u64
	vertical_key u64
}
fn alignment_resolve(symbol string)u64{return runtime_symbol('/System/Library/Frameworks/SwiftUI.framework/SwiftUI',symbol) or {panic(err)}}
fn alignment_api()AlignmentApi{
	return AlignmentApi{alignment_resolve('_$s7SwiftUI19HorizontalAlignmentV6centerACvgZ'),alignment_resolve('_$s7SwiftUI9AlignmentV6centerACvgZ'),swiftui_horizontal_center_key,swiftui_vertical_center_key}
}
fn alignment_calls(api AlignmentApi,probe AlignmentProbe,guard u64){
	assert api.horizontal_key!=0&&api.vertical_key!=0&&api.horizontal_key&1==0&&api.vertical_key&1==1
	assert api.horizontal_key>>1!=api.vertical_key>>1
	assert unsafe{AlignmentGetter(voidptr(api.horizontal))}()==api.horizontal_key
	assert unsafe{AlignmentPairGetter(voidptr(api.pair))}()==SwiftUIAlignmentValue{api.horizontal_key,api.vertical_key}
	for pair in [[api.horizontal,api.horizontal_key,u64(0)]!,[api.pair,api.horizontal_key,api.vertical_key]!]!{
		mut result:=[u64(0xcafe),0,0,0,0,0,0,0xbeef]!
		probe(0xffffffffffffffff,0xfafa,pair[0],unsafe{&result[1]},guard)
		assert result[0]==0xcafe&&result[7]==0xbeef&&result[1]==pair[1]&&result[5]==0x5020&&result[6]==0x5021
		if pair[0]==api.pair{assert result[2]==pair[2]}
	}
}
fn alignment_reader(probe AlignmentProbe,guard u64)AlignmentApi{
	api:=alignment_api();for _ in 0..1024{assert alignment_api()==api;alignment_calls(api,probe,guard)};return api
}
__global alignment_teardown_calls=0
__global alignment_probe_address=u64(0)
__global alignment_guard_address=u64(0)
fn alignment_teardown(object u64,selector &char){assert ios_runtime.swift_concurrency_retired;alignment_calls(alignment_api(),unsafe{AlignmentProbe(voidptr(alignment_probe_address))},alignment_guard_address);alignment_teardown_calls++}
fn test_swiftui_alignment(){
	page:=usize(C.getpagesize());code:=u64(C.mmap(unsafe{nil},page,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));guard:=u64(C.mmap(unsafe{nil},page,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert code!=u64(-1)&&guard!=u64(-1)
	for i,op in [u32(0xa9bd7bfd),0xa90153f3,0xa9025bf5,0xaa0203f0,0xaa0303f3,0xd28a0414,0xd28a0435,0xaa0403e8,0xd63f0200,0xa9000660,0xa9010e62,0xa9025674,0xa9425bf5,0xa94153f3,0xa8c37bfd,0xd65f03c0]!{write32(code+u64(i*4),op)}
	C.__builtin___clear_cache(voidptr(code),voidptr(code+64));assert C.mprotect(voidptr(code),page,C.PROT_READ|C.PROT_EXEC)==0;probe:=unsafe{AlignmentProbe(voidptr(code))};alignment_probe_address=code;alignment_guard_address=guard
	$if macos{
		ui:=C.dlopen(c'/System/Library/Frameworks/SwiftUI.framework/SwiftUI',2);assert ui!=unsafe{nil}
		horizontal:=u64(C.dlsym(ui,c'$s7SwiftUI19HorizontalAlignmentV6centerACvgZ'));pair:=u64(C.dlsym(ui,c'$s7SwiftUI9AlignmentV6centerACvgZ'));vertical:=u64(C.dlsym(ui,c'$s7SwiftUI17VerticalAlignmentV6centerACvgZ'));assert horizontal!=0&&pair!=0&&vertical!=0
		api:=AlignmentApi{horizontal,pair,unsafe{AlignmentGetter(voidptr(horizontal))}(),unsafe{AlignmentGetter(voidptr(vertical))}()};for _ in 0..1000{alignment_calls(api,probe,guard)};assert C.dlclose(ui)==0
		println('NATIVE-SWIFTUI-ALIGNMENT: POD center identities with axis tags, horizontal/pair component consistency, direct x0 and x0/x1 results, protected x8 and preserved x20/x21')
	}
	stable:=alignment_api();alignment_calls(stable,probe,guard)
	for symbol in ['_$s7SwiftUI19HorizontalAlignmentVMa','_$s7SwiftUI19HorizontalAlignmentV7leadingACvgZ','_$s7SwiftUI17VerticalAlignmentV6centerACvgZ','_$s7SwiftUI9AlignmentV6centerACvgZExtra','_$s7SwiftUICore9AlignmentV6centerACvgZ']!{if _:=swiftui_alignment_symbol(symbol){assert false}}
	for _ in 0..2{
		objc_start();mut workers:=[]thread AlignmentApi{};for _ in 0..8{workers<<spawn alignment_reader(probe,guard)};for worker in workers{assert worker.wait()==stable};unsafe{workers.free()}
		for library in ['/usr/lib/swift/libswiftCore.dylib','/System/Library/Frameworks/Foundation.framework/Foundation','/System/Library/Frameworks/SwiftUICore.framework/SwiftUICore']!{for symbol in ['_$s7SwiftUI19HorizontalAlignmentV6centerACvgZ','_$s7SwiftUI9AlignmentV6centerACvgZ']!{if _:=runtime_symbol(library,symbol){assert false}}}
		assert ios_runtime.swift_strings.len==0&&ios_runtime.swift_arrays.len==0&&ios_runtime.swift_heap.len==0&&ios_runtime.swift_buffers.len==0&&ios_runtime.live==0
		cls:=objc_allocate_class(ios_runtime.names['NSObject'],c'VinixAlignmentTeardown',0);assert cls!=0&&objc_add_method(cls,u64(c'dealloc'),u64(unsafe{voidptr(alignment_teardown)}),c'v16@0:8');objc_register_class(cls);objc_autorelease(objc_new(cls))
		before:=alignment_teardown_calls;ios_runtime.swift_concurrency_retired=true;objc_stop();assert alignment_teardown_calls==before+1&&ios_runtime.live==0;assert alignment_api()==stable;alignment_calls(stable,probe,guard)
	}
	assert C.munmap(voidptr(code),page)==0&&C.munmap(voidptr(guard),page)==0
	println('IOS-SWIFTUI-ALIGNMENT: eight cold readers, 16384 concurrent iterations across two drained lifetimes, stable reserved axis-tagged identities, direct x0 and x0/x1 results, protected x8 and preserved x20/x21, exact framework routing, no owned payloads and callback/post-shutdown use; metadata, custom alignment and layout remain unsupported')
}

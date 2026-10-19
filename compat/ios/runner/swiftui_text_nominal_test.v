// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import strconv
#include <dlfcn.h>
fn C.dlopen(&char,i32)voidptr
fn C.dlsym(voidptr,&char)voidptr
fn C.dlclose(voidptr)i32
fn C.mincore(voidptr,usize,&u8)i32
$if macos {
	#include <mach/mach.h>
	fn C.mach_task_self()u32
	fn C.vm_region_64(u32,&u64,&u64,i32,&i32,&u32,&u32)i32
	fn C.mach_port_deallocate(u32,u32)i32
}
type TextNominalAccess = fn (u64)SwiftAssociatedMetadata
fn text_nominal_relative(p u64)u64{delta:=i32(read32(p));return if delta==0{u64(0)}else{u64(i64(p)+i64(delta))}}
fn text_nominal_text(p u64)string{return unsafe{(&char(p)).vstring()}}
fn text_nominal_resolve()u64{return runtime_symbol('/System/Library/Frameworks/SwiftUI.framework/SwiftUI','_$s7SwiftUI4TextVMn') or {panic(err)}}
fn text_nominal_table()u64{return runtime_symbol('/System/Library/Frameworks/SwiftUI.framework/SwiftUI','_$s7SwiftUI4TextVAA4ViewAAWP') or {panic(err)}}
fn text_nominal_protection(address u64,length u64,executable bool){
	$if macos{
		mut start:=address;mut size:=u64(0);mut info:=[16]i32{};mut count:=u32(C.VM_REGION_BASIC_INFO_COUNT_64);mut object:=u32(0);task:=C.mach_task_self()
		assert C.vm_region_64(task,&start,&size,C.VM_REGION_BASIC_INFO_64,unsafe{&info[0]},&count,&object)==0
		assert start<=address&&address+length<=start+size&&info[0]==(C.PROT_READ|if executable{C.PROT_EXEC}else{0})
		if object!=0{assert C.mach_port_deallocate(task,object)==0}
	}$else{
		mut found:=false
		for line in (os.read_file('/proc/self/maps') or {panic(err)}).split_into_lines(){fields:=line.fields();if fields.len<2{continue};range:=fields[0].split('-');if range.len!=2{continue};start:=strconv.parse_uint(range[0],16,64) or {panic(err)};end:=strconv.parse_uint(range[1],16,64) or {panic(err)};if address>=start&&address<end{assert address+length<=end&&fields[1]==if executable{'r-xp'}else{'r--p'};found=true;break}};assert found
	}
}
fn text_nominal_signature(descriptor u64,table u64,native bool){
	assert read32(descriptor)==0x51&&read32(descriptor+20)==2&&read32(descriptor+24)==2
	module_descriptor:=text_nominal_relative(descriptor+4)
	assert read32(module_descriptor)==0&&text_nominal_text(text_nominal_relative(module_descriptor+8))=='SwiftUI'
	assert text_nominal_text(text_nominal_relative(descriptor+8))=='Text'
	conformance:=read64(table);assert read32(conformance+12)==8&&read64(text_nominal_relative(conformance+4))==descriptor
	assert text_nominal_relative(descriptor+12)!=0
	if !native{
		assert descriptor==ios_runtime.swiftui_text_view_arena+u64(C.getpagesize())&&table==descriptor+384
		assert read32(descriptor+16)==0&&text_nominal_relative(descriptor+12)==ios_runtime.swiftui_text_view_arena+64
		text_nominal_protection(ios_runtime.swiftui_text_view_arena,64,true);text_nominal_protection(descriptor,488,false)
	}
}
fn text_nominal_lookup(descriptor u64,name u64,guard u64,request u64,symbolic bool){metadata:=swiftui_text_metadata();if symbolic{assert swift_mangled_state_lookup_checked(request,name,5,guard,guard) or {panic(err)}==metadata}else{call:=unsafe{TextNominalAccess(voidptr(text_nominal_relative(descriptor+12)))};assert call(request)==SwiftAssociatedMetadata{metadata:metadata}}}
fn text_nominal_rejection(descriptor u64){
	page:=usize(C.getpagesize());base:=u64(C.mmap(unsafe{nil},page*2,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert base!=u64(-1)
	guard:=base+u64(page);name:=guard-5;slot:=base+64
	unsafe{*(&u64(slot))=descriptor};assert C.mprotect(voidptr(guard),page,C.PROT_NONE)==0
	for tag in [u8(1),2]!{
		unsafe{*(&u8(name))=tag};target:=if tag==1{descriptor}else{slot};delta:=i64(target)-i64(name+1);assert delta>=-2147483648&&delta<=2147483647;bits:=u32(i32(delta))
		for i in u64(0)..4{unsafe{*(&u8(name+1+i))=u8(bits>>(i*8))}}
		assert C.mprotect(voidptr(base),page,C.PROT_READ)==0
		for request in [u64(0),0x3f,0xff,0x100,0x13f,0x1ff]!{text_nominal_lookup(descriptor,name,guard,request,true)}
		assert C.mprotect(voidptr(base),page,C.PROT_READ|C.PROT_WRITE)==0
	}
	for request in [u64(0),0xff,0x1ff,~u64(0)]!{text_nominal_lookup(descriptor,name,guard,request,false)}
	assert C.munmap(voidptr(base),page*2)==0
}
fn text_nominal_reader()u64{mut descriptor:=u64(0);for _ in 0..128{candidate:=text_nominal_resolve();if descriptor==0{descriptor=candidate}else{assert descriptor==candidate};assert read32(descriptor)==0x51&&read64(text_nominal_relative(read64(text_nominal_table())+4))==descriptor};return descriptor}
__global text_nominal_teardown_calls=0
fn text_nominal_teardown(object u64,selector &char){assert ios_runtime.swift_concurrency_retired;text_nominal_signature(text_nominal_resolve(),text_nominal_table(),false);text_nominal_teardown_calls++}
fn test_swiftui_text_nominal(){
	$if macos{
		library:=C.dlopen(c'/System/Library/Frameworks/SwiftUI.framework/SwiftUI',2);assert library!=unsafe{nil}
		descriptor:=u64(C.dlsym(library,c'$s7SwiftUI4TextVMn'));table:=u64(C.dlsym(library,c'$s7SwiftUI4TextVAA4ViewAAWP'));assert descriptor!=0&&table!=0
		text_nominal_signature(descriptor,table,true);assert C.dlclose(library)==0
		println('NATIVE-SWIFTUI-TEXT-NOMINAL: nongeneric SwiftUI.Text, two fields, offset vector word two, shared View conformance identity')
	}
	if _:=swiftui_text_view_arena_checked(){assert false};page:=usize(C.getpagesize())
	for _ in 0..2{
		objc_start();assert ios_runtime.swiftui_text_view_arena==0&&!ios_runtime.swiftui_text_view_retired
		ios_runtime.swift_concurrency_retired=true;if _:=runtime_symbol('/System/Library/Frameworks/SwiftUI.framework/SwiftUI','_$s7SwiftUI4TextVMn'){assert false};ios_runtime.swift_concurrency_retired=false
		for symbol in ['_$s7SwiftUI4TextVNExtra','_$s7SwiftUI4TextVMa','_$s7SwiftUI4TextVMnExtra','_$s7SwiftUI4TextVMf','_$s11SwiftUICore4TextVMn']!{if _:=swiftui_text_view_symbol(symbol){assert false}};assert ios_runtime.swiftui_text_view_arena==0
		mut workers:=[]thread u64{};for _ in 0..8{workers<<spawn text_nominal_reader()};mut descriptor:=u64(0);for i,worker in workers{candidate:=worker.wait();if i==0{descriptor=candidate}else{assert descriptor==candidate}};unsafe{workers.free()}
		text_nominal_signature(descriptor,text_nominal_table(),false);text_nominal_rejection(descriptor)
		for library in ['/usr/lib/swift/libswiftCore.dylib','/System/Library/Frameworks/Foundation.framework/Foundation','/System/Library/Frameworks/SwiftUICore.framework/SwiftUICore']!{if _:=runtime_symbol(library,'_$s7SwiftUI4TextVMn'){assert false}}
		assert ios_runtime.swiftui_opacity_arena==0&&ios_runtime.swift_void_arena==0&&ios_runtime.swift_array_arena==0&&ios_runtime.swift_metadata_arena==0&&ios_runtime.swift_heap.len==0&&ios_runtime.swift_buffers.len==0&&ios_runtime.live==0
		cls:=objc_allocate_class(ios_runtime.names['NSObject'],c'VinixTextNominalTeardown',0);assert cls!=0&&objc_add_method(cls,u64(c'dealloc'),u64(unsafe{voidptr(text_nominal_teardown)}),c'v16@0:8');objc_register_class(cls);objc_autorelease(objc_new(cls))
		base:=ios_runtime.swiftui_text_view_arena;before:=text_nominal_teardown_calls;ios_runtime.swift_concurrency_retired=true;assert text_nominal_resolve()==descriptor;objc_stop()
		assert text_nominal_teardown_calls==before+1&&ios_runtime.swiftui_text_view_arena==0&&ios_runtime.swiftui_text_view_retired&&ios_runtime.live==0&&ios_runtime.objects.len==0
		$if macos{assert C.mprotect(voidptr(base),page*2,C.PROT_READ)==-1}$else{mut residency:=[u8(0),0]!;assert C.mincore(voidptr(base),page*2,unsafe{&residency[0]})==-1};if _:=swiftui_text_view_arena_checked(){assert false}
	}
	println('IOS-SWIFTUI-TEXT-NOMINAL: eight cold readers, shared sealed nominal and View identity, native nongeneric signature, 32 complete direct/indirect symbolic and metadata lookups, bounded names at a protected boundary, protected contexts/arguments, exact routing, callbacks and two drained/unmapped lifetimes; SwiftUI Text construction, graph execution and rendering remain unsupported')
}

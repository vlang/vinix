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
const button_view_symbol='_$s7SwiftUI6ButtonVyxGAA4ViewAAMc'
type ButtonViewInstantiate=fn(u64,u64,u64)
type ButtonViewLookup=fn(u64,u64,u64)u64
fn button_view_relative(field u64)u64{mut bits:=u32(0);for i in u64(0)..4{bits|=u32(unsafe{*(&u8(field+i))})<<u32(i*8)};delta:=i32(bits);return if delta==0{u64(0)}else{u64(i64(field)+i64(delta))}}
fn button_view_indirect(field u64)u64{bits:=i32(read32(field));target:=u64(i64(field)+i64(bits&~1));return if bits&1!=0{read64(target)}else{target}}
fn button_view_text(address u64)string{return unsafe{(&char(address)).vstring()}}
fn button_view_resolve()u64{return runtime_symbol('/System/Library/Frameworks/SwiftUI.framework/SwiftUI',button_view_symbol) or {panic(err)}}
fn button_view_nominal()u64{return runtime_symbol('/System/Library/Frameworks/SwiftUI.framework/SwiftUI','_$s7SwiftUI6ButtonVMn') or {panic(err)}}
fn button_view_protection(address u64,length u64,executable bool){
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
fn button_view_signature(conformance u64,native bool){
	assert read32(conformance+12)==0x20000
	nominal:=button_view_relative(conformance+4);view:=button_view_indirect(conformance);module_descriptor:=button_view_relative(nominal+4)
	assert read32(nominal)==0xd1&&button_view_text(button_view_relative(nominal+8))=='Button'&&read32(module_descriptor)==0&&button_view_text(button_view_relative(module_descriptor+8))=='SwiftUI'
	assert read32(nominal+36)==0x10001&&read32(nominal+40)==2&&read32(nominal+44)==0x80&&read32(nominal+48)==0x80&&button_view_text(button_view_relative(nominal+52))=='x'&&button_view_indirect(nominal+56)==view
	assert read32(view)==0x30043&&button_view_text(button_view_relative(view+8))=='View'&&read32(view+12)==1&&read32(view+16)==6
	if native{assert button_view_relative(conformance+8)!=0&&read32(conformance+16)==0x10007&&read32(conformance+20)==0&&button_view_relative(conformance+24)!=0}else{
		assert nominal==button_view_nominal()&&conformance==nominal+320&&view==nominal+128
		assert read32(conformance+8)==0&&read32(conformance+16)==0x10000&&read32(conformance+24)==0
		assert button_view_relative(conformance+20)==ios_runtime.swiftui_button_nominal_arena+16
		button_view_protection(ios_runtime.swiftui_button_nominal_arena,32,true);button_view_protection(nominal,348,false)
	}
}
fn button_view_child(conformance u64,table u64,metadata u64,arguments u64,instantiate bool){
	mut fds:=[2]i32{};assert C.pipe(unsafe{&fds[0]})==0;pid:=C.ios_fork();assert pid>=0
	if pid==0{C.close(fds[0]);assert C.dup2(fds[1],2)==2;C.close(fds[1]);if instantiate{call:=unsafe{ButtonViewInstantiate(voidptr(button_view_relative(conformance+20)))};call(table,metadata,arguments)}else{lookup:=unsafe{ButtonViewLookup(voidptr(runtime_symbol('/usr/lib/swift/libswiftCore.dylib','_swift_getWitnessTable') or {panic(err)}))};lookup(conformance,metadata,arguments)};C._exit(0)}
	C.close(fds[1]);mut bytes:=[16384]u8{};mut length:=0
	for{assert length<bytes.len;count:=C.read(fds[0],unsafe{&bytes[length]},usize(bytes.len-length));if count==0{break};if count<0&&unsafe{*C.ios_errno_address()}==C.EINTR{continue};assert count>0;length+=int(count)}
	C.close(fds[0]);mut status:=i32(0);assert C.ios_waitpid(pid,&status,0)==pid&&status==256
	output:=unsafe{tos(&bytes[0],length)};assert output.contains(if instantiate{'iOS: SwiftUI Button View witness instantiation is not implemented'}else{'iOS: Swift generic/resilient/foreign witness lookup is not implemented'});for bad in ['runtime error:','AddressSanitizer','SIGSEGV','SIGBUS','Segmentation fault']!{assert !output.contains(bad),output}
}
fn button_view_rejection(conformance u64){
	page:=usize(C.getpagesize());guard:=u64(C.mmap(unsafe{nil},page,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));base:=u64(C.mmap(unsafe{nil},page*3,C.PROT_NONE,C.MAP_SHARED|C.MAP_ANONYMOUS,-1,0));assert guard!=u64(-1)&&base!=u64(-1);shared:=base+u64(page)
	for metadata in [u64(0),guard,1,~u64(0)]!{for arguments in [u64(0),guard,1,~u64(0)]!{
		for _ in 0..64{if _:=swift_witness_table_checked(conformance,metadata,arguments){assert false}else{assert err.msg()=='iOS: Swift generic/resilient/foreign witness lookup is not implemented'}}
		button_view_child(conformance,guard,metadata,arguments,false);button_view_child(conformance,guard,metadata,arguments,true)
		assert C.mprotect(voidptr(shared),page,C.PROT_READ|C.PROT_WRITE)==0;C.memset(voidptr(shared),0xa5,page)
		for writable in [true,false]!{assert C.mprotect(voidptr(shared),page,C.PROT_READ|if writable{C.PROT_WRITE}else{0})==0;for table in [shared,shared+u64(page)-128]!{button_view_child(conformance,table,metadata,arguments,true);for i in u64(0)..u64(page){assert unsafe{*(&u8(shared+i))}==0xa5}}}
	}}
	assert C.munmap(voidptr(guard),page)==0&&C.munmap(voidptr(base),page*3)==0
}
fn button_view_reader(nominal_first bool)u64{if nominal_first{assert read32(button_view_nominal())==0xd1};mut result:=u64(0);for _ in 0..128{candidate:=button_view_resolve();if result==0{result=candidate}else{assert result==candidate};assert button_view_relative(candidate+4)==button_view_nominal()};return result}
__global button_view_teardown_calls=0
fn button_view_teardown(object u64,selector &char){assert ios_runtime.swift_concurrency_retired;conformance:=button_view_resolve();assert read32(conformance+12)==0x20000&&button_view_relative(conformance+4)==button_view_nominal();button_view_teardown_calls++}
fn test_swiftui_button_view(){
	$if macos{library:=C.dlopen(c'/System/Library/Frameworks/SwiftUI.framework/SwiftUI',2);assert library!=unsafe{nil};descriptor:=u64(C.dlsym(library,c'$s7SwiftUI6ButtonVyxGAA4ViewAAMc'));assert descriptor!=0;button_view_signature(descriptor,true);assert C.dlclose(library)==0;println('NATIVE-SWIFTUI-BUTTON-VIEW: unconditional generic conformance, Label: View supplied by the nominal signature, seven copied witness words, no private or conditional arguments and no native instantiator')}
	if _:=swiftui_button_nominal_arena_checked(){assert false};page:=usize(C.getpagesize())
	for _ in 0..2{
		objc_start();assert ios_runtime.swiftui_button_nominal_arena==0&&!ios_runtime.swiftui_button_nominal_retired
		ios_runtime.swift_concurrency_retired=true;if _:=swiftui_button_nominal_arena_checked(){assert false};ios_runtime.swift_concurrency_retired=false
		for symbol in [button_view_symbol+'Extra',button_view_symbol.replace('$s7SwiftUI','$s11SwiftUICore'),button_view_symbol.replace('AAMc','AAWP'),'_$s7SwiftUI6ButtonVMa']!{if _:=swiftui_button_nominal_symbol(symbol){assert false}};assert ios_runtime.swiftui_button_nominal_arena==0
		mut workers:=[]thread u64{};for i in 0..8{workers<<spawn button_view_reader(i&1==0)};mut conformance:=u64(0);for i,worker in workers{candidate:=worker.wait();if i==0{conformance=candidate}else{assert conformance==candidate}};unsafe{workers.free()}
		button_view_signature(conformance,false);button_view_rejection(conformance)
		for library in ['/usr/lib/swift/libswiftCore.dylib','/System/Library/Frameworks/Foundation.framework/Foundation','/System/Library/Frameworks/SwiftUICore.framework/SwiftUICore']!{if _:=runtime_symbol(library,button_view_symbol){assert false}}
		assert ios_runtime.swiftui_modified_arena==0&&ios_runtime.swiftui_opacity_arena==0&&ios_runtime.swift_metadata_arena==0&&ios_runtime.swift_heap.len==0&&ios_runtime.swift_buffers.len==0&&ios_runtime.live==0
		cls:=objc_allocate_class(ios_runtime.names['NSObject'],c'VinixButtonViewTeardown',0);assert cls!=0&&objc_add_method(cls,u64(c'dealloc'),u64(unsafe{voidptr(button_view_teardown)}),c'v16@0:8');objc_register_class(cls);objc_autorelease(objc_new(cls))
		base:=ios_runtime.swiftui_button_nominal_arena;before:=button_view_teardown_calls;ios_runtime.swift_concurrency_retired=true;assert button_view_resolve()==conformance;objc_stop()
		assert button_view_teardown_calls==before+1&&ios_runtime.swiftui_button_nominal_arena==0&&ios_runtime.swiftui_button_nominal_retired&&ios_runtime.live==0&&ios_runtime.objects.len==0
		$if macos{assert C.mprotect(voidptr(base),page*2,C.PROT_READ)==-1}$else{mut residency:=[u8(0),0]!;assert C.mincore(voidptr(base),page*2,unsafe{&residency[0]})==-1};if _:=swiftui_button_nominal_arena_checked(){assert false}
	}
	println('IOS-SWIFTUI-BUTTON-VIEW: eight cold readers in both resolution orders, shared canonical nominal/protocol/conformance descriptors, native unconditional generic flags, zero pattern/private words and no writable cache, protected metadata and arguments rejected before pattern read, 192 child calls exit 1, unchanged shared writable/read-only table pages at both guard boundaries, explicit instantiator diagnostic, no metadata ownership, callback access and two drained/unmapped lifetimes; Button witness specialization, construction, graph execution and rendering remain unsupported')
}

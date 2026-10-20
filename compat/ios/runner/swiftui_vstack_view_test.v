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
const vstack_view_symbol='_$s7SwiftUI6VStackVyxGAA4ViewAAMc'
type VStackViewLookup=fn(u64,u64,u64)u64
type VStackViewBody=fn(u64,u64,u64)u64
type VStackViewProbe=fn(&u64,u64,&u64)
fn vstack_view_relative(field u64)u64{mut bits:=u32(0);for i in u64(0)..4{bits|=u32(unsafe{*(&u8(field+i))})<<u32(i*8)};delta:=i32(bits);return if delta==0{u64(0)}else{u64(i64(field)+i64(delta))}}
fn vstack_view_indirect(field u64)u64{bits:=i32(read32(field));target:=u64(i64(field)+i64(bits&~1));return if bits&1!=0{read64(target)}else{target}}
fn vstack_view_text(address u64)string{return unsafe{(&char(address)).vstring()}}
fn vstack_view_resolve()u64{return runtime_symbol('/System/Library/Frameworks/SwiftUI.framework/SwiftUI',vstack_view_symbol) or {panic(err)}}
fn vstack_view_nominal()u64{return runtime_symbol('/System/Library/Frameworks/SwiftUI.framework/SwiftUI','_$s7SwiftUI6VStackVMn') or {panic(err)}}
fn vstack_view_protection(address u64,length u64,executable bool){
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
fn vstack_view_signature(conformance u64,native bool){
	assert read32(conformance+12)==0
	nominal:=vstack_view_relative(conformance+4);view:=vstack_view_indirect(conformance);module_descriptor:=vstack_view_relative(nominal+4)
	assert read32(nominal)==0xd1&&vstack_view_text(vstack_view_relative(nominal+8))=='VStack'&&read32(module_descriptor)==0&&vstack_view_text(vstack_view_relative(module_descriptor+8))=='SwiftUI'
	assert read32(nominal+20)==1&&read32(nominal+24)==4&&read32(nominal+36)==0x10001&&read32(nominal+40)==2&&read32(nominal+44)==0x80&&read32(nominal+48)==0x80&&vstack_view_text(vstack_view_relative(nominal+52))=='x'&&vstack_view_indirect(nominal+56)==view
	assert read32(view)==0x30043&&vstack_view_text(vstack_view_relative(view+8))=='View'&&read32(view+12)==1&&read32(view+16)==6
	table:=vstack_view_relative(conformance+8);assert table!=0&&read64(table)==conformance&&read64(table+8)&1==1&&read64(table+16)&1==1
	record:=read64(table+8)&~u64(1);type_name:=read64(table+16)&~u64(1);assert unsafe{*(&u8(record))}==0xff&&unsafe{*(&u8(record+1))}==7&&unsafe{*(&u8(type_name))}==2
	never:=read64(vstack_view_relative(type_name+1));assert read32(never)==0x52&&vstack_view_text(vstack_view_relative(never+8))=='Never'&&vstack_view_text(vstack_view_relative(vstack_view_relative(never+4)+8))=='Swift'
	if !native{
		base:=ios_runtime.swiftui_vstack_nominal_arena
		assert nominal==vstack_view_nominal()&&conformance==nominal+320&&view==nominal+128&&table==nominal+352&&record==nominal+416&&type_name==nominal+432&&never==nominal+448
		assert vstack_view_relative(record+2)==base+48&&vstack_view_relative(never+12)==base+16
		for i in u64(3)..7{assert read64(table+i*8)==base+32}
		vstack_view_protection(base,64,true);vstack_view_protection(nominal,520,false)
	}
}
fn vstack_view_child(conformance u64,slot u64,metadata u64,arguments u64,guard u64,result u64,probe VStackViewProbe){
	mut fds:=[2]i32{};assert C.pipe(unsafe{&fds[0]})==0;pid:=C.ios_fork();assert pid>=0
	if pid==0{
		C.close(fds[0]);assert C.dup2(fds[1],2)==2;C.close(fds[1]);table:=vstack_view_relative(conformance+8);view:=vstack_view_indirect(conformance)
		if slot==7{swift_mangled_lookup_request_checked(0xff,read64(table+16)&~u64(1),5,metadata,arguments) or {panic(err)}}
		else if slot>=3{input:=[metadata,arguments,guard,guard,guard,guard,guard,guard,guard,guard,result,guard,guard]!;mut output:=[6]u64{};probe(unsafe{&input[0]},read64(table+slot*8),unsafe{&output[0]})}
		else if slot==1{record:=read64(table+8)&~u64(1);call:=unsafe{VStackViewBody(voidptr(vstack_view_relative(record+2)))};call(guard,metadata,arguments)}
		else{swift_associated_type(0x1ff,table,metadata,view+28,view+44)}
		C._exit(0)
	}
	C.close(fds[1]);mut bytes:=[16384]u8{};mut length:=0
	for{assert length<bytes.len;count:=C.read(fds[0],unsafe{&bytes[length]},usize(bytes.len-length));if count==0{break};if count<0&&unsafe{*C.ios_errno_address()}==C.EINTR{continue};assert count>0;length+=int(count)}
	C.close(fds[0]);mut status:=i32(0);assert C.ios_waitpid(pid,&status,0)==pid&&status==256
	output:=unsafe{tos(&bytes[0],length)};expected:=if slot==7{'iOS: SwiftUI VStack Body Never metadata is not implemented'}else if slot>=3{'iOS: SwiftUI VStack View graph operations are not implemented'}else if slot==1{'iOS: SwiftUI VStack Body Never View conformance is not implemented'}else{'iOS: Swift associated-type mangled name is not implemented'}
	assert output.contains(expected);for bad in ['runtime error:','AddressSanitizer','SIGSEGV','SIGBUS','Segmentation fault']!{assert !output.contains(bad),output}
}
fn vstack_view_rejection(conformance u64){
	page:=usize(C.getpagesize());guard:=u64(C.mmap(unsafe{nil},page,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));base:=u64(C.mmap(unsafe{nil},page*3,C.PROT_NONE,C.MAP_SHARED|C.MAP_ANONYMOUS,-1,0));code:=u64(C.mmap(unsafe{nil},page,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert guard!=u64(-1)&&base!=u64(-1)&&code!=u64(-1);shared:=base+u64(page)
	for i,op in [u32(0xa9bc7bfd),0xa90153f3,0xa9025bf5,0xaa0003f1,0xaa0103f0,0xaa0203f3,0xd10043ff,0xa9400620,0xa9410e22,0xa9421624,0xa9431e26,0xa9442a29,0xa9002be9,0xf9402a28,0xf9402e34,0xf9403235,0xd63f0200,0xa9000660,0xa9010e62,0xa9025674,0x910043ff,0xa9425bf5,0xa94153f3,0xa8c47bfd,0xd65f03c0]!{write32(code+u64(i*4),op)}
	C.__builtin___clear_cache(voidptr(code),voidptr(code+100));assert C.mprotect(voidptr(code),page,C.PROT_READ|C.PROT_EXEC)==0;probe:=unsafe{VStackViewProbe(voidptr(code))}
	table:=vstack_view_relative(conformance+8);lookup:=unsafe{VStackViewLookup(voidptr(runtime_symbol('/usr/lib/swift/libswiftCore.dylib','_swift_getWitnessTable') or {panic(err)}))}
	for metadata in [u64(0),guard,1,~u64(0)]!{for arguments in [u64(0),guard,1,~u64(0)]!{
		for _ in 0..64{assert (swift_witness_table_checked(conformance,metadata,arguments) or {panic(err)})==table&&lookup(conformance,metadata,arguments)==table}
		for slot in [u64(1),2,3,4,5,6,7]!{vstack_view_child(conformance,slot,metadata,arguments,guard,guard,probe)}
	}}
	assert C.mprotect(voidptr(shared),page,C.PROT_READ|C.PROT_WRITE)==0;C.memset(voidptr(shared),0xa5,page)
	for writable in [true,false]!{assert C.mprotect(voidptr(shared),page,C.PROT_READ|if writable{C.PROT_WRITE}else{0})==0;for result in [shared,shared+u64(page)-128]!{for slot in u64(3)..7{vstack_view_child(conformance,slot,guard,guard,guard,result,probe);for i in u64(0)..u64(page){assert unsafe{*(&u8(shared+i))}==0xa5}}}}
	assert C.munmap(voidptr(code),page)==0&&C.munmap(voidptr(guard),page)==0&&C.munmap(voidptr(base),page*3)==0
}
fn vstack_view_reader(nominal_first bool)u64{if nominal_first{assert read32(vstack_view_nominal())==0xd1};mut result:=u64(0);for _ in 0..128{candidate:=vstack_view_resolve();if result==0{result=candidate}else{assert result==candidate};assert vstack_view_relative(candidate+4)==vstack_view_nominal()};return result}
__global vstack_view_teardown_calls=0
fn vstack_view_teardown(object u64,selector &char){assert ios_runtime.swift_concurrency_retired;conformance:=vstack_view_resolve();assert read32(conformance+12)==0&&vstack_view_relative(conformance+4)==vstack_view_nominal();vstack_view_teardown_calls++}
fn test_swiftui_vstack_view(){
	$if macos{library:=C.dlopen(c'/System/Library/Frameworks/SwiftUI.framework/SwiftUI',2);assert library!=unsafe{nil};descriptor:=u64(C.dlsym(library,c'$s7SwiftUI6VStackVyxGAA4ViewAAMc'));assert descriptor!=0;vstack_view_signature(descriptor,true);assert C.dlclose(library)==0;println('NATIVE-SWIFTUI-VSTACK-VIEW: unconditional static seven-word table, Content: View supplied by the nominal signature, tagged Body Never and conformance accessor; no generic witness control')}
	if _:=swiftui_vstack_nominal_arena_checked(){assert false};page:=usize(C.getpagesize())
	for _ in 0..2{
		objc_start();assert ios_runtime.swiftui_vstack_nominal_arena==0&&!ios_runtime.swiftui_vstack_nominal_retired
		ios_runtime.swift_concurrency_retired=true;if _:=swiftui_vstack_nominal_arena_checked(){assert false};ios_runtime.swift_concurrency_retired=false
		for symbol in [vstack_view_symbol+'Extra',vstack_view_symbol.replace('$s7SwiftUI','$s11SwiftUICore'),vstack_view_symbol.replace('AAMc','AAWP'),'_$s7SwiftUI6VStackVMa']!{if _:=swiftui_vstack_nominal_symbol(symbol){assert false}};assert ios_runtime.swiftui_vstack_nominal_arena==0
		mut workers:=[]thread u64{};for i in 0..8{workers<<spawn vstack_view_reader(i&1==0)};mut conformance:=u64(0);for i,worker in workers{candidate:=worker.wait();if i==0{conformance=candidate}else{assert conformance==candidate}};unsafe{workers.free()}
		vstack_view_signature(conformance,false);vstack_view_rejection(conformance)
		for library in ['/usr/lib/swift/libswiftCore.dylib','/System/Library/Frameworks/Foundation.framework/Foundation','/System/Library/Frameworks/SwiftUICore.framework/SwiftUICore']!{if _:=runtime_symbol(library,vstack_view_symbol){assert false}}
		assert ios_runtime.swiftui_modified_arena==0&&ios_runtime.swiftui_opacity_arena==0&&ios_runtime.swift_metadata_arena==0&&ios_runtime.swift_heap.len==0&&ios_runtime.swift_buffers.len==0&&ios_runtime.live==0
		cls:=objc_allocate_class(ios_runtime.names['NSObject'],c'VinixVStackViewTeardown',0);assert cls!=0&&objc_add_method(cls,u64(c'dealloc'),u64(unsafe{voidptr(vstack_view_teardown)}),c'v16@0:8');objc_register_class(cls);objc_autorelease(objc_new(cls))
		base:=ios_runtime.swiftui_vstack_nominal_arena;before:=vstack_view_teardown_calls;ios_runtime.swift_concurrency_retired=true;assert vstack_view_resolve()==conformance;objc_stop()
		assert vstack_view_teardown_calls==before+1&&ios_runtime.swiftui_vstack_nominal_arena==0&&ios_runtime.swiftui_vstack_nominal_retired&&ios_runtime.live==0&&ios_runtime.objects.len==0
		$if macos{assert C.mprotect(voidptr(base),page*2,C.PROT_READ)==-1}$else{mut residency:=[u8(0),0]!;assert C.mincore(voidptr(base),page*2,unsafe{&residency[0]})==-1};if _:=swiftui_vstack_nominal_arena_checked(){assert false}
	}
	println('IOS-SWIFTUI-VSTACK-VIEW: eight cold readers in both resolution orders, shared canonical nominal/protocol/conformance descriptors, native static table and tagged symbolic Never, protected unused metadata/arguments, 256 child calls exit 1, protected graph stack/Self/x8, unchanged shared writable/read-only result pages at both guard boundaries, terminal graph/body/metadata diagnostics, no metadata ownership, callback access and two drained/unmapped lifetimes; VStack construction, Body Never metadata/conformance, graph execution and rendering remain unsupported')
}

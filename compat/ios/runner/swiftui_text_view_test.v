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
type TextViewMetadata = fn (u64)SwiftAssociatedMetadata
type TextViewGraph = fn (u64,u64,u64,u64)
type TextViewBody = fn (u64,u64,u64)u64
type TextViewLookup = fn (u64,u64,u64)u64
fn text_view_relative(field u64)u64{mut bits:=u32(0);for i in u64(0)..4{bits|=u32(unsafe{*(&u8(field+i))})<<(i*8)};delta:=i32(bits);return if delta==0{u64(0)}else{u64(i64(field)+i64(delta))}}
fn text_view_indirect(field u64)u64{bits:=i32(read32(field));p:=u64(i64(field)+i64(bits&~1));return if bits&1!=0{read64(p)}else{p}}
fn text_view_text(p u64)string{return unsafe{(&char(p)).vstring()}}
fn text_view_resolve()u64{return read64(runtime_symbol('/System/Library/Frameworks/SwiftUI.framework/SwiftUI','_$s7SwiftUI4TextVAA4ViewAAWP') or {panic(err)})}
fn text_view_nominal()u64{descriptor:=runtime_symbol('/System/Library/Frameworks/SwiftUI.framework/SwiftUI','_$s7SwiftUI4TextVMn') or {panic(err)};assert descriptor==read64(text_view_relative(text_view_resolve()+4));return descriptor}
fn text_view_protection(address u64,length u64,executable bool){
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
fn text_view_signature(conformance u64,native bool){
 assert read32(conformance+12)==8
 nominal:=read64(text_view_relative(conformance+4));view:=text_view_indirect(conformance)
 assert read32(nominal)==0x51&&text_view_text(text_view_relative(nominal+8))=='Text'
 module_descriptor:=text_view_relative(nominal+4);assert read32(module_descriptor)==0&&text_view_text(text_view_relative(module_descriptor+8))=='SwiftUI'
 assert read32(nominal+20)==2&&read32(nominal+24)==2
 assert read32(view)==0x30043&&read32(view+12)==1&&read32(view+16)==6
 assert text_view_text(text_view_relative(view+8))=='View'&&text_view_text(text_view_relative(view+20))=='Body'&&read32(view+24)==0x80&&text_view_indirect(view+32)==view
 for j,flag in [u32(0xcade0008),0x4b5f0007,0xaeaf0001,0x6ddd0001,0x4cbb0001,0xd1fd0013]!{assert read32(view+36+u64(j*8))==flag}
 table:=text_view_relative(conformance+8);assert table!=0&&read64(table)==conformance
 assert read64(table+8)&1!=0&&read64(table+16)&1!=0
 record:=read64(table+8)&~u64(1);assert unsafe{*(&u8(record))}==0xff&&unsafe{*(&u8(record+1))}==7
 type_name:=read64(table+16)&~u64(1);assert unsafe{*(&u8(type_name))}==2
 never:=read64(text_view_relative(type_name+1));assert read32(never)==0x52&&text_view_text(text_view_relative(never+8))=='Never'
 if !native{
  base:=ios_runtime.swiftui_text_view_arena;data:=base+u64(C.getpagesize())
  assert nominal==data&&conformance==data+352&&table==data+384&&never==data+112&&view==data+208
  assert read64(table+8)==((data+448)|1)&&read64(table+16)==((data+464)|1)&&text_view_relative(record+2)==base+48
  assert text_view_relative(nominal+12)==base&&text_view_relative(never+12)==base+16
  for i in u64(3)..7{assert read64(table+i*8)==base+32}
  path:=text_view_relative(view+28);for j,byte in [u8(`4`),`B`,`o`,`d`,`y`,2]!{assert unsafe{*(&u8(path+u64(j)))}==byte}
  assert read64(text_view_relative(path+6))==view&&text_view_text(path+10)=='Qz'
  for j in u64(0)..6{assert read32(view+40+j*8)==0}
  for offset in [u64(16),128]!{assert read32(data+offset)==0}
  text_view_protection(base,64,true);text_view_protection(data,488,false)
 }
}
fn text_view_rejection(conformance u64){
 page:=usize(C.getpagesize());guard:=u64(C.mmap(unsafe{nil},page,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert guard!=u64(-1)
 table:=text_view_relative(conformance+8);modifier:=text_view_indirect(conformance)
 lookup:=unsafe{TextViewLookup(voidptr(runtime_symbol('/usr/lib/swift/libswiftCore.dylib','_swift_getWitnessTable') or {panic(err)}))}
 for metadata in [u64(0),guard,~u64(0)]!{for _ in 0..64{assert swift_witness_table_checked(conformance,metadata,guard) or {panic(err)}==table;assert lookup(conformance,metadata,guard)==table}}
 for slot in [u64(3),4,5,6,1,2,0,7]!{
  mut fds:=[2]i32{};assert C.pipe(unsafe{&fds[0]})==0;pid:=C.ios_fork();assert pid>=0
  if pid==0{
   C.close(fds[0]);assert C.dup2(fds[1],2)==2;C.close(fds[1])
   if slot==7{swift_mangled_lookup_request_checked(0xff,read64(table+16)&~u64(1),5,guard,guard) or {panic(err)}}
   else if slot>=3{call:=unsafe{TextViewGraph(voidptr(read64(table+slot*8)))};call(guard,guard,guard,guard)}
   else if slot==1{record:=read64(table+8)&~u64(1);call:=unsafe{TextViewBody(voidptr(text_view_relative(record+2)))};call(guard,guard,guard)}
   else if slot==0{call:=unsafe{TextViewMetadata(voidptr(text_view_relative(text_view_nominal()+12)))};call(~u64(0))}
   else{swift_associated_type(0x1ff,table,guard,modifier+28,modifier+44)}
   C._exit(0)
  }
  C.close(fds[1]);mut bytes:=[16384]u8{};mut length:=0
  for{assert length<bytes.len;count:=C.read(fds[0],unsafe{&bytes[length]},usize(bytes.len-length));if count==0{break};if count<0&&unsafe{*C.ios_errno_address()}==C.EINTR{continue};assert count>0;length+=int(count)}
  C.close(fds[0]);mut status:=i32(0);assert C.ios_waitpid(pid,&status,0)==pid&&status==256
  output:=unsafe{tos(&bytes[0],length)}
  expected:=if slot==7{'iOS: SwiftUI Text Body Never metadata is not implemented'}else if slot>=3{'iOS: SwiftUI Text View graph operations are not implemented'}else if slot==1{'iOS: SwiftUI Text Body Never View conformance is not implemented'}else if slot==0{'iOS: SwiftUI Text metadata and value ownership are not implemented'}else{'iOS: Swift associated-type mangled name is not implemented'}
  assert output.contains(expected)&&!output.contains('runtime error:')&&!output.contains('AddressSanitizer')
 }
 assert read64(table+16)&1!=0&&C.munmap(voidptr(guard),page)==0
}
fn text_view_reader()u64{mut result:=u64(0);for _ in 0..128{candidate:=text_view_resolve();if result==0{result=candidate}else{assert result==candidate};assert read64(text_view_relative(candidate+4))==text_view_nominal();assert swift_witness_table(candidate,~u64(0),~u64(0))==text_view_relative(candidate+8)};return result}
__global text_view_teardown_calls=0
fn text_view_teardown(object u64,selector &char){assert ios_runtime.swift_concurrency_retired;conformance:=text_view_resolve();assert read32(conformance+12)==8&&read64(text_view_relative(conformance+4))==text_view_nominal();text_view_teardown_calls++}
fn test_swiftui_text_view(){
	$if macos{
		library:=C.dlopen(c'/System/Library/Frameworks/SwiftUI.framework/SwiftUI',2);assert library!=unsafe{nil};descriptor:=read64(u64(C.dlsym(library,c'$s7SwiftUI4TextVAA4ViewAAWP')));assert descriptor!=0;text_view_signature(descriptor,true);assert C.dlclose(library)==0
		println('NATIVE-SWIFTUI-TEXT-VIEW: seven-word table, indirect Text nominal flags 8, native six-slot View signature and symbolic Never Body')
	}
	if _:=swiftui_text_view_arena_checked(){assert false};page:=usize(C.getpagesize())
	for _ in 0..2{
		objc_start();assert ios_runtime.swiftui_text_view_arena==0&&!ios_runtime.swiftui_text_view_retired
		ios_runtime.swift_concurrency_retired=true;if _:=swiftui_text_view_arena_checked(){assert false};ios_runtime.swift_concurrency_retired=false
		for symbol in ['_$s7SwiftUI4TextVN','_$s7SwiftUI4TextVMnExtra','_$s7SwiftUI4TextVAA4ViewAAMc','_$s7SwiftUI4TextVMa','_$s7SwiftUI4TextVAA4ViewAAWPExtra','_$s11SwiftUICore4TextVAA4ViewAAWP']!{if _:=swiftui_text_view_symbol(symbol){assert false}};assert ios_runtime.swiftui_text_view_arena==0
		mut workers:=[]thread u64{};for _ in 0..8{workers<<spawn text_view_reader()};mut conformance:=u64(0);for i,worker in workers{candidate:=worker.wait();if i==0{conformance=candidate}else{assert conformance==candidate}};unsafe{workers.free()}
		text_view_signature(conformance,false);text_view_rejection(conformance)
		for library in ['/usr/lib/swift/libswiftCore.dylib','/System/Library/Frameworks/Foundation.framework/Foundation','/System/Library/Frameworks/SwiftUICore.framework/SwiftUICore']!{if _:=runtime_symbol(library,'_$s7SwiftUI4TextVAA4ViewAAWP'){assert false}}
		assert ios_runtime.swiftui_opacity_arena==0&&ios_runtime.swift_void_arena==0&&ios_runtime.swift_array_arena==0&&ios_runtime.swift_metadata_arena==0&&ios_runtime.swift_heap.len==0&&ios_runtime.swift_buffers.len==0&&ios_runtime.live==0
		cls:=objc_allocate_class(ios_runtime.names['NSObject'],c'VinixTextViewTeardown',0);assert cls!=0&&objc_add_method(cls,u64(c'dealloc'),u64(unsafe{voidptr(text_view_teardown)}),c'v16@0:8');objc_register_class(cls);objc_autorelease(objc_new(cls))
		base:=ios_runtime.swiftui_text_view_arena;before:=text_view_teardown_calls;ios_runtime.swift_concurrency_retired=true;assert text_view_resolve()==conformance;objc_stop()
		assert text_view_teardown_calls==before+1&&ios_runtime.swiftui_text_view_arena==0&&ios_runtime.swiftui_text_view_retired&&ios_runtime.live==0&&ios_runtime.objects.len==0
		$if macos{assert C.mprotect(voidptr(base),page*2,C.PROT_READ)==-1}$else{mut residency:=[u8(0),0]!;assert C.mincore(voidptr(base),page*2,unsafe{&residency[0]})==-1};if _:=swiftui_text_view_arena_checked(){assert false}
	}
	println('IOS-SWIFTUI-TEXT-VIEW: eight cold readers, native seven-word table and indirect Text identity, tagged symbolic Never and conformance data, sealed RX/RO pages, protected unused metadata and arguments, 16 terminal graph/body/metadata child probes, exact framework routing, callbacks and two drained/unmapped lifetimes; Text metadata/value ownership and rendering remain unsupported')
}

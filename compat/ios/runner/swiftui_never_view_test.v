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
const never_view_symbol='_$ss5NeverO7SwiftUI4ViewACWP'
type NeverViewLookup=fn(u64,u64,u64)u64
type NeverViewBody=fn(u64,u64,u64)u64
type NeverViewProbe=fn(&u64,u64,&u64)
type NeverViewAssociated=fn(u64,u64,u64,u64,u64)SwiftAssociatedMetadata
type NeverViewConform=fn(u64,u64,u64,u64,u64)u64
type NeverViewAccess=fn(u64)SwiftAssociatedMetadata
fn never_view_relative(field u64)u64{mut bits:=u32(0);for i in u64(0)..4{bits|=u32(unsafe{*(&u8(field+i))})<<u32(i*8)};delta:=i32(bits);return if delta==0{u64(0)}else{u64(i64(field)+i64(delta))}}
fn never_view_indirect(field u64)u64{bits:=i32(read32(field));target:=u64(i64(field)+i64(bits&~1));return if bits&1!=0{read64(target)}else{target}}
fn never_view_text(address u64)string{return unsafe{(&char(address)).vstring()}}
fn never_view_resolve()u64{return runtime_symbol('/System/Library/Frameworks/SwiftUI.framework/SwiftUI',never_view_symbol) or {panic(err)}}
fn never_view_opacity()u64{return runtime_symbol('/System/Library/Frameworks/SwiftUI.framework/SwiftUI','_$s7SwiftUI14_OpacityEffectVAA12ViewModifierAAWP') or {panic(err)}}
fn never_view_protection(address u64,length u64,executable bool){
	$if macos{mut start:=address;mut size:=u64(0);mut info:=[16]i32{};mut count:=u32(C.VM_REGION_BASIC_INFO_COUNT_64);mut object:=u32(0);task:=C.mach_task_self();assert C.vm_region_64(task,&start,&size,C.VM_REGION_BASIC_INFO_64,unsafe{&info[0]},&count,&object)==0;assert start<=address&&address+length<=start+size&&info[0]==(C.PROT_READ|if executable{C.PROT_EXEC}else{0});if object!=0{assert C.mach_port_deallocate(task,object)==0}}
	$else{mut found:=false;for line in (os.read_file('/proc/self/maps') or {panic(err)}).split_into_lines(){fields:=line.fields();if fields.len<2{continue};range:=fields[0].split('-');if range.len!=2{continue};start:=strconv.parse_uint(range[0],16,64) or {panic(err)};end:=strconv.parse_uint(range[1],16,64) or {panic(err)};if address>=start&&address<end{assert address+length<=end&&fields[1]==if executable{'r-xp'}else{'r--p'};found=true;break}};assert found}
}
fn never_view_signature(table u64,native bool){
	conformance:=read64(table);assert read32(conformance+12)==8&&never_view_relative(conformance+8)==table
	descriptor:=read64(never_view_relative(conformance+4));view:=never_view_indirect(conformance)
	assert read32(descriptor)==0x52&&never_view_text(never_view_relative(descriptor+8))=='Never'&&read32(descriptor+20)==0&&read32(descriptor+24)==0
	assert never_view_text(never_view_relative(never_view_relative(descriptor+4)+8))=='Swift'
	assert read32(view)==0x30043&&never_view_text(never_view_relative(view+8))=='View'&&read32(view+12)==1&&read32(view+16)==6&&read32(view+24)==0x80
	assert never_view_text(never_view_relative(view+20))=='Body'&&never_view_indirect(view+32)==view
	for i,flags in [u32(0xcade0008),0x4b5f0007,0xaeaf0001,0x6ddd0001,0x4cbb0001,0xd1fd0013]!{assert read32(view+36+u64(i*8))==flags}
	record:=read64(table+8)&~u64(1);assert read64(table+8)&1==1&&unsafe{*(&u8(record))}==0xff&&unsafe{*(&u8(record+1))}==7
	if native{type_name:=read64(table+16)&~u64(1);assert read64(table+16)&1==1&&unsafe{*(&u8(type_name))}==2&&read64(never_view_relative(type_name+1))==descriptor}
	else{
		base:=ios_runtime.swiftui_opacity_arena;data:=base+u64(C.getpagesize());metadata:=read64(table+16)
		assert table==data+960&&conformance==data+944&&descriptor==data+384&&view==data+640&&record==data+1024&&never_view_relative(record+2)==base+160
		assert metadata==data+264&&read64(never_view_opacity()+16)==metadata&&read64(metadata)==0x201&&read64(metadata+8)==descriptor
		witness:=read64(metadata-8);assert witness==data+288&&read64(witness+64)==0&&read64(witness+72)==1&&read32(witness+80)==0&&read32(witness+84)==0
		assert read64(table+24)==base+192&&read64(table+32)==base+192&&read64(table+40)==base+176&&read64(table+48)==base+208
		accessor:=unsafe{NeverViewAccess(voidptr(never_view_relative(descriptor+12)))};for request in [u64(0),0xff,0x1ff,~u64(0)]!{result:=accessor(request);assert result.metadata==metadata&&result.state==0}
		never_view_protection(base,224,true);never_view_protection(data,1048,false)
	}
}
fn never_view_count(table u64,metadata u64,arguments u64,guard u64,result u64,probe NeverViewProbe){
	input:=[guard,metadata,arguments,guard,guard,guard,guard,guard,guard,guard,result,u64(0x5020),0x5021]!;mut output:=[6]u64{};probe(unsafe{&input[0]},read64(table+40),unsafe{&output[0]});assert output[0]==0&&output[1]==1&&output[4]==0x5020&&output[5]==0x5021
}
fn never_view_child(table u64,slot u64,metadata u64,arguments u64,guard u64,result u64,probe NeverViewProbe){
	mut fds:=[2]i32{};assert C.pipe(unsafe{&fds[0]})==0;pid:=C.ios_fork();assert pid>=0
	if pid==0{C.close(fds[0]);assert C.dup2(fds[1],2)==2;C.close(fds[1]);input:=[metadata,arguments,guard,guard,guard,guard,guard,guard,guard,guard,result,guard,guard]!;mut output:=[6]u64{};probe(unsafe{&input[0]},read64(table+slot*8),unsafe{&output[0]});C._exit(0)}
	C.close(fds[1]);mut bytes:=[16384]u8{};mut length:=0;for{assert length<bytes.len;count:=C.read(fds[0],unsafe{&bytes[length]},usize(bytes.len-length));if count==0{break};if count<0&&unsafe{*C.ios_errno_address()}==C.EINTR{continue};assert count>0;length+=int(count)}
	C.close(fds[0]);mut status:=i32(0);assert C.ios_waitpid(pid,&status,0)==pid&&status==256
	output:=unsafe{tos(&bytes[0],length)};assert output.contains(if slot==6{'iOS: SwiftUI Never.body must not be called'}else{'iOS: SwiftUI Never View graph construction is not implemented'});for bad in ['runtime error:','AddressSanitizer','SIGSEGV','SIGBUS','Segmentation fault']!{assert !output.contains(bad),output}
}
fn never_view_operations(table u64,probe NeverViewProbe,native_table u64){
	page:=usize(C.getpagesize());guard:=u64(C.mmap(unsafe{nil},page,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));base:=u64(C.mmap(unsafe{nil},page*3,C.PROT_NONE,C.MAP_SHARED|C.MAP_ANONYMOUS,-1,0));assert guard!=u64(-1)&&base!=u64(-1);shared:=base+u64(page)
	conformance:=read64(table);view:=never_view_indirect(conformance);body:=read64(table+16);record:=read64(table+8)&~u64(1);body_witness:=unsafe{NeverViewBody(voidptr(never_view_relative(record+2)))}
	lookup:=unsafe{NeverViewLookup(voidptr(runtime_symbol('/usr/lib/swift/libswiftCore.dylib','_swift_getWitnessTable') or {panic(err)}))}
	for metadata in [u64(0),guard,1,~u64(0)]!{for arguments in [u64(0),guard,1,~u64(0)]!{
		for request in [u64(0),0xff,0x1ff,~u64(0)]!{for _ in 0..16{assert (swift_witness_table_checked(conformance,metadata,arguments) or {panic(err)})==table&&lookup(conformance,metadata,arguments)==table;associated:=swift_associated_type(request,table,metadata,view+28,view+44);assert associated.metadata==body&&associated.state==0&&body_witness(guard,metadata,arguments)==table}}
		never_view_count(table,metadata,arguments,guard,guard,probe);if native_table!=0{never_view_count(native_table,metadata,arguments,guard,guard,probe)}
		for slot in [u64(3),4,6]!{never_view_child(table,slot,metadata,arguments,guard,guard,probe)}
	}}
	assert C.mprotect(voidptr(shared),page,C.PROT_READ|C.PROT_WRITE)==0;C.memset(voidptr(shared),0xa5,page)
	for writable in [true,false]!{assert C.mprotect(voidptr(shared),page,C.PROT_READ|if writable{C.PROT_WRITE}else{0})==0;for result in [shared,shared+u64(page)-128]!{never_view_count(table,guard,guard,guard,result,probe);if native_table!=0{never_view_count(native_table,guard,guard,guard,result,probe)};for slot in [u64(3),4,6]!{never_view_child(table,slot,guard,guard,guard,result,probe)};for i in u64(0)..u64(page){assert unsafe{*(&u8(shared+i))}==0xa5}}}
	assert C.munmap(voidptr(guard),page)==0&&C.munmap(voidptr(base),page*3)==0
}
fn never_view_reader(opacity_first bool)u64{if opacity_first{assert never_view_opacity()!=0};mut result:=u64(0);for _ in 0..128{candidate:=never_view_resolve();if result==0{result=candidate}else{assert result==candidate};assert read64(candidate+16)==read64(never_view_opacity()+16)};return result}
__global never_view_teardown_calls=0
fn never_view_teardown(object u64,selector &char){assert ios_runtime.swift_concurrency_retired;table:=never_view_resolve();view:=never_view_indirect(read64(table));assert swift_associated_type(0,table,0,view+28,view+44).metadata==read64(never_view_opacity()+16);never_view_teardown_calls++}
fn test_swiftui_never_view(){
	page:=usize(C.getpagesize());code:=u64(C.mmap(unsafe{nil},page,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert code!=u64(-1)
	for i,op in [u32(0xa9bc7bfd),0xa90153f3,0xa9025bf5,0xaa0003f1,0xaa0103f0,0xaa0203f3,0xd10043ff,0xa9400620,0xa9410e22,0xa9421624,0xa9431e26,0xa9442a29,0xa9002be9,0xf9402a28,0xf9402e34,0xf9403235,0xd63f0200,0xa9000660,0xa9010e62,0xa9025674,0x910043ff,0xa9425bf5,0xa94153f3,0xa8c47bfd,0xd65f03c0]!{write32(code+u64(i*4),op)}
	C.__builtin___clear_cache(voidptr(code),voidptr(code+100));assert C.mprotect(voidptr(code),page,C.PROT_READ|C.PROT_EXEC)==0;probe:=unsafe{NeverViewProbe(voidptr(code))}
	mut native_table:=u64(0);mut core:=unsafe{voidptr(0)};mut library:=unsafe{voidptr(0)}
	$if macos{library=C.dlopen(c'/System/Library/Frameworks/SwiftUI.framework/SwiftUI',2);core=C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',2);assert library!=unsafe{nil}&&core!=unsafe{nil};native_table=u64(C.dlsym(library,c'$ss5NeverO7SwiftUI4ViewACWP'));assert native_table!=0;never_view_signature(native_table,true);println('NATIVE-SWIFTUI-NEVER-VIEW: static seven-word table, indirect Never descriptor flags 8, Body Never and recursive Body:View, view-list count nil')}
	if _:=swiftui_opacity_arena_checked(){assert false}
	for _ in 0..2{
		objc_start();assert ios_runtime.swiftui_opacity_arena==0&&!ios_runtime.swiftui_opacity_retired;ios_runtime.swift_concurrency_retired=true;if _:=swiftui_opacity_arena_checked(){assert false};ios_runtime.swift_concurrency_retired=false
		for symbol in [never_view_symbol+'Extra',never_view_symbol.replace('7SwiftUI','11SwiftUICore'),never_view_symbol.replace('ACWP','ACMc') ]!{if _:=swiftui_opacity_symbol(symbol){assert false}};assert ios_runtime.swiftui_opacity_arena==0
		mut workers:=[]thread u64{};for i in 0..8{workers<<spawn never_view_reader(i&1==0)};mut table:=u64(0);for i,worker in workers{candidate:=worker.wait();if i==0{table=candidate}else{assert table==candidate}};unsafe{workers.free()}
		never_view_signature(table,false);never_view_operations(table,probe,native_table)
		$if macos{
			view:=never_view_indirect(read64(table));associated:=unsafe{NeverViewAssociated(C.dlsym(core,c'swift_getAssociatedTypeWitness'))};conform:=unsafe{NeverViewConform(C.dlsym(core,c'swift_getAssociatedConformanceWitness'))};body:=read64(table+16)
			// Native Swift caches and authenticates associated conformances in
			// the witness slot. Give that runtime its own writable table copy.
			writable:=u64(C.mmap(unsafe{nil},page,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert writable!=u64(-1);C.memcpy(voidptr(writable),voidptr(table),56)
			for _ in 0..16{assert associated(0xff,writable,body,view+28,view+44).metadata==body&&conform(writable,body,body,view+28,view+36)==table}
			assert read64(writable+8)!=read64(table+8)&&read64(table+8)&1==1&&C.munmap(voidptr(writable),page)==0
		}
		for library_name in ['/usr/lib/swift/libswiftCore.dylib','/System/Library/Frameworks/Foundation.framework/Foundation','/System/Library/Frameworks/SwiftUICore.framework/SwiftUICore']!{if _:=runtime_symbol(library_name,never_view_symbol){assert false}}
		assert ios_runtime.swiftui_tuple_nominal_arena==0&&ios_runtime.swiftui_tuple_init_arena==0&&ios_runtime.swiftui_text_view_arena==0&&ios_runtime.swift_void_arena==0&&ios_runtime.swift_heap.len==0&&ios_runtime.swift_buffers.len==0&&ios_runtime.live==0
		cls:=objc_allocate_class(ios_runtime.names['NSObject'],c'VinixNeverViewTeardown',0);assert cls!=0&&objc_add_method(cls,u64(c'dealloc'),u64(unsafe{voidptr(never_view_teardown)}),c'v16@0:8');objc_register_class(cls);objc_autorelease(objc_new(cls))
		base:=ios_runtime.swiftui_opacity_arena;before:=never_view_teardown_calls;ios_runtime.swift_concurrency_retired=true;assert never_view_resolve()==table;objc_stop();assert never_view_teardown_calls==before+1&&ios_runtime.swiftui_opacity_arena==0&&ios_runtime.swiftui_opacity_retired&&ios_runtime.live==0&&ios_runtime.objects.len==0
		$if macos{assert C.mprotect(voidptr(base),page*2,C.PROT_READ)==-1}$else{mut residency:=[u8(0),0]!;assert C.mincore(voidptr(base),page*2,unsafe{&residency[0]})==-1};if _:=swiftui_opacity_arena_checked(){assert false}
	}
	$if macos{assert C.dlclose(core)==0&&C.dlclose(library)==0};assert C.munmap(voidptr(code),page)==0
	println('IOS-SWIFTUI-NEVER-VIEW: eight cold readers in both resolution orders, shared opacity arena and complete zero-size Never metadata, recursive Body:View witness, native associated-type/conformance lookup, view-list count nil with protected inputs and x20/x21 preserved, sealed RX/RO pages, 120 terminal graph/body child calls, protected stack/Self/x8 and unchanged writable/read-only result pages at both guard boundaries, exact routing, callback access and two drained/unmapped lifetimes; graph construction and rendering remain unsupported')
}

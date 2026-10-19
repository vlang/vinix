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
type ModifiedViewInstantiate = fn (u64,u64,u64)
type ModifiedViewLookup = fn (u64,u64,u64)u64
fn modified_view_relative(field u64)u64{mut bits:=u32(0);for i in u64(0)..4{bits|=u32(unsafe{*(&u8(field+i))})<<(i*8)};delta:=i32(bits);return if delta==0{u64(0)}else{u64(i64(field)+i64(delta))}}
fn modified_view_indirect(field u64)u64{bits:=i32(read32(field));p:=u64(i64(field)+i64(bits&~1));return if bits&1!=0{read64(p)}else{p}}
fn modified_view_text(p u64)string{return unsafe{(&char(p)).vstring()}}
fn modified_view_resolve()u64{return runtime_symbol('/System/Library/Frameworks/SwiftUI.framework/SwiftUI','_$s7SwiftUI15ModifiedContentVyxq_GAA4ViewA2aERzAA0E8ModifierR_rlMc') or {panic(err)}}
fn modified_view_nominal()u64{return runtime_symbol('/System/Library/Frameworks/SwiftUI.framework/SwiftUI','_$s7SwiftUI15ModifiedContentVMn') or {panic(err)}}
fn modified_view_protection(address u64,length u64,executable bool){
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
fn modified_view_signature(conformance u64,native bool){
	assert read32(conformance+12)==0x20200
	nominal:=modified_view_relative(conformance+4);view:=modified_view_indirect(conformance)
	assert read32(nominal)==0xd1&&modified_view_text(modified_view_relative(nominal+8))=='ModifiedContent'
	module_descriptor:=modified_view_relative(nominal+4);assert read32(module_descriptor)==0&&modified_view_text(modified_view_relative(module_descriptor+8))=='SwiftUI'
	assert read32(nominal+36)==2&&read32(nominal+40)==2&&read32(nominal+44)==0x8080
	for i,param in ['x','q_']!{
		requirement:=conformance+16+u64(i*12);protocol:=modified_view_indirect(requirement+8)
		assert read32(requirement)==0x80&&modified_view_text(modified_view_relative(requirement+4))==param
		assert modified_view_text(modified_view_relative(protocol+8))==if i==0{'View'}else{'ViewModifier'}
		assert read32(protocol)==0x30043&&read32(protocol+12)==1&&read32(protocol+16)==6
		assert modified_view_text(modified_view_relative(protocol+20))=='Body'&&read32(protocol+24)==0x80&&modified_view_indirect(protocol+32)==view
		flags:=if i==0{[u32(0xcade0008),0x4b5f0007,0xaeaf0001,0x6ddd0001,0x4cbb0001,0xd1fd0013]!}else{[u32(0xd0130008),0x52130007,0xc7420001,0xb8560001,0xf78f0001,0x2b980011]!}
		for j,flag in flags{assert read32(protocol+36+u64(j*8))==flag}
		if !native{
			assert modified_view_relative(protocol+4)==module_descriptor
			path:=modified_view_relative(protocol+28)
			for j,byte in [u8(`4`),`B`,`o`,`d`,`y`,1]!{assert unsafe{*(&u8(path+u64(j)))}==byte}
			assert modified_view_relative(path+6)==protocol&&modified_view_text(path+10)=='Qz'
			for j in u64(0)..6{assert read32(protocol+40+j*8)==0}
		}
	}
	if native{assert modified_view_relative(conformance+8)!=0&&read32(conformance+40)==0x50007&&read32(conformance+44)==0&&modified_view_relative(conformance+48)!=0}else{
		assert nominal==modified_view_nominal()&&conformance==nominal+128
		assert read32(conformance+8)==0&&read32(conformance+40)==0x50000&&read32(conformance+48)==0
		assert modified_view_relative(conformance+44)==ios_runtime.swiftui_modified_arena+16
		modified_view_protection(ios_runtime.swiftui_modified_arena,32,true);modified_view_protection(nominal,541,false)
	}
}
fn modified_view_rejection(conformance u64){
	page:=usize(C.getpagesize());guard:=u64(C.mmap(unsafe{nil},page,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert guard!=u64(-1)
	for metadata in [u64(0),guard,~u64(0)]!{for _ in 0..64{if _:=swift_witness_table_checked(conformance,metadata,guard){assert false}else{assert err.msg()=='iOS: Swift generic/resilient/foreign witness lookup is not implemented'}}}
	lookup:=unsafe{ModifiedViewLookup(voidptr(runtime_symbol('/usr/lib/swift/libswiftCore.dylib','_swift_getWitnessTable') or {panic(err)}))}
	for instantiate in [false,true]!{
		mut fds:=[2]i32{};assert C.pipe(unsafe{&fds[0]})==0;pid:=C.ios_fork();assert pid>=0
		if pid==0{C.close(fds[0]);assert C.dup2(fds[1],2)==2;C.close(fds[1]);if instantiate{call:=unsafe{ModifiedViewInstantiate(voidptr(modified_view_relative(conformance+44)))};call(guard,guard,guard)}else{lookup(conformance,guard,guard)};C._exit(0)}
		C.close(fds[1]);mut bytes:=[16384]u8{};mut length:=0
		for{assert length<bytes.len;count:=C.read(fds[0],unsafe{&bytes[length]},usize(bytes.len-length));if count==0{break};if count<0&&unsafe{*C.ios_errno_address()}==C.EINTR{continue};assert count>0;length+=int(count)}
		C.close(fds[0]);mut status:=i32(0);assert C.ios_waitpid(pid,&status,0)==pid&&status==256
		output:=unsafe{tos(&bytes[0],length)};assert output.contains(if instantiate{'iOS: SwiftUI ModifiedContent View witness instantiation is not implemented'}else{'iOS: Swift generic/resilient/foreign witness lookup is not implemented'})&&!output.contains('runtime error:')&&!output.contains('AddressSanitizer')
	}
	assert C.munmap(voidptr(guard),page)==0
}
fn modified_view_reader()u64{mut result:=u64(0);for _ in 0..128{candidate:=modified_view_resolve();if result==0{result=candidate}else{assert result==candidate};assert modified_view_relative(candidate+4)==modified_view_nominal()};return result}
__global modified_view_teardown_calls=0
fn modified_view_teardown(object u64,selector &char){assert ios_runtime.swift_concurrency_retired;conformance:=modified_view_resolve();assert read32(conformance+12)==0x20200&&modified_view_relative(conformance+4)==modified_view_nominal();modified_view_teardown_calls++}
fn test_swiftui_modified_view(){
	$if macos{
		library:=C.dlopen(c'/System/Library/Frameworks/SwiftUI.framework/SwiftUI',2);assert library!=unsafe{nil};descriptor:=u64(C.dlsym(library,c'$s7SwiftUI15ModifiedContentVyxq_GAA4ViewA2aERzAA0E8ModifierR_rlMc'));assert descriptor!=0;modified_view_signature(descriptor,true);assert C.dlclose(library)==0
		println('NATIVE-SWIFTUI-MODIFIED-VIEW: conditional generic conformance, Content View and Modifier ViewModifier key requirements, native six-slot protocol signatures and two private conditional arguments')
	}
	if _:=swiftui_modified_arena_checked(){assert false};page:=usize(C.getpagesize())
	for _ in 0..2{
		objc_start();assert ios_runtime.swiftui_modified_arena==0&&!ios_runtime.swiftui_modified_retired
		ios_runtime.swift_concurrency_retired=true;if _:=swiftui_modified_arena_checked(){assert false};ios_runtime.swift_concurrency_retired=false
		for symbol in ['_$s7SwiftUI15ModifiedContentVMa','_$s7SwiftUI15ModifiedContentVyxq_GAA4ViewA2aERzAA0E8ModifierR_rlMcExtra','_$s7SwiftUICore15ModifiedContentVyxq_GAA4ViewA2aERzAA0E8ModifierR_rlMc']!{if _:=swiftui_modified_symbol(symbol){assert false}};assert ios_runtime.swiftui_modified_arena==0
		mut workers:=[]thread u64{};for _ in 0..8{workers<<spawn modified_view_reader()};mut conformance:=u64(0);for i,worker in workers{candidate:=worker.wait();if i==0{conformance=candidate}else{assert conformance==candidate}};unsafe{workers.free()}
		modified_view_signature(conformance,false);modified_view_rejection(conformance)
		for library in ['/usr/lib/swift/libswiftCore.dylib','/System/Library/Frameworks/Foundation.framework/Foundation','/System/Library/Frameworks/SwiftUICore.framework/SwiftUICore']!{if _:=runtime_symbol(library,'_$s7SwiftUI15ModifiedContentVyxq_GAA4ViewA2aERzAA0E8ModifierR_rlMc'){assert false}}
		assert ios_runtime.swiftui_opacity_arena==0&&ios_runtime.swift_void_arena==0&&ios_runtime.swift_array_arena==0&&ios_runtime.swift_metadata_arena==0&&ios_runtime.swift_heap.len==0&&ios_runtime.swift_buffers.len==0&&ios_runtime.live==0
		cls:=objc_allocate_class(ios_runtime.names['NSObject'],c'VinixModifiedViewTeardown',0);assert cls!=0&&objc_add_method(cls,u64(c'dealloc'),u64(unsafe{voidptr(modified_view_teardown)}),c'v16@0:8');objc_register_class(cls);objc_autorelease(objc_new(cls))
		base:=ios_runtime.swiftui_modified_arena;before:=modified_view_teardown_calls;ios_runtime.swift_concurrency_retired=true;assert modified_view_resolve()==conformance;objc_stop()
		assert modified_view_teardown_calls==before+1&&ios_runtime.swiftui_modified_arena==0&&ios_runtime.swiftui_modified_retired&&ios_runtime.live==0&&ios_runtime.objects.len==0
		$if macos{assert C.mprotect(voidptr(base),page*2,C.PROT_READ)==-1}$else{mut residency:=[u8(0),0]!;assert C.mincore(voidptr(base),page*2,unsafe{&residency[0]})==-1};if _:=swiftui_modified_arena_checked(){assert false}
	}
	println('IOS-SWIFTUI-MODIFIED-VIEW: eight cold readers, shared canonical nominal/conformance descriptors, native conditional requirements and six-slot protocol signatures, sealed RX/RO pages, no witness pattern or writable cache, protected metadata/arguments rejected before table access, explicit instantiator diagnostic, no dependent metadata ownership, callback access and two drained/unmapped lifetimes; witness specialization and SwiftUI rendering remain unsupported')
}

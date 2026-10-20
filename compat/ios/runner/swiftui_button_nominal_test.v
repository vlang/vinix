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
type ButtonNominalAccess = fn (u64,u64,u64)SwiftAssociatedMetadata
fn button_nominal_relative(field u64)u64{mut bits:=u32(0);for i in u64(0)..4{bits|=u32(unsafe{*(&u8(field+i))})<<u32(i*8)};delta:=i32(bits);return if delta==0{u64(0)}else{u64(i64(field)+i64(delta))}}
fn button_nominal_text(address u64)string{return unsafe{(&char(address)).vstring()}}
fn button_nominal_protocol(field u64)u64{raw:=read32(field);target:=u64(i64(field)+i64(i32(raw&~u32(1))));return if raw&1!=0{read64(target)}else{target}}
fn button_nominal_resolve()u64{return runtime_symbol('/System/Library/Frameworks/SwiftUI.framework/SwiftUI','_$s7SwiftUI6ButtonVMn') or {panic(err)}}
fn button_nominal_protection(address u64,length u64,executable bool){
	$if macos{
		mut start:=address;mut size:=u64(0);mut info:=[16]i32{};mut count:=u32(C.VM_REGION_BASIC_INFO_COUNT_64);mut object:=u32(0);task:=C.mach_task_self()
		assert C.vm_region_64(task,&start,&size,C.VM_REGION_BASIC_INFO_64,unsafe{&info[0]},&count,&object)==0
		assert start<=address&&address+length<=start+size&&info[0]==(C.PROT_READ|if executable{C.PROT_EXEC}else{0})
		if object!=0{assert C.mach_port_deallocate(task,object)==0}
	}$else{
		mut found:=false
		for line in (os.read_file('/proc/self/maps') or {panic(err)}).split_into_lines(){
			fields:=line.fields();if fields.len<2{continue};range:=fields[0].split('-');if range.len!=2{continue}
			start:=strconv.parse_uint(range[0],16,64) or {panic(err)};end:=strconv.parse_uint(range[1],16,64) or {panic(err)}
			if address>=start&&address<end{assert address+length<=end&&fields[1]==if executable{'r-xp'}else{'r--p'};found=true;break}
		};assert found
	}
}
fn button_nominal_signature(descriptor u64,native bool){
 module_descriptor:=button_nominal_relative(descriptor+4)
 assert read32(descriptor)==0xd1&&button_nominal_text(button_nominal_relative(descriptor+8))=='Button'
 assert read32(module_descriptor)==0&&button_nominal_text(button_nominal_relative(module_descriptor+8))=='SwiftUI'
 assert read32(descriptor+20)==3&&read32(descriptor+24)==4
 assert read32(descriptor+36)==0x10001&&read32(descriptor+40)==2&&read32(descriptor+44)==0x80
 assert read32(descriptor+48)==0x80&&button_nominal_text(button_nominal_relative(descriptor+52))=='x'
 view:=button_nominal_protocol(descriptor+56);view_parent:=button_nominal_relative(view+4)
 assert read32(view)==0x30043&&button_nominal_text(button_nominal_relative(view+8))=='View'&&button_nominal_text(button_nominal_relative(view_parent+8))=='SwiftUI'
 assert read32(view+12)==1&&read32(view+16)==6&&button_nominal_text(button_nominal_relative(view+20))=='Body'&&read32(view+24)==0x80&&button_nominal_protocol(view+32)==view
 path:=button_nominal_relative(view+28);tag:=unsafe{*(&u8(path+5))};assert button_nominal_text(path).starts_with('4Body')&&tag in [u8(1),2]!&&button_nominal_text(path+10)=='Qz'
 context:=button_nominal_relative(path+6);assert (if tag==1{context}else{read64(context)})==view
 for i,flags in [u32(0xcade0008),0x4b5f0007,0xaeaf0001,0x6ddd0001,0x4cbb0001,0xd1fd0013]!{assert read32(view+36+u64(i*8))==flags;if !native{assert read32(view+40+u64(i*8))==0}}
 assert button_nominal_relative(descriptor+12)!=0
 if native{assert button_nominal_relative(descriptor+28)!=0&&button_nominal_relative(descriptor+32)!=0}else{
  assert descriptor==ios_runtime.swiftui_button_nominal_arena+u64(C.getpagesize())
  for offset in [u64(16),28,32]!{assert read32(descriptor+offset)==0}
  button_nominal_protection(ios_runtime.swiftui_button_nominal_arena,16,true);button_nominal_protection(descriptor,274,false)
 }
}
fn button_nominal_symbolic_rejection(descriptor u64){
	page:=usize(C.getpagesize());base:=u64(C.mmap(unsafe{nil},page*2,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert base!=u64(-1)
	guard:=base+u64(page);name:=guard-5;slot:=base+64
	unsafe{*(&u64(slot))=descriptor};assert C.mprotect(voidptr(guard),page,C.PROT_NONE)==0
	for tag in [u8(1),2]!{
		unsafe{*(&u8(name))=tag};target:=if tag==1{descriptor}else{slot};delta:=u32(i32(i64(target)-i64(name+1)))
		for i in u64(0)..4{unsafe{*(&u8(name+1+i))=u8(delta>>(i*8))}}
		assert C.mprotect(voidptr(base),page,C.PROT_READ)==0
		for request in [u64(0),0x3f,0xff,0x100,0x13f,0x1ff]!{for _ in 0..32{
			if _:=swift_mangled_state_lookup_checked(request,name,5,guard,guard){assert false}else{assert err.msg()=='iOS: unsupported Swift symbolic context descriptor'}
		}}
		assert C.mprotect(voidptr(base),page,C.PROT_READ|C.PROT_WRITE)==0
	}
	assert C.munmap(voidptr(base),page*2)==0
}
fn button_nominal_access_rejection(descriptor u64){
	page:=usize(C.getpagesize());guard:=u64(C.mmap(unsafe{nil},page,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert guard!=u64(-1)
	accessor:=unsafe{ButtonNominalAccess(voidptr(button_nominal_relative(descriptor+12)))}
	for request in [u64(0),0xff,0x1ff,~u64(0)]!{for label in [u64(0),guard,1,~u64(0)]!{for witness in [u64(0),guard,1,~u64(0)]!{
		mut fds:=[2]i32{};assert C.pipe(unsafe{&fds[0]})==0;pid:=C.ios_fork();assert pid>=0
		if pid==0{C.close(fds[0]);assert C.dup2(fds[1],2)==2;C.close(fds[1]);accessor(request,label,witness);C._exit(0)}
		C.close(fds[1]);mut bytes:=[16384]u8{};mut length:=0
		for{assert length<bytes.len;count:=C.read(fds[0],unsafe{&bytes[length]},usize(bytes.len-length));if count==0{break};if count<0&&unsafe{*C.ios_errno_address()}==C.EINTR{continue};assert count>0;length+=int(count)}
		C.close(fds[0]);mut status:=i32(0);assert C.ios_waitpid(pid,&status,0)==pid&&status==256
		output:=unsafe{tos(&bytes[0],length)};assert output.contains('iOS: SwiftUI Button generic instantiation is not implemented')&&!output.contains('runtime error:')&&!output.contains('AddressSanitizer')
	}}}
	assert C.munmap(voidptr(guard),page)==0
}
fn button_nominal_reader()u64{mut descriptor:=u64(0);for _ in 0..128{candidate:=button_nominal_resolve();if descriptor==0{descriptor=candidate}else{assert descriptor==candidate};assert read32(descriptor)==0xd1};return descriptor}
__global button_nominal_teardown_calls=0
fn button_nominal_teardown(object u64,selector &char){assert ios_runtime.swift_concurrency_retired;descriptor:=button_nominal_resolve();assert read32(descriptor)==0xd1&&button_nominal_text(button_nominal_relative(descriptor+8))=='Button';button_nominal_teardown_calls++}
fn test_swiftui_button_nominal(){
	$if macos{
		library:=C.dlopen(c'/System/Library/Frameworks/SwiftUI.framework/SwiftUI',2);assert library!=unsafe{nil};descriptor:=u64(C.dlsym(library,c'$s7SwiftUI6ButtonVMn'));assert descriptor!=0;button_nominal_signature(descriptor,true);assert C.dlclose(library)==0
		println('NATIVE-SWIFTUI-BUTTON-NOMINAL: generic struct SwiftUI.Button, Label: View requirement and two key arguments; three fields with offset vector at word four, full View declaration and Body: View signature')
	}
	if _:=swiftui_button_nominal_arena_checked(){assert false}
	page:=usize(C.getpagesize())
	for _ in 0..2{
		objc_start();assert ios_runtime.swiftui_button_nominal_arena==0&&!ios_runtime.swiftui_button_nominal_retired
		ios_runtime.swift_concurrency_retired=true;if _:=swiftui_button_nominal_arena_checked(){assert false};ios_runtime.swift_concurrency_retired=false
		for symbol in ['_$s7SwiftUI6ButtonVMa','_$s7SwiftUI6ButtonVMnExtra','_$s7SwiftUI6ButtonVMf','_$s7SwiftUI6ButtonVMnSuffix','_$s11SwiftUICore6ButtonVMn']!{if _:=swiftui_button_nominal_symbol(symbol){assert false}}
		assert ios_runtime.swiftui_button_nominal_arena==0;mut workers:=[]thread u64{};for _ in 0..8{workers<<spawn button_nominal_reader()};mut descriptor:=u64(0)
		for i,worker in workers{candidate:=worker.wait();if i==0{descriptor=candidate}else{assert descriptor==candidate}};unsafe{workers.free()}
		button_nominal_signature(descriptor,false);button_nominal_symbolic_rejection(descriptor);button_nominal_access_rejection(descriptor)
		for library in ['/usr/lib/swift/libswiftCore.dylib','/usr/lib/swift/libswiftFoundation.dylib','/System/Library/Frameworks/Foundation.framework/Foundation','/System/Library/Frameworks/SwiftUICore.framework/SwiftUICore']!{if _:=runtime_symbol(library,'_$s7SwiftUI6ButtonVMn'){assert false}}
		assert ios_runtime.swiftui_modified_arena==0&&ios_runtime.swiftui_opacity_arena==0&&ios_runtime.swiftui_tree_arena==0&&ios_runtime.swiftui_vstack_arena==0&&ios_runtime.swift_array_arena==0&&ios_runtime.swift_metadata_arena==0&&ios_runtime.swift_heap.len==0&&ios_runtime.swift_buffers.len==0&&ios_runtime.live==0
		cls:=objc_allocate_class(ios_runtime.names['NSObject'],c'VinixButtonNominalDescriptorTeardown',0);assert cls!=0&&objc_add_method(cls,u64(c'dealloc'),u64(unsafe{voidptr(button_nominal_teardown)}),c'v16@0:8');objc_register_class(cls);objc_autorelease(objc_new(cls))
		base:=ios_runtime.swiftui_button_nominal_arena;before:=button_nominal_teardown_calls;ios_runtime.swift_concurrency_retired=true;assert button_nominal_resolve()==descriptor;objc_stop()
		assert button_nominal_teardown_calls==before+1&&ios_runtime.swiftui_button_nominal_arena==0&&ios_runtime.swiftui_button_nominal_retired&&ios_runtime.live==0&&ios_runtime.objects.len==0
		$if macos{assert C.mprotect(voidptr(base),page*2,C.PROT_READ)==-1}$else{mut residency:=[u8(0),0]!;assert C.mincore(voidptr(base),page*2,unsafe{&residency[0]})==-1}
		if _:=swiftui_button_nominal_arena_checked(){assert false}
	}
	println('IOS-SWIFTUI-BUTTON-NOMINAL: eight cold readers, sealed module descriptor and native Label: View signature, two key arguments, generic bit retained, direct/indirect symbolic rejection before accessor, 128 child calls with protected Label metadata and View witnesses, explicit instantiation diagnostic, no fabricated metadata or ownership, retirement guards, callback access and two drained/unmapped lifetimes; Button specialization, construction, action storage, View conformance and rendering remain unsupported')
}

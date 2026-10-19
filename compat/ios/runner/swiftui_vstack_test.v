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
type VStackAccess = fn (u64)SwiftAssociatedMetadata
type VStackProbe = fn (u64,u64,&u64)
type VStackCopy = fn (u64,u64,u64)u64
type VStackDestroy = fn (u64,u64)
type VStackGetTag = fn (u64,u32,u64)u32
type VStackStoreTag = fn (u64,u32,u32,u64)
type VStackLookup = fn (u64,u64,u64,u64,u64)u64
fn vstack_relative(field u64)u64{delta:=i32(read32(field));return if delta==0{u64(0)}else{u64(i64(field)+i64(delta))}}
fn vstack_text(address u64)string{return unsafe{(&char(address)).vstring()}}
fn vstack_resolve()u64{return runtime_symbol('/System/Library/Frameworks/SwiftUI.framework/SwiftUI','_$s7SwiftUI13_VStackLayoutVMn') or {panic(err)}}
fn vstack_protection(address u64,length u64,executable bool){
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
fn vstack_layout(descriptor u64,probe VStackProbe,native bool)u64{
	entry:=vstack_relative(descriptor+12);accessor:=unsafe{VStackAccess(voidptr(entry))};metadata:=accessor(0).metadata;witness:=read64(metadata-8)
	assert metadata!=0&&read64(metadata)==0x200&&read64(metadata+8)==descriptor
	assert read32(descriptor)==0x51&&read32(descriptor+20)==2&&read32(descriptor+24)==2
	assert read32(metadata+16)==0&&read32(metadata+20)==8
	assert read64(witness+64)==17&&read64(witness+72)==24&&read32(witness+80)==7&&read32(witness+84)==0
	assert vstack_text(vstack_relative(descriptor+8))=='_VStackLayout'&&vstack_text(vstack_relative(vstack_relative(descriptor+4)+8))=='SwiftUI'
	for request in [u64(0),0x3f,0xff,0x100,0x13f,0x1ff,~u64(0)]!{
		mut result:=[u64(0xcafe),0,0,0,0,0xbeef]!
		probe(request,entry,unsafe{&result[1]});assert result==[u64(0xcafe),metadata,0,0x5020,0x5021,0xbeef]!
	}
	if !native{
		assert descriptor==ios_runtime.swiftui_vstack_arena+u64(C.getpagesize())+160&&vstack_relative(descriptor+16)==0
		vstack_protection(entry,24,true);vstack_protection(metadata-8,238,false)
	}
	return metadata
}
fn vstack_values(metadata u64){
	witness:=read64(metadata-8);page:=usize(C.getpagesize());base:=u64(C.mmap(unsafe{nil},page*2,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert base!=u64(-1)
	guard:=base+u64(page);source:=guard-17
	for i in u64(0)..17{unsafe{*(&u8(source+i))=u8(i+1)}}
	assert C.mprotect(voidptr(base),page,C.PROT_READ)==0&&C.mprotect(voidptr(guard),page,C.PROT_NONE)==0
	for slot in [u64(0),2,3,4,5]!{
		transfer:=unsafe{VStackCopy(voidptr(read64(witness+slot*8)))};mut destination:=[40]u8{}
		for i in 0..destination.len{destination[i]=0xa5}
		pointer:=u64(unsafe{&destination[8]});assert transfer(pointer,source,guard)==pointer
		for i in 0..destination.len{assert destination[i]==if i>=8&&i<25{u8(i-7)}else{u8(0xa5)}}
		assert transfer(pointer,pointer,guard)==pointer
		for i in 0..destination.len{assert destination[i]==if i>=8&&i<25{u8(i-7)}else{u8(0xa5)}}
	}
	destroy:=unsafe{VStackDestroy(voidptr(read64(witness+8)))};destroy(guard,guard);destroy(source,guard)
	get:=unsafe{VStackGetTag(voidptr(read64(witness+48)))};store:=unsafe{VStackStoreTag(voidptr(read64(witness+56)))}
	assert get(guard,0,guard)==0;store(guard,0,0,guard)
	for cases in [u32(0),1,255,256,65536,0xffffffff]!{for tag in [u32(0),1,255,256,0xfffffffe,0xffffffff]!{
		mut value:=[u64(0xcafe),0x1122334455667788,0x99aabbccddeeff00,0x8877665544332211,0xbeef]!
		pointer:=u64(unsafe{&value[1]});store(pointer,tag,cases,guard)
		first:=if tag==0{u64(0x1122334455667788)}else{u64(tag-1)};second:=if tag==0{u64(0x99aabbccddeeff00)}else{u64(0)}
		mut third:=u64(0x8877665544332211);if tag!=0{third&=~u64(255)};if cases!=0{third=(third&~u64(0xff00))|if tag==0{u64(0)}else{u64(0x100)}}
		assert value==[u64(0xcafe),first,second,third,0xbeef]!
		assert get(pointer,cases,guard)==if cases==0{u32(0)}else{tag}
	}}
	mut wrapping:=[u64(0xffffffff),0,0x100]!;assert get(u64(unsafe{&wrapping[0]}),1,guard)==0
	// A one-byte tag may use any nonzero encoding. Payload arithmetic wraps u32.
	for tag_byte in [u64(0),1,127,255]!{mut raw:=[u64(255),0,tag_byte<<8]!;assert get(u64(unsafe{&raw[0]}),1,guard)==if tag_byte==0{u32(0)}else{u32(256)}}
	assert C.munmap(voidptr(base),page*2)==0
}
fn vstack_symbolic(lookup VStackLookup,descriptor u64,metadata u64){
	page:=usize(C.getpagesize());base:=u64(C.mmap(unsafe{nil},page,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert base!=u64(-1)
	name:=base+32;slot:=base+64;unsafe{*(&u8(name))=2;*(&u64(slot))=descriptor};delta:=u32(i32(i64(slot)-i64(name+1)))
	for i in u64(0)..4{unsafe{*(&u8(name+1+i))=u8(delta>>(i*8))}};assert C.mprotect(voidptr(base),page,C.PROT_READ)==0
	for request in [u64(0),0xff,0x100,0x1ff]!{for _ in 0..32{assert lookup(request,name,5,0,0)==metadata}}
	assert C.munmap(voidptr(base),page)==0
}
fn vstack_reader()u64{
	mut descriptor:=u64(0)
	for _ in 0..128{candidate:=vstack_resolve();if descriptor==0{descriptor=candidate}else{assert descriptor==candidate};accessor:=unsafe{VStackAccess(voidptr(vstack_relative(descriptor+12)))};response:=accessor(0xff);assert read64(response.metadata+8)==descriptor}
	return descriptor
}
__global vstack_teardown_calls=0
fn vstack_teardown(object u64,selector &char){assert ios_runtime.swift_concurrency_retired;descriptor:=vstack_resolve();accessor:=unsafe{VStackAccess(voidptr(vstack_relative(descriptor+12)))};response:=accessor(0);assert read64(response.metadata+8)==descriptor;vstack_teardown_calls++}
fn test_swiftui_vstack(){
	page:=usize(C.getpagesize());code:=u64(C.mmap(unsafe{nil},page,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert code!=u64(-1)
	for i,op in [u32(0xa9bd7bfd),0xa90153f3,0xa9025bf5,0xaa0203f3,0xaa0103f0,0xd28a0414,0xd28a0435,0xd63f0200,0xa9000660,0xa9015674,0xa94153f3,0xa9425bf5,0xa8c37bfd,0xd65f03c0]!{write32(code+u64(i*4),op)}
	C.__builtin___clear_cache(voidptr(code),voidptr(code+56));assert C.mprotect(voidptr(code),page,C.PROT_READ|C.PROT_EXEC)==0;probe:=unsafe{VStackProbe(voidptr(code))}
	$if macos{
		library:=C.dlopen(c'/System/Library/Frameworks/SwiftUI.framework/SwiftUI',2);core:=C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',2);assert library!=unsafe{nil}&&core!=unsafe{nil}
		descriptor:=u64(C.dlsym(library,c'$s7SwiftUI13_VStackLayoutVMn'));assert descriptor!=0;metadata:=vstack_layout(descriptor,probe,true);vstack_values(metadata)
		lookup:=unsafe{VStackLookup(C.dlsym(core,c'swift_getTypeByMangledNameInContextInMetadataState'))};vstack_symbolic(lookup,descriptor,metadata)
		assert C.dlclose(core)==0&&C.dlclose(library)==0
		println('NATIVE-SWIFTUI-VSTACK: canonical nongeneric descriptor, 17-byte POD/24-byte stride, field offsets 0/8, exact copies with padding preserved, no-op destruction, both single-payload populations and u32 wrapping, indirect symbolic lookup and x20/x21 preservation')
	}
	if _:=swiftui_vstack_arena_checked(){assert false}
	for _ in 0..2{
		objc_start();assert ios_runtime.swiftui_vstack_arena==0&&!ios_runtime.swiftui_vstack_retired
		ios_runtime.swift_concurrency_retired=true;if _:=swiftui_vstack_arena_checked(){assert false};ios_runtime.swift_concurrency_retired=false
		for symbol in ['_$s7SwiftUI13_VStackLayoutVMa','_$s7SwiftUI13_VStackLayoutVN','_$s7SwiftUI13_VStackLayoutVMnExtra','_$s7SwiftUI13_ZStackLayoutVMn']!{if _:=swiftui_vstack_symbol(symbol){assert false}}
		assert ios_runtime.swiftui_vstack_arena==0;mut workers:=[]thread u64{};for _ in 0..8{workers<<spawn vstack_reader()};mut descriptor:=u64(0)
		for i,worker in workers{got:=worker.wait();if i==0{descriptor=got}else{assert descriptor==got}};unsafe{workers.free()}
		metadata:=vstack_layout(descriptor,probe,false);vstack_values(metadata);vstack_symbolic(unsafe{VStackLookup(voidptr(swift_mangled_state_lookup))},descriptor,metadata)
		for library in ['/usr/lib/swift/libswiftCore.dylib','/usr/lib/swift/libswiftFoundation.dylib','/System/Library/Frameworks/Foundation.framework/Foundation','/System/Library/Frameworks/SwiftUICore.framework/SwiftUICore']!{if _:=runtime_symbol(library,'_$s7SwiftUI13_VStackLayoutVMn'){assert false}}
		allocation:=swift_array_allocate(2,metadata);assert ios_runtime.swift_arrays[allocation.owner].stride==24&&ios_runtime.swift_arrays[allocation.owner].destroy==0
		C.memset(voidptr(allocation.bytes),0,48);swift_bridge_release(allocation.owner);assert ios_runtime.swift_arrays.len==0&&ios_runtime.swift_heap.len==0&&ios_runtime.swift_buffers.len==0&&ios_runtime.live==0
		cls:=objc_allocate_class(ios_runtime.names['NSObject'],c'VinixVStackMetadataTeardown',0);assert cls!=0&&objc_add_method(cls,u64(c'dealloc'),u64(unsafe{voidptr(vstack_teardown)}),c'v16@0:8');objc_register_class(cls);objc_autorelease(objc_new(cls))
		base:=ios_runtime.swiftui_vstack_arena;before:=vstack_teardown_calls;ios_runtime.swift_concurrency_retired=true;assert vstack_resolve()==descriptor;objc_stop()
		assert vstack_teardown_calls==before+1&&ios_runtime.swiftui_vstack_arena==0&&ios_runtime.swiftui_vstack_retired&&ios_runtime.live==0&&ios_runtime.objects.len==0
		$if macos{assert C.mprotect(voidptr(base),page*2,C.PROT_READ)==-1}$else{mut residency:=[u8(0),0]!;assert C.mincore(voidptr(base),page*2,unsafe{&residency[0]})==-1}
		if _:=swiftui_vstack_arena_checked(){assert false}
	}
	assert C.munmap(voidptr(code),page)==0
	println('IOS-SWIFTUI-VSTACK: eight cold readers, sealed distinct SwiftUI descriptor and complete accessor, exact 17-byte POD copies with seven padding bytes preserved, guarded unused inputs, two-field offsets and enum witnesses, native indirect type-reference lookup, typed Array ownership, retirement guards, callback access and two drained/unmapped lifetimes; SwiftUI views/layout/reflection remain unsupported')
}

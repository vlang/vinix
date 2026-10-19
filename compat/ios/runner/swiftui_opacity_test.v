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
type OpacityAccess=fn (u64)SwiftAssociatedMetadata
type OpacityProbe=fn (u64,u64,&u64)
type OpacityCopy=fn (u64,u64,u64)u64
type OpacityDestroy=fn (u64,u64)
type OpacityGet=fn (u64,u32,u64)u32
type OpacityStore=fn (u64,u32,u32,u64)
type OpacityAssociated=fn (u64,u64,u64,u64,u64)SwiftAssociatedMetadata
type OpacityConformance=fn (u64,u64,u64,u64,u64)u64
type OpacityLookup=fn (u64,u64,u64)u64
type OpacitySign=fn (u64,u64)u64
type OpacityStrip=fn (u64)u64
type OpacityGraph=fn (u64,u64,u64,u64)
type OpacityBody=fn (u64,u64,u64)u64
fn opacity_relative(p u64)u64{mut bits:=u32(0);for i in u64(0)..4{bits|=u32(unsafe{*(&u8(p+i))})<<(i*8)};delta:=i32(bits);return if delta==0{u64(0)}else{u64(i64(p)+i64(delta))}}
fn opacity_indirect(p u64)u64{bits:=i32(read32(p));target:=u64(i64(p)+i64(bits&~1));return if bits&1!=0{read64(target)}else{target}}
fn opacity_text(p u64)string{return unsafe{(&char(p)).vstring()}}
fn opacity_descriptor_resolve()u64{return runtime_symbol('/System/Library/Frameworks/SwiftUI.framework/SwiftUI','_$s7SwiftUI14_OpacityEffectVMn') or {panic(err)}}
fn opacity_resolve()u64{return runtime_symbol('/System/Library/Frameworks/SwiftUI.framework/SwiftUI','_$s7SwiftUI14_OpacityEffectVAA12ViewModifierAAWP') or {panic(err)}}
fn opacity_protection(address u64,length u64,executable bool){
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
fn opacity_values(metadata u64,empty bool){
	witness:=read64(metadata-8);size:=if empty{u64(0)}else{u64(8)}
	assert read64(witness+64)==size&&read64(witness+72)==if empty{u64(1)}else{u64(8)}
	assert read32(witness+80)==if empty{u32(0)}else{u32(7)}&&read32(witness+84)==0
	page:=usize(C.getpagesize());base:=u64(C.mmap(unsafe{nil},page*2,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert base!=u64(-1);guard:=base+u64(page);source:=guard-size
	for i in u64(0)..size{unsafe{*(&u8(source+i))=u8(i+1)}};assert C.mprotect(voidptr(base),page,C.PROT_READ)==0&&C.mprotect(voidptr(guard),page,C.PROT_NONE)==0
	for slot in [u64(0),2,3,4,5]!{transfer:=unsafe{OpacityCopy(voidptr(read64(witness+slot*8)))};mut value:=[24]u8{};for i in 0..value.len{value[i]=0xa5};p:=u64(unsafe{&value[8]});assert transfer(p,source,guard)==p;for i in 0..value.len{assert value[i]==if i>=8&&i<8+int(size){u8(i-7)}else{u8(0xa5)}};assert transfer(p,p,guard)==p;if empty{assert transfer(guard,guard,guard)==guard}}
	destroy:=unsafe{OpacityDestroy(voidptr(read64(witness+8)))};destroy(guard,guard)
	get:=unsafe{OpacityGet(voidptr(read64(witness+48)))};store:=unsafe{OpacityStore(voidptr(read64(witness+56)))};assert get(guard,0,guard)==0;store(guard,0,0,guard)
	for cases in [u32(0),1,254,255,256,65534,65535,65536,0xffffffff]!{for tag in [u32(0),1,255,256,0xfffffffe,0xffffffff]!{
		mut value:=[u64(0xcafe),0x1122334455667788,0x8877665544332211,0xbeef]!;p:=u64(unsafe{&value[1]});store(p,tag,cases,guard)
		if empty{
			width:=if cases==0||cases==0xffffffff{u32(0)}else if cases<255{u32(1)}else if cases<65535{u32(2)}else{u32(4)}
			mask:=if width==0{u64(0)}else{(u64(1)<<(width*8))-1};assert value==[u64(0xcafe),(u64(0x1122334455667788)&~mask)|(u64(tag)&mask),u64(0x8877665544332211),0xbeef]!
			assert get(p,cases,guard)==u32(u64(tag)&mask)
		}else{
			first:=if tag==0{u64(0x1122334455667788)}else{u64(tag-1)};second:=if cases==0{u64(0x8877665544332211)}else{u64(0x8877665544332200)|if tag==0{u64(0)}else{u64(1)}}
			assert value==[u64(0xcafe),first,second,0xbeef]!;assert get(p,cases,guard)==if cases==0{u32(0)}else{tag}
		}
	}}
	if empty{assert get(guard,0xffffffff,guard)==0;store(guard,0xffffffff,0xffffffff,guard)}else{for byte in [u64(0),1,127,255]!{mut raw:=[u64(0xffffffff),byte]!;assert get(u64(unsafe{&raw[0]}),1,guard)==0}}
	assert C.munmap(voidptr(base),page*2)==0
}
fn opacity_contract(table u64,associated OpacityAssociated,probe OpacityProbe,native bool)u64{
	conformance:=read64(table);descriptor:=opacity_relative(conformance+4);modifier:=opacity_indirect(conformance)
	assert read32(conformance+12)==0&&opacity_relative(conformance+8)==table
	assert opacity_text(opacity_relative(modifier+8))=='ViewModifier'&&opacity_text(opacity_relative(modifier+20))=='Body'
	assert read32(modifier)==0x30043&&read32(modifier+12)==1&&read32(modifier+16)==6
	for i,flags in [u32(8),7,1,1,1,0x11]!{assert read32(modifier+36+u64(i*8))&0xffff==flags}
	assert read32(modifier+24)==0x80;view:=opacity_indirect(modifier+32);assert opacity_text(opacity_relative(view+8))=='View'&&read32(view+12)==1&&read32(view+16)==6
	assert read32(descriptor)==0x51&&read32(descriptor+20)==1&&read32(descriptor+24)==2&&opacity_text(opacity_relative(descriptor+8))=='_OpacityEffect'
	assert opacity_text(opacity_relative(opacity_relative(descriptor+4)+8))=='SwiftUI'
	accessor:=unsafe{OpacityAccess(voidptr(opacity_relative(descriptor+12)))};metadata:=accessor(0).metadata;assert read64(metadata)==0x200&&read64(metadata+8)==descriptor&&read32(metadata+16)==0
	for request in [u64(0),0xff,0x1ff,~u64(0)]!{mut result:=[u64(0xcafe),0,0,0,0,0xbeef]!;probe(request,opacity_relative(descriptor+12),unsafe{&result[1]});assert result==[u64(0xcafe),metadata,0,0x5020,0x5021,0xbeef]!}
	body:=associated(0xff,table,metadata,modifier+28,modifier+44).metadata;nd:=read64(body+8)
	assert read64(body)==0x201&&read32(nd)==0x52&&read32(nd+20)==0&&read32(nd+24)==0&&opacity_text(opacity_relative(nd+8))=='Never'&&opacity_text(opacity_relative(opacity_relative(nd+4)+8))=='Swift'
	opacity_values(metadata,false);opacity_values(body,true)
	if !native{
		base:=ios_runtime.swiftui_opacity_arena;data:=base+u64(C.getpagesize());assert table==data+480&&body==data+264&&read64(table+16)==body&&read64(table+8)==((data+896)|1)
		assert opacity_descriptor_resolve()==descriptor
		assert read32(descriptor+16)==0&&read32(nd+16)==0&&ios_runtime.swift_void_arena==0
		for slot in u64(3)..7{assert read64(table+slot*8)==base+64}
		for _ in 0..64{assert swift_witness_table(conformance,0,0)==table&&swift_associated_type(0,table,0,modifier+28,modifier+44).metadata==body}
		opacity_protection(base,96,true);opacity_protection(data,903,false)
	}
	return metadata
}
fn opacity_rejection(table u64,metadata u64,native_conform u64){
	page:=usize(C.getpagesize());guard:=u64(C.mmap(unsafe{nil},page,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert guard!=u64(-1)
	for slot in [u64(3),4,5,6,0,1]!{
		mut fds:=[2]i32{};assert C.pipe(unsafe{&fds[0]})==0;pid:=C.ios_fork();assert pid>=0
		if pid==0{C.close(fds[0]);assert C.dup2(fds[1],2)==2;C.close(fds[1]);if slot>=3{call:=unsafe{OpacityGraph(voidptr(read64(table+slot*8)))};call(guard,guard,guard,guard)}else if slot==1&&native_conform!=0{call:=unsafe{OpacityConformance(voidptr(native_conform))};modifier:=opacity_relative(read64(table));call(table,metadata,read64(table+16),modifier+28,modifier+36)}else{record:=read64(table+8)&~u64(1);assert unsafe{*(&u8(record))}==0xff&&unsafe{*(&u8(record+1))}==7;call:=unsafe{OpacityBody(voidptr(opacity_relative(record+2)))};call(guard,guard,guard)};C._exit(0)}
		C.close(fds[1]);mut bytes:=[16384]u8{};mut length:=0;for{assert length<bytes.len;n:=C.read(fds[0],unsafe{&bytes[length]},usize(bytes.len-length));if n==0{break};if n<0&&unsafe{*C.ios_errno_address()}==C.EINTR{continue};assert n>0;length+=int(n)}
		C.close(fds[0]);mut status:=i32(0);assert C.ios_waitpid(pid,&status,0)==pid&&status==256
		output:=unsafe{tos(&bytes[0],length)};assert output.contains(if slot>=3{'opacity ViewModifier graph operations are not implemented'}else{'opacity Body Never View conformance is not implemented'})&&!output.contains('runtime error:')&&!output.contains('AddressSanitizer')
	}
	conformance:=read64(table);assert swift_witness_table(conformance,guard,guard)==table
	assert C.munmap(voidptr(guard),page)==0
}
fn opacity_reader()u64{mut table:=u64(0);for _ in 0..128{candidate:=opacity_resolve();if table==0{table=candidate}else{assert table==candidate};assert swift_witness_table(read64(table),0,0)==table;assert opacity_descriptor_resolve()==opacity_relative(read64(table)+4)};return table}
__global opacity_teardown_calls=0
fn opacity_teardown(object u64,selector &char){assert ios_runtime.swift_concurrency_retired;table:=opacity_resolve();modifier:=opacity_relative(read64(table));assert swift_associated_type(0,table,0,modifier+28,modifier+44).metadata==read64(table+16);opacity_teardown_calls++}
fn test_swiftui_opacity(){
	page:=usize(C.getpagesize());code:=u64(C.mmap(unsafe{nil},page,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert code!=u64(-1)
	for i,op in [u32(0xa9bd7bfd),0xa90153f3,0xa9025bf5,0xaa0203f3,0xaa0103f0,0xd28a0414,0xd28a0435,0xd63f0200,0xa9000660,0xa9015674,0xa94153f3,0xa9425bf5,0xa8c37bfd,0xd65f03c0]!{write32(code+u64(i*4),op)}
	write32(code+64,0xdac10820);write32(code+68,0xd65f03c0);write32(code+80,0xdac147e0);write32(code+84,0xd65f03c0)
	C.__builtin___clear_cache(voidptr(code),voidptr(code+88));assert C.mprotect(voidptr(code),page,C.PROT_READ|C.PROT_EXEC)==0;probe:=unsafe{OpacityProbe(voidptr(code))}
	mut core:=unsafe{voidptr(0)};mut native_associated:=u64(0);mut native_conform:=u64(0)
	$if macos{core=C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',2);lib:=C.dlopen(c'/System/Library/Frameworks/SwiftUI.framework/SwiftUI',2);assert core!=unsafe{nil}&&lib!=unsafe{nil};native_associated=u64(C.dlsym(core,c'swift_getAssociatedTypeWitness'));native_conform=u64(C.dlsym(core,c'swift_getAssociatedConformanceWitness'));table:=u64(C.dlsym(lib,c'$s7SwiftUI14_OpacityEffectVAA12ViewModifierAAWP'));opacity_contract(table,unsafe{OpacityAssociated(voidptr(native_associated))},probe,true);assert C.dlclose(lib)==0;println('NATIVE-SWIFTUI-OPACITY: six-requirement static ViewModifier table, POD8 opacity metadata, Body Never enum with size zero/stride one, exact value/tag spans and accessor x20/x21 preservation')}
	if _:=swiftui_opacity_arena_checked(){assert false}
	for _ in 0..2{
		objc_start();assert ios_runtime.swiftui_opacity_arena==0&&!ios_runtime.swiftui_opacity_retired;ios_runtime.swift_concurrency_retired=true;if _:=swiftui_opacity_arena_checked(){assert false};ios_runtime.swift_concurrency_retired=false
		for symbol in ['_$s7SwiftUI14_OpacityEffectVAA12ViewModifierAAMc','_$s7SwiftUI14_OpacityEffectVMa','_$s7SwiftUI12ViewModifierMp','_$s7SwiftUI14_OpacityEffectVAA12ViewModifierAAWPExtra']!{if _:=swiftui_opacity_symbol(symbol){assert false}};assert ios_runtime.swiftui_opacity_arena==0
		mut workers:=[]thread u64{};for _ in 0..8{workers<<spawn opacity_reader()};mut table:=u64(0);for i,worker in workers{candidate:=worker.wait();if i==0{table=candidate}else{assert table==candidate}};unsafe{workers.free()}
		metadata:=opacity_contract(table,swift_associated_type,probe,false)
		$if macos{opacity_contract(table,unsafe{OpacityAssociated(voidptr(native_associated))},probe,false);sign:=unsafe{OpacitySign(voidptr(code+64))};strip:=unsafe{OpacityStrip(voidptr(code+80))};lookup:=unsafe{OpacityLookup(C.dlsym(core,c'swift_getWitnessTable'))};assert strip(lookup(sign(read64(table),0xc6eb),0,0))==table}
		opacity_rejection(table,metadata,native_conform)
		for library in ['/usr/lib/swift/libswiftCore.dylib','/System/Library/Frameworks/Foundation.framework/Foundation','/System/Library/Frameworks/SwiftUICore.framework/SwiftUICore']!{for symbol in ['_$s7SwiftUI14_OpacityEffectVAA12ViewModifierAAWP','_$s7SwiftUI14_OpacityEffectVMn']!{if _:=runtime_symbol(library,symbol){assert false}}}
		allocation:=swift_array_allocate(2,metadata);assert ios_runtime.swift_arrays[allocation.owner].stride==8&&ios_runtime.swift_arrays[allocation.owner].destroy==0;C.memset(voidptr(allocation.bytes),0,16);swift_bridge_release(allocation.owner)
		// Never has no inhabitants: reserve typed capacity with count zero.
		owner:=swift_array_buffer_allocate(1,read64(table+16));assert ios_runtime.swift_arrays[owner].stride==1&&ios_runtime.swift_arrays[owner].destroy==0&&read64(owner+16)==0;swift_bridge_release(owner)
		assert ios_runtime.swift_void_arena==0&&ios_runtime.swift_heap.len==0&&ios_runtime.swift_arrays.len==0&&ios_runtime.swift_buffers.len==0&&ios_runtime.live==0
		cls:=objc_allocate_class(ios_runtime.names['NSObject'],c'VinixOpacityWitnessTeardown',0);assert cls!=0&&objc_add_method(cls,u64(c'dealloc'),u64(unsafe{voidptr(opacity_teardown)}),c'v16@0:8');objc_register_class(cls);objc_autorelease(objc_new(cls))
		base:=ios_runtime.swiftui_opacity_arena;before:=opacity_teardown_calls;ios_runtime.swift_concurrency_retired=true;assert opacity_resolve()==table;objc_stop();assert opacity_teardown_calls==before+1&&ios_runtime.swiftui_opacity_arena==0&&ios_runtime.swiftui_opacity_retired&&ios_runtime.live==0&&ios_runtime.objects.len==0
		$if macos{assert C.mprotect(voidptr(base),page*2,C.PROT_READ)==-1}$else{mut residency:=[u8(0),0]!;assert C.mincore(voidptr(base),page*2,unsafe{&residency[0]})==-1};if _:=swiftui_opacity_arena_checked(){assert false}
	}
	$if macos{assert C.dlclose(core)==0};assert C.munmap(voidptr(code),page)==0
	println('IOS-SWIFTUI-OPACITY: eight cold readers, sealed canonical static conformance and native six-slot protocol signature, complete POD8 opacity and zero-size Never metadata, native associated-type/static-table lookup, protected value/enum spans and unused inputs, explicit graph/associated-conformance diagnostics, no dependent metadata ownership, callback access and two drained/unmapped lifetimes; SwiftUI rendering and Never View conformance remain unsupported')
}

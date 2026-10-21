// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

#include <dlfcn.h>
$if macos {
	#flag -framework CoreFoundation
	#include <CoreFoundation/CFString.h>
}
fn C.dlopen(&char,i32)voidptr
fn C.dlsym(voidptr,&char)voidptr
fn C.CFStringCreateMutable(voidptr,i64)voidptr
fn C.CFGetRetainCount(voidptr)i64
fn C.CFRetain(voidptr)voidptr
fn C.CFRelease(voidptr)
fn C.mincore(voidptr,usize,&u8)i32

type EaAllocate = fn(u64,u64,u64,bool)SwiftArrayAllocation
type EaRetain = fn(u64)u64
type EaRelease = fn(u64)
type EaExtract = fn(u64,&u64,&SwiftErrorValue)
type EaCopy = fn(u64,u64,u64)u64
type EaDestroy = fn(u64,u64)
type EaSign = fn(u64,u64)u64

struct EaApi {
	native bool
	allocate EaAllocate @[required]
	retain EaRetain @[required]
	release EaRelease @[required]
	extract EaExtract @[required]
	metadata [3]u64
	witness u64
}
struct EaState {
	api EaApi
	size u64
	alignment u64
	reenter bool
mut:
	copies int
	takes int
	destroys int
}
fn ea_symbol(native bool,name string)u64{
	$if macos { if native {
		library:=C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',2);assert library!=unsafe{nil}
		entry:=u64(C.dlsym(library,name[1..].str));assert entry!=0,name;return entry
	} }
	return runtime_symbol('/usr/lib/swift/libswiftCore.dylib',name) or {panic(err)}
}
fn ea_api(native bool)EaApi{
	return EaApi{native:native,
		allocate:unsafe{EaAllocate(voidptr(ea_symbol(native,'_swift_allocError')))},
		retain:unsafe{EaRetain(voidptr(ea_symbol(native,'_swift_errorRetain')))},
		release:unsafe{EaRelease(voidptr(ea_symbol(native,'_swift_errorRelease')))},
		extract:unsafe{EaExtract(voidptr(ea_symbol(native,'_swift_getErrorValue')))},
		metadata:[ea_symbol(native,'_$sSiN'),ea_symbol(native,'_$sSSN'),ea_symbol(native,'_$ss11_MergeErrorON')]!,
		witness:ea_symbol(native,'_$ss11_MergeErrorOs0B0sWP')}
}
fn ea_object(api EaApi)u64{
	$if macos {if api.native{return u64(C.CFStringCreateMutable(unsafe{nil},0))}}
	return owned_string('owned generic Swift error payload')
}
fn ea_hold(api EaApi,object u64){
	$if macos {if api.native{C.CFRetain(voidptr(object));return}}
	objc_retain(object)
}
fn ea_drop(api EaApi,object u64){
	$if macos {if api.native{C.CFRelease(voidptr(object));return}}
	objc_release(object)
}
fn ea_refs(api EaApi,object u64)i64{
	$if macos {if api.native{return C.CFGetRetainCount(voidptr(object))}}
	return obj_header(object).refs
}
fn ea_resolve()u64{return ea_symbol(false,'_swift_allocError')}
fn ea_reenter(s &EaState){if s.reenter{worker:=spawn ea_resolve();assert worker.wait()==u64(voidptr(s.api.allocate))}}
fn ea_copy(destination u64,source u64,metadata u64)u64{
	mut s:=unsafe{&EaState(read64(metadata+8))};assert destination&(s.alignment-1)==0 && source&(s.alignment-1)==0
	s.copies++;C.memcpy(voidptr(destination),voidptr(source),usize(s.size));ea_hold(s.api,read64(source));ea_reenter(s);return destination
}
fn ea_take(destination u64,source u64,metadata u64)u64{
	mut s:=unsafe{&EaState(read64(metadata+8))};assert destination&(s.alignment-1)==0 && source&(s.alignment-1)==0
	s.takes++;C.memcpy(voidptr(destination),voidptr(source),usize(s.size));ea_reenter(s);return destination
}
fn ea_destroy(value u64,metadata u64){
	mut s:=unsafe{&EaState(read64(metadata+8))};assert value&(s.alignment-1)==0
	s.destroys++;ea_drop(s.api,read64(value));ea_reenter(s)
}
fn ea_alias_worker(api EaApi,owner u64){for _ in 0..128{assert api.retain(owner)==owner;api.release(owner)}}

fn ea_case(api EaApi,code u64,kind int,mode int,at_end bool){
	page:=usize(C.getpagesize());custom:=kind>=3
	profiles:=[[u64(8),1]!,[u64(24),8]!,[u64(32),16]!,[u64(64),32]!,[u64(129),64]!,[u64(65536),256]!]!
	size:=if custom{profiles[kind-3][0]}else if kind==0{u64(8)}else if kind==1{u64(16)}else{u64(0)}
	alignment:=if custom{profiles[kind-3][1]}else if kind==2{u64(1)}else{u64(8)}
	span_size:=(usize(size)+page-1)/page*page+page*3
	span:=u64(C.mmap(unsafe{nil},span_size,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert span!=~u64(0)
	defer{assert C.munmap(voidptr(span),span_size)==0}
	readable:=span+u64(page);readable_size:=span_size-page*2
	assert C.mprotect(voidptr(readable),readable_size,C.PROT_READ|C.PROT_WRITE)==0
	stride:=if size==0{u64(1)}else{(size+alignment-1)&~(alignment-1)}
	source:=if at_end{readable+u64(readable_size)-stride}else{readable}
	data:=u64(C.mmap(unsafe{nil},page,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert data!=~u64(0)
	defer{assert C.munmap(voidptr(data),page)==0}
	mut state:=EaState{api:api,size:size,alignment:alignment,reenter:!api.native&&custom}
	mut metadata:=if custom{data+16}else{api.metadata[kind]}
	if custom{
		witness:=data+128;mut pointer:=witness
		$if macos {if api.native{pointer=unsafe{EaSign(voidptr(code+16))(witness,(metadata-8)|(u64(0x2e3f)<<48))}}}
		unsafe{*(&u64(metadata-8))=pointer;*(&u64(metadata))=0x200;*(&u64(metadata+8))=u64(&state)}
		for item in [[u64(8),u64(voidptr(ea_destroy)),0x4f8]!,[u64(16),u64(voidptr(ea_copy)),0xe3ba]!,[u64(32),u64(voidptr(ea_take)),0x48d8]!]!{
			mut entry:=item[1];slot:=witness+item[0]
			$if macos {if api.native{entry=unsafe{EaSign(voidptr(code))(entry,slot|(item[2]<<48))}}}
			unsafe{*(&u64(slot))=entry}
		}
		unsafe{*(&u64(witness+64))=size;*(&u64(witness+72))=stride}
		write32(witness+80,u32(alignment-1)|0x10000|if size>24||alignment>8{u32(0x20000)}else{u32(0)})
	}
	object:=ea_object(api);defer{ea_drop(api,object)}
	C.memset(voidptr(source),0x6b,usize(size))
	if kind==1{ea_hold(api,object);unsafe{*(&SwiftStringWords(source))=SwiftStringWords{second:object|0x5000000000000000}}}
	else if custom{ea_hold(api,object);C.memcpy(voidptr(source),unsafe{&object},8)}
	else if kind==0{unsafe{*(&u64(source))=0x8123456789abcdef}}
	assert C.mprotect(voidptr(readable),readable_size,C.PROT_READ)==0&&C.mprotect(voidptr(data),page,C.PROT_READ)==0
	vwt:=read64(metadata-8)&0x0000ffffffffffff
	payload_copy:=unsafe{EaCopy(voidptr(read64(vwt+16)&0x0000ffffffffffff))}
	destroy:=unsafe{EaDestroy(voidptr(read64(vwt+8)&0x0000ffffffffffff))}
	allocation:=api.allocate(metadata,api.witness,if mode==0{u64(0)}else{source},mode==2)
	assert allocation.owner!=0 && allocation.bytes!=0 && allocation.bytes&(alignment-1)==0
	if alignment<=8{assert allocation.bytes-allocation.owner==72}
	if mode==0{payload_copy(allocation.bytes,source,metadata)}
	if size!=0{assert C.memcmp(voidptr(allocation.bytes),voidptr(source),usize(size))==0}
	mut scratch:=u64(0xaabbccdd);mut value:=SwiftErrorValue{}
	api.extract(allocation.owner,unsafe{&scratch},unsafe{&value})
	assert scratch==0xaabbccdd && value==SwiftErrorValue{value:allocation.bytes,metadata:metadata,witness:api.witness}
	for unused in [u64(0),span,~u64(0)]!{api.extract(allocation.owner,unsafe{&u64(unused)},unsafe{&value});assert value.value==allocation.bytes}
	assert api.retain(allocation.owner)==allocation.owner;api.release(allocation.owner)
	if !api.native{
		mut first:=u64(0);mut second:=u64(0);mut held:=api.retain(allocation.owner);original:=allocation.owner
		swift_objc_value_copy(u64(unsafe{&first}),u64(unsafe{&original}),0)
		swift_objc_value_copy(u64(unsafe{&second}),u64(unsafe{&original}),0)
		swift_objc_value_assign_copy(u64(unsafe{&first}),u64(unsafe{&original}),0)
		swift_objc_value_destroy(u64(unsafe{&first}),0)
		swift_objc_value_take(u64(unsafe{&first}),u64(unsafe{&second}),0)
		swift_objc_value_assign_take(u64(unsafe{&first}),u64(unsafe{&held}),0)
		swift_objc_value_destroy(u64(unsafe{&first}),0)
		if _:=swift_error_bridge_checked(allocation.owner){assert false}
		if _:=swift_error_to_nserror_checked(allocation.owner){assert false}
	}
	if kind==8&&mode==1&&at_end{
		mut workers:=[]thread{};for _ in 0..8{workers<<spawn ea_alias_worker(api,allocation.owner)};workers.wait();unsafe{workers.free()}
	}
	if kind==1||custom{assert ea_refs(api,object)==if mode==2{i64(2)}else{i64(3)}}
	if custom{assert state.copies==if mode==2{0}else{1};assert state.takes==if mode==2{1}else{0}}
	api.release(allocation.owner)
	if custom{assert state.destroys==1}
	if mode!=2{destroy(source,metadata)}
	assert ea_refs(api,object)==1
	if custom{assert state.destroys==if mode==2{1}else{2}}
}
fn ea_matrix(api EaApi,code u64){for kind in 0..9{for mode in 0..3{for at_end in [false,true]!{ea_case(api,code,kind,mode,at_end)}}}}
fn ea_worker(api EaApi,code u64,i int){ea_case(api,code,3+i%6,i%3,true)}

fn test_swift_error_allocation(){
	page:=usize(C.getpagesize());code:=u64(C.mmap(unsafe{nil},page*2,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert code!=~u64(0)
	for item in [[u64(0),0xdac10020]!,[u64(4),0xd65f03c0]!,[u64(16),0xdac10820]!,[u64(20),0xd65f03c0]!]!{write32(code+item[0],u32(item[1]))}
	C.__builtin___clear_cache(voidptr(code),voidptr(code+24));assert C.mprotect(voidptr(code),page,C.PROT_READ|C.PROT_EXEC)==0&&C.mprotect(voidptr(code+u64(page)),page,C.PROT_NONE)==0
	$if macos {ea_matrix(ea_api(true),code);println('NATIVE-ERROR-ALLOCATION: 54 nil/copy/take cases, Int/String/empty Error and custom owned values through 64 KiB/alignment 256, protected source, exact ownership and untouched scratch, concurrent retain/release')}
	for _ in 0..2{
		objc_start();api:=ea_api(false);assert ios_runtime.swift_error_allocation_arena==0
		mut workers:=[]thread{};for i in 0..8{workers<<spawn ea_worker(api,code,i)};workers.wait();unsafe{workers.free()}
		ea_matrix(api,code)
		for witness in [u64(0),1]!{if _:=swift_error_allocate_checked(api.metadata[0],witness,0,false){assert false}}
		for metadata in [u64(0),1,~u64(7)]!{if _:=swift_error_allocate_checked(metadata,api.witness,0,false){assert false}}
		for source in [u64(1),~u64(7)]!{if _:=swift_error_allocate_checked(api.metadata[1],api.witness,source,false){assert false}}
		ios_runtime.swift_concurrency_retired=true;if _:=swift_error_allocate_checked(code+u64(page),code+u64(page),code+u64(page),false){assert false};ios_runtime.swift_concurrency_retired=false
		assert ios_runtime.swift_errors.len==0&&ios_runtime.swift_heap.len==0&&ios_runtime.live==0
		arena:=ios_runtime.swift_error_allocation_arena;objc_stop();assert ios_runtime.swift_error_allocation_arena==0&&ios_runtime.swift_errors.len==0
		if _:=swift_error_allocate_checked(code+u64(page),code+u64(page),code+u64(page),false){assert false}
		$if macos{assert C.mprotect(voidptr(arena),page,C.PROT_READ)==-1}$else{mut resident:=u8(0);assert C.mincore(voidptr(arena),page,unsafe{&resident})==-1}
	}
	assert C.munmap(voidptr(code),page*2)==0
	println('IOS-ERROR-ALLOCATION: bounded complete value boxes, nil/copy/take initialization, exact payload destruction and borrowed Error extraction, Error existential ownership, guarded source and scratch, eight cold workers and reentrant callbacks, two drained/unmapped lifetimes; native NSError bridging and Error dynamic casts remain unsupported')
}

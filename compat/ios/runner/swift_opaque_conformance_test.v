// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char,i32)voidptr
fn C.dlsym(voidptr,&char)voidptr
type OcSign=fn(u64,u64)u64
type OcProbe=fn(u64,u64,u64,u64,u64,&u64,u64)
struct OcApi { native bool entry u64 code u64 guard u64 }
struct OcState { mut: arguments u64 answer u64 calls i64 reenter bool entry u64 }
__global oc_state=OcState{}
fn oc_lookup()u64{return runtime_symbol('/usr/lib/swift/libswiftCore.dylib','_swift_getOpaqueTypeConformance2') or {panic(err)}}
fn oc_callback(arguments u64)u64{
	assert arguments==oc_state.arguments
	previous:=C.ios_ref_change(unsafe{&oc_state.calls},1)
	if previous==0&&oc_state.reenter{worker:=spawn oc_lookup();assert worker.wait()==oc_state.entry}
	return oc_state.answer
}
fn oc_other(arguments u64)u64{assert arguments==oc_state.arguments;C.ios_ref_change(unsafe{&oc_state.calls},1);return oc_state.answer^0x55}
fn oc_api(native bool,code u64,guard u64)OcApi{
	$if macos{if native{core:=C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',2);assert core!=unsafe{nil};entry:=u64(C.dlsym(core,c'swift_getOpaqueTypeConformance2'));assert entry!=0;return OcApi{true,entry,code,guard}}}
	return OcApi{false,oc_lookup(),code,guard}
}
fn oc_call(api OcApi,arguments u64,descriptor u64,index u64)u64{
	mut words:=[u64(0xcafe),0,0,0,0,0,0xbeef]!
	signed_descriptor:=if api.native{unsafe{OcSign(voidptr(api.code+128))(descriptor,0xbdd1)}}else{descriptor}
	unsafe{OcProbe(voidptr(api.code))(arguments,signed_descriptor,index,api.guard,api.entry,&words[1],api.guard)}
	assert words[0]==0xcafe&&words[6]==0xbeef&&words[3]==api.guard&&words[4]==0x5121&&words[5]==0x5222
	return words[1]
}
fn oc_worker(api OcApi,descriptor u64,index u64,expected u64){for _ in 0..32{assert oc_call(api,oc_state.arguments,descriptor,index)==expected}}
fn oc_bad(arguments u64,descriptor u64,index u32){before:=oc_state.calls;if _:=swift_opaque_conformance_checked(arguments,descriptor,index){assert false,'unsupported opaque descriptor accepted'};assert oc_state.calls==before}
fn oc_emit_name(name u64,leading int,trailing int,accessor u64){
	for i in 0..leading{unsafe{*(&u8(name+u64(i)))=0xff}}
	tag:=name+u64(leading);unsafe{*(&u8(tag))=9}
	delta:=i64(accessor)-i64(tag+1);assert delta>=-2147483648&&delta<=2147483647
	for i in 0..4{unsafe{*(&u8(tag+1+u64(i)))=u8(u32(i32(delta))>>u32(i*8))}}
	for i in 0..trailing{unsafe{*(&u8(tag+5+u64(i)))=0xff}}
	unsafe{*(&u8(tag+5+u64(trailing)))=0}
}
fn oc_matrix(api OcApi){
	page:=u64(C.getpagesize());base:=u64(C.mmap(unsafe{nil},usize(page*5),C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert base!=~u64(0)
	for offset in [page,page*3]!{assert C.mprotect(voidptr(base+offset),usize(page),C.PROT_READ|C.PROT_WRITE)==0}
	mut vector:=[u64(0xaabb),0xccdd]!
	for shape in [[0,0,0]!,[1,0,0]!,[1,1,1]!,[3,2,2]!,[4,1,2]!,[64,64,2]!]!{
		generic:=shape[0]!=0;parameters:=if generic{shape[0]}else{0};requirements:=shape[1];count:=if shape[2]==2{64}else{2}
		header:=if generic{16+((parameters+3)&~3)+requirements*12}else{8}
		descriptor_page:=base+if parameters&1!=0{page*3}else{page}
		name_page:=base+if parameters&1!=0{page}else{page*3}
		descriptor:=descriptor_page+page-u64(header+count*4)
		assert C.mprotect(voidptr(descriptor_page),usize(page),C.PROT_READ|C.PROT_WRITE)==0
		write32(descriptor,(u32(count)<<16)|if generic{u32(0xc4)}else{u32(0x44)});write32(descriptor+4,0x80000000)
		if generic{write32(descriptor+8,u32(parameters)|(u32(requirements)<<16));write32(descriptor+12,u32(parameters+requirements));for i in 16..header{unsafe{*(&u8(descriptor+u64(i)))=0xa5}}}
		// Every unselected argument points at inaccessible storage. Parsing
		// the selected entry must not inspect other underlying expressions.
		for i in 0..count{swift_protocol_relative(descriptor+u64(header+i*4),api.guard)}
		for padding in [0,1,2,3,64]!{
			assert C.mprotect(voidptr(name_page),usize(page),C.PROT_READ|C.PROT_WRITE)==0
			name:=name_page+page-u64(6+padding);oc_emit_name(name,padding,0,api.code+256)
			first_name:=name_page;oc_emit_name(first_name,padding,0,api.code+288)
			assert C.mprotect(voidptr(name_page),usize(page),C.PROT_READ)==0
			assert C.mprotect(voidptr(descriptor_page),usize(page),C.PROT_READ|C.PROT_WRITE)==0
			swift_protocol_relative(descriptor+u64(header),first_name);swift_protocol_relative(descriptor+u64(header+(count-1)*4),name)
			assert C.mprotect(voidptr(descriptor_page),usize(page),C.PROT_READ)==0
			for arguments in [u64(0),api.guard,u64(unsafe{&vector[0]})]!{
				for answer in [u64(0),0x1234,api.guard]!{
					oc_state=OcState{arguments:arguments,answer:answer,entry:api.entry,reenter:!api.native&&padding==1&&parameters==1&&requirements==1&&arguments==api.guard&&answer==api.guard}
					for index in [u64(count-1),u64(count-1)+0x100000000]!{assert oc_call(api,arguments,descriptor,index)==answer}
					other:=oc_call(api,arguments,descriptor,0);assert other==answer^0x55,'native=${api.native} parameters=${parameters} padding=${padding}'
					assert oc_state.calls==3,'native=${api.native} parameters=${parameters} padding=${padding}'
				}
			}
		}
		oc_state=OcState{arguments:api.guard,answer:api.guard,entry:api.entry,reenter:false}
		mut readers:=[]thread{};for _ in 0..8{readers<<spawn oc_worker(api,descriptor,u64(count-1),api.guard)};readers.wait();unsafe{readers.free()};assert oc_state.calls==256
	}
	assert vector[0]==0xaabb&&vector[1]==0xccdd
	if !api.native{
		assert ios_runtime.live==0&&ios_runtime.swift_heap.len==0&&ios_runtime.swift_objc_metadata.len==0
		// Rejected headers need only their first word; generic counts/pack
		// flags fail before any parameter, requirement or argument-table read.
		assert C.mprotect(voidptr(base+page),usize(page),C.PROT_READ|C.PROT_WRITE)==0
		descriptor:=base+page*2-4
		for flags in [u32(0),4,0x10003,0x10024,0x10104,0x10000004,0x410044]!{write32(descriptor,flags);oc_bad(api.guard,descriptor,0)}
		write32(descriptor,0x10044);oc_bad(api.guard,descriptor,1)
		for invalid in [u64(0),1,~u64(3),descriptor+1]!{oc_bad(api.guard,invalid,0)}
		generic:=base+page*2-16;write32(generic,0x100c4)
		for sizes in [u32(65),65<<16]!{write32(generic+8,sizes);write32(generic+12,0);oc_bad(api.guard,generic,0)}
		write32(generic+8,0);for flags in [u32(129),0x10000,0x80000000]!{write32(generic+12,flags);oc_bad(api.guard,generic,0)}
		desc:=base+page;name:=base+page*3;write32(desc,0x10044);swift_protocol_relative(desc+8,name)
		assert C.mprotect(voidptr(base+page*3),usize(page),C.PROT_READ|C.PROT_WRITE)==0
		for tag in [u8(0),1,2,3,8,10,0x53,0xff]!{unsafe{*(&u8(name))=tag;*(&u8(name+1))=0};oc_bad(api.guard,desc,0)}
		oc_emit_name(name,0,0,api.code+256);unsafe{*(&u8(name+5))=0x53};oc_bad(api.guard,desc,0)
		oc_emit_name(name,65,0,api.code+256);oc_bad(api.guard,desc,0);oc_emit_name(name,0,1,api.code+256);oc_bad(api.guard,desc,0)
		oc_emit_name(name,0,0,api.code+257);oc_bad(api.guard,desc,0)
		write32(desc+8,0);oc_bad(api.guard,desc,0)
		if _:=swift_opaque_conformance_relative(1,0x80000000){assert false};if _:=swift_opaque_conformance_relative(~u64(0),1){assert false}
		if _:=swift_opaque_conformance_relative(4,0xfffffffc){assert false}
		ios_runtime.swift_concurrency_retired=true;oc_bad(api.guard,api.guard,0);ios_runtime.swift_concurrency_retired=false
		write32(desc,0x10044);swift_protocol_relative(desc+8,name);oc_emit_name(name,1,0,api.code+256)
		assert C.mprotect(voidptr(base+page),usize(page),C.PROT_READ)==0&&C.mprotect(voidptr(base+page*3),usize(page),C.PROT_READ)==0
		objc_stop();assert read32(desc)==0x10044&&unsafe{*(&u8(name))}==0xff;oc_bad(api.guard,api.guard,0)
	}
	assert C.munmap(voidptr(base),usize(page*5))==0
}
fn test_swift_opaque_conformance(){
	page:=usize(C.getpagesize());code:=u64(C.mmap(unsafe{nil},page,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));guard:=u64(C.mmap(unsafe{nil},page,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert code!=~u64(0)&&guard!=~u64(0)
	defer{assert C.munmap(voidptr(code),page)==0&&C.munmap(voidptr(guard),page)==0}
	for i,op in [u32(0xa9bc7bfd),0xa90153f3,0xa9025bf5,0xaa0503f3,0xaa0403f0,0xaa0603f4,u32(0xd2800000|(0x5121<<5)|21),u32(0xd2800000|(0x5222<<5)|22),0xaa0603e8,0xd63f0200,0xa9000660,0xa9015674,0xf9001276,0xa9425bf5,0xa94153f3,0xa8c47bfd,0xd65f03c0]!{write32(code+u64(i*4),op)}
	write32(code+128,0xdac10820);write32(code+132,0xd65f03c0)
	for pair in [[code+256,u64(voidptr(oc_callback))]!,[code+288,u64(voidptr(oc_other))]!]!{write32(pair[0],0x58000050);write32(pair[0]+4,0xd61f0200);unsafe{*(&u64(pair[0]+8))=pair[1]}}
	C.__builtin___clear_cache(voidptr(code),voidptr(code+304));assert C.mprotect(voidptr(code),page,C.PROT_READ|C.PROT_EXEC)==0
	$if macos{oc_matrix(oc_api(true,code,guard));println('NATIVE-OPAQUE-CONFORMANCE: SwiftCC scalar ABI and UInt32 index wrapping; padded 0x09 C accessor, exact original argument pointer and zero/inaccessible results, generic descriptor counts through 64, selected entry only and readonly boundaries, eight readers and preserved x20/x21/x22 with inaccessible x8')}
	oc_bad(guard,guard,0)
	for _ in 0..2{objc_start();oc_matrix(oc_api(false,code,guard))}
	println('IOS-OPAQUE-CONFORMANCE: bounded standalone accessor expressions in nongeneric/ordinary generic descriptors, original vector forwarding without parent/requirement/result reads, guarded scalar ABI, UInt32 index, padding and malformed descriptor/expression/pack/retired rejection before callbacks, unlocked registry reentry, eight readers, borrowed readonly storage and two drained lifetimes')
}

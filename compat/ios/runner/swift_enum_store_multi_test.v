// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char,i32)voidptr
fn C.dlsym(voidptr,&char)voidptr
type EsAllocate=fn(u64,u64,u64,u64)u64
type EsProbe=fn(u64,u64,u64,u64,u64,&u64,u64)
struct EsApi { native bool entry u64 code u64 guard u64 }
struct EsInput { base u64 page u64 descriptor u64 witness u64 metadata u64 offset u64 }
fn es_symbol(native bool,name string)u64{
	$if macos{if native{library:=C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',2);entry:=u64(C.dlsym(library,name[1..].str));assert entry!=0,name;return entry}}
	return runtime_symbol('/usr/lib/swift/libswiftCore.dylib',name) or {panic(err)}
}
fn es_emit(code u64){
	for i,op in [u32(0xa9bc7bfd),0xa90153f3,0xa9025bf5,0xaa0503f3,0xaa0403f0,0xaa0603f4,
		u32(0xd2800000|(0x5121<<5)|21),u32(0xd2800000|(0x5222<<5)|22),0xaa0603e8,0xd63f0200,
		0xa9000660,0xa9015674,0xf9001276,0xa9425bf5,0xa94153f3,0xa8c47bfd,0xd65f03c0]!{write32(code+u64(i*4),op)}
}
fn es_call(api EsApi,value u64,metadata u64,which u32){
	mut words:=[u64(0xcafe),0,0,0,0,0,0xbeef]!
	unsafe{EsProbe(voidptr(api.code))(value,metadata,(u64(0xfeedbeef)<<32)|u64(which),api.guard,api.entry,&words[1],api.guard)}
	assert words[0]==0xcafe&&words[6]==0xbeef&&words[3]==api.guard&&words[4]==0x5121&&words[5]==0x5222
}
fn es_input(api EsApi,offset u64,at_end bool)EsInput{
	page:=u64(C.getpagesize());base:=u64(C.mmap(unsafe{nil},usize(page*9),C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert base!=~u64(0)
	for i in [u64(1),3,5,7]!{assert C.mprotect(voidptr(base+page*i),usize(page),C.PROT_READ|C.PROT_WRITE)==0}
	d:=base+page*2-24;w:=base+page*3-64;m:=base+page*5+if at_end{page-(offset+1)*8}else{u64(8)};p:=base+page*8-16
	write32(d,0xd2);write32(d+20,u32(offset<<24)|2);write32(p+8,0x40200000);swift_protocol_relative(p+12,w)
	mut description:=d
	$if macos{if api.native{
		// Let native allocation supply the signed descriptor word, then copy
		// only that word into separately guarded borrowed metadata.
		assert C.mprotect(voidptr(base+page*2),usize(page),C.PROT_READ|C.PROT_WRITE)==0
		allocate:=unsafe{EsAllocate(voidptr(es_symbol(true,'_swift_allocateGenericValueMetadata')))}
		original:=allocate(d,api.guard,p,offset*8);description=read64(original+8)
		assert C.mprotect(voidptr(base+page*2),usize(page),C.PROT_NONE)==0
	}}
	unsafe{*(&u64(m-8))=w;*(&u64(m))=0x201;*(&u64(m+8))=description}
	for i in [u64(1),3,5,7]!{assert C.mprotect(voidptr(base+page*i),usize(page),C.PROT_READ)==0}
	return EsInput{base,page,d,w,m,offset}
}
fn es_layout(input EsInput,payload u64,width u64,cases u32){
	for i in [u64(1),3,5]!{assert C.mprotect(voidptr(input.base+input.page*i),usize(input.page),C.PROT_READ|C.PROT_WRITE)==0}
	write32(input.descriptor+20,u32(input.offset<<24)|cases)
	unsafe{*(&u64(input.metadata+input.offset*8))=payload;*(&u64(input.witness+64))=payload+width;*(&u64(input.witness+72))=if payload+width==0{u64(1)}else{payload+width}}
	write32(input.witness+80,0x200000)
	for i in [u64(1),3,5]!{assert C.mprotect(voidptr(input.base+input.page*i),usize(input.page),C.PROT_READ)==0}
}
fn es_bytes(address u64,value u32,width u64){for i in u64(0)..if width<4{width}else{u64(4)}{unsafe{*(&u8(address+i))=u8(value>>u32(i*8))}}}
fn es_mix(hash u64,value u32)u64{return (hash^u64(value))*u64(1099511628211)}
fn es_matrix(api EsApi)u64{
	page:=u64(C.getpagesize());length:=u64(1048576)+page*4
	span:=u64(C.mmap(unsafe{nil},usize(length),C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert span!=~u64(0)
	expected:=u64(C.mmap(unsafe{nil},usize(length),C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert expected!=~u64(0)
	defer{assert C.munmap(voidptr(span),usize(length))==0;assert C.munmap(voidptr(expected),usize(length))==0}
	assert C.mprotect(voidptr(span),usize(page),C.PROT_NONE)==0
	assert C.mprotect(voidptr(span+length-page),usize(page),C.PROT_NONE)==0
	mut hash:=u64(14695981039346656037)
	for at_end in [false,true]!{for offset in [u64(2),3,5,255]!{
		input:=es_input(api,offset,at_end)
		for payload in [u64(0),1,2,3,4,8,31,65536,1048576]!{for width in u64(0)..5{for cases in [u32(2),255,256,65535,65536,0xffffff]!{
			es_layout(input,payload,width,cases);size:=payload+width
			for which in [u32(0),1,cases-1,cases,cases+1,255,256,65535,65536,0xffffff,0xffffffff]!{
				value:=if at_end{span+length-page-size}else{span+page+1}
				unsafe{C.memset(voidptr(value),0xa5,usize(size));C.memset(voidptr(expected),0xa5,usize(size));*(&u8(value-1))=0x6d}
				if !at_end{unsafe{*(&u8(value+size))=0xd6}}
				mut tag:=which
				if which>=cases{
					index:=which-cases
					bits:=u32(payload*8)
					tag=cases+if payload>=4{u32(0)}else{index>>bits}
					unsafe{C.memset(voidptr(expected),0,usize(payload))}
					es_bytes(expected,index,payload)
				}
				es_bytes(expected+payload,tag,width)
				es_call(api,value,input.metadata,which)
				assert C.memcmp(voidptr(value),voidptr(expected),usize(size))==0
				assert unsafe{*(&u8(value-1))}==0x6d
				if !at_end{assert unsafe{*(&u8(value+size))}==0xd6}
				hash=es_mix(hash,swift_enum_case_multi_read(value,payload))
				hash=es_mix(hash,swift_enum_case_multi_read(value+payload,width))
				if payload>4{hash=es_mix(hash,u32(unsafe{*(&u8(value+payload-1))}))}
			}
		}}}
		assert C.munmap(voidptr(input.base),usize(page*9))==0
	}}
	return hash
}
fn es_bad(value u64,metadata u64){if _:=swift_enum_store_multi_checked(value,metadata,2){assert false,'unsupported enum tag store accepted'}}
fn es_invalid(api EsApi){
	input:=es_input(api,2,true);defer{assert C.munmap(voidptr(input.base),usize(input.page*9))==0}
	es_layout(input,8,1,2)
	for value in [u64(0),~u64(7)]!{es_bad(value,input.metadata)}
	for metadata in [u64(0),1,~u64(7)]!{es_bad(api.guard,metadata)}
	assert C.mprotect(voidptr(input.base+input.page*5),usize(input.page),C.PROT_READ|C.PROT_WRITE)==0
	for kind in [u64(0x200),0x202,0x301,0x400]!{unsafe{*(&u64(input.metadata))=kind};es_bad(api.guard,input.metadata)};unsafe{*(&u64(input.metadata))=0x201}
	for descriptor in [u64(0),1,~u64(3)]!{unsafe{*(&u64(input.metadata+8))=descriptor};es_bad(api.guard,input.metadata)};unsafe{*(&u64(input.metadata+8))=input.descriptor}
	for witness in [u64(0),1,~u64(7)]!{unsafe{*(&u64(input.metadata-8))=witness};es_bad(api.guard,input.metadata)};unsafe{*(&u64(input.metadata-8))=input.witness}
	assert C.mprotect(voidptr(input.base+input.page),usize(input.page),C.PROT_READ|C.PROT_WRITE)==0
	for flags in [u32(0x51),0x1d2]!{write32(input.descriptor,flags);es_bad(api.guard,input.metadata)};write32(input.descriptor,0xd2)
	for counts in [u32(2),0x01000002,0x02000000,0x02000001]!{write32(input.descriptor+20,counts);es_bad(api.guard,input.metadata)}
	for pair in [[u64(1048577),1]!,[u64(8),5]!]!{es_layout(input,pair[0],pair[1],2);es_bad(api.guard,input.metadata)}
	es_layout(input,8,1,2)
	assert C.mprotect(voidptr(input.base+input.page*3),usize(input.page),C.PROT_READ|C.PROT_WRITE)==0
	for size in [u64(0),7,14]!{unsafe{*(&u64(input.witness+64))=size};es_bad(api.guard,input.metadata)};unsafe{*(&u64(input.witness+64))=9}
	for stride in [u64(0),8]!{unsafe{*(&u64(input.witness+72))=stride};es_bad(api.guard,input.metadata)};unsafe{*(&u64(input.witness+72))=9}
	for flags in [u32(0),0x600000,0x200002,0x200001]!{write32(input.witness+80,flags);es_bad(api.guard,input.metadata)}
	ios_runtime.swift_concurrency_retired=true;es_bad(api.guard,api.guard);ios_runtime.swift_concurrency_retired=false
}
fn es_untouched(api EsApi){
	input:=es_input(api,255,true);defer{assert C.munmap(voidptr(input.base),usize(input.page*9))==0}
	es_layout(input,1048576,0,2)
	for value in [u64(0),api.guard,~u64(0)]!{es_call(api,value,input.metadata,1)}
	es_layout(input,0,0,2)
	for value in [u64(0),api.guard,~u64(0)]!{es_call(api,value,input.metadata,0xffffffff)}
	es_layout(input,1048576,1,2)
	page:=usize(C.getpagesize());value:=u64(C.mmap(unsafe{nil},usize(1048576)+page,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert value!=~u64(0)
	defer{assert C.munmap(voidptr(value),usize(1048576)+page)==0}
	assert C.mprotect(voidptr(value+1048576),page,C.PROT_READ|C.PROT_WRITE)==0
	es_call(api,value,input.metadata,1);assert unsafe{*(&u8(value+1048576))}==1
}
fn es_worker(api EsApi,metadata u64){
	mut value:=[u8(0xa5),0xa5,0xa5,0xa5,0xa5,0xa5,0xa5,0xa5,0xa5]!
	for _ in 0..256{
		es_call(api,u64(unsafe{&value[0]}),metadata,0x1234567a)
		assert value==[u8(0x78),0x56,0x34,0x12,0,0,0,0,2]!
		es_call(api,u64(unsafe{&value[0]}),metadata,1)
		assert value==[u8(0x78),0x56,0x34,0x12,0,0,0,0,1]!
	}
}
fn test_swift_enum_store_multi(){
	page:=usize(C.getpagesize());code:=u64(C.mmap(unsafe{nil},page,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert code!=~u64(0)
	guard:=u64(C.mmap(unsafe{nil},page,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert guard!=~u64(0)
	defer{assert C.munmap(voidptr(code),page)==0;assert C.munmap(voidptr(guard),page)==0}
	es_emit(code);C.__builtin___clear_cache(voidptr(code),voidptr(code+68));assert C.mprotect(voidptr(code),page,C.PROT_READ|C.PROT_EXEC)==0
	mut native_hash:=u64(0)
	$if macos{
		api:=EsApi{true,es_symbol(true,'_swift_storeEnumTagMultiPayload'),code,guard};native_hash=es_matrix(api);es_untouched(api)
		println('IOS-ENUM-STORE-MULTI-NATIVE: three-argument C void ABI, low w2 only, payloads zero to 1 MiB, zero to four tag bytes, 24-bit payload counts, UInt32 empty-case wrap, full byte comparison and payload zeroing, guarded unaligned values and signed borrowed headers, untouched opaque payloads and x20/x21/x22; hash='+native_hash.hex())
	}
	for _ in 0..2{
		objc_start();api:=EsApi{false,es_symbol(false,'_swift_storeEnumTagMultiPayload'),code,guard};hash:=es_matrix(api)
		assert hash==u64(0x4de1ab0a58ec5ee5)
		$if macos{assert hash==native_hash}
		println('IOS-ENUM-STORE-MULTI-MATRIX: hash='+hash.hex())
		es_untouched(api);es_invalid(api)
		input:=es_input(api,2,false);es_layout(input,8,1,2)
		mut workers:=[]thread{};for _ in 0..8{workers<<spawn es_worker(api,input.metadata)};workers.wait();unsafe{workers.free()}
		assert C.munmap(voidptr(input.base),usize(input.page*9))==0
		assert ios_runtime.live==0&&ios_runtime.swift_heap.len==0&&ios_runtime.swift_generic_value_allocations.len==0
		objc_stop();es_bad(guard,guard)
	}
	println('IOS-ENUM-STORE-MULTI: bounded initialized multi-payload enum tag stores, payload-case preservation and full empty-payload clearing, truncated tags and wrapped UInt32 cases, no callbacks/ARC, rejected layouts/states before writes, eight writers and two drained lifetimes')
}

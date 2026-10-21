// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char,i32)voidptr
fn C.dlsym(voidptr,&char)voidptr
type EmAllocate=fn(u64,u64,u64,u64)u64
type EmProbe=fn(u64,u64,u64,u64,u64,&u64,u64)
struct EmApi { native bool entry u64 code u64 guard u64 }
struct EmInput { base u64 page u64 descriptor u64 witness u64 metadata u64 offset u64 }
fn em_symbol(native bool,name string)u64{
	$if macos{if native{library:=C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',2);entry:=u64(C.dlsym(library,name[1..].str));assert entry!=0,name;return entry}}
	return runtime_symbol('/usr/lib/swift/libswiftCore.dylib',name) or {panic(err)}
}
fn em_emit(code u64){
	for i,op in [u32(0xa9bc7bfd),0xa90153f3,0xa9025bf5,0xaa0503f3,0xaa0403f0,0xaa0603f4,
		u32(0xd2800000|(0x5121<<5)|21),u32(0xd2800000|(0x5222<<5)|22),0xaa0603e8,0xd63f0200,
		0xa9000660,0xa9015674,0xf9001276,0xa9425bf5,0xa94153f3,0xa8c47bfd,0xd65f03c0]!{write32(code+u64(i*4),op)}
}
fn em_call(api EmApi,value u64,metadata u64)u32{
	mut words:=[u64(0xcafe),0,0,0,0,0,0xbeef]!
	unsafe{EmProbe(voidptr(api.code))(value,metadata,api.guard,api.guard,api.entry,&words[1],api.guard)}
	assert words[0]==0xcafe&&words[6]==0xbeef&&words[3]==api.guard&&words[4]==0x5121&&words[5]==0x5222&&words[1]<=0xffffffff
	return u32(words[1])
}
fn em_input(api EmApi,offset u64,at_end bool)EmInput{
	page:=u64(C.getpagesize());base:=u64(C.mmap(unsafe{nil},usize(page*9),C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert base!=~u64(0)
	for i in [u64(1),3,5,7]!{assert C.mprotect(voidptr(base+page*i),usize(page),C.PROT_READ|C.PROT_WRITE)==0}
	d:=base+page*2-24;w:=base+page*3-64;m:=base+page*5+if at_end{page-(offset+1)*8}else{u64(8)};p:=base+page*8-16
	write32(d,0xd2);write32(d+20,u32(offset<<24)|2);write32(p+8,0x40200000);swift_protocol_relative(p+12,w)
	mut description:=d
	$if macos{if api.native{
		// Let native allocation supply the signed descriptor word, then copy
		// only that word into separately guarded borrowed metadata.
		assert C.mprotect(voidptr(base+page*2),usize(page),C.PROT_READ|C.PROT_WRITE)==0
		allocate:=unsafe{EmAllocate(voidptr(em_symbol(true,'_swift_allocateGenericValueMetadata')))}
		original:=allocate(d,api.guard,p,offset*8);description=read64(original+8)
		assert C.mprotect(voidptr(base+page*2),usize(page),C.PROT_NONE)==0
	}}
	unsafe{*(&u64(m-8))=w;*(&u64(m))=0x201;*(&u64(m+8))=description}
	for i in [u64(1),3,5,7]!{assert C.mprotect(voidptr(base+page*i),usize(page),C.PROT_READ)==0}
	return EmInput{base,page,d,w,m,offset}
}
fn em_layout(input EmInput,payload u64,width u64,cases u32){
	for i in [u64(1),3,5]!{assert C.mprotect(voidptr(input.base+input.page*i),usize(input.page),C.PROT_READ|C.PROT_WRITE)==0}
	write32(input.descriptor+20,u32(input.offset<<24)|cases)
	unsafe{*(&u64(input.metadata+input.offset*8))=payload;*(&u64(input.witness+64))=payload+width;*(&u64(input.witness+72))=if payload+width==0{u64(1)}else{payload+width}}
	write32(input.witness+80,0x200000)
	for i in [u64(1),3,5]!{assert C.mprotect(voidptr(input.base+input.page*i),usize(input.page),C.PROT_READ)==0}
}
fn em_bytes(address u64,value u32,width u64){for i in u64(0)..if width<4{width}else{u64(4)}{unsafe{*(&u8(address+i))=u8(value>>u32(i*8))}}}
fn em_mix(hash u64,value u32)u64{return (hash^u64(value))*u64(1099511628211)}
fn em_matrix(api EmApi)u64{
	page:=u64(C.getpagesize());length:=u64(1048576)+page*4
	span:=u64(C.mmap(unsafe{nil},usize(length),C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert span!=~u64(0)
	defer{assert C.munmap(voidptr(span),usize(length))==0}
	mut hash:=u64(14695981039346656037)
	for at_end in [false,true]!{for offset in [u64(2),3,5,255]!{
		input:=em_input(api,offset,at_end)
		for payload in [u64(0),1,2,3,4,8,31,65536,1048576]!{for width in u64(0)..5{for cases in [u32(2),255,256,65535,65536,0xffffff]!{
			em_layout(input,payload,width,cases)
			for tag in [u32(0),1,cases-1,cases,cases+1,255,256,65535,65536,0xffffff,0xffffffff]!{for bits in [u32(0),0x12345678,0xffffffff]!{
				if width==0{hash=em_mix(hash,em_call(api,api.guard,input.metadata));continue}
				value:=if at_end{span+length-page-width-payload}else{span+page}
				tag_address:=value+payload;tag_page:=tag_address&~(page-1);first_page:=value&~(page-1)
				leading:=if payload<4{payload}else{u64(4)};last_page:=if leading==0{first_page}else{(value+leading-1)&~(page-1)}
				assert C.mprotect(voidptr(tag_page),usize(page),C.PROT_READ|C.PROT_WRITE)==0
				em_bytes(tag_address,tag,width)
				actual_tag:=if width==4{tag}else{tag&((u32(1)<<u32(width*8))-1)}
				if actual_tag>=cases&&payload!=0{
					assert C.mprotect(voidptr(first_page),usize(page),C.PROT_READ|C.PROT_WRITE)==0
					if last_page!=first_page{assert C.mprotect(voidptr(last_page),usize(page),C.PROT_READ|C.PROT_WRITE)==0}
					em_bytes(value,bits,payload)
					assert C.mprotect(voidptr(first_page),usize(page),C.PROT_READ)==0
					if last_page!=first_page{assert C.mprotect(voidptr(last_page),usize(page),C.PROT_READ)==0}
				}else{for part in [first_page,last_page]!{if part!=tag_page{assert C.mprotect(voidptr(part),usize(page),C.PROT_NONE)==0}}}
				assert C.mprotect(voidptr(tag_page),usize(page),C.PROT_READ)==0
				hash=em_mix(hash,em_call(api,value,input.metadata))
			}}
		}}}
		assert C.munmap(voidptr(input.base),usize(page*9))==0
	}}
	return hash
}
fn em_bad(value u64,metadata u64){if _:=swift_enum_case_multi_checked(value,metadata){assert false,'unsupported enum case accepted'}}
fn em_invalid(api EmApi){
	input:=em_input(api,2,true);defer{assert C.munmap(voidptr(input.base),usize(input.page*9))==0}
	em_layout(input,8,1,2)
	for value in [u64(0),~u64(7)]!{em_bad(value,input.metadata)}
	for metadata in [u64(0),1,~u64(7)]!{em_bad(api.guard,metadata)}
	assert C.mprotect(voidptr(input.base+input.page*5),usize(input.page),C.PROT_READ|C.PROT_WRITE)==0
	for kind in [u64(0x200),0x202,0x301,0x400]!{unsafe{*(&u64(input.metadata))=kind};em_bad(api.guard,input.metadata)};unsafe{*(&u64(input.metadata))=0x201}
	for descriptor in [u64(0),1,~u64(3)]!{unsafe{*(&u64(input.metadata+8))=descriptor};em_bad(api.guard,input.metadata)};unsafe{*(&u64(input.metadata+8))=input.descriptor}
	for witness in [u64(0),1,~u64(7)]!{unsafe{*(&u64(input.metadata-8))=witness};em_bad(api.guard,input.metadata)};unsafe{*(&u64(input.metadata-8))=input.witness}
	assert C.mprotect(voidptr(input.base+input.page*1),usize(input.page),C.PROT_READ|C.PROT_WRITE)==0
	for flags in [u32(0x51),0x1d2]!{write32(input.descriptor,flags);em_bad(api.guard,input.metadata)};write32(input.descriptor,0xd2)
	for counts in [u32(2),0x01000002,0x02000000,0x02000001]!{write32(input.descriptor+20,counts);em_bad(api.guard,input.metadata)}
	for pair in [[u64(1048577),1]!,[u64(8),5]!]!{em_layout(input,pair[0],pair[1],2);em_bad(api.guard,input.metadata)}
	em_layout(input,8,1,2)
	assert C.mprotect(voidptr(input.base+input.page*3),usize(input.page),C.PROT_READ|C.PROT_WRITE)==0
	for size in [u64(0),7,14]!{unsafe{*(&u64(input.witness+64))=size};em_bad(api.guard,input.metadata)};unsafe{*(&u64(input.witness+64))=9}
	for stride in [u64(0),8]!{unsafe{*(&u64(input.witness+72))=stride};em_bad(api.guard,input.metadata)};unsafe{*(&u64(input.witness+72))=9}
	for flags in [u32(0),0x600000,0x200002,0x200001]!{write32(input.witness+80,flags);em_bad(api.guard,input.metadata)}
	em_layout(input,8,0,2);assert em_call(api,0,input.metadata)==0&&em_call(api,~u64(0),input.metadata)==0
	ios_runtime.swift_concurrency_retired=true;em_bad(api.guard,api.guard);ios_runtime.swift_concurrency_retired=false
}
fn em_worker(api EmApi,value u64,metadata u64){for _ in 0..256{assert em_call(api,value,metadata)==1}}
fn test_swift_enum_case_multi(){
	page:=usize(C.getpagesize());code:=u64(C.mmap(unsafe{nil},page,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert code!=~u64(0)
	guard:=u64(C.mmap(unsafe{nil},page,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert guard!=~u64(0)
	defer{assert C.munmap(voidptr(code),page)==0;assert C.munmap(voidptr(guard),page)==0}
	em_emit(code);C.__builtin___clear_cache(voidptr(code),voidptr(code+68));assert C.mprotect(voidptr(code),page,C.PROT_READ|C.PROT_EXEC)==0
	mut native_hash:=u64(0)
	$if macos{api:=EmApi{true,em_symbol(true,'_swift_getEnumCaseMultiPayload'),code,guard};native_hash=em_matrix(api);println('NATIVE-ENUM-CASE-MULTI: two-argument C UInt32 ABI, dynamic enum trailing tags zero to four bytes, payloads zero to 1 MiB, 24-bit case counts, small-payload empty-case discriminators and UInt32 wrap, signed borrowed descriptors, protected value/metadata/VWT ends and unused payloads, unchanged x20/x21/x22; hash='+native_hash.hex())}
	for _ in 0..2{
		objc_start();api:=EmApi{false,em_symbol(false,'_swift_getEnumCaseMultiPayload'),code,guard};hash:=em_matrix(api)
		// Native matrix output is independent of addresses, page size or seed.
		// Retain that oracle on guests that cannot load Darwin's Swift runtime.
		assert hash==u64(0xdc421a95655debe5)
		$if macos{assert hash==native_hash}
		println('IOS-ENUM-CASE-MULTI-MATRIX: hash='+hash.hex())
		em_invalid(api)
		input:=em_input(api,255,true);em_layout(input,1048576,1,2)
		value:=u64(C.mmap(unsafe{nil},usize(1048576)+page,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert value!=~u64(0)
		assert C.mprotect(voidptr(value+1048576),page,C.PROT_READ|C.PROT_WRITE)==0;unsafe{*(&u8(value+1048576))=1};assert C.mprotect(voidptr(value+1048576),page,C.PROT_READ)==0
		mut workers:=[]thread{};for _ in 0..8{workers<<spawn em_worker(api,value,input.metadata)};workers.wait();unsafe{workers.free()}
		assert C.munmap(voidptr(value),usize(1048576)+page)==0;assert C.munmap(voidptr(input.base),usize(input.page*9))==0
		assert ios_runtime.live==0&&ios_runtime.swift_heap.len==0&&ios_runtime.swift_generic_value_allocations.len==0
		objc_stop();em_bad(guard,guard)
	}
	println('IOS-ENUM-CASE-MULTI: bounded layout-initialized dynamic multi-payload enum lookup, exact UInt32 tag decoding and empty-case wrap, protected opaque payloads and borrowed headers without callbacks/ARC/writes, invalid layout/state rejection, eight readers and two drained lifetimes')
}

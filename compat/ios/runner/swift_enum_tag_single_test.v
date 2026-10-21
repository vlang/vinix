// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char,i32)voidptr
fn C.dlsym(voidptr,&char)voidptr
type SgProbe=fn(u64,u64,u64,u64,u64,&u64,u64)
type SgGet=fn(u64,u32,u64,u64)u32
struct SgApi { native bool entry u64 code u64 callback u64 guard u64 }
struct SgInput { base u64 page u64 witness u64 metadata u64 trace u64 }
fn sg_symbol(native bool)u64{
	$if macos{if native{library:=C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',2);entry:=u64(C.dlsym(library,c'swift_getEnumTagSinglePayloadGeneric'));assert entry!=0;return entry}}
	return runtime_symbol('/usr/lib/swift/libswiftCore.dylib','_swift_getEnumTagSinglePayloadGeneric') or {panic(err)}
}
fn sg_emit(code u64){
	// x0/value, w1/empty cases, x2/payload metadata, x3/SwiftCC callback.
	for i,op in [u32(0xa9bc7bfd),0xa90153f3,0xa9025bf5,0xaa0503f3,0xaa0403f0,0xaa0603f4,
		u32(0xd2800000|(0x5121<<5)|21),u32(0xd2800000|(0x5222<<5)|22),0xaa0603e8,0xd63f0200,
		0xa9000660,0xa9015674,0xf9001276,0xa9425bf5,0xa94153f3,0xa8c47bfd,0xd65f03c0]!{write32(code+u64(i*4),op)}
	// A leaf app callback records x0/w1/x2 and context registers through a
	// fixture-owned trace pointer, then returns an arbitrary UInt32 unchanged.
	for i,op in [u32(0xf9400049),0xa9000520,0xa9015122,0xa9025935,0xf940192a,0x9100054a,0xf900192a,0xb9403920,0xd65f03c0]!{write32(code+128+u64(i*4),op)}
}
fn sg_call(api SgApi,value u64,cases u32,metadata u64,callback u64)u32{
	mut words:=[u64(0xcafe),0,0,0,0,0,0xbeef]!
	unsafe{SgProbe(voidptr(api.code))(value,cases,metadata,callback,api.entry,&words[1],api.guard)}
	assert words[0]==0xcafe&&words[6]==0xbeef&&words[3]==api.guard&&words[4]==0x5121&&words[5]==0x5222&&words[1]<=0xffffffff
	return u32(words[1])
}
fn sg_input(at_end bool)SgInput{
	page:=u64(C.getpagesize());base:=u64(C.mmap(unsafe{nil},usize(page*9),C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert base!=~u64(0)
	for i in [u64(3),5,7]!{assert C.mprotect(voidptr(base+page*i),usize(page),C.PROT_READ|C.PROT_WRITE)==0}
	w:=if at_end{base+page*4-88}else{base+page*3-64};m:=base+page*6;t:=base+page*7
	unsafe{*(&u64(m-8))=w}
	assert C.mprotect(voidptr(base+page*5),usize(page),C.PROT_READ)==0
	return SgInput{base,page,w,m,t}
}
fn sg_layout(input SgInput,size u64,extra u32,mask u32){
	assert C.mprotect(voidptr(input.base+input.page*3),usize(input.page),C.PROT_READ|C.PROT_WRITE)==0
	unsafe{*(&u64(input.witness+64))=size;*(&u64(input.witness+72))=(if size==0{u64(1)}else{size}+u64(mask))&~u64(mask)}
	write32(input.witness+80,mask);write32(input.witness+84,extra)
	assert C.mprotect(voidptr(input.base+input.page*3),usize(input.page),C.PROT_READ)==0
}
fn sg_callback_page(input SgInput,enabled bool){
	assert C.mprotect(voidptr(input.metadata),usize(input.page),if enabled{C.PROT_READ|C.PROT_WRITE}else{C.PROT_NONE})==0
	if enabled{unsafe{*(&u64(input.metadata))=input.trace};assert C.mprotect(voidptr(input.metadata),usize(input.page),C.PROT_READ)==0}
}
fn sg_bytes(address u64,value u32,width u64){for i in u64(0)..if width<4{width}else{u64(4)}{unsafe{*(&u8(address+i))=u8(value>>u32(i*8))}}}
fn sg_mix(hash u64,value u32)u64{return (hash^u64(value))*u64(1099511628211)}
fn sg_matrix(api SgApi)u64{
	page:=u64(C.getpagesize());length:=u64(1048576)+page*4
	span:=u64(C.mmap(unsafe{nil},usize(length),C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert span!=~u64(0)
	defer{assert C.munmap(voidptr(span),usize(length))==0}
	mut hash:=u64(14695981039346656037)
	for at_end in [false,true]!{
		input:=sg_input(at_end)
		for size in [u64(0),1,2,3,4,8,65536,1048576]!{for extra in [u32(0),1,2,255,65535,0x7fffffff,0xfffffffe,0xffffffff]!{for cases in [u32(0),1,2,254,255,256,65535,65536,0x7fffffff,0xfffffffe,0xffffffff]!{
			sg_layout(input,size,extra,0);width:=u64(swift_optional_extra_width(size,extra,cases))
			for tag in [u32(0),1,2,255,65535,0xffffffff]!{for bits in [u32(0),0x12345678,0xffffffff]!{
				value:=if width==0{api.guard}else if at_end{span+length-page-width-size}else{span+page}
				tag_address:=value+size;tag_page:=tag_address&~(page-1);first_page:=value&~(page-1)
				leading:=if size<4{size}else{u64(4)};last_page:=if leading==0{first_page}else{(value+leading-1)&~(page-1)}
				actual_tag:=if width==0{u32(0)}else if width==4{tag}else{tag&((u32(1)<<u32(width*8))-1)}
				if width!=0{
					assert C.mprotect(voidptr(tag_page),usize(page),C.PROT_READ|C.PROT_WRITE)==0;sg_bytes(tag_address,tag,width)
					if actual_tag!=0&&size!=0{
						for part in [first_page,last_page]!{assert C.mprotect(voidptr(part),usize(page),C.PROT_READ|C.PROT_WRITE)==0}
						sg_bytes(value,bits,size)
						for part in [first_page,last_page]!{assert C.mprotect(voidptr(part),usize(page),C.PROT_READ)==0}
					}else{for part in [first_page,last_page]!{if part!=tag_page{assert C.mprotect(voidptr(part),usize(page),C.PROT_NONE)==0}}}
					assert C.mprotect(voidptr(tag_page),usize(page),C.PROT_READ)==0
				}
				callback_used:=actual_tag==0&&extra>0;sg_callback_page(input,callback_used)
				unsafe{*(&u64(input.trace+48))=0};write32(input.trace+56,bits)
				result:=sg_call(api,value,cases,input.metadata,if callback_used{api.callback}else{api.guard})
				assert read64(input.trace+48)==u64(callback_used)
				if callback_used{assert read64(input.trace)==value&&read64(input.trace+8)==extra&&read64(input.trace+16)==input.metadata&&result==bits}
				hash=sg_mix(sg_mix(hash,result),u32(read64(input.trace+48)))
			}}
		}}}
		// With no tag and no extra inhabitants even null/overflow values and
		// callback pointers are ignored; no metadata body may be read.
		sg_layout(input,1048576,0,255);sg_callback_page(input,false)
		for value in [u64(0),~u64(0),api.guard]!{hash=sg_mix(hash,sg_call(api,value,0,input.metadata,0))}
		assert C.munmap(voidptr(input.base),usize(input.page*9))==0
	}
	return hash
}
fn sg_bad(value u64,cases u32,metadata u64,callback u64){if _:=swift_enum_tag_single_checked(value,cases,metadata,callback){assert false,'unsupported single-payload tag accepted'}}
fn sg_invalid(api SgApi){
	input:=sg_input(false);defer{assert C.munmap(voidptr(input.base),usize(input.page*9))==0}
	sg_layout(input,8,0,0)
	for metadata in [u64(0),1,~u64(7)]!{sg_bad(api.guard,1,metadata,api.guard)}
	for value in [u64(0),~u64(7)]!{sg_bad(value,1,input.metadata,api.guard)}
	assert C.mprotect(voidptr(input.base+input.page*5),usize(input.page),C.PROT_READ|C.PROT_WRITE)==0
	for witness in [u64(0),1,~u64(7)]!{unsafe{*(&u64(input.metadata-8))=witness};sg_bad(api.guard,0,input.metadata,api.guard)};unsafe{*(&u64(input.metadata-8))=input.witness}
	assert C.mprotect(voidptr(input.base+input.page*3),usize(input.page),C.PROT_READ|C.PROT_WRITE)==0
	for size in [u64(1048577),~u64(0)]!{unsafe{*(&u64(input.witness+64))=size};sg_bad(api.guard,0,input.metadata,api.guard)};unsafe{*(&u64(input.witness+64))=8}
	for stride in [u64(0),7,9]!{unsafe{*(&u64(input.witness+72))=stride};write32(input.witness+80,7);sg_bad(api.guard,0,input.metadata,api.guard)};unsafe{*(&u64(input.witness+72))=8}
	for flags in [u32(2),0x400000,0x600000]!{write32(input.witness+80,flags);sg_bad(api.guard,0,input.metadata,api.guard)}
	sg_layout(input,0,1,0)
	for callback in [u64(0),1,~u64(3)]!{sg_bad(api.guard,0,input.metadata,callback)}
	ios_runtime.swift_concurrency_retired=true;sg_bad(api.guard,0,api.guard,api.guard);ios_runtime.swift_concurrency_retired=false
}
fn sg_lookup_worker()u64{return sg_symbol(false)}
fn sg_reenter(value u64,extra u32,metadata u64)u32{
	worker:=spawn sg_lookup_worker();assert worker.wait()!=0
	// Re-enter the public helper with a separate no-XI layout while the app
	// callback is active. Its value and callback must stay opaque.
	trace:=read64(metadata);nested:=read64(trace+64);entry:=unsafe{SgGet(voidptr(sg_symbol(false)))}
	assert entry(value,0,nested,0)==0;return extra
}
fn sg_worker(api SgApi){
	input:=sg_input(true);nested:=sg_input(false)
	sg_layout(input,8,7,7);sg_layout(nested,0,0,0);sg_callback_page(input,true);unsafe{*(&u64(input.trace+64))=nested.metadata}
	for _ in 0..32{assert sg_call(api,api.guard,0,input.metadata,u64(voidptr(sg_reenter)))==7}
	for item in [input,nested]!{assert C.munmap(voidptr(item.base),usize(item.page*9))==0}
}
fn test_swift_enum_tag_single(){
	page:=usize(C.getpagesize());code:=u64(C.mmap(unsafe{nil},page,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert code!=~u64(0)
	guard:=u64(C.mmap(unsafe{nil},page,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert guard!=~u64(0)
	defer{assert C.munmap(voidptr(code),page)==0;assert C.munmap(voidptr(guard),page)==0}
	sg_emit(code);C.__builtin___clear_cache(voidptr(code),voidptr(code+164));assert C.mprotect(voidptr(code),page,C.PROT_READ|C.PROT_EXEC)==0
	mut native_hash:=u64(0)
	$if macos{api:=SgApi{true,sg_symbol(true),code,code+128,guard};native_hash=sg_matrix(api);println('NATIVE-ENUM-TAG-SINGLE: four scalar SwiftCC arguments, x0/w1/x2 callback and UInt32 return; zero-case callback invocation, arbitrary callback results, zero to four tag bytes, UInt32 rounding/wrap, protected borrowed VWT/metadata/value spans and ignored callbacks, unchanged x20/x21/x22; hash='+native_hash.hex())}
	for _ in 0..2{
		objc_start();api:=SgApi{false,sg_symbol(false),code,code+128,guard};hash:=sg_matrix(api)
		// Retain the measured Darwin oracle on Linux guests as well.
		assert hash==u64(0x163855d6a05abae5)
		$if macos{assert hash==native_hash}
		println('IOS-ENUM-TAG-SINGLE-MATRIX: hash='+hash.hex());sg_invalid(api)
		mut workers:=[]thread{};for _ in 0..8{workers<<spawn sg_worker(api)};workers.wait();unsafe{workers.free()}
		assert ios_runtime.live==0&&ios_runtime.swift_heap.len==0&&ios_runtime.swift_generic_value_allocations.len==0
		objc_stop();sg_bad(guard,0,guard,guard)
	}
	println('IOS-ENUM-TAG-SINGLE: bounded generic single-payload enum tag decoding, exact native matrix and callback semantics, protected opaque payloads and borrowed headers, no ARC/writes, invalid layout/state/callback rejection, eight concurrent reentrant callbacks and two drained lifetimes')
}

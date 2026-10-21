// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char,i32)voidptr
fn C.dlsym(voidptr,&char)voidptr
type SsProbe=fn(u64,u64,u64,u64,u64,u64,&u64,u64)
type SsStore=fn(u64,u32,u32,u64,u64)
struct SsApi { native bool entry u64 code u64 callback u64 guard u64 }
struct SsInput { base u64 page u64 witness u64 metadata u64 trace u64 }
fn ss_symbol(native bool)u64{
	$if macos{if native{library:=C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',2);entry:=u64(C.dlsym(library,c'swift_storeEnumTagSinglePayloadGeneric'));assert entry!=0;return entry}}
	return runtime_symbol('/usr/lib/swift/libswiftCore.dylib','_swift_storeEnumTagSinglePayloadGeneric') or {panic(err)}
}
fn ss_emit(code u64){
	// Five scalar SwiftCC arguments; x8 and x20/x21/x22 are guarded too.
	for i,op in [u32(0xa9bc7bfd),0xa90153f3,0xa9025bf5,0xaa0603f3,0xaa0503f0,0xaa0703f4,
		u32(0xd2800000|(0x5121<<5)|21),u32(0xd2800000|(0x5222<<5)|22),0xaa0703e8,0xd63f0200,
		0xa9000660,0xa9015674,0xf9001276,0xa9425bf5,0xa94153f3,0xa8c47bfd,0xd65f03c0]!{write32(code+u64(i*4),op)}
	// Record the callback's x0/w1/w2/x3 through a fixture-owned pointer.
	// Callee-saved registers are checked after the writer returns: it may
	// use them for locals while invoking this callback. Leave the value opaque.
	for i,op in [u32(0xf9400069),0xa9000520,0xa9010d22,0xf9401d2a,0x9100054a,0xf9001d2a,0xd65f03c0]!{write32(code+128+u64(i*4),op)}
}
fn ss_call(api SsApi,value u64,which u32,cases u32,metadata u64,callback u64){
	mut words:=[u64(0xcafe),0,0,0,0,0,0xbeef]!
	unsafe{SsProbe(voidptr(api.code))(value,(u64(0xfeedbeef)<<32)|which,(u64(0xcafefeed)<<32)|cases,metadata,callback,api.entry,&words[1],api.guard)}
	assert words[0]==0xcafe&&words[6]==0xbeef&&words[3]==api.guard&&words[4]==0x5121&&words[5]==0x5222
}
fn ss_input(at_end bool)SsInput{
	page:=u64(C.getpagesize());base:=u64(C.mmap(unsafe{nil},usize(page*9),C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert base!=~u64(0)
	for i in [u64(3),5,7]!{assert C.mprotect(voidptr(base+page*i),usize(page),C.PROT_READ|C.PROT_WRITE)==0}
	w:=if at_end{base+page*4-88}else{base+page*3-64};m:=base+page*6;t:=base+page*7
	unsafe{*(&u64(m-8))=w};assert C.mprotect(voidptr(base+page*5),usize(page),C.PROT_READ)==0
	return SsInput{base,page,w,m,t}
}
fn ss_layout(input SsInput,size u64,extra u32,mask u32){
	assert C.mprotect(voidptr(input.base+input.page*3),usize(input.page),C.PROT_READ|C.PROT_WRITE)==0
	unsafe{*(&u64(input.witness+64))=size;*(&u64(input.witness+72))=(if size==0{u64(1)}else{size}+u64(mask))&~u64(mask)}
	write32(input.witness+80,mask);write32(input.witness+84,extra)
	assert C.mprotect(voidptr(input.base+input.page*3),usize(input.page),C.PROT_READ)==0
}
fn ss_callback_page(input SsInput,enabled bool){
	assert C.mprotect(voidptr(input.metadata),usize(input.page),if enabled{C.PROT_READ|C.PROT_WRITE}else{C.PROT_NONE})==0
	if enabled{unsafe{*(&u64(input.metadata))=input.trace};assert C.mprotect(voidptr(input.metadata),usize(input.page),C.PROT_READ)==0}
}
fn ss_bytes(address u64,value u32,width u64){for i in u64(0)..if width<4{width}else{u64(4)}{unsafe{*(&u8(address+i))=u8(value>>u32(i*8))}}}
fn ss_mix(hash u64,value u32)u64{return (hash^u64(value))*u64(1099511628211)}
fn ss_matrix(api SsApi)u64{
	page:=u64(C.getpagesize());length:=u64(1048576)+page*4
	span:=u64(C.mmap(unsafe{nil},usize(length),C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert span!=~u64(0)
	expected:=u64(C.mmap(unsafe{nil},usize(length),C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert expected!=~u64(0)
	defer{assert C.munmap(voidptr(span),usize(length))==0;assert C.munmap(voidptr(expected),usize(length))==0}
	assert C.mprotect(voidptr(span),usize(page),C.PROT_NONE)==0;assert C.mprotect(voidptr(span+length-page),usize(page),C.PROT_NONE)==0
	mut hash:=u64(14695981039346656037)
	for at_end in [false,true]!{
		input:=ss_input(at_end)
		for size in [u64(0),1,2,3,4,8,31,65536,1048576]!{for extra in [u32(0),1,2,255,65535,0x7fffffff,0xfffffffe,0xffffffff]!{for cases in [u32(0),1,2,254,255,256,65535,65536,0x7fffffff,0xfffffffe,0xffffffff]!{
			ss_layout(input,size,extra,0);width:=u64(swift_optional_extra_width(size,extra,cases));total:=size+width
			for which in [u32(0),1,extra,extra+u32(1),extra+u32(2),cases,0x12345678,0xffffffff]!{
				value:=if at_end{span+length-page-total}else{span+page+1}
				unsafe{C.memset(voidptr(value),0xa5,usize(total));C.memset(voidptr(expected),0xa5,usize(total));*(&u8(value-1))=0x6d}
				if !at_end{unsafe{*(&u8(value+total))=0xd6}}
				callback_used:=which!=0&&which<=extra;ss_callback_page(input,callback_used);unsafe{*(&u64(input.trace+56))=0}
				mut tag:=u32(0)
				if which>extra{
					index:=which-extra-u32(1);tag=if size<4{u32(1)+(index>>u32(size*8))}else{u32(1)}
					unsafe{C.memset(voidptr(expected),0,usize(size))};ss_bytes(expected,index,size)
				}
				ss_bytes(expected+size,tag,width);ss_call(api,value,which,cases,input.metadata,if callback_used{api.callback}else{api.guard})
				assert C.memcmp(voidptr(value),voidptr(expected),usize(total))==0
				assert unsafe{*(&u8(value-1))}==0x6d;if !at_end{assert unsafe{*(&u8(value+total))}==0xd6}
				assert read64(input.trace+56)==u64(callback_used)
				if callback_used{assert read64(input.trace)==value&&u32(read64(input.trace+8))==which&&u32(read64(input.trace+16))==extra&&read64(input.trace+24)==input.metadata}
				hash=ss_mix(ss_mix(ss_mix(hash,swift_enum_case_multi_read(value,size)),swift_enum_case_multi_read(value+size,width)),u32(callback_used))
				if size>4{hash=ss_mix(hash,u32(unsafe{*(&u8(value+size-1))}))}
			}
		}}}
		assert C.munmap(voidptr(input.base),usize(input.page*9))==0
	}
	return hash
}
fn ss_untouched(api SsApi){
	input:=ss_input(true);defer{assert C.munmap(voidptr(input.base),usize(input.page*9))==0}
	ss_layout(input,1048576,7,255);ss_callback_page(input,true)
	for value in [u64(0),~u64(0),api.guard]!{
		ss_call(api,value,0,7,input.metadata,0)
		unsafe{*(&u64(input.trace+56))=0};ss_call(api,value,7,7,input.metadata,api.callback)
		assert read64(input.trace)==value&&read64(input.trace+56)==1
	}
	ss_layout(input,0,0,0);ss_callback_page(input,false)
	for value in [u64(0),~u64(0),api.guard]!{ss_call(api,value,0xffffffff,0,input.metadata,api.guard)}
	ss_layout(input,1048576,0,0)
	page:=usize(C.getpagesize());value:=u64(C.mmap(unsafe{nil},usize(1048576)+page,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert value!=~u64(0)
	defer{assert C.munmap(voidptr(value),usize(1048576)+page)==0}
	assert C.mprotect(voidptr(value+1048576),page,C.PROT_READ|C.PROT_WRITE)==0
	unsafe{*(&u8(value+1048576))=0xff};ss_call(api,value,0,1,input.metadata,api.guard);assert unsafe{*(&u8(value+1048576))}==0
}
fn ss_bad(value u64,which u32,cases u32,metadata u64,callback u64){if _:=swift_enum_store_single_checked(value,which,cases,metadata,callback){assert false,'unsupported single-payload store accepted'}}
fn ss_invalid(api SsApi){
	input:=ss_input(false);defer{assert C.munmap(voidptr(input.base),usize(input.page*9))==0}
	ss_layout(input,8,0,0)
	for metadata in [u64(0),1,~u64(7)]!{ss_bad(api.guard,1,1,metadata,api.guard)}
	for value in [u64(0),~u64(7)]!{ss_bad(value,1,1,input.metadata,api.guard);ss_bad(value,1,0,input.metadata,api.guard)}
	assert C.mprotect(voidptr(input.base+input.page*5),usize(input.page),C.PROT_READ|C.PROT_WRITE)==0
	for witness in [u64(0),1,~u64(7)]!{unsafe{*(&u64(input.metadata-8))=witness};ss_bad(api.guard,0,0,input.metadata,0)};unsafe{*(&u64(input.metadata-8))=input.witness}
	assert C.mprotect(voidptr(input.base+input.page*3),usize(input.page),C.PROT_READ|C.PROT_WRITE)==0
	for size in [u64(1048577),~u64(0)]!{unsafe{*(&u64(input.witness+64))=size};ss_bad(api.guard,0,0,input.metadata,0)};unsafe{*(&u64(input.witness+64))=8}
	for stride in [u64(0),7,9]!{unsafe{*(&u64(input.witness+72))=stride};write32(input.witness+80,7);ss_bad(api.guard,0,0,input.metadata,0)};unsafe{*(&u64(input.witness+72))=8}
	for flags in [u32(2),0x400000,0x600000]!{write32(input.witness+80,flags);ss_bad(api.guard,0,0,input.metadata,0)}
	ss_layout(input,0,1,0)
	// Invalid callbacks are rejected before a pending tag write can touch the guard.
	for callback in [u64(0),1,~u64(3)]!{ss_bad(api.guard,1,2,input.metadata,callback)}
	ios_runtime.swift_concurrency_retired=true;ss_bad(api.guard,0,0,api.guard,0);ios_runtime.swift_concurrency_retired=false
}
fn ss_lookup_worker()u64{return ss_symbol(false)}
fn ss_reenter(value u64,which u32,extra u32,metadata u64){
	worker:=spawn ss_lookup_worker();assert worker.wait()!=0
	assert which==7&&extra==7&&unsafe{*(&u8(value+8))}==0
	trace:=read64(metadata);nested:=read64(trace+64);entry:=unsafe{SsStore(voidptr(ss_symbol(false)))}
	entry(~u64(0),0,0,nested,0);unsafe{*(&u8(value))=u8(which);*(&u64(trace+56))+=1}
}
fn ss_worker(api SsApi){
	input:=ss_input(true);nested:=ss_input(false)
	ss_layout(input,8,7,7);ss_layout(nested,0,0,0);ss_callback_page(input,true);unsafe{*(&u64(input.trace+64))=nested.metadata;*(&u64(input.trace+56))=0}
	mut value:=[u8(0xa5),0xa5,0xa5,0xa5,0xa5,0xa5,0xa5,0xa5,0xff,0xd6]!
	for _ in 0..32{value[8]=0xff;ss_call(api,u64(unsafe{&value[0]}),7,8,input.metadata,u64(voidptr(ss_reenter)));assert value==[u8(7),0xa5,0xa5,0xa5,0xa5,0xa5,0xa5,0xa5,0,0xd6]!}
	assert read64(input.trace+56)==32
	for item in [input,nested]!{assert C.munmap(voidptr(item.base),usize(item.page*9))==0}
}
fn test_swift_enum_store_single(){
	page:=usize(C.getpagesize());code:=u64(C.mmap(unsafe{nil},page,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert code!=~u64(0)
	guard:=u64(C.mmap(unsafe{nil},page,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert guard!=~u64(0)
	defer{assert C.munmap(voidptr(code),page)==0;assert C.munmap(voidptr(guard),page)==0}
	ss_emit(code);C.__builtin___clear_cache(voidptr(code),voidptr(code+164));assert C.mprotect(voidptr(code),page,C.PROT_READ|C.PROT_EXEC)==0
	mut native_hash:=u64(0)
	$if macos{api:=SsApi{true,ss_symbol(true),code,code+128,guard};native_hash=ss_matrix(api);ss_untouched(api);println('IOS-ENUM-STORE-SINGLE-NATIVE: five scalar SwiftCC arguments, x0/w1/w2/x3 callback, low UInt32 arguments, zero to four tag bytes, UInt32 wrap, complete byte comparison, protected borrowed headers and opaque values, preserved x20/x21/x22; hash='+native_hash.hex())}
	for _ in 0..2{
		objc_start();api:=SsApi{false,ss_symbol(false),code,code+128,guard};hash:=ss_matrix(api)
		assert hash==0xa923b8b4fd5af3a5
		$if macos{assert hash==native_hash}
		println('IOS-ENUM-STORE-SINGLE-MATRIX: hash='+hash.hex());ss_untouched(api);ss_invalid(api)
		mut workers:=[]thread{};for _ in 0..8{workers<<spawn ss_worker(api)};workers.wait();unsafe{workers.free()}
		assert ios_runtime.live==0&&ios_runtime.swift_heap.len==0&&ios_runtime.swift_generic_value_allocations.len==0
		objc_stop();ss_bad(guard,0,0,guard,0)
	}
	println('IOS-ENUM-STORE-SINGLE: bounded single-payload tag stores, tag clearing before extra-inhabitant callbacks, empty-payload zeroing, native matrix, no ARC/allocation, invalid layout/state/callback rejection, eight reentrant workers and two drained lifetimes')
}

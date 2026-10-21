// SPDX-License-Identifier: GPL-2.0-or-later
module main
#include <dlfcn.h>
fn C.dlopen(&char,i32)voidptr
fn C.dlsym(voidptr,&char)voidptr
fn C.mincore(voidptr,usize,&u8)i32
type SmGet=fn(u64,u64)SwiftAssociatedMetadata
type SmSign=fn(u64,u64)u64
type SmProbe=fn(u64,u64,u64,u64,u64,&u64,u64)
struct SmApi { native bool entry u64 code u64 guard u64 }
struct SmInput { base u64 page u64 descriptor u64 metadata u64 witness u64 cache u64 trace u64 }
fn sm_lookup()u64{return runtime_symbol('/usr/lib/swift/libswiftCore.dylib','_swift_getSingletonMetadata') or {panic(err)}}
fn sm_api(native bool,code u64,guard u64)SmApi{
	$if macos{if native{core:=C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',2);entry:=u64(C.dlsym(core,c'swift_getSingletonMetadata'));assert entry!=0;return SmApi{true,entry,code,guard}}}
	return SmApi{false,sm_lookup(),code,guard}
}
fn sm_call(api SmApi,request u64,descriptor u64)SwiftAssociatedMetadata{
	mut words:=[u64(0xcafe),0,0,0,0,0,0xbeef]!
	unsafe{SmProbe(voidptr(api.code))(request,descriptor,api.guard,api.guard,api.entry,&words[1],api.guard)}
	assert words[0]==0xcafe&&words[6]==0xbeef&&words[3]==api.guard&&words[4]==0x5121&&words[5]==0x5222
	return SwiftAssociatedMetadata{words[1],words[2]}
}
fn sm_complete(metadata u64,context u64,pattern u64)SwiftAssociatedMetadata{
	assert pattern==0
	for i in 0..4{assert read64(context+u64(i*8))==0;unsafe{*(&u64(context+u64(i*8)))=u64(0x3100+i)}}
	descriptor:=read64(metadata+8)&0x0000ffffffffffff;trace:=u64(i64(descriptor+16)+i64(i32(read32(descriptor+16))))
	assert C.ios_ref_change(unsafe{&i64(trace)},1)==0
	cache:=u64(i64(descriptor+28)+i64(i32(read32(descriptor+28))));assert C.ios_load_pointer(unsafe{&u64(cache)})==0
	if read64(trace+24)!=0{C.pthread_mutex_lock(voidptr(trace+128));C.pthread_mutex_unlock(voidptr(trace+128))}
	if read64(trace+48)!=0{
		worker:=spawn sm_lookup();assert worker.wait()==read64(trace+16)
		get:=unsafe{SmGet(voidptr(read64(trace+16)))};partial:=get(0x1ff,descriptor);assert partial.metadata==metadata&&partial.state==read64(trace+72)
		if _:=swift_singleton_metadata_checked(0,descriptor){assert false}
		if read64(trace+56)!=0{nested:=get(0,read64(trace+56));assert nested.metadata!=0&&nested.state==0}
	}
	witness:=read64(metadata-8)
	if read64(trace+40)!=1{unsafe{*(&u64(witness+64))=8;*(&u64(witness+72))=8};write32(witness+80,7);write32(witness+84,0)}
	for i in 0..4{unsafe{*(&u64(metadata+16+u64(i*8)))=u64(0x4100+i)}}
	match read64(trace+40){2{unsafe{*(&u64(metadata+8))=0}}3{unsafe{*(&u64(metadata))=0x301}}4{unsafe{*(&u64(witness+72))=0}}else{}}
	return SwiftAssociatedMetadata{read64(trace+32),~u64(0)} // state unused when dependency is nil
}
fn sm_input(api SmApi,kind u32,incomplete bool,at_end bool)SmInput{
	page:=u64(C.getpagesize());base:=u64(C.mmap(unsafe{nil},usize(page*9),C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert base!=~u64(0)
	for i in [u64(1),3,5,7]!{assert C.mprotect(voidptr(base+page*i),usize(page),C.PROT_READ|C.PROT_WRITE)==0}
	d:=base+page+if at_end{page-40}else{u64(0)};m:=base+page*3+if at_end{page-48}else{u64(8)}
	w:=base+page*5+if at_end{page-88}else{u64(0)};cache:=base+page*7;trace:=cache+64
	write32(d,if kind==0x200{u32(0x10051)}else{u32(0x10052)});write32(d+4,0x80000000);write32(d+8,0x80000000);write32(d+12,0x80000000)
	swift_protocol_relative(d+16,trace);write32(d+20,if kind==0x200{u32(4)}else{u32(1)});write32(d+24,if kind==0x200{u32(2)}else{u32(1)})
	swift_protocol_relative(d+28,cache);swift_protocol_relative(d+32,m);swift_protocol_relative(d+36,api.code+256)
	signed:=if api.native{unsafe{SmSign(voidptr(api.code+128))(d,0xae86)}}else{d}
	unsafe{*(&u64(m-8))=w;*(&u64(m))=kind;*(&u64(m+8))=signed;*(&u64(w+64))=8;*(&u64(w+72))=8;*(&u64(trace+8))=u64(api.native);*(&u64(trace+16))=api.entry;*(&u64(trace+72))=if incomplete{u64(0xff)}else{u64(0x3f)}}
	write32(w+80,if incomplete{u32(0x400007)}else{u32(7)})
	assert C.ios_mutex_create(unsafe{&u64(trace+128)},0)==0
	assert C.mprotect(voidptr(base+page),usize(page),C.PROT_READ)==0
	return SmInput{base,page,d,m,w,cache,trace}
}
fn sm_check(api SmApi,input SmInput,request u64)u64{
	response:=sm_call(api,request,input.descriptor);assert response.metadata==input.metadata&&response.state==0
	assert C.ios_load_pointer(unsafe{&u64(input.cache)})==input.metadata&&read64(input.trace)==1
	for i in 0..4{assert read64(input.metadata+16+u64(i*8))==u64(0x4100+i)}
	if !api.native{
		assert read64(input.cache+8)==0
		checked:=swift_metadata_state_checked(request,input.metadata) or {panic(err)};assert checked.metadata==input.metadata&&checked.state==0
	}
	return response.metadata
}
fn sm_worker(api SmApi,input SmInput)u64{return sm_check(api,input,0)}
fn sm_generic_complete(descriptor u64,_arguments u64,_pattern u64)u64{trace:=u64(i64(descriptor+16)+i64(i32(read32(descriptor+16))));return read64(trace+88)}
fn sm_generic_case(api SmApi)SmInput{
	input:=sm_input(api,0x200,false,false);d:=input.descriptor;p:=d+64
	assert C.mprotect(voidptr(input.base+input.page),usize(input.page),C.PROT_READ|C.PROT_WRITE)==0
	write32(d,0xd1);swift_protocol_relative(d+32,p);write32(d+36,0);write32(d+40,0);swift_protocol_relative(p,api.code+288);write32(p+4,0);write32(p+8,0x40000000);unsafe{*(&u64(input.trace+88))=input.metadata}
	assert C.mprotect(voidptr(input.base+input.page),usize(input.page),C.PROT_READ)==0
	result:=swift_generic_metadata_checked(0,0,d) or {panic(err)};assert result.metadata==input.metadata&&result.state==0
	return input
}
fn sm_matrix(api SmApi)[]SmInput{
	mut inputs:=[]SmInput{}
	for kind in [u32(0x200),0x201]!{for incomplete in [false,true]!{for request in [u64(0),1,0x3f,0xff,0x100,0x101,0x13f,0x1ff]!{
		input:=sm_input(api,kind,incomplete,request&1!=0);inputs<<input;sm_check(api,input,request)
		assert C.mprotect(voidptr(input.base+input.page*3),usize(input.page),C.PROT_READ)==0&&C.mprotect(voidptr(input.base+input.page*5),usize(input.page),C.PROT_READ)==0
		for next in [u64(0),1,0x3f,0xff,0x100,0x101,0x13f,0x1ff]!{sm_check(api,input,next)}
	}}}
	for incomplete in [false,true]!{
		input:=sm_input(api,0x200,incomplete,true);inputs<<input;unsafe{*(&u64(input.trace+24))=1}
		C.pthread_mutex_lock(voidptr(input.trace+128));worker:=spawn sm_worker(api,input)
		for C.ios_load_pointer(unsafe{&u64(input.trace)})==0{C.usleep(1000)}
		for request in [u64(0x100),0x101,0x13f,0x1ff,0xff]!{partial:=sm_call(api,request,input.descriptor);assert partial.metadata==input.metadata&&partial.state==read64(input.trace+72)}
		assert C.ios_load_pointer(unsafe{&u64(input.cache)})==0
		C.pthread_mutex_unlock(voidptr(input.trace+128));assert worker.wait()==input.metadata;sm_check(api,input,0)
	}
	input:=sm_input(api,0x201,true,false);inputs<<input
	if !api.native{nested:=sm_input(api,0x200,true,true);inputs<<nested;unsafe{*(&u64(input.trace+48))=1;*(&u64(input.trace+56))=nested.descriptor}}
	mut workers:=[]thread u64{};for _ in 0..8{workers<<spawn sm_worker(api,input)};results:=workers.wait();for result in results{assert result==input.metadata};assert read64(input.trace)==1;unsafe{workers.free();results.free()}
	return inputs
}
fn sm_bad(request u64,descriptor u64){if _:=swift_singleton_metadata_checked(request,descriptor){assert false,'unsupported singleton accepted'}}
fn sm_invalid(api SmApi)[]SmInput{
	mut inputs:=[]SmInput{};input:=sm_input(api,0x200,true,true);inputs<<input
	for request in [u64(2),0x40,0x200,~u64(0)]!{sm_bad(request,api.guard)};for descriptor in [u64(0),1,~u64(3)]!{sm_bad(0,descriptor)}
	assert C.mprotect(voidptr(input.base+input.page),usize(input.page),C.PROT_READ|C.PROT_WRITE)==0
	for flags in [u32(0x51),0x10050,0x100d1,0x10151,0x50051,0x90051,0x40010051]!{write32(input.descriptor,flags);sm_bad(0,input.descriptor)}
	write32(input.descriptor,0x10051);write32(input.descriptor+20,65);sm_bad(0,input.descriptor);write32(input.descriptor+20,4)
	for offset in [u32(0),1,129]!{write32(input.descriptor+24,offset);sm_bad(0,input.descriptor)};write32(input.descriptor+24,2)
	for field in [u64(28),32,36]!{saved:=read32(input.descriptor+field);write32(input.descriptor+field,0);sm_bad(0,input.descriptor);write32(input.descriptor+field,saved)}
	assert read64(input.trace)==0
	unsafe{*(&u64(input.cache+8))=api.guard};sm_bad(0,input.descriptor);unsafe{*(&u64(input.cache+8))=0;*(&u64(input.cache))=input.metadata};sm_bad(0,input.descriptor);unsafe{*(&u64(input.cache))=0}
	assert C.mprotect(voidptr(input.base+input.page),usize(input.page),C.PROT_READ)==0
	for mode in [u64(1),2,3,4]!{bad:=sm_input(api,0x201,true,true);inputs<<bad;unsafe{*(&u64(bad.trace+40))=mode};sm_bad(0,bad.descriptor);sm_bad(0,bad.descriptor);assert read64(bad.trace)==1&&read64(bad.cache)==0}
	bad:=sm_input(api,0x200,true,false);inputs<<bad;unsafe{*(&u64(bad.trace+32))=api.guard};sm_bad(0,bad.descriptor);sm_bad(0,bad.descriptor);assert read64(bad.trace)==1&&read64(bad.cache)==0
	ios_runtime.swift_generic_metadata_retired=true;sm_bad(0,api.guard);ios_runtime.swift_generic_metadata_retired=false
	for ios_runtime.swift_generic_metadata_count<64{extra:=sm_input(api,0x200,true,false);inputs<<extra;sm_check(api,extra,0)}
	extra:=sm_input(api,0x200,true,false);inputs<<extra;sm_bad(0,extra.descriptor);assert read64(extra.trace)==0
	return inputs
}
fn test_swift_singleton_metadata(){
	page:=usize(C.getpagesize());code:=u64(C.mmap(unsafe{nil},page,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));guard:=u64(C.mmap(unsafe{nil},page,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert code!=~u64(0)&&guard!=~u64(0)
	defer{assert C.munmap(voidptr(code),page)==0&&C.munmap(voidptr(guard),page)==0}
	for i,op in [u32(0xa9bc7bfd),0xa90153f3,0xa9025bf5,0xaa0503f3,0xaa0403f0,0xaa0603f4,u32(0xd2800000|(0x5121<<5)|21),u32(0xd2800000|(0x5222<<5)|22),0xaa0603e8,0xd63f0200,0xa9000660,0xa9015674,0xf9001276,0xa9425bf5,0xa94153f3,0xa8c47bfd,0xd65f03c0]!{write32(code+u64(i*4),op)}
	write32(code+128,0xdac10820);write32(code+132,0xd65f03c0);write32(code+256,0x58000050);write32(code+260,0xd61f0200);unsafe{*(&u64(code+264))=u64(voidptr(sm_complete))}
	write32(code+288,0x58000050);write32(code+292,0xd61f0200);unsafe{*(&u64(code+296))=u64(voidptr(sm_generic_complete))}
	C.__builtin___clear_cache(voidptr(code),voidptr(code+304));assert C.mprotect(voidptr(code),page,C.PROT_READ|C.PROT_EXEC)==0
	$if macos{inputs:=sm_matrix(sm_api(true,code,guard));unsafe{inputs.free()};println('NATIVE-SINGLETON-METADATA: SwiftCC request/descriptor and x0/x1 response, four-word zero completion context and null pattern, both value kinds, all eight cold/warm request modes, Abstract/LayoutComplete busy responses, one completion across eight readers and preserved x20/x21/x22')}
	sm_bad(0,guard)
	for _ in 0..2{
		objc_start();api:=sm_api(false,code,guard);mixed:=sm_generic_case(api);mut inputs:=sm_matrix(api);inputs<<mixed;invalid:=sm_invalid(api);inputs<<invalid;unsafe{invalid.free()}
		assert (swift_generic_metadata_checked(0,0,mixed.descriptor) or {panic(err)}).metadata==mixed.metadata
		arena:=ios_runtime.swift_generic_metadata_arena;assert ios_runtime.swift_generic_metadata_users==0;objc_stop();assert ios_runtime.swift_generic_metadata_arena==0&&ios_runtime.swift_generic_metadata_count==0
		$if macos{assert C.mprotect(voidptr(arena),page,C.PROT_READ)==-1}$else{mut resident:=u8(0);assert C.mincore(voidptr(arena),page,&resident)==-1}
		sm_bad(0,guard)
		for input in inputs{assert read64(input.trace)<=1;assert C.pthread_mutex_destroy(voidptr(input.trace+128))==0;assert C.munmap(voidptr(input.base),usize(input.page*9))==0};unsafe{inputs.free()}
	}
	println('IOS-SINGLETON-METADATA: bounded in-place value completion and release cache publication, native scalar request/state ABI and busy partial responses, shared 64-entry arena, metadata-state completion recognition, unlocked nested/registry reentry and recursive rejection, dependency/malformed result poisoning without publication, guarded borrowed storage and two drained/unmapped lifetimes')
}

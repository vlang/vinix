// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char,i32)voidptr
fn C.dlsym(voidptr,&char)voidptr
fn C.mincore(voidptr,usize,&u8)i32
type GmAllocate=fn(u64,u64,u64,u64)u64
type GmProbe=fn(u64,u64,u64,u64,u64,&u64,u64)
struct GmApi { native bool entry u64 allocate u64 integer u64 other u64 code u64 guard u64 }
struct GmInput { base u64 page u64 descriptor u64 pattern u64 arguments u64 trace u64 count int }
fn gm_symbol(native bool,name string)u64{
	$if macos{if native{library:=C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',2);entry:=u64(C.dlsym(library,name[1..].str));assert entry!=0,name;return entry}}
	return runtime_symbol('/usr/lib/swift/libswiftCore.dylib',name) or {panic(err)}
}
fn gm_lookup()u64{C.ios_objc_initialize_lock();defer{C.ios_objc_initialize_unlock()};return gm_symbol(false,'_swift_getGenericMetadata')}
fn gm_instantiate(descriptor u64,arguments u64,pattern u64)u64{
	trace:=u64(i64(descriptor+16)+i64(i32(read32(descriptor+16))))
	assert read64(trace+16)==pattern;unsafe{*(&u64(trace+8))=read64(trace+8)+1}
	if read64(trace+24)!=0{
		reader:=spawn gm_lookup();assert reader.wait()==read64(trace+32)
		if read64(trace+64)!=0{
			nested:=swift_generic_metadata_checked(0,read64(trace+72),read64(trace+64)) or {panic(err)}
			assert nested.metadata!=0&&nested.state==0
		}
		if read64(trace+40)!=0{
			// Same-thread allocation recursion must fail without locking the
			// entry mutex again. It must not poison the outer instantiation.
			if _:=swift_generic_metadata_checked(0,arguments,descriptor){assert false}
		}
	}
	if read64(trace+56)!=0{return read64(trace+56)}
	allocate:=unsafe{GmAllocate(voidptr(read64(trace)))}
	metadata:=allocate(descriptor,arguments,pattern,u64(swift_generic_value_half(descriptor+40))*8)
	if read64(trace+48)!=0{unsafe{*(&u64(metadata))=0x301}}
	return metadata
}
fn gm_input(api GmApi,kind u32,count int,at_end bool)GmInput{
	page:=u64(C.getpagesize());base:=u64(C.mmap(unsafe{nil},usize(page*11),C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert base!=~u64(0)
	for i in [u64(1),3,5,7,9]!{assert C.mprotect(voidptr(base+page*i),usize(page),C.PROT_READ|C.PROT_WRITE)==0}
	d:=base+page+if at_end{page-u64(44+((count+3)&~3))}else{u64(0)}
	p:=base+page*3+if at_end{page-16}else{u64(64)};a:=if count==0{api.guard}else{base+page*5+if at_end{page-u64(count*8)}else{u64(0)}}
	w:=base+page*7+if at_end{page-88}else{u64(0)};t:=base+page*9;code:=base+page*7+128
	write32(d,if kind==0x200{u32(0xd1)}else{u32(0xd2)})
	swift_protocol_relative(d+4,base+page*3);swift_protocol_relative(d+8,t+128);swift_protocol_relative(d+16,t)
	C.memcpy(voidptr(t+128),c'GenericFixture',15);swift_protocol_relative(base+page*3+8,t+160);C.memcpy(voidptr(t+160),c'Fixture',8)
	swift_protocol_relative(d+32,p);write32(d+36,u32(count));write32(d+40,u32(count))
	for i in 0..count{unsafe{*(&u8(d+44+u64(i)))=0x80;*(&u64(a+u64(i*8)))=api.integer}}
	write32(code,0x58000050);write32(code+4,0xd61f0200);unsafe{*(&u64(code+8))=u64(voidptr(gm_instantiate))}
	swift_protocol_relative(p,code);write32(p+8,kind<<21);swift_protocol_relative(p+12,w)
	unsafe{*(&u64(w+64))=0;*(&u64(w+72))=1;*(&u64(t))=api.allocate;*(&u64(t+16))=p;*(&u64(t+24))=u64(!api.native);*(&u64(t+32))=api.entry}
	C.__builtin___clear_cache(voidptr(code),voidptr(code+16))
	for i in [u64(1),3,5]!{assert C.mprotect(voidptr(base+page*i),usize(page),C.PROT_READ)==0}
	assert C.mprotect(voidptr(base+page*7),usize(page),C.PROT_READ|C.PROT_EXEC)==0
	return GmInput{base,page,d,p,a,t,count}
}
fn gm_call(api GmApi,request u64,arguments u64,descriptor u64)SwiftAssociatedMetadata{
	mut words:=[u64(0xcafe),0,0,0,0,0,0xbeef]!
	unsafe{GmProbe(voidptr(api.code))(request,arguments,descriptor,api.guard,api.entry,&words[1],api.guard)}
	assert words[0]==0xcafe&&words[6]==0xbeef&&words[3]==api.guard&&words[4]==0x5121&&words[5]==0x5222
	return SwiftAssociatedMetadata{words[1],words[2]}
}
fn gm_check(api GmApi,input GmInput,argument u64)u64{
	mut first:=u64(0)
	for request in [u64(0),1,0x3f,0xff,0x100,0x101,0x13f,0x1ff]!{
		response:=gm_call(api,request,input.arguments,input.descriptor)
		assert response.metadata!=0&&response.state==0
		if first==0{first=response.metadata}else{assert response.metadata==first}
		assert read64(first)==if read32(input.descriptor)&31==17{u64(0x200)}else{u64(0x201)}
		assert read64(first+8)&0x0000ffffffffffff==input.descriptor
		for i in 0..input.count{assert read64(first+16+u64(i*8))==if i==0{argument}else{api.integer}}
		if !api.native{checked:=swift_metadata_state_checked(request,first) or {panic(err)};assert checked.metadata==first&&checked.state==0}
	}
	return first
}
fn gm_worker(api GmApi,input GmInput)u64{return gm_check(api,input,api.integer)}
fn gm_matrix(api GmApi)[]GmInput{
	mut inputs:=[]GmInput{}
	for kind in [u32(0x200),0x201]!{for count in [0,1,3,64]!{for at_end in [false,true]!{
		input:=gm_input(api,kind,count,at_end);inputs<<input
		first:=gm_check(api,input,api.integer);assert read64(input.trace+8)==1
		if count!=0{
			// Different argument-vector addresses retain the same key. A
			// changed type key selects a new specialization of the descriptor.
			mut copy:=[64]u64{};for i in 0..count{copy[i]=api.integer}
			assert gm_call(api,0,u64(unsafe{&copy[0]}),input.descriptor).metadata==first
			assert C.mprotect(voidptr(input.base+input.page*5),usize(input.page),C.PROT_READ|C.PROT_WRITE)==0
			unsafe{*(&u64(input.arguments))=api.other}
			second:=gm_check(api,input,api.other);assert second!=first&&read64(input.trace+8)==2
			unsafe{*(&u64(input.arguments))=api.integer}
			assert C.mprotect(voidptr(input.base+input.page*5),usize(input.page),C.PROT_READ)==0
			assert gm_check(api,input,api.integer)==first&&read64(input.trace+8)==2
		}
	}}}
	input:=gm_input(api,0x200,3,true);inputs<<input
	if !api.native{nested:=gm_input(api,0x201,0,false);inputs<<nested;unsafe{*(&u64(input.trace+40))=1;*(&u64(input.trace+64))=nested.descriptor;*(&u64(input.trace+72))=nested.arguments}}
	mut workers:=[]thread u64{};for _ in 0..8{workers<<spawn gm_worker(api,input)};values:=workers.wait()
	for value in values{assert value==values[0]};assert read64(input.trace+8)==1;unsafe{workers.free();values.free()}
	return inputs
}
fn gm_bad(request u64,arguments u64,descriptor u64){if _:=swift_generic_metadata_checked(request,arguments,descriptor){assert false,'unsupported generic metadata accepted'}}
fn gm_invalid(api GmApi)GmInput{
	input:=gm_input(api,0x200,1,true)
	for request in [u64(2),0x40,0x200,~u64(0)]!{gm_bad(request,api.guard,api.guard)}
	for descriptor in [u64(0),1,~u64(3)]!{gm_bad(0,api.guard,descriptor)}
	for arguments in [u64(0),1,~u64(7)]!{gm_bad(0,arguments,input.descriptor)}
	assert C.mprotect(voidptr(input.base+input.page),usize(input.page),C.PROT_READ|C.PROT_WRITE)==0
	for flags in [u32(0x51),0xd0,0x1d1,0x100d1]!{write32(input.descriptor,flags);gm_bad(0,input.arguments,input.descriptor)};write32(input.descriptor,0xd1)
	for pair in [[u32(65),65]!,[u32(0x10001),1]!,[u32(1),0x10001]!,[u32(1),0]!]!{write32(input.descriptor+36,pair[0]);write32(input.descriptor+40,pair[1]);gm_bad(0,input.arguments,input.descriptor)};write32(input.descriptor+36,1);write32(input.descriptor+40,1)
	for parameter in [u8(0),0x81]!{unsafe{*(&u8(input.descriptor+44))=parameter};gm_bad(0,input.arguments,input.descriptor)};unsafe{*(&u8(input.descriptor+44))=0x80}
	assert C.mprotect(voidptr(input.base+input.page*5),usize(input.page),C.PROT_READ|C.PROT_WRITE)==0
	unsafe{*(&u64(input.arguments))=0};gm_bad(0,input.arguments,input.descriptor);unsafe{*(&u64(input.arguments))=api.integer}
	assert C.mprotect(voidptr(input.base+input.page*3),usize(input.page),C.PROT_READ|C.PROT_WRITE)==0
	for completion in [u32(1),0xfffffffc]!{write32(input.pattern+4,completion);gm_bad(0,input.arguments,input.descriptor)};write32(input.pattern+4,0)
	for flags in [u32(0),0x40000002,0x40200000]!{write32(input.pattern+8,flags);gm_bad(0,input.arguments,input.descriptor)};write32(input.pattern+8,0x40000000)
	for field in [input.descriptor+32,input.pattern]!{saved:=read32(field);write32(field,0);gm_bad(0,input.arguments,input.descriptor);write32(field,saved)}
	assert read64(input.trace+8)==0
	unsafe{*(&u64(input.trace+48))=1};gm_bad(0,input.arguments,input.descriptor);assert read64(input.trace+8)==1
	// A failed instantiator result is never returned or re-instantiated.
	gm_bad(0,input.arguments,input.descriptor);assert read64(input.trace+8)==1
	ios_runtime.swift_generic_metadata_retired=true;gm_bad(0,api.guard,api.guard);ios_runtime.swift_generic_metadata_retired=false
	return input
}
fn gm_borrowed(api GmApi)GmInput{
	input:=gm_input(api,0x200,0,false);metadata:=input.base+input.page*5+8
	assert C.mprotect(voidptr(input.base+input.page*5),usize(input.page),C.PROT_READ|C.PROT_WRITE)==0
	witness:=u64(i64(input.pattern+12)+i64(i32(read32(input.pattern+12))))
	unsafe{*(&u64(metadata-8))=witness;*(&u64(metadata))=0x200;*(&u64(metadata+8))=input.descriptor;*(&u64(input.trace+56))=metadata}
	assert C.mprotect(voidptr(input.base+input.page*5),usize(input.page),C.PROT_READ)==0
	assert gm_check(api,input,api.integer)==metadata&&read64(input.trace+8)==1
	return input
}
fn gm_capacity(api GmApi)[]GmInput{
	mut inputs:=[]GmInput{}
	for ios_runtime.swift_generic_metadata_count<64{
		input:=gm_input(api,0x201,0,true);inputs<<input;gm_check(api,input,api.integer)
	}
	input:=gm_input(api,0x200,0,false);inputs<<input
	gm_bad(0,input.arguments,input.descriptor);assert read64(input.trace+8)==0&&ios_runtime.swift_generic_metadata_count==64
	return inputs
}
fn test_swift_generic_metadata(){
	page:=usize(C.getpagesize());code:=u64(C.mmap(unsafe{nil},page,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));guard:=u64(C.mmap(unsafe{nil},page,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert code!=~u64(0)&&guard!=~u64(0)
	defer{assert C.munmap(voidptr(code),page)==0;assert C.munmap(voidptr(guard),page)==0}
	for i,op in [u32(0xa9bc7bfd),0xa90153f3,0xa9025bf5,0xaa0503f3,0xaa0403f0,0xaa0603f4,u32(0xd2800000|(0x5121<<5)|21),u32(0xd2800000|(0x5222<<5)|22),0xaa0603e8,0xd63f0200,0xa9000660,0xa9015674,0xf9001276,0xa9425bf5,0xa94153f3,0xa8c47bfd,0xd65f03c0]!{write32(code+u64(i*4),op)}
	C.__builtin___clear_cache(voidptr(code),voidptr(code+68));assert C.mprotect(voidptr(code),page,C.PROT_READ|C.PROT_EXEC)==0
	$if macos{
		api:=GmApi{true,gm_symbol(true,'_swift_getGenericMetadata'),gm_symbol(true,'_swift_allocateGenericValueMetadata'),gm_symbol(true,'_$sSiN'),gm_symbol(true,'_$ss6UInt64VN'),code,guard}
		inputs:=gm_matrix(api);assert inputs.len==17;unsafe{inputs.free()}
		println('NATIVE-GENERIC-METADATA: scalar SwiftCC request/arguments/descriptor, x0/x1 complete metadata response, C three-argument instantiator, immutable guarded generic struct/enum descriptors and patterns, zero/one/three/64 complete type keys, argument-vector identity independence and distinct keys, all eight request modes, one instantiation across eight readers, preserved x20/x21/x22')
	}
	for _ in 0..2{
		objc_start();api:=GmApi{false,gm_symbol(false,'_swift_getGenericMetadata'),gm_symbol(false,'_swift_allocateGenericValueMetadata'),gm_symbol(false,'_$sSiN'),gm_symbol(false,'_$ss6UInt64VN'),code,guard}
		mut inputs:=gm_matrix(api);inputs<<gm_invalid(api);inputs<<gm_borrowed(api)
		assert ios_runtime.swift_generic_metadata_count==32&&ios_runtime.swift_generic_metadata_users==0
		capacity:=gm_capacity(api);inputs<<capacity;unsafe{capacity.free()}
		base:=ios_runtime.swift_generic_metadata_arena;objc_stop();assert ios_runtime.swift_generic_metadata_arena==0&&ios_runtime.swift_generic_metadata_count==0
		$if macos{assert C.mprotect(voidptr(base),page,C.PROT_READ)==-1}$else{mut resident:=u8(0);assert C.mincore(voidptr(base),page,&resident)==-1}
		gm_bad(0,guard,guard)
		for input in inputs{if read64(input.trace+56)!=0{assert read64(read64(input.trace+56))==0x200};assert C.munmap(voidptr(input.base),usize(input.page*11))==0};unsafe{inputs.free()}
	}
	println('IOS-GENERIC-METADATA: bounded complete-pattern generic value metadata uniquing, native request/response and instantiation ABI, 64 type keys and cache entries, eight concurrent readers and reentrant lookup, recursive-allocation and malformed signature/pattern/result rejection, no duplicate callback or ownership transfer, recognized complete cache results and two drained lifetimes')
}

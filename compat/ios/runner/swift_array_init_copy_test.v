// SPDX-License-Identifier: GPL-2.0-or-later
module main

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
type AcInitialize = fn(u64,u64,u64,u64)
type AcAccess = fn(u64)SwiftAssociatedMetadata
type AcSign = fn(u64,u64)u64
struct AcApi {
	native bool
	initialize AcInitialize @[required]
	metadata [4]u64
}
struct AcState {
	api AcApi
	size u64
	stride u64
	source u64
	destination u64
	owned bool
	reenter bool
mut:
	visited u64
}
struct AcSpan { base u64 length usize value u64 span u64 }
fn ac_symbol(native bool,library string,name string)u64{
	$if macos{if native{handle:=C.dlopen(library.str,2);assert handle!=unsafe{nil};entry:=u64(C.dlsym(handle,name[1..].str));assert entry!=0,name;return entry}}
	return runtime_symbol(library,name) or {panic(err)}
}
fn ac_api(native bool)AcApi{
	core:='/usr/lib/swift/libswiftCore.dylib';foundation:='/System/Library/Frameworks/Foundation.framework/Foundation'
	date:=unsafe{AcAccess(voidptr(ac_symbol(native,foundation,'_$s10Foundation4DateVMa')))(0)}
	assert date.state==0
	return AcApi{native:native,initialize:unsafe{AcInitialize(voidptr(ac_symbol(native,core,'_swift_arrayInitWithCopy')))},
		metadata:[ac_symbol(native,core,'_$sSiN'),ac_symbol(native,core,'_$sSSN'),ac_symbol(native,core,'_$ss11_MergeErrorON'),date.metadata]!}
}
fn ac_object(api AcApi)u64{$if macos{if api.native{return u64(C.CFStringCreateMutable(unsafe{nil},0))}};return owned_string('array initializeWithCopy owned payload')}
fn ac_hold(api AcApi,owner u64){$if macos{if api.native{C.CFRetain(voidptr(owner));return}};objc_retain(owner)}
fn ac_drop(api AcApi,owner u64){$if macos{if api.native{C.CFRelease(voidptr(owner));return}};objc_release(owner)}
fn ac_refs(api AcApi,owner u64)i64{$if macos{if api.native{return C.CFGetRetainCount(voidptr(owner))}};return obj_header(owner).refs}
fn ac_lookup()u64{return ac_symbol(false,'/usr/lib/swift/libswiftCore.dylib','_swift_arrayInitWithCopy')}
fn ac_word(address u64)u64{mut value:=u64(0);for i in u64(0)..8{value|=u64(unsafe{*(&u8(address+i))})<<(i*8)};return value}
fn ac_store(address u64,value u64){for i in u64(0)..8{unsafe{*(&u8(address+i))=u8(value>>(i*8))}}}
fn ac_payload_copy(destination u64,source u64,metadata u64)u64{
	mut state:=unsafe{&AcState(read64(metadata+8))}
	assert source==state.source+state.visited*state.stride && destination==state.destination+state.visited*state.stride
	state.visited++;if state.size!=0{C.memcpy(voidptr(destination),voidptr(source),usize(state.size))}
	if state.owned{ac_hold(state.api,ac_word(source))}
	if state.reenter{worker:=spawn ac_lookup();assert worker.wait()==u64(voidptr(state.api.initialize))}
	return destination
}
fn ac_span(span u64,alignment u64,at_end bool)AcSpan{
	page:=u64(C.getpagesize());readable:=((span+alignment+page-1)/page)*page
	length:=usize(readable+page*2);base:=u64(C.mmap(unsafe{nil},length,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert base!=~u64(0)
	assert C.mprotect(voidptr(base+page),usize(readable),C.PROT_READ|C.PROT_WRITE)==0
	value:=base+page+if at_end{readable-((span+alignment-1)&~(alignment-1))}else{u64(0)}
	return AcSpan{base,length,value,span}
}
fn ac_readonly(span AcSpan){page:=u64(C.getpagesize());assert C.mprotect(voidptr(span.base+page),span.length-usize(page*2),C.PROT_READ)==0}
fn ac_case(api AcApi,code u64,kind int,count u64,at_end bool){
	custom:=kind>=4
	profiles:=[[u64(13),16,1,0]!,[u64(0),1,1,0]!,[u64(24),32,8,0]!,[u64(65536),65536,256,0]!,
		[u64(13),16,1,1]!,[u64(24),32,8,1]!,[u64(129),192,64,1]!,[u64(65536),65536,256,1]!,[u64(0),1,1,1]!]!
	data:=u64(C.mmap(unsafe{nil},usize(C.getpagesize()),C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert data!=~u64(0)
	defer{assert C.munmap(voidptr(data),usize(C.getpagesize()))==0}
	mut metadata:=if custom{data+16}else{api.metadata[kind]}
	mut size:=u64(0);mut stride:=u64(0);mut alignment:=u64(0);mut pod:=false
	if custom{p:=profiles[kind-4];size=p[0];stride=p[1];alignment=p[2];pod=p[3]==0}else{vwt:=read64(metadata-8)&0x0000ffffffffffff;size=read64(vwt+64);stride=read64(vwt+72);flags:=read32(vwt+80);alignment=u64(flags&255)+1;pod=flags&0x10000==0}
	span:=if pod{count*stride}else{(count-1)*stride+size}
	source:=ac_span(span,alignment,at_end);destination:=ac_span(span,alignment,at_end)
	defer{assert C.munmap(voidptr(source.base),source.length)==0;assert C.munmap(voidptr(destination.base),destination.length)==0}
	owned:=kind==1||(custom&&!pod&&size>=8)
	owner:=ac_object(api);assert owner!=0;defer{ac_drop(api,owner)}
	mut state:=AcState{api,size,stride,source.value,destination.value,custom&&owned,!api.native&&custom&&!pod&&count<=3,0}
	if custom{
		witness:=data+128;mut pointer:=witness;mut entry:=u64(voidptr(ac_payload_copy))
		$if macos{if api.native{pointer=unsafe{AcSign(voidptr(code+16))(witness,(metadata-8)|(u64(0x2e3f)<<48))};entry=unsafe{AcSign(voidptr(code))(entry,(witness+16)|(u64(0xe3ba)<<48))}}}
		unsafe{*(&u64(metadata-8))=pointer;*(&u64(metadata))=0x200;*(&u64(metadata+8))=u64(&state);*(&u64(witness+16))=entry;*(&u64(witness+64))=size;*(&u64(witness+72))=stride}
		write32(witness+80,u32(alignment-1)|if pod{u32(0)}else{u32(0x110000)})
	}
	C.memset(voidptr(source.value),0x35,usize(span));C.memset(voidptr(destination.value),0xab,usize(span))
	if owned{for i in u64(0)..count{ac_hold(api,owner);ac_store(source.value+i*stride,if kind==1{u64(0)}else{owner});if kind==1{ac_store(source.value+i*stride+8,owner|0x5000000000000000)}}}
	ac_readonly(source);assert C.mprotect(voidptr(data),usize(C.getpagesize()),C.PROT_READ)==0
	api.initialize(destination.value,source.value,count,metadata)
	if custom{assert state.visited==if pod{u64(0)}else{count}}
	for i in u64(0)..span{is_value:=pod||i%stride<size;assert unsafe{*(&u8(destination.value+i))}==if is_value{unsafe{*(&u8(source.value+i))}}else{u8(0xab)}}
	if owned{
		assert ac_refs(api,owner)==i64(1+count*2)
		for i in u64(0)..count{if custom{ac_drop(api,ac_word(destination.value+i*stride))}else{vwt:=read64(metadata-8)&0x0000ffffffffffff;destroy:=unsafe{SwiftDynamicCastDestroy(voidptr(read64(vwt+8)&0x0000ffffffffffff))};destroy(destination.value+i*stride,metadata)}}
		assert ac_refs(api,owner)==i64(1+count)
		for _ in u64(0)..count{ac_drop(api,owner)}
		assert ac_refs(api,owner)==1
	}
}
fn ac_matrix(api AcApi,code u64){
	for kind in 0..13{for count in [u64(1),3,16]!{for at_end in [false,true]!{ac_case(api,code,kind,count,at_end)}}}
	for pointer in [u64(0),code+u64(C.getpagesize()),~u64(0)]!{api.initialize(pointer,pointer,0,pointer)}
}
fn ac_worker(api AcApi,code u64,index int){ac_case(api,code,8+index%5,3,index%2==0)}
fn ac_invalid(guard u64){
	mut witness:=[u64(0),0,0,0,0,0,0,0,8,8,7]!
	mut words:=[u64(0),0x200,0]!
	words[0]=u64(unsafe{&witness[0]});metadata:=u64(unsafe{&words[1]})
	mut source:=[u64(0xabc),0]!
	mut destination:=[u64(0xdef),0]!
	src:=u64(unsafe{&source[0]});dst:=u64(unsafe{&destination[0]})
	for invalid in [u64(0),1,~u64(7)]!{if _:=swift_array_init_copy_checked(dst,src,1,invalid){assert false};if _:=swift_array_init_copy_checked(invalid,src,1,metadata){assert false};if _:=swift_array_init_copy_checked(dst,invalid,1,metadata){assert false}}
	for count in [u64(1048577),~u64(0)]!{if _:=swift_array_init_copy_checked(guard,guard,count,metadata){assert false}}
	if _:=swift_array_init_copy_checked(src,src,1,metadata){assert false}
	witness[8]=13;witness[9]=16;witness[10]=0x10000
	for entry in [u64(0),1]!{witness[2]=entry;if _:=swift_array_init_copy_checked(dst,src,1,metadata){assert false}}
	for flags in [u64(0x400000),0x800000,6]!{witness[10]=flags;if _:=swift_array_init_copy_checked(dst,src,1,metadata){assert false}}
	assert source==[u64(0xabc),0]!&&destination==[u64(0xdef),0]!
}
fn test_swift_array_init_copy(){
	page:=u64(C.getpagesize());code:=u64(C.mmap(unsafe{nil},usize(page*2),C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert code!=~u64(0)
	for item in [[u64(0),0xdac10020]!,[u64(4),0xd65f03c0]!,[u64(16),0xdac10820]!,[u64(20),0xd65f03c0]!]!{write32(code+item[0],u32(item[1]))}
	C.__builtin___clear_cache(voidptr(code),voidptr(code+24));assert C.mprotect(voidptr(code),usize(page),C.PROT_READ|C.PROT_EXEC)==0&&C.mprotect(voidptr(code+page),usize(page),C.PROT_NONE)==0
	$if macos{ac_matrix(ac_api(true),code);println('NATIVE-ARRAY-INIT-COPY: Int/String/empty Error/Date and custom POD/owned values, zero/one/many elements, 64 KiB/alignment 256 and 1 MiB spans, bulk padding versus forward copy witnesses, exact retains and guarded source/destination')}
	for _ in 0..2{
		objc_start();api:=ac_api(false)
		mut workers:=[]thread{};for i in 0..8{workers<<spawn ac_worker(api,code,i)};workers.wait();unsafe{workers.free()}
		ac_matrix(api,code);ac_invalid(code+page)
		ios_runtime.swift_concurrency_retired=true;if _:=swift_array_init_copy_checked(code+page,code+page,0,code+page){assert false};ios_runtime.swift_concurrency_retired=false
		assert ios_runtime.live==0&&ios_runtime.swift_arrays.len==0&&ios_runtime.swift_heap.len==0
		objc_stop();if _:=swift_array_init_copy_checked(code+page,code+page,0,code+page){assert false}
	}
	assert C.munmap(voidptr(code),usize(page*2))==0
	println('IOS-ARRAY-INIT-COPY: bounded disjoint initialization, zero-count guarded no-op, stride-wide POD bulk copy and forward non-POD witnesses, exact ownership, invalid layout/overflow/overlap rejection before writes, reentrant callbacks and eight workers, two drained lifetimes; take/assignment runtime entries remain unsupported')
}

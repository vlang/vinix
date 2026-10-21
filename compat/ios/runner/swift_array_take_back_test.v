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
type TbInitialize = fn(u64,u64,u64,u64)
type TbAccess = fn(u64)SwiftAssociatedMetadata
type TbSign = fn(u64,u64)u64
struct TbApi { native bool initialize TbInitialize @[required] metadata [4]u64 }
struct TbState {
	size u64
	stride u64
	source u64
	destination u64
	reenter bool
	entry u64
mut:
	remaining u64
}
struct TbSpan { base u64 length usize value u64 }
fn tb_symbol(native bool,library string,name string)u64{
	$if macos{if native{handle:=C.dlopen(library.str,2);assert handle!=unsafe{nil};entry:=u64(C.dlsym(handle,name[1..].str));assert entry!=0,name;return entry}}
	return runtime_symbol(library,name) or {panic(err)}
}
fn tb_api(native bool)TbApi{
	core:='/usr/lib/swift/libswiftCore.dylib';foundation:='/System/Library/Frameworks/Foundation.framework/Foundation'
	date:=unsafe{TbAccess(voidptr(tb_symbol(native,foundation,'_$s10Foundation4DateVMa')))(0)};assert date.state==0
	return TbApi{native,unsafe{TbInitialize(voidptr(tb_symbol(native,core,'_swift_arrayInitWithTakeBackToFront')))},
		[tb_symbol(native,core,'_$sSiN'),tb_symbol(native,core,'_$sSSN'),tb_symbol(native,core,'_$ss11_MergeErrorON'),date.metadata]!}
}
fn tb_object(api TbApi)u64{$if macos{if api.native{return u64(C.CFStringCreateMutable(unsafe{nil},0))}};return owned_string('backward array take owned payload')}
fn tb_hold(api TbApi,owner u64){$if macos{if api.native{C.CFRetain(voidptr(owner));return}};objc_retain(owner)}
fn tb_drop(api TbApi,owner u64){$if macos{if api.native{C.CFRelease(voidptr(owner));return}};objc_release(owner)}
fn tb_refs(api TbApi,owner u64)i64{$if macos{if api.native{return C.CFGetRetainCount(voidptr(owner))}};return obj_header(owner).refs}
fn tb_lookup()u64{return tb_symbol(false,'/usr/lib/swift/libswiftCore.dylib','_swift_arrayInitWithTakeBackToFront')}
fn tb_word(address u64)u64{mut value:=u64(0);for i in u64(0)..8{value|=u64(unsafe{*(&u8(address+i))})<<(i*8)};return value}
fn tb_store(address u64,value u64){for i in u64(0)..8{unsafe{*(&u8(address+i))=u8(value>>(i*8))}}}
fn tb_payload_take(destination u64,source u64,metadata u64)u64{
	mut state:=unsafe{&TbState(read64(metadata+8))};assert state.remaining!=0;state.remaining--
	assert source==state.source+state.remaining*state.stride && destination==state.destination+state.remaining*state.stride
	if state.size!=0{C.memcpy(voidptr(destination),voidptr(source),usize(state.size));C.memset(voidptr(source),0xad,usize(state.size))}
	if state.reenter{worker:=spawn tb_lookup();assert worker.wait()==state.entry}
	return destination
}
fn tb_span(span u64,alignment u64,at_end bool)TbSpan{
	page:=u64(C.getpagesize());readable:=((span+alignment+page-1)/page)*page
	length:=usize(readable+page*2);base:=u64(C.mmap(unsafe{nil},length,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert base!=~u64(0)
	assert C.mprotect(voidptr(base+page),usize(readable),C.PROT_READ|C.PROT_WRITE)==0
	value:=base+page+if at_end{readable-((span+alignment-1)&~(alignment-1))}else{u64(0)}
	return TbSpan{base,length,value}
}
fn tb_case(api TbApi,code u64,kind int,count u64,mode int,at_end bool){
	custom:=kind>=4
	profiles:=[[u64(13),16,1,0]!,[u64(0),1,1,0]!,[u64(65536),65536,256,0]!,
		[u64(13),16,1,0x10000]!,[u64(24),32,8,0x10000]!,[u64(8),8,8,0x810000]!,
		[u64(13),16,1,0x110000]!,[u64(24),32,8,0x110000]!,[u64(129),192,64,0x110000]!,
		[u64(65536),65536,256,0x110000]!,[u64(8),8,8,0x910000]!,[u64(0),1,1,0x110000]!]!
	data:=u64(C.mmap(unsafe{nil},usize(C.getpagesize()),C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert data!=~u64(0)
	defer{assert C.munmap(voidptr(data),usize(C.getpagesize()))==0}
	metadata:=if custom{data+16}else{api.metadata[kind]}
	mut size:=u64(0);mut stride:=u64(0);mut alignment:=u64(0);mut flags:=u32(0)
	if custom{p:=profiles[kind-4];size=p[0];stride=p[1];alignment=p[2];flags=u32(p[3])|u32(alignment-1)}else{vwt:=read64(metadata-8)&0x0000ffffffffffff;size=read64(vwt+64);stride=read64(vwt+72);flags=read32(vwt+80);alignment=u64(flags&255)+1}
	bitwise:=flags&0x100000==0
	if !bitwise && mode>=3{return}
	span:=if bitwise{count*stride}else{(count-1)*stride+size}
	shift:=if mode==0||mode==4{u64(0)}else if mode==2{count*stride}else{stride}
	buffer:=tb_span(span+shift,alignment,at_end)
	separate:=if mode==0{tb_span(span,alignment,at_end)}else{TbSpan{}}
	defer{assert C.munmap(voidptr(buffer.base),buffer.length)==0;if mode==0{assert C.munmap(voidptr(separate.base),separate.length)==0}}
	source:=buffer.value+if mode==3{shift}else{u64(0)}
	destination:=if mode==0{separate.value}else{buffer.value+if mode==3{u64(0)}else{shift}}
	owned:=kind==1||(custom&&flags&0x10000!=0&&size>=8)
	owner:=tb_object(api);assert owner!=0;defer{tb_drop(api,owner)}
	mut state:=TbState{size,stride,source,destination,!api.native&&custom&&!bitwise&&count<=3,u64(voidptr(api.initialize)),count}
	if custom{
		witness:=data+128;mut pointer:=witness;mut entry:=if bitwise{code+u64(C.getpagesize())}else{u64(voidptr(tb_payload_take))}
		$if macos{if api.native{pointer=unsafe{TbSign(voidptr(code+16))(witness,(metadata-8)|(u64(0x2e3f)<<48))};entry=unsafe{TbSign(voidptr(code))(entry,(witness+32)|(u64(0x48d8)<<48))}}}
		unsafe{*(&u64(metadata-8))=pointer;*(&u64(metadata))=0x200;*(&u64(metadata+8))=u64(&state);*(&u64(witness+16))=code+u64(C.getpagesize());*(&u64(witness+32))=entry;*(&u64(witness+64))=size;*(&u64(witness+72))=stride}
		write32(witness+80,flags)
	}
	C.memset(voidptr(buffer.value),0xab,usize(span+shift));if mode==0{C.memset(voidptr(destination),0xab,usize(span))}
	C.memset(voidptr(source),0x35,usize(span))
	if owned{for i in u64(0)..count{tb_hold(api,owner);tb_store(source+i*stride,if kind==1{u64(0)}else{owner});if kind==1{tb_store(source+i*stride+8,owner|0x5000000000000000)}}}
	mut before:=[]u8{len:int(span)};mut padding:=[]u8{len:int(span)}
	defer{unsafe{before.free();padding.free()}}
	if span!=0{C.memcpy(before.data,voidptr(source),usize(span));C.memcpy(padding.data,voidptr(destination),usize(span))}
	if bitwise&&mode==0{page:=u64(C.getpagesize());assert C.mprotect(voidptr(buffer.base+page),buffer.length-usize(page*2),C.PROT_READ)==0}
	assert C.mprotect(voidptr(data),usize(C.getpagesize()),C.PROT_READ)==0
	api.initialize(destination,source,count,metadata)
	if custom{assert state.remaining==if bitwise{count}else{u64(0)}}
	for i in u64(0)..span{assert unsafe{*(&u8(destination+i))}==if bitwise||i%stride<size{before[int(i)]}else{padding[int(i)]}}
	if custom&&!bitwise&&mode==1&&size!=0{for i in u64(0)..size{assert unsafe{*(&u8(source+i))}==0xad}}
	if owned{
		assert tb_refs(api,owner)==i64(1+count)
		for i in u64(0)..count{if custom{tb_drop(api,tb_word(destination+i*stride))}else{vwt:=read64(metadata-8)&0x0000ffffffffffff;destroy:=unsafe{SwiftDynamicCastDestroy(voidptr(read64(vwt+8)&0x0000ffffffffffff))};destroy(destination+i*stride,metadata)}}
		assert tb_refs(api,owner)==1
	}
}
fn tb_matrix(api TbApi,code u64){for kind in 0..16{for count in [u64(1),3,16]!{for mode in 0..5{for at_end in [false,true]!{tb_case(api,code,kind,count,mode,at_end)}}}};for pointer in [u64(0),code+u64(C.getpagesize()),~u64(0)]!{api.initialize(pointer,pointer,0,pointer)}}
fn tb_worker(api TbApi,code u64,index int){tb_case(api,code,10+index%6,3,1,index%2==0)}
fn tb_invalid(guard u64){
	mut witness:=[u64(0),0,0,0,0,0,0,0,8,16,0x110007]!
	mut words:=[u64(0),0x200,0]!
	words[0]=u64(unsafe{&witness[0]});metadata:=u64(unsafe{&words[1]})
	mut storage:=[16]u64{};for i in 0..16{storage[i]=u64(i+1)}
	base:=u64(unsafe{&storage[0]});src:=base+32;dst:=base+64
	for invalid in [u64(0),1,~u64(7)]!{if _:=swift_array_take_back_checked(dst,src,1,invalid){assert false};if _:=swift_array_take_back_checked(invalid,src,1,metadata){assert false};if _:=swift_array_take_back_checked(dst,invalid,1,metadata){assert false}}
	for count in [u64(1048577),~u64(0)]!{if _:=swift_array_take_back_checked(guard,guard,count,metadata){assert false}}
	witness[4]=guard
	for target in [src,src-16,src+8]!{if _:=swift_array_take_back_checked(target,src,3,metadata){assert false}}
	for entry in [u64(0),1]!{witness[4]=entry;if _:=swift_array_take_back_checked(dst,src,1,metadata){assert false}}
	for flags in [u64(0x400000),6]!{witness[10]=flags;if _:=swift_array_take_back_checked(dst,src,1,metadata){assert false}}
	for i in 0..16{assert storage[i]==u64(i+1)}
}
fn test_swift_array_take_back(){
	page:=u64(C.getpagesize());code:=u64(C.mmap(unsafe{nil},usize(page*2),C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert code!=~u64(0)
	for item in [[u64(0),0xdac10020]!,[u64(4),0xd65f03c0]!,[u64(16),0xdac10820]!,[u64(20),0xd65f03c0]!]!{write32(code+item[0],u32(item[1]))}
	C.__builtin___clear_cache(voidptr(code),voidptr(code+24));assert C.mprotect(voidptr(code),usize(page),C.PROT_READ|C.PROT_EXEC)==0&&C.mprotect(voidptr(code+page),usize(page),C.PROT_NONE)==0
	$if macos{tb_matrix(tb_api(true),code);println('NATIVE-ARRAY-TAKE-BACK: Int/String/empty Error/Date and custom POD/non-POD/noncopyable values, bitwise memmove and reverse take witnesses, overlapping whole-element shifts, 64 KiB/alignment 256 and 1 MiB spans, exact transferred ownership and guarded buffers')}
	for _ in 0..2{
		objc_start();api:=tb_api(false)
		mut workers:=[]thread{};for i in 0..8{workers<<spawn tb_worker(api,code,i)};workers.wait();unsafe{workers.free()}
		tb_matrix(api,code);tb_invalid(code+page)
		ios_runtime.swift_concurrency_retired=true;if _:=swift_array_take_back_checked(code+page,code+page,0,code+page){assert false};ios_runtime.swift_concurrency_retired=false
		assert ios_runtime.live==0&&ios_runtime.swift_arrays.len==0&&ios_runtime.swift_heap.len==0
		objc_stop();if _:=swift_array_take_back_checked(code+page,code+page,0,code+page){assert false}
	}
	assert C.munmap(voidptr(code),usize(page*2))==0
	println('IOS-ARRAY-TAKE-BACK: bounded bitwise memmove and reverse take initialization, consumed source and exact destination ownership, guarded padding and zero-count no-op, invalid layouts/spans/directions rejected before writes, reentrant callbacks and eight workers, two drained lifetimes; frontward take and assignment runtime entries remain unsupported')
}

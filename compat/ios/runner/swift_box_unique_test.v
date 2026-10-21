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
fn C.mincore(voidptr,usize,&u8)i32
type BuAllocate = fn(u64)SwiftArrayAllocation
type BuRetain = fn(u64)u64
type BuRelease = fn(u64)
type BuCopy = fn(u64,u64,u64)u64
type BuDestroy = fn(u64,u64)
type BuSign = fn(u64,u64)u64
type BuProbe = fn(u64,u64,u64,u64,u64,&u64,u64)
struct BuApi { native bool entry u64 code u64 guard u64 retain BuRetain @[required] release BuRelease @[required] }
struct BuState { api BuApi size u64 alignment u64 mut: copies int destroys int }

fn bu_symbol(native bool,name string)u64 {
	$if macos { if native {
		library:=C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',2);assert library!=unsafe{nil}
		entry:=u64(C.dlsym(library,name[1..].str));assert entry!=0,name;return entry
	} }
	return runtime_symbol('/usr/lib/swift/libswiftCore.dylib',name) or {panic(err)}
}
fn bu_api(native bool,code u64,guard u64)BuApi {
	return BuApi{native,bu_symbol(native,'_swift_makeBoxUnique'),code,guard,
		unsafe{BuRetain(voidptr(bu_symbol(native,'_swift_retain')))},unsafe{BuRelease(voidptr(bu_symbol(native,'_swift_release')))}}
}
fn bu_call(api BuApi,buffer u64,metadata u64,mask u64)SwiftArrayAllocation {
	mut words:=[u64(0xcafe),0,0,0,0,0,0xbeef]!
	unsafe{BuProbe(voidptr(api.code))(buffer,metadata,mask,api.guard,api.entry,&words[1],api.guard)}
	assert words[0]==0xcafe && words[6]==0xbeef && words[3]==api.guard && words[4]==0x5121 && words[5]==0x5222
	return SwiftArrayAllocation{owner:words[1],bytes:words[2]}
}
fn bu_object(api BuApi)u64 {
	$if macos {if api.native{return u64(C.CFStringCreateMutable(unsafe{nil},0))}}
	return owned_string('owned box copy-on-write payload')
}
fn bu_hold(api BuApi,object u64) {
	$if macos {if api.native{C.CFRetain(voidptr(object));return}}
	objc_retain(object)
}
fn bu_drop(api BuApi,object u64) {
	$if macos {if api.native{C.CFRelease(voidptr(object));return}}
	objc_release(object)
}
fn bu_refs(api BuApi,object u64)i64 {
	$if macos {if api.native{return C.CFGetRetainCount(voidptr(object))}}
	return obj_header(object).refs
}
fn bu_resolve()u64{return bu_symbol(false,'_swift_makeBoxUnique')}
fn bu_reenter(s &BuState){if !s.api.native{worker:=spawn bu_resolve();assert worker.wait()==s.api.entry}}
fn bu_copy(destination u64,source u64,metadata u64)u64 {
	mut s:=unsafe{&BuState(read64(metadata+8))};assert destination&(s.alignment-1)==0 && source&(s.alignment-1)==0
	s.copies++;C.memcpy(voidptr(destination),voidptr(source),usize(s.size));bu_hold(s.api,read64(source));bu_reenter(s);return destination
}
fn bu_destroy(value u64,metadata u64) {
	mut s:=unsafe{&BuState(read64(metadata+8))};assert value&(s.alignment-1)==0
	s.destroys++;bu_drop(s.api,read64(value));bu_reenter(s)
}
fn bu_local_dispose(owner u64) {
	metadata:=read64(read64(owner)+16);witness:=read64(metadata-8)
	offset:=(16+u64(read32(witness+80)&255))&~u64(read32(witness+80)&255)
	destroy:=unsafe{BuDestroy(voidptr(read64(witness+8)))};destroy(owner+offset,metadata)
	swift_heap_deallocate(owner,offset+read64(witness+64),u64(read32(witness+80)&255)|7)
}
// Every type record remains mapped throughout its runtime lifetime: native
// Swift caches allocBox metadata by the borrowed value-metadata address too.
fn bu_case(api BuApi,kind int,shared bool,edge bool)u64 {
	page:=usize(C.getpagesize());custom:=kind>=3
	profiles:=[[u64(8),1]!,[u64(24),8]!,[u64(32),16]!,[u64(64),32]!,[u64(129),64]!,[u64(65536),256]!]!
	size:=if custom{profiles[kind-3][0]}else if kind==0{u64(8)}else if kind==1{u64(16)}else{u64(0)}
	alignment:=if custom{profiles[kind-3][1]}else if kind==2{u64(1)}else{u64(8)}
	stride:=if size==0{u64(1)}else{(size+alignment-1)&~(alignment-1)}
	span_size:=(usize(size)+page-1)/page*page+page*3
	span:=u64(C.mmap(unsafe{nil},span_size,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert span!=~u64(0)
	defer{assert C.munmap(voidptr(span),span_size)==0}
	readable:=span+u64(page);readable_size:=span_size-page*2
	assert C.mprotect(voidptr(readable),readable_size,C.PROT_READ|C.PROT_WRITE)==0
	source:=if edge{readable+u64(readable_size)-stride}else{readable}
	data:=u64(C.mmap(unsafe{nil},page,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert data!=~u64(0)
	mut state:=BuState{api:api,size:size,alignment:alignment}
	metadata:=if custom{data+16}else{bu_symbol(api.native,['_$sSiN','_$sSSN','_$sytN']![kind])+if kind==2{u64(8)}else{u64(0)}}
	if custom {
		witness:=data+128;mut pointer:=witness
		$if macos {if api.native{pointer=unsafe{BuSign(voidptr(api.code+128))(witness,(metadata-8)|(u64(0x2e3f)<<48))}}}
		unsafe{*(&u64(metadata-8))=pointer;*(&u64(metadata))=0x200;*(&u64(metadata+8))=u64(&state)}
		for item in [[u64(8),u64(voidptr(bu_destroy)),0x4f8]!,[u64(16),u64(voidptr(bu_copy)),0xe3ba]!]! {
			mut entry:=item[1];slot:=witness+item[0]
			$if macos {if api.native{entry=unsafe{BuSign(voidptr(api.code+112))(entry,slot|(item[2]<<48))}}}
			unsafe{*(&u64(slot))=entry}
		}
		unsafe{*(&u64(witness+64))=size;*(&u64(witness+72))=stride}
		write32(witness+80,u32(alignment-1)|0x10000|if size>24 || alignment>8{u32(0x20000)}else{u32(0)})
	}
	witness:=read64(metadata-8)&0x0000ffffffffffff
	initialize:=unsafe{BuCopy(voidptr(read64(witness+16)&0x0000ffffffffffff))}
	destroy:=unsafe{BuDestroy(voidptr(read64(witness+8)&0x0000ffffffffffff))}
	object:=bu_object(api);defer{bu_drop(api,object)}
	C.memset(voidptr(source),0x6b,usize(size))
	if kind==1 {bu_hold(api,object);unsafe{*(&SwiftStringWords(source))=SwiftStringWords{second:object|0x5000000000000000}}}
	else if custom {bu_hold(api,object);C.memcpy(voidptr(source),unsafe{&object},8)}
	else if kind==0 {unsafe{*(&u64(source))=0x8123456789abcdef}}
	offset:=(16+alignment-1)&~(alignment-1)
	mut original:=SwiftArrayAllocation{}
	$if macos {if api.native{original=unsafe{BuAllocate(voidptr(bu_symbol(true,'_swift_allocBox')))(metadata)}}}
	if !api.native {
		box_metadata:=data+536
		unsafe{*(&u64(box_metadata-16))=api.code+80;*(&u64(box_metadata))=0x400;*(&u64(box_metadata+16))=metadata}
		owner:=swift_heap_allocate(box_metadata,offset+size,(alignment-1)|7)
		original=SwiftArrayAllocation{owner:owner,bytes:owner+offset}
	}
	assert original.bytes==original.owner+offset
	initialize(original.bytes,source,metadata)
	if shared {assert api.retain(original.owner)==original.owner}
	buffer_span:=u64(C.mmap(unsafe{nil},page*3,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert buffer_span!=~u64(0)
	defer{assert C.munmap(voidptr(buffer_span),page*3)==0}
	assert C.mprotect(voidptr(buffer_span+u64(page)),page,C.PROT_READ|C.PROT_WRITE)==0
	buffer:=if edge{buffer_span+u64(page*2)-24}else{buffer_span+u64(page)}
	unsafe{*(&u64(buffer))=original.owner;*(&u64(buffer+8))=0x12345678;*(&u64(buffer+16))=0x98765432}
	assert C.mprotect(voidptr(readable),readable_size,C.PROT_READ)==0 && C.mprotect(voidptr(data),page,C.PROT_READ)==0
	if !shared{assert C.mprotect(voidptr(buffer_span+u64(page)),page,C.PROT_READ)==0}
	result:=bu_call(api,buffer,metadata,alignment-1)
	assert read64(buffer)==result.owner && result.bytes==result.owner+offset && result.bytes&(alignment-1)==0
	assert read64(buffer+8)==0x12345678 && read64(buffer+16)==0x98765432
	assert shared == (result.owner != original.owner)
	if size!=0 {assert C.memcmp(voidptr(result.bytes),voidptr(source),usize(size))==0}
	assert bu_call(api,buffer,metadata,alignment-1)==result
	if custom{assert state.copies==if shared{2}else{1};assert state.destroys==0}
	if kind==1 || custom{assert bu_refs(api,object)==if shared{i64(4)}else{i64(3)}}
	if shared {
		box_metadata:=read64(result.owner)&0x0000ffffffffffff
		assert read64(box_metadata)==0x500 && read32(box_metadata+8)==u32(offset) && read64(box_metadata+16)==metadata
		assert api.retain(result.owner)==result.owner
		next:=bu_call(api,buffer,metadata,alignment-1)
		assert next.owner!=result.owner && read64(buffer)==next.owner && read64(next.owner)==read64(result.owner)
		if size!=0{assert C.memcmp(voidptr(next.bytes),voidptr(source),usize(size))==0}
		if kind==0{unsafe{*(&u64(next.bytes))=42};assert read64(original.bytes)==0x8123456789abcdef && read64(result.bytes)==0x8123456789abcdef}
		else if size>8 && custom{unsafe{*(&u8(next.bytes+8))=0xa5};assert unsafe{*(&u8(original.bytes+8))}==0x6b && unsafe{*(&u8(result.bytes+8))}==0x6b}
		api.release(next.owner);api.release(original.owner)
	}
	api.release(result.owner);destroy(source,metadata)
	assert bu_refs(api,object)==1
	if custom{assert state.copies==if shared{3}else{1};assert state.destroys==if shared{4}else{2}}
	return data
}
fn bu_matrix(api BuApi)[]u64 {mut pages:=[]u64{};for kind in 0..9{for shared in [false,true]!{for edge in [false,true]!{pages<<bu_case(api,kind,shared,edge)}}};return pages}
fn bu_bad(buffer u64,metadata u64,mask u64){if _:=swift_box_unique_checked(buffer,metadata,mask){assert false,'invalid value box accepted'}}
fn bu_invalid(api BuApi) {
	page := usize(C.getpagesize())
	arena := u64(C.mmap(unsafe { nil },page,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0))
	assert arena != ~u64(0)
	defer { assert C.munmap(voidptr(arena),page) == 0 }
	metadata := arena+16; witness := arena+128; box := arena+536
	int_metadata := bu_symbol(false,'_$sSiN')
	C.memcpy(voidptr(witness),voidptr(read64(int_metadata-8)),88)
	unsafe { *(&u64(metadata-8))=witness; *(&u64(metadata))=0x200
		*(&u64(box-16))=api.code+80; *(&u64(box))=0x400; *(&u64(box+16))=metadata }
	owner := swift_heap_allocate(box,24,7)
	unsafe { *(&u64(owner+16))=1234 }
	mut buffer := [owner,u64(0xface),0xbeef]!
	pointer := u64(unsafe { &buffer[0] })
	for item in [[u64(64),65537]!,[u64(64),16]!,[u64(72),0]!,[u64(72),4]!,[u64(8),0]!,[u64(16),1]!]! {
		previous := read64(witness+item[0])
		unsafe { *(&u64(witness+item[0]))=item[1] }
		bu_bad(pointer,metadata,7)
		unsafe { *(&u64(witness+item[0]))=previous }
	}
	flags := read32(witness+80)
	for invalid in [u32(2),flags|0x00400000]! {
		write32(witness+80,invalid); bu_bad(pointer,metadata,u64(invalid&255))
	}
	write32(witness+80,flags)
	for item in [[metadata-8,u64(0)]!,[metadata,u64(0x203)]!,[owner,u64(0)]!,[box,u64(0x200)]!,[owner+8,u64(5)]!]! {
		previous := read64(item[0]); unsafe { *(&u64(item[0]))=item[1] }
		bu_bad(pointer,metadata,7); unsafe { *(&u64(item[0]))=previous }
	}
	mut storage := ios_runtime.swift_heap[owner] or { panic('missing invalid-case box') }
	storage.deiniting=true; ios_runtime.swift_heap[owner]=storage; bu_bad(pointer,metadata,7)
	storage.deiniting=false; ios_runtime.swift_heap[owner]=storage
	assert buffer == [owner,u64(0xface),0xbeef]!
	assert read64(owner+8)==3 && read64(owner+16)==1234
	api.release(owner)
}
fn bu_any(api BuApi) {
	metadata:=bu_symbol(false,'_$sypN')+8
	int_metadata:=bu_symbol(false,'_$sSiN')
	owner:=swift_any_box_allocate()
	unsafe{*(&u64(owner+16))=1234;*(&u64(owner+40))=int_metadata}
	api.retain(owner);mut buffer:=[owner,u64(0xface),0xbeef]!
	result:=bu_call(api,u64(unsafe{&buffer[0]}),metadata,7)
	assert result.owner!=owner && read64(result.bytes)==1234 && read64(result.bytes+24)==int_metadata
	mut second:=u64(0)
	projection := swift_any_buffer_copy_checked(u64(unsafe{&second}),u64(unsafe{&buffer[0]}),metadata) or {panic(err)}
	assert projection == result.bytes
	api.release(second);api.release(result.owner);api.release(owner)
}
fn test_swift_box_unique() {
	page:=usize(C.getpagesize())
	code:=u64(C.mmap(unsafe{nil},page,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0))
	guard:=u64(C.mmap(unsafe{nil},page,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert code!=~u64(0) && guard!=~u64(0)
	defer{assert C.munmap(voidptr(code),page)==0;assert C.munmap(voidptr(guard),page)==0}
	for i,op in [u32(0xa9bc7bfd),0xa90153f3,0xa9025bf5,0xaa0503f3,0xaa0403f0,0xaa0603f4,u32(0xd2800000|(0x5121<<5)|21),u32(0xd2800000|(0x5222<<5)|22),0xaa0603e8,0xd63f0200,0xa9000660,0xa9015674,0xf9001276,0xa9425bf5,0xa94153f3,0xa8c47bfd,0xd65f03c0]! {write32(code+u64(i*4),op)}
	for i,op in [u32(0xaa1403e0),0x58000070,0xd61f0200,0xd503201f]!{write32(code+80+u64(i*4),op)}
	unsafe{*(&u64(code+96))=u64(voidptr(bu_local_dispose))}
	for item in [[u64(112),0xdac10020]!,[u64(116),0xd65f03c0]!,[u64(128),0xdac10820]!,[u64(132),0xd65f03c0]!]!{write32(code+item[0],u32(item[1]))}
	C.__builtin___clear_cache(voidptr(code),voidptr(code+136));assert C.mprotect(voidptr(code),page,C.PROT_READ|C.PROT_EXEC)==0
	$if macos {pages:=bu_matrix(bu_api(true,code,guard));for arena in pages{assert C.munmap(voidptr(arena),page)==0};unsafe{pages.free()};println('NATIVE-BOX-UNIQUE: 36 unique/shared guarded cases, Int/String/Void and owned values through 64 KiB/alignment 256; x0/x1 pair return with inaccessible x8, saved registers, exact copy/destruction and generic metadata reuse')}
	for _ in 0..2 {
		objc_start();api:=bu_api(false,code,guard);assert ios_runtime.swift_box_code==0
		mut workers:=[]thread u64{};for i in 0..8{workers<<spawn bu_case(api,3+i%6,true,true)}
		mut pages:=workers.wait();unsafe{workers.free()};pages<<bu_matrix(api)
		bu_any(api)
		bu_invalid(api)
		metadata:=bu_symbol(false,'_$sSiN');mut empty:=u64(0)
		for pointer in [u64(0),1,~u64(7)]!{bu_bad(pointer,metadata,7);bu_bad(u64(unsafe{&empty}),pointer,7)}
		for mask in [u64(0),3,15,~u64(0)]!{bu_bad(u64(unsafe{&empty}),metadata,mask)}
		bu_bad(u64(unsafe{&empty}),metadata,7)
		ios_runtime.swift_concurrency_retired=true;bu_bad(guard,guard,guard);ios_runtime.swift_concurrency_retired=false
		assert ios_runtime.live==0 && ios_runtime.swift_heap.len==0
		mut arenas:=[]u64{};for _,box in ios_runtime.swift_box_metadata{arenas<<box.arena};arenas<<ios_runtime.swift_box_code
		objc_stop();assert ios_runtime.swift_box_code==0 && ios_runtime.swift_box_metadata.len==0
		bu_bad(guard,guard,guard)
		for arena in arenas{$if macos{assert C.mprotect(voidptr(arena),page,C.PROT_READ)==-1}$else{mut resident:=u8(0);assert C.mincore(voidptr(arena),page,unsafe{&resident})==-1}}
		for arena in pages{assert C.munmap(voidptr(arena),page)==0};unsafe{pages.free();arenas.free()}
	}
	println('IOS-BOX-UNIQUE: native pair ABI, readonly unique buffer and shared copy-on-write, generic/local box ownership, Any interoperability, exact value witnesses, eight cold workers with reentrant callbacks, bounded invalid/retired rejection, two drained and unmapped lifetimes')
}

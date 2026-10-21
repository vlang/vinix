// SPDX-License-Identifier: GPL-2.0-or-later
module main

import macho
#include <dlfcn.h>
fn C.dlopen(&char,i32) voidptr
fn C.dlsym(voidptr,&char) voidptr
fn C.mincore(voidptr,usize,&u8)i32
type EdProbe = fn (u64,u64,u64,u64,&u64,u64)
type EdSign = fn (u64,u64) u64
type EdUtf8 = fn (u64,u64) u64
type EdDrop = fn (u64)
const ed_symbol = '_$ss5ErrorPsE7_domainSSvg'

fn ed_emit(code u64) {
	for i, op in [u32(0xa9bc7bfd),0xa90153f3,0xa9025bf5,0xaa0403f3,0xaa0303f0,0xaa0003f4,
		0xaa0103e0,0xaa0203e1,u32(0xd2800000|(0x5121<<5)|21),u32(0xd2800000|(0x5222<<5)|22),
		0xaa0503e8,0xd63f0200,0xa9000660,0xa9015674,0xf9001276,
		0xa9425bf5,0xa94153f3,0xa8c47bfd,0xd65f03c0]! {write32(code+u64(i*4),op)}
	write32(code+128,0xdac10820);write32(code+132,0xd65f03c0)
}
fn ed_call(probe EdProbe,entry u64,metadata u64,guard u64) SwiftStringWords {
	mut output := [u64(0x12345678),0,0,0,0,0,0x87654321]!
	probe(guard,metadata,guard,entry,unsafe{&output[1]},guard)
	assert output[0]==0x12345678&&output[6]==0x87654321
	assert output[3]==guard&&output[4]==0x5121&&output[5]==0x5222
	return SwiftStringWords{output[1],output[2]}
}
fn ed_text(words SwiftStringWords,expected string,native bool,lib voidptr) {
	$if macos {if native {
		get := unsafe{EdUtf8(C.dlsym(lib,c'$sSS11utf8CStrings15ContiguousArrayVys4Int8VGvg'))}
		drop := unsafe{EdDrop(C.dlsym(lib,c'swift_bridgeObjectRelease'))}
		owner := get(words.first,words.second)
		assert read64(owner+16)==u64(expected.len+1)&&C.memcmp(voidptr(owner+32),expected.str,usize(expected.len+1))==0,expected
		drop(owner);drop(words.second);return
	}}
	mut scratch := [u64(0),0]!
	bytes := swift_string_bytes(words,u64(unsafe{&scratch[0]})) or {panic(err)}
	assert bytes.count==u64(expected.len)&&C.memcmp(voidptr(bytes.address),expected.str,usize(expected.len))==0,expected
	swift_bridge_release(words.second)
}
fn ed_relative(field u64,target u64){write32(field,u32(i32(i64(target)-i64(field))))}
// Six stable metadata records: native Swift caches their names for process
// lifetime. Input Self, Error table and x8 all point into an inaccessible page.
fn ed_record(base u64,slot int,kind u64,nested bool,name string,native bool,sign EdSign) u64 {
	metadata := base+u64(slot*512)+8;descriptor := metadata+24;parent := metadata+96;outer := metadata+128
	unsafe{*(&u64(metadata))=kind;*(&u64(metadata+8))=descriptor}
	write32(descriptor,if kind==0x201{u32(0x52)}else{u32(0x51)})
	ed_relative(descriptor+4,if nested{outer}else{parent});ed_relative(descriptor+8,metadata+192)
	ed_relative(parent+8,metadata+256);C.memcpy(voidptr(metadata+256),c'DomainFixture',14)
	write32(outer,0x51);ed_relative(outer+4,parent);ed_relative(outer+8,metadata+288);C.memcpy(voidptr(metadata+288),c'Outer',6)
	C.memcpy(voidptr(metadata+192),name.str,usize(name.len+1))
	$if macos {if native {unsafe{*(&u64(metadata+8))=sign(descriptor,(metadata+8)|(u64(44678)<<48))}}}
	return metadata
}
fn ed_cases(probe EdProbe,entry u64,base u64,guard u64,native bool,lib voidptr,sign EdSign) {
	for i,name in ['E','A_long_error_name_which_requires_owned_storage','Ошибка']! {
		for j,kind in [u64(0x201),0x200]! {
			metadata := ed_record(base,i*2+j,kind,j==1,name,native,sign)
			assert C.mprotect(voidptr(base),usize(C.getpagesize()),C.PROT_READ)==0
			expected := 'DomainFixture.'+if j==1{'Outer.'}else{''}+name
			ed_text(ed_call(probe,entry,metadata,guard),expected,native,lib)
			assert C.mprotect(voidptr(base),usize(C.getpagesize()),C.PROT_READ|C.PROT_WRITE)==0
		}
	}
}
fn ed_native(probe EdProbe,base u64,guard u64,sign EdSign) {
	$if macos {
		lib:=C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',C.RTLD_NOW);assert lib!=unsafe{nil}
		entry:=u64(C.dlsym(lib,unsafe{&char(ed_symbol.str+1)}));assert entry!=0
		ed_cases(probe,entry,base,guard,true,lib,sign)
		merge:=u64(C.dlsym(lib,c'$ss11_MergeErrorON'));assert merge!=0
		ed_text(ed_call(probe,entry,merge,guard),'Swift._MergeError',true,lib)
		println('NATIVE-ERROR-DOMAIN: module-qualified enum/struct and nested names, Unicode, direct x0/x1 owned String, unread Self/table/x8 and preserved x20/x21/x22')
	}
}
fn ed_resolver() u64 {return runtime_symbol('/usr/lib/swift/libswiftCore.dylib',ed_symbol) or {panic(err)}}
fn ed_control() SwiftStringWords {return swift_string_literal(c'control',7,true)}
fn ed_worker(probe EdProbe,entry u64,metadata u64,guard u64) {
	for _ in 0..128 {
		assert ed_resolver()==entry
		ed_text(ed_call(probe,entry,metadata,guard),'DomainFixture.E',false,unsafe{nil})
	}
}
fn ed_reject(source u64,metadata u64){if _:=swift_error_domain_checked(source,metadata){assert false}}
fn ed_invalid(base u64,guard u64) {
	metadata:=base+8;descriptor:=base+32;module:=base+104
	before:=ios_runtime.swift_strings.len
	for bad in [u64(0),1,~u64(0),guard,guard-8]!{ed_reject(guard,bad)}
	for kind in [u64(0),0x202,0x203,0x300,0x301,0x302,0x303,0x304,0x305,~u64(0)]! {
		unsafe{*(&u64(metadata))=kind};ed_reject(guard,metadata)
	}
	unsafe{*(&u64(metadata))=0x201}
	for bad in [u64(0),1,guard,~u64(0)-3]!{unsafe{*(&u64(metadata+8))=bad};ed_reject(guard,metadata)}
	unsafe{*(&u64(metadata+8))=descriptor}
	for flags in [u32(0),0x51,0xd2,0x10052,0x60012,0xffffffff]!{write32(descriptor,flags);ed_reject(guard,metadata)}
	write32(descriptor,0x52)
	ed_relative(descriptor+4,descriptor);ed_reject(guard,metadata) // Cycle, depth cap.
	ed_relative(descriptor+4,module)
	for flags in [u32(1),2,0x80,0xffffffff]!{write32(module,flags);ed_reject(guard,metadata)}
	write32(module,0);write32(module+4,4);ed_reject(guard,metadata);write32(module+4,0)
	for delta in [u32(0),0x7fffffff,0x80000000]!{write32(descriptor+8,delta);ed_reject(guard,metadata)}
	ed_relative(descriptor+8,guard-5);C.memset(voidptr(guard-5),0x61,5);ed_reject(guard,metadata)
	ed_relative(descriptor+8,base+200);unsafe{*(&u8(base+200))=0};ed_reject(guard,metadata)
	unsafe{*(&u8(base+200))=0xff;*(&u8(base+201))=0};ed_reject(guard,metadata)
	assert ios_runtime.swift_strings.len==before
}
fn test_swift_error_domain() {
	$if !arm64{return}
	page:=usize(C.getpagesize())
	code:=u64(C.mmap(unsafe{nil},page*3,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert code!=~u64(0)
	defer{assert C.munmap(voidptr(code),page*3)==0}
	base:=code+u64(page);guard:=code+u64(page*2)
	ed_emit(code);C.__builtin___clear_cache(voidptr(code),voidptr(code+136))
	assert C.mprotect(voidptr(code),page,C.PROT_READ|C.PROT_EXEC)==0&&C.mprotect(voidptr(guard),page,C.PROT_NONE)==0
	probe:=unsafe{EdProbe(voidptr(code))};sign:=unsafe{EdSign(voidptr(code+128))}
	ed_native(probe,base,guard,sign)
	for _ in 0..2 {
		C.memset(voidptr(base),0,page);objc_start()
		mut publishers:=[]thread u64{};for _ in 0..8{publishers<<spawn ed_resolver()};entries:=publishers.wait()
		for entry in entries{assert entry==entries[0]&&entry!=0};entry:=entries[0];arena:=ios_runtime.swift_error_arena;assert entry==arena+192
		ed_text(ed_call(probe,u64(unsafe{voidptr(ed_control)}),guard,guard),'control',false,unsafe{nil})
		mut loaded:=LoadedModule{image:macho.Image{segments:[macho.Segment{name:'__DATA_CONST',address:0,size:u64(page),filesize:u64(page),prot:1}]},layout:macho.Layout{base:0,size:u64(page)},base:base}
		mut runtime:=ModuleRuntime{modules:[unsafe{&loaded}]};assert module_runtime==unsafe{nil};module_runtime=unsafe{&runtime}
		ed_cases(probe,entry,base,guard,false,unsafe{nil},sign)
		assert C.mprotect(voidptr(base),page,C.PROT_READ)==0
		mut workers:=[]thread{};for _ in 0..8{workers<<spawn ed_worker(probe,entry,base+8,guard)};workers.wait()
		// Returned storage survives loss of all access to the borrowed metadata.
		held:=ed_call(probe,entry,base+8,guard)
		assert C.mprotect(voidptr(base),page,C.PROT_NONE)==0
		ed_text(held,'DomainFixture.E',false,unsafe{nil})
		assert C.mprotect(voidptr(base),page,C.PROT_READ|C.PROT_WRITE)==0
		ed_invalid(base,guard)
		module_runtime=unsafe{nil};ed_reject(guard,base+8)
		merge:=runtime_symbol('/usr/lib/swift/libswiftCore.dylib','_$ss11_MergeErrorON') or {panic(err)}
		ed_text(ed_call(probe,entry,merge,guard),'Swift._MergeError',false,unsafe{nil})
		assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib',ed_symbol+'Extra')==none
		assert runtime_symbol('/usr/lib/libSystem.B.dylib',ed_symbol)==none
		ios_runtime.swift_concurrency_retired=true;ed_reject(guard,guard);assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib',ed_symbol)==none
		ios_runtime.swift_concurrency_retired=false
		assert ios_runtime.swift_strings.len==0&&ios_runtime.swift_buffers.len==0&&ios_runtime.swift_heap.len==0&&ios_runtime.objects.len==0&&ios_runtime.live==0
		objc_stop();assert ios_runtime.swift_error_arena==0;ed_reject(guard,guard)
		for offset in [usize(0),page]!{
			$if macos{assert C.mprotect(voidptr(arena+u64(offset)),page,C.PROT_READ)==-1}
			$else{mut resident:=u8(0);assert C.mincore(voidptr(arena+u64(offset)),page,unsafe{&resident})==-1}
		}
	}
	println('IOS-ERROR-DOMAIN: qualified enum/struct/nested/Unicode names, owned String survives protected metadata, readonly image bounds and unsupported-context rejection, preserved registers, eight cold publishers/workers and two drained/unmapped lifetimes')
}

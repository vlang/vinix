// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#flag -framework CoreFoundation
	#include <CoreFoundation/CFError.h>
	#include <CoreFoundation/CFString.h>
	#include <CoreFoundation/CFDictionary.h>
}
#include <dlfcn.h>
fn C.dlopen(&char,i32)voidptr
fn C.dlsym(voidptr,&char)voidptr
fn C.CFStringCreateWithBytes(voidptr,&u8,i64,u32,bool)voidptr
fn C.CFErrorCreate(voidptr,voidptr,i64,voidptr)voidptr
fn C.CFGetRetainCount(voidptr)i64
fn C.CFRelease(voidptr)
fn C.CFDictionaryCreateMutable(voidptr,i64,voidptr,voidptr)voidptr
fn C.CFDictionarySetValue(voidptr,voidptr,voidptr)
fn C.CFDictionaryGetCount(voidptr)i64
fn C.CFDictionaryGetValue(voidptr,voidptr)voidptr
fn C.mincore(voidptr,usize,&u8)i32
type SsProbe=fn(u64,u64,u64,u64,&u64,u64)
type SsUtf8=fn(u64,u64)u64
type SsDrop=fn(u64)
type SsLookup=fn(u64,u64,u64)u64
type SsMangled=fn(u64,u64,u64,u64)u64
const ss_symbol='_$ss5ErrorWS'
fn ss_emit(code u64){
	for i,op in [u32(0xa9bc7bfd),0xa90153f3,0xa9025bf5,0xaa0403f3,0xaa0303f0,0xaa0003f4,
		0xaa0103e0,0xaa0203e1,u32(0xd2800000|(0x5121<<5)|21),u32(0xd2800000|(0x5222<<5)|22),
		0xaa0503e8,0xd63f0200,0xa9000660,0xa9015674,0xf9001276,0xa9425bf5,0xa94153f3,0xa8c47bfd,0xd65f03c0]!{write32(code+u64(i*4),op)}
}
fn ss_call(probe SsProbe,entry u64,source u64,guard u64)SwiftStringWords{
	mut words:=[u64(0x12345678),0,0,0,0,0,0x87654321]!
	probe(source,guard,guard,entry,unsafe{&words[1]},guard)
	assert words[0]==0x12345678&&words[6]==0x87654321
	assert words[3]==source&&words[4]==0x5121&&words[5]==0x5222
	return SwiftStringWords{words[1],words[2]}
}
fn ss_relative(field u64)u64{return u64(i64(field)+i64(i32(read32(field))))}
fn ss_layout(table u64,protocol u64){
	descriptor:=read64(table)
	assert descriptor!=0&&ss_relative(descriptor)==protocol&&ss_relative(descriptor+4)==protocol
	assert ss_relative(descriptor+8)==table&&read32(descriptor+12)==0
	for i in 1..5{assert read64(table+u64(i*8))!=0}
}
fn ss_native_string(core voidptr,words SwiftStringWords,expected string){
	get:=unsafe{SsUtf8(C.dlsym(core,c'$sSS11utf8CStrings15ContiguousArrayVys4Int8VGvg'))}
	drop:=unsafe{SsDrop(C.dlsym(core,c'swift_bridgeObjectRelease'))}
	owner:=get(words.first,words.second)
	assert read64(owner+16)==u64(expected.len+1)&&C.memcmp(voidptr(owner+32),expected.str,usize(expected.len+1))==0,expected
	drop(owner);drop(words.second)
}
fn ss_native(probe SsProbe,guard u64){
	$if macos{
		core:=C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',C.RTLD_NOW);assert core!=unsafe{nil}
		table:=u64(C.dlsym(core,c'$ss5ErrorWS'));protocol:=u64(C.dlsym(core,c'$ss5ErrorMp'));assert table!=0&&protocol!=0
		assert read64(table)==u64(C.dlsym(core,c'$ss5ErrorMS'));ss_layout(table,protocol)
		lookup:=unsafe{SsLookup(C.dlsym(core,c'swift_getWitnessTable'))}
		mangled:=unsafe{SsMangled(C.dlsym(core,c'swift_getTypeByMangledNameInContext'))};name:='s5Error_p'
		metadata:=mangled(u64(name.str),u64(name.len),0,0);assert metadata!=0&&lookup(read64(table),metadata,guard)==table
		page:=usize(C.getpagesize());source:=guard-8
		for text in ['tiny','long Error existential domain é 🎮','a\x00b']!{for number in [i64(0),-17,9223372036854775807,-9223372036854775807-1]!{for with_info in [false,true]!{
			domain:=C.CFStringCreateWithBytes(unsafe{nil},text.str,i64(text.len),0x08000100,false)
			mut info:=unsafe{voidptr(nil)}
			if with_info{info=C.CFDictionaryCreateMutable(unsafe{nil},0,unsafe{&C.kCFTypeDictionaryKeyCallBacks},unsafe{&C.kCFTypeDictionaryValueCallBacks});C.CFDictionarySetValue(info,domain,domain)}
			owner:=C.CFErrorCreate(unsafe{nil},domain,number,info);assert owner!=unsafe{nil};if info!=unsafe{nil}{C.CFRelease(info)}
			unsafe{*(&u64(source))=u64(owner)};assert C.mprotect(voidptr(guard-u64(page)),page,C.PROT_READ)==0
			before:=C.CFGetRetainCount(owner)
			result:=ss_call(probe,read64(table+8)&0x0000ffffffffffff,source,guard)
			assert i64(ss_call(probe,read64(table+16)&0x0000ffffffffffff,source,guard).first)==number
			user_info:=ss_call(probe,read64(table+24)&0x0000ffffffffffff,source,guard).first;assert user_info!=0
			embedded:=ss_call(probe,read64(table+32)&0x0000ffffffffffff,source,guard).first
			assert embedded==u64(owner)&&read64(source)==u64(owner)&&C.CFGetRetainCount(owner)==before+1
			C.CFRelease(voidptr(embedded));assert C.CFGetRetainCount(owner)==before;C.CFRelease(owner)
			ss_native_string(core,result,text)
			assert C.CFDictionaryGetCount(voidptr(user_info))==if with_info{i64(1)}else{i64(0)}
			if with_info{assert C.CFDictionaryGetValue(voidptr(user_info),domain)==domain}
			C.CFRelease(voidptr(user_info));C.CFRelease(domain)
			assert C.mprotect(voidptr(guard-u64(page)),page,C.PROT_READ|C.PROT_WRITE)==0
		}}}
		println('NATIVE-ERROR-SELF: self-conformance descriptor and four opening witnesses, ignored protected metadata/table/x8, exact readonly Error reference, signed code extrema, Unicode/NUL domains, concrete empty/nonempty userInfo and embedded ownership, results survive Error destruction, preserved x20/x21/x22')
	}
}
fn ss_resolver()u64{return runtime_symbol('/usr/lib/swift/libswiftCore.dylib',ss_symbol)or{panic(err)}}
fn ss_control()SwiftStringWords{return SwiftStringWords{0xfeed1234,0x5678cafe}}
fn ss_text(words SwiftStringWords,expected string){
	mut scratch:=[u64(0),0]!
	bytes:=swift_string_bytes(words,u64(unsafe{&scratch[0]}))or{panic(err)}
	assert bytes.count==u64(expected.len)&&C.memcmp(voidptr(bytes.address),expected.str,usize(expected.len))==0
	swift_bridge_release(words.second)
}
fn ss_cases(probe SsProbe,table u64,guard u64){
	page:=usize(C.getpagesize());source:=guard-8
	for text in ['tiny','long Error existential domain é 🎮','a\x00b']!{for number in [i64(0),-17,9223372036854775807,-9223372036854775807-1]!{for with_info in [false,true]!{
		domain:=owned_string(text);mut info:=u64(0)
		if with_info{info=cf_dictionary_mutable(0,0,cf_callbacks_constant('_kCFTypeDictionaryKeyCallBacks'),cf_callbacks_constant('_kCFTypeDictionaryValueCallBacks'));cf_dictionary_set(info,domain,domain);objc_set_class(info,ios_runtime.names['NSDictionary'])}
		owner:=objc_allocate(cf_error_type_id());mut header:=obj_header(owner);header.fields[0]=domain;header.fields[1]=info;header.number=number
		before:=header.refs;unsafe{*(&u64(source))=owner};assert C.mprotect(voidptr(guard-u64(page)),page,C.PROT_READ)==0
		result:=ss_call(probe,read64(table+8),source,guard)
		assert i64(ss_call(probe,read64(table+16),source,guard).first)==number
		user_info:=ss_call(probe,read64(table+24),source,guard).first;assert user_info!=0
		embedded:=ss_call(probe,read64(table+32),source,guard).first
		assert embedded==owner&&read64(source)==owner&&header.refs==before+1;objc_release(embedded);assert header.refs==before;objc_release(owner)
		ss_text(result,text)
		assert objc_is_kind(user_info,ios_runtime.names['NSDictionary'])&&obj_header(user_info).keys.len==if with_info{1}else{0}
		if with_info{assert cf_dictionary_value(user_info,domain)==domain}
		objc_release(user_info);assert C.mprotect(voidptr(guard-u64(page)),page,C.PROT_READ|C.PROT_WRITE)==0
	}}}
}
fn ss_worker(probe SsProbe,table u64,source u64,guard u64){
	for _ in 0..256{
		assert ss_resolver()==table
		assert i64(ss_call(probe,read64(table+16),source,guard).first)==-17
		info:=ss_call(probe,read64(table+24),source,guard).first;assert obj_header(info).keys.len==0;objc_release(info)
	}
}
fn test_swift_error_self(){
	$if !arm64{return}
	page:=usize(C.getpagesize());code:=u64(C.mmap(unsafe{nil},page*3,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert code!=~u64(0)
	defer{assert C.munmap(voidptr(code),page*3)==0}
	guard:=code+u64(page*2);source:=guard-8;ss_emit(code);C.__builtin___clear_cache(voidptr(code),voidptr(code+76))
	assert C.mprotect(voidptr(code),page,C.PROT_READ|C.PROT_EXEC)==0&&C.mprotect(voidptr(guard),page,C.PROT_NONE)==0
	probe:=unsafe{SsProbe(voidptr(code))};assert ss_call(probe,u64(unsafe{voidptr(ss_control)}),guard,guard)==SwiftStringWords{0xfeed1234,0x5678cafe}
	ss_native(probe,guard)
	for _ in 0..2{
		objc_start();mut publishers:=[]thread u64{};for _ in 0..8{publishers<<spawn ss_resolver()};tables:=publishers.wait()
		for table in tables{assert table!=0&&table==tables[0]};table:=tables[0];arena:=ios_runtime.swift_error_arena
		assert table==arena+u64(page)+768;ss_layout(table,arena+u64(page)+240)
		assert swift_witness_table(read64(table),guard,guard)==table
		$if macos{core:=C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',C.RTLD_NOW);lookup:=unsafe{SsLookup(C.dlsym(core,c'swift_getWitnessTable'))};assert lookup(read64(table),guard,guard)==table}
		ss_cases(probe,table,guard)
		domain:=owned_string('threaded Error self-conformance');owner:=objc_allocate(cf_error_type_id());mut header:=obj_header(owner);header.fields[0]=domain;header.number=-17
		unsafe{*(&u64(source))=owner};assert C.mprotect(voidptr(guard-u64(page)),page,C.PROT_READ)==0
		mut workers:=[]thread{};for _ in 0..8{workers<<spawn ss_worker(probe,table,source,guard)};workers.wait();assert header.refs==1
		mut scratch:=u64(0);mut output:=SwiftErrorValue{}
		for bad in [u64(0),1,guard,~u64(0)]!{if _:=swift_error_self_value_checked(bad,unsafe{&scratch},unsafe{&output}){assert false}}
		assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib',ss_symbol+'Extra')==none&&runtime_symbol('/usr/lib/libSystem.B.dylib',ss_symbol)==none
		ios_runtime.swift_concurrency_retired=true
		if _:=swift_error_self_value_checked(owner,unsafe{&scratch},unsafe{&output}){assert false};assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib',ss_symbol)==none
		ios_runtime.swift_concurrency_retired=false;objc_release(owner);assert C.mprotect(voidptr(guard-u64(page)),page,C.PROT_READ|C.PROT_WRITE)==0
		assert ios_runtime.objects.len==0&&ios_runtime.live==0&&ios_runtime.swift_strings.len==0&&ios_runtime.swift_heap.len==0&&ios_runtime.swift_buffers.len==0
		objc_stop();assert ios_runtime.swift_error_arena==0
		if _:=swift_error_self_value_checked(guard,unsafe{&scratch},unsafe{&output}){assert false}
		for offset in [usize(0),page]!{
			$if macos{assert C.mprotect(voidptr(arena+u64(offset)),page,C.PROT_READ)==-1}
			$else{mut resident:=u8(0);assert C.mincore(voidptr(arena+u64(offset)),page,unsafe{&resident})==-1}
		}
	}
	println('IOS-ERROR-SELF: readonly descriptor/table with four opening witnesses, exact Error reference and protected unused inputs, native signed/Unicode/NUL and ownership comparisons, results survive Error destruction, preserved contexts, native witness lookup, invalid/retired rejection, eight cold publishers/workers and two drained/unmapped lifetimes')
}
